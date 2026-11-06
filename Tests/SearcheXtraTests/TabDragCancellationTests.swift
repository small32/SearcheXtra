import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class TabDragCancellationTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "tab-drag-cancel-\(getpid())", 1)
        super.setUp()
    }

    func testCancelledPressStaysCancelledUntilItEnds() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        let tab = try XCTUnwrap(browser.active)
        let previous = browser.prefs.splitView
        browser.prefs.splitView = true
        defer {
            _ = TabDrag.shared.finish(browser: browser, tab: tab)
            browser.closeAll()
            browser.prefs.splitView = previous
        }
        _ = TabDrag.shared.update(browser: browser, tab: tab, translation: .zero)
        TabDrag.shared.cancel()
        // A slow release is still the same press, even beyond the old timeout.
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(TabDrag.shared.update(browser: browser, tab: tab, translation: .init(width: 150, height: 0)))
        XCTAssertEqual(TabDrag.shared.cancelledID, tab.id)
        let result = TabDrag.shared.finish(browser: browser, tab: tab)
        guard case .cancelled = result.drop else { return XCTFail("A cancelled drag must not drop") }
    }

    func testNextPressCanDragImmediatelyWithoutPreviousEndCallback() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        let tab = try XCTUnwrap(browser.active)
        let previous = browser.prefs.splitView
        browser.prefs.splitView = true
        defer {
            _ = TabDrag.shared.finish(browser: browser, tab: tab)
            browser.closeAll()
            browser.prefs.splitView = previous
        }
        _ = TabDrag.shared.update(browser: browser, tab: tab, translation: .zero)
        TabDrag.shared.cancel()
        // What the next mouse-down monitor does, with no time limit.
        TabDrag.shared.pressBegan()
        XCTAssertNil(TabDrag.shared.cancelledID)
        _ = TabDrag.shared.update(browser: browser, tab: tab, translation: .zero)
        let result = TabDrag.shared.finish(browser: browser, tab: tab)
        if case .cancelled = result.drop { XCTFail("A new press is a new drag") }
    }
}
