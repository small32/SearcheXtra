import Foundation

// The address field doubles as the most basic kind of command line: a
// handful of words that mean "go here in the app" rather than "go here on
// the web". Only the whole word runs on Return, so a search that starts
// with one still searches; part of a word is just offered lower in the
// list. Off by default (Settings ›
// General › Address bar commands): nobody typing "settings" into a browser
// expects the app to open its own panel instead of asking Google.
//
// Not the menus' Command (Shortcuts.swift): these are words, not keys.

@MainActor
enum AddressCommand: CaseIterable, Equatable {
    case settings
    case newTab
    case newPrivateTab
    case newSpace
    case bookmarks
    case history
    case downloads
    case passwords
    case toggleSidebar

    /// What you'd type to reach it. The first is what the list shows.
    var aliases: [String] {
        switch self {
        case .settings: return ["设置", "偏好设置", "settings", "preferences"]
        case .newTab: return ["新建标签页", "new tab"]
        case .newPrivateTab: return ["新建无痕标签页", "无痕标签页", "new private tab", "private tab"]
        case .newSpace: return ["新建空间", "new space"]
        case .bookmarks: return ["书签", "bookmarks"]
        case .history: return ["历史记录", "history"]
        case .downloads: return ["下载", "downloads"]
        case .passwords: return ["密码", "passwords"]
        case .toggleSidebar: return ["切换侧边栏", "侧边栏", "toggle sidebar", "sidebar"]
        }
    }

    var title: String { (L10n.isChinese ? aliases[0] : aliases.first { $0.allSatisfy(\.isASCII) } ?? aliases[0]).localizedCapitalized }

    /// Some only mean something once the feature behind them is even on.
    func available(in browser: Browser) -> Bool {
        switch self {
        case .newSpace: return browser.prefs.usesSpaces
        default: return true
        }
    }

    func run(on browser: Browser) {
        switch self {
        case .settings: browser.tuning = true
        case .newTab: browser.launch()
        case .newPrivateTab: browser.newShyTab()
        case .newSpace: browser.makingSpace = true
        case .bookmarks: browser.bookmarking = true
        case .history: browser.recalling = true
        case .downloads: browser.showDownloads()
        case .passwords: browser.managing = true
        case .toggleSidebar: browser.toggleSidebar()
        }
    }

    /// The command whose words are all that was typed, if any. Only the
    /// whole thing: a command must not take a search from anyone, so
    /// "settings for gmail" or "sett" still searches.
    static func matching(_ typed: String, in browser: Browser) -> AddressCommand? {
        let needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        return allCases.first { $0.available(in: browser) && $0.aliases.contains(needle) }
    }

    /// A command that partly matches: "down", "dwn" or "downlaods" for
    /// Downloads. From three letters, and only offered, never run on Return.
    static func near(_ typed: String, in browser: Browser) -> AddressCommand? {
        let needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        guard needle.count >= 3, matching(needle, in: browser) == nil else { return nil }
        let letters = Array(needle.utf8)
        let available = allCases.filter { $0.available(in: browser) }
        // Closest match first, then the order above.
        let tests: [(String) -> Bool] = [
            { $0.hasPrefix(needle) || $0.split(separator: " ").contains { $0.hasPrefix(needle) } },
            { $0.split(separator: " ").contains { Fuzzy.abbreviates(needle, $0) } },
            { Fuzzy.nearly(letters, in: $0) },
        ]
        for test in tests {
            if let found = available.first(where: { $0.aliases.contains(where: test) }) { return found }
        }
        return nil
    }
}
