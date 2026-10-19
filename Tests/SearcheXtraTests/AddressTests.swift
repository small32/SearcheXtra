import AppKit
import Darwin
import Foundation
import XCTest
@testable import SearcheXtra

final class AddressTests: XCTestCase {
    func testExistingPathsKeepTheirLiteralNames() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        for name in ["report.pdf", "résumé #1? 100%.html"] {
            let file = folder.appendingPathComponent(name)
            try Data("local file".utf8).write(to: file)
            let url = try XCTUnwrap(Address.file(from: " \(file.path)\n"))
            XCTAssertNil(Address.url(from: file.path), "Suggestions and text drops must not resolve paths")
            XCTAssertTrue(url.isFileURL)
            XCTAssertEqual(url.path, file.path)
            XCTAssertNil(url.query)
            XCTAssertNil(url.fragment)
            XCTAssertEqual(Address.url(from: url.absoluteString), url)
        }
        XCTAssertNil(Address.file(from: folder.path))
        XCTAssertNil(Address.file(from: folder.appendingPathComponent("missing.pdf").path))
    }

    func testHomeRelativePath() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path + "/"
        let file = #filePath
        try XCTSkipUnless(file.hasPrefix(home), "Checkout is outside the home directory")
        let url = try XCTUnwrap(Address.file(from: "~/" + file.dropFirst(home.count)))
        XCTAssertEqual(url.path, file)
    }

    func testOnlyRegularFilesAreAccepted() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("regular.txt")
        try Data("text".utf8).write(to: file)
        let pipe = folder.appendingPathComponent("pipe")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        let link = folder.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        for path in [folder.path, pipe.path, link.path, "/dev/zero", "/dev/random",
                     "/" + file.path, folder.appendingPathComponent("missing").path] {
            XCTAssertNil(Address.file(from: path), path)
        }
        try FileManager.default.removeItem(at: file)
        XCTAssertNil(Address.file(from: link.path), "A broken link is not a regular file either")
    }

    func testNumericDomainLabelsAreNotPrivateIPv4Addresses() {
        for host in ["10.io", "10.example.com", "172.16.example", "192.168.example"] {
            XCTAssertEqual(Address.url(from: host)?.scheme, "https", host)
        }
        for host in ["10.1.2.3", "172.16.2.3", "192.168.2.3"] {
            XCTAssertEqual(Address.url(from: host)?.scheme, "http", host)
        }
    }

    func testTabEditingHidesExtensionURLsAndEmbeddedCredentials() throws {
        let page = try XCTUnwrap(URL(string: "https://username:password@example.com/path?q=value#part"))
        let edited = Address.tabEditable(page)
        XCTAssertFalse(edited.contains("username"))
        XCTAssertFalse(edited.contains("password"))
        XCTAssertEqual(Address.url(from: edited)?.absoluteString, "https://example.com/path?q=value#part")
        XCTAssertEqual(Address.tabEditable(try XCTUnwrap(URL(string: "webkit-extension://fixture/newtab.html"))), "")
    }

    func testAddressesAndSearchPhrasesKeepTheirMeaning() {
        XCTAssertEqual(Address.url(from: "example.com")?.absoluteString, "https://example.com")
        XCTAssertEqual(Address.url(from: "localhost:3000/test")?.absoluteString, "http://localhost:3000/test")
        XCTAssertEqual(Address.url(from: "https://example.com/a?q=b#c")?.absoluteString, "https://example.com/a?q=b#c")
        for text in ["", "two words", "./report.pdf", "person@example.com", "javascript:alert(1)"] {
            XCTAssertNil(Address.url(from: text), text)
            XCTAssertNil(Address.file(from: text), text)
        }
    }
}

@MainActor
final class FileDestinationTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "file-destination-\(getpid())", 1)
        super.setUp()
    }

    func testOnlyCommittedDestinationsResolvePathsAndSiteSearchKeepsPrecedence() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).html")
        try Data("fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        browser.typed = file.path
        XCTAssertNil(browser.ending)
        XCTAssertFalse(browser.offers.contains { $0.url.isFileURL })
        XCTAssertEqual(browser.destination(for: file.path), file)
        XCTAssertEqual(browser.destination(for: file.absoluteString), file)
        XCTAssertEqual(browser.destination(for: "/dev/zero"), browser.searchURL(for: "/dev/zero"))

        let site = SearchSite(name: "Fixture", host: "example.test", template: "https://example.test/?q=%s")
        browser.siteChip = site
        XCTAssertEqual(browser.destination(for: file.path), site.url(for: file.path))
        browser.siteChip = nil
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(browser.destination(for: file.path), browser.searchURL(for: file.path))
    }
}
