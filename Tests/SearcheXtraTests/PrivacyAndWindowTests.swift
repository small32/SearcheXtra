import AppKit
import WebKit
import XCTest
@testable import SearcheXtra

@MainActor
final class PrivacyAndWindowTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "privacy-window-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
    }

    func testClosingLastBlankTabTargetsItsOwnWindow() throws {
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { browser.closeAll(); browser.dozing?.invalidate() }
        let window = CloseTrackingWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        browser.window = window
        let tab = try XCTUnwrap(browser.active)
        XCTAssertTrue(tab.isBlank)
        XCTAssertFalse(window.isKeyWindow)
        browser.close(tab)
        XCTAssertEqual(window.closeRequests, 1)
    }

    func testClosingLastBlankTabBesidePinsTargetsItsOwnWindow() throws {
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        let previous = browser.prefs.newTabAfterLast
        browser.prefs.newTabAfterLast = true
        defer { browser.prefs.newTabAfterLast = previous; browser.closeAll() }
        let window = CloseTrackingWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        browser.window = window
        let blank = try XCTUnwrap(browser.active)
        let pin = SearcheXtra.Tab()
        pin.restore(url: URL(string: "https://pin.example/")!, title: "Pinned")
        pin.pin = "P"
        browser.prepare(pin)
        browser.insert(pin, at: 0)
        browser.activeID = blank.id
        XCTAssertFalse(window.isKeyWindow)
        browser.close(blank)
        XCTAssertEqual(window.closeRequests, 1)
    }

    func testPDFSaveKeepsPrivateDownloadsOutOfTheSharedList() throws {
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        let previousFolder = browser.prefs.downloads
        let previousAsk = browser.prefs.asksWhereToSave
        let previousSpaces = browser.prefs.usesSpaces
        let previousKeeps = browser.loot.kept
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("search-private-pdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            // Adding the ordinary control download can evict the oldest item
            // from the shared fifty-entry list. Restore the whole snapshot.
            browser.loot.forgetAll()
            for keep in previousKeeps.reversed() { browser.loot.add(keep) }
            browser.prefs.downloads = previousFolder
            browser.prefs.asksWhereToSave = previousAsk
            browser.prefs.usesSpaces = previousSpaces
            browser.closeAll()
            browser.dozing?.invalidate()
            try? FileManager.default.removeItem(at: folder)
        }
        browser.prefs.usesSpaces = false
        browser.prefs.downloads = folder
        browser.prefs.asksWhereToSave = false
        let plain = try XCTUnwrap(browser.active)
        browser.newShyTab()
        let privately = try XCTUnwrap(browser.active)
        let data = Data("%PDF-1.7\nfixture".utf8)
        let source = URL(string: "https://private-pdf.example/document.pdf")!
        let before = browser.loot.kept
        browser.webView(privately.web, saveDataToFile: data, suggestedFilename: "private.pdf", mimeType: "application/pdf", originatingURL: source)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("private.pdf")), data)
        XCTAssertEqual(browser.loot.kept, before)
        browser.webView(plain.web, saveDataToFile: data, suggestedFilename: "ordinary.pdf", mimeType: "application/pdf", originatingURL: source)
        XCTAssertTrue(browser.loot.kept.contains { $0.path == folder.appendingPathComponent("ordinary.pdf").path && $0.from == "private-pdf.example" })
    }

    func testForgetChoicesClearsPrivateAndPersistentPermissions() {
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        let saved = Store.settings.dictionaryRepresentation().filter { $0.key.hasPrefix("capture.") || $0.key.hasPrefix(Grounded.prefix) }
        let transient = Browsers.all.map { ($0, $0.transientSitePermissions) }
        defer {
            for (key, value) in saved { Store.settings.set(value, forKey: key) }
            for (owner, permissions) in transient { owner.transientSitePermissions = permissions }
            browser.closeAll()
            browser.dozing?.invalidate()
        }
        let site = "https://\(UUID().uuidString).example"
        let camera = site + "|\(WKMediaCaptureType.camera.rawValue)"
        browser.transientSitePermissions[camera] = true
        browser.transientSitePermissions[site + "|location"] = false
        Store.settings.set(true, forKey: "capture." + camera)
        browser.forgetCaptureChoices()
        XCTAssertTrue(browser.transientSitePermissions.isEmpty)
        XCTAssertNil(Store.settings.object(forKey: "capture." + camera))
    }
}

private final class CloseTrackingWindow: NSWindow {
    var closeRequests = 0
    override func performClose(_ sender: Any?) { closeRequests += 1 }
}
