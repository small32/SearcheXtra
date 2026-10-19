import AppKit
import SwiftUI

// The bookmarks bar: the top of the bookmarks, in a thin row above the page,
// as Chrome and Safari have one. A folder opens as a menu. More than the row
// holds scrolls sideways.
//
// Off unless asked for — Settings › Tabs, or Bookmarks › Show Bookmarks Bar
// — since the page gives up a strip of its height to it. It goes with the
// tabs when they fold away (⌘S) and when a video takes the screen.

struct BookmarksBar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var bookmarks: Bookmarks
    /// On the window's ground, above the page's card, with the tabs down the
    /// side: the ground's colour and no line of its own, the card's edge
    /// being the line (see CardEdge).
    var onFrame = false

    static let height: CGFloat = 30

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: browser.prefs.compactBookmarksBar ? 0 : 2) {
                ForEach(bookmarks.roots) { node in
                    Item(node: node, compact: browser.prefs.compactBookmarksBar, folderIcons: browser.prefs.bookmarkBarFolderIcons, websiteIcons: browser.prefs.bookmarkWebsiteIcons) { anchor in
                        if node.isFolder {
                            BookmarkMenu.shared.popUp(node, in: browser, from: anchor)
                        } else if let text = node.url, let url = URL(string: text) {
                            browser.visitBookmarkBar(url)
                        }
                    }
                    .contextMenu { BookmarkContextMenu(browser: browser, bookmarks: bookmarks, node: node) }
                    .overlay {
                        if let url = node.url.flatMap(URL.init(string:)) {
                            MiddleClick { browser.openBookmarkInBackground(url) }
                        }
                    }
                }
            }
            .padding(.horizontal, browser.prefs.compactBookmarksBar ? 6 : 10)
        }
        .frame(height: BookmarksBar.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(onFrame ? Palette.frame : Palette.ground)
        .overlay(alignment: .bottom) {
            if !onFrame { Rectangle().fill(Palette.hairline).frame(height: 1) }
        }
        .contentShape(Rectangle())
        .contextMenu { BookmarkContextMenu(browser: browser, bookmarks: bookmarks, node: nil) }
    }

    /// One on the bar. A bookmark without a name is its icon alone, in a
    /// square as tall as the others, its address on hover.
    struct Item: View {
        let node: Bookmark
        let compact: Bool
        let folderIcons: Bool
        let websiteIcons: Bool
        let act: (NSView?) -> Void
        @State private var hovering = false
        @State private var anchor: NSView?

        var body: some View {
            HStack(spacing: compact ? 3 : 6) {
                if node.isFolder && folderIcons {
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.ink)
                } else if !node.isFolder && websiteIcons {
                    BookmarkMark(node: node, size: 13)
                }
                if !node.unnamed || !websiteIcons {
                    Text(node.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .frame(maxWidth: 150, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                }
                if node.isFolder {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                }
            }
            .padding(.horizontal, node.unnamed ? 0 : (compact ? 4 : 8))
            .frame(minWidth: node.unnamed ? 22 : nil)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? Palette.hover : .clear))
            .contentShape(Rectangle())
            .background(MenuAnchor { anchor = $0 })
            .onTapGesture { act(anchor) }
            .onHover {
                hovering = $0
                if $0, node.isFolder { BookmarkBarPanel.hover(node, from: anchor) }
            }
            .help(node.url ?? node.title)
        }
    }

    private struct MenuAnchor: NSViewRepresentable {
        let ready: (NSView) -> Void
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async { ready(view) }
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {}
    }
}

/// One menu for the bar, its folder popups and the bookmark manager.
struct BookmarkContextMenu: View {
    let browser: Browser
    @ObservedObject var bookmarks: Bookmarks
    let node: Bookmark?
    var close: () -> Void = {}
    @ObservedObject private var prefs = Shared.prefs

    var body: some View {
        let parent = node.map { $0.isFolder ? $0.id : bookmarks.parent(of: $0.id) } ?? nil
        let urls = Bookmarks.urls(node.map { [$0] } ?? bookmarks.roots)
        if let node, let text = node.url, let url = URL(string: text) {
            Button(L10n.text("bookmarks.context.open")) { close(); browser.visitBookmarkBar(url) }
            Button(L10n.text("bookmarks.context.openTab")) { close(); browser.openBookmarkInBackground(url) }
            Divider()
        }
        Button(L10n.text("bookmarks.context.addPage")) { close(); bookmarks.askNewBookmark(in: parent) }
        Button(L10n.text("bookmarks.context.addFolder")) { close(); bookmarks.askNewFolder(in: parent) }
        Divider()
        if node?.isFolder != false {
            Button(L10n.text("bookmarks.context.openAll", String(urls.count))) {
                close()
                _ = browser.openBookmarks(urls, from: browser.active)
            }.disabled(urls.isEmpty)
        }
        Button(node?.isFolder == false ? L10n.text("bookmarks.context.openOneWindow") : L10n.text("bookmarks.context.openWindow", String(urls.count))) { openWindow(urls, privately: false) }.disabled(urls.isEmpty)
        Button(node?.isFolder == false ? L10n.text("bookmarks.context.openOnePrivate") : L10n.text("bookmarks.context.openPrivate", String(urls.count))) { openWindow(urls, privately: true) }.disabled(urls.isEmpty)
        Button(L10n.text("bookmarks.context.openGroup", String(urls.count))) {
            close()
            browser.openBookmarkGroup(urls, name: node?.title ?? L10n.text("Bookmarks.0247"))
        }.disabled(urls.isEmpty)
        if let node {
            Divider()
            if node.isFolder {
                Button(L10n.text("bookmarks.context.rename")) {
                    close()
                    Ask.name(L10n.text("bookmarks.context.rename"), placeholder: node.title, initial: node.title, confirm: L10n.text("Bookmarks.0224")) {
                        bookmarks.update(node.id, title: $0, url: nil)
                    }
                }
            } else {
                Button(L10n.text("bookmarks.context.edit")) { close(); bookmarks.askEdit(node) }
            }
            Divider()
            Button(L10n.text("bookmarks.context.cut")) { close(); bookmarks.copy(node, cut: true) }
            Button(L10n.text("bookmarks.context.copy")) { close(); bookmarks.copy(node) }
        }
        Button(L10n.text("bookmarks.context.paste")) { close(); bookmarks.paste(into: parent) }.disabled(!bookmarks.canPaste)
        if let node {
            Divider()
            Button(L10n.text("Bookmarks.0220")) { close(); bookmarks.askRemove(node) }
        }
        Divider()
        Button(L10n.text("bookmarks.context.manager")) { close(); browser.bookmarking = true }
        Menu(L10n.text("bookmarks.context.bar")) {
            Toggle(L10n.text("bookmarks.context.showBar"), isOn: $prefs.bookmarksBar)
            Toggle(L10n.text("bookmarks.bar.compact.title"), isOn: $prefs.compactBookmarksBar)
            Toggle(L10n.text("bookmarks.bar.folderIcons"), isOn: $prefs.bookmarkBarFolderIcons)
            Toggle(L10n.text("bookmarks.bar.websiteIcons"), isOn: $prefs.bookmarkWebsiteIcons)
        }
    }

    private func openWindow(_ urls: [URL], privately: Bool) {
        guard !urls.isEmpty else { return }
        close()
        let target = Browser(record: WindowRecord(space: browser.spaceID), opensStartPage: false)
        for (index, url) in urls.enumerated() {
            if privately { target.newShyTab(); target.visit(url) }
            else if index == 0 { target.visit(url) }
            else { target.open(url, foreground: false, atEnd: true, mayWait: true) }
        }
        if privately { for tab in target.tabs where !tab.shy && tab.isBlank { target.close(tab) } }
        Browsers.open(target, frame: nil)
    }

}

@MainActor
extension Browser {
    /// Explicit new-tab gestures never change the active page, even with Shift held.
    @discardableResult
    func openBookmarkInBackground(_ url: URL) -> Tab {
        open(url, foreground: false, from: active, mayWait: true)
    }
    @discardableResult
    func openBookmarks(_ urls: [URL], from source: Tab? = nil) -> [Tab] {
        urls.map { open($0, foreground: false, atEnd: true, from: source, mayWait: true) }
    }

    @discardableResult
    func openBookmarkGroup(_ urls: [URL], name: String) -> [Tab] {
        guard !urls.isEmpty else { return [] }
        prefs.usesTabGroups = true
        let opened = openBookmarks(urls, from: active)
        let group = addTabGroup(containing: opened[0])
        renameTabGroup(group, to: name)
        for tab in opened.dropFirst() { move(tab, toGroup: group) }
        editingGroupID = nil
        return opened
    }
}
