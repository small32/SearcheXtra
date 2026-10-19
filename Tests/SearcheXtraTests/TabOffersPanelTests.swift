import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class TabOffersPanelTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "tab-offers-\(getpid())", 1)
        super.setUp()
    }

    func testLateClearAndFieldDismantleCannotDismissAnotherWindowsOffers() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let a = Browser(record: WindowRecord()), b = Browser(record: WindowRecord())
        let first = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        let second = NSWindow(contentRect: NSRect(x: 600, y: 0, width: 500, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        first.isReleasedWhenClosed = false
        second.isReleasedWhenClosed = false
        a.window = first
        b.window = second
        let aField = NSTextField(frame: NSRect(x: 20, y: 260, width: 220, height: 22))
        let bField = NSTextField(frame: NSRect(x: 20, y: 260, width: 220, height: 22))
        try XCTUnwrap(first.contentView).addSubview(aField)
        try XCTUnwrap(second.contentView).addSubview(bField)
        let originalPresentation = TabOffersPanel.present
        var presentedIn: [NSWindow] = []
        // Build the real panel and hosting view, but never order a test
        // window or its child onto the user's screen.
        TabOffersPanel.present = { panel, owner in
            XCTAssertFalse(panel.isVisible)
            presentedIn.append(owner)
        }
        defer {
            TabOffersPanel.forget(a)
            TabOffersPanel.forget(b)
            TabOffersPanel.present = originalPresentation
            a.closeAll(); b.closeAll()
            first.close(); second.close()
        }

        a.beginTabEdit(try XCTUnwrap(a.active))
        b.beginTabEdit(try XCTUnwrap(b.active))
        _ = a.tabTyped("offer-first")
        _ = b.tabTyped("offer-second")
        XCTAssertFalse(a.tabOffers.isEmpty)
        XCTAssertFalse(b.tabOffers.isEmpty)
        TabOffersPanel.follow(a, anchor: aField)
        TabOffersPanel.follow(b, anchor: bField)
        // Both fields exist before the first publication is delivered: a
        // shared anchor would attach A's offers to B's window here.
        TabOffersPanel.update(a)
        XCTAssertTrue(TabOffersPanel.isShown(for: a))
        XCTAssertTrue(presentedIn.last === first)
        TabOffersPanel.update(b)
        XCTAssertTrue(TabOffersPanel.isShown(for: b))
        XCTAssertTrue(presentedIn.last === second)

        a.cancelTabEdit()
        TabOffersPanel.update(a) // A's delayed empty publication.
        XCTAssertTrue(TabOffersPanel.isShown(for: b))
        TabOffersPanel.hide(for: a) // A's old field dismantled afterward.
        TabOffersPanel.forget(a)
        XCTAssertTrue(TabOffersPanel.isShown(for: b))
        b.cancelTabEdit()
        TabOffersPanel.update(b)
        XCTAssertFalse(TabOffersPanel.isShown)
        XCTAssertFalse(first.isVisible)
        XCTAssertFalse(second.isVisible)
    }
}
