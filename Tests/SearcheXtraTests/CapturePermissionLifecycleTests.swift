import AppKit
import WebKit
import XCTest
@testable import SearcheXtra

@MainActor
final class CapturePermissionLifecycleTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "capture-lifecycle-\(getpid())", 1)
        Store.settings.set("zh-Hans", forKey: "interface.language")
        super.setUp()
    }

    func testVisiblePermissionsEndWithTheirSource() async throws {
        for kind in ["camera", "location", "notifications"] {
            for event in ["switch", "navigate", "close", "crash", "discard", "replace", "window"] {
                let (browser, tab, frame) = try await fixture()
                var replies: [Bool] = []
                request(kind, in: browser, tab: tab, frame: frame) { replies.append($0) }
                XCTAssertEqual(browser.asking?.wants, kind)
                switch event {
                case "switch": browser.newTab()
                case "navigate": browser.webView(tab.web, didStartProvisionalNavigation: nil)
                case "close": browser.close(tab)
                case "crash": browser.webViewWebContentProcessDidTerminate(tab.web)
                case "discard": tab.rest()
                case "replace": browser.replace(tab, going: URL(string: "about:blank")!)
                default: browser.closeAll()
                }
                XCTAssertEqual(replies, [false], "\(kind): \(event)")
                XCTAssertNil(browser.asking, "\(kind): \(event)")
                browser.cancelCapture()
                browser.closeAll()
                XCTAssertEqual(replies, [false], "A request must be answered only once")
            }
        }
    }

    func testWaitingRequestCannotOutliveItsTabOrDocument() async throws {
        for event in ["select", "rapid-switch", "navigate", "close", "move"] {
            let (browser, tab, frame) = try await fixture()
            browser.newTab()
            let other = try XCTUnwrap(browser.active)
            var replies: [Bool] = []
            request("camera", in: browser, tab: tab, frame: frame) { replies.append($0) }
            XCTAssertNil(browser.asking)
            switch event {
            case "select": browser.select(tab)
            case "rapid-switch": browser.select(tab); browser.select(other)
            case "navigate": browser.webView(tab.web, didStartProvisionalNavigation: nil)
            case "close": browser.close(tab)
            default:
                let destination = Browser(record: WindowRecord())
                browser.moveToWindow(tab, destination)
                destination.closeAll()
            }
            try await Task.sleep(nanoseconds: 150_000_000)
            if event == "select" {
                XCTAssertEqual(browser.asking?.wants, "camera")
                XCTAssertTrue(replies.isEmpty)
            } else {
                XCTAssertNil(browser.asking, event)
                XCTAssertEqual(replies, [false], event)
            }
            XCTAssertTrue(browser.heldDialogs[tab.id]?.isEmpty ?? true)
            browser.closeAll()
            XCTAssertEqual(replies, [false], event)
        }
    }

    func testPrivatePeekDoesNotReadOrWritePersistentPermissions() async throws {
        let (browser, parent, _) = try await fixture(shy: true)
        defer { browser.closeAll() }
        browser.peek(URL(string: "about:blank")!, from: parent)
        let peek = try XCTUnwrap(browser.peekTab)
        let frame = try await loadFrame(in: peek)
        XCTAssertFalse(peek.store.isPersistent)
        XCTAssertNil(browser.tab(for: peek.web))
        let origin = frame.securityOrigin
        let site = "\(origin.protocol)://\(origin.host)" + (origin.port == 0 ? "" : ":\(origin.port)")
        let key = "capture.\(site)|\(WKMediaCaptureType.microphone.rawValue)"
        defer { Store.settings.removeObject(forKey: key) }
        Store.settings.set(true, forKey: key)
        var replies: [WKPermissionDecision] = []
        browser.askedForCapture(peek.web, origin: frame.securityOrigin, frame: frame, type: .microphone) { replies.append($0) }
        XCTAssertTrue(replies.isEmpty, "A private peek must not reuse an ordinary permission")
        XCTAssertEqual(browser.asking?.wants, "microphone")
        browser.cancelCapture()
        XCTAssertEqual(replies, [.deny])
        Store.settings.removeObject(forKey: key)
        browser.askedForCapture(peek.web, origin: frame.securityOrigin, frame: frame, type: .microphone) { replies.append($0) }
        try await Task.sleep(nanoseconds: 550_000_000)
        browser.allowCapture()
        XCTAssertEqual(replies, [.deny, .grant])
        XCTAssertNil(Store.settings.object(forKey: key), "A private permission must leave no site on disk")
        browser.askedForCapture(peek.web, origin: frame.securityOrigin, frame: frame, type: .microphone) { replies.append($0) }
        browser.closePeek()
        XCTAssertNil(browser.asking)
        XCTAssertEqual(replies, [.deny, .grant, .deny])
    }

    func testOtherPageNavigationDoesNotCancelAndReplyCanAskAgain() async throws {
        let (browser, tab, frame) = try await fixture()
        defer { browser.closeAll() }
        let other = WKWebView(frame: .zero)
        var first: [Bool] = [], next: [Bool] = []
        request("camera", in: browser, tab: tab, frame: frame) { answer in
            first.append(answer)
            self.request("camera", in: browser, tab: tab, frame: frame) { next.append($0) }
        }
        browser.webView(other, didStartProvisionalNavigation: nil)
        XCTAssertTrue(first.isEmpty)
        XCTAssertEqual(browser.asking?.wants, "camera")
        browser.cancelCapture(for: tab.web)
        XCTAssertEqual(first, [false])
        XCTAssertTrue(next.isEmpty)
        XCTAssertEqual(browser.asking?.wants, "camera")
        browser.cancelCapture(for: tab.web)
        XCTAssertEqual(next, [false])
    }

    func testChineseInterfaceKeepsPermissionKindsUntranslated() async throws {
        let (browser, tab, frame) = try await fixture()
        let oldLanguage = LanguageSettings.shared.selection
        defer { LanguageSettings.shared.selection = oldLanguage; browser.closeAll() }
        LanguageSettings.shared.selection = .simplifiedChinese
        XCTAssertTrue(L10n.isChinese, "Run regression classes in isolated processes with run-macos-regressions.sh")
        let cases: [(WKMediaCaptureType, String)] = [(.camera, "camera"), (.microphone, "microphone"), (.cameraAndMicrophone, "cameraAndMicrophone")]
        for (kind, token) in cases {
            browser.askedForCapture(tab.web, origin: frame.securityOrigin, frame: frame, type: kind) { _ in }
            XCTAssertEqual(browser.asking?.wants, token)
            browser.cancelCapture()
        }
    }

    func testScreenReplyCanStartACameraQuestion() async throws {
        let (browser, tab, frame) = try await fixture()
        defer { browser.closeAll() }
        var screen: [Int] = [], camera: [Bool] = []
        browser.askedToShareScreen(tab.web, origin: frame.securityOrigin, frame: frame, systemAudio: false) { answer in
            screen.append(answer)
            self.request("camera", in: browser, tab: tab, frame: frame) { camera.append($0) }
        }
        browser.cancelCapture(for: tab.web)
        XCTAssertEqual(screen, [0])
        XCTAssertTrue(camera.isEmpty)
        XCTAssertEqual(browser.asking?.wants, "camera")
        browser.cancelCapture(for: tab.web)
        XCTAssertEqual(camera, [false])
    }

    func testLastWindowCloseSettlesThePendingPermission() async throws {
        let (browser, tab, frame) = try await fixture()
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        browser.window = window
        Browsers.register(browser)
        defer { browser.closeAll(); browser.window = nil }
        var replies: [Bool] = []
        request("camera", in: browser, tab: tab, frame: frame) { replies.append($0) }
        Browsers.closing(window)
        XCTAssertTrue(browser.shut)
        XCTAssertNil(browser.asking)
        XCTAssertEqual(replies, [false])
    }

    func testExtensionPanelNavigationCancelsOnlyItsOwnQuestion() async throws {
        let (browser, tab, frame) = try await fixture()
        defer { browser.closeAll() }
        let url = try XCTUnwrap(tab.web.url)
        let panel = ExtensionPanelDelegate(browser: browser, base: url, first: url)
        var replies: [Bool] = []
        request("camera", in: browser, tab: tab, frame: frame) { replies.append($0) }
        panel.webView(WKWebView(frame: .zero), didStartProvisionalNavigation: nil)
        XCTAssertTrue(replies.isEmpty)
        panel.webView(tab.web, didStartProvisionalNavigation: nil)
        XCTAssertEqual(replies, [false])
        XCTAssertNil(browser.asking)
        browser.cancelCapture()
        XCTAssertEqual(replies, [false])
    }

    private func request(_ kind: String, in browser: Browser, tab: Tab, frame: WKFrameInfo, reply: @escaping (Bool) -> Void) {
        if kind == "notifications" {
            browser.askedForNotifications(tab.web, origin: frame.securityOrigin, decisionHandler: reply)
        } else if kind == "location" {
            browser.askedForLocation(tab.web, origin: frame.securityOrigin, frame: frame) { reply($0 == .grant) }
        } else {
            browser.askedForCapture(tab.web, origin: frame.securityOrigin, frame: frame, type: .camera) { reply($0 == .grant) }
        }
    }

    private func fixture(shy: Bool = false) async throws -> (Browser, Tab, WKFrameInfo) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        XCTAssertTrue(Store.testing)
        let browser = Browser(record: WindowRecord())
        browser.forgetCaptureChoices()
        browser.prefs.siteNotifications = true
        let tab = Tab(shy: shy)
        browser.prepare(tab)
        browser.insert(tab, at: browser.tabs.count)
        browser.select(tab)
        return (browser, tab, try await loadFrame(in: tab))
    }

    private func loadFrame(in tab: Tab) async throws -> WKFrameInfo {
        let receiver = CaptureFrameReceiver()
        let controller = tab.web.configuration.userContentController
        controller.add(receiver, name: "captureFixture")
        defer { controller.removeScriptMessageHandler(forName: "captureFixture") }
        tab.web.loadHTMLString("<script>webkit.messageHandlers.captureFixture.postMessage('ready')</script>",
                               baseURL: URL(string: "https://capture.example/"))
        for _ in 0..<200 {
            if let frame = receiver.frame { return frame }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw NSError(domain: "CapturePermissionLifecycleTests", code: 1)
    }
}

@MainActor
private final class CaptureFrameReceiver: NSObject, WKScriptMessageHandler {
    var frame: WKFrameInfo?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        frame = message.frameInfo
    }
}
