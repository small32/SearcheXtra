import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class SidePanelScopeTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "panel-scope-\(getpid())", 1)
        super.setUp()
    }

    func testDisablingOneTabKeepsOtherWindowsAndBindings() throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Web extensions require macOS 15.4") }
        _ = NSApplication.shared
        let first = Browser(record: WindowRecord(), opensStartPage: false)
        let second = Browser(record: WindowRecord(), opensStartPage: false)
        let id = "panel-scope-fixture"
        defer {
            first.closeAll()
            second.closeAll()
            ExtensionShims.panelTabs[id] = nil
            ExtensionShims.panelTabIDs[id] = nil
            ExtensionShims.panelOff.remove(id)
        }
        let a = try XCTUnwrap(first.active)
        first.newTab()
        let b = try XCTUnwrap(first.active)
        let c = try XCTUnwrap(second.active)
        let url = URL(string: "https://example.com/panel")!
        let panelA = SidePanelContent.page(extensionID: id, url: url, tab: a.id)
        let panelB = SidePanelContent.page(extensionID: id, url: url, tab: b.id)
        let panelC = SidePanelContent.page(extensionID: id, url: url, tab: c.id)
        SidePanelPages.shared.bind(panelA, to: a.id, in: first)
        SidePanelPages.shared.bind(panelB, to: b.id, in: first)
        SidePanelPages.shared.bind(panelC, to: c.id, in: second)
        first.sidePanel = panelB
        first.sidePanelShown = true
        second.sidePanel = panelC
        second.sidePanelShown = true
        ExtensionShims.panelTabIDs[id] = [1: a.id, 2: b.id, 3: c.id]
        ExtensionShims.panelTabs[id] = [1: (nil, false), 2: (nil, true), 3: (nil, true)]

        ExtensionShims.refreshPanels(id, in: [first, second])
        XCTAssertNil(SidePanelPages.shared.bound(to: a.id, in: first))
        XCTAssertEqual(SidePanelPages.shared.bound(to: b.id, in: first), panelB)
        XCTAssertEqual(first.sidePanel, panelB)
        XCTAssertEqual(second.sidePanel, panelC)

        ExtensionShims.panelOff.insert(id)
        ExtensionShims.refreshPanels(id, in: [first, second])
        XCTAssertEqual(first.sidePanel, panelB, "A tab's explicit enable overrides the disabled default")
        XCTAssertEqual(second.sidePanel, panelC)
        ExtensionShims.panelTabs[id]?[2] = (nil, false)
        ExtensionShims.refreshPanels(id, in: [first, second])
        XCTAssertNil(first.sidePanel)
        XCTAssertEqual(second.sidePanel, panelC)
    }

    func testClosingHiddenTabRemovesItsBindingWithoutClosingOtherPanels() throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Web extensions require macOS 15.4") }
        _ = NSApplication.shared
        let first = Browser(record: WindowRecord(), opensStartPage: false)
        let second = Browser(record: WindowRecord(), opensStartPage: false)
        defer { first.closeAll(); second.closeAll() }
        let a = try XCTUnwrap(first.active)
        first.newTab()
        let b = try XCTUnwrap(first.active)
        let c = try XCTUnwrap(second.active)
        let id = "panel-close-fixture", url = URL(string: "https://example.com/panel")!
        let panelA = SidePanelContent.page(extensionID: id, url: url, tab: a.id)
        let panelB = SidePanelContent.page(extensionID: id, url: url, tab: b.id)
        let panelC = SidePanelContent.page(extensionID: id, url: url, tab: c.id)
        SidePanelPages.shared.bind(panelA, to: a.id, in: first)
        SidePanelPages.shared.bind(panelB, to: b.id, in: first)
        SidePanelPages.shared.bind(panelC, to: c.id, in: second)
        first.sidePanel = panelB
        first.sidePanelShown = true
        second.sidePanel = panelC
        second.sidePanelShown = true

        try ExtensionShims.closePanel(id, for: a.id, in: first)
        XCTAssertNil(SidePanelPages.shared.bound(to: a.id, in: first), "Switching back cannot reopen the closed panel")
        XCTAssertEqual(SidePanelPages.shared.bound(to: b.id, in: first), panelB)
        XCTAssertEqual(first.sidePanel, panelB)
        XCTAssertEqual(second.sidePanel, panelC)
        try ExtensionShims.closePanel(id, for: b.id, in: first)
        XCTAssertNil(first.sidePanel)
        XCTAssertFalse(first.sidePanelShown)
        XCTAssertNil(SidePanelPages.shared.bound(to: b.id, in: first))
        XCTAssertEqual(second.sidePanel, panelC)
    }

    func testWindowCloseKeepsTabBindingsAndOtherWindows() throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Web extensions require macOS 15.4") }
        _ = NSApplication.shared
        let first = Browser(record: WindowRecord(), opensStartPage: false)
        let second = Browser(record: WindowRecord(), opensStartPage: false)
        defer { first.closeAll(); second.closeAll() }
        let tab = try XCTUnwrap(first.active)
        let id = "panel-close-fixture", url = URL(string: "https://example.com/panel")!
        let specific = SidePanelContent.page(extensionID: id, url: url, tab: tab.id)
        let global = SidePanelContent.page(extensionID: id, url: url, tab: nil)
        SidePanelPages.shared.bind(specific, to: tab.id, in: first)
        first.sidePanel = specific
        first.sidePanelShown = true
        second.sidePanel = global
        second.sidePanelShown = true

        try ExtensionShims.closePanel(id, in: first)
        XCTAssertEqual(first.sidePanel, specific, "A window close targets only the global panel")
        first.sidePanel = global
        try ExtensionShims.closePanel(id, in: first)
        XCTAssertNil(first.sidePanel)
        XCTAssertEqual(SidePanelPages.shared.bound(to: tab.id, in: first), specific)
        XCTAssertEqual(second.sidePanel, global)
    }

    func testTabCloseRejectsGlobalPanelAndKeepsOtherExtensions() throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Web extensions require macOS 15.4") }
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { browser.closeAll() }
        let tab = try XCTUnwrap(browser.active)
        let id = "panel-close-fixture", url = URL(string: "https://example.com/panel")!
        let global = SidePanelContent.page(extensionID: id, url: url, tab: nil)
        browser.sidePanel = global
        browser.sidePanelShown = true
        XCTAssertThrowsError(try ExtensionShims.closePanel(id, for: tab.id, in: browser))
        XCTAssertEqual(browser.sidePanel, global)

        let other = SidePanelContent.page(extensionID: "another-extension", url: url, tab: tab.id)
        SidePanelPages.shared.bind(other, to: tab.id, in: browser)
        browser.sidePanel = other
        try ExtensionShims.closePanel(id, for: tab.id, in: browser)
        try ExtensionShims.closePanel(id, in: browser)
        XCTAssertEqual(browser.sidePanel, other)
        XCTAssertEqual(SidePanelPages.shared.bound(to: tab.id, in: browser), other)
    }
}
