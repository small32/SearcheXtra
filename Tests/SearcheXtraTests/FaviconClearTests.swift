import AppKit
import Foundation
import XCTest
@testable import SearcheXtra

@MainActor
final class FaviconClearTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "favicon-clear-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        _ = NSApplication.shared
        IconClearProtocol.reset()
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IconClearProtocol.self]
        return URLSession(configuration: configuration)
    }

    private var folder: URL { Store.folder.appendingPathComponent("icons", isDirectory: true) }

    func testLateTabIconCannotRestoreClearedHistory() async throws {
        let session = session(), icons = Favicons(session: session)
        let server = try LocalPageServer(["/forgotten/path": .init(type: "text/html", body: "<title>Ready</title>")])
        let tab = SearcheXtra.Tab()
        defer { tab.close(); server.stop(); icons.forgetAll(); session.invalidateAndCancel() }
        icons.forgetAll()
        let url = server.url("/forgotten/path")
        tab.go(to: url)
        try await waitUntil { tab.title == "Ready" }
        icons.fetch(for: tab)
        try await waitUntil { IconClearProtocol.count == 1 }

        let waiting = expectation(description: "bookmark joined the tab request")
        let finished = expectation(description: "joined bookmark released on clear")
        Task {
            waiting.fulfill()
            await icons.fetch(for: url)
            finished.fulfill()
        }
        await fulfillment(of: [waiting], timeout: 1)
        icons.forgetAll()
        await fulfillment(of: [finished], timeout: 1)
        IconClearProtocol.finishHeld()
        try await Task.sleep(for: .milliseconds(1300))
        XCTAssertNil(icons.cached(for: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "A late icon must not recreate the cleared page index or PNGs")
    }

    func testClearReleasesQueuedActiveAndDuplicateBookmarkRequests() async throws {
        let session = session(), icons = Favicons(session: session)
        defer { icons.forgetAll(); session.invalidateAndCancel() }
        icons.forgetAll()
        let urls = (0..<8).map { URL(string: "https://clear-\($0).example/page")! }
        let finished = expectation(description: "all bookmark fetches ended")
        finished.expectedFulfillmentCount = urls.count + 1
        for url in urls + [urls[0]] {
            Task { await icons.fetch(for: url); finished.fulfill() }
        }
        try await waitUntil { IconClearProtocol.count == 4 }
        icons.forgetAll()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(IconClearProtocol.count, 4, "Queued work must not start after clearing")
        XCTAssertNil(icons.cached(for: urls[0]))

        IconClearProtocol.respondImmediately()
        await icons.fetch(for: urls[0])
        XCTAssertNotNil(icons.cached(for: urls[0]), "A new request for the same page must not join stale work")
    }

    func testClearOrdersDiskWritesAndAllowsNewSaves() async throws {
        let session = session(), icons = Favicons(session: session)
        defer { icons.forgetAll(); session.invalidateAndCancel() }
        icons.forgetAll()
        IconClearProtocol.respondImmediately()
        let old = URL(string: "https://old-icon.example/private-path")!
        let new = URL(string: "https://new-icon.example/page")!
        await icons.fetch(for: old)
        XCTAssertNotNil(icons.cached(for: old))
        icons.forgetAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        await icons.fetch(for: new)
        try await waitUntil { FileManager.default.fileExists(atPath: folder.appendingPathComponent("pages.json").path) }
        let data = try Data(contentsOf: folder.appendingPathComponent("pages.json"))
        let index = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(index["old-icon.example"])
        XCTAssertNotNil(index["new-icon.example"])
        XCTAssertNil(icons.cached(for: old))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let until = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < until else { throw NSError(domain: "FaviconClearTests", code: 1) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class IconClearProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var held: [IconClearProtocol] = []
    private static var immediate = false
    private static var requests = 0
    private var stopped = false

    static var count: Int { lock.lock(); defer { lock.unlock() }; return requests }
    static func reset() {
        lock.lock(); held = []; immediate = false; requests = 0; lock.unlock()
    }
    static func respondImmediately() {
        lock.lock(); immediate = true; lock.unlock()
        finishHeld()
    }
    static func finishHeld() {
        lock.lock(); let waiting = held; held = []; lock.unlock()
        waiting.forEach { $0.finish() }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests += 1
        let immediate = Self.immediate
        if !immediate { Self.held.append(self) }
        Self.lock.unlock()
        if immediate { finish() }
    }
    private func finish() {
        Self.lock.lock(); let stopped = stopped; Self.lock.unlock()
        guard !stopped, let url = request.url else { return }
        let image = url.path.hasSuffix(".png") || url.path == "/favicon.ico"
        let data = image
            ? Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGMQaPjwH4QZYAwAU3QJ/a65wk8AAAAASUVORK5CYII=")!
            : Data("<link rel='icon' href='/icon.png'>".utf8)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": image ? "image/png" : "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        Self.lock.lock(); stopped = true; Self.held.removeAll { $0 === self }; Self.lock.unlock()
    }
}
