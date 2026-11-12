import AppKit
import Darwin
import WebKit
import XCTest
@testable import SearcheXtra

@MainActor
final class BenchBoundaryTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "bench-boundary-\(getpid())", 1)
        super.setUp()
    }

    func testTimeoutsBoundHugeNegativeAndNonfiniteNumbers() {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(Bench.responseTimeout(for: ["do": "wait", "seconds": value]), 25)
            XCTAssertEqual(Bench.responseTimeout(for: ["do": "import-file", "timeout": value]), 25)
        }
        for value in [Double.greatestFiniteMagnitude, 1e100] {
            XCTAssertEqual(Bench.responseTimeout(for: ["do": "wait", "seconds": value]), 600)
            XCTAssertEqual(Bench.responseTimeout(for: ["do": "import-file", "timeout": value]), 600)
        }
        XCTAssertEqual(Bench.responseTimeout(for: ["do": "wait", "seconds": -100]), 1)
        XCTAssertEqual(Bench.responseTimeout(for: ["do": "import-file", "timeout": -100]), 1)
        XCTAssertEqual(Bench.responseTimeout(for: ["do": "wait", "seconds": 2]), 7)
        XCTAssertEqual(Bench.responseTimeout(for: ["do": "import-file", "timeout": 120]), 120)
    }

    func testWindowIndexesCannotOverflowAndStillAnswer() async throws {
        try await withBrowser { browser in
            let bench = Bench()
            for index in [Int.min, Int.max, -1, 0, 1, 2] {
                let result = try await self.reply(bench, ["do": "tabs", "window": index])
                let tabs = try XCTUnwrap(result["tabs"] as? [[String: Any]])
                XCTAssertEqual(tabs.count, browser.tabs.count)
                XCTAssertEqual(tabs.first?["id"] as? String, browser.active.map(Bench.short))
            }
        }
    }

    func testShippedModeRejectsTakingOverTheUIAndWritingCustomFiles() async throws {
        try await withBrowser { browser in
            // The data world remains isolated; only the command policy is real-mode.
            let bench = Bench(testRun: false)
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("bench-protected-\(UUID()).png")
            let original = Data("do not replace".utf8)
            try original.write(to: path)
            defer { try? FileManager.default.removeItem(at: path) }
            let tuning = browser.tuning, active = browser.activeID
            let requests: [[String: Any]] = [
                ["do": "ui", "settings": !tuning],
                ["do": "select", "id": browser.active.map(Bench.short) ?? ""],
                ["do": "press", "code": 12, "chars": "q", "mods": ["cmd"]],
                ["do": "windows", "action": "new"],
                ["do": "news", "path": path.path],
                ["do": "ext-menu", "path": path.path],
                ["do": "ext-shot", "path": path.path],
            ]
            for request in requests {
                let result = try await self.reply(bench, request)
                XCTAssertNotNil(result["error"], "Must reject \(request)")
                XCTAssertEqual(try Data(contentsOf: path), original)
                XCTAssertEqual(browser.tuning, tuning)
                XCTAssertEqual(browser.activeID, active)
            }
            let denied = try await self.reply(bench, ["do": "eval", "id": browser.active.map(Bench.short) ?? "", "world": "search", "js": "1"])
            XCTAssertNotNil(denied["error"], "Shipped mode cannot inspect a person's non-bench tab")
            let owned = browser.benchOpen(URL(string: "about:blank")!)
            let world = try await self.reply(bench, ["do": "eval", "id": Bench.short(owned), "world": "search", "js": "1"])
            XCTAssertEqual(world["error"] as? String, "search world needs a test run")
        }
    }

    func testSnapshotIgnoresCustomPathInShippedMode() async throws {
        try await withBrowser { browser in
            let server = try LocalPageServer(["/page": .init(type: "text/html", body: "<p>snapshot</p>")])
            defer { server.stop() }
            let tab = browser.benchOpen(server.url("/page"))
            let bench = Bench(testRun: false)
            let requested = FileManager.default.temporaryDirectory.appendingPathComponent("bench-untouched-\(UUID()).png")
            let fallback = URL(fileURLWithPath: NSTemporaryDirectory() + "search-bench-\(Bench.short(tab)).png")
            let original = Data("untouched".utf8)
            try original.write(to: requested)
            defer {
                try? FileManager.default.removeItem(at: requested)
                try? FileManager.default.removeItem(at: fallback)
            }
            let end = Date().addingTimeInterval(10)
            while tab.web.isLoading || tab.web.url != server.url("/page") {
                guard Date() < end else { XCTFail("Page did not load"); return }
                try await Task.sleep(for: .milliseconds(20))
            }
            let result = try await self.reply(bench, ["do": "shot", "id": Bench.short(tab), "path": requested.path, "width": 160])
            XCTAssertNil(result["error"], "\(result)")
            XCTAssertEqual(result["path"] as? String, fallback.path)
            XCTAssertEqual(try Data(contentsOf: requested), original)
            XCTAssertNotNil(NSImage(contentsOf: fallback))
            let probe = try await self.reply(Bench(testRun: true), ["do": "shot", "id": Bench.short(tab), "path": requested.path, "width": 160])
            XCTAssertEqual(probe["path"] as? String, requested.path)
            XCTAssertNotNil(NSImage(contentsOf: requested), "An isolated test run may still choose its output")
        }
    }

    func testExtremeKeyCodesCreateEventsWithoutIntegerTraps() async throws {
        try await withBrowser { _ in
            let bench = Bench()
            for (code, expected) in [(Int.min, UInt16(0)), (Int.max, UInt16.max), (12, UInt16(12))] {
                var response: [String: Any]?
                let done = self.expectation(description: "press reply")
                bench.handle(["do": "press", "code": code, "chars": "x"]) { response = $0; done.fulfill() }
                // Inspect the actual posted events without sending them to a page.
                for type in [NSEvent.EventTypeMask.keyDown, .keyUp] {
                    let event = try XCTUnwrap(NSApp.nextEvent(matching: type, until: Date(), inMode: .default, dequeue: true))
                    XCTAssertEqual(event.keyCode, expected)
                }
                await self.fulfillment(of: [done], timeout: 2)
                XCTAssertNil(response?["error"])
            }
        }
    }

    private func reply(_ bench: Bench, _ request: [String: Any]) async throws -> [String: Any] {
        let done = expectation(description: "bench \(request["do"] ?? "")")
        var result: [String: Any]?
        bench.handle(request) { result = $0; done.fulfill() }
        await fulfillment(of: [done], timeout: 15)
        return try XCTUnwrap(result)
    }

    private func withBrowser(_ body: (Browser) async throws -> Void) async throws {
        guard Store.testing else { throw XCTSkip("Requires an isolated data world") }
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        Browsers.register(browser)
        defer {
            for tab in browser.tabs where tab.bench { tab.built?.window?.close() }
            Browsers.discard(browser)
        }
        try await body(browser)
    }
}
