import XCTest
@testable import SearcheXtra

@MainActor
final class BookmarkImportProfileTests: XCTestCase {
    func testPersonalMigratesLegacySourceAndRecoversFromAnotherProfilesMarker() throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        let file = Store.file("bookmarks.json")
        Disk.drain()
        let original = try? Data(contentsOf: file)
        let oldKey = "bookmarks.top", newKey = "bookmarks.top.bookmarks.json"
        let oldSource = Store.settings.string(forKey: oldKey)
        let newSource = Store.settings.string(forKey: newKey)
        defer {
            if let original { Disk.write(file, now: true) { original } }
            else { Disk.remove(file) }
            Disk.drain()
            Store.settings.set(oldSource, forKey: oldKey)
            Store.settings.set(newSource, forKey: newKey)
        }
        let node = Bookmark.site("Existing Chrome bookmark", URL(string: "https://personal-import.example/")!)
        let data = try JSONEncoder().encode([node])
        for legacy in ["Chrome", "Another profile browser"] {
            Disk.write(file, now: true) { data }
            Store.settings.removeObject(forKey: newKey)
            Store.settings.set(legacy, forKey: oldKey)
            let personal = Bookmarks()

            let again = personal.take([node], from: "Chrome")

            XCTAssertEqual(again.added, 0)
            XCTAssertEqual(again.already, 1)
            XCTAssertEqual(personal.roots.count, 1)
            XCTAssertEqual(Store.settings.string(forKey: newKey), "Chrome")
        }
    }

    func testBrowserImportsKeepTheirTopLevelSourcePerBookmarkFile() throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        let first = Bookmarks(file: "bookmarks-test-\(UUID().uuidString).json")
        let second = Bookmarks(file: "bookmarks-test-\(UUID().uuidString).json")
        let legacy = Store.settings.string(forKey: "bookmarks.top")
        Store.settings.set("Existing Personal Import", forKey: "bookmarks.top")
        defer {
            first.retire(); second.retire(); Disk.drain()
            Store.settings.set(legacy, forKey: "bookmarks.top")
        }
        let chrome = [Bookmark.site("Chrome", URL(string: "https://chrome-import.example/")!)]
        let safari = [Bookmark.site("Safari", URL(string: "https://safari-import.example/")!)]

        XCTAssertEqual(first.take(chrome, from: "Chrome").added, 1)
        XCTAssertEqual(second.take(safari, from: "Safari").added, 1)
        let again = first.take(chrome, from: "Chrome")

        XCTAssertEqual(again.added, 0)
        XCTAssertEqual(again.already, 1)
        XCTAssertEqual(first.roots.count, 1)
        XCTAssertFalse(first.roots[0].isFolder)
        XCTAssertEqual(second.take(safari, from: "Safari").added, 0)
        XCTAssertEqual(Store.settings.string(forKey: "bookmarks.top"), "Existing Personal Import")
    }

    func testFileImportsKeepTheirTopLevelSourcePerBookmarkFile() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        let first = Bookmarks(file: "bookmarks-test-\(UUID().uuidString).json")
        let second = Bookmarks(file: "bookmarks-test-\(UUID().uuidString).json")
        defer { first.retire(); second.retire(); Disk.drain() }
        let a = [Bookmark.site("First", URL(string: "https://first-import.example/")!)]
        let b = [Bookmark.site("Second", URL(string: "https://second-import.example/")!)]
        _ = try await first.takeFile(a, from: "first.html", control: ImportFile.Control())
        _ = try await second.takeFile(b, from: "second.html", control: ImportFile.Control())

        let again = try await first.takeFile(a, from: "first.html", control: ImportFile.Control())

        XCTAssertEqual(again.added, 0)
        XCTAssertEqual(again.already, 1)
        XCTAssertEqual(first.roots.map(\.url), a.map(\.url))
    }

    func testProfileWithExistingBookmarksInfersSourceWithoutUsingPersonalImport() throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        let marks = Bookmarks(file: "bookmarks-test-\(UUID().uuidString).json")
        let legacy = Store.settings.string(forKey: "bookmarks.top")
        Store.settings.set("Personal browser", forKey: "bookmarks.top")
        defer {
            marks.retire(); Disk.drain()
            Store.settings.set(legacy, forKey: "bookmarks.top")
        }
        let node = Bookmark.site("Already imported", URL(string: "https://existing-import.example/")!)
        marks.insert(node, into: nil)

        let again = marks.take([node], from: "Other profile browser")

        XCTAssertEqual(again.added, 0)
        XCTAssertEqual(again.already, 1)
        XCTAssertEqual(marks.roots.count, 1)
    }
}
