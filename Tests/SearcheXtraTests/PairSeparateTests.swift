import AppKit
import SwiftUI
import XCTest
@testable import SearcheXtra

/// A pair carried down the column comes apart only where that was shown
/// (#883): the hand at rest over another tab dims the half that stays, and
/// only then does letting go take the other half out. Hosted as
/// PinDragTests does, in a borderless window far off every screen; the hand
/// is told to TabDrag through `testPointer`, since the mouse is elsewhere.
@MainActor
final class PairSeparateTests: XCTestCase {
    private var browsers: [Browser] = []
    private var windows: [NSWindow] = []
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
        try await carry(from: from, to: to, in: window)
        XCTAssertNil(PairSeparation.shared.leaving, "nothing shown")
        try await send(.leftMouseUp, at: to, in: window)
        try await settle()
        XCTAssertNotNil(browser.split(for: t[1]), "still a pair")
        XCTAssertEqual(browser.tabs.map(\.id), t.map(\.id))
    }

    func testAtRestOverAnotherTabShowsItThenSeparates() async throws {
        let (browser, t, window) = try await setUpColumn()
        let (from, to) = try dragPoints(t, in: window)
        try await carry(from: from, to: to, in: window)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(PairSeparation.shared.leaving, t[2].id, "the half held is the one leaving")
        try await send(.leftMouseUp, at: to, in: window)
        try await settle()
        XCTAssertNil(browser.split(for: t[1]), "apart, as shown")
        XCTAssertNil(PairSeparation.shared.leaving, "nothing shown once let go")
    }

    func testBackOverItsOwnPlaceTakesTheSeparationBack() async throws {
        let (browser, t, window) = try await setUpColumn()
        let (from, to) = try dragPoints(t, in: window)
        try await carry(from: from, to: to, in: window)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(PairSeparation.shared.leaving, t[2].id)
        try await send(.leftMouseDragged, at: from, in: window)
        XCTAssertNil(PairSeparation.shared.leaving, "taken back")
        try await send(.leftMouseUp, at: from, in: window)
        try await settle()
        XCTAssertNotNil(browser.split(for: t[1]), "still a pair")
    }

    /// Escape puts the carried tab down until the button comes up: the next
    /// move of the hand picked it up again, shadow and all. Escape is sent
    /// to TabDrag directly, since its monitor asks whether the real button
    /// is down.
    func testEscapedStaysPutDownUntilLetGo() async throws {
        let (browser, t, window) = try await setUpColumn()
        let (from, to) = try dragPoints(t, in: window)
        try await carry(from: from, to: to, in: window)
        XCTAssertEqual(CarryGuard.count, 1, "carried")
        TabDrag.shared.cancel()
        try await settle()
        for travel in [4.0, 8, 12] {
            try await send(.leftMouseDragged, at: NSPoint(x: to.x, y: to.y - travel), in: window)
        }
        XCTAssertEqual(CarryGuard.count, 0, "not picked up again")
        try await send(.leftMouseUp, at: NSPoint(x: to.x, y: to.y - 12), in: window)
        try await settle()
        XCTAssertNotNil(browser.split(for: t[1]), "still a pair")
        XCTAssertEqual(browser.tabs.map(\.id), t.map(\.id))

        // The next carry is its own, not the cancelled one.
        let (nextFrom, nextTo) = try dragPoints(t, in: window)
        try await carry(from: nextFrom, to: nextTo, in: window)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(PairSeparation.shared.leaving, t[2].id)
        try await send(.leftMouseUp, at: nextTo, in: window)
        try await settle()
        XCTAssertNil(browser.split(for: t[1]), "apart, as shown")
    }

    /// The column with a separation shown, for looking at by eye: only when
    /// PAIR_SEPARATE_SHOTS names a folder.
    func testLooks() async throws {
        guard let folder = ProcessInfo.processInfo.environment["PAIR_SEPARATE_SHOTS"] else { return }
        let (_, tabs, window) = try await setUpColumn()
        func shoot(_ name: String) throws {
            guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
        }
        let (from, to) = try dragPoints(tabs, in: window)
        try await carry(from: from, to: to, in: window)
        try shoot("carried")
        try await Task.sleep(for: .milliseconds(500))
        try shoot("shown")
        try await send(.leftMouseUp, at: to, in: window)
        try await settle()
        try shoot("after")
    }

    // MARK: - helpers

    private func setUpColumn() async throws -> (Browser, [SearcheXtra.Tab], NSWindow) {
        _ = NSApplication.shared
        activationPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.prohibited)
        let prefs = Shared.prefs
        let previous = (prefs.sidebar, prefs.usesTabGroups, prefs.splitView, prefs.listsPins, prefs.roomyTabs)
        restorePreferences = {
            (prefs.sidebar, prefs.usesTabGroups, prefs.splitView, prefs.listsPins, prefs.roomyTabs) = previous
        }
        let browser = Browser(record: WindowRecord())
        browsers.append(browser)
        browser.prefs.sidebar = true
        browser.prefs.usesTabGroups = false
        browser.prefs.splitView = true
        browser.prefs.listsPins = false
        browser.prefs.roomyTabs = false
        for word in ["one", "two", "three", "four", "five"] {
            if browser.tabs.last?.isBlank == false { browser.newTab() }
            browser.tabs.last?.restore(url: URL(string: "about:blank#\(word)")!, title: word)
        }
        let t = browser.tabs
        browser.pair(t[2], with: t[1], onLeft: false)
        browser.select(t[2])
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: browser.prefs.sideWidth, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SideBar(browser: browser, prefs: browser.prefs))
        window.orderFrontRegardless()
        XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(window.frame) }, "never on a screen")
        windows.append(window)
        browser.window = window
        try await settle()
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

    private func carry(from: NSPoint, to: NSPoint, in window: NSWindow) async throws {
        try await send(.leftMouseDown, at: from, in: window)
        for fraction in [0.4, 0.75, 1] {
            let y = from.y + (to.y - from.y) * fraction
            try await send(.leftMouseDragged, at: NSPoint(x: from.x, y: y), in: window)
        }
        XCTAssertEqual(CarryGuard.count, 1, "The pair is carried before testing its drop")
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
