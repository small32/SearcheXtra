import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class BookmarkBarTests: XCTestCase {
    private var previousOpening: BookmarkBarOpening = .standard
    private var previousCompact = false
    private var previousLazy = false

    override func setUp() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        previousOpening = Shared.prefs.bookmarkBarOpening
        previousCompact = Shared.prefs.compactBookmarksBar
        previousLazy = Shared.prefs.lazyTabs
    }

    override func tearDown() async throws {
        guard Store.testing else { return }
        Shared.prefs.bookmarkBarOpening = previousOpening
        Shared.prefs.compactBookmarksBar = previousCompact
        Shared.prefs.lazyTabs = previousLazy
    }

    func testOpeningModesPreserveOrChangeTheActiveTab() {
        let original = URL(string: "http://127.0.0.1:1/original")!
        let bookmark = URL(string: "http://127.0.0.1:1/bookmark")!
        for mode in BookmarkBarOpening.allCases {
            let browser = Browser(record: WindowRecord(), opensStartPage: false)
            defer { for tab in browser.tabs { tab.close() } }
            browser.visit(original)
            let first = browser.active!
            let count = browser.tabs.count
            Shared.prefs.bookmarkBarOpening = mode
            Shared.prefs.lazyTabs = true
            browser.visitBookmarkBar(bookmark)
            switch mode {
            case .standard:
                XCTAssertEqual(browser.tabs.count, count)
                XCTAssertEqual(browser.activeID, first.id)
                XCTAssertEqual(first.address, bookmark)
            case .background:
                XCTAssertEqual(browser.tabs.count, count + 1)
                XCTAssertEqual(browser.activeID, first.id)
                XCTAssertEqual(first.address, original)
                XCTAssertEqual(browser.tabs.first { $0.id != first.id }?.pending, bookmark)
            case .foreground:
                XCTAssertEqual(browser.tabs.count, count + 1)
                XCTAssertNotEqual(browser.activeID, first.id)
                XCTAssertEqual(first.address, original)
                XCTAssertEqual(browser.active?.address, bookmark)
            }
        }
    }

    func testOrdinaryBookmarkDoesNotReplaceAPinnedTab() {
        Shared.prefs.bookmarkBarOpening = .standard
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { for tab in browser.tabs { tab.close() } }
        let home = URL(string: "http://127.0.0.1:1/pin")!
        let destination = URL(string: "http://127.0.0.1:1/bookmark")!
        browser.visit(home)
        let pinned = browser.active!
        browser.pin(pinned)
        browser.visitBookmarkBar(destination)
        XCTAssertEqual(pinned.address, home)
        XCTAssertNotEqual(browser.activeID, pinned.id)
        XCTAssertEqual(browser.active?.address, destination)
    }

    func testBulkOpeningPreservesBookmarkOrder() {
        Shared.prefs.lazyTabs = true
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { for tab in browser.tabs { tab.close() } }
        let urls = ["a", "b", "c"].map { URL(string: "http://127.0.0.1:1/" + $0)! }
        let opened = browser.openBookmarks(urls)
        XCTAssertEqual(opened.compactMap { $0.pending ?? $0.address }, urls)
        XCTAssertEqual(browser.tabs.filter { tab in opened.contains { $0.id == tab.id } }.map { $0.id }, opened.map { $0.id })
    }

    func testExplicitNewTabPickAlwaysStaysInBackgroundAndKeepsListOpen() {
        Shared.prefs.lazyTabs = true
        for mode in BookmarkBarOpening.allCases {
            Shared.prefs.bookmarkBarOpening = mode
            let browser = Browser(record: WindowRecord(), opensStartPage: false)
            defer { for tab in browser.tabs { tab.close() } }
            let original = URL(string: "http://127.0.0.1:1/original")!
            browser.visit(original)
            let source = browser.active!
            browser.bookmarking = true
            browser.bookmarksOpen = true
            let url = URL(string: "http://127.0.0.1:1/bookmark")!
            browser.pickBookmark(url, inNewTab: true)
            XCTAssertEqual(browser.tabs.count, 2)
            XCTAssertEqual(browser.activeID, source.id)
            XCTAssertEqual(source.address, original)
            XCTAssertEqual(browser.tabs.first { $0.id != source.id }?.pending, url)
            XCTAssertTrue(browser.bookmarking)
            XCTAssertTrue(browser.bookmarksOpen)
        }
    }

    func testExplicitBackgroundBookmarkKeepsPrivateStore() {
        Shared.prefs.lazyTabs = true
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { for tab in browser.tabs { tab.close() } }
        browser.newShyTab()
        let source = browser.active!
        source.setAddressOptimistically(URL(string: "https://private.example/original")!)
        let opened = browser.openBookmarkInBackground(URL(string: "https://private.example/bookmark")!)
        XCTAssertEqual(browser.activeID, source.id)
        XCTAssertTrue(opened.shy)
        XCTAssertTrue(opened.store === source.store)
        XCTAssertFalse(opened.store.isPersistent)
    }

    func testBookmarkFolderPopupStaysBelowBarAndCloses() {
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { for tab in browser.tabs { tab.close() } }
        let folder = browser.bookmarks.insert(.folder("Popup test", [.site("Bookmark", URL(string: "https://example.com")!)]), into: nil)
        defer { browser.bookmarks.remove(folder.id); BookmarkBarPanel.hide() }
        let window = NSWindow(contentRect: NSRect(x: 160, y: 200, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            BookmarkBarPanel.hide()
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        let anchor = NSView(frame: NSRect(x: 20, y: 350, width: 100, height: 22))
        window.contentView?.addSubview(anchor)
        BookmarkBarPanel.show(folder, in: browser, from: anchor)
        XCTAssertTrue(BookmarkBarPanel.isShown)
        let panel = window.childWindows?.first
        XCTAssertNotNil(panel)
        XCTAssertTrue(panel!.isVisible)
        let spot = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        XCTAssertLessThanOrEqual(panel!.frame.maxY, spot.minY)
        BookmarkBarPanel.hide()
        XCTAssertFalse(BookmarkBarPanel.isShown)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }

    func testExtensionResultCountsRejectNegativeValues() throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Extensions require macOS 15.4") }
        XCTAssertThrowsError(try ExtensionShims.resultLimit(-1, default: 10))
        XCTAssertThrowsError(try ExtensionShims.resultLimit(26, default: 25, maximum: 25))
        XCTAssertEqual(try ExtensionShims.resultLimit(0, default: 10), 0)
        XCTAssertEqual(try ExtensionShims.resultLimit(nil, default: 10), 10)
    }

    func testLastPrivatePageLeavesAPrivateBlankTab() {
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { for tab in browser.tabs { tab.close() } }
        browser.newShyTab()
        let privatePage = browser.active!
        privatePage.setAddressOptimistically(URL(string: "https://private.example")!)
        for tab in browser.tabs where !tab.shy { browser.close(tab) }
        let store = privatePage.store
        browser.close(privatePage)
        XCTAssertEqual(browser.tabs.count, 1)
        XCTAssertEqual(browser.active?.shy, true)
        XCTAssertEqual(browser.active?.isBlank, true)
        XCTAssertTrue(browser.active?.store === store)
        XCTAssertFalse(browser.active!.store.isPersistent)
    }

    func testBookmarkGroupFromPrivatePageKeepsPrivacyAndStaysOutOfSession() {
        let previousGroups = Shared.prefs.usesTabGroups
        defer { Shared.prefs.usesTabGroups = previousGroups }
        Shared.prefs.lazyTabs = true
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { for tab in browser.tabs { tab.close() } }
        let ordinary = browser.active!
        ordinary.setAddressOptimistically(URL(string: "https://ordinary.example")!)
        browser.newShyTab()
        let source = browser.active!
        let urls = ["a", "b"].map { URL(string: "https://private.example/" + $0)! }
        let opened = browser.openBookmarkGroup(urls, name: "Private bookmarks")
        XCTAssertEqual(opened.count, 2)
        XCTAssertTrue(opened.allSatisfy { $0.shy && !$0.store.isPersistent && $0.store === source.store })
        let group = opened[0].groupID
        XCTAssertNotNil(group)
        XCTAssertTrue(opened.allSatisfy { $0.groupID == group })
        browser.move(ordinary, toGroup: group)
        XCTAssertNil(ordinary.groupID)
        browser.dropTabIntoStrip(ordinary, before: opened[0])
        XCTAssertNil(ordinary.groupID)
        XCTAssertFalse(browser.allRows().values.flatMap { $0.groups ?? [] }.contains { $0.id == group })
    }

    func testPrivateExtensionSettingRebuildsExistingPageWithSameStore() throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Extensions require macOS 15.4") }
        let previous = Shared.prefs.extensionsInPrivate
        defer { Shared.prefs.extensionsInPrivate = previous }
        Shared.prefs.extensionsInPrivate = false
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { for tab in browser.tabs { tab.close() } }
        browser.newShyTab()
        let tab = browser.active!
        let id = tab.id
        let store = tab.store
        let address = URL(string: "https://private.example")!
        tab.setAddressOptimistically(address)
        let oldView = tab.web
        Shared.prefs.extensionsInPrivate = true
        XCTAssertTrue(tab.carriesExtensions)
        XCTAssertEqual(tab.id, id)
        XCTAssertTrue(tab.store === store)
        XCTAssertTrue(tab.web !== oldView)
        XCTAssertEqual(tab.address, address)
        Shared.prefs.extensionsInPrivate = false
        XCTAssertFalse(tab.carriesExtensions)
        XCTAssertTrue(tab.store === store)
        XCTAssertFalse(tab.store.isPersistent)
        XCTAssertEqual(tab.address, address)
    }

    func testSettingsPersist() {
        Shared.prefs.compactBookmarksBar = true
        XCTAssertTrue(Preferences().compactBookmarksBar)
        Shared.prefs.compactBookmarksBar = false
        XCTAssertFalse(Preferences().compactBookmarksBar)
        for mode in BookmarkBarOpening.allCases {
            Shared.prefs.bookmarkBarOpening = mode
            XCTAssertEqual(Preferences().bookmarkBarOpening, mode)
        }
    }
}
