import AppKit
import WebKit
import XCTest
@testable import SearcheXtra

@available(macOS 15.4, *)
@MainActor
final class ExtensionLifecycleTests: XCTestCase {
    private var folder: URL!
    private var id: String!

    override func setUp() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("extension-lifecycle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Lifecycle Fixture", "version": "1.0"]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        try "<!doctype html><title>Fixture</title>".write(to: folder.appendingPathComponent("page.html"), atomically: true, encoding: .utf8)
        id = Crx.unpackedID(for: folder)
    }

    override func tearDown() async throws {
        if let id { Extensions.shared.remove(id) }
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    private func waitUntilAdmitted() async throws {
        let deadline = Date().addingTimeInterval(5)
        while !Extensions.shared.installed.contains(where: { $0.id == id }) {
            guard Date() < deadline else { throw NSError(domain: "ExtensionLifecycleTests", code: 1) }
            await Task.yield()
        }
    }

    func testRemovalWhileFolderInstallIsQueuedCannotReinstallIt() async throws {
        let install = try XCTUnwrap(Extensions.shared.installFolder(at: folder, confirm: false))
        // Removal wins even before copying starts, or while it is suspended.
        Extensions.shared.remove(id)
        await install.value
        XCTAssertFalse(Extensions.shared.installed.contains { $0.id == id })
        XCTAssertNil(Extensions.shared.contexts[id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: Extensions.folder(for: id).path))
    }

    func testOnlyOneFolderInstallForAnIDCanPrepareAtATime() async throws {
        let install = try XCTUnwrap(Extensions.shared.installFolder(at: folder, confirm: false))
        XCTAssertNil(Extensions.shared.installFolder(at: folder, confirm: false))
        await install.value
        XCTAssertEqual(Extensions.shared.installed.filter { $0.id == id }.count, 1)
    }

    func testDisableDuringInitialLoadStaysDisabled() async throws {
        let install = try XCTUnwrap(Extensions.shared.installFolder(at: folder, confirm: false))
        await Task.yield()
        try await waitUntilAdmitted()
        Extensions.shared.setEnabled(id, false)
        await install.value
        XCTAssertEqual(Extensions.shared.installed.first { $0.id == id }?.enabled, false)
        XCTAssertNil(Extensions.shared.contexts[id])
    }

    func testRemovalBeforeQueuedEnableCannotReloadOrUseAStaleIndex() async throws {
        let install = try XCTUnwrap(Extensions.shared.installFolder(at: folder, confirm: false))
        await install.value
        let previousPrivate = Shared.prefs.extensionsInPrivate
        defer { Shared.prefs.extensionsInPrivate = previousPrivate }
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { for tab in browser.tabs { tab.close() } }
        Shared.prefs.extensionsInPrivate = true
        XCTAssertEqual(Extensions.shared.contexts[id]?.hasAccessToPrivateData, true)
        browser.newShyTab()
        let source = browser.active!
        let context = try XCTUnwrap(Extensions.shared.contexts[id])
        let opened = browser.openBookmarks([context.baseURL.appendingPathComponent("page.html")], from: source)
        XCTAssertEqual(opened.first?.shy, true)
        XCTAssertTrue(opened.first?.store === source.store)
        XCTAssertFalse(opened.first!.store.isPersistent)
        Shared.prefs.extensionsInPrivate = false
        XCTAssertEqual(context.hasAccessToPrivateData, false)
        XCTAssertTrue(opened.first!.isBlank)
        Extensions.shared.setEnabled(id, false)
        let enable = try XCTUnwrap(Extensions.shared.setEnabled(id, true))
        Extensions.shared.remove(id)
        let loaded = await enable.value
        XCTAssertFalse(loaded)
        XCTAssertFalse(Extensions.shared.installed.contains { $0.id == id })
        XCTAssertNil(Extensions.shared.contexts[id])
    }

    func testUserScriptSwitchIsOptInReloadsAndPreservesSavedScripts() async throws {
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Userscript Fixture", "version": "1.0",
                                       "permissions": ["userScripts", "scripting"], "host_permissions": ["<all_urls>"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let install = try XCTUnwrap(Extensions.shared.installFolder(at: folder, confirm: false))
        await install.value
        XCTAssertTrue(Extensions.shared.supportsUserScripts(id))
        XCTAssertFalse(Extensions.userScriptsAllowed(id))
        let first = try XCTUnwrap(Extensions.shared.contexts[id])
        let denied = try await ExtensionShims.answer(["api": "userScripts.file", "args": [["id": "probe", "js": [["code": "void 0;"]]]]], from: first, owner: .shared) as? [String: Any]
        XCTAssertEqual(denied?["error"] as? String, L10n.text("extensions.userScripts.disabled"))

        let saved = Extensions.folder(for: id).appendingPathComponent("_search/userscripts.json")
        try FileManager.default.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
        let retained: [String: Any] = ["id": "retained", "matches": ["https://not-found.scriptcat.org/*"],
                                       "js": [["code": "void 0;"]], "world": "USER_SCRIPT"]
        let scripts = try JSONSerialization.data(withJSONObject: [retained])
        try scripts.write(to: saved)
        let enable = try XCTUnwrap(Extensions.shared.setUserScriptsAllowed(id, true))
        let enabled = await enable.value
        XCTAssertTrue(enabled)
        XCTAssertTrue(Extensions.userScriptsAllowed(id))
        let second = try XCTUnwrap(Extensions.shared.contexts[id])
        XCTAssertFalse(first === second)
        let disable = try XCTUnwrap(Extensions.shared.setUserScriptsAllowed(id, false))
        let disabled = await disable.value
        XCTAssertTrue(disabled)
        XCTAssertFalse(Extensions.userScriptsAllowed(id))
        XCTAssertEqual(try Data(contentsOf: saved), scripts)
        let enabledAgain = try XCTUnwrap(Extensions.shared.setUserScriptsAllowed(id, true))
        let restored = await enabledAgain.value
        XCTAssertTrue(restored)
        XCTAssertEqual(try Data(contentsOf: saved), scripts)
        Extensions.shared.remove(id)
        XCTAssertNil(Store.settings.object(forKey: "extensions.userscripts.\(id!)"))
    }

    func testUserScriptWorldAndRegistrationSurviveReloadWithoutLeakingRejectedChanges() async throws {
        let manifest: [String: Any] = ["manifest_version": 3, "name": "User world fixture", "version": "1.0",
                                       "permissions": ["userScripts"], "host_permissions": ["https://example.com/*"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let install = try XCTUnwrap(Extensions.shared.installFolder(at: folder, confirm: false))
        await install.value
        let enable = try XCTUnwrap(Extensions.shared.setUserScriptsAllowed(id, true))
        let enabled = await enable.value
        XCTAssertTrue(enabled)
        let context = try XCTUnwrap(Extensions.shared.contexts[id])
        let world: [String: Any] = ["worldId": "scriptcat", "messaging": true, "csp": "script-src 'self' 'unsafe-inline' 'unsafe-eval' *"]
        _ = try await ExtensionUserScripts.call("userScripts.world", args: [world], context: context)
        let script: [String: Any] = ["id": "fixture", "matches": ["https://example.com/*"], "world": "USER_SCRIPT", "worldId": "scriptcat",
                                    "runAt": "document_start", "allFrames": true, "js": [["code": "globalThis.fixture = new Function('return chrome.runtime.id')();"]]]
        _ = try await ExtensionUserScripts.call("userScripts.register", args: [[script]], context: context)
        do {
            _ = try await ExtensionUserScripts.call("userScripts.register", args: [[script]], context: context)
            XCTFail("Duplicate registration must fail")
        } catch {}
        do {
            _ = try await ExtensionUserScripts.call("userScripts.world", args: [["worldId": "scriptcat", "csp": "script-src 'none'"]], context: context)
            XCTFail("An unsupported policy must fail before changing saved settings")
        } catch {}
        let before = try await ExtensionUserScripts.call("userScripts.worlds", args: [], context: context) as? [[String: Any]]
        XCTAssertEqual(before?.first?["csp"] as? String, world["csp"] as? String)
        Extensions.shared.setEnabled(id, false)
        let reload = try XCTUnwrap(Extensions.shared.setEnabled(id, true))
        let loaded = await reload.value
        XCTAssertTrue(loaded)
        let restored = try XCTUnwrap(Extensions.shared.contexts[id])
        let scripts = try await ExtensionUserScripts.call("userScripts.list", args: [], context: restored) as? [[String: Any]]
        XCTAssertEqual(scripts?.count, 1)
        XCTAssertEqual(scripts?.first?["worldId"] as? String, "scriptcat")
        let worlds = try await ExtensionUserScripts.call("userScripts.worlds", args: [], context: restored) as? [[String: Any]]
        XCTAssertEqual(worlds?.first?["messaging"] as? Bool, true)
        _ = try await ExtensionUserScripts.call("userScripts.unregister", args: [["ids": ["fixture"]]], context: restored)
        let remaining = try await ExtensionUserScripts.call("userScripts.list", args: [], context: restored) as? [[String: Any]]
        XCTAssertEqual(remaining?.count, 0)
    }

    func testUserScriptFrameDiscoveryIsOnlyInstalledWhileAuthorized() async throws {
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Discovery fixture", "version": "1.0",
                                       "permissions": ["userScripts"], "host_permissions": ["https://example.com/*"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let install = try XCTUnwrap(Extensions.shared.installFolder(at: folder, confirm: false))
        await install.value
        let tab = Tab()
        defer { tab.close() }
        let controller = tab.web.configuration.userContentController
        func hasDiscovery() -> Bool { controller.userScripts.contains { $0.source.contains("__searchDiscoverFrame") } }
        XCTAssertFalse(hasDiscovery(), "Ordinary pages need no user-script frame transport before opt-in")
        let enable = try XCTUnwrap(Extensions.shared.setUserScriptsAllowed(id, true))
        let enabled = await enable.value
        XCTAssertTrue(enabled)
        XCTAssertTrue(hasDiscovery(), "An existing tab must acquire discovery when its extension is authorized")
        let disable = try XCTUnwrap(Extensions.shared.setUserScriptsAllowed(id, false))
        let disabled = await disable.value
        XCTAssertTrue(disabled)
        XCTAssertFalse(hasDiscovery(), "Revoking the last user-script extension must release discovery")
    }

    func testRuntimeReloadClearsUserScriptsAndWorldsWithoutRecopyingTheSource() async throws {
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Runtime reload fixture", "version": "1.0",
                                       "permissions": ["userScripts"], "host_permissions": ["https://example.com/*"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let install = try XCTUnwrap(Extensions.shared.installFolder(at: folder, confirm: false))
        await install.value
        let enable = try XCTUnwrap(Extensions.shared.setUserScriptsAllowed(id, true))
        let enabled = await enable.value
        XCTAssertTrue(enabled)
        let previous = try XCTUnwrap(Extensions.shared.contexts[id])
        let script: [String: Any] = ["id": "registered", "matches": ["https://example.com/*"], "js": [["code": "void 0;"]]]
        _ = try await ExtensionUserScripts.call("userScripts.register", args: [[script]], context: previous)
        _ = try await ExtensionUserScripts.call("userScripts.world", args: [["worldId": "registered-world", "messaging": true]], context: previous)
        let kept = Extensions.folder(for: id).appendingPathComponent("_search/retained.txt")
        try "installed-copy".write(to: kept, atomically: true, encoding: .utf8)
        let reload = try XCTUnwrap(Extensions.shared.reloadRuntime(previous))
        let reloaded = await reload.value
        XCTAssertTrue(reloaded)
        let current = try XCTUnwrap(Extensions.shared.contexts[id])
        XCTAssertFalse(current === previous)
        XCTAssertNil(Extensions.shared.reloadRuntime(previous), "A retired extension context cannot reload its replacement")
        let scripts = try await ExtensionUserScripts.call("userScripts.list", args: [], context: current) as? [[String: Any]]
        let worlds = try await ExtensionUserScripts.call("userScripts.worlds", args: [], context: current) as? [[String: Any]]
        XCTAssertEqual(scripts?.count, 0)
        XCTAssertEqual(worlds?.count, 0)
        XCTAssertEqual(try String(contentsOf: kept, encoding: .utf8), "installed-copy")
        XCTAssertTrue(Extensions.userScriptsAllowed(id))
    }
}
