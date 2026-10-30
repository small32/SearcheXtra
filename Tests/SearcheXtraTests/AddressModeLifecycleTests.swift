import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class AddressModeLifecycleTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "address-mode-lifecycle-\(getpid())", 1)
        super.setUp()
    }

    func testAddressAndTabSearchModesClearThePreviousSiteSearch() throws {
        try withBrowser { browser, tab, _, _ in
            let site = SearchSite(name: "Reddit", host: "reddit.com", template: "https://www.reddit.com/search/?q=%s")
            browser.edit()
            browser.siteChip = site
            browser.typed = "a draft query"

            browser.edit()

            XCTAssertNil(browser.siteChip)
            XCTAssertEqual(browser.typed, tab.address?.absoluteString)
            XCTAssertEqual(browser.destination(for: browser.typed), tab.address)

            browser.siteChip = site
            browser.summon()
            XCTAssertNil(browser.siteChip)
            XCTAssertTrue(browser.summoning)
            XCTAssertTrue(browser.offers.allSatisfy { $0.kind == .open })
        }
    }

    func testSiteCardClosesWhenItsAddressOrTabContextEnds() throws {
        let actions: [(String, (Browser, Tab) -> Void)] = [
            ("typing", { browser, _ in browser.typed += "?changed" }),
            ("hide field", { browser, _ in browser.editing = false }),
            ("dismiss", { browser, _ in browser.dismiss() }),
            ("edit again", { browser, _ in browser.edit() }),
            ("tab search", { browser, _ in browser.summon() }),
            ("submit", { browser, _ in browser.submit() }),
            ("switch tab", { browser, _ in browser.newTab() }),
            ("close tab", { browser, tab in browser.close(tab) }),
            ("close window", { browser, _ in browser.closeAll() }),
        ]
        for (name, action) in actions {
            try withBrowser { browser, tab, field, window in
                if name == "submit" { browser.typed = "about:blank" }
                SiteCardPanel.show(for: tab, in: browser, under: field)
                XCTAssertTrue(SiteCardPanel.isShown, name)
                action(browser, tab)
                XCTAssertFalse(SiteCardPanel.isShown, name)
                XCTAssertTrue(window.childWindows?.isEmpty ?? true, name)
            }
        }
    }

    private func withBrowser(_ body: (Browser, Tab, NSView, NSWindow) throws -> Void) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        browser.leaveFiles()
        browser.closeAll()
        browser.record.rows = [:]
        browser.restoreSession(useStartPage: false)
        let tab = try XCTUnwrap(browser.active)
        tab.restore(url: URL(string: "https://address-context.example/page")!, title: "Site card")
        browser.edit()
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 500, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let field = NSTextField(frame: NSRect(x: 20, y: 120, width: 400, height: 28))
        window.contentView = field
        defer {
            SiteCardPanel.hide()
            browser.closeAll()
            window.contentView = nil
            window.close()
        }
        try body(browser, tab, field, window)
    }
}
