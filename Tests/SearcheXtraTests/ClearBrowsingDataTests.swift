import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class ClearBrowsingDataTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "clear-browsing-data-\(getpid())", 1)
        super.setUp()
    }

    func testClearOpensHistoryAndReusesItsTab() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { browser.closeAll() }
        XCTAssertFalse(browser.recalling)
        browser.clearBrowsingData()
        XCTAssertTrue(browser.recalling)
        XCTAssertEqual(browser.recallMode, .clearing)
        browser.clearBrowsingData()
        XCTAssertEqual(browser.tabs.filter { $0.page?.kind == .history }.count, 1)
        XCTAssertEqual(browser.recallMode, .clearing)
    }

    func testClearUsesAlreadyOpenHistory() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { browser.closeAll() }
        browser.recalling = true
        XCTAssertEqual(browser.recallMode, .history)
        browser.clearBrowsingData()
        XCTAssertEqual(browser.recallMode, .clearing)
    }
}
