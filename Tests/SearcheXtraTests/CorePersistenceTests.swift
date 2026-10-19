import Foundation
import XCTest
@testable import SearcheXtra

@MainActor
final class CorePersistenceTests: XCTestCase {
    func testHiddenElementsFlushAndRestoreBeforeTheSaveDelay() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("search-curtain-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("hidden.json")
        let curtain = Curtain(file: file)
        curtain.hide(".banner", label: "Banner", note: "", on: "fixture.example")
        curtain.flush()
        XCTAssertEqual(Curtain(file: file).veils(on: "fixture.example").map(\.selector), [".banner"])
        curtain.restoreAll(on: "fixture.example")
        curtain.flush()
        Disk.drain()
        XCTAssertTrue(Curtain(file: file).byHost.isEmpty)
    }

    func testClearSearchSitesOvertakesAnOlderQueuedWrite() throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        let previous = SiteSearch.learned
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("search-site-queue-\(UUID().uuidString)", isDirectory: true)
        let release = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        defer {
            release.signal()
            Disk.drain()
            SiteSearch.forget()
            for site in previous { SiteSearch.adopt(host: site.host, template: site.template) }
            Disk.drain()
            try? FileManager.default.removeItem(at: folder)
        }
        SiteSearch.forget()
        Disk.write(folder.appendingPathComponent("blocker")) {
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
            return Data()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        SiteSearch.adopt(host: "queued.example", template: "https://queued.example/?q=%s")
        SiteSearch.forget()
        release.signal()
        Disk.drain()
        let data = try Data(contentsOf: Store.file("search-sites.json"))
        XCTAssertTrue(try JSONDecoder().decode([SearchSite].self, from: data).isEmpty)
        XCTAssertTrue(SiteSearch.learned.isEmpty)
    }

    func testClearSearchSitesRejectsAnAlreadyStartedDescriptionRequest() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        let previous = SiteSearch.learned
        SiteSearch.forget()
        defer {
            SiteSearch.forget()
            for site in previous { SiteSearch.adopt(host: site.host, template: site.template) }
            Disk.drain()
        }
        let started = expectation(description: "OpenSearch request started")
        let finished = expectation(description: "OpenSearch callback settled")
        PendingSearchDescription.started = started
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PendingSearchDescription.self]
        let session = URLSession(configuration: configuration, delegate: FinishedSearchSession(finished), delegateQueue: .main)
        defer { session.invalidateAndCancel() }
        let page = URL(string: "https://inflight-description.example/")!
        SiteSearch.learn(from: page, description: page.appendingPathComponent("opensearch.xml"), session: session)
        await fulfillment(of: [started], timeout: 5)
        SiteSearch.forget()
        PendingSearchDescription.finish()
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertTrue(SiteSearch.learned.isEmpty)
        Disk.drain()
        let data = try Data(contentsOf: Store.file("search-sites.json"))
        XCTAssertTrue(try JSONDecoder().decode([SearchSite].self, from: data).isEmpty)
    }
}

private final class FinishedSearchSession: NSObject, URLSessionDelegate {
    let finished: XCTestExpectation
    init(_ finished: XCTestExpectation) { self.finished = finished }
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        DispatchQueue.main.async { self.finished.fulfill() }
    }
}

private final class PendingSearchDescription: URLProtocol {
    private static let lock = NSLock()
    static var started: XCTestExpectation?
    private static var pending: PendingSearchDescription?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.pending = self
        let started = Self.started
        Self.started = nil
        Self.lock.unlock()
        started?.fulfill()
    }
    override func stopLoading() {}

    static func finish() {
        lock.lock()
        let pending = pending
        self.pending = nil
        lock.unlock()
        guard let pending, let url = pending.request.url else { return }
        let body = Data(#"<OpenSearchDescription><ShortName>Fixture</ShortName><Url type="text/html" template="https://inflight-description.example/search?q={searchTerms}"/></OpenSearchDescription>"#.utf8)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/opensearchdescription+xml"])!
        pending.client?.urlProtocol(pending, didReceive: response, cacheStoragePolicy: .notAllowed)
        pending.client?.urlProtocol(pending, didLoad: body)
        pending.client?.urlProtocolDidFinishLoading(pending)
    }
}
