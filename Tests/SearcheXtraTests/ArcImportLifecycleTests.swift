import AppKit
import XCTest
@testable import SearcheXtra

@MainActor
final class ArcImportLifecycleTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "arc-import-lifecycle-\(getpid())", 1)
        Store.settings.set("zh-Hans", forKey: "interface.language")
        super.setUp()
    }

    func testDefaultArcProfileImportsIntoTheCurrentProfile() throws {
        try withBrowser { browser in
            XCTAssertTrue(L10n.isChinese)
            XCTAssertNotEqual(L10n.render("bookmarks.bar.opening.standard", language: "zh-Hans"), "Default")
            let before = Set(Profiles.shared.list.map(\.id))
            let name = "Arc Default \(UUID().uuidString)"
            let url = URL(string: "https://arc-default.example/kept")!
            let sidebar = ArcSidebar(favorites: [], spaces: [
                .init(name: name, symbol: "briefcase", profile: "Default", pinned: [
                    .item(.init(title: "Default tab", url: url)),
                ]),
            ])

            let imported = browser.takeArc(sidebar)

            XCTAssertEqual(Set(Profiles.shared.list.map(\.id)), before,
                           "A machine profile identifier must not create a localized extra profile")
            XCTAssertEqual(imported.tabs, 1)
            let target = try XCTUnwrap(browser.spaces.first { $0.name == name })
            XCTAssertEqual(target.profileID, browser.profileID)
            XCTAssertEqual(browser.readRow(target.id).tabs.map(\.url), [url.absoluteString])
        }
    }

    func testImportIntoPreloadedSpaceWritesItsWholeRowBeforeItIsVisited() throws {
        try withBrowser { browser in
            for folder in [nil, "Existing folder", "New folder"] as [String?] {
                let target = Space(id: UUID(), name: "Arc Parked \(UUID().uuidString)", colour: 0,
                                   sharesSignIns: true, profile: browser.profileID)
                Spaces.write(Spaces.read() + [target])
                let group = TabGroup(id: UUID(), name: "Existing folder", collapsed: true)
                let old = URL(string: "https://arc-old.example/kept")!
                let added = URL(string: "https://arc-new.example/\(target.id.uuidString)")!
                Session.write(now: true, space: target.id, .init(
                    tabs: [.init(url: old.absoluteString, title: "Old", groupID: group.id)],
                    active: 0, groups: [group]
                ))
                browser.preloadSpaces()
                XCTAssertNotNil(browser.parked[target.id])
                let node = ArcSidebar.Node.item(.init(title: "Imported", url: added))
                let pinned: [ArcSidebar.Node] = folder.map { [.folder(.init(title: $0, items: [node]))] } ?? [node]
                let sidebar = ArcSidebar(favorites: [], spaces: [
                    .init(name: target.name, symbol: "briefcase", profile: "Default", pinned: pinned),
                ])

                XCTAssertEqual(browser.takeArc(sidebar).tabs, 1)
                browser.flushSession()

                XCTAssertNotEqual(browser.spaceID, target.id, "The target must never have been visited")
                let saved = Session.read(space: target.id)
                XCTAssertEqual(saved.tabs.map(\.url), [old.absoluteString, added.absoluteString])
                XCTAssertEqual(saved.groups?.first { $0.id == group.id }?.collapsed, true)
                if let folder {
                    let importedGroup = try XCTUnwrap(saved.groups?.first { $0.name == folder })
                    XCTAssertEqual(saved.tabs.last?.groupID, importedGroup.id)
                } else {
                    XCTAssertNil(saved.tabs.last?.groupID)
                }
                let restored = browser.loadRow(target.id)
                XCTAssertEqual(restored.tabs.compactMap { $0.address?.absoluteString }, saved.tabs.map(\.url))
                XCTAssertTrue(restored.tabs.allSatisfy { $0.built == nil })
                for tab in restored.tabs { tab.close() }
            }
        }
    }

    private func withBrowser(_ body: (Browser) throws -> Void) rethrows {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let prefs = Shared.prefs
        let oldPreferences = (prefs.usesSpaces, prefs.usesTabGroups, prefs.listsPins)
        let existingProfiles = Set(Profiles.shared.list.map(\.id))
        prefs.usesSpaces = true
        prefs.usesTabGroups = true
        prefs.listsPins = false
        let profile = Profiles.shared.add(named: "Arc lifecycle \(UUID().uuidString)")
        let browser = Browser(record: WindowRecord(space: profile.home), opensStartPage: false)
        defer {
            browser.leaveFiles()
            browser.closeAll()
            for profile in Profiles.shared.list where !existingProfiles.contains(profile.id) {
                Profiles.shared.delete(profile.id)
            }
            prefs.usesSpaces = oldPreferences.0
            prefs.usesTabGroups = oldPreferences.1
            prefs.listsPins = oldPreferences.2
            Disk.drain()
        }
        try body(browser)
    }
}
