import AppKit
import SwiftUI
import WebKit

struct TabAddressEditor: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab

    var body: some View {
        HStack(spacing: 6) {
            if let url = tab.pageAddress, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                SiteInfoButton(browser: browser, tab: tab).frame(width: 20, height: 20)
            }
            TabAddressField(browser: browser).frame(height: 16)
        }
    }
}

private struct SiteInfoButton: NSViewRepresentable {
    let browser: Browser
    let tab: Tab
    func makeCoordinator() -> Coordinator { Coordinator(browser: browser, tab: tab) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: L10n.text("site.info"))!, target: context.coordinator, action: #selector(Coordinator.open))
        button.identifier = NSUserInterfaceItemIdentifier("TabSiteInfo")
        button.isBordered = false
        button.refusesFirstResponder = true
        button.toolTip = L10n.text("site.info")
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) { context.coordinator.browser = browser; context.coordinator.tab = tab }
    final class Coordinator: NSObject {
        var browser: Browser
        var tab: Tab
        init(browser: Browser, tab: Tab) { self.browser = browser; self.tab = tab }
        @MainActor @objc func open() { SiteCardPanel.show(for: tab, in: browser) }
    }
}

struct SiteDetails: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    let cookiesPage: Bool
    let back: () -> Void
    @State private var cookies: [HTTPCookie] = []
    @State private var values: [String: String] = [:]
    @State private var choices: [String: Int] = [:]
    @State private var status = ""

    private var dataStore: WKWebsiteDataStore? { tab.built?.configuration.websiteDataStore }
    private var origin: String { tab.pageAddress.map { Browser.origin($0.scheme ?? "", $0.host() ?? "", $0.port ?? 0) } ?? "" }
    private let permissions = [(String(WKMediaCaptureType.camera.rawValue), "site.camera"), (String(WKMediaCaptureType.microphone.rawValue), "site.microphone"), (String(WKMediaCaptureType.cameraAndMicrophone.rawValue), "site.cameraMicrophone"), ("location", "site.location"), ("notifications", "site.notifications")]
    private func cookieKey(_ cookie: HTTPCookie) -> String { cookie.domain + "|" + cookie.path + "|" + cookie.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(L10n.text("site.back"), action: back).buttonStyle(.plain)
            Text(L10n.text(cookiesPage ? "site.data" : "site.settings")).font(.headline)
            if cookiesPage {
                Text(L10n.text("site.cookieCount", String(cookies.count)))
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(cookies, id: \.self) { cookie in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cookie.name).fontWeight(.medium)
                                Text(cookie.domain + cookie.path).font(.caption).foregroundStyle(.secondary)
                                TextField(L10n.text("site.value"), text: Binding(get: { values[cookieKey(cookie)] ?? cookie.value }, set: { values[cookieKey(cookie)] = $0 }))
                                HStack {
                                    Button(L10n.text("site.save")) {
                                        guard var properties = cookie.properties else { return }
                                        properties[.value] = values[cookieKey(cookie)] ?? cookie.value
                                        guard let updated = HTTPCookie(properties: properties) else { return }
                                        dataStore?.httpCookieStore.setCookie(updated) { status = L10n.text("site.saved") }
                                    }
                                    Button(L10n.text("site.delete")) { dataStore?.httpCookieStore.delete(cookie) { loadCookies() } }
                                }
                            }
                        }
                    }
                }.frame(maxHeight: 260)
                Button(L10n.text("site.clear"), action: clearData)
            } else {
                ForEach(permissions.map { $0.0 }, id: \.self) { permissionID in
                    let permission = permissions.first { $0.0 == permissionID }!
                    Picker(L10n.text(permission.1), selection: Binding(get: { choices[permission.0] ?? 0 }, set: { value in
                        choices[permission.0] = value
                        let key = origin + "|" + permission.0
                        if tab.shy {
                            if value == 0 { browser.transientSitePermissions.removeValue(forKey: key) }
                            else { browser.transientSitePermissions[key] = value == 1 }
                        } else if value == 0 { Store.settings.removeObject(forKey: "capture." + key) }
                        else { Store.settings.set(value == 1, forKey: "capture." + key) }
                        status = L10n.text("site.reload")
                    })) {
                        Text(L10n.text("site.ask")).tag(0)
                        Text(L10n.text("site.allow")).tag(1)
                        Text(L10n.text("site.block")).tag(2)
                    }
                    .disabled(tab.shy && permissionID == "notifications")
                }
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(12).frame(width: 320)
        .onAppear {
            loadCookies()
            for permission in permissions {
                let key = origin + "|" + permission.0
                let value = tab.shy ? browser.transientSitePermissions[key] : Store.settings.object(forKey: "capture." + key) as? Bool
                choices[permission.0] = value.map { $0 ? 1 : 2 } ?? 0
            }
        }
    }

    private func loadCookies() {
        guard let host = tab.pageAddress?.host(), let dataStore else { return }
        dataStore.httpCookieStore.getAllCookies { all in
            cookies = all.filter { cookie in
                let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                return host == domain || host.hasSuffix("." + domain)
            }
        }
    }

    private func clearData() {
        guard let host = tab.pageAddress?.host(), let dataStore else { return }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: types) { records in
            let selected = records.filter { host == $0.displayName || host.hasSuffix("." + $0.displayName) }
            dataStore.removeData(ofTypes: types, for: selected) {
                loadCookies(); status = L10n.text("site.cleared")
            }
        }
    }
}
