import AppKit
import XCTest
@testable import SearcheXtra

/// Panel ownership follows the active tab, including changes that bypass
/// select(_:). These model tests never create or show a browser window.
@MainActor
final class SidePanelLifecycleTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "side-panel-lifecycle-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
    }

    override func tearDown() async throws {
        XCTAssertTrue(NSApp.windows.allSatisfy { !$0.isVisible })
        XCTAssertFalse(NSApp.isActive)
    }

    func testNewTabHidesThePreviousTabsPanelButKeepsItsBinding() throws {
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { browser.closeAll() }
        let original = try page(in: browser)
        let content = bindPanel(to: original, in: browser)
        browser.newTab()
        XCTAssertNotEqual(browser.activeID, original.id)
        XCTAssertFalse(browser.sidePanelShown)
        XCTAssertNil(browser.sidePanel)
        XCTAssertEqual(SidePanelPages.shared.bound(to: original.id, in: browser), content)
    }

    func testFocusingAnotherSplitPaneHidesATabSpecificPanel() throws {
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        let previousSplit = browser.prefs.splitView
        defer { browser.closeAll(); browser.prefs.splitView = previousSplit }
        let left = try page(in: browser)
        browser.prefs.splitView = true
        browser.startSplit()
        let right = try XCTUnwrap(browser.active)
        XCTAssertNotEqual(left.id, right.id)
        let content = bindPanel(to: right, in: browser)
        browser.focusPane(left)
        XCTAssertEqual(browser.activeID, left.id)
        XCTAssertFalse(browser.sidePanelShown)
        XCTAssertNil(browser.sidePanel)
        XCTAssertEqual(SidePanelPages.shared.bound(to: right.id, in: browser), content)
    }

    func testSwitchingSpaceRowsAndNilActiveKeepLiveParkedBindings() async throws {
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { browser.closeAll() }
        let original = try page(in: browser)
        let content = bindPanel(to: original, in: browser)
        let space = UUID()
        browser.parked[space] = Parked(tabs: browser.tabs, active: original.id)
        let other = Tab()
        browser.prepare(other)
        other.restore(url: URL(string: "https://other.example/")!, title: "Other")
        browser.showRow([other], active: other.id)
        XCTAssertFalse(browser.sidePanelShown)
        XCTAssertNil(browser.sidePanel)
        await drainMainQueue()
        XCTAssertEqual(SidePanelPages.shared.bound(to: original.id, in: browser), content)

        browser.sidePanel = content
        browser.sidePanelShown = true
        browser.activeID = nil
        XCTAssertFalse(browser.sidePanelShown)
        XCTAssertNil(browser.sidePanel)
        XCTAssertEqual(SidePanelPages.shared.bound(to: original.id, in: browser), content)

        browser.parked.removeValue(forKey: space)?.tabs.forEach { $0.close() }
        await drainMainQueue()
        XCTAssertNil(SidePanelPages.shared.bound(to: original.id, in: browser))
    }

    func testClosingTheLastPageClearsItsPanelBeforeSelectingTheReplacement() throws {
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { browser.closeAll() }
        let original = try page(in: browser)
        _ = bindPanel(to: original, in: browser)
        browser.close(original)
        XCTAssertNotEqual(browser.activeID, original.id)
        XCTAssertFalse(browser.sidePanelShown)
        XCTAssertNil(browser.sidePanel)
        XCTAssertNil(SidePanelPages.shared.bound(to: original.id, in: browser))
    }

    func testReplacingATabAndClosingTheWindowForgetBindings() throws {
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { browser.closeAll() }
        let original = try page(in: browser)
        _ = bindPanel(to: original, in: browser)
        browser.replace(original, going: URL(string: "https://replacement.example/")!)
        XCTAssertNil(SidePanelPages.shared.bound(to: original.id, in: browser))
        XCTAssertFalse(browser.sidePanelShown)
        let current = try XCTUnwrap(browser.active)
        _ = bindPanel(to: current, in: browser)
        browser.closeAll()
        XCTAssertNil(SidePanelPages.shared.bound(to: current.id, in: browser))
        XCTAssertNil(SidePanelPages.shared.web(in: browser))
        XCTAssertFalse(browser.sidePanelShown)
        XCTAssertNil(browser.sidePanel)
    }

    private func page(in browser: Browser) throws -> SearcheXtra.Tab {
        let tab = try XCTUnwrap(browser.active)
        tab.restore(url: URL(string: "https://panel-owner.example/")!, title: "Panel owner")
        return tab
    }

    @discardableResult
    private func bindPanel(to tab: SearcheXtra.Tab, in browser: Browser) -> SidePanelContent {
        let content = SidePanelContent.page(extensionID: "side-panel-fixture",
                                            url: URL(string: "chrome-extension://side-panel-fixture/panel.html")!, tab: tab.id)
        SidePanelPages.shared.bind(content, to: tab.id, in: browser)
        browser.sidePanel = content
        browser.sidePanelShown = true
        return content
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
