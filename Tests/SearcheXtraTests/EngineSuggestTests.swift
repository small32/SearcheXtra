import AppKit
import WebKit
import XCTest
@testable import SearcheXtra

/// Settings › General › Suggestions from your search engine (idea 347).
@MainActor
final class EngineSuggestTests: XCTestCase {
    /// Shaped like a GitHub token, made up, and put together here so no
    /// secret scanner takes the file for one.
    private let fakeToken = "gh" + "p_" + "0000Fake1111Token2222Shape3333Only44"

    override class func setUp() {
        setenv("SEARCH_PROBE", "engine-suggest-\(getpid())", 1)
        super.setUp()
    }

    // MARK: - what each engine answers

    func testOpenSearchAnswersAreRead() {
        // Google's (client=firefox), with its extra members after the words.
        let google = #"["coffee",["coffee shop","coffee shop nantes","Coffee","coffee pot"],[],{"google:suggestsubtypes":[[512]]}]"#
        XCTAssertEqual(EngineSuggest.parse(Data(google.utf8), asked: "coffee"),
                       ["coffee shop", "coffee shop nantes", "coffee pot"])
        // DuckDuckGo's, Bing's, Ecosia's, Startpage's, Kagi's, Brave's, Qwant's.
        let plain = #"["café",["café","café del mar"," café au lait ","café del mar"]]"#
        XCTAssertEqual(EngineSuggest.parse(Data(plain.utf8), asked: "Café "), ["café del mar", "café au lait"])
    }

    func testSuggestionRowsHaveTheirOwnIdentity() throws {
        let url = try XCTUnwrap(Engine.url(for: "coffee shop", template: Engine.google.template(custom: "")))
        let local = Suggestion(key: "coffee shop", title: "Google", url: url, kind: .search)
        let remote = Suggestion(key: "coffee shop", title: "", url: url, kind: .suggested)
        XCTAssertNotEqual(local.id, remote.id)
    }

    func testAnswersAreCappedAtSix() {
        let many = #"["a",["a1","a2","a3","a4","a5","a6","a7","a8"]]"#
        XCTAssertEqual(EngineSuggest.parse(Data(many.utf8), asked: "a").count, 6)
    }

    func testAnythingElseIsNothing() {
        for junk in ["", "null", "{}", #"{"query":"x","suggestions":["y"]}"#, #"["x"]"#, #"["x","y"]"#,
                     #"["x",[1,2,{"a":1}]]"#, "<html>nope</html>", #"["x",["","  ","line\nbreak"]]"#] {
            XCTAssertEqual(EngineSuggest.parse(Data(junk.utf8), asked: "x"), [], junk)
        }
        let long = String(repeating: "x", count: 300)
        XCTAssertEqual(EngineSuggest.parse(Data(#"["x",["\#(long)"]]"#.utf8), asked: "x"), [])
    }

    func testEveryEngineButCustomHasAnHTTPSAddress() throws {
        for engine in Engine.allCases {
            guard engine != .custom else {
                XCTAssertNil(EngineSuggest.endpoint(for: engine))
                XCTAssertNil(EngineSuggest.url(for: "coffee", engine: engine))
                continue
            }
            let url = try XCTUnwrap(EngineSuggest.url(for: "café crème", engine: engine), engine.title)
            XCTAssertEqual(url.scheme, "https", engine.title)
            XCTAssertTrue(url.absoluteString.contains("caf%C3%A9%20cr%C3%A8me"), url.absoluteString)
        }
        XCTAssertEqual(EngineSuggest.url(for: "a&b", engine: .google)?.absoluteString,
                       "https://suggestqueries.google.com/complete/search?client=firefox&q=a%26b")
        XCTAssertEqual(EngineSuggest.url(for: "x y", engine: .qwant)?.absoluteString,
                       "https://api.qwant.com/api/suggest/?q=x%20y&client=opensearch")
    }

    func testOnlyHTTPSOrATestRunsLoopback() {
        XCTAssertNotNil(EngineSuggest.url(for: "a", engine: .google, test: "http://127.0.0.1:9/s?q=%s"))
        XCTAssertNotNil(EngineSuggest.url(for: "a", engine: .google, test: "http://localhost:9/s?q=%s"))
        XCTAssertNil(EngineSuggest.url(for: "a", engine: .google, test: "http://example.com/s?q=%s"))
        XCTAssertNil(EngineSuggest.url(for: "a", engine: .google, test: "ftp://127.0.0.1/s?q=%s"))
        XCTAssertNil(EngineSuggest.url(for: "a", engine: .google, test: "file:///tmp/%s"))
    }

    // MARK: - what may leave the Mac

    func testPlainWordsAreSent() {
        for words in ["coffee", "coffee shop near me", "café crème", "iphone 15 pro", "how to tie a tie",
                      "what is node.js", "c++ tutorial", "東京 天気", "上海 天气", "咖啡店", "re: meeting notes", "10:30 train"] {
            XCTAssertTrue(EngineSuggest.sendable(words), words)
        }
    }

    func testAddressesAreNeverSent() {
        for address in ["https://example.com", "http://x", "example.com", "www.apple.com/mac", "localhost",
                        "localhost:3000", "127.0.0.1", "192.168.1.1:8080", "[::1]:3000", "mailto:me@x.com",
                        "javascript:alert(1)", "about:blank", "data:text/html,x", "file:///etc/hosts",
                        "node.js", "a/b", "foo.bar", "ftp://files", "chrome-extension://abc"] {
            XCTAssertFalse(EngineSuggest.sendable(address), address)
        }
    }

    func testPathsAreNeverSent() {
        for path in ["/Users/drice/Documents/taxes.pdf", "~/Desktop", "./build.sh", "../secret",
                     "C:\\Users\\x", "src/main.swift"] {
            XCTAssertFalse(EngineSuggest.sendable(path), path)
        }
    }

    func testSecretsAndPersonalDetailsAreNeverSent() {
        for secret in ["hunter2hunter2x", "sk-proj-4f9aX2kQ7", fakeToken,
                       "AKIAIOSFODNN7EXAMPLE", "correcthorsebatterystaplecorrecthorse",
                       "4111111111111111", "4111-1111-1111-1111", "my password is Tr0ub4dor&3xyzzy",
                       "drice@officecommun.com", "write to me@example.org", "line one\nline two",
                       String(repeating: "word ", count: 17)] {
            XCTAssertFalse(EngineSuggest.sendable(secret), secret)
        }
    }

    func testEmptyIsNeverSent() {
        for blank in ["", " ", "\n", "\t "] { XCTAssertFalse(EngineSuggest.sendable(blank)) }
    }

    // MARK: - when the field asks

    func testTheFieldAsksOnlyWhenOnAndNeverInPrivate() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer {
            browser.prefs.engineSuggests = false
            browser.closeAll()
        }
        browser.prefs.engine = .duckduckgo
        browser.prefs.engineSuggests = false
        XCTAssertNil(browser.engineQuestion(for: "coffee"), "off by default: nothing asked")

        browser.prefs.engineSuggests = true
        let question = try XCTUnwrap(browser.engineQuestion(for: "coffee"))
        XCTAssertEqual(question.host(), "duckduckgo.com")
        XCTAssertNil(browser.engineQuestion(for: "example.com"))
        XCTAssertNil(browser.engineQuestion(for: fakeToken))

        browser.prefs.engine = .custom
        XCTAssertNil(browser.engineQuestion(for: "coffee"), "a custom engine has nowhere to ask")
        browser.prefs.engine = .duckduckgo

        browser.newShyTab()
        XCTAssertEqual(browser.active?.shy, true)
        XCTAssertNil(browser.engineQuestion(for: "coffee"), "a private tab never asks")
    }

    func testAKeywordIsNotAskedAbout() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let kept = browser.prefs.keywords
        defer {
            browser.prefs.keywords = kept
            browser.prefs.engineSuggests = false
            browser.closeAll()
        }
        browser.prefs.engineSuggests = true
        browser.prefs.engine = .google
        browser.prefs.keywords = [Keyword(keyword: "yt", template: "https://www.youtube.com/results?search_query=%s")]
        XCTAssertNil(browser.engineQuestion(for: "yt cats"), "a shortcut's words go to its site, not the engine")
        XCTAssertNotNil(browser.engineQuestion(for: "cats"))
    }

    func testAddressFieldUsesTheSelectedTabsPrivacyAndNeverRenames() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer {
            browser.prefs.engineSuggests = false
            browser.closeAll()
        }
        browser.prefs.engine = .duckduckgo
        browser.prefs.engineSuggests = true
        let ordinary = try XCTUnwrap(browser.active)
        browser.newShyTab()
        let shy = try XCTUnwrap(browser.active)
        XCTAssertTrue(shy.shy)

        // An address request selects its tab before the shared field asks
        // for suggestions, so a private page never sends search words.
        browser.beginTabEdit(ordinary)
        XCTAssertNotNil(browser.engineQuestion(for: "上海 天气"))
        XCTAssertNil(browser.engineQuestion(for: "example.com"))
        XCTAssertNil(browser.engineQuestion(for: fakeToken))

        browser.select(ordinary)
        browser.beginTabEdit(shy)
        XCTAssertNil(browser.engineQuestion(for: "coffee"))
        browser.beginTabRename(ordinary)
        XCTAssertNil(browser.engineQuestion(for: "coffee"))
        browser.cancelTabEdit()
        browser.prefs.engineSuggests = false
        XCTAssertNil(browser.engineQuestion(for: "coffee"))
    }

    func testAddressFieldCancellationAndTurningOffStopPendingQuestions() async throws {
        _ = NSApplication.shared
        let oldEndpoint = Store.settings.object(forKey: "suggest.testURL")
        Store.settings.set("http://127.0.0.1:9/s?q=%s", forKey: "suggest.testURL")
        let browser = Browser(record: WindowRecord())
        defer {
            browser.prefs.engineSuggests = false
            browser.closeAll()
            if let oldEndpoint { Store.settings.set(oldEndpoint, forKey: "suggest.testURL") }
            else { Store.settings.removeObject(forKey: "suggest.testURL") }
        }
        browser.prefs.engineSuggests = true
        let tab = try XCTUnwrap(browser.active)
        tab.go(to: URL(string: "http://127.0.0.1:9/address-fixture")!)
        let asked = browser.suggester.asked
        let cancelled = browser.suggester.cancelled
        browser.beginTabEdit(tab)
        browser.typed = "coffee"
        browser.dismiss()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(browser.suggester.asked, asked, "a cancelled debounce sends nothing")
        XCTAssertGreaterThan(browser.suggester.cancelled, cancelled)
        XCTAssertTrue(browser.offers.isEmpty)

        browser.beginTabEdit(tab)
        browser.typed = "tea"
        browser.prefs.engineSuggests = false
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(browser.suggester.asked, asked, "turning off cancels before the pause ends")
        XCTAssertFalse(browser.offers.contains { $0.kind == .suggested })
        XCTAssertNil(browser.engineQuestion(for: "tea"))
    }


    func testOldNameFieldFocusLossCannotCloseAReopenedRename() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let tab = try XCTUnwrap(browser.active)
        browser.beginTabRename(tab)
        let oldField = TabNameField.Coordinator(browser: browser)
        oldField.focusRequest = browser.focusRequest
        oldField.focusedRequest = browser.focusRequest
        let ended = Notification(name: NSControl.textDidEndEditingNotification)
        oldField.controlTextDidEndEditing(ended)
        // Reopen before the queued end-edit callback is delivered.
        browser.beginTabRename(tab)
        let newRequest = browser.focusRequest
        // SwiftUI may already have scheduled the replacement field's focus.
        oldField.focusRequest = newRequest
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(browser.editingTab, tab.id)
        XCTAssertEqual(browser.focusRequest, newRequest)

        // A removed field can also report its focus loss only after the
        // replacement has already appeared.
        oldField.controlTextDidEndEditing(ended)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(browser.editingTab, tab.id)
    }


    func testDelayedFocusLossCannotDismissTheCurrentNameEditor() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        browser.window = window
        let tab = try XCTUnwrap(browser.active)
        browser.beginTabRename(tab)
        let coordinator = TabNameField.Coordinator(browser: browser)
        coordinator.focusRequest = browser.focusRequest
        coordinator.focusedRequest = browser.focusRequest
        let field = TabNameField.Field(frame: NSRect(x: 20, y: 20, width: 320, height: 22))
        field.delegate = coordinator
        try XCTUnwrap(window.contentView).addSubview(field)
        defer {
            browser.closeAll()
            window.close()
        }
        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertNotNil(field.currentEditor())
        coordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(browser.editingTab, tab.id)
        XCTAssertTrue(window.firstResponder === field.currentEditor())
        XCTAssertFalse(window.isVisible)
    }

}
