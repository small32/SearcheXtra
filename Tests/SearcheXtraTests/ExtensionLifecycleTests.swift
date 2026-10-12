import AppKit
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
}
