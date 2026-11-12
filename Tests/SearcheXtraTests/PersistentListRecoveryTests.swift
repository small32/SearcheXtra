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
        try withUnreadableList("spaces") { file, original, backup in
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
        try withUnreadableList("windows") { file, original, backup in
            XCTAssertTrue(Browsers.read().isEmpty)
            XCTAssertEqual(try Data(contentsOf: backup()), original)
            let browser = Browser(record: WindowRecord(), opensStartPage: false)
            Browsers.register(browser)
            defer { Browsers.discard(browser) }
            Browsers.save(now: true)
            let records = try JSONDecoder().decode([WindowRecord].self, from: Data(contentsOf: file))
            XCTAssertTrue(records.contains { $0.id == browser.record.id })
            XCTAssertEqual(try Data(contentsOf: backup()), original)
        }
    }

    func testBrokenBookmarksAreKeptAfterAddingANewBookmark() throws {
        try withUnreadableList("bookmarks-recovery") { file, original, backup in
            let bookmarks = Bookmarks(file: file.lastPathComponent)
            XCTAssertTrue(bookmarks.isEmpty)
            XCTAssertEqual(try Data(contentsOf: backup()), original)
            let url = try XCTUnwrap(URL(string: "https://recovered.example/"))
            let added = try XCTUnwrap(bookmarks.add(url, title: "Recovered"))
            Disk.drain()
            let saved = try JSONDecoder().decode([Bookmark].self, from: Data(contentsOf: file))
            XCTAssertEqual(saved.map(\.id), [added.id])
            XCTAssertEqual(Bookmarks(file: file.lastPathComponent).roots.compactMap(\.url), [url.absoluteString])
            XCTAssertEqual(try Data(contentsOf: backup()), original)
        }
    }

    func testBrokenHistoryIsKeptAfterRecordingAnotherVisit() throws {
        try withUnreadableList("history-recovery") { file, original, backup in
            let history = History(file: file)
            XCTAssertTrue(history.recent().isEmpty)
            XCTAssertEqual(try Data(contentsOf: backup()), original)
            let url = try XCTUnwrap(URL(string: "https://recovered.example/"))
            history.record(url, title: "Recovered")
            history.flush()
            XCTAssertEqual(History(file: file).recent().map(\.url), [url])
            XCTAssertEqual(try Data(contentsOf: backup()), original)
        }
    }

    func testBrokenHiddenElementsAreKeptAfterHidingAnotherElement() throws {
        try withUnreadableList("hidden-recovery") { file, original, backup in
            let curtain = Curtain(file: file)
            XCTAssertTrue(curtain.byHost.isEmpty)
            XCTAssertEqual(try Data(contentsOf: backup()), original)
            curtain.hide(".banner", label: "Banner", note: "Top", on: "recovered.example")
            curtain.flush()
            let saved = try JSONDecoder().decode([String: [Veil]].self, from: Data(contentsOf: file))
            XCTAssertEqual(saved["recovered.example"]?.map(\.selector), [".banner"])
            XCTAssertEqual(Curtain(file: file).veils(on: "recovered.example").map(\.selector), [".banner"])
            XCTAssertEqual(try Data(contentsOf: backup()), original)
        }
    }
}

// These two readers load once per process. The macOS regression runner runs
// each test class separately so these fixtures exercise their first real load.
@MainActor
final class PinRecoveryTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "pin-recovery-\(getpid())", 1)
        super.setUp()
    }

    func testBrokenPinsAreKeptAfterPinningAnotherPage() throws {
        try withUnreadableList("pins") { file, original, backup in
            XCTAssertTrue(Pins.defs(Space.firstID).isEmpty)
            XCTAssertEqual(try Data(contentsOf: backup()), original)
            let browser = Browser(record: WindowRecord(), opensStartPage: false)
            defer { browser.closeAll() }
            let pin = PinDef(id: UUID(), letter: "R", home: "https://recovered.example/", title: "Recovered", name: nil)
            Pins.set(Space.firstID, [pin], from: browser)
            defer { Pins.forget(Space.firstID) }
            Disk.drain()
            let saved = try XCTUnwrap(Pins.decode(Data(contentsOf: file)))
            XCTAssertEqual(saved.bySpace[Space.firstID], [pin])
            XCTAssertEqual(try Data(contentsOf: backup()), original)
        }
    }
}

@MainActor
final class ProfileRecoveryTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "profile-recovery-\(getpid())", 1)
        super.setUp()
    }

    func testBrokenProfilesAreKeptAfterRenamingTheFallbackProfile() throws {
        try withUnreadableList("profiles") { file, original, backup in
            let profiles = Profiles.shared
            XCTAssertEqual(profiles.list, [.personal])
            XCTAssertEqual(try Data(contentsOf: backup()), original)
            defer { profiles.rename(Profile.personalID, to: Profile.personal.name) }
            profiles.rename(Profile.personalID, to: "Recovered")
            let saved = try JSONDecoder().decode([Profile].self, from: Data(contentsOf: file))
            XCTAssertEqual(saved.map(\.id), [Profile.personalID])
            XCTAssertEqual(saved.map(\.name), ["Recovered"])
            XCTAssertEqual(Profiles.read(), saved)
            XCTAssertEqual(try Data(contentsOf: backup()), original)
        }
    }
}

@MainActor
private func withUnreadableList(_ name: String,
                               _ body: (URL, Data, () throws -> URL) throws -> Void) throws {
    guard Store.testing else { throw XCTSkip("Requires an isolated test world") }
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
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
        XCTAssertEqual(backups.count, 1, "The original must be kept exactly once")
        return try XCTUnwrap(backups.first)
    }
}
