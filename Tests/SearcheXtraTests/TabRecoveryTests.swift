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

    private func makeTab() -> Tab {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return Tab(configuration: configuration)
    }
}
