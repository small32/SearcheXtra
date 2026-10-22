import AppKit
import SwiftUI
import WebKit

// Your own keys for the menu commands (Settings › Shortcuts). Only what you
// change is kept, on top of the keys the menus already have, so a browser
// nobody has customised behaves exactly as it always did — and a default
// that changes later still reaches everyone who never touched it.

/// A key and the modifiers held with it.
struct KeyCombo: Codable, Hashable {
    /// A lowercased character, or the name of a key that has none:
    /// left, right, up, down, return, delete, space, f1…f12.
    var key: String
    var command = false
    var shift = false
    var option = false
    var control = false

    init(_ key: String, command: Bool = true, shift: Bool = false, option: Bool = false, control: Bool = false) {
        // ⌘+ is ⇧⌘= on some keyboards and a key of its own on others; both
        // mean the same thing, so both are kept as "+" with nothing about ⇧.
        let plus = key == "=" || key == "+"
        self.key = plus ? "+" : key.lowercased()
        self.shift = plus ? false : shift
        self.command = command
        self.option = option
        self.control = control
    }

    /// The key an event pressed, read the way the keyboard's own layout
    /// names it with nothing held — so ⇧⌘] is "]" with shift, not "}" —
    /// and the top row by where it sits, as ⌘1–⌘9 are.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let named = KeyCombo.names[event.keyCode] ?? ContentView.digits[event.keyCode].map(String.init)
        let key = named ?? event.shortcutKey
        guard !key.isEmpty else { return nil }
        self.init(key, command: flags.contains(.command), shift: flags.contains(.shift),
                  option: flags.contains(.option), control: flags.contains(.control))
    }

    private static let names: [UInt16: String] = [
        123: "left", 124: "right", 125: "down", 126: "up", 36: "return", 76: "return",
        51: "delete", 117: "delete", 49: "space", 48: "tab", 53: "escape",
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8",
        101: "f9", 109: "f10", 103: "f11", 111: "f12",
    ]

    private static let symbols: [String: String] = [
        "left": "←", "right": "→", "up": "↑", "down": "↓", "return": "↩", "delete": "⌫", "space": L10n.text("Shortcuts.0873"),
        "tab": "⇥", "escape": "⎋",
    ]

    /// As a menu shows it: ⌃⌥⇧⌘ then the key.
    var display: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "")
            + (KeyCombo.symbols[key] ?? key.uppercased())
    }

    private var isFunctionKey: Bool { key.count > 1 && key.hasPrefix("f") && Int(key.dropFirst()) != nil }

    /// A key alone, or with only ⇧, is typing — never a shortcut.
    var isUsable: Bool { command || option || control || isFunctionKey }

    var swiftUI: KeyboardShortcut? {
        let equivalent: KeyEquivalent
        switch key {
        case "left": equivalent = .leftArrow
        case "right": equivalent = .rightArrow
        case "up": equivalent = .upArrow
        case "down": equivalent = .downArrow
        case "return": equivalent = .return
        case "delete": equivalent = .delete
        case "space": equivalent = .space
        default:
            if isFunctionKey, let n = Int(key.dropFirst()), let scalar = UnicodeScalar(NSF1FunctionKey + n - 1) {
                equivalent = KeyEquivalent(Character(scalar))
            } else if key.count == 1, let character = key.first {
                equivalent = KeyEquivalent(character)
            } else {
                return nil
            }
        }
        var modifiers: EventModifiers = []
        if command { modifiers.insert(.command) }
        if shift { modifiers.insert(.shift) }
        if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }
        return KeyboardShortcut(equivalent, modifiers: modifiers)
    }

    /// macOS's own, the ones every text field relies on, and the ones Search
    /// keeps for itself: ⌘1–⌘9 for tabs, Tab and Escape
    /// with anything. Not ours to give, and so never taken from the Mac.
    static func isReserved(_ combo: KeyCombo) -> Bool {
        let system: Set<KeyCombo> = [
            KeyCombo("q"), KeyCombo("q", option: true), KeyCombo("q", control: true),
            KeyCombo("q", shift: true), KeyCombo("q", shift: true, option: true),
            KeyCombo("h"), KeyCombo("h", option: true), KeyCombo("m"), KeyCombo("m", option: true),
            KeyCombo("c"), KeyCombo("v"), KeyCombo("x"), KeyCombo("a"), KeyCombo("z"), KeyCombo("z", shift: true),
            KeyCombo("`"), KeyCombo("`", shift: true), KeyCombo("f", control: true),
            KeyCombo("space"), KeyCombo("space", command: false, control: true),
            KeyCombo("space", option: true), KeyCombo("space", command: false, option: true, control: true),
        ]
        if system.contains(combo) || combo.key == "tab" || combo.key == "escape" { return true }
        let digit = combo.key.count == 1 && ("1"..."9").contains(combo.key)
        return digit && !combo.option && !combo.shift && combo.command && !combo.control
    }

    /// Keys an extension never has, wherever Search's own commands are:
    /// closing, and opening a tab or a window, as Chrome keeps them. Yours
    /// to move among Search's commands, not to give to an extension.
    static func isBrowserOnly(_ combo: KeyCombo) -> Bool {
        [KeyCombo("w"), KeyCombo("w", shift: true), KeyCombo("w", option: true),
         KeyCombo("t"), KeyCombo("t", shift: true), KeyCombo("n"), KeyCombo("n", shift: true)].contains(combo)
    }
}

/// A menu command, and the key it has unless you give it another.
struct Command: Identifiable {
    enum Section: String, CaseIterable {
        case app = "SearcheXtra", file = "File", edit = "Edit", view = "View", tabs = "Tabs", spaces = "Spaces", bookmarks = "Bookmarks", history = "History"
        var title: String {
            switch self {
            case .app: return "SearcheXtra"
            case .file: return L10n.text("section.file")
            case .edit: return L10n.text("section.edit")
            case .view: return L10n.text("section.view")
            case .spaces: return L10n.text("section.spaces")
            case .tabs: return L10n.text("section.tabs")
            case .bookmarks: return L10n.text("section.bookmarks")
            case .history: return L10n.text("section.history")
            }
        }
    }

    let id: String
    let title: String
    let section: Section
    let defaultKey: KeyCombo?
    let run: @MainActor (Browser) -> Void

    init(_ id: String, _ title: String, _ section: Section, _ key: KeyCombo?, _ run: @escaping @MainActor (Browser) -> Void) {
        self.id = id
        self.title = title
        self.section = section
        self.defaultKey = key
        self.run = run
    }

    static func named(_ id: String) -> Command? { byID[id] }
    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// The same commands, keys and order as the menus (see App.swift).
    static let all: [Command] = [
        Command("app.settings", L10n.text("Shortcuts.0874"), .app, KeyCombo(",")) { $0.tuning.toggle() },
        Command("app.welcome", L10n.text("Shortcuts.0875"), .app, nil) { $0.welcoming = true },
        Command("app.passwords", L10n.text("Shortcuts.0876"), .app, KeyCombo("l", option: true)) { $0.managing = true },

        Command("file.newWindow", L10n.text("Shortcuts.0877"), .file, KeyCombo("n")) { _ in Browsers.newWindow() },
        Command("file.newTab", L10n.text("Shortcuts.0878"), .file, KeyCombo("t")) { $0.newTab() },
        Command("file.newPrivateTab", L10n.text("Shortcuts.0879"), .file, KeyCombo("n", shift: true)) { $0.newShyTab() },
        Command("file.reopen", L10n.text("Shortcuts.0880"), .file, KeyCombo("t", shift: true)) { $0.reopen() },
        Command("file.openAddress", L10n.text("Shortcuts.0881"), .file, KeyCombo("l")) { $0.edit() },
        Command("file.closeTab", L10n.text("Shortcuts.0882"), .file, KeyCombo("w")) { $0.closeFront() },
        Command("file.closeWindow", L10n.text("upstream.closeWindow"), .file, KeyCombo("w", shift: true)) { $0.closeWindow() },
        Command("file.import", L10n.text("Shortcuts.0883"), .file, nil) { $0.bringingIn = "" },
        Command("file.share", L10n.text("Shortcuts.0884"), .file, nil) { $0.share() },
        Command("file.exportPDF", L10n.text("command.exportPDF"), .file, nil) { $0.exportPDF() },
        Command("file.print", L10n.text("Shortcuts.0885"), .file, KeyCombo("p")) { $0.printPage() },

        Command("edit.find", L10n.text("Shortcuts.0886"), .edit, KeyCombo("f")) { $0.openFind() },
        Command("edit.findNext", L10n.text("Shortcuts.0887"), .edit, KeyCombo("g")) { $0.look(forward: true) },
        Command("edit.findPrevious", L10n.text("Shortcuts.0888"), .edit, KeyCombo("g", shift: true)) { $0.look(forward: false) },

        Command("view.sidebar", L10n.text("Shortcuts.0889"), .view, KeyCombo("s", shift: true)) { $0.toggleSidebar() },
        Command("view.fold", L10n.text("Shortcuts.0890"), .view, KeyCombo("s")) { $0.toggleFold() },
        Command("view.reload", L10n.text("Shortcuts.0891"), .view, KeyCombo("r")) { $0.reload() },
        Command("view.reloadOrigin", L10n.text("Shortcuts.0892"), .view, KeyCombo("r", option: true)) { $0.reload(fromOrigin: true) },
        Command("view.reader", L10n.text("Shortcuts.0893"), .view, KeyCombo("r", shift: true)) { $0.toggleReader() },
        Command("view.float", L10n.text("Shortcuts.0894"), .view, KeyCombo("p", shift: true)) { $0.toggleFloat() },
        Command("view.dusk", L10n.text("appearance.darkenSite"), .view, KeyCombo("d", shift: true)) { $0.toggleDusk() },
        Command("view.duskPause", L10n.text("appearance.pauseDarkening"), .view, KeyCombo("d", shift: true, option: true)) { $0.pauseDusk() },
        Command("view.hide", L10n.text("Shortcuts.0897"), .view, KeyCombo("h", shift: true)) { $0.toggleHiding() },
        Command("view.hidden", L10n.text("Shortcuts.0898"), .view, KeyCombo("u", shift: true)) { $0.reviewing.toggle() },
        Command("view.zoomIn", L10n.text("Shortcuts.0899"), .view, KeyCombo("+")) { $0.zoom(by: 1.1) },
        Command("view.zoomOut", L10n.text("Shortcuts.0900"), .view, KeyCombo("-")) { $0.zoom(by: 1 / 1.1) },
        Command("view.actualSize", L10n.text("Shortcuts.0901"), .view, KeyCombo("0")) { $0.resetZoom() },
        Command("view.inspector", L10n.text("Shortcuts.0902"), .view, KeyCombo("i", option: true)) { $0.toggleInspector() },
        Command("view.console", L10n.text("Shortcuts.0903"), .view, KeyCombo("j", option: true)) { $0.showConsole() },
        Command("view.inspect", L10n.text("Shortcuts.0904"), .view, KeyCombo("c", option: true)) { $0.inspectElement() },

        Command("tabs.back", L10n.text("Shortcuts.0905"), .tabs, KeyCombo("[")) { $0.back() },
        Command("tabs.forward", L10n.text("Shortcuts.0906"), .tabs, KeyCombo("]")) { $0.forward() },
        Command("tabs.next", L10n.text("Shortcuts.0907"), .tabs, KeyCombo("]", shift: true)) { $0.step(1) },
        Command("tabs.previous", L10n.text("Shortcuts.0908"), .tabs, KeyCombo("[", shift: true)) { $0.step(-1) },
        Command("tabs.search", L10n.text("Shortcuts.0909"), .tabs, KeyCombo("k")) { browser in
            if browser.editing, !browser.offers.isEmpty { browser.stepSummon() } else { browser.summon() }
        },
        // ⌥⌘N, Chrome's on the Mac: ⌃⌘S is the Mac's own Show Sidebar, and
        // sits beside ⌘S, which folds the tabs away.
        Command("tabs.split", L10n.text("Shortcuts.0910"), .tabs, KeyCombo("n", option: true)) { browser in
            guard browser.prefs.splitView else { return }
            browser.startSplit()
        },
        Command("tabs.focusLeftPane", L10n.text("Shortcuts.0911"), .tabs, KeyCombo("left", control: true)) { browser in
            guard browser.prefs.splitView else { return }
            browser.focusPane(onLeft: true)
        },
        Command("tabs.focusRightPane", L10n.text("Shortcuts.0912"), .tabs, KeyCombo("right", control: true)) { browser in
            guard browser.prefs.splitView else { return }
            browser.focusPane(onLeft: false)
        },
        Command("tabs.focusOtherPane", L10n.text("Shortcuts.0913"), .tabs, nil) { browser in
            guard browser.prefs.splitView else { return }
            browser.focusOtherPane()
        },
        Command("tabs.swapSplit", L10n.text("Shortcuts.0914"), .tabs, nil) { browser in
            guard browser.prefs.splitView else { return }
            browser.swapSplit()
        },
        Command("tabs.separateSplit", L10n.text("Shortcuts.0915"), .tabs, nil) { browser in
            guard browser.prefs.splitView, let tab = browser.active else { return }
            browser.detachSplit(tab)
        },
        Command("tabs.rename", L10n.text("Shortcuts.0916"), .tabs, nil) { browser in
            if let tab = browser.active { browser.beginTabRename(tab) }
        },
        Command("tabs.duplicate", L10n.text("Shortcuts.0917"), .tabs, KeyCombo("d")) { $0.duplicate() },
        Command("tabs.copyAddress", L10n.text("Shortcuts.0918"), .tabs, KeyCombo("c", shift: true)) { $0.copyAddress() },
        Command("tabs.copyMarkdown", L10n.text("Shortcuts.0919"), .tabs, nil) { $0.copyMarkdownLink() },
        Command("tabs.pasteAndGo", L10n.text("Shortcuts.0920"), .tabs, KeyCombo("v", shift: true)) { $0.pasteAndGo() },
        Command("tabs.closeOthers", L10n.text("Shortcuts.0921"), .tabs, nil) { browser in
            if let tab = browser.active { browser.closeOthers(but: tab) }
        },
        Command("tabs.mute", L10n.text("Shortcuts.0922"), .tabs, KeyCombo("m", shift: true)) { $0.pauseMedia() },

        Command("bookmarks.add", L10n.text("Shortcuts.0923"), .bookmarks, KeyCombo("b", shift: true)) { $0.bookmarkCurrent() },
        Command("bookmarks.show", L10n.text("Shortcuts.0924"), .bookmarks, nil) { $0.bookmarking = true },
        Command("bookmarks.bar", L10n.text("Shortcuts.0925"), .bookmarks, nil) { browser in
            withAnimation(Motion.glide) { browser.prefs.bookmarksBar.toggle() }
        },

        Command("history.show", L10n.text("Shortcuts.0926"), .history, KeyCombo("y")) { $0.recalling.toggle() },
        Command("history.downloads", L10n.text("Shortcuts.0927"), .history, KeyCombo("j", shift: true)) { $0.hoarding.toggle() },
        Command("history.clearData", L10n.text("Shortcuts.0928"), .history, KeyCombo("delete", shift: true)) { $0.recallMode = .clearing },
        Command("history.clear", L10n.text("Shortcuts.0929"), .history, nil) { $0.clearHistory() },
    ] + (1...9).map { number in
        Command("spaces.\(number)", L10n.text("shortcuts.space", String(number)), .spaces,
                KeyCombo(String(number), command: false, control: true)) { browser in
            browser.switchSpace(index: number - 1)
        }
    }
}

/// What you've changed, on top of the defaults: a new key, or none. One for
/// the app, whichever window the key is pressed in. Only Settings › Shortcuts
/// changes it: no page and no extension can.
@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    private struct Override: Codable, Equatable { var key: KeyCombo? }

    @Published private var changed: [String: Override]
    /// A key is being typed into Settings; the app's own keys stand aside.
    @Published var recording = false
    /// The key each extension command came with, as its extension loaded
    /// (see `adopt`), by its id here: "ext:" + extension + ":" + command.
    private var manifest: [String: Override] = [:]

    init() {
        // Read with the same rules the Settings box keeps: a key that isn't
        // ours to give stays the Mac's, whatever the file says.
        let saved = Store.settings.data(forKey: "shortcuts")
            .flatMap { try? JSONDecoder().decode([String: Override].self, from: $0) } ?? [:]
        changed = saved.filter { id, override in
            override.key.map { !KeyCombo.isReserved($0) && !(id.hasPrefix("ext:") && KeyCombo.isBrowserOnly($0)) } ?? true
        }
    }

    func key(for id: String) -> KeyCombo? {
        if let override = changed[id] { return override.key }
        return defaultKey(for: id)
    }

    private func defaultKey(for id: String) -> KeyCombo? {
        guard id.hasPrefix("ext:") else { return Command.named(id)?.defaultKey }
        // What the manifest asked for, while no key of Search's is in the
        // way: checked each time, so moving or resetting one of Search's
        // commands frees or takes an extension's key at once.
        return manifest[id]?.key.flatMap { keepsFromExtensions($0) ? nil : $0 }
    }

    func isChanged(_ id: String) -> Bool { changed[id] != nil }
    var anyChanged: Bool { !changed.isEmpty }

    /// Changed commands, and Space keys which have no menu to handle their defaults.
    func customCommand(on combo: KeyCombo) -> Command? {
        Command.all.first { (changed[$0.id] != nil || $0.section == .spaces) && key(for: $0.id) == combo }
    }

    /// A key an extension may not have: one of the Mac's, or one of
    /// Search's commands has as things stand.
    func keepsFromExtensions(_ combo: KeyCombo) -> Bool {
        KeyCombo.isReserved(combo) || KeyCombo.isBrowserOnly(combo) || Command.all.contains { key(for: $0.id) == combo }
    }

    /// A key the menus had that no command has now: the page's again —
    /// unless you gave it to an extension's command.
    func isFreed(_ combo: KeyCombo) -> Bool {
        guard Command.all.contains(where: { $0.defaultKey == combo && changed[$0.id] != nil }),
              !Command.all.contains(where: { key(for: $0.id) == combo })
        else { return false }
        if #available(macOS 15.4, *), extensionCommands().contains(where: { key(for: $0.id) == combo }) { return false }
        return true
    }

    /// The command already on `combo`, other than `id`: one of Search's,
    /// or an extension's.
    func owner(of combo: KeyCombo, except id: String) -> (id: String, title: String)? {
        if let command = Command.all.first(where: { $0.id != id && key(for: $0.id) == combo }) {
            return (command.id, command.title)
        }
        if #available(macOS 15.4, *),
           let other = extensionCommands().first(where: { $0.id != id && key(for: $0.id) == combo }) {
            return (other.id, other.command.title)
        }
        return nil
    }

    /// `combo` for `id`, taken from whichever command had it.
    func assign(_ combo: KeyCombo, to id: String) {
        if let other = owner(of: combo, except: id) { set(nil, for: other.id) }
        set(combo, for: id)
    }

    func clear(_ id: String) { set(nil, for: id) }

    func reset(_ id: String) {
        if let key = defaultKey(for: id) { assign(key, to: id) }
        else { set(nil, for: id) }
    }

    func resetAll() {
        changed = [:]
        save()
        applyExtensions()
    }

    /// Only a difference from the default is kept.
    private func set(_ combo: KeyCombo?, for id: String) {
        changed[id] = combo == defaultKey(for: id) ? nil : Override(key: combo)
        save()
        applyExtensions()
    }

    /// Every extension command's key as it now stands, handed to WebKit: a
    /// change to one of Search's can free or take an extension's.
    private func applyExtensions() {
        guard #available(macOS 15.4, *) else { return }
        for command in extensionCommands() { applied(command.id) }
    }

    /// An extension command's key, handed to WebKit, which matches it.
    private func applied(_ id: String) {
        guard id.hasPrefix("ext:"), #available(macOS 15.4, *),
              let command = extensionCommands().first(where: { $0.id == id })?.command else { return }
        let combo = key(for: id)
        command.activationKey = combo?.key
        command.modifierFlags = combo?.flags ?? []
    }

    private func save() {
        if changed.isEmpty {
            Store.settings.removeObject(forKey: "shortcuts")
        } else {
            Store.settings.set(try? JSONEncoder().encode(changed), forKey: "shortcuts")
        }
    }
}

// Extension commands, #189: the keys an extension's manifest asks for, set
// otherwise here as WebKit means them to be — it matches the key it is
// given, and the app keeps it. Only single keys, as a manifest has them.

@available(macOS 15.4, *)
extension ShortcutStore {
    struct ExtensionCommand {
        let id: String
        let extensionName: String
        let command: WKWebExtension.Command
    }

    /// The commands of every extension loaded, with a name to show.
    func extensionCommands() -> [ExtensionCommand] {
        let names = Dictionary(Extensions.shared.installed.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return Extensions.shared.contexts.sorted { $0.key < $1.key }.flatMap { ext, context in
            context.commands.map {
                ExtensionCommand(id: "ext:\(ext):\($0.id)", extensionName: names[ext] ?? ext, command: $0)
            }
        }
    }

    /// An extension just loaded: the keys it came with noted, and yours
    /// put in their place. A key its manifest asks for that is the Mac's,
    /// or that one of Search's commands has, it doesn't get — as in Chrome,
    /// an extension never has a key the browser uses. Its command is left
    /// without one, for you to give it one in Settings if you like.
    func adopt(_ context: WKWebExtensionContext, id ext: String) {
        for command in context.commands {
            let id = "ext:\(ext):\(command.id)"
            // What WebKit holds is the manifest's on a fresh load, or an
            // update's; once applied here, it is ours, and not taken again.
            let current = KeyCombo(activation: command.activationKey, flags: command.modifierFlags)
            if manifest[id] == nil || current != key(for: id) { manifest[id] = Override(key: current) }
            applied(id)
        }
    }
}

extension KeyCombo {
    /// An extension command's key, as WebKit holds it.
    init?(activation key: String?, flags: NSEvent.ModifierFlags) {
        guard let key, !key.isEmpty else { return nil }
        self.init(key, command: flags.contains(.command), shift: flags.contains(.shift),
                  option: flags.contains(.option), control: flags.contains(.control))
    }

    var flags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        return flags
    }
}

extension View {
    /// The command's key as it stands, or none (see ShortcutStore).
    @MainActor
    func shortcut(_ id: String) -> some View {
        keyboardShortcut(ShortcutStore.shared.key(for: id)?.swiftUI)
    }
}

extension Command {
    /// Split View's commands: with it off, not listed, and their keys go on
    /// to the page.
    static let split: Set<String> = ["tabs.split", "tabs.focusLeftPane", "tabs.focusRightPane", "tabs.focusOtherPane",
                                     "tabs.swapSplit", "tabs.separateSplit"]
    /// Dark pages': with them off, not listed, and their keys go on to the page.
    static let dusk: Set<String> = ["view.dusk", "view.duskPause"]
}
