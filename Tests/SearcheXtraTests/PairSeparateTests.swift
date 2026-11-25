import AppKit
import SwiftUI
import XCTest
@testable import SearcheXtra

/// A pair carried down the column comes apart only where that was shown
/// (#883): the hand at rest over another tab dims the half that stays, and
/// only then does letting go take the other half out. Drive TabDrag at its
/// gesture boundary with real drop markers. The optional screenshots still
/// drive the hosted sidebar with AppKit events.
@MainActor
final class PairSeparateTests: XCTestCase {
    private var browsers: [Browser] = []
    private var windows: [NSWindow] = []
    private var markers: [SplitDropZone.Marker] = []
    private var restorePreferences: (() -> Void)?
    private var activationPolicy: NSApplication.ActivationPolicy?

    override class func setUp() {
        setenv("SEARCH_PROBE", "pair-separate-\(getpid())", 1)
        super.setUp()
    }

    override class func tearDown() {
        if let world = Store.world, world.hasPrefix("pair-separate-") {
            try? FileManager.default.removeItem(at: Store.folder)
            UserDefaults.standard.removePersistentDomain(forName: "com.officecommun.search.test.\(world)")
        }
        super.tearDown()
    }

    override func tearDown() async throws {
        TabDrag.testPointer = nil
        for browser in browsers {
            for tab in browser.tabs { TabDrag.shared.callOff(tab) }
        }
        TabDrag.shared.pressBegan()
        for marker in markers { TabDrag.shared.unregister(marker) }
        markers.removeAll()
        for window in windows { window.contentView = nil; window.close() }
        for browser in browsers { browser.window = nil; browser.closeAll() }
        restorePreferences?()
        if let activationPolicy { NSApp.setActivationPolicy(activationPolicy) }
        windows.removeAll()
        browsers.removeAll()
        try await Task.sleep(for: .milliseconds(250))
        try await super.tearDown()
    }

    func testCarriedOnWithoutStoppingStaysAPair() async throws {
        let (browser, t, window) = try await setUpColumn()
        let (from, to) = try dragPoints(t, in: window)
        carry(t[1], half: t[2], in: browser, from: from, to: to, in: window)
        XCTAssertNil(PairSeparation.shared.leaving, "nothing shown")
        let result = TabDrag.shared.finish(browser: browser, tab: t[1])
        if case .strip = result.drop { XCTFail("A moving pair must not split on release") }
        XCTAssertNotNil(browser.split(for: t[1]), "still a pair")
        XCTAssertEqual(browser.tabs.map(\.id), t.map(\.id))
    }

    func testAtRestOverAnotherTabShowsItThenSeparates() async throws {
        let (browser, t, window) = try await setUpColumn()
        let (from, to) = try dragPoints(t, in: window)
        carry(t[1], half: t[2], in: browser, from: from, to: to, in: window)
        try await waitForSeparation(of: t[2])
        XCTAssertEqual(PairSeparation.shared.leaving, t[2].id, "the half held is the one leaving")
        dropHalf(t[2], of: t[1], before: t[3], in: browser)
        XCTAssertNil(browser.split(for: t[1]), "apart, as shown")
        XCTAssertNil(PairSeparation.shared.leaving, "nothing shown once let go")
    }

    func testBackOverItsOwnPlaceTakesTheSeparationBack() async throws {
        let (browser, t, window) = try await setUpColumn()
        let (from, to) = try dragPoints(t, in: window)
        carry(t[1], half: t[2], in: browser, from: from, to: to, in: window)
        try await waitForSeparation(of: t[2])
        XCTAssertEqual(PairSeparation.shared.leaving, t[2].id)
        drag(t[1], in: browser, from: from, to: from, in: window)
        XCTAssertNil(PairSeparation.shared.leaving, "taken back")
        let result = TabDrag.shared.finish(browser: browser, tab: t[1])
        if case .strip = result.drop { XCTFail("Returning the pair must take its separation back") }
        XCTAssertNotNil(browser.split(for: t[1]), "still a pair")
    }

    /// Escape puts the carried tab down until the button comes up: the next
    /// move of the hand picked it up again, shadow and all.
    func testEscapedStaysPutDownUntilLetGo() async throws {
        let (browser, t, window) = try await setUpColumn()
        let (from, to) = try dragPoints(t, in: window)
        carry(t[1], half: t[2], in: browser, from: from, to: to, in: window)
        TabDrag.shared.cancel()
        XCTAssertEqual(TabDrag.shared.cancelledID, t[1].id)
        for travel in [4.0, 8, 12] {
            drag(t[1], in: browser, from: from, to: NSPoint(x: to.x, y: to.y - travel), in: window)
        }
        XCTAssertNil(TabDrag.shared.source(of: t[1]), "not picked up again")
        XCTAssertNil(PairSeparation.shared.leaving)
        let cancelled = TabDrag.shared.finish(browser: browser, tab: t[1])
        guard case .cancelled = cancelled.drop else { return XCTFail("Releasing a cancelled drag must drop nothing") }
        XCTAssertNotNil(browser.split(for: t[1]), "still a pair")
        XCTAssertEqual(browser.tabs.map(\.id), t.map(\.id))

        // The next carry is its own, not the cancelled one.
        let (nextFrom, nextTo) = try dragPoints(t, in: window)
        TabDrag.shared.pressBegan()
        carry(t[1], half: t[2], in: browser, from: nextFrom, to: nextTo, in: window)
        try await waitForSeparation(of: t[2])
        XCTAssertEqual(PairSeparation.shared.leaving, t[2].id)
        dropHalf(t[2], of: t[1], before: t[3], in: browser)
        XCTAssertNil(browser.split(for: t[1]), "apart, as shown")
    }

    /// The column with a separation shown, for looking at by eye: only when
    /// PAIR_SEPARATE_SHOTS names a folder.
    func testLooks() async throws {
        guard let folder = ProcessInfo.processInfo.environment["PAIR_SEPARATE_SHOTS"] else { return }
        let (_, tabs, window) = try await setUpColumn(hostSidebar: true)
        func shoot(_ name: String) throws {
            guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
        }
        let (from, to) = try dragPoints(tabs, in: window)
        try await send(.leftMouseDown, at: from, in: window)
        for point in dragPoints(from: from, to: to) {
            try await send(.leftMouseDragged, at: point, in: window)
        }
        XCTAssertEqual(CarryGuard.count, 1, "The pair is carried before taking screenshots")
        try shoot("carried")
        try await Task.sleep(for: .milliseconds(500))
        try shoot("shown")
        try await send(.leftMouseUp, at: to, in: window)
        try await settle()
        try shoot("after")
    }

    // MARK: - helpers

    private func setUpColumn(hostSidebar: Bool = false) async throws -> (Browser, [SearcheXtra.Tab], NSWindow) {
        _ = NSApplication.shared
        activationPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.prohibited)
        let prefs = Shared.prefs
        let previous = (prefs.sidebar, prefs.usesTabGroups, prefs.splitView, prefs.listsPins, prefs.roomyTabs)
        restorePreferences = {
            (prefs.sidebar, prefs.usesTabGroups, prefs.splitView, prefs.listsPins, prefs.roomyTabs) = previous
        }
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        browsers.append(browser)
        browser.prefs.sidebar = true
        browser.prefs.usesTabGroups = false
        browser.prefs.splitView = true
        browser.prefs.listsPins = false
        browser.prefs.roomyTabs = false
        for word in ["one", "two", "three", "four", "five"] {
            if browser.tabs.last?.isBlank == false { browser.newTab() }
            if let tab = browser.tabs.last { setPinDragFixture(tab, name: word) }
        }
        let t = browser.tabs
        browser.pair(t[2], with: t[1], onLeft: false)
        browser.select(t[2])
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: browser.prefs.sideWidth, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if hostSidebar {
            window.contentView = NSHostingView(rootView: SideBar(browser: browser, prefs: browser.prefs))
            window.orderFrontRegardless()
        } else {
            let strip = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
            window.contentView = strip
            for (index, tab) in t.enumerated() {
                let marker = SplitDropZone.Marker(frame: NSRect(x: 10, y: 320 - CGFloat(index) * 30,
                                                                  width: browser.prefs.sideWidth - 20, height: 28))
                marker.browser = browser
                marker.tab = tab
                strip.addSubview(marker)
                markers.append(marker)
                TabDrag.shared.register(marker)
            }
        }
        XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(window.frame) }, "never on a screen")
        windows.append(window)
        browser.window = window
        if hostSidebar { try await settle() }
        return (browser, t, window)
    }

    /// Grab the lower half of the pair just above the next row. Stay near
    /// the edge between the two rows so the pair does not reorder first.
    private func dragPoints(_ tabs: [SearcheXtra.Tab], in window: NSWindow) throws -> (NSPoint, NSPoint) {
        let half = try tabStripFrame(for: tabs[2], in: window)
        let next = try tabStripFrame(for: tabs[3], in: window)
        let x = half.midX
        return (NSPoint(x: x, y: half.minY + 4), NSPoint(x: x, y: next.maxY - 5))
    }

    private func dragPoints(from: NSPoint, to: NSPoint) -> [NSPoint] {
        [0.4, 0.75, 1].map { NSPoint(x: from.x, y: from.y + (to.y - from.y) * $0) }
    }

    private func carry(_ row: SearcheXtra.Tab, half: SearcheXtra.Tab, in browser: Browser, from: NSPoint, to: NSPoint, in window: NSWindow) {
        for point in dragPoints(from: from, to: to) { drag(row, in: browser, from: from, to: point, in: window) }
        XCTAssertTrue(TabDrag.shared.source(of: row) === half, "The half under the hand is carried")
    }

    private func drag(_ tab: SearcheXtra.Tab, in browser: Browser, from: NSPoint, to: NSPoint, in window: NSWindow) {
        TabDrag.testPointer = window.convertToScreen(NSRect(origin: to, size: .zero)).origin
        _ = TabDrag.shared.update(browser: browser, tab: tab, translation: CGSize(width: to.x - from.x, height: from.y - to.y))
    }

    private func waitForSeparation(of tab: SearcheXtra.Tab) async throws {
        for _ in 0..<100 {
            if PairSeparation.shared.leaving == tab.id { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func dropHalf(_ tab: SearcheXtra.Tab, of row: SearcheXtra.Tab, before next: SearcheXtra.Tab, in browser: Browser) {
        let result = TabDrag.shared.finish(browser: browser, tab: row)
        guard case .strip(let destination) = result.drop else { return XCTFail("The shown separation must be the drop") }
        XCTAssertTrue(result.source === tab)
        XCTAssertTrue(destination === next)
        browser.dropTabIntoStrip(result.source, before: destination)
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    private func send(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) async throws {
        TabDrag.testPointer = window.convertToScreen(NSRect(origin: point, size: .zero)).origin
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        ))
        if type == .leftMouseDown {
            // The app's local monitor clears cancellation when a new press
            // starts, even if the earlier gesture never delivered onEnded.
            NSApp.sendEvent(event)
        } else {
            window.sendEvent(event)
        }
        try await Task.sleep(for: .milliseconds(30))
    }
}
