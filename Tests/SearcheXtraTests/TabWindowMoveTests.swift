import AppKit
import WebKit
import XCTest
@testable import SearcheXtra

@MainActor
final class TabWindowMoveTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "tab-window-move-\(getpid())", 1)
        super.setUp()
    }

    func testCancellingMoveToAnotherStorePreservesTheDocumentAndRow() async throws {
        try await withBrowsers { source, destination, tab, web in
            Ask.testing = false
            source.moveToWindow(tab, destination)
            try await until {
                try await web.evaluateJavaScript("window.formCheckCount || 0", in: nil, contentWorld: Web.world) as? Int == 1
            }
            // Finish the evaluateInSearch completion that handled Cancel.
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(source.tabs.contains { $0 === tab })
            XCTAssertFalse(destination.tabs.contains { $0 === tab })
            XCTAssertTrue(tab.built === web)
            let draft = try await web.evaluateJavaScript("document.getElementById('draft').textContent") as? String
            XCTAssertEqual(draft, "unsaved rich text")
        }
    }

    func testConfirmedMoveUsesTheDestinationStore() async throws {
        try await withBrowsers { source, destination, tab, web in
            Ask.testing = true
            source.moveToWindow(tab, destination)
            try await until { destination.tabs.contains { $0 === tab } }
            XCTAssertFalse(source.tabs.contains { $0 === tab })
            XCTAssertFalse(tab.built === web)
            XCTAssertTrue(tab.store === Spaces.store(for: destination.spaceID))
            XCTAssertEqual(destination.activeID, tab.id)
        }
    }

    func testMovingWithinTheSameStoreKeepsTheDocumentWithoutAsking() async throws {
        try await withBrowsers(sameStore: true) { source, destination, tab, web in
            Ask.testing = false
            source.moveToWindow(tab, destination)
            XCTAssertTrue(destination.tabs.contains { $0 === tab })
            XCTAssertFalse(source.tabs.contains { $0 === tab })
            XCTAssertTrue(tab.built === web)
            let checks = try await web.evaluateJavaScript("window.formCheckCount || 0", in: nil, contentWorld: Web.world) as? Int
            XCTAssertEqual(checks, 0)
        }
    }

    private func withBrowsers(sameStore: Bool = false,
                              _ body: (Browser, Browser, Tab, PageView) async throws -> Void) async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let prefs = Shared.prefs
        let oldUsesSpaces = prefs.usesSpaces
        let oldAnswer = Ask.testing
        prefs.usesSpaces = true
        let profile = Profiles.shared.add(named: "Move lifecycle \(UUID().uuidString)")
        let other = Space(id: UUID(), name: "Other sign-ins", colour: 0,
                          sharesSignIns: sameStore, profile: profile.id)
        Spaces.write(Spaces.read() + [other])
        let source = Browser(record: WindowRecord(space: profile.home), opensStartPage: false)
        let destination = Browser(record: WindowRecord(space: other.id), opensStartPage: false)
        let server = try LocalPageServer(["/draft": .init(type: "text/html", body: """
        <!doctype html><title>Draft</title><div id="draft" contenteditable>unsaved rich text</div>
        """)])
        defer {
            source.leaveFiles()
            destination.leaveFiles()
            source.closeAll()
            destination.closeAll()
            Profiles.shared.delete(profile.id)
            prefs.usesSpaces = oldUsesSpaces
            Ask.testing = oldAnswer
            server.stop()
            Disk.drain()
        }
        let tab = try XCTUnwrap(source.active)
        tab.go(to: server.url("/draft"))
        let web = tab.web
        try await until { web.url == server.url("/draft") && !web.isLoading }
        _ = try await web.evaluateJavaScript("document.getElementById('draft').textContent = 'unsaved rich text'")
        await withCheckedContinuation { continuation in
            web.evaluateInSearch("""
            window.__officeForms = {unsaved: () => {
                window.formCheckCount = (window.formCheckCount || 0) + 1;
                return true;
            }};
            """) { _ in continuation.resume() }
        }
        try await body(source, destination, tab, web)
    }

    private func until(_ condition: () async throws -> Bool) async throws {
        for _ in 0..<300 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for tab move")
        throw Timeout.waiting
    }

    private enum Timeout: Error { case waiting }
}
