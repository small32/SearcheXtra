import AppKit
import Foundation
import WebKit
import XCTest
@testable import SearcheXtra

/// Optional integration against the unmodified official MV3 package. The CI
/// supplies the pinned, hash-checked ZIP/folder; production install/prepare is
/// the only code allowed to change the package before WebKit loads it.
@available(macOS 15.4, *)
@MainActor
final class ExtensionScriptCatTests: XCTestCase {
    func testOriginalMV3RunsGMStorageXHRFramesAlongsideMV2() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        guard let input = ProcessInfo.processInfo.environment["SEARCHEXTRA_TEST_MV3_FOLDER"], !input.isEmpty else {
            throw XCTSkip("Set SEARCHEXTRA_TEST_MV3_FOLDER to the original ScriptCat 1.4.0 Chrome ZIP or folder")
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let files = FileManager.default
        let scratch = files.temporaryDirectory.appendingPathComponent("scriptcat-native-\(UUID().uuidString)", isDirectory: true)
        let package = scratch.appendingPathComponent("scriptcat", isDirectory: true)
        try files.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: scratch) }
        var directory: ObjCBool = false
        guard files.fileExists(atPath: input, isDirectory: &directory) else { throw FixtureFailure("ScriptCat fixture is missing") }
        if directory.boolValue { try files.copyItem(at: URL(fileURLWithPath: input), to: package) }
        else { try Crx.unpack(Data(contentsOf: URL(fileURLWithPath: input)), into: package) }
        let manifest = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: package.appendingPathComponent("manifest.json"))) as? [String: Any])
        XCTAssertEqual(manifest["manifest_version"] as? Int, 3)
        XCTAssertEqual(manifest["version"] as? String, "1.4.0")
        let identifier = Crx.unpackedID(for: package)
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        let previousFront = Front.shared.browser
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 900, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        browser.window = window
        Browsers.register(browser)
        Front.shared.set(browser)
        var installed = [identifier]
        defer {
            for id in installed { Extensions.shared.remove(id) }
            // Retire this fixture without adding a restorable user window.
            browser.extensionPopup = "scriptcat-native-fixture"
            Browsers.closing(window)
            browser.closeAll(); browser.dozing?.invalidate()
            window.contentView = nil; window.close()
            Front.shared.set(previousFront)
        }
        func show(_ tab: Tab) {
            browser.select(tab, floatPrevious: false)
            tab.web.frame = NSRect(x: 0, y: 0, width: 900, height: 650)
            window.contentView = tab.web
        }
        let pageServer = try LocalDownloadServer(size: 1024)
        let xhrServer = try LocalDownloadServer(size: 1024)
        defer { pageServer.stop(); xhrServer.stop() }
        let website = browser.open(pageServer.url("/page"), foreground: true)
        show(website)
        try await until("initial local website") { !website.web.isLoading && website.web.url == pageServer.url("/page") }
        do {
            let install = try XCTUnwrap(Extensions.shared.installFolder(at: package, confirm: false))
            await install.value
            let first = try XCTUnwrap(Extensions.shared.contexts[identifier])
            XCTAssertFalse(Extensions.userScriptsAllowed(identifier))
            let firstOptions = browser.open(try XCTUnwrap(first.optionsPageURL), foreground: true)
            show(firstOptions)
            try await until("ScriptCat options API") {
                (try? await self.evaluate(firstOptions.web, "return document.readyState === 'complete' && typeof chrome.userScripts?.getScripts === 'function';")) as? Bool == true
            }
            let denied = try await evaluate(firstOptions.web, "try { await chrome.userScripts.getScripts(); return false; } catch { return true; }")
            XCTAssertEqual(denied as? Bool, true)
            let enable = try XCTUnwrap(Extensions.shared.setUserScriptsAllowed(identifier, true))
            let enabled = await enable.value
            XCTAssertTrue(enabled)
            let context = try XCTUnwrap(Extensions.shared.contexts[identifier])
            browser.close(firstOptions)
            let options = browser.open(try XCTUnwrap(context.optionsPageURL), foreground: true)
            show(options)
            try await until("ScriptCat native user-world registration") {
                let scripts = try await ExtensionUserScripts.call("userScripts.list", args: [], context: context) as? [[String: Any]] ?? []
                return scripts.contains { $0["id"] as? String == "scriptcat-content" }
            }
            let userCode = #"""
            // ==UserScript==
            // @name SearcheXtra native MV3 regression
            // @namespace https://searchextra.test/
            // @version 1.0
            // @match http://127.0.0.1/*
            // @run-at document-end
            // @grant GM.getValue
            // @grant GM.setValue
            // @grant GM_xmlhttpRequest
            // @connect 127.0.0.1
            // ==/UserScript==
            (async () => {
              document.documentElement.setAttribute('data-sx-scriptcat-started', 'true');
              const count = Number(await GM.getValue('searchextra-native-test-count', 0)) + 1;
              await GM.setValue('searchextra-native-test-count', count);
              document.documentElement.setAttribute('data-sx-scriptcat-count', String(count));
              GM_xmlhttpRequest({ method: 'GET', url: XHR_URL,
                onload: response => document.documentElement.setAttribute('data-sx-scriptcat-xhr', response.status + ':' + response.responseText.includes('Local test page')),
                onerror: error => document.documentElement.setAttribute('data-sx-scriptcat-error', 'xhr:' + String(error.error || error)) });
            })().catch(error => document.documentElement.setAttribute('data-sx-scriptcat-error', String(error)));
            """#.replacingOccurrences(of: "XHR_URL", with: quoted(xhrServer.url("/page").absoluteString))
            let response = try await evaluate(options.web, #"""
            const now = Date.now(), uuid = crypto.randomUUID();
            const script = { uuid, name: 'SearcheXtra native MV3 regression', namespace: 'https://searchextra.test/', origin: '', originDomain: '',
              checkUpdateUrl: '', downloadUrl: '', metadata: { name: ['SearcheXtra native MV3 regression'], namespace: ['https://searchextra.test/'],
                version: ['1.0'], match: ['http://127.0.0.1/*'], 'run-at': ['document-end'], grant: ['GM.getValue', 'GM.setValue', 'GM_xmlhttpRequest'], connect: ['127.0.0.1'] },
              selfMetadata: {}, sort: -1, type: 1, status: 1, runStatus: 'complete', createtime: now, updatetime: now, checktime: now };
            const result = await chrome.runtime.sendMessage({ action: 'serviceWorker/script/install', data: { script, code, upsertBy: 'user' } });
            if (!result || result.code) throw new Error(JSON.stringify(result));
            return { uuid, result };
            """#, arguments: ["code": userCode]) as? [String: Any]
            let scriptID = try XCTUnwrap(response?["uuid"] as? String)
            try await until("real installed user-script registration") {
                let scripts = try await ExtensionUserScripts.call("userScripts.list", args: [], context: context) as? [[String: Any]] ?? []
                return scripts.contains { $0["id"] as? String == scriptID }
            }
            show(website)
            try await reload(website.web)
            func state() async throws -> [String: Any] {
                try await self.evaluate(website.web, "return { started: document.documentElement.getAttribute('data-sx-scriptcat-started'), count: document.documentElement.getAttribute('data-sx-scriptcat-count'), xhr: document.documentElement.getAttribute('data-sx-scriptcat-xhr'), error: document.documentElement.getAttribute('data-sx-scriptcat-error') };") as? [String: Any] ?? [:]
            }
            try await until("real GM storage and cross-origin GM_xmlhttpRequest") {
                let value = try await state()
                if let error = value["error"] as? String { throw FixtureFailure("User script: " + error) }
                return value["count"] as? String != nil && value["xhr"] as? String == "200:true"
            }
            let firstState = try await state()
            let firstCount = Int(try XCTUnwrap(firstState["count"] as? String)) ?? 0
            XCTAssertGreaterThan(firstCount, 0)
            XCTAssertGreaterThan(xhrServer.count("/page"), 0)
            try await reload(website.web)
            try await until("GM value persists across navigation") {
                let current = try await state()
                return (Int(current["count"] as? String ?? "0") ?? 0) > firstCount
            }
            _ = try await evaluate(website.web, "const frame = document.createElement('iframe'); frame.id = 'scriptcat-native-child'; frame.src = location.href; document.body.appendChild(frame); return true;")
            try await until("real ScriptCat GM storage in a matching iframe") {
                try await self.evaluate(website.web, "return Boolean(document.querySelector('#scriptcat-native-child')?.contentDocument?.documentElement?.getAttribute('data-sx-scriptcat-count'));") as? Bool == true
            }
            let mv2 = scratch.appendingPathComponent("mv2", isDirectory: true)
            try files.createDirectory(at: mv2, withIntermediateDirectories: true)
            try #"{"manifest_version":2,"name":"SearcheXtra native MV2 fixture","version":"1.0","content_scripts":[{"matches":["http://127.0.0.1/*"],"js":["content.js"],"run_at":"document_end"}]}"#.write(to: mv2.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try "document.documentElement.setAttribute('data-sx-mv2','native');".write(to: mv2.appendingPathComponent("content.js"), atomically: true, encoding: .utf8)
            installed.append(Crx.unpackedID(for: mv2))
            let mv2Install = try XCTUnwrap(Extensions.shared.installFolder(at: mv2, confirm: false))
            await mv2Install.value
            show(website)
            try await reload(website.web)
            try await until("MV2 and real ScriptCat MV3 run together") {
                try await self.evaluate(website.web, "return document.documentElement.getAttribute('data-sx-mv2') === 'native' && document.documentElement.getAttribute('data-sx-scriptcat-started') === 'true';") as? Bool == true
            }
            let disable = try XCTUnwrap(Extensions.shared.setUserScriptsAllowed(identifier, false))
            let disabled = await disable.value
            XCTAssertTrue(disabled)
            try await reload(website.web)
            let revoked = try await evaluate(website.web, "return document.documentElement.getAttribute('data-sx-scriptcat-started') === null && document.documentElement.getAttribute('data-sx-mv2') === 'native';")
            XCTAssertEqual(revoked as? Bool, true)
            print("PASS: original ScriptCat MV3 1.4.0: installation, opt-in, real GM storage, cross-origin XHR, reload, iframe, MV2 coexistence and revocation")
        } catch {
            print("ScriptCat native errors: \(Extensions.shared.errors[identifier] ?? [])")
            throw error
        }
    }

    private func until(_ label: String, _ predicate: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(60)
        var last = ""
        repeat {
            do { if try await predicate() { return } } catch { last = error.localizedDescription }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while Date() < deadline
        throw FixtureFailure("Timed out: \(label). \(last)")
    }

    private func evaluate(_ web: WKWebView, _ body: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await web.callAsyncJavaScript("return await Promise.race([(async () => {\n" + body + "\n})(), new Promise((_, reject) => setTimeout(() => reject(new Error('ScriptCat fixture JavaScript timed out')), 15000))]);",
                                         arguments: arguments, in: nil, contentWorld: .page)
    }

    private func reload(_ web: WKWebView) async throws {
        let marker = UUID().uuidString
        _ = try await evaluate(web, "document.documentElement.setAttribute('data-sx-before-reload', marker); return true;", arguments: ["marker": marker])
        web.reload()
        try await until("a new document completes navigation") {
            guard !web.isLoading else { return false }
            return (try await self.evaluate(web, "return document.readyState === 'complete' && document.documentElement.getAttribute('data-sx-before-reload') !== marker;", arguments: ["marker": marker])) as? Bool == true
        }
    }

    private func quoted(_ string: String) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed]), encoding: .utf8)!
    }

    private struct FixtureFailure: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }
}
