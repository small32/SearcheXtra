import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class PersistentListRecoveryTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "persistent-lists-\(getpid())", 1)
        super.setUp()
    }

    func testBrokenSpacesAreKeptBeforeTheFallbackIsEdited() throws {
        try withBrokenFile("spaces") { file, original, backup in
            XCTAssertEqual(Spaces.read(), [Space.first()])
            XCTAssertEqual(try Data(contentsOf: backup()), original)
            let extra = Space(id: UUID(), name: "After recovery", colour: 1)
            Spaces.write([Space.first(), extra])
            XCTAssertEqual(Spaces.read().map(\.id), [Space.firstID, extra.id])
            XCTAssertEqual(try Data(contentsOf: backup()), original)
            XCTAssertNoThrow(try JSONDecoder().decode([Space].self, from: Data(contentsOf: file)))
        }
    }

    func testBrokenWindowRecordsAreKeptBeforeAnotherSave() throws {
        try withBrokenFile("windows") { _, original, backup in
            XCTAssertTrue(Browsers.read().isEmpty)
            XCTAssertEqual(try Data(contentsOf: backup()), original)
        }
    }

    private func withBrokenFile(_ name: String,
                                _ body: (URL, Data, () throws -> URL) throws -> Void) throws {
        guard Store.testing else { throw XCTSkip("Requires an isolated test world") }
        _ = NSApplication.shared
        Disk.drain()
        let file = Store.file(name + ".json"), files = FileManager.default
        let previous = try? Data(contentsOf: file)
        let known = Spaces.known
        let old = Set((try? files.contentsOfDirectory(at: Store.folder, includingPropertiesForKeys: nil)) ?? [])
        defer {
            Disk.drain()
            Spaces.known = known
            if let previous { try? previous.write(to: file) }
            else { try? files.removeItem(at: file) }
            for added in ((try? files.contentsOfDirectory(at: Store.folder, includingPropertiesForKeys: nil)) ?? [])
            where !old.contains(added) && added.lastPathComponent.hasPrefix(name + ".unreadable-") {
                try? files.removeItem(at: added)
            }
        }
        let original = Data("{unreadable \(name) fixture".utf8)
        try original.write(to: file)
        try body(file, original) {
            let backups = try files.contentsOfDirectory(at: Store.folder, includingPropertiesForKeys: nil)
                .filter { !old.contains($0) && $0.lastPathComponent.hasPrefix(name + ".unreadable-") }
            return try XCTUnwrap(backups.first)
        }
    }
}
