import AppKit
import WebKit
import XCTest
@testable import SearcheXtra

@MainActor
final class FlowDragAuxiliaryTests: XCTestCase {
    private var browser: Browser!
    private var previousConfig = FlowDragConfig()
    private var previousSpaces = false
    private var previousGroups = false
    private var previousSplit = false
    private var previousPins: [UUID: [PinDef]] = [:]

    override func setUp() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Pins.load()
        previousPins = Pins.bySpace
        previousConfig = FlowDragSettings.shared.config
        previousSpaces = Shared.prefs.usesSpaces
        previousGroups = Shared.prefs.usesTabGroups
        previousSplit = Shared.prefs.splitView
        Shared.prefs.usesSpaces = false
        Shared.prefs.usesTabGroups = false
        Shared.prefs.splitView = false
        // WindowRecord starts with an empty row, but Browser reconciles the
        // globally shared pins into it. Keep each fixture's row independent.
        for space in Array(Pins.bySpace.keys) { Pins.forget(space) }
        browser = Browser(record: WindowRecord(), opensStartPage: false)
        XCTAssertEqual(browser.tabs.count, 1)
        XCTAssertNil(browser.active?.pin)
    }

    override func tearDown() async throws {
        guard browser != nil else { return }
        autoreleasepool {
            let fixture = browser!
            for little in LittleWindow.all where LittleWindow.tabs(for: fixture).contains(where: { $0 === little.tab }) {
                little.close()
            }
            fixture.closeAll()
            fixture.dozing?.invalidate()
            FlowDragSettings.shared.config = previousConfig
            let spaces = Set(Pins.bySpace.keys).union(previousPins.keys)
            for space in spaces { Pins.set(space, previousPins[space] ?? [], from: fixture) }
            // rememberSession's delayed callback is weak. Release the owner
            // before restoring preferences, which can otherwise write it again.
            browser = nil
        }
        Shared.prefs.usesSpaces = previousSpaces
        Shared.prefs.usesTabGroups = previousGroups
        Shared.prefs.splitView = previousSplit
        Disk.drain()
    }

    func testPrivatePeekAndItsBackgroundDragKeepSourceSignIns() throws {
        browser.newShyTab()
        let source = try XCTUnwrap(browser.active)
        browser.peek(url("preview"), from: source)
        let preview = try XCTUnwrap(browser.peekTab)
        XCTAssertTrue(preview.shy)
        XCTAssertTrue(preview.store === source.store)
        configure(active: false)
        let count = browser.tabs.count
        browser.performFlowDrag(preview, request())
        XCTAssertEqual(browser.tabs.count, count + 1)
        XCTAssertTrue(browser.peekTab === preview)
        XCTAssertEqual(browser.activeID, source.id)
        let opened = try XCTUnwrap(browser.tabs.first { $0.address == url("target") })
        XCTAssertTrue(opened.shy)
        XCTAssertTrue(opened.store === source.store)
    }

    func testPeekUsesOwningBrowserSpaceInsteadOfGlobalCurrentSpace() throws {
        let previousCurrent = Spaces.current
        defer { Spaces.current = previousCurrent }
        browser.spaceID = UUID()
        Spaces.current = Space.firstID
        let source = try XCTUnwrap(browser.active)
        browser.peek(url("preview"), from: source)
        let preview = try XCTUnwrap(browser.peekTab)
        XCTAssertTrue(preview.store === Spaces.store(for: browser.spaceID))
        XCTAssertFalse(preview.store === Spaces.store(for: Spaces.current))
    }

    func testCurrentPageDragNavigatesPeekWithoutSelectingDetachedTab() throws {
        let source = try XCTUnwrap(browser.active)
        browser.peek(url("preview"), from: source)
        let preview = try XCTUnwrap(browser.peekTab)
        configure(position: "current")
        let count = browser.tabs.count
        browser.performFlowDrag(preview, request())
        XCTAssertEqual(browser.tabs.count, count)
        XCTAssertEqual(browser.activeID, source.id)
        XCTAssertTrue(browser.peekTab === preview)
        XCTAssertEqual(preview.address, url("target"))
    }

    func testForegroundDragDismissesPeekAndSelectsNewTab() throws {
        let source = try XCTUnwrap(browser.active)
        browser.peek(url("preview"), from: source)
        let preview = try XCTUnwrap(browser.peekTab)
        configure(active: true)
        browser.performFlowDrag(preview, request())
        XCTAssertNil(browser.peekTab)
        XCTAssertEqual(browser.active?.address, url("target"))
        XCTAssertNotEqual(browser.activeID, source.id)
    }

    func testPrivateBackgroundDragFromRegularPeekKeepsRowAndPreview() throws {
        let source = try XCTUnwrap(browser.active)
        browser.peek(url("preview"), from: source)
        let preview = try XCTUnwrap(browser.peekTab)
        configure(active: false, incognito: true)
        browser.performFlowDrag(preview, request())
        XCTAssertTrue(browser.peekTab === preview)
        XCTAssertEqual(browser.activeID, source.id)
        let opened = try XCTUnwrap(browser.tabs.first { $0.address == url("target") })
        XCTAssertTrue(opened.shy)
        XCTAssertFalse(opened.store.isPersistent)
        XCTAssertFalse(opened.store === preview.store)
    }

    func testLittleWindowDragBelongsOnlyToItsPreparingBrowser() throws {
        LittleWindow.show(url("little"), for: browser, front: false)
        let little = try XCTUnwrap(LittleWindow.all.last)
        let selected = browser.activeID
        configure(active: false)
        let other = Browser(record: WindowRecord(), opensStartPage: false)
        defer { other.closeAll(); other.dozing?.invalidate() }
        let otherCount = other.tabs.count
        other.performFlowDrag(little.tab, request())
        XCTAssertEqual(other.tabs.count, otherCount)
        let count = browser.tabs.count
        browser.performFlowDrag(little.tab, request())
        XCTAssertEqual(browser.tabs.count, count + 1)
        XCTAssertEqual(browser.activeID, selected)
        XCTAssertTrue(LittleWindow.tabs(for: browser).contains { $0 === little.tab })
        little.close()
        let closedCount = browser.tabs.count
        browser.performFlowDrag(little.tab, request())
        XCTAssertEqual(browser.tabs.count, closedCount)
    }

    func testFirstPositionStaysAfterPinsAndBeforeOrdinaryTabs() throws {
        let pin = try XCTUnwrap(browser.active)
        pin.pin = url("pinned").absoluteString
        let first = browser.open(url("first"), foreground: true)
        let source = browser.open(url("source"), foreground: true)
        configure(position: "first", active: false)
        browser.performFlowDrag(source, request())
        XCTAssertEqual(browser.tabs[0].id, pin.id)
        XCTAssertEqual(browser.tabs[1].address, url("target"))
        XCTAssertEqual(browser.tabs[2].id, first.id)
        XCTAssertEqual(browser.activeID, source.id)
    }

    func testRightPositionKeepsSourceSplitTogether() throws {
        Shared.prefs.splitView = true
        let left = try XCTUnwrap(browser.active)
        XCTAssertEqual(browser.tabs.count, 1)
        XCTAssertNil(left.pin)
        let right = browser.open(url("right"), foreground: true)
        browser.pair(right, with: left, onLeft: false)
        configure(position: "right", active: false)
        browser.performFlowDrag(right, request())
        XCTAssertEqual(browser.tabs.prefix(3).map(\.id), [left.id, right.id, try XCTUnwrap(browser.tabs.first { $0.address == url("target") }).id])
        XCTAssertNotNil(browser.split(for: left))
    }

    func testImageSubdirectoryUsesCapturedSpaceDownloadFolder() async throws {
        let fixture = try LocalDownloadServer(size: 32)
        defer { fixture.stop() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let global = root.appendingPathComponent("global", isDirectory: true)
        let scoped = root.appendingPathComponent("space", isDirectory: true)
        let previousDownloads = browser.prefs.downloads
        defer { browser.prefs.downloads = previousDownloads; try? FileManager.default.removeItem(at: root) }
        browser.prefs.downloads = global
        Shared.prefs.usesSpaces = true
        browser.spaces[0].downloads = scoped.path
        browser.spaceID = browser.spaces[0].id
        var config = FlowDragConfig()
        config.rules = [.init(object: "image", pattern: "→", action: "saveImage", subdir: "pictures")]
        FlowDragSettings.shared.config = config
        let source = try XCTUnwrap(browser.active)
        var image = request()
        image.object = "image"
        image.imageUrl = fixture.url("image.bin").absoluteString
        browser.performFlowDrag(source, image)
        // Cookie lookup and the HTTP request have not returned yet.
        browser.spaces[0].downloads = nil
        let destination = scoped.appendingPathComponent("pictures/fixture.bin")
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: destination.path), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(try Data(contentsOf: destination), fixture.expectedBytes())
        XCTAssertFalse(FileManager.default.fileExists(atPath: global.appendingPathComponent("pictures/fixture.bin").path))
    }

    private func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:1/" + path)! }
    private func request() -> FlowDragRequest {
        .init(phase: "perform", id: "auxiliary-fixture", object: "link", pattern: "→", text: "", linkUrl: url("target").absoluteString, imageUrl: "", linkText: "Target", pageUrl: url("source").absoluteString)
    }
    private func configure(position: String = "right", active: Bool = true, incognito: Bool = false) {
        var config = FlowDragConfig()
        config.rules = [.init(object: "link", pattern: "→", action: "openTab", active: active, position: position, incognito: incognito)]
        FlowDragSettings.shared.config = config
    }
}
