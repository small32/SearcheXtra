import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class SettingsSiteControlTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "settings-site-\(getpid())", 1)
        super.setUp()
    }

    func testSettingsKeepsTheWebsiteThatOpenedItAndDropsClosedTargets() throws {
        guard Store.testing else { throw XCTSkip("Requires an isolated test store") }
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { browser.closeAll() }
        let website = try XCTUnwrap(browser.active)
        website.restore(url: URL(string: "https://control.example/page")!, title: "Website")
        let settings = browser.show(InternalPage(.settings, "privacy"))
        XCTAssertTrue(browser.active === settings)
        XCTAssertNil(browser.hereHost)
        let target = try XCTUnwrap(SettingsPanel.shieldTarget(in: browser))
        XCTAssertTrue(target.tab === website)
        XCTAssertEqual(target.host, "control.example")
        browser.close(website)
        XCTAssertNil(SettingsPanel.shieldTarget(in: browser))
    }

    func testReopeningSettingsFromAnotherWebsiteChangesItsSiteContext() throws {
        guard Store.testing else { throw XCTSkip("Requires an isolated test store") }
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { browser.closeAll() }
        let first = try XCTUnwrap(browser.active)
        first.restore(url: URL(string: "https://first.example/")!, title: "First")
        let settings = browser.show(InternalPage(.settings))
        browser.newTab()
        let second = try XCTUnwrap(browser.active)
        second.restore(url: URL(string: "https://second.example/")!, title: "Second")
        XCTAssertTrue(browser.show(InternalPage(.settings, "privacy")) === settings)
        XCTAssertTrue(SettingsPanel.shieldTarget(in: browser)?.tab === second)
        XCTAssertEqual(SettingsPanel.shieldTarget(in: browser)?.host, "second.example")
    }

    func testOldSiteControlCannotReloadOrChangeANavigatedPage() throws {
        guard Store.testing else { throw XCTSkip("Requires an isolated test store") }
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        let host = "shield-\(UUID().uuidString.lowercased()).example"
        let previous = Shield.shared.isPaused(on: host)
        defer { browser.closeAll(); Shield.shared.pause(host, previous) }
        let website = try XCTUnwrap(browser.active)
        website.restore(url: URL(string: "https://\(host)/")!, title: "First")
        browser.show(InternalPage(.settings, "privacy"))
        let oldControl = try XCTUnwrap(SettingsPanel.shieldTarget(in: browser))
        website.restore(url: URL(string: "https://another.example/")!, title: "Another")
        SettingsPanel.setShield(previous, for: oldControl.tab, host: oldControl.host, in: browser)
        XCTAssertEqual(Shield.shared.isPaused(on: host), previous)
        XCTAssertNil(website.built, "A stale control must not reload the replacement page")
    }
}
