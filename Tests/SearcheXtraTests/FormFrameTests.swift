import AppKit
import WebKit
import XCTest
@testable import SearcheXtra

@MainActor
final class FormFrameTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "form-frames-\(getpid())", 1)
        super.setUp()
    }

    func testCrossOriginFrameSubmissionIsSavedForItsOwnHost() async throws {
        guard Store.testing else { throw XCTSkip("Needs a probe data store") }
        _ = NSApplication.shared
        let server = try LocalPageServer([
            "/top": .init(type: "text/html", body: """
                <title>Top</title><iframe id=f></iframe>
                <script>f.src='http://localhost:'+location.port+'/login'</script>
                """),
            "/login": .init(type: "text/html", body: """
                <form onsubmit="event.preventDefault();this.remove()">
                <input name=username value=frame-user><input type=password value=frame-secret>
                <button>Sign in</button></form>
                <script>setTimeout(()=>document.querySelector('form').requestSubmit(),800)</script>
                """)
        ])
        let tab = SearcheXtra.Tab()
        defer { tab.close(); server.stop() }
        let offered = expectation(description: "frame credentials offered")
        tab.onCredentials = { _, host, user, password, clear in
            XCTAssertEqual(host, "localhost")
            XCTAssertEqual(user, "frame-user")
            XCTAssertEqual(password, "frame-secret")
            XCTAssertTrue(clear)
            offered.fulfill()
        }
        tab.go(to: server.url("/top"))
        await fulfillment(of: [offered], timeout: 8)
    }

    func testAccountListIsReboundWhenFocusMovesBetweenSameOriginFrames() async throws {
        guard Store.testing else { throw XCTSkip("Needs a probe data store") }
        _ = NSApplication.shared
        let user = "frame-list-\(UUID().uuidString)"
        guard Vault.save(host: "127.0.0.1", user: user, password: "fixture", clear: true) else {
            throw XCTSkip("The test process cannot write its keychain")
        }
        defer { Vault.forget(host: "127.0.0.1", user: user, clear: true) }
        let server = try LocalPageServer([
            "/top": .init(type: "text/html", body: "<title>Top</title><iframe src='/login'></iframe><iframe src='/login'></iframe>"),
            "/login": .init(type: "text/html", body: "<form><input id=user autocomplete=username><input type=password></form>")
        ])
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        defer { browser.closeAll(); server.stop() }
        let tab = try XCTUnwrap(browser.active)
        tab.go(to: server.url("/top"))
        let until = Date().addingTimeInterval(5)
        while tab.title != "Top" || tab.web.isLoading {
            guard Date() < until else { return XCTFail("Page did not load") }
            try await Task.sleep(for: .milliseconds(20))
        }
        _ = try await tab.web.callAsyncJavaScript("frames[0].document.getElementById('user').focus();", contentWorld: Web.world)
        while browser.suggesting?.logins.contains(where: { $0.user == user }) != true {
            guard Date() < until else { return XCTFail("Account list did not appear") }
            try await Task.sleep(for: .milliseconds(20))
        }
        let first = try XCTUnwrap(browser.suggesting?.formID)
        _ = try await tab.web.callAsyncJavaScript("frames[1].document.getElementById('user').focus();", contentWorld: Web.world)
        while tab.formID == first {
            guard Date() < until else { return XCTFail("Frame focus did not change") }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(browser.suggesting?.formID, tab.formID)
        XCTAssertNotEqual(browser.suggesting?.formID, first)
    }

    func testFillTargetsTheFocusedFrameAndRejectsAReplacedDocument() async throws {
        guard Store.testing else { throw XCTSkip("Needs a probe data store") }
        _ = NSApplication.shared
        let server = try LocalPageServer([
            "/top": .init(type: "text/html", body: """
                <title>Top</title><form><input id=top-user><input id=top-pass type=password></form>
                <iframe src='/login'></iframe>
                """),
            "/login": .init(type: "text/html", body: """
                <form><input id=user autocomplete=username><input id=pass type=password></form>
                <script>setTimeout(()=>document.getElementById('user').focus(),800)</script>
                """)
        ])
        let tab = SearcheXtra.Tab()
        defer { tab.close(); server.stop() }
        tab.go(to: server.url("/top"))
        let until = Date().addingTimeInterval(5)
        while tab.formSource?.frame == nil && Date() < until { try await Task.sleep(for: .milliseconds(20)) }
        let source = try XCTUnwrap(tab.formSource)
        let frame = try XCTUnwrap(source.frame)
        let filled = expectation(description: "frame filled")
        tab.fill(user: "chosen-user", password: "chosen-secret", onlyOn: source.url) { worked in
            XCTAssertTrue(worked); filled.fulfill()
        }
        await fulfillment(of: [filled], timeout: 2)
        let top = try await tab.web.callAsyncJavaScript("return document.getElementById('top-pass').value", contentWorld: Web.world)
        XCTAssertEqual(top as? String, "")
        let child = try await tab.web.callAsyncJavaScript("return document.getElementById('pass').value", in: frame, contentWorld: Web.world)
        XCTAssertEqual(child as? String, "chosen-secret")

        _ = try await tab.web.callAsyncJavaScript("window.__officeForms.document='another-document';", in: frame, contentWorld: Web.world)
        let refused = expectation(description: "stale field refused")
        tab.fill(user: "other", password: "other", onlyOn: source.url) { worked in
            XCTAssertFalse(worked); refused.fulfill()
        }
        await fulfillment(of: [refused], timeout: 2)
    }
}
