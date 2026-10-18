import Combine
import XCTest
@testable import SearcheXtra

@MainActor
final class BookmarkManagerTests: XCTestCase {
    func testBatchDeletionPublishesOneChangeAndKeepsUnselectedSiblings() throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        let bookmarks = Bookmarks()
        let previous = bookmarks.roots
        bookmarks.remove(Set(previous.map(\.id)))
        defer {
            bookmarks.remove(Set(bookmarks.roots.map(\.id)))
            for node in previous { bookmarks.insert(node, into: nil) }
        }
        let children = (0..<100).map { Bookmark(title: "Page \($0)", url: "https://bookmark-\($0).example/") }
        let folder = bookmarks.insert(.folder("Folder", children), into: nil)
        let survivor = bookmarks.insert(.folder("Survivor", []), into: nil)
        var changes = 0
        let watch = bookmarks.objectWillChange.sink { changes += 1 }
        bookmarks.remove(Set([folder.id] + children.prefix(50).map(\.id)))
        watch.cancel()
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(bookmarks.roots.map(\.id), [survivor.id])
        Disk.drain()
        XCTAssertEqual(Bookmarks().roots.map(\.id), [survivor.id])
    }

    func testSortingFolderPreservesOtherFoldersAndPersists() throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        let bookmarks = Bookmarks()
        let previous = bookmarks.roots
        for node in previous { bookmarks.remove(node.id) }
        defer {
            for node in bookmarks.roots { bookmarks.remove(node.id) }
            for node in previous { bookmarks.insert(node, into: nil) }
        }
        let z = Bookmark(title: "Z", url: "https://z.example")
        let a = Bookmark(title: "A", url: "https://a.example")
        let target = bookmarks.insert(.folder("Target", [z, a]), into: nil)
        let otherZ = Bookmark(title: "Z", url: "https://other-z.example")
        let otherA = Bookmark(title: "A", url: "https://other-a.example")
        let untouched = bookmarks.insert(.folder("Other", [otherZ, otherA]), into: nil)
        bookmarks.sortByName(in: target.id)
        XCTAssertEqual(bookmarks.bookmark(target.id)?.children?.map(\.id), [a.id, z.id])
        XCTAssertEqual(bookmarks.bookmark(untouched.id)?.children?.map(\.id), [otherZ.id, otherA.id])
        Disk.drain()
        XCTAssertEqual(Bookmarks().bookmark(target.id)?.children?.map(\.id), [a.id, z.id])
        bookmarks.sortByName()
        XCTAssertEqual(bookmarks.roots.map(\.id), [untouched.id, target.id])
        XCTAssertTrue(SettingsPanel.Page.allCases.contains(.bookmarks))
        let nested = bookmarks.insert(.folder("Nested", []), into: target.id)
        bookmarks.move([target.id], into: nested.id)
        XCTAssertNil(bookmarks.parent(of: target.id))
        XCTAssertEqual(bookmarks.parent(of: nested.id), target.id)
        bookmarks.move([a.id, z.id], into: nil, at: 1)
        XCTAssertEqual(bookmarks.roots.map(\.id), [untouched.id, a.id, z.id, target.id])
        XCTAssertEqual(bookmarks.bookmark(target.id)?.children?.map(\.id), [nested.id])
        bookmarks.move([untouched.id, a.id], into: target.id)
        XCTAssertEqual(bookmarks.bookmark(target.id)?.children?.map(\.id), [nested.id, untouched.id, a.id])
    }
}
