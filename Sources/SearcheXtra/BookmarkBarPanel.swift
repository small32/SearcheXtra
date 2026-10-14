import AppKit
import SwiftUI

/// The bar's folder list needs real rows: NSMenu consumes secondary clicks
/// before SwiftUI can provide the same actions as the bar and manager.
@MainActor
enum BookmarkBarPanel {
    private static var panels: [Panel] = []
    private static weak var browser: Browser?
    private static var rootID: Bookmark.ID?
    private static var mouse: Any?
    private static var resign: Any?
    private static var spring: DispatchWorkItem?

    static var isShown: Bool { !panels.isEmpty }

    static func show(_ folder: Bookmark, in browser: Browser, from anchor: NSView?) {
        hide()
        guard let anchor, let window = anchor.window else { return }
        self.browser = browser
        rootID = folder.id
        let spot = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        append(folder, browser: browser, parent: window, spot: spot, depth: 0)
        mouse = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            MainActor.assumeIsolated {
                if !panels.contains(where: { $0 === event.window }) { hide() }
            }
            return event
        }
        resign = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { hide() }
        }
    }

    /// Once one root folder is open, moving across the bar opens the next.
    static func hover(_ folder: Bookmark, from anchor: NSView?) {
        guard isShown, rootID != folder.id, let browser else { return }
        show(folder, in: browser, from: anchor)
    }

    private static func append(_ folder: Bookmark, browser: Browser, parent: NSWindow, spot: NSRect, depth: Int) {
        let screen = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let rowHeight: CGFloat = browser.prefs.compactBookmarksBar ? 23 : 29
        let count = max(1, folder.children?.count ?? 0)
        let desired = min(480, CGFloat(count) * rowHeight + 8)
        // Root folders always open below the bar. A long list scrolls there.
        let top = depth == 0 ? spot.minY - 2 : min(spot.maxY + 4, screen.maxY - 6)
        let size = NSSize(width: 286, height: min(desired, max(rowHeight + 8, top - screen.minY - 8)))
        var x = depth == 0 ? spot.minX : spot.maxX - 3
        if depth > 0, x + size.width > screen.maxX - 8 { x = spot.minX - size.width + 3 }
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        let panel = Panel(contentRect: NSRect(origin: NSPoint(x: x, y: top - size.height), size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = FirstClick(rootView: List(browser: browser, bookmarks: browser.bookmarks, folderID: folder.id, depth: depth, rowHeight: rowHeight))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = true
        parent.addChildWindow(panel, ordered: .above)
        panels.append(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    private static func trim(after depth: Int) {
        spring?.cancel()
        spring = nil
        while panels.count > depth + 1 {
            let panel = panels.removeLast()
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    private static func expand(_ node: Bookmark, from anchor: NSView?, depth: Int, immediately: Bool) {
        spring?.cancel()
        guard node.isFolder, let anchor, let parent = anchor.window, let browser else { trim(after: depth); return }
        let open = DispatchWorkItem {
            guard panels.indices.contains(depth), panels[depth] === parent else { return }
            trim(after: depth)
            let spot = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            append(node, browser: browser, parent: parent, spot: spot, depth: depth + 1)
        }
        spring = open
        if immediately { open.perform() }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: open) }
    }

    static func hide() {
        trim(after: -1)
        if let mouse { NSEvent.removeMonitor(mouse) }
        if let resign { NotificationCenter.default.removeObserver(resign) }
        mouse = nil
        resign = nil
        rootID = nil
        browser = nil
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private final class FirstClick: NSHostingView<List> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private struct List: View {
        let browser: Browser
        @ObservedObject var bookmarks: Bookmarks
        @ObservedObject private var prefs = Shared.prefs
        let folderID: Bookmark.ID
        let depth: Int
        let rowHeight: CGFloat
        @State private var selected: Bookmark.ID?
        @State private var anchors: [Bookmark.ID: NSView] = [:]
        @FocusState private var keyboard: Bool

        private var nodes: [Bookmark] { bookmarks.bookmark(folderID)?.children ?? [] }

        var body: some View {
            ScrollViewReader { scroller in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if nodes.isEmpty {
                            Text(L10n.text("Bookmarks.0263"))
                                .foregroundStyle(Palette.faint)
                                .frame(maxWidth: .infinity, minHeight: rowHeight)
                        }
                        ForEach(nodes) { node in
                            row(node).id(node.id)
                        }
                    }
                    .padding(4)
                }
                .onChange(of: selected) { _, value in if let value { scroller.scrollTo(value) } }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.ground))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hairline, lineWidth: 1))
            .contextMenu {
                if let folder = bookmarks.bookmark(folderID) {
                    BookmarkContextMenu(browser: browser, bookmarks: bookmarks, node: folder, close: hide)
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($keyboard)
            .onAppear { keyboard = true; selected = nodes.first?.id }
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, .space, .escape]) { key in
                switch key.key {
                case .escape: hide()
                case .leftArrow:
                    if depth > 0 { trim(after: depth - 1); panels.last?.makeKey() }
                    else { hide() }
                case .upArrow, .downArrow:
                    guard !nodes.isEmpty else { return .handled }
                    let index = nodes.firstIndex { $0.id == selected } ?? 0
                    let next = (index + (key.key == .upArrow ? -1 : 1) + nodes.count) % nodes.count
                    selected = nodes[next].id
                    trim(after: depth)
                default:
                    guard let node = nodes.first(where: { $0.id == selected }) else { return .handled }
                    if node.isFolder { expand(node, from: anchors[node.id], depth: depth, immediately: true) }
                    else if key.key != .rightArrow { visit(node) }
                }
                return .handled
            }
        }

        private func visit(_ node: Bookmark) {
            guard let url = node.url.flatMap(URL.init(string:)) else { return }
            hide()
            browser.visitBookmarkBar(url)
        }

        private func row(_ node: Bookmark) -> some View {
            HStack(spacing: 7) {
                if node.isFolder && prefs.bookmarkBarFolderIcons {
                    Image(systemName: "folder").frame(width: 16)
                } else if !node.isFolder && prefs.bookmarkWebsiteIcons {
                    BookmarkMark(node: node, size: 14)
                }
                Text(node.title).lineLimit(1)
                Spacer(minLength: 6)
                if node.isFolder { Image(systemName: "chevron.right").font(.system(size: 9)) }
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 8)
            .frame(height: rowHeight)
            .background(RoundedRectangle(cornerRadius: 4).fill(selected == node.id ? Palette.hover : .clear))
            .contentShape(Rectangle())
            .background(Anchor { anchors[node.id] = $0 })
            .onTapGesture {
                if node.isFolder { expand(node, from: anchors[node.id], depth: depth, immediately: true) }
                else { visit(node) }
            }
            .onHover { over in
                if over {
                    selected = node.id
                    expand(node, from: anchors[node.id], depth: depth, immediately: false)
                }
            }
            .contextMenu { BookmarkContextMenu(browser: browser, bookmarks: bookmarks, node: node, close: hide) }
            .overlay {
                if let url = node.url.flatMap(URL.init(string:)) {
                    MiddleClick { browser.openBookmarkInBackground(url) }
                }
            }
        }
    }

    private struct Anchor: NSViewRepresentable {
        let ready: (NSView) -> Void
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async { ready(view) }
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {}
    }
}
