import AppKit
import Darwin
import WebKit
import XCTest
@testable import SearcheXtra

@available(macOS 15.4, *)
@MainActor
final class ExtensionBoundaryTests: XCTestCase {
    private var folders: [URL] = []

    override class func setUp() {
        setenv("SEARCH_PROBE", "extension-boundaries-\(getpid())", 1)
        super.setUp()
    }

    override func tearDown() async throws {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        folders.removeAll()
    }

    private func context(permissions: [String] = [], popup: String? = nil) async throws -> WKWebExtensionContext {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("extension-boundaries-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folders.append(folder)
        var manifest: [String: Any] = ["manifest_version": 3, "name": "Boundary fixture", "version": "1",
                                       "permissions": permissions]
        if let popup {
            manifest["action"] = ["default_popup": popup]
            try Data("<!doctype html><title>Popup</title>".utf8).write(to: folder.appendingPathComponent("popup.html"))
        }
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: folder))
        context.baseURL = URL(string: "\(Extensions.scheme)://\(UUID().uuidString.lowercased())/")!
        return context
    }

    private func answer(_ api: String, _ args: [Any] = [], context: WKWebExtensionContext) async throws -> [String: Any] {
        let reply = try await ExtensionShims.answer(["api": api, "args": args], from: context, owner: Extensions.shared)
        return try XCTUnwrap(reply as? [String: Any])
    }

    func testTabGroupingCannotBypassTheNativePermissionGate() async throws {
        guard Store.testing else { throw XCTSkip("Use SEARCH_PROBE for browser tests") }
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        Browsers.register(browser)
        defer { Browsers.discard(browser) }
        let tab = try XCTUnwrap(browser.active)
        let context = try await context(permissions: ["tabs"])
        let key = "extensions.granted.\(context.uniqueIdentifier)"
        let previous = Store.settings.object(forKey: key)
        defer {
            if let previous { Store.settings.set(previous, forKey: key) }
            else { Store.settings.removeObject(forKey: key) }
        }
        Store.settings.removeObject(forKey: key)

        for api in ["tabs.group", "tabs.groups", "tabs.ungroup"] {
            let reply = try await answer(api, [[0], -1], context: context)
            XCTAssertTrue((reply["error"] as? String)?.contains("tabGroups") == true, "\(api): \(reply)")
            XCTAssertNil(browser.group(of: tab))
        }

        // Exercise the same native entry point after an optional grant,
        // including mutation: this is not merely a permission-table check.
        Store.settings.set(["tabGroups"], forKey: key)
        let grouped = try await answer("tabs.group", [[0], -1], context: context)
        XCTAssertNil(grouped["error"], "\(grouped)")
        let group = try XCTUnwrap(browser.group(of: tab))
        XCTAssertEqual(grouped["value"] as? Int, TabGroup.number(group))
        let described = try await answer("tabs.groups", [[0]], context: context)
        XCTAssertEqual(described["value"] as? [Int], [TabGroup.number(group)])
        Store.settings.removeObject(forKey: key)
        let refused = try await answer("tabs.ungroup", [[0]], context: context)
        XCTAssertNotNil(refused["error"])
        XCTAssertEqual(browser.group(of: tab), group)
        Store.settings.set(["tabGroups"], forKey: key)
        let ungrouped = try await answer("tabs.ungroup", [[0]], context: context)
        XCTAssertNil(ungrouped["error"], "\(ungrouped)")
        XCTAssertNil(browser.group(of: tab))
    }

    func testSystemInformationNeedsEachAreasOwnPermission() async throws {
        guard Store.testing else { throw XCTSkip("Use SEARCH_PROBE for browser tests") }
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        Browsers.register(browser)
        defer { Browsers.discard(browser) }
        let context = try await context(permissions: ["tabs"])
        let key = "extensions.granted.\(context.uniqueIdentifier)"
        let previous = Store.settings.object(forKey: key)
        defer {
            if let previous { Store.settings.set(previous, forKey: key) }
            else { Store.settings.removeObject(forKey: key) }
        }
        let areas = ["system.cpu", "system.memory", "system.storage", "system.display"]
        for granted in areas {
            Store.settings.set([granted], forKey: key)
            for area in areas {
                let reply = try await answer(area + ".getInfo", context: context)
                if area == granted {
                    XCTAssertNil(reply["error"], "\(area): \(reply)")
                    XCTAssertNotNil(reply["value"])
                } else {
                    XCTAssertTrue((reply["error"] as? String)?.contains(area) == true, "\(area): \(reply)")
                    XCTAssertNil(reply["value"])
                }
            }
        }
        Store.settings.removeObject(forKey: key)
        let refused = try await answer("system.cpu.getInfo", context: context)
        XCTAssertNotNil(refused["error"], "Removing a grant must immediately close the native boundary")
    }

    func testPopupURLsStayInsideTheirOwnExtension() async throws {
        let context = try await context(popup: "popup.html?view=compact#settings")
        let popup = try XCTUnwrap(Extensions.popupURL(for: context))
        XCTAssertEqual(popup.scheme, Extensions.scheme)
        XCTAssertEqual(popup.host, context.baseURL.host)
        XCTAssertEqual(popup.path, "/popup.html")
        XCTAssertEqual(popup.query, "view=compact")
        XCTAssertEqual(popup.fragment, "settings")
        for path in ["/popup.html", "./popup.html", "nested/../popup.html", popup.absoluteString] {
            let own = try XCTUnwrap(Extensions.ownPage(path, for: context), path)
            XCTAssertEqual(own.scheme, Extensions.scheme)
            XCTAssertEqual(own.host, context.baseURL.host)
        }
        for path in ["https://example.com/popup", "http://example.com/", "//example.com/popup",
                     "\(Extensions.scheme)://another-extension/popup.html", "file:///tmp/popup.html",
                     "data:text/html,popup", "javascript:alert(1)", "about:blank"] {
            XCTAssertNil(Extensions.ownPage(path, for: context), path)
        }
        let external = try await self.context(popup: "https://example.com/popup")
        XCTAssertNil(Extensions.popupURL(for: external), "Manifest popups use the same origin restriction")
    }
}
