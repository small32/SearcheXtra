import AppKit
import Combine
import Foundation
import XCTest
@testable import SearcheXtra

@MainActor
final class BookmarkIconTests: XCTestCase {
    func testDeclaredIconsUseFinalURLPortAndDecodeEntities() throws {
        _ = NSApplication.shared
        let page = try XCTUnwrap(URL(string: "https://bookmarks.example:8443/path/page"))
        let html = #"<LINK REL='shortcut ICON' HREF='../assets/icon.png?a=1&amp;b=2' SIZES='64x64'><link rel=apple-touch-icon href=/touch.png sizes=180x180><link rel=stylesheet href=/style.css>"#
        XCTAssertEqual(Favicons.candidates(in: html, page: page, dark: false).map(\.absoluteString), [
            "https://bookmarks.example:8443/assets/icon.png?a=1&b=2",
            "https://bookmarks.example:8443/touch.png",
            "https://bookmarks.example:8443/favicon.ico",
        ])
    }

    func testDarkIconAndRootFallbackWithoutFetchingUnsafeURL() throws {
        let page = try XCTUnwrap(URL(string: "http://bookmarks.example:3000/page"))
        let html = #"<link rel='icon' href='/light.png' media='(prefers-color-scheme: light)'><link rel='icon' href='/dark.png' media='(prefers-color-scheme: dark)'><link rel='icon' href='javascript:alert(1)'>"#
        XCTAssertEqual(Favicons.candidates(in: html, page: page, dark: true).map(\.path), ["/dark.png", "/favicon.ico"])
        XCTAssertEqual(Favicons.candidates(in: "<title>No declaration</title>", page: page, dark: false).map(\.absoluteString), ["http://bookmarks.example:3000/favicon.ico"])
        XCTAssertEqual(Favicons.candidates(in: #"<base href='/assets/'><link rel='icon' href='site.png'>"#, page: page, dark: false).map(\.absoluteString), ["http://bookmarks.example:3000/assets/site.png", "http://bookmarks.example:3000/favicon.ico"])
    }

    func testUnvisitedBookmarkLoadsDeclaredIconAndNotifiesRows() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        _ = NSApplication.shared
        BookmarkIconProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BookmarkIconProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let icons = Favicons(session: session)
        let url = try XCTUnwrap(URL(string: "https://\(UUID().uuidString.lowercased()).example:8443/path/page"))
        var arrivals = 0
        let subscription = icons.objectWillChange.sink { arrivals += 1 }
        defer { subscription.cancel() }
        async let first: Void = icons.fetch(for: url)
        async let second: Void = icons.fetch(for: url)
        _ = await (first, second)
        XCTAssertNotNil(icons.cached(try XCTUnwrap(Favicons.site(url))))
        XCTAssertEqual(arrivals, 1)
        XCTAssertEqual(BookmarkIconProtocol.count("/path/page"), 1)
        XCTAssertEqual(BookmarkIconProtocol.count("/custom/icon.png"), 1)
        XCTAssertEqual(BookmarkIconProtocol.count("/favicon.ico"), 0)
        await icons.fetch(for: url)
        XCTAssertEqual(BookmarkIconProtocol.count("/path/page"), 1)
    }

    func testUnvisitedBookmarksOnOneHostKeepTheirOwnAppIcons() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        _ = NSApplication.shared
        BookmarkIconProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BookmarkIconProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let icons = Favicons(session: session)
        let site = "https://\(UUID().uuidString.lowercased()).example"
        let firstURL = try XCTUnwrap(URL(string: site + "/one/page"))
        let secondURL = try XCTUnwrap(URL(string: site + "/two/page"))
        await icons.fetch(for: firstURL)
        let first = try XCTUnwrap(icons.cached(for: firstURL))
        await icons.fetch(for: secondURL)
        let second = try XCTUnwrap(icons.cached(for: secondURL))
        XCTAssertFalse(first === second, "Two applications on a host must not inherit each other's declared icon")
        XCTAssertTrue(icons.cached(for: firstURL) === first)
        XCTAssertEqual(BookmarkIconProtocol.count("/one/icon.png"), 1)
        XCTAssertEqual(BookmarkIconProtocol.count("/two/icon.png"), 1)
    }

}

private final class BookmarkIconProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests: [String: Int] = [:]

    static func reset() { lock.lock(); requests = [:]; lock.unlock() }
    static func count(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return requests[path] ?? 0 }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock(); Self.requests[url.path, default: 0] += 1; Self.lock.unlock()
        let image = url.path.hasSuffix("/icon.png")
        let application = url.path.hasPrefix("/one/") ? "one" : url.path.hasPrefix("/two/") ? "two" : nil
        let iconPath = application.map { "/\($0)/icon.png" } ?? "/custom/icon.png"
        let html = "<title>Bookmark fixture</title><link rel='icon' href='\(iconPath)' sizes='64x64'>"
        let data = image
            ? Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGMQaPjwH4QZYAwAU3QJ/a65wk8AAAAASUVORK5CYII=")!
            : Data(html.utf8)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": image ? "image/png" : "text/html; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
