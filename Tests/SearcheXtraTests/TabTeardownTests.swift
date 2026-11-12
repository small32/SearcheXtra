import AppKit
import WebKit
import XCTest
@testable import SearcheXtra

@MainActor
final class TabTeardownTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "tab-teardown-\(getpid())", 1)
        super.setUp()
    }

    func testClosingRenamedTabClearsEditorAndAnswersQuestionsOnce() throws {
        let browser = try makeBrowser()
        let layout = browser.prefs.tabsLayout
        browser.prefs.tabsLayout = .top
        defer { browser.closeAll(); browser.prefs.tabsLayout = layout }
        let tab = try XCTUnwrap(browser.active)
        let web = tab.web
        let other = Tab(configuration: Web.configuration(space: browser.spaceID))
        browser.prepare(other)
        browser.insert(other, at: browser.tabs.count)
        browser.select(other)
        var shown = 0, dropped = 0, answers: [Bool] = []
        let held = try XCTUnwrap(browser.ask(from: web, show: { shown += 1 }, drop: { dropped += 1 }))
        let question = PaneQuestion(tab: tab.id, host: "fixture.test", message: "Leave?", kind: .confirm) { ok, _ in
            answers.append(ok)
        }
        browser.paneQuestions.append(question)
        browser.beginTabRename(tab)
        browser.tabDraft = "Uncommitted name"
        XCTAssertEqual(browser.editingTab, tab.id)
        XCTAssertTrue(browser.renamingTab)

        browser.close(tab)

        XCTAssertFalse(browser.tabs.contains { $0 === tab })
        assertNoEditor(browser)
        XCTAssertNil(tab.name, "Closing must discard the unfinished rename")
        XCTAssertNil(tab.built)
        XCTAssertNil(web.navigationDelegate)
        XCTAssertNil(web.uiDelegate)
        XCTAssertNil(tab.onLink)
        XCTAssertNil(browser.heldDialogs[tab.id])
        XCTAssertFalse(browser.paneQuestions.contains { $0.tab == tab.id })
        XCTAssertEqual(shown, 0)
        XCTAssertEqual(dropped, 1)
        XCTAssertEqual(answers, [false])
        held.dismiss()
        question.answer(ok: true)
        browser.close(tab)
        XCTAssertEqual(dropped, 1)
        XCTAssertEqual(answers, [false])
    }

    func testRemovedPinFinishesItsEditorsQuestionsAndSplit() throws {
        let browser = try makeBrowser()
        let saved = (browser.prefs.tabsLayout, browser.prefs.splitView, browser.prefs.sharesPins)
        browser.prefs.tabsLayout = .top
        browser.prefs.splitView = true
        browser.prefs.sharesPins = false
        defer {
            browser.closeAll()
            browser.prefs.tabsLayout = saved.0
            browser.prefs.splitView = saved.1
            browser.prefs.sharesPins = saved.2
        }
        let gone = try XCTUnwrap(browser.active)
        let web = gone.web
        let kept = Tab(configuration: Web.configuration(space: browser.spaceID))
        browser.prepare(kept)
        browser.insert(kept, at: browser.tabs.count)
        browser.pair(gone, with: kept, onLeft: true)
        XCTAssertNotNil(browser.split(for: gone))
        browser.select(kept)
        // Reconciliation also accepts rows restored from disk, including a
        // pin that belonged to a split in an older session.
        gone.pin = "P"
        gone.pinID = UUID()
        var dropped = 0, answers: [Bool] = []
        let held = try XCTUnwrap(browser.ask(from: web, show: { XCTFail("Removed pin must not show a dialog") },
                                             drop: { dropped += 1 }))
        let question = PaneQuestion(tab: gone.id, host: "fixture.test", message: "Leave?", kind: .confirm) { ok, _ in
            answers.append(ok)
        }
        browser.paneQuestions.append(question)
        browser.beginTabRename(gone)
        browser.tabDraft = "Uncommitted name"
        browser.editLetter(gone)

        let row = browser.reconcilePins(browser.tabs, space: UUID())

        XCTAssertFalse(row.contains { $0 === gone })
        XCTAssertTrue(row.contains { $0 === kept })
        assertNoEditor(browser)
        XCTAssertNil(browser.editingPin)
        XCTAssertNil(browser.split(for: gone))
        XCTAssertNil(gone.built)
        XCTAssertNil(web.navigationDelegate)
        XCTAssertNil(browser.heldDialogs[gone.id])
        XCTAssertFalse(browser.paneQuestions.contains { $0.tab == gone.id })
        XCTAssertEqual(dropped, 1)
        XCTAssertEqual(answers, [false])
        held.dismiss()
        question.answer(ok: true)
        XCTAssertEqual(dropped, 1)
        XCTAssertEqual(answers, [false])
    }

    func testLatePinFieldCompletionCannotEndAnotherPinsEdit() async throws {
        let browser = try makeBrowser()
        defer { browser.closeAll() }
        let first = Tab(), second = Tab()
        first.pin = "A"
        second.pin = "B"
        let field = NSTextField()
        let old = PinField.Coordinator(browser: browser, tab: first)
        browser.editLetter(first)
        old.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        browser.editLetter(second)
        await drainMainQueue()
        XCTAssertEqual(browser.editingPin, second.id)

        let current = PinField.Coordinator(browser: browser, tab: second)
        current.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        await drainMainQueue()
        XCTAssertNil(browser.editingPin)
        browser.editLetter(second)
        browser.closeAll()
        XCTAssertNil(browser.editingPin)
        assertNoEditor(browser)
    }

    private func makeBrowser() throws -> Browser {
        guard Store.testing else { throw XCTSkip("Requires an isolated test store") }
        _ = NSApplication.shared
        return Browser(record: WindowRecord(), opensStartPage: false)
    }

    private func assertNoEditor(_ browser: Browser, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(browser.editingTab, file: file, line: line)
        XCTAssertFalse(browser.renamingTab, file: file, line: line)
        XCTAssertEqual(browser.tabDraft, "", file: file, line: line)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
