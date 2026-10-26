import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class TabSelectionTests: XCTestCase {
    private var browsers: [Browser] = []
    private var previousSession: Session.Shape?
    private var previousPreferences: (split: Bool, spaces: Bool, groups: Bool)?
    private var activationPolicy: NSApplication.ActivationPolicy?

    override class func setUp() {
        setenv("SEARCH_PROBE", "tab-selection-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() async throws {
        try await super.setUp()
        guard Store.testing else { throw XCTSkip("Run browser model tests with SEARCH_PROBE=interface-tests") }
        _ = NSApplication.shared
        activationPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.prohibited)
        previousSession = Session.read(space: Space.firstID)
        Session.write(now: true, space: Space.firstID, .init(tabs: [], active: 0))
        let prefs = Shared.prefs
        previousPreferences = (prefs.splitView, prefs.usesSpaces, prefs.usesTabGroups)
        prefs.splitView = false
        prefs.usesSpaces = false
        prefs.usesTabGroups = false
    }

    override func tearDown() async throws {
        for browser in browsers { browser.closeAll() }
        // Session callbacks hold weak owners. Release them before restoring
        // the saved row and preferences, so this test cannot write it again.
        browsers.removeAll()
        Disk.drain()
        if let previousSession {
            Session.write(now: true, space: Space.firstID, previousSession)
        }
        previousSession = nil
        if let previousPreferences {
            let prefs = Shared.prefs
            prefs.splitView = previousPreferences.split
            prefs.usesSpaces = previousPreferences.spaces
            prefs.usesTabGroups = previousPreferences.groups
        }
        previousPreferences = nil
        if let activationPolicy { NSApp.setActivationPolicy(activationPolicy) }
        activationPolicy = nil
        try await super.tearDown()
    }

    func testCommandTogglesAndShiftSelectsVisibleRange() {
        let browser = makeBrowser()
        let tabs = browser.shownTabs
        XCTAssertEqual(tabs.count, 4)

        browser.extendTabSelection(to: tabs[0], modifiers: .command)
        browser.extendTabSelection(to: tabs[2], modifiers: .command)
        XCTAssertEqual(browser.selectedTabIDs, Set([tabs[0].id, tabs[2].id, tabs[3].id]))
        XCTAssertEqual(browser.selectedTabLinks, ["https://one.example/", "https://three.example/", "https://four.example/"])

        browser.extendTabSelection(to: tabs[1], modifiers: .shift)
        XCTAssertEqual(browser.selectedTabIDs, Set([tabs[1].id, tabs[2].id]))
        XCTAssertEqual(browser.selectedTabLinks, ["https://two.example/", "https://three.example/"])

        browser.extendTabSelection(to: tabs[2], modifiers: .command)
        XCTAssertEqual(browser.selectedTabIDs, [tabs[1].id])
        browser.clearTabSelection()
        XCTAssertTrue(browser.selectedTabIDs.isEmpty)
    }

    func testBothSplitHalvesCanBeSelectedAndRangesIncludeBoth() {
        let browser = makeBrowser()
        let tabs = browser.shownTabs
        browser.prefs.splitView = true
        browser.pair(tabs[1], with: tabs[0], onLeft: false)
        browser.select(tabs[3])
        browser.extendTabSelection(to: tabs[0], modifiers: .command)
        browser.extendTabSelection(to: tabs[1], modifiers: .command)
        XCTAssertEqual(browser.selectedTabIDs, Set([tabs[0].id, tabs[1].id, tabs[3].id]))
        XCTAssertEqual(browser.selectedTabLinks, ["https://one.example/", "https://two.example/", "https://four.example/"])

        browser.clearTabSelection()
        browser.extendTabSelection(to: tabs[0], modifiers: .shift)
        XCTAssertEqual(browser.selectedTabIDs, Set(tabs.map(\.id)))
        XCTAssertEqual(browser.visibleSelectedTabCount, 4)
        XCTAssertEqual(browser.selectedTabLinks.count, 4)
    }

    private func makeBrowser() -> Browser {
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        browsers.append(browser)
        for word in ["one", "two", "three", "four"] {
            if browser.tabs.last?.isBlank == false { browser.newTab() }
            browser.tabs.last?.restore(url: URL(string: "https://\(word).example/")!, title: word)
        }
        return browser
    }
}
