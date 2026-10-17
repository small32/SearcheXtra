import Foundation
import AppKit
import JavaScriptCore
import WebKit
import XCTest
@testable import SearcheXtra

@available(macOS 15.4, *)
@MainActor
final class ExtensionScriptingTests: XCTestCase {
    func testUserScriptDeclarationIncludesOptionalPermission() {
        XCTAssertTrue(Extensions.declaresUserScripts(["permissions": ["userScripts"]]))
        XCTAssertTrue(Extensions.declaresUserScripts(["optional_permissions": ["userScripts"]]))
        XCTAssertFalse(Extensions.declaresUserScripts(["permissions": ["scripting"]]))
        XCTAssertFalse(Extensions.declaresUserScripts([:]))
    }

    func testOptionalUserScriptsReceivesTheScriptingBridge() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("optional-us-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Optional userscripts", "version": "1.0",
                                       "optional_permissions": ["userScripts"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        try ExtensionShims.prepare(folder, fresh: true)
        let updated = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) as? [String: Any])
        XCTAssertTrue((updated["permissions"] as? [String] ?? []).contains("scripting"))
        XCTAssertFalse((updated["permissions"] as? [String] ?? []).contains("userScripts"))
        XCTAssertEqual(updated["optional_permissions"] as? [String], ["userScripts"])
    }

    func testForwardedFunctionKeepsArgumentsAndResult() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("script-ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let path = try ExtensionShims.scriptingFile("(value, amount) => value + amount", arguments: ["clip", 2], in: folder)
        let source = try String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8)
        let context = try XCTUnwrap(JSContext())
        XCTAssertEqual(context.evaluateScript(source)?.toString(), "clip2")
        XCTAssertEqual(try ExtensionShims.scriptingFile("(value, amount) => value + amount", arguments: ["clip", 2], in: folder), path)
        // Past a megabyte of source, refused (Security).
        XCTAssertThrowsError(try ExtensionShims.scriptingFile("() => '" + String(repeating: "x", count: 1_000_001) + "'", arguments: [], in: folder))
    }

    func testSupportedUserWorldCSPIsExplicitAndRestrictivePoliciesAreRefused() throws {
        XCTAssertNoThrow(try ExtensionUserScripts.validateWorld([:]))
        XCTAssertNoThrow(try ExtensionUserScripts.validateWorld(["messaging": true, "csp": "script-src 'self' 'unsafe-eval';"]))
        XCTAssertNoThrow(try ExtensionUserScripts.validateWorld(["csp": "script-src * 'unsafe-inline' 'self' 'unsafe-eval'"]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateWorld(["csp": "script-src 'self'"]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateWorld(["csp": "script-src 'unsafe-eval'; connect-src 'none'"]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateWorld(["csp": 12]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateWorld(["messaging": NSNumber(value: 1)]))
    }

    func testUserScriptFileCannotReadOutsideItsExtension() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("user-world-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "globalThis.testSource = 1;".write(to: folder.appendingPathComponent("script.js"), atomically: true, encoding: .utf8)
        let script: [String: Any] = ["matches": ["https://example.com/*"], "js": [["file": "script.js"]]]
        XCTAssertNoThrow(try ExtensionUserScripts.validate(script, folder: folder))
        XCTAssertThrowsError(try ExtensionUserScripts.validate(script.merging(["js": [["file": "../outside.js"]]]) { _, new in new }, folder: folder))
        XCTAssertThrowsError(try ExtensionUserScripts.validate(script.merging(["world": "MAIN", "worldId": "named"]) { _, new in new }, folder: folder))
        XCTAssertThrowsError(try ExtensionUserScripts.validate(script.merging(["world": "MAIN", "worldId": ""]) { _, new in new }, folder: folder))
        XCTAssertNoThrow(try ExtensionUserScripts.validate(script.merging(["world": "MAIN"]) { _, new in new }, folder: folder))
        XCTAssertNoThrow(try ExtensionUserScripts.validate(script.merging(["worldId": String(repeating: "界", count: 85)]) { _, new in new }, folder: folder))
        XCTAssertThrowsError(try ExtensionUserScripts.validate(script.merging(["worldId": String(repeating: "界", count: 86)]) { _, new in new }, folder: folder))
        XCTAssertThrowsError(try ExtensionUserScripts.validate(script.merging(["js": [["code": "void 0", "file": "script.js"]]]) { _, new in new }, folder: folder))
    }

    func testExecuteTargetChoicesAndUTF8WorldIdentifiers() throws {
        let document = UUID().uuidString
        XCTAssertNoThrow(try ExtensionUserScripts.validateTarget(["tabId": 1]))
        XCTAssertNoThrow(try ExtensionUserScripts.validateTarget(["tabId": 1, "allFrames": true]))
        XCTAssertNoThrow(try ExtensionUserScripts.validateTarget(["tabId": 1, "allFrames": false, "frameIds": [0, 7]]))
        XCTAssertNoThrow(try ExtensionUserScripts.validateTarget(["tabId": 1, "documentIds": [document]]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateTarget(["frameIds": [0]]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateTarget(["tabId": true]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateTarget(["tabId": 1.5]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateTarget(["tabId": 1, "allFrames": NSNumber(value: 1)]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateTarget(["tabId": 1, "frameIds": [true]]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateTarget(["tabId": 1, "allFrames": true, "frameIds": [7]]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateTarget(["tabId": 1, "frameIds": [7], "documentIds": [document]]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateTarget(["tabId": 1, "frameIds": []]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateTarget(["tabId": 1, "frameIds": [-1]]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateTarget(["tabId": 1, "documentIds": ["old-or-invalid-document"]]))
        XCTAssertNoThrow(try ExtensionUserScripts.validateWorld(["worldId": String(repeating: "界", count: 85)]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateWorld(["worldId": String(repeating: "界", count: 86)]))
        XCTAssertThrowsError(try ExtensionUserScripts.validateWorld(["worldId": "_reserved"]))
    }

    func testFrameDiscoveryKeepsDuplicateURLIframesSeparateWithoutRegisteredScripts() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let captured = UserFrameFixtureReply()
        configuration.userContentController.addScriptMessageHandler(captured, contentWorld: Web.world, name: "frameFixture")
        configuration.userContentController.addUserScript(WKUserScript(source: ExtensionUserScripts.discovery(channel: "frameFixture"),
                                                                      injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Web.world))
        let web = WKWebView(frame: .zero, configuration: configuration)
        let loaded = expectation(description: "Two same-address frames loaded")
        let navigation = UserWorldFixtureNavigation(loaded)
        web.navigationDelegate = navigation
        defer {
            web.stopLoading(); web.navigationDelegate = nil
            configuration.userContentController.removeScriptMessageHandler(forName: "frameFixture", contentWorld: Web.world)
        }
        web.loadHTMLString("<!doctype html><body><iframe srcdoc='<p>first</p>'></iframe><iframe srcdoc='<p>second</p>'></iframe></body>", baseURL: URL(string: "https://frames.example/"))
        await fulfillment(of: [loaded], timeout: 8)
        let children = captured.frames.filter { !$0.value.isMainFrame }
        XCTAssertEqual(children.count, 2)
        var labels = Set<String>()
        for (document, frame) in children {
            let identity = try await web.evaluateJavaScript("globalThis.__searchFrameDocument", in: frame, contentWorld: Web.world)
            XCTAssertEqual(identity as? String, document)
            let label = try await web.evaluateJavaScript("document.body.textContent.trim()", in: frame, contentWorld: .page)
            labels.insert(try XCTUnwrap(label as? String))
        }
        XCTAssertEqual(labels, ["first", "second"])
    }

    func testNativeUserWorldSupportsDynamicFunctionsWithoutExtensionPrivileges() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let world = WKContentWorld.world(name: "user-script-fixture-\(UUID().uuidString)")
        let reply = UserWorldFixtureReply()
        let controller = configuration.userContentController
        controller.addScriptMessageHandler(reply, contentWorld: world, name: "fixture")
        controller.addUserScript(WKUserScript(source: ExtensionUserScripts.bootstrap(id: "fixtureExtension", channel: "fixture", messaging: true),
                                               injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world))
        controller.addUserScript(WKUserScript(source: "globalThis.userOnly = 12;", injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world))
        let web = WKWebView(frame: .zero, configuration: configuration)
        let loaded = expectation(description: "Strict CSP page loaded")
        let navigation = UserWorldFixtureNavigation(loaded)
        web.navigationDelegate = navigation
        defer {
            web.stopLoading()
            web.navigationDelegate = nil
            controller.removeScriptMessageHandler(forName: "fixture", contentWorld: world)
        }
        web.loadHTMLString("<!doctype html><meta http-equiv='Content-Security-Policy' content=\"script-src 'none'\"><p>Strict CSP fixture</p>",
                           baseURL: URL(string: "https://user-world.example/"))
        await fulfillment(of: [loaded], timeout: 8)
        let id = try await web.evaluateJavaScript("new Function('return globalThis.chrome.runtime.id')()", in: nil, contentWorld: world)
        XCTAssertEqual(id as? String, "fixtureExtension")
        let privileges = try await web.evaluateJavaScript("JSON.stringify([typeof chrome.storage, typeof chrome.tabs, typeof chrome.runtime.sendNativeMessage])", in: nil, contentWorld: world)
        XCTAssertEqual(privileges as? String, "[\"undefined\",\"undefined\",\"undefined\"]")
        let page = try await web.evaluateJavaScript("typeof userOnly", in: nil, contentWorld: .page)
        XCTAssertEqual(page as? String, "undefined")
        let content = try await web.evaluateJavaScript("typeof userOnly", in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(content as? String, "undefined")
        let response = try await web.callAsyncJavaScript("return await new Function('return chrome.runtime.sendMessage({ probe: true })')();", in: nil, contentWorld: world)
        XCTAssertEqual((response as? [String: Any])?["probe"] as? Bool, true)
    }
}

@MainActor private final class UserWorldFixtureNavigation: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation
    init(_ loaded: XCTestExpectation) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
}

@MainActor private final class UserWorldFixtureReply: NSObject, WKScriptMessageHandlerWithReply {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let body = message.body as? [String: Any] ?? [:]
        replyHandler(["value": body["message"] ?? NSNull()], nil)
    }
}

@MainActor private final class UserFrameFixtureReply: NSObject, WKScriptMessageHandlerWithReply {
    var frames: [String: WKFrameInfo] = [:]
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let body = message.body as? [String: Any] ?? [:]
        if let document = body["documentId"] as? String {
            if body["phase"] as? String == "hello" { frames[document] = message.frameInfo }
            else { frames[document] = nil }
        }
        replyHandler(true, nil)
    }
}
