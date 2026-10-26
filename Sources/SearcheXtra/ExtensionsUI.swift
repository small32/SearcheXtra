import SwiftUI
import WebKit

/// Settings › Extensions: installation preferences and the management entry.
struct ExtensionsPage: View {
    @ObservedObject var browser: Browser

    var body: some View {
        if #available(macOS 15.4, *) {
            Installer(browser: browser, extensions: .shared)
        } else {
            Card {
                Line(L10n.text("ExtensionsUI.0478"), L10n.text("ExtensionsUI.0479")) { EmptyView() }
            }
        }
    }

    @available(macOS 15.4, *)
    private struct Installer: View {
        @ObservedObject var browser: Browser
        @ObservedObject var extensions: Extensions
        @State private var link = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(L10n.text("ExtensionsUI.0480"))
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: 8)
                            Pill(L10n.text("ExtensionsUI.0481")) {
                                browser.open(Browser.webStore, foreground: true)
                            }
                        }
                        HStack(spacing: 8) {
                            ZStack(alignment: .leading) {
                                if link.isEmpty {
                                    Text(L10n.text("ExtensionsUI.0482"))
                                        .foregroundStyle(Palette.muted.opacity(0.8))
                                }
                                TextField("", text: $link)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(Palette.ink)
                                    .onSubmit(add)
                            }
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            if extensions.busy != nil {
                                Ring(size: 12)
                            } else {
                                Pill(L10n.text("ExtensionsUI.0483"), filled: true, action: add)
                                    .disabled(Crx.id(in: link) == nil)
                            }
                        }
                        Text(L10n.text("ExtensionsUI.0484"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                }

                Card {
                    Line(L10n.text("ExtensionsUI.0485"), L10n.text("ExtensionsUI.0486")) {
                        Pill(L10n.text("ExtensionsUI.0487")) {
                            browser.bringingExtensions = true
                            browser.lead(to: InternalPage(.importing))
                        }
                    }
                }

                Card {
                    Line(L10n.text("extensions.manage")) {
                        Pill(L10n.text("extensions.openManager")) { ExtensionManagerWindow.shared.show() }
                    }
                }
                Text(L10n.text("extensions.private.detail"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Card {
                    Line(L10n.text("ExtensionsUI.0491"), L10n.text("ExtensionsUI.0492")) {
                        Pill(L10n.text("ExtensionsUI.0493")) { extensions.installFolder() }
                    }
                }
            }
        }

        private func add() {
            guard Crx.id(in: link) != nil else { return }
            extensions.install(from: link)
            link = ""
        }
    }
}

/// On an extension's page in the Chrome Web Store, the offer to add it —
/// where the store's own button only says "Switch to Chrome".
struct StoreOffer: View {
    @ObservedObject var browser: Browser

    var body: some View {
        if #available(macOS 15.4, *), let tab = browser.active {
            Watch(tab: tab, extensions: .shared)
        }
    }

    @available(macOS 15.4, *)
    private struct Watch: View {
        @ObservedObject var tab: Tab
        @ObservedObject var extensions: Extensions

        var body: some View {
            // Only where the page's own "Add to Search" isn't in place — a
            // store that has changed its markup still gets a way in.
            if let url = tab.address, let id = Crx.storeID(of: url),
               tab.storePlaced != id, !extensions.installed.contains(where: { $0.id == id }) {
                HStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.muted)
                    Text(extensions.busy == id ? L10n.text("ExtensionsUI.0509") : L10n.text("ExtensionsUI.0510"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.ink)
                    if extensions.busy == id {
                        Ring(size: 10)
                    } else {
                        Button(L10n.text("ExtensionsUI.0511")) { extensions.install(from: id) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.ground)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Palette.ink, in: Capsule())
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 10)
                .padding(.vertical, 9)
                .background(Palette.ground, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    static func isStorePage(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else { return false }
        let host = url.host()?.lowercased() ?? ""
        return host == "chromewebstore.google.com"
            || (host == "chrome.google.com" && url.path.hasPrefix("/webstore"))
    }
}

/// Settings › Browsing › Searching › Home page: what a new tab opens to, while an
/// extension offers a page for it. Search's own page with the address field
/// ready, or the page of an extension that asked to take its place, and
/// the way back from one that did. With nothing offered there is nothing to
/// pick, so the line isn't there at all, and neither is its hairline.
struct NewTabPageLine: View {
    var body: some View {
        if #available(macOS 15.4, *) {
            Chooser(extensions: .shared)
        }
    }

    @available(macOS 15.4, *)
    private struct Chooser: View {
        @ObservedObject var extensions: Extensions

        var body: some View {
            let askers = extensions.newTabAskers
            let current = extensions.newTabPageID
            if !askers.isEmpty {
                Rule(inset: SettingsPanel.textInset)
                SettingRow(icon: "house", title: L10n.text("upstream.newTab.page"), detail: detail(askers, current)) {
                    Picker("", selection: Binding(
                        get: { current ?? "" },
                        set: { extensions.setNewTabPage($0.isEmpty ? nil : $0) }
                    )) {
                        Text(L10n.text("upstream.newTab.blank")).tag("")
                        Divider()
                        ForEach(askers) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }

        private func detail(_ askers: [Installed], _ current: String?) -> String {
            if let current, let name = askers.first(where: { $0.id == current })?.name {
                return L10n.text("upstream.newTab.showExtension", name)
            }
            return askers.count == 1
                ? L10n.text("upstream.newTab.askedOne", askers[0].name)
                : L10n.text("upstream.newTab.askedMany", String(askers.count))
        }
    }
}
