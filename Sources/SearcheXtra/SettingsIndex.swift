import SwiftUI

// Every line of Settings, written down once.
//
// Settings › each section draws its groups from this list, and the ⌘F
// "Find a setting" field filters the same list, so a setting can't be on a
// page and missing from the search, or the other way round. Each line says
// which keys it reads and writes (the bench's `settings` verb answers with
// them, see Tests/settings_layout.py). The controls themselves are drawn in
// Settings.swift; what a merged control does to the old keys is here, on
// Preferences, so the switch and the bench write the same thing.

/// A titled group inside a section: a small heading with its icon, then
/// its rows in one card.
struct SettingsGroup: Identifiable {
    let id: String
    let page: SettingsPanel.Page
    let title: String
    let icon: String
}

/// One row of Settings.
struct SettingsItem: Identifiable {
    enum Kind {
        /// A control on the right of the row.
        case control
        /// A control wide enough to go under the words (pictures, long
        /// segmented choices).
        case wide
        /// No control: a feature that is always there, said so plainly.
        /// Only shown by the find field.
        case note
    }

    let id: String
    let group: String
    let icon: String
    let title: String
    /// One short line, under ~90 characters.
    let detail: String
    /// The rest of the story, behind the (i).
    var more: String? = nil
    /// The defaults keys the row reads and writes.
    var keys: [String] = []
    /// Other words someone might type for it.
    var words: [String] = []
    var kind: Kind = .control
    /// The row that makes this one count. It stands at the same level as
    /// every other row, and is only there while that one makes it count
    /// (see SettingsIndex.applies).
    var parent: String? = nil
    /// Only the find field shows it (moved to a menu, or always on).
    var findOnly = false

    var page: SettingsPanel.Page { SettingsIndex.group(group)?.page ?? .general }
}

enum SettingsIndex {
    // MARK: - groups

    static let groups: [SettingsGroup] = [
        .init(id: "browser", page: .general, title: L10n.text("upstream.settings.34b9767b44"), icon: "globe.desk"),
        .init(id: "bookmarkManager", page: .bookmarks, title: L10n.text("App.0170"), icon: "book"),
        .init(id: "bookmarkAppearance", page: .bookmarks, title: L10n.text("flowDrag.rootFolder"), icon: "bookmark"),
        .init(id: "extensions", page: .extensions, title: L10n.text("Extensions.0461"), icon: "puzzlepiece.extension"),
        .init(id: "downloads", page: .general, title: L10n.text("Recall.0660"), icon: "arrow.down.circle"),

        .init(id: "theme", page: .appearance, title: L10n.text("upstream.settings.e3e7d8fb22"), icon: "circle.lefthalf.filled"),
        .init(id: "window", page: .appearance, title: L10n.text("Windows.1287"), icon: "macwindow"),
        .init(id: "tablook", page: .appearance, title: L10n.text("App.0145"), icon: "textformat.size"),
        .init(id: "motion", page: .appearance, title: L10n.text("upstream.settings.e040db2b7f"), icon: "wind"),

        .init(id: "newtabs", page: .tabs, title: L10n.text("upstream.settings.406f113ad5"), icon: "plus.square"),
        .init(id: "memory", page: .tabs, title: L10n.text("upstream.settings.89c8a2851d"), icon: "moon.zzz"),
        .init(id: "tabbar", page: .tabs, title: L10n.text("upstream.settings.2f0b565b0d"), icon: "number"),

        .init(id: "search", page: .browsing, title: L10n.text("upstream.settings.98cc363c01"), icon: "magnifyingglass"),
        .init(id: "links", page: .browsing, title: L10n.text("flowDrag.object.link"), icon: "link"),
        .init(id: "reading", page: .browsing, title: L10n.text("Settings.0845"), icon: "doc.plaintext"),
        .init(id: "video", page: .browsing, title: L10n.text("upstream.settings.bc17c1f017"), icon: "play.rectangle"),
        .init(id: "pages", page: .browsing, title: L10n.text("upstream.settings.600584c2d5"), icon: "doc.richtext"),

        .init(id: "arc", page: .spaces, title: L10n.text("upstream.settings.70cd152ff9"), icon: "arrow.down.forward.square"),
        .init(id: "spaces", page: .spaces, title: L10n.text("upstream.settings.eadc6e8b87"), icon: "rectangle.3.group"),
        .init(id: "pins", page: .spaces, title: L10n.text("upstream.settings.76859a9147"), icon: "pin"),
        .init(id: "opening", page: .spaces, title: L10n.text("upstream.settings.67e8dcea47"), icon: "command"),

        .init(id: "passwords", page: .passwords, title: L10n.text("Settings.0784"), icon: "key"),
        .init(id: "apple", page: .passwords, title: L10n.text("applePasswords.name"), icon: "lock.rectangle.stack"),

        .init(id: "blocking", page: .privacy, title: L10n.text("upstream.settings.d785c0d4b3"), icon: "shield"),
        .init(id: "permissions", page: .privacy, title: L10n.text("upstream.settings.dc5f2eb465"), icon: "checkmark.shield"),
        .init(id: "clear", page: .privacy, title: L10n.text("Recall.0651"), icon: "trash"),

        .init(id: "mouse", page: .keyboard, title: L10n.text("upstream.settings.4786b531bc"), icon: "computermouse"),

        .init(id: "updates", page: .about, title: L10n.text("Settings.0849"), icon: "arrow.triangle.2.circlepath"),
        .init(id: "developer", page: .about, title: L10n.text("upstream.settings.7e08ebec5e"), icon: "hammer"),
    ]

    static func group(_ id: String) -> SettingsGroup? { groups.first { $0.id == id } }
    static func groups(of page: SettingsPanel.Page) -> [SettingsGroup] { groups.filter { $0.page == page } }
    static func items(in group: String) -> [SettingsItem] { items.filter { $0.group == group && !$0.findOnly } }

    // MARK: - rows

    static let items: [SettingsItem] = ([
        // General
        .init(id: "general.default", group: "browser", icon: "link.badge.plus",
              title: L10n.text("Settings.0702"), detail: L10n.text("upstream.settings.39f47c84c1"),
              words: ["default browser"]),
        .init(id: "general.import", group: "browser", icon: "square.and.arrow.down.on.square",
              title: L10n.text("ImportPanel.0558"), detail: L10n.text("upstream.settings.563204d064"),
              more: L10n.text("upstream.settings.d50751fdf5"),
              words: ["import", "chrome", "safari", "arc", "migrate"]),
        .init(id: "interface.language", group: "browser", icon: "character.bubble",
              title: L10n.text("language.title"), detail: L10n.text("language.detail"),
              keys: ["interface.language"], words: ["language", "Chinese", "English"]),
        .init(id: "startPage", group: "browser", icon: "house",
              title: L10n.text("startPage.title"), detail: L10n.text("upstream.settings.startPage.short"),
              more: L10n.text("startPage.detail"),
              keys: ["start.page"], words: ["home page", "startup", "blank"], kind: .wide),
        .init(id: "quit.confirm", group: "browser", icon: "power",
              title: L10n.text("upstream.settings.32c4fd5631"), detail: L10n.text("upstream.settings.88cd4455ba"),
              keys: ["quit.confirm"], words: ["quit", "cmd q"]),
        .init(id: "downloads.folder", group: "downloads", icon: "folder",
              title: L10n.text("Settings.0801"), detail: "", keys: ["downloads"], words: ["download folder"]),
        .init(id: "downloads.ask", group: "downloads", icon: "questionmark.folder",
              title: L10n.text("Settings.0803"), detail: L10n.text("upstream.settings.76a69eeb06"),
              keys: ["downloads.ask"]),
        .init(id: "downloads.button", group: "downloads", icon: "arrow.down.to.line",
              title: L10n.text("Settings.0804"), detail: L10n.text("upstream.settings.6b0a8835e7"),
              keys: ["downloads.button"]),

        // Appearance
        .init(id: "look", group: "theme", icon: "circle.lefthalf.filled",
              title: L10n.text("Settings.0716"), detail: L10n.text("upstream.settings.8e7edca2fe"),
              keys: ["look"], words: ["dark mode", "light mode", "theme", "system"], kind: .wide),
        .init(id: "pages.dusk", group: "theme", icon: "moon",
              title: L10n.text("sync.settings.dark"), detail: L10n.text("upstream.settings.0000d6d9cb"),
              more: L10n.text("upstream.settings.87bc8b1e5d"),
              keys: ["pages.dusk"], words: ["dark", "dusk", "night"], parent: "look"),
        .init(id: "tabs.layout", group: "window", icon: "sidebar.left",
              title: L10n.text("App.0145"), detail: L10n.text("upstream.88017ad.7e5d69be4d"),
              more: L10n.text("upstream.88017ad.3aa9715b2e"),
              keys: ["sidebar", "sidebar.position", "sidebar.icons"],
              words: ["sidebar", "vertical tabs", "column", "left", "right", "top", "tab bar", "position",
                      "icons only", "compact", "collapsed", "narrow", "favicons"], kind: .wide),
        .init(id: "sidebar.hides", group: "window", icon: "sidebar.squares.left",
              title: L10n.text("upstream.settings.b0954cf556"), detail: L10n.text("upstream.settings.2da0207a22"),
              keys: ["sidebar.hides"], words: ["auto hide", "sidebar"], parent: "tabs.layout"),
        .init(id: "layout.cards", group: "window", icon: "rectangle.inset.filled",
              title: L10n.text("sync.settings.cards"), detail: L10n.text("upstream.settings.0ad654940b"),
              more: L10n.text("upstream.settings.23eecbed74"),
              keys: ["layout.cards"], words: ["edge to edge", "rounded", "margin"], kind: .wide, parent: "tabs.layout"),
        .init(id: "toolbar.left", group: "window", icon: "arrow.left.arrow.right",
              title: L10n.text("Settings.0752"), detail: L10n.text("Settings.0753"),
              keys: ["toolbar.left"], words: ["toolbar", "buttons", "navigation"], parent: "tabs.layout"),
        .init(id: "sidebar.roomy", group: "tablook", icon: "textformat.size.larger",
              title: L10n.text("sync.settings.roomy"), detail: L10n.text("upstream.settings.7daa104ab5"),
              keys: ["sidebar.roomy"], words: ["bigger", "larger", "text size", "accessibility"], parent: "tabs.layout"),
        .init(id: "glyph", group: "tablook", icon: "app",
              title: L10n.text("Settings.0760"), detail: L10n.text("Settings.0761"),
              keys: ["glyph"], words: ["favicon", "icons", "letters"]),
        .init(id: "tabs.reading", group: "tablook", icon: "text.line.first.and.arrowtriangle.forward",
              title: L10n.text("Settings.0764"), detail: L10n.text("upstream.settings.7d2b1d7401"),
              keys: ["tabs.reading"], words: ["progress", "scroll"]),
        .init(id: "tabs.give", group: "tablook", icon: "hand.point.up.left",
              title: L10n.text("upstream.settings.2defb63e14"), detail: L10n.text("upstream.settings.3c14e67218"),
              keys: ["tabs.give"], words: ["press", "animation", "bounce"]),
        .init(id: "bookmarks.bar", group: "tablook", icon: "bookmark",
              title: L10n.text("Settings.0762"), detail: L10n.text("upstream.settings.c487bf83e0"),
              keys: ["bookmarks.bar"], words: ["favorites bar"]),
        .init(id: "motion.light", group: "motion", icon: "leaf",
              title: L10n.text("upstream.settings.323cb0f56b"), detail: L10n.text("upstream.settings.989186de64"),
              more: L10n.text("upstream.settings.e22db26a6e"),
              keys: [Motion.lightKey], words: ["battery", "animations", "motion"]),

        // Bookmarks and extension management retained from this fork.
        .init(id: "bookmarks.manager", group: "bookmarkManager", icon: "book",
              title: L10n.text("bookmarks.manager.title"), detail: L10n.text("bookmarks.manager.detail"),
              words: ["bookmarks", "import", "sort", "folders"]),
        .init(id: "bookmarks.bar.compact", group: "bookmarkAppearance", icon: "arrow.down.right.and.arrow.up.left",
              title: L10n.text("bookmarks.bar.compact.title"), detail: L10n.text("bookmarks.bar.compact.detail"),
              keys: ["bookmarks.bar.compact"], words: ["compact", "menu"]),
        .init(id: "bookmarks.bar.folderIcons", group: "bookmarkAppearance", icon: "folder",
              title: L10n.text("bookmarks.bar.folderIcons"), detail: L10n.text("upstream.settings.b7c83284a4"),
              keys: ["bookmarks.bar.folderIcons"], words: ["folder", "icon"]),
        .init(id: "bookmarks.bar.websiteIcons", group: "bookmarkAppearance", icon: "globe",
              title: L10n.text("bookmarks.bar.websiteIcons"), detail: L10n.text("upstream.settings.094776bd6d"),
              keys: ["bookmarks.bar.websiteIcons"], words: ["favicon", "website", "icon"]),
        .init(id: "bookmarks.bar.opening", group: "bookmarkAppearance", icon: "arrow.up.forward.square",
              title: L10n.text("bookmarks.bar.opening.title"), detail: L10n.text("bookmarks.bar.opening.detail"),
              keys: ["bookmarks.bar.opening"], words: ["background", "foreground", "click"]),
        .init(id: "extensions.manager", group: "extensions", icon: "puzzlepiece.extension",
              title: L10n.text("extensions.manage"), detail: L10n.text("upstream.settings.6b706ef1d9"),
              words: ["extensions", "user scripts", "ScriptCat", "MV2", "MV3", "pin"], findOnly: true),
        // Tabs
        .init(id: "flowDrag.open", group: "newtabs", icon: "hand.draw",
              title: L10n.text("flowDrag.title"), detail: L10n.text("upstream.settings.826e825d58"),
              words: ["drag", "gesture", "search", "background", "FlowMouse"]),
        .init(id: "newtab.floating", group: "newtabs", icon: "rectangle.on.rectangle",
              title: L10n.text("upstream.address.floatingNewTab"), detail: L10n.text("upstream.address.floatingNewTab.detail"),
              keys: ["newtab.floating"], words: ["new tab", "floating", "address"]),
        .init(id: "tabs.newPlace", group: "newtabs", icon: "arrow.right.to.line",
              title: L10n.text("sync.settings.newPlace"), detail: L10n.text("upstream.settings.7614d2c22d"),
              more: L10n.text("sync.settings.newPlace.detail"),
              keys: ["tabs.newPlace"], words: ["new tab", "order"]),
        .init(id: "tabs.newAfterLast", group: "newtabs", icon: "plus.rectangle.on.rectangle",
              title: L10n.text("sync.settings.afterLast"), detail: L10n.text("upstream.settings.cb5248336a"),
              keys: ["tabs.newAfterLast"], words: ["last tab"]),
        .init(id: "tabs.closeGoesBack", group: "newtabs", icon: "arrow.uturn.backward",
              title: L10n.text("upstream.88017ad.fab3c3b5c5"), detail: L10n.text("upstream.88017ad.5198315823"),
              more: L10n.text("upstream.88017ad.8541bf11cc"),
              keys: ["tabs.closeGoesBack"], words: ["close", "previous tab", "recent"]),
        .init(id: "tabs.lazy", group: "newtabs", icon: "hourglass",
              title: L10n.text("Settings.0768"), detail: L10n.text("upstream.settings.9631a40911"),
              more: L10n.text("upstream.settings.4724442b27"),
              keys: ["tabs.lazy"], words: ["lazy", "background"]),
        .init(id: "tabs.popupWindows", group: "newtabs", icon: "macwindow.on.rectangle",
              title: L10n.text("upstream.settings.e29218eaf4"), detail: L10n.text("upstream.settings.7ed9c707ec"),
              more: L10n.text("upstream.settings.5063c25d1c"),
              keys: ["tabs.popupWindows"], words: ["popup", "pop-up", "window"]),
        .init(id: "tabs.sleep", group: "memory", icon: "moon.zzz",
              title: L10n.text("Settings.0766"), detail: L10n.text("upstream.settings.4bbda4d948"),
              more: L10n.text("upstream.settings.788533bb3f"),
              keys: ["tabs.sleep", SleepPace.key], words: ["memory", "discard", "suspend", "ram"], kind: .wide),
        .init(id: "tabs.close.after", group: "memory", icon: "timer",
              title: L10n.text("sync.settings.tabLife"), detail: L10n.text("upstream.settings.90e5ddd4a8"),
              more: L10n.text("upstream.settings.8a54ad31b4"),
              keys: ["tabs.close.after"], words: ["auto close", "archive", "clean up"]),
        .init(id: "tabs.shortcuts", group: "tabbar", icon: "command",
              title: L10n.text("upstream.settings.896a867f8d"), detail: L10n.text("upstream.settings.ed84f9bee9"),
              keys: ["tabs.shortcuts"], words: ["numbers", "shortcut"]),
        .init(id: "tabs.address", group: "tabbar", icon: "lock",
              title: L10n.text("upstream.settings.cbc613b68a"), detail: L10n.text("upstream.settings.93ebd696f1"),
              more: L10n.text("upstream.settings.4d69cb55d1"),
              keys: ["tabs.address"], words: ["url", "domain", "security", "address bar"]),

        // Browsing
        .init(id: "search.engine", group: "search", icon: "magnifyingglass",
              title: L10n.text("Settings.0711"), detail: L10n.text("Settings.0749"),
              keys: ["search.engine", "search.custom"], words: ["google", "duckduckgo", "engine", "kagi", "bing"]),
        .init(id: "search.suggest", group: "search", icon: "text.magnifyingglass",
              title: L10n.text("suggestions.title"), detail: L10n.text("upstream.settings.1516448a33"),
              more: L10n.text("upstream.settings.e03f7e7b86"),
              keys: ["search.suggest"], words: ["autocomplete", "suggest"]),
        .init(id: "search.keywords", group: "search", icon: "character.cursor.ibeam",
              title: L10n.text("Settings.0712"), detail: L10n.text("upstream.settings.d030890ae4"),
              keys: ["search.keywords"], words: ["keyword", "bang"]),
        .init(id: "links.little", group: "links", icon: "rectangle.on.rectangle",
              title: L10n.text("Settings.0724"), detail: L10n.text("Settings.0725"),
              keys: ["links.little"], words: ["little arc", "mini window"]),
        .init(id: "reader.twins", group: "reading", icon: "doc.text",
              title: L10n.text("upstream.settings.c57ac240ab"), detail: L10n.text("upstream.settings.107729ebd1"),
              more: L10n.text("upstream.88017ad.f654ec5618"),
              keys: ["reader.twins"], words: ["markdown", "reader"]),
        .init(id: "reader.follows", group: "reading", icon: "circle.righthalf.filled",
              title: L10n.text("upstream.settings.cc16e3115a"), detail: L10n.text("upstream.settings.3fffe20d2d"),
              more: L10n.text("upstream.settings.ca804abfa5"),
              keys: ["reader.follows"], words: ["reader", "dark"]),
        .init(id: "float.style", group: "video", icon: "pip",
              title: L10n.text("upstream.settings.7676fb16a0"), detail: L10n.text("upstream.settings.1ec81ee4d6"),
              more: L10n.text("upstream.settings.848825439e"),
              keys: ["float.style"], words: ["pip", "picture in picture", "mini player"]),
        .init(id: "float.own", group: "video", icon: "pip.exit",
              title: L10n.text("upstream.settings.23626d0e65"), detail: L10n.text("upstream.settings.e21bf7297a"),
              more: L10n.text("upstream.settings.aa70f49e34"),
              keys: ["float.leave", "float.away"], words: ["pip", "picture in picture", "switch apps"], kind: .wide),
        .init(id: "media.click", group: "video", icon: "play.slash",
              title: L10n.text("Settings.0738"), detail: L10n.text("upstream.settings.4a6670977d"),
              keys: [Preferences.waitsKey], words: ["autoplay", "auto-play"]),
        .init(id: "fullscreen.escapeTwice", group: "video", icon: "escape",
              title: L10n.text("upstream.settings.e5c02af6e8"), detail: L10n.text("upstream.settings.bd656c0164"),
              keys: ["fullscreen.escapeTwice"], words: ["escape", "full screen"]),
        .init(id: "pageZoom", group: "pages", icon: "plus.magnifyingglass",
              title: L10n.text("Settings.0718"), detail: L10n.text("upstream.settings.d0f97cfeef"),
              keys: ["pageZoom"], words: ["zoom", "size", "scale"]),
        .init(id: "pages.120", group: "pages", icon: "speedometer",
              title: L10n.text("Settings.0732"), detail: L10n.text("upstream.settings.4eea36338e"),
              more: L10n.text("upstream.settings.06c35cf447"),
              keys: ["pages.120.mode", "pages.120"], words: ["promotion", "frame rate", "fps", "smooth", "120"]),

        // Spaces & Pins
        .init(id: "arc.setup", group: "arc", icon: "wand.and.stars",
              title: L10n.text("upstream.settings.b84398bf93"), detail: L10n.text("upstream.settings.db96a8e140"),
              more: L10n.text("upstream.settings.607c3f0f39"),
              words: ["arc", "the browser company"]),
        .init(id: "arc.import", group: "arc", icon: "square.and.arrow.down",
              title: L10n.text("upstream.settings.324dd4fcf8"), detail: L10n.text("upstream.settings.99a5631c83"),
              words: ["arc", "import"]),
        .init(id: "spaces", group: "spaces", icon: "square.stack.3d.up",
              title: L10n.text("section.spaces"), detail: L10n.text("upstream.settings.d17c7b2deb"),
              more: L10n.text("upstream.settings.d7c0819a61"),
              keys: ["spaces"], words: ["workspaces", "profiles"]),
        .init(id: "profiles", group: "spaces", icon: "person.2",
              title: L10n.text("profiles.title"), detail: L10n.text("upstream.settings.a27f029ce4"),
              more: L10n.text("upstream.settings.3906b51121"),
              words: ["profile", "accounts", "work", "personal"]),
        .init(id: "pins.keep", group: "pins", icon: "pin.circle",
              title: L10n.text("upstream.settings.a6d370950b"), detail: L10n.text("upstream.settings.3a34d1db9a"),
              more: L10n.text("upstream.settings.da76021d36"),
              keys: ["pins.home", "pins.peek"], words: ["pinned tabs", "go home", "reset pin"]),
        .init(id: "pins.list", group: "pins", icon: "list.bullet.rectangle",
              title: L10n.text("Settings.0778"), detail: L10n.text("upstream.settings.5635856487"),
              more: L10n.text("upstream.settings.177a9fcabd"),
              keys: ["pins.list"], words: ["arc", "pinned"], parent: "tabs.layout"),
        .init(id: "commandbar", group: "opening", icon: "chevron.right.square",
              title: L10n.text("Settings.0726"), detail: L10n.text("upstream.settings.9f78ee0aea"),
              keys: ["commandbar"], words: ["commands", "command palette"]),
        .init(id: "start.fresh", group: "opening", icon: "sunrise",
              title: L10n.text("Settings.0772"), detail: L10n.text("upstream.settings.6e93be1b67"),
              keys: [Preferences.freshKey], words: ["restore", "session", "startup"]),

        // Passwords
        .init(id: "passwords.open", group: "passwords", icon: "key.viewfinder",
              title: L10n.text("Settings.0784"), detail: L10n.text("Settings.0785"), words: ["keychain"]),
        .init(id: "passwords.save", group: "passwords", icon: "square.and.arrow.down",
              title: L10n.text("Settings.0787"), detail: L10n.text("Settings.0783"),
              keys: ["passwords.save"], words: ["save password"]),
        .init(id: "passwords.fill", group: "passwords", icon: "rectangle.and.pencil.and.ellipsis",
              title: L10n.text("Settings.0788"), detail: L10n.text("upstream.settings.f0b3bc8adf"),
              keys: ["passwords.fill"], words: ["autofill", "login"]),
        .init(id: "passkeys", group: "passwords", icon: "person.badge.key",
              title: L10n.text("Settings.0790"), detail: L10n.text("Settings.0793"),
              keys: ["passkeys"], words: ["webauthn", "touch id"]),
        .init(id: "passwords.apple", group: "apple", icon: "applelogo",
              title: L10n.text("applePasswords.settingTitle"), detail: L10n.text("upstream.settings.aa8f556dce"),
              more: L10n.text("upstream.settings.a43ca65dfb"),
              keys: ["passwords.apple"], words: ["icloud keychain", "apple"]),

        // Privacy
        .init(id: "shield", group: "blocking", icon: "shield.lefthalf.filled",
              title: L10n.text("Settings.0806"), detail: L10n.text("upstream.88017ad.133181a7e0"),
              more: L10n.text("upstream.88017ad.79b365167e"),
              keys: ["shield"], words: ["adblock", "ad blocker", "ads", "youtube"]),
        .init(id: "sites.keep", group: "blocking", icon: "eye.slash",
              title: L10n.text("Settings.0812"), detail: L10n.text("upstream.settings.0744c57b83"),
              more: L10n.text("upstream.settings.c3d31a62a1"),
              keys: ["sites.keep"], words: ["itp", "cookies", "tracking"]),
        .init(id: "privacy.clickIDs", group: "blocking", icon: "scissors",
              title: L10n.text("upstream.settings.8631549282"), detail: L10n.text("upstream.settings.d4712327c0"),
              more: L10n.text("upstream.settings.be82654f6b"),
              keys: ["privacy.clickIDs"], words: ["gclid", "fbclid", "click id", "link tracking", "tracking parameters"]),
        .init(id: "privacy.gpc", group: "blocking", icon: "hand.raised",
              title: L10n.text("upstream.settings.a16ae52957"), detail: L10n.text("upstream.settings.8fc60c90ae"),
              more: L10n.text("upstream.settings.56f90ffb14"),
              keys: ["privacy.gpc"], words: ["gpc", "do not sell", "do not track", "dnt", "global privacy control"]),
        .init(id: "notifications.ask", group: "permissions", icon: "bell.badge",
              title: L10n.text("Settings.0817"), detail: L10n.text("upstream.settings.d89270d4ef"),
              keys: ["notifications.ask"], words: ["notifications", "alerts", "push"]),
        .init(id: "privacy.forget", group: "permissions", icon: "arrow.uturn.backward.circle",
              title: L10n.text("Settings.0814"), detail: L10n.text("upstream.settings.060bd36217"),
              words: ["permissions", "camera", "microphone", "location", "reset"]),
        .init(id: "clear.history", group: "clear", icon: "clock.arrow.circlepath",
              title: L10n.text("App.0175"), detail: L10n.text("Settings.0820"), words: ["clear history"]),
        .init(id: "clear.cookies", group: "clear", icon: "person.crop.circle.badge.xmark",
              title: L10n.text("Recall.0652"), detail: L10n.text("Recall.0653"), words: ["cookies", "sign out"]),
        .init(id: "clear.cache", group: "clear", icon: "internaldrive",
              title: L10n.text("Recall.0655"), detail: L10n.text("Recall.0656"), words: ["clear cache"]),

        // Keyboard & Mouse
        .init(id: "links.peek", group: "mouse", icon: "eye",
              title: L10n.text("links.peekShortcut"), detail: L10n.text("upstream.settings.c0bc0a021f"),
              more: L10n.text("upstream.settings.2040b9321b"),
              keys: ["links.peek", "links.peekClick"], words: ["preview", "shift click", "peek"]),
        .init(id: "autoscroll", group: "mouse", icon: "arrow.up.and.down.circle",
              title: L10n.text("Settings.0730"), detail: L10n.text("upstream.settings.7b3795dbda"),
              keys: ["autoscroll"], words: ["middle click", "autoscroll", "wheel"]),
        .init(id: "swipe.history", group: "mouse", icon: "hand.draw",
              title: L10n.text("Settings.0734"), detail: L10n.text("upstream.settings.e7995407b7"),
              more: L10n.text("upstream.settings.62cd3a2895"),
              keys: ["swipe.history"], words: ["gesture", "trackpad", "back"]),

        // About
        .init(id: "updates.version", group: "updates", icon: "arrow.down.app",
              title: L10n.text("Settings.0849"), detail: L10n.text("Settings.0854"), words: ["version", "update"]),
        .init(id: "updates.auto", group: "updates", icon: "arrow.triangle.2.circlepath",
              title: L10n.text("Settings.0829"), detail: L10n.text("upstream.settings.048a1b94df"),
              keys: [Updater.installKey], words: ["automatic updates"]),
        .init(id: "about.feedback", group: "updates", icon: "envelope",
              title: L10n.text("Settings.0831"), detail: L10n.text("Settings.0832"), words: ["bug", "feedback", "report"]),
        .init(id: "about.notes", group: "updates", icon: "sparkles",
              title: L10n.text("Settings.0834"), detail: L10n.text("Settings.0835"), words: ["release notes", "changelog"]),
        .init(id: "bench", group: "developer", icon: "terminal",
              title: L10n.text("Settings.0744"), detail: L10n.text("upstream.settings.8741878c81"),
              more: L10n.text("upstream.settings.3ff52f1b46"),
              keys: ["bench"], words: ["automation", "script", "developer"]),

        // Moved to a menu, or always on: only the find field says so.
        .init(id: "autocorrect", group: "pages", icon: "textformat.abc.dottedunderline",
              title: L10n.text("Settings.0720"), detail: L10n.text("upstream.settings.87a65dc611"),
              keys: ["autocorrect"], words: ["autocorrect", "spelling", "spell"], findOnly: true),
        .init(id: "note.split", group: "window", icon: "rectangle.split.2x1",
              title: L10n.text("Settings.0780"), detail: L10n.text("upstream.settings.a1c6e4d0fe"),
              keys: ["splitView"], words: ["split", "side by side"]),
        .init(id: "note.groups", group: "newtabs", icon: "folder",
              title: L10n.text("Settings.0776"), detail: L10n.text("upstream.settings.b8c8482afc"),
              keys: ["tabs.groups"], words: ["groups", "folders"]),
        .init(id: "note.panel", group: "links", icon: "sidebar.right",
              title: L10n.text("upstream.settings.c904980595"), detail: L10n.text("upstream.settings.17d093af2c"),
              keys: ["panel.sites"], words: ["side panel", "website", "address"]),
        .init(id: "note.translate", group: "pages", icon: "translate",
              title: L10n.text("upstream.settings.c9cdbf0253"), detail: L10n.text("upstream.settings.8186f2eb6f"),
              keys: ["translate.pages"], words: ["translate", "language"], kind: .note, findOnly: true),
        .init(id: "note.awake", group: "memory", icon: "sun.max",
              title: L10n.text("sync.settings.keepAwake"), detail: L10n.text("upstream.settings.f002432498"),
              keys: ["tabs.keepAwake"], words: ["awake", "sleep"]),
        .init(id: "note.sitesearch", group: "search", icon: "arrow.right.to.line.compact",
              title: L10n.text("Settings.0770"), detail: L10n.text("upstream.settings.34e7f7c678"),
              keys: ["search.sites"], words: ["tab to search", "site search"]),
        .init(id: "note.sharedpins", group: "pins", icon: "pin",
              title: L10n.text("sync.settings.sharedPins"), detail: L10n.text("upstream.settings.28649bc045"),
              keys: ["pins.shared"], words: ["favorites", "shared pins"]),
        .init(id: "note.pinback", group: "pins", icon: "arrow.uturn.backward",
              title: L10n.text("upstream.settings.14f2c0903c"), detail: L10n.text("upstream.settings.1ef84b765c"),
              keys: ["pins.numberBack"], words: ["cmd 1", "toggle"]),
        .init(id: "note.switcher", group: "mouse", icon: "rectangle.stack",
              title: L10n.text("sync.settings.switcherKeys"), detail: L10n.text("upstream.settings.b657a0710b"),
              keys: ["switcher.keys"], words: ["ctrl tab", "switcher"]),
        .init(id: "note.links", group: "links", icon: "link",
              title: L10n.text("Settings.0728"), detail: L10n.text("upstream.settings.177388989b"),
              keys: ["links.show"], words: ["status bar", "hover"]),
        .init(id: "note.flick", group: "video", icon: "hand.raised.fingers.spread",
              title: L10n.text("Settings.0736"), detail: L10n.text("upstream.settings.db3c83a8ff"),
              keys: ["float.flicks"], words: ["flick", "corner"]),
    ] as [SettingsItem]).filter(offered)

    /// Rows for a feature this Mac's WebKit doesn't have aren't listed at
    /// all, on the page or in the find field (see Privacy.swift).
    private static func offered(_ item: SettingsItem) -> Bool {
        switch item.id {
        case "privacy.clickIDs": return ClickIDs.possible
        case "privacy.gpc": return PrivacySignal.possible
        case "extensions.manager":
            if #available(macOS 15.4, *) { return true }
            return false
        default: return true
        }
    }

    static func item(_ id: String) -> SettingsItem? { items.first { $0.id == id } }

    // MARK: - finding

    /// The rows whose words match what was typed, in the order of the
    /// sections. Every word typed has to be found somewhere in the row.
    static func find(_ typed: String) -> [SettingsItem] {
        let words = typed.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let order = SettingsPanel.Page.allCases
        return items
            .filter { item in
                let group = SettingsIndex.group(item.group)
                let hay = ([item.title, item.detail, item.more ?? "", group?.title ?? "", item.page.title]
                    + item.words + item.keys).joined(separator: " ").lowercased()
                return words.allSatisfy { hay.contains($0) }
            }
            .sorted { (order.firstIndex(of: $0.page) ?? 0, groupOrder($0.group)) < (order.firstIndex(of: $1.page) ?? 0, groupOrder($1.group)) }
    }

    private static func groupOrder(_ id: String) -> Int { groups.firstIndex { $0.id == id } ?? 0 }

    /// Whether a dependent row means anything as things are set now. Its
    /// section hides it otherwise; the find field shows it dimmed.
    @MainActor static func applies(_ item: SettingsItem, _ prefs: Preferences) -> Bool {
        switch item.id {
        case "pages.dusk": return prefs.look != .light
        case "sidebar.roomy": return prefs.sidebar && !prefs.sideIcons
        case "sidebar.hides", "layout.cards", "pins.list": return prefs.sidebar
        case "toolbar.left": return !prefs.sidebar
        default: return true
        }
    }

    /// What a dimmed dependent row says instead of its own line.
    static func needs(_ item: SettingsItem) -> String {
        switch item.id {
        case "pages.dusk": return L10n.text("upstream.settings.18b9a07d81")
        case "toolbar.left": return L10n.text("upstream.settings.e89364ed5e")
        case "sidebar.roomy": return L10n.text("upstream.88017ad.61579a8b34")
        default: return L10n.text("upstream.settings.f2d1566f46")
        }
    }
}

// MARK: - merged controls

/// Tabs: across the top, a column down either side, or that column as
/// icons only. Reads and writes `sidebar` and `sidebar.position`, as the
/// two switches did, and `sidebar.icons`. Icons only keeps the side the
/// column was on.
enum TabsLayout: String, CaseIterable, Identifiable {
    case top, left, right, icons
    var id: String { rawValue }
    var title: String {
        switch self {
        case .top: return L10n.text("sync.settings.top")
        case .left: return L10n.text("Prefs.0638")
        case .right: return L10n.text("Prefs.0639")
        case .icons: return L10n.text("upstream.88017ad.7eefba1f1c")
        }
    }
}

/// Sleep tabs: Never, or how soon. `tabs.sleep` and `tabs.sleep.pace`.
enum SleepChoice: String, CaseIterable, Identifiable {
    case never, later, normal, sooner
    var id: String { rawValue }
    var title: String { self == .never ? L10n.text("sync.tabs.never") : pace!.title }
    var pace: SleepPace? { SleepPace(rawValue: rawValue) }
    var detail: String {
        guard let pace else { return L10n.text("upstream.settings.b4a29191e8") }
        return L10n.text("upstream.settings.sleepDetail", pace.detail.trimmingCharacters(in: CharacterSet(charactersIn: ".。")))
    }
}

/// Float the video on its own: `float.leave` and `float.away`.
enum FloatOwn: String, CaseIterable, Identifiable {
    case never, tabs, tabsOrApps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .never: return L10n.text("sync.tabs.never")
        case .tabs: return L10n.text("upstream.settings.1e210ba8b3")
        case .tabsOrApps: return L10n.text("upstream.settings.f2f680cf77")
        }
    }
}

/// Peek at a link: Off, or the click that does it. `links.peek` and
/// `links.peekClick`.
enum PeekChoice: String, CaseIterable, Identifiable {
    case off, shift, optionShift, optionCommand
    var id: String { rawValue }
    var title: String { self == .off ? L10n.text("upstream.settings.e3de5ab0ca") : click!.title }
    var click: PeekClick? { PeekClick(rawValue: rawValue) }
}

extension Preferences {
    var tabsLayout: TabsLayout {
        get { !sidebar ? .top : sideIcons ? .icons : (sidePosition == .right ? .right : .left) }
        set {
            switch newValue {
            case .top:
                sidebar = false
            case .icons:
                sideIcons = true
                sidebar = true
            case .left, .right:
                sidePosition = newValue == .right ? .right : .left
                sideIcons = false
                sidebar = true
            }
        }
    }

    var sleepChoice: SleepChoice {
        get { sleepsTabs ? (SleepChoice(rawValue: sleepPace.rawValue) ?? .normal) : .never }
        set {
            if let pace = newValue.pace { sleepPace = pace; sleepsTabs = true } else { sleepsTabs = false }
        }
    }

    /// Away alone (never seen from the switches, but possible) reads as the
    /// nearest choice that includes it.
    var floatOwn: FloatOwn {
        get { floatsAway ? .tabsOrApps : (floatsOnLeave ? .tabs : .never) }
        set {
            floatsOnLeave = newValue != .never
            floatsAway = newValue == .tabsOrApps
        }
    }

    var pinsKeepSite: Bool {
        get { pinsGoHome || pinsPeek }
        set { pinsGoHome = newValue; pinsPeek = newValue }
    }

    var peekChoice: PeekChoice {
        get { peeksLinks ? (PeekChoice(rawValue: peekClick.rawValue) ?? .shift) : .off }
        set {
            if let click = newValue.click { peekClick = click; peeksLinks = true } else { peeksLinks = false }
        }
    }

    /// Set Up Like Arc: what it turns on, and what was there before, so
    /// Undo can put it back.
    struct ArcSetup {
        var layout: TabsLayout
        var spaces: Bool
        var rows: Bool
        var keep: (home: Bool, peek: Bool)
    }

    var arcSnapshot: ArcSetup {
        ArcSetup(layout: tabsLayout, spaces: usesSpaces, rows: listsPins, keep: (pinsGoHome, pinsPeek))
    }

    var looksLikeArc: Bool {
        tabsLayout == .left && usesSpaces && listsPins && pinsGoHome && pinsPeek
    }

    /// Turns Arc's way on and says what changed.
    @discardableResult
    func setUpLikeArc() -> [String] {
        var changed: [String] = []
        if tabsLayout != .left { tabsLayout = .left; changed.append(L10n.text("upstream.settings.3d46d47429")) }
        if !usesSpaces { usesSpaces = true; changed.append(L10n.text("section.spaces")) }
        if !listsPins { listsPins = true; changed.append(L10n.text("upstream.settings.279aee48f5")) }
        if !(pinsGoHome && pinsPeek) { pinsKeepSite = true; changed.append(L10n.text("upstream.settings.b9b2f1866a")) }
        return changed
    }

    func restore(_ before: ArcSetup) {
        tabsLayout = before.layout
        usesSpaces = before.spaces
        listsPins = before.rows
        pinsGoHome = before.keep.home
        pinsPeek = before.keep.peek
    }
}

// MARK: - for the bench

extension SettingsIndex {
    /// The merged controls as Settings shows them, and the switches whose
    /// defaults changed: what Tests/settings_layout.py reads back.
    @MainActor static func values(_ prefs: Preferences) -> [String: Any] {
        [
            "tabs.layout": prefs.tabsLayout.rawValue,
            "tabs.sleep": prefs.sleepChoice.rawValue,
            "float.own": prefs.floatOwn.rawValue,
            "pins.keep": prefs.pinsKeepSite,
            "pins.home": prefs.pinsGoHome,
            "pins.peek": prefs.pinsPeek,
            "links.peek": prefs.peekChoice.rawValue,
            "pages.120": prefs.fastPages.rawValue,
            "swipe.history": prefs.holdsHistory,
            "tabs.address": prefs.showsAddress,
            "links.show": prefs.showsLinks,
            "float.flicks": prefs.floatFlicks,
            "arc": prefs.looksLikeArc,
            "always": [
                "splitView": prefs.splitView, "tabs.groups": prefs.usesTabGroups,
                "panel.sites": prefs.sitesInPanel, "translate": PageTranslator.enabled,
                "tabs.keepAwake": prefs.keepsSitesAwake, "search.sites": prefs.searchesSites,
                "pins.shared": prefs.sharesPins, "pins.numberBack": prefs.pinNumberGoesBack,
                "switcher.keys": prefs.switcherKeys,
            ],
        ]
    }

    /// A merged control moved as Settings moves it. False for an id or a
    /// value it doesn't know.
    @MainActor static func apply(_ id: String, _ value: Any, to prefs: Preferences) -> Bool {
        switch id {
        case "tabs.layout":
            guard let layout = (value as? String).flatMap(TabsLayout.init) else { return false }
            prefs.tabsLayout = layout
        case "tabs.sleep":
            guard let choice = (value as? String).flatMap(SleepChoice.init) else { return false }
            prefs.sleepChoice = choice
        case "float.own":
            guard let choice = (value as? String).flatMap(FloatOwn.init) else { return false }
            prefs.floatOwn = choice
        case "pins.keep":
            guard let on = value as? Bool else { return false }
            prefs.pinsKeepSite = on
        case "links.peek":
            guard let choice = (value as? String).flatMap(PeekChoice.init) else { return false }
            prefs.peekChoice = choice
        case "arc.setup":
            prefs.setUpLikeArc()
        default:
            return false
        }
        return true
    }

    static func describe(_ item: SettingsItem) -> [String: Any] {
        ["id": item.id, "page": item.page.rawValue, "group": item.group,
         "groupTitle": group(item.group)?.title ?? "", "title": item.title, "detail": item.detail,
         "keys": item.keys, "findOnly": item.findOnly, "note": item.kind == .note,
         "parent": item.parent ?? ""]
    }
}
