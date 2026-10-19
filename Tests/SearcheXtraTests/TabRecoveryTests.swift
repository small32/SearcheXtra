import AppKit
import WebKit
import XCTest
@testable import SearcheXtra

@MainActor
final class TabRecoveryTests: XCTestCase {
    override func setUp() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
    }

    func testDelayedWakeCannotRebuildRestingOrClosedTabs() async throws {
        let resting = makeTab()
        let closed = makeTab()
        defer { resting.close(); closed.close() }
        let url = URL(string: "http://127.0.0.1:9/unused")!
        for tab in [resting, closed] {
            tab.restore(url: url, title: "Restored")
            XCTAssertTrue(tab.wake())
            XCTAssertNotNil(tab.built)
        }
        resting.rest()
        closed.close()
        try await Task.sleep(for: .seconds(2.5))
        XCTAssertNil(resting.built)
        XCTAssertTrue(resting.asleep)
        XCTAssertNil(closed.built)
    }

    func testDelayedWakeCannotReplaceANewerNavigation() async throws {
        let first = try LocalDownloadServer(size: 1)
        let second = try LocalDownloadServer(size: 1)
        let tab = makeTab()
        defer { tab.close(); first.stop(); second.stop() }
        tab.restore(url: first.url("/page"), title: "Restored")
        XCTAssertTrue(tab.wake())
        tab.go(to: second.url("/page"))
        try await Task.sleep(for: .seconds(2.5))
        XCTAssertEqual(tab.address, second.url("/page"))
        XCTAssertEqual(first.count("/page"), 0)
        XCTAssertGreaterThan(second.count("/page"), 0)
    }

    func testExtensionRuntimeChangeWaitsForReloadAndPreservesHistory() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires native extension support") }
        let fixture = try LocalDownloadServer(size: 1)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.webExtensionController = Extensions.shared.controller
        let tab = Tab(configuration: configuration)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 700, height: 500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            tab.close()
            window.contentView = nil
            window.close()
            fixture.stop()
        }
        let first = fixture.url("/page").appending(queryItems: [URLQueryItem(name: "entry", value: "first")])
        let second = fixture.url("/page").appending(queryItems: [URLQueryItem(name: "entry", value: "second")])
        let original = tab.web
        original.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        window.contentView = original
        tab.go(to: first)
        try await until("first history entry") { original.url == first && !original.isLoading }
        tab.go(to: second)
        try await until("second history entry") { original.url == second && !original.isLoading && original.canGoBack }
        _ = try await original.evaluateJavaScript("""
        const input = document.createElement('input');
        input.id = 'runtime-reload-draft';
        input.value = 'unsaved draft';
        document.body.appendChild(input);
        true;
        """)
        let identifier = tab.id
        let controller = original.configuration.userContentController
        let history = original.backForwardList.backList.map(\.url)
        let requests = fixture.count("/page")

        tab.extensionRuntimeChanged()
        XCTAssertTrue(tab.needsExtensionReload)
        XCTAssertTrue(tab.built === original, "A permission change must leave the current document in place")
        let draft = try await original.evaluateJavaScript("document.getElementById('runtime-reload-draft').value")
        XCTAssertEqual(draft as? String, "unsaved draft")
        XCTAssertEqual(fixture.count("/page"), requests, "Marking a runtime change must not refresh the website")

        tab.reload()
        let restored = try XCTUnwrap(tab.built)
        XCTAssertFalse(restored === original)
        XCTAssertFalse(restored.configuration.userContentController === controller)
        XCTAssertTrue(restored.configuration.websiteDataStore === configuration.websiteDataStore)
        XCTAssertEqual(tab.id, identifier)
        XCTAssertFalse(tab.needsExtensionReload)
        restored.frame = original.frame
        window.contentView = restored
        try await until("restored current page") { restored.url == second && !restored.isLoading }
        XCTAssertEqual(restored.backForwardList.backList.map(\.url), history)
        tab.back()
        try await until("restored back navigation") { restored.url == first && !restored.isLoading }
        tab.forward()
        try await until("restored forward navigation") { restored.url == second && !restored.isLoading }
    }

    private func until(_ label: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(label)")
        throw NavigationFailure.timedOut
    }

    private enum NavigationFailure: Error { case timedOut }

    private func makeTab() -> Tab {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return Tab(configuration: configuration)
    }
}
