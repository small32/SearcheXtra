import AppKit
import WebKit
import XCTest
@testable import SearcheXtra

@MainActor
final class LittleKeepTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "little-keep-\(getpid())", 1)
        super.setUp()
    }

    func testCancellingCrossStoreKeepPreservesTheSmallWindowAndDraft() async throws {
        try await withWindow { little, destination, web in
            Ask.testing = false
            little.keep(in: destination)
            try await self.until { (try await web.evaluateJavaScript("window.checks || 0", in: nil, contentWorld: Web.world) as? Int) == 1 }
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(LittleWindow.all.contains { $0 === little })
            XCTAssertFalse(destination.tabs.contains { $0 === little.tab })
            XCTAssertTrue(little.tab.built === web)
            let text = try await web.evaluateJavaScript("document.getElementById('draft').textContent") as? String
            XCTAssertEqual(text, "unsaved words")
        }
    }

    func testConfirmedCrossStoreKeepUsesDestinationSignIns() async throws {
        try await withWindow { little, destination, web in
            Ask.testing = true
            little.keep(in: destination)
            try await self.until { destination.tabs.contains { $0 === little.tab } }
            XCTAssertFalse(LittleWindow.all.contains { $0 === little })
            XCTAssertFalse(little.tab.built === web)
            XCTAssertTrue(little.tab.store === Spaces.store(for: destination.spaceID))
        }
    }

    private func withWindow(_ body: (LittleWindow, Browser, PageView) async throws -> Void) async throws {
        guard Store.testing else { throw XCTSkip("Requires an isolated test store") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let previousSpaces = Shared.prefs.usesSpaces
        let previousAnswer = Ask.testing
        Shared.prefs.usesSpaces = true
        let profile = Profiles.shared.add(named: "Little keep \(UUID().uuidString)")
        let other = Space(id: UUID(), name: "Other sign-ins", colour: 0, sharesSignIns: false, profile: profile.id)
        Spaces.write(Spaces.read() + [other])
        let source = Browser(record: WindowRecord(space: profile.home), opensStartPage: false)
        let destination = Browser(record: WindowRecord(space: other.id), opensStartPage: false)
        let server = try LocalPageServer(["/draft": .init(type: "text/html", body: "<title>Draft</title><div id='draft' contenteditable>unsaved words</div>")])
        LittleWindow.show(server.url("/draft"), for: source, front: false)
        let little = try XCTUnwrap(LittleWindow.all.last)
        defer {
            if LittleWindow.all.contains(where: { $0 === little }) { little.close() }
            source.leaveFiles(); destination.leaveFiles()
            source.closeAll(); destination.closeAll()
            Profiles.shared.delete(profile.id)
            Shared.prefs.usesSpaces = previousSpaces
            Ask.testing = previousAnswer
            server.stop(); Disk.drain()
        }
        let web = little.tab.web
        try await until { web.url == server.url("/draft") && !web.isLoading }
        _ = try await web.callAsyncJavaScript("window.__officeForms = {unsaved: () => { window.checks = (window.checks || 0) + 1; return true; }};", contentWorld: Web.world)
        try await body(little, destination, web)
    }

    private func until(_ condition: () async throws -> Bool) async throws {
        for _ in 0..<300 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for small-window keep")
        throw NSError(domain: "LittleKeepTests", code: 1)
    }
}
