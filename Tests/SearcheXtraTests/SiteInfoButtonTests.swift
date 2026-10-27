import AppKit
import SwiftUI
import XCTest
@testable import SearcheXtra

@MainActor
final class SiteInfoButtonTests: XCTestCase {
    func testButtonOpensSiteCardWithoutFocusedAddressField() throws {
        guard Store.testing else { throw XCTSkip("Use SEARCH_PROBE for browser tests") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        let tab = try XCTUnwrap(browser.active)
        tab.go(to: URL(string: "http://127.0.0.1:1/site-test")!)
        browser.beginTabEdit(tab)
        let draft = browser.typed
        let host = NSHostingView(rootView: SiteInfoButton(browser: browser, tab: tab))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 32),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            SiteCardPanel.hide()
            browser.dismiss()
            browser.closeAll()
            window.close()
        }
        host.layoutSubtreeIfNeeded()
        func siteButton(in view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.identifier?.rawValue == "TabSiteInfo" {
                return button
            }
            return view.subviews.compactMap { siteButton(in: $0) }.first
        }
        let button = try XCTUnwrap(siteButton(in: host))
        window.makeFirstResponder(nil)
        XCTAssertFalse(SiteCardPanel.isShown)
        button.performClick(nil)
        XCTAssertTrue(SiteCardPanel.isShown)
        XCTAssertTrue(browser.editing)
        XCTAssertNil(browser.editingTab)
        XCTAssertEqual(browser.typed, draft)
        XCTAssertEqual(window.childWindows?.count, 1)
        // A focus-loss callback queued before the panel opened arrives late.
        browser.finishTabEdit()
        XCTAssertTrue(browser.editing)
        XCTAssertNil(browser.editingTab)
        XCTAssertEqual(browser.typed, draft)
        XCTAssertTrue(SiteCardPanel.isShown)
        button.performClick(nil)
        XCTAssertEqual(window.childWindows?.count, 1)
        SiteCardPanel.dismiss()
        XCTAssertFalse(SiteCardPanel.isShown)
        XCTAssertNil(browser.editingTab)
        XCTAssertEqual(browser.typed, draft)
    }
}
