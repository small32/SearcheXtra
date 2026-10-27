import AppKit
import SwiftUI

/// Stored independently of appearance and of all existing preference keys.
enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", simplifiedChinese = "zh-Hans"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return L10n.text("language.system")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }
    static func resolve(_ language: InterfaceLanguage, preferred: [String] = Locale.preferredLanguages) -> String {
        if language != .system { return language.rawValue }
        return preferred.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
    }
}

enum L10n {
    static let language = InterfaceLanguage.resolve(
        InterfaceLanguage(rawValue: Store.settings.string(forKey: "interface.language") ?? "system") ?? .system
    )
    static var isChinese: Bool { language == "zh-Hans" }
    static let resourceBundle: Bundle = {
        // SwiftPM's generated accessor differs across toolchains. An installed
        // app always keeps the bundle in Contents/Resources; command-line tests
        // can still use SwiftPM's own locator.
        if let url = Bundle.main.resourceURL?.appendingPathComponent("SearcheXtra_SearcheXtra.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }()
    static let translations: [String: [String: String]] = {
        guard let url = resourceBundle.url(forResource: "Translations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { preconditionFailure("Missing interface translations") }
        return result
    }()
    static func javaScriptString(_ value: String) -> String {
        // JSON quoting keeps localized labels from becoming executable script.
        String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
    }
    static func text(_ key: String, _ arguments: String...) -> String {
        render(key, language: language, arguments: arguments)
    }
    static func render(_ key: String, language: String, arguments: [String] = []) -> String {
        let entry = translations[key]
        let template = entry?[language] ?? entry?["en"] ?? key
        // One pass: user content resembling a placeholder must stay verbatim.
        var result = "", rest = template[...]
        while let opening = rest.firstIndex(of: "{"),
              let closing = rest[opening...].firstIndex(of: "}") {
            result += rest[..<opening]
            let token = rest[rest.index(after: opening)..<closing]
            if let index = Int(token), arguments.indices.contains(index) { result += arguments[index] }
            else { result += rest[opening...closing] }
            rest = rest[rest.index(after: closing)...]
        }
        return result + rest
    }
}

@MainActor
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()
    private let initial: InterfaceLanguage
    @Published var selection: InterfaceLanguage {
        didSet {
            Store.settings.set(selection.rawValue, forKey: "interface.language")
            // System-owned menus and privacy prompts read the app's language at launch.
            if selection == .system { Store.settings.removeObject(forKey: "AppleLanguages") }
            else { Store.settings.set([selection.rawValue], forKey: "AppleLanguages") }
        }
    }
    var needsRestart: Bool { selection != initial }
    private init() {
        let saved = InterfaceLanguage(rawValue: Store.settings.string(forKey: "interface.language") ?? "system") ?? .system
        initial = saved
        selection = saved
    }
    func restart() {
        // Use the updater's exit-aware relaunch, retaining the probe's menu language.
        Updater.shared.relaunch(arguments: Store.testing
            ? ["-AppleLanguages", "(\"\(InterfaceLanguage.resolve(selection))\")"] : [])
    }
}
