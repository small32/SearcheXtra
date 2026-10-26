import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class StartPageTests: XCTestCase {
    private var previousPage = ""
    private var previousSession: Session.Shape?
    private var browsers: [Browser] = []

    override func setUp() async throws {
        guard Store.testing else { throw XCTSkip("Run browser model tests with SEARCH_PROBE=interface-tests") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        previousPage = Shared.prefs.startPage
        // A fresh profile window now reads the profile's session files even
        // when it is made with an empty WindowRecord. Give every test an
        // empty first space instead of a row left by an earlier fixture.
        previousSession = Session.read(space: Space.firstID)
        Session.write(now: true, space: Space.firstID, .init(tabs: [], active: 0))
        Shared.prefs.startPage = ""
    }

    override func tearDown() async throws {
        guard Store.testing else { return }
        for browser in browsers { browser.closeAll() }
        browsers.removeAll()
        Disk.drain()
        if let previousSession {
            Session.write(now: true, space: Space.firstID, previousSession)
        }
        previousSession = nil
        Shared.prefs.startPage = previousPage
        XCTAssertTrue(NSApp.windows.allSatisfy { !$0.isVisible })
    }

    private func makeBrowser(record: WindowRecord = WindowRecord(), opensStartPage: Bool = true) -> Browser {
        let browser = Browser(record: record, opensStartPage: opensStartPage)
        browsers.append(browser)
        return browser
    }

    func testAddressesNormalizeAndRejectNonWebInputs() {
        XCTAssertEqual(StartPage.url(from: " example.com/path?q=1 \n")?.absoluteString, "https://example.com/path?q=1")
        XCTAssertEqual(StartPage.url(from: "localhost:8080/start")?.absoluteString, "http://localhost:8080/start")
        XCTAssertEqual(StartPage.url(from: "http://0.0.0.0:8080/")?.host(), "localhost")
        for input in ["", "   ", "search words", "https://", "javascript:alert(1)", "file:///tmp/start.html", "mailto:a@example.com", "https://example.com/\npath"] {
            XCTAssertNil(StartPage.url(from: input), input)
        }
    }

    func testPreferencePersistsAndClears() {
        Shared.prefs.startPage = "http://127.0.0.1:1/start"
        XCTAssertEqual(Preferences().startPageURL?.absoluteString, Shared.prefs.startPage)
        Shared.prefs.startPage = ""
        XCTAssertNil(Preferences().startPageURL)
    }

    func testFreshWindowUsesStartPageButNormalNewTabsStayBlank() {
        let url = "http://127.0.0.1:1/start"
        Shared.prefs.startPage = url
        let browser = makeBrowser()
        XCTAssertEqual(browser.active?.address?.absoluteString, url)
        let first = browser.activeID
        browser.newTab()
        XCTAssertNotEqual(browser.activeID, first)
        XCTAssertEqual(browser.active?.isBlank, true)
        XCTAssertNil(browser.active?.address)
        XCTAssertNil(browser.active?.pending)
        XCTAssertEqual(Shared.prefs.startPage, url)
        // The setting still applies to the first tab of another fresh window.
        let anotherWindow = makeBrowser()
        XCTAssertEqual(anotherWindow.active?.address?.absoluteString, url)
    }

    func testUnsetStartPageKeepsFreshWindowsAndNewTabsBlank() {
        let browser = makeBrowser()
        XCTAssertEqual(browser.active?.isBlank, true)
        browser.open(URL(string: "http://127.0.0.1:1/previous")!, foreground: true)
        browser.newTab()
        XCTAssertEqual(browser.active?.isBlank, true)
        XCTAssertNil(browser.active?.address)
        XCTAssertNil(browser.active?.pending)
    }

    func testPrivateTabsStayBlankAndClearingRestoresBlankNewTabs() {
        Shared.prefs.startPage = "http://127.0.0.1:1/start"
        let browser = makeBrowser()
        browser.newShyTab()
        browser.newTab()
        XCTAssertEqual(browser.active?.shy, true)
        XCTAssertEqual(browser.active?.isBlank, true)
        let plain = browser.tabs.first { !$0.shy }!
        browser.select(plain)
        Shared.prefs.startPage = ""
        browser.newTab()
        XCTAssertEqual(browser.active?.shy, false)
        XCTAssertEqual(browser.active?.isBlank, true)
    }

    func testNavigationMovesLeftOnceAndPreservesLaterChoices() {
        let keys = ["toolbar.left", "toolbar.leading-layout"]
        let previous = keys.map { Store.settings.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { Store.settings.set(value, forKey: key) }
                else { Store.settings.removeObject(forKey: key) }
            }
        }
        Store.settings.set(false, forKey: "toolbar.left")
        Store.settings.removeObject(forKey: "toolbar.leading-layout")
        let prefs = Preferences()
        XCTAssertTrue(prefs.navigationLeft)
        prefs.navigationLeft = false
        XCTAssertFalse(Preferences().navigationLeft)
    }

    func testHomeNavigatesCurrentTabWithoutAddingTabs() {
        let browser = makeBrowser()
        browser.open(URL(string: "http://127.0.0.1:1/previous")!, foreground: true)
        let id = browser.activeID
        let count = browser.tabs.count
        Shared.prefs.startPage = "http://127.0.0.1:1/home"
        browser.openHome()
        XCTAssertEqual(browser.activeID, id)
        XCTAssertEqual(browser.tabs.count, count)
        XCTAssertEqual(browser.active?.address?.absoluteString, Shared.prefs.startPage)
        Shared.prefs.startPage = ""
        browser.openHome()
        XCTAssertEqual(browser.activeID, id)
        XCTAssertEqual(browser.tabs.count, count)
        XCTAssertEqual(browser.active?.isBlank, true)
        XCTAssertNil(browser.active?.pending)
        XCTAssertEqual(browser.active?.title, "")
    }

    func testHomeKeepsPrivateTabPrivate() {
        let browser = makeBrowser()
        browser.newShyTab()
        let id = browser.activeID
        Shared.prefs.startPage = "http://127.0.0.1:1/home"
        browser.openHome()
        XCTAssertEqual(browser.activeID, id)
        XCTAssertEqual(browser.active?.shy, true)
        XCTAssertEqual(browser.active?.address?.absoluteString, Shared.prefs.startPage)
    }

    func testExplicitWindowPagesCanSkipStartPage() {
        Shared.prefs.startPage = "http://127.0.0.1:1/start"
        let browser = makeBrowser(opensStartPage: false)
        XCTAssertEqual(browser.active?.isBlank, true)
    }

    func testRestoredSessionKeepsItsOriginalPage() {
        Shared.prefs.startPage = "http://127.0.0.1:1/start"
        let restored = "http://127.0.0.1:1/previous"
        var record = WindowRecord()
        record.rows[record.space.uuidString] = Session.Shape(tabs: [
            Session.Entry(url: restored, title: "Previous", pin: nil, name: nil, home: nil)
        ], active: 0)
        let browser = makeBrowser(record: record)
        XCTAssertEqual((browser.active?.pending ?? browser.active?.address)?.absoluteString, restored)
    }
}
