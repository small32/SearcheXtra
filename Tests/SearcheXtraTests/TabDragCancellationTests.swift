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
        guard Store.testing else { throw XCTSkip("Requires an isolated test store") }
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
        guard Store.testing else { throw XCTSkip("Requires an isolated test store") }
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 100, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        browser.window = window
        let tab = try XCTUnwrap(browser.active)
        let previous = browser.prefs.splitView
        browser.prefs.splitView = true
        defer {
            _ = TabDrag.shared.finish(browser: browser, tab: tab)
            browser.closeAll()
            window.close()
            browser.prefs.splitView = previous
        }
        _ = TabDrag.shared.update(browser: browser, tab: tab, translation: .zero)
        TabDrag.shared.cancel()
        XCTAssertEqual(TabDrag.shared.cancelledID, tab.id)
        // Dispatch through NSApplication so the installed local monitor,
        // rather than a direct call to pressBegan(), begins the new press.
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: NSPoint(x: 50, y: 50), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        NSApp.sendEvent(event)
        XCTAssertNil(TabDrag.shared.cancelledID)
        _ = TabDrag.shared.update(browser: browser, tab: tab, translation: .zero)
        let result = TabDrag.shared.finish(browser: browser, tab: tab)
        if case .cancelled = result.drop { XCTFail("A new press is a new drag") }
    }
}
