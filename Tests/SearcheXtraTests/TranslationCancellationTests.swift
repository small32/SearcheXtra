import AppKit
import WebKit
import XCTest
@testable import SearcheXtra

@available(macOS 15, *)
@MainActor
final class TranslationCancellationTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "translation-cancel-\(getpid())", 1)
        super.setUp()
    }

    func testLateCollectionCannotReviveACancelledTranslation() async throws {
        guard Store.testing else { throw XCTSkip("Needs a probe data store") }
        _ = NSApplication.shared
        let server = try LocalPageServer(["/": .init(type: "text/html", body: "<html lang=en><title>Ready</title><p>Hello world</p></html>")])
        let tab = SearcheXtra.Tab()
        defer { tab.close(); server.stop() }
        tab.go(to: server.url("/"))
        let until = Date().addingTimeInterval(5)
        while tab.title != "Ready" && Date() < until { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(tab.title, "Ready")
        // Hold the real WebKit async reply across Show Original; no model or
        // translation session is requested by this fixture.
        _ = try await tab.web.callAsyncJavaScript("""
            window.__searchTr = {
              collect: () => new Promise(resolve => { window.releaseCollection = () => resolve([]); }),
              restore: () => 0
            };
            """, contentWorld: Web.world)
        let translator = try XCTUnwrap(PageTranslator.start(tab, to: Locale.Language(identifier: "fr")))
        while (try await tab.web.callAsyncJavaScript("return typeof window.releaseCollection === 'function'", contentWorld: Web.world) as? Bool) != true {
            guard Date() < until else { return XCTFail("Collection did not start") }
            try await Task.sleep(for: .milliseconds(10))
        }
        translator.end(restore: true)
        _ = try await tab.web.callAsyncJavaScript("window.releaseCollection();", contentWorld: Web.world)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(tab.translator)
        XCTAssertNil(tab.translation, "A late collection must not restore the working mark")
    }
}
