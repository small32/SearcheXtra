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
    @ObservedObject private var prefs = Shared.prefs

    static let height: CGFloat = 30

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: browser.prefs.compactBookmarksBar ? 0 : 2) {
                ForEach(bookmarks.roots) { node in
                    Item(node: node, browser: browser, compact: browser.prefs.compactBookmarksBar, folderIcons: browser.prefs.bookmarkBarFolderIcons, websiteIcons: browser.prefs.bookmarkWebsiteIcons) { anchor in
                        if node.isFolder {
                            BookmarkMenu.shared.popUp(node, in: browser, from: anchor)
                        } else if let text = node.url, let url = URL(string: text) {
                            browser.visitBookmarkBar(url)
                        }
                    }
                    .contextMenu { contextMenu(for: node) }
                    .overlay {
                        if let url = node.url.flatMap(URL.init(string:)) {
                            MiddleClick { browser.open(url, foreground: false, from: browser.active, mayWait: true) }
                        }
                    }
                }
            }
            .padding(.horizontal, browser.prefs.compactBookmarksBar ? 6 : 10)
        }
        .frame(height: BookmarksBar.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.ground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
        .contextMenu { contextMenu(for: nil) }
        .modifier(SuperDragDropZone(browser:browser,region:"bookmarks"))
    }

    @ViewBuilder
    private func contextMenu(for node: Bookmark?) -> some View {
        let parent = node?.isFolder == true ? node?.id : nil
        let urls = Bookmarks.urls(node.map { [$0] } ?? bookmarks.roots)
        Button(L10n.text("bookmarks.context.addPage")) { bookmarks.askNewBookmark(in: parent) }
        Button(L10n.text("bookmarks.context.addFolder")) { bookmarks.askNewFolder(in: parent) }
        Divider()
        Button(L10n.text("bookmarks.context.openAll", String(urls.count))) {
            _ = browser.openBookmarks(urls, from: browser.active)
        }.disabled(urls.isEmpty)
        Button(L10n.text("bookmarks.context.openWindow", String(urls.count))) { openWindow(urls, privately: false) }.disabled(urls.isEmpty)
        Button(L10n.text("bookmarks.context.openPrivate", String(urls.count))) { openWindow(urls, privately: true) }.disabled(urls.isEmpty)
        Button(L10n.text("bookmarks.context.openGroup", String(urls.count))) {
            browser.openBookmarkGroup(urls, name: node?.title ?? L10n.text("Bookmarks.0247"))
        }.disabled(urls.isEmpty)
        if let node {
            Divider()
            Button(L10n.text("bookmarks.context.rename")) {
                Ask.name(L10n.text("bookmarks.context.rename"), placeholder: node.title, initial: node.title, confirm: L10n.text("Bookmarks.0224")) {
                    bookmarks.update(node.id, title: $0, url: nil)
                }
            }
            Divider()
            Button(L10n.text("bookmarks.context.cut")) { bookmarks.copy(node, cut: true) }
            Button(L10n.text("bookmarks.context.copy")) { bookmarks.copy(node) }
        }
        Button(L10n.text("bookmarks.context.paste")) { bookmarks.paste(into: parent) }.disabled(!bookmarks.canPaste)
        if let node {
            Divider()
            Button(L10n.text("Bookmarks.0220")) { bookmarks.askRemove(node) }
        }
        Divider()
        Button(L10n.text("bookmarks.context.manager")) { browser.bookmarking = true }
        Menu(L10n.text("bookmarks.context.bar")) {
            Toggle(L10n.text("bookmarks.context.showBar"), isOn: $prefs.bookmarksBar)
            Toggle(L10n.text("bookmarks.bar.compact.title"), isOn: $prefs.compactBookmarksBar)
            Toggle(L10n.text("bookmarks.bar.folderIcons"), isOn: $prefs.bookmarkBarFolderIcons)
            Toggle(L10n.text("bookmarks.bar.websiteIcons"), isOn: $prefs.bookmarkWebsiteIcons)
        }
    }

    private func openWindow(_ urls: [URL], privately: Bool) {
        guard !urls.isEmpty else { return }
        let target = Browser(record: WindowRecord(space: browser.spaceID), opensStartPage: false)
        for (index, url) in urls.enumerated() {
            if privately { target.newShyTab(); target.visit(url) }
            else if index == 0 { target.visit(url) }
            else { target.open(url, foreground: false, atEnd: true, mayWait: true) }
        }
        if privately { for tab in target.tabs where !tab.shy && tab.isBlank { target.close(tab) } }
        Browsers.open(target, frame: nil)
    }

    private struct Item: View {
        let node: Bookmark
        let browser: Browser
        let compact: Bool
        let folderIcons: Bool
        let websiteIcons: Bool
        let act: (NSView?) -> Void
        @State private var hovering = false
        @State private var anchor: NSView?
        @ObservedObject private var favicons = Favicons.shared

        var body: some View {
            HStack(spacing: compact ? 3 : 6) {
                if node.isFolder && folderIcons {
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Palette.ink)
                } else if !node.isFolder && websiteIcons {
                    Mark(icon: favicons.cached(node.site ?? ""), letter: String((node.host ?? "•").prefix(1)).uppercased(), size: 13)
                }
                Text(node.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                if node.isFolder {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(Palette.faint)
                }
            }
            .padding(.horizontal, compact ? 4 : 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? Palette.hover : .clear))
            .contentShape(Rectangle())
            .background(MenuAnchor(node: node, browser: browser) { anchor = $0 })
            .onTapGesture { act(anchor) }
            .onHover { hovering = $0 }
            .help(node.url ?? node.title)
            .task(id: websiteIcons) {
                if websiteIcons, let url = node.url.flatMap(URL.init(string:)) {
                    await favicons.fetchBookmark(url, privately: browser.active?.shy == true)
                }
            }
        }
    }

    private struct MenuAnchor: NSViewRepresentable {
        let node: Bookmark
        let browser: Browser
        let ready: (NSView) -> Void
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            BookmarkMenu.shared.registerBarAnchor(view, folder: node, browser: browser)
            DispatchQueue.main.async { ready(view) }
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {
            BookmarkMenu.shared.registerBarAnchor(view, folder: node, browser: browser)
        }
        static func dismantleNSView(_ view: NSView, coordinator: ()) {
            BookmarkMenu.shared.removeBarAnchor(view)
        }
    }
}

@MainActor
extension Browser {
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
