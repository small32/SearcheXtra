import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class TabRenameSheetTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "rename-sheet-\(getpid())", 1)
        super.setUp()
    }

    func testIconColumnAndSquarePinsUseAnEditableRenameSheet() async throws {
        _ = NSApplication.shared
        let activation = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        let prefs = browser.prefs
        let saved = (prefs.tabsLayout, prefs.sidePosition, prefs.listsPins, prefs.sharesPins)
        let front = Front.shared.browser
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 700, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        browser.window = window
        Front.shared.set(browser)
        window.orderFrontRegardless()
        prefs.sharesPins = false
        defer {
            if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .alertSecondButtonReturn) }
            Front.shared.set(front)
            browser.closeAll()
            window.close()
            prefs.tabsLayout = saved.0
            prefs.sidePosition = saved.1
            prefs.listsPins = saved.2
            prefs.sharesPins = saved.3
            NSApp.setActivationPolicy(activation)
        }
        let tab = try XCTUnwrap(browser.active)
        tab.restore(url: URL(string: "http://127.0.0.1:1/rename")!, title: "Page title")

        prefs.tabsLayout = .icons
        browser.beginTabRename(tab)
        var sheet = try XCTUnwrap(window.attachedSheet)
        var field = try XCTUnwrap(editableField(in: try XCTUnwrap(sheet.contentView)))
        XCTAssertEqual(field.stringValue, "Page title")
        XCTAssertNil(browser.editingTab, "There is no inline name field in an icon tile")
        field.stringValue = "Named icon"
        window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(tab.name, "Named icon")

        prefs.tabsLayout = .left
        prefs.listsPins = false
        browser.pin(tab)
        browser.endPinEdit()
        browser.beginTabRename(tab)
        sheet = try XCTUnwrap(window.attachedSheet)
        field = try XCTUnwrap(editableField(in: try XCTUnwrap(sheet.contentView)))
        XCTAssertEqual(field.stringValue, "Named icon")
        field.stringValue = "Discarded"
        window.endSheet(sheet, returnCode: .alertSecondButtonReturn)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(tab.name, "Named icon")

        browser.beginTabRename(tab)
        sheet = try XCTUnwrap(window.attachedSheet)
        field = try XCTUnwrap(editableField(in: try XCTUnwrap(sheet.contentView)))
        field.stringValue = "  "
        window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(tab.name, "An empty answer restores the page's title")

        prefs.tabsLayout = .top
        browser.beginTabRename(tab)
        XCTAssertEqual(browser.editingTab, tab.id, "Top-bar pins retain their existing inline field")
        XCTAssertNil(window.attachedSheet)
        browser.cancelTabEdit()
        prefs.tabsLayout = .left
        prefs.listsPins = true
        browser.setListed(tab, true)
        browser.beginTabRename(tab)
        XCTAssertEqual(browser.editingTab, tab.id, "A listed pin still has a normal sidebar name field")
        XCTAssertNil(window.attachedSheet)
    }

    private func editableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.compactMap { editableField(in: $0) }.first
    }
}
