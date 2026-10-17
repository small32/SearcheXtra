import AppKit
import SwiftUI
import WebKit

@available(macOS 15.4, *)
@MainActor
final class ExtensionManagerWindow {
    static let shared = ExtensionManagerWindow()
    private(set) var window: NSWindow?

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L10n.text("extensions.manage")
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 440, height: 360)
        window.contentView = NSHostingView(rootView: ExtensionManager(extensions: .shared)
            .environment(\.locale, Locale(identifier: L10n.language)))
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

@available(macOS 15.4, *)
private struct ExtensionManager: View {
    @ObservedObject var extensions: Extensions
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("extensions.manage"))
                .font(.system(size: 20, weight: .semibold))
            TextField(L10n.text("extensions.search"), text: $search)
                .textFieldStyle(.plain)
                .disabled(extensions.busy != nil)
                .padding(12)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9))
            ScrollView {
                let items = extensions.installed.filter {
                    search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.name.localizedCaseInsensitiveContains(search.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if items.isEmpty {
                    Nothing(L10n.text("extensions.empty"))
                        .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], alignment: .leading, spacing: 16) {
                        ForEach(items) { item in
                            ExtensionManagerCard(item: item, extensions: extensions)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Palette.ink)
        .background(Palette.ground)
    }
}

@available(macOS 15.4, *)
private struct ExtensionManagerCard: View {
    let item: Installed
    @ObservedObject var extensions: Extensions
    @ObservedObject private var capture = ExtensionCapture.shared
    @State private var expanded = false
    @State private var updateMessage: String?
    @State private var pendingPermissions: [String]?
    @State private var consent: CheckedContinuation<Bool, Never>?

    var body: some View {
        let context = extensions.contexts[item.id]
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let icon = context?.webExtension.icon(for: CGSize(width: 32, height: 32)) {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "puzzlepiece.extension").foregroundStyle(Palette.muted)
                    }
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.system(size: 14, weight: .semibold))
                    Text(L10n.text("extensions.version", item.version)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Pill(L10n.text("extensions.details")) { expanded.toggle() }
                    .disabled(extensions.busy == item.id)
                Pill(L10n.text("ExtensionsUI.0502")) { ExtensionActions.confirmRemove(item.id, name: item.name, extensions) }
                    .disabled(extensions.busy == item.id)
                Spacer(minLength: 8)
                Switch(on: Binding(get: { item.enabled }, set: { extensions.setEnabled(item.id, $0) }))
                    .accessibilityLabel(L10n.text("extensions.enable", item.name))
            }
            Text(L10n.text(item.enabled ? "extensions.enabled" : "extensions.disabled"))
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            if expanded {
                Rule()
                Toggle(L10n.text("extensions.pin"), isOn: Binding(
                    get: { item.pinned == true }, set: { extensions.setPinned(item.id, $0) }
                ))
                .toggleStyle(.checkbox)
                if extensions.supportsUserScripts(item.id) {
                    Toggle(L10n.text("extensions.userScripts.label"), isOn: Binding(
                        get: { Extensions.userScriptsAllowed(item.id) },
                        set: { extensions.setUserScriptsAllowed(item.id, $0) }
                    )).toggleStyle(.checkbox)
                        .disabled(extensions.busy == item.id)
                    Text(L10n.text("extensions.userScripts.detail"))
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Pill(L10n.text("extensions.open")) { extensions.press(item.id) }
                    .disabled(!item.enabled)
                if context?.optionsPageURL != nil {
                    Pill(L10n.text("ExtensionsUI.0501")) { extensions.openOptions(item.id) }
                }
                if item.fromStore {
                    Pill(L10n.text("extensions.update")) {
                        updateMessage = L10n.text("extensions.checking")
                        Task {
                            updateMessage = await extensions.update(item, manual: true,
                                progress: { updateMessage = $0 },
                                confirmPermissions: { permissions in
                                    guard ExtensionManagerWindow.shared.window?.isVisible == true else { return false }
                                    return await withCheckedContinuation { continuation in
                                        pendingPermissions = permissions
                                        consent = continuation
                                    }
                                })
                        }
                    }
                    .disabled(extensions.busy != nil)
                    if let updateMessage {
                        Text(updateMessage).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    if let pendingPermissions {
                        ForEach(pendingPermissions, id: \.self) { permission in
                            Text("• " + permission).font(.system(size: 12))
                        }
                        HStack(spacing: 8) {
                            Pill(L10n.text("extensions.confirm"), filled: true) { finishConsent(true) }
                            Pill(L10n.text("extensions.cancel")) { finishConsent(false) }
                        }
                    }
                }
                if context?.overrideNewTabPageURL != nil {
                    Toggle(L10n.text("extensions.newTab"), isOn: Binding(
                        get: { Store.settings.bool(forKey: "extensions.newtab.\(item.id)") },
                        set: { Store.settings.set($0, forKey: "extensions.newtab.\(item.id)"); extensions.objectWillChange.send() }
                    )).toggleStyle(.checkbox)
                }
                if item.source != nil || !item.fromStore {
                    Pill(L10n.text("ExtensionsUI.0500")) { extensions.reload(item.id) }
                }
                if ExtensionCapture.allowedIDs.contains(item.id) {
                    Pill(L10n.text("ExtensionsUI.0495")) { ExtensionCapture.forget(item.id) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.wash.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.hairline, lineWidth: 1))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if (note.object as? NSWindow) === ExtensionManagerWindow.shared.window { finishConsent(false) }
        }
        .onDisappear { finishConsent(false) }
    }
    private func finishConsent(_ accepted: Bool) {
        let pending = consent
        consent = nil
        pendingPermissions = nil
        pending?.resume(returning: accepted)
    }
}
