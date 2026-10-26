import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class InternalPageTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "internal-pages-\(getpid())", 1)
        super.setUp()
    }

    func testRoutesRoundTripAndRejectWebsiteAddresses() {
        for kind in InternalPage.Kind.allCases {
            let page = InternalPage(kind, "a section 中文")
            XCTAssertEqual(InternalPage(url: page.url), page)
        }
        XCTAssertNil(InternalPage(url: URL(string: "https://settings/privacy")!))
        XCTAssertNil(InternalPage(url: URL(string: "search://unknown")!))
    }

    func testRepeatedSettingsRequestsReuseTheSameTab() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { browser.closeAll() }
        let first = browser.show(InternalPage(.settings, "privacy"))
        let again = browser.show(InternalPage(.settings, "general"))
        XCTAssertTrue(first === again)
        XCTAssertEqual(first.page?.detail, "general")
        XCTAssertEqual(browser.tabs.filter { $0.page?.kind == .settings }.count, 1)
    }

    func testBookmarkPickKeepsTheManagerTabAndItsBackHistory() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { browser.closeAll() }
        let manager = browser.show(InternalPage(.bookmarks))
        browser.pickBookmark(InternalPage(.history).url)
        XCTAssertEqual(browser.activeID, manager.id)
        XCTAssertTrue(browser.tabs.contains { $0 === manager })
        XCTAssertEqual(manager.page?.kind, .history)
        browser.back()
        XCTAssertEqual(manager.page?.kind, .bookmarks)
        browser.pickBookmark(InternalPage(.downloads).url, inNewTab: true)
        XCTAssertEqual(browser.activeID, manager.id)
        XCTAssertEqual(manager.page?.kind, .bookmarks)
        XCTAssertTrue(browser.tabs.contains { $0 !== manager && $0.page?.kind == .downloads })
    }

    func testBackgroundInternalPageDoesNotReplaceTheActiveBlankTab() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { browser.closeAll() }
        let source = browser.active!
        let count = browser.tabs.count
        let opened = browser.open(InternalPage(.downloads).url, foreground: false)
        XCTAssertEqual(browser.activeID, source.id)
        XCTAssertTrue(source.isBlank)
        XCTAssertNotEqual(opened.id, source.id)
        XCTAssertEqual(opened.page?.kind, .downloads)
        XCTAssertEqual(browser.tabs.count, count + 1)
    }
}
