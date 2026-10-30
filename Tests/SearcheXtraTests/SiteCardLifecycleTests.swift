import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class SiteCardLifecycleTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "site-card-lifecycle-\(getpid())", 1)
        super.setUp()
    }

    func testCardActionsKeepTheirTabWhenTheActiveTabChanges() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { browser.closeAll() }
        let first = try XCTUnwrap(browser.active)
        first.restore(url: URL(string: "http://127.0.0.1:1/first")!, title: "First")
        let card = SiteCard(browser: browser, tab: first, close: {})
        browser.newTab()
        let second = try XCTUnwrap(browser.active)
        second.restore(url: URL(string: "http://127.0.0.1:1/second")!, title: "Second")
        first.magnify(to: 1)
        second.magnify(to: 1)
        card.magnify(by: 1.1)
        XCTAssertEqual(first.zoom, 1.1, accuracy: 0.001)
        XCTAssertEqual(second.zoom, 1, accuracy: 0.001)
        card.copyAddress()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), first.address?.absoluteString)
        card.resetZoom()
        XCTAssertEqual(first.zoom, Tab.defaultZoom, accuracy: 0.001)
        XCTAssertEqual(second.zoom, 1, accuracy: 0.001)

        browser.close(first)
        XCTAssertNil(first.built)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("unchanged", forType: .string)
        card.copyAddress()
        card.magnify(by: 1.1)
        card.resetZoom()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "unchanged")
        XCTAssertNil(first.built, "An old card must not recreate a tab removed from its browser")
    }

    func testOnlyTheOwningBrowserCanInvalidateThePanel() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        let other = Browser(record: WindowRecord(), opensStartPage: false)
        let tab = try XCTUnwrap(browser.active)
        tab.restore(url: URL(string: "http://127.0.0.1:1/site-card")!, title: "Page")
        browser.beginTabEdit(tab)
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 600, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        browser.window = window
        let anchor = NSButton(frame: NSRect(x: 20, y: 100, width: 20, height: 20))
        try XCTUnwrap(window.contentView).addSubview(anchor)
        defer {
            SiteCardPanel.hide()
            browser.closeAll()
            other.closeAll()
            window.close()
        }
        SiteCardPanel.show(for: tab, in: browser, under: anchor)
        XCTAssertTrue(SiteCardPanel.isShown)
        SiteCardPanel.hide(in: other)
        other.typed = "background typing"
        XCTAssertTrue(SiteCardPanel.isShown)
        XCTAssertEqual(window.childWindows?.count, 1)
        SiteCardPanel.hide(in: browser)
        XCTAssertFalse(SiteCardPanel.isShown)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
        SiteCardPanel.show(for: tab, in: browser, under: anchor)
        XCTAssertTrue(SiteCardPanel.isShown)
        tab.restore(url: URL(string: "http://127.0.0.1:1/other")!, title: "Other")
        XCTAssertFalse(SiteCardPanel.isShown, "Navigation must close the previous site's card")
    }

    func testInvalidatingPendingPlacementPreventsThePanelFromReopening() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        let tab = try XCTUnwrap(browser.active)
        tab.restore(url: URL(string: "http://127.0.0.1:1/site-card")!, title: "Page")
        browser.beginTabEdit(tab)
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 600, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        browser.window = window
        let field = NSTextField(frame: NSRect(x: 20, y: 100, width: 400, height: 24))
        try XCTUnwrap(window.contentView).addSubview(field)
        XCTAssertTrue(window.makeFirstResponder(field))
        defer {
            SiteCardPanel.hide()
            browser.closeAll()
            window.close()
        }
        SiteCardPanel.show(for: tab, in: browser)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(SiteCardPanel.isShown)
        SiteCardPanel.hide(in: browser)
        SiteCardPanel.show(for: tab, in: browser)
        SiteCardPanel.hide(in: browser)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(SiteCardPanel.isShown)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }
}
