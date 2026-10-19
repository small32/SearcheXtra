import AppKit
import WebKit
import XCTest
@testable import SearcheXtra

@MainActor
final class SidePanelDownloadTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "side-panel-download-\(getpid())", 1)
        super.setUp()
    }

    func testDownloadLinksAndAttachmentsUseTheBrowserDownloadLifecycle() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let fixture = try LocalDownloadServer(size: 64 * 1024)
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let oldFolder = browser.prefs.downloads, oldAsk = browser.prefs.asksWhereToSave
        browser.prefs.downloads = folder
        browser.prefs.asksWhereToSave = false
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 700, height: 500), configuration: configuration)
        // A loopback page stands in for an extension's own origin so the
        // shipping panel delegate can be exercised without store access.
        let delegate = ExtensionPanelDelegate(browser: browser, base: fixture.url("/"), first: fixture.url("/page"))
        web.navigationDelegate = delegate
        web.uiDelegate = delegate
        let window = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        browser.window = window
        defer {
            for entry in browser.fetches.entries { browser.cancelDownload(entry) }
            web.stopLoading()
            web.navigationDelegate = nil
            web.uiDelegate = nil
            browser.closeAll()
            window.contentView = nil
            window.close()
            browser.prefs.downloads = oldFolder
            browser.prefs.asksWhereToSave = oldAsk
            fixture.stop()
            try? FileManager.default.removeItem(at: folder)
        }

        for (index, path) in ["/panel-link.bin", "/panel-attachment.bin"].enumerated() {
            web.load(URLRequest(url: fixture.url("/page")))
            try await until { web.url == fixture.url("/page") && !web.isLoading }
            let before = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
            if index == 0 {
                _ = try await web.evaluateJavaScript("""
                const link = document.createElement('a');
                link.href = '\(path)'; link.download = 'panel.bin';
                document.body.appendChild(link); link.click(); true;
                """)
            } else {
                web.load(URLRequest(url: fixture.url(path)))
            }
            try await until {
                let names = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                let files = names.subtracting(before)
                return files.count == 1 && files.allSatisfy {
                    (try? Data(contentsOf: folder.appendingPathComponent($0)).count) == 64 * 1024
                } && browser.downloading.isEmpty
            }
            XCTAssertGreaterThan(fixture.count(path), 0)
            XCTAssertTrue(browser.fetches.entries.isEmpty)
            XCTAssertFalse(window.isVisible)
        }
    }

    private func until(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for the side-panel download")
        throw URLError(.timedOut)
    }
}
