import SwiftUI

/// Everything there is to set. Pages down the left, one page at a time on
/// the right, each a short list of lines with a hairline between them —
/// nothing to scroll through, nothing to hunt for. The same white and
/// hairline as the rest of the app; the same pill for the page you are on
/// as for the tab you are on.
struct SettingsPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    @ObservedObject private var language = LanguageSettings.shared
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var shield = Shield.shared
    @State private var startPageDraft = ""
    @State private var isDefault = Links.isDefault
    /// A site shortcut being written, kept out of Preferences until it's saved.
    @State private var draft: Keyword?
    @State private var page: Page = Page(rawValue: Store.settings.string(forKey: "settings.page") ?? "") ?? .general

    enum Page: String, CaseIterable, Identifiable {
        case general, tabs, shortcuts, bookmarks, extensions, passwords, downloads, privacy, about, flowDrag
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return L10n.text("Settings.0692")
            case .tabs: return L10n.text("Settings.0693")
            case .flowDrag: return L10n.text("flowDrag.title")
            case .shortcuts: return L10n.text("Settings.0694")
            case .bookmarks: return L10n.text("bookmarks.manager.title")
            case .extensions: return L10n.text("Settings.0695")
            case .passwords: return L10n.text("Settings.0696")
            case .downloads: return L10n.text("Settings.0697")
            case .privacy: return L10n.text("Settings.0698")
            case .about: return L10n.text("Settings.0699")
            }
        }
        var icon: String {
            switch self {
            case .general: return "macwindow"
            case .tabs: return "rectangle.split.3x1"
            case .flowDrag: return "hand.draw"
            case .shortcuts: return "keyboard"
            case .bookmarks: return "book"
            case .extensions: return "puzzlepiece.extension"
            case .passwords: return "key"
            case .downloads: return "arrow.down.circle"
            case .privacy: return "hand.raised"
            case .about: return "info.circle"
            }
        }
    }

    private static let rail: CGFloat = 168
    private static let width: CGFloat = 660
    private static let height: CGFloat = 500

    var body: some View {
        HStack(spacing: 0) {
            pages
            Rectangle().fill(Palette.hairline).frame(width: 1)
            content
        }
        .frame(width: SettingsPanel.width, height: SettingsPanel.height)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 34, y: 12)
        .onAppear { startPageDraft = prefs.startPage }
        .onChange(of: prefs.startPage) { _, value in startPageDraft = value }
        .onChange(of: page) { _, page in Store.settings.set(page.rawValue, forKey: "settings.page") }
    }

    // MARK: - the rail

    private var pages: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text("Settings.0700"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 12)
            ForEach(Page.allCases.filter{$0 != .flowDrag}) { item in
                PageRow(page: item, on: page == item) { page = item }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: SettingsPanel.rail, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.wash.opacity(0.45), in: Rectangle())
    }

    private struct PageRow: View {
        let page: Page
        let on: Bool
        let act: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                HStack(spacing: 9) {
                    Image(systemName: page.icon)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 16)
                    Text(page.title)
                        .font(.system(size: 13, weight: on ? .medium : .regular))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(on ? Palette.ink : (hovering ? Palette.ink.opacity(0.75) : Palette.muted))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(on ? Palette.ground : (hovering ? Palette.hover : .clear))
                        .shadow(color: .black.opacity(on ? 0.06 : 0), radius: 3, y: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }

    // MARK: - the page

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(page.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Door(icon: "xmark", help: L10n.text("Settings.0701")) { browser.tuning = false }
            }
            .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    switch page {
                    case .general: general
                    case .tabs:
                        Card {Line(L10n.text("flowDrag.title"),""){Pill(L10n.text("Settings.0786")){page = .flowDrag}}}
                        tabs
                        if !prefs.sidebar { toolbar }
                    case .shortcuts: ShortcutsPage(browser: browser, store: .shared, prefs: prefs)
                    case .flowDrag:
                        Button("← "+L10n.text("Settings.0693")){page = .tabs}.buttonStyle(.plain)
                        FlowDragSettingsPage(browser:browser)
                    case .bookmarks:
                        Card {
                            Line(L10n.text("bookmarks.manager.title"), L10n.text("bookmarks.manager.detail")) {
                                Pill(L10n.text("Settings.0786")) {
                                    browser.tuning = false
                                    browser.bookmarking = true
                                }
                            }
                        }
                    case .extensions: ExtensionsPage(browser: browser)
                    case .passwords: passwords
                    case .downloads: downloads
                    case .privacy: privacy
                    case .about: about
                    }
                }
                .padding(.bottom, 4)
            }
            // A page of its own opens at its top. One scroll view kept for
            // them all opened Tabs as far down as General had been read.
            .id(page)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var startPageProblem: String? {
        let text = startPageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && StartPage.url(from: text) == nil ? L10n.text("startPage.invalid") : nil
    }

    private func saveStartPage() {
        guard startPageProblem == nil else { return }
        prefs.startPage = StartPage.url(from: startPageDraft)?.absoluteString ?? ""
        startPageDraft = prefs.startPage
    }

    // MARK: - general

    private var general: some View {
        Card {
            Line(L10n.text("language.title"), L10n.text("language.detail")) {
                Picker(L10n.text("language.title"), selection: $language.selection) {
                    ForEach(InterfaceLanguage.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            if language.needsRestart {
                Rule()
                Line(L10n.text("language.pending"), L10n.text("language.restartDetail")) {
                    Pill(L10n.text("language.restart"), filled: true) { language.restart() }
                }
            }
            Rule()
            Line(L10n.text("startPage.title"), L10n.text("startPage.detail")) { EmptyView() }
            HStack(spacing: 8) {
                TextField(L10n.text("startPage.placeholder"), text: $startPageDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .onSubmit(saveStartPage)
                Pill(L10n.text("startPage.save"), filled: true, action: saveStartPage)
                    .disabled(startPageProblem != nil || startPageDraft == prefs.startPage)
                Pill(L10n.text("startPage.blank")) {
                    prefs.startPage = ""
                    startPageDraft = ""
                }
                .disabled(prefs.startPage.isEmpty && startPageDraft.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 11)
            if let problem = startPageProblem {
                Text(problem)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 11)
            }
            Rule()
            Line(
                L10n.text("Settings.0702"),
                isDefault ? L10n.text("Settings.0703") : L10n.text("Settings.0704")
            ) {
                if isDefault {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 24)
                } else {
                    Pill(L10n.text("Settings.0705"), filled: true) {
                        Links.becomeDefault { worked in
                            isDefault = Links.isDefault
                            browser.announce(worked && isDefault ? L10n.text("Settings.0706") : L10n.text("Settings.0707"))
                        }
                    }
                }
            }
            Rule()
            // Coming from another browser, now or any time later: the same
            // sheet as File › Bring Things Over… and the Welcome's.
            Line(L10n.text("Settings.0708"), L10n.text("Settings.0709")) {
                Pill(L10n.text("Settings.0710")) {
                    browser.tuning = false
                    browser.bringingIn = ""
                }
            }
            Rule()
            Line(L10n.text("Settings.0711"), searchDetail) {
                Picker("", selection: $prefs.engine) {
                    ForEach(Engine.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            if prefs.engine == .custom {
                ZStack(alignment: .leading) {
                    if prefs.customEngine.isEmpty {
                        Text("https://example.com/search?q=%s")
                            .foregroundStyle(Palette.muted.opacity(0.8))
                    }
                    TextField("", text: $prefs.customEngine)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Palette.ink)
                }
                .font(.system(size: 12.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 11)
            }
            Rule()
            Line(L10n.text("suggestions.title"), suggestDetail) {
                Switch(on: $prefs.engineSuggests)
            }
            Rule()
            Line(L10n.text("Settings.0712"), keywordDetail) {
                if draft == nil {
                    Pill(L10n.text("Settings.0713")) { draft = Keyword() }
                } else {
                    HStack(spacing: 6) {
                        Pill(L10n.text("Settings.0714")) { draft = nil }
                        Pill(L10n.text("Settings.0715"), filled: true) { saveDraft() }
                            .disabled(draftProblem != nil)
                            .opacity(draftProblem == nil ? 1 : 0.4)
                    }
                }
            }
            if let current = draft {
                HStack(spacing: 8) {
                    TextField("yt", text: Binding(
                        get: { current.keyword },
                        set: { draft?.keyword = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .frame(width: 50)
                    Text("→").foregroundStyle(Palette.muted)
                    TextField("https://www.youtube.com/results?search_query=%s", text: Binding(
                        get: { current.template },
                        set: { draft?.template = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .onSubmit(saveDraft)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
            ForEach(prefs.keywords) { entry in
                HStack(spacing: 8) {
                    Text(entry.keyword)
                        .frame(width: 50, alignment: .leading)
                    Text("→").foregroundStyle(Palette.muted)
                    Text(entry.template)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        prefs.keywords.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.faint)
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
            Rule()
            Line(L10n.text("Settings.0716"), L10n.text("Settings.0717")) {
                Segmented(options: Look.allCases.map { ($0, $0.title) }, selection: $prefs.look)
            }
            // Only where it can do something: in Light, nothing is darkened.
            if prefs.look != .light {
                Rule()
                Line(L10n.text("sync.settings.dark"), L10n.text("sync.settings.dark.detail")) {
                    Switch(on: $prefs.darkensPages)
                }
            }
            Rule()
            Line(L10n.text("Settings.0718"), L10n.text("Settings.0719")) {
                // The number itself takes it back to 100%.
                Steps(stops: Preferences.zooms, value: $prefs.pageZoom, home: 1) { "\(Int(($0 * 100).rounded()))%" }
            }
            Rule()
            Line(L10n.text("Settings.0720"), L10n.text("Settings.0721")) {
                Switch(on: $prefs.autocorrect)
            }
            Rule()
            Line(L10n.text("sync.peek.title", prefs.peekClick.title), L10n.text("Settings.0723")) {
                Switch(on: $prefs.peeksLinks)
            }
            Rule()
            Line(L10n.text("Settings.0724"), L10n.text("Settings.0725")) {
                Switch(on: $prefs.littleLinks)
            }
            Rule()
            Line(L10n.text("Settings.0726"), L10n.text("Settings.0727")) {
                Switch(on: $prefs.commandBar)
            }
            Rule()
            Line(L10n.text("Settings.0728"), L10n.text("Settings.0729")) {
                Switch(on: $prefs.showsLinks)
            }
            Rule()
            Line(L10n.text("Settings.0730"), L10n.text("Settings.0731")) {
                Switch(on: $prefs.autoScroll)
            }
            Rule()
            Line(L10n.text("Settings.0732"), L10n.text("sync.settings.fast.detail")) {
                Segmented(options: FastPages.allCases.map { ($0, $0.title) }, selection: $prefs.fastPages)
            }
            Rule()
            Line(L10n.text("Settings.0734"), L10n.text("Settings.0735")) {
                Switch(on: $prefs.holdsHistory)
            }
            Rule()
            Line(L10n.text("Settings.0736"), L10n.text("Settings.0737")) {
                Switch(on: $prefs.floatFlicks)
            }
            Rule()
            Line(L10n.text("Settings.0738"), L10n.text("Settings.0739")) {
                Switch(on: $prefs.waitsForPlay)
            }
            Rule()
            Line(L10n.text("Settings.0740"), L10n.text("Settings.0741")) {
                Switch(on: $prefs.floatsOnLeave)
            }
            Rule()
            Line(L10n.text("Settings.0742"), L10n.text("Settings.0743")) {
                Switch(on: $prefs.floatsAway)
            }
            Rule()
            Line(L10n.text("Settings.0744"), L10n.text("Settings.0745")) {
                Switch(on: $prefs.bench)
            }
        }
    }

    /// Checked when it's saved, not as it's typed into the list: a shortcut
    /// only exists once its address is one it's safe to send words to.
    private var draftProblem: String? {
        guard let draft else { return nil }
        return Keyword.problem(word: draft.keyword, template: draft.template, among: prefs.keywords)
    }

    private var keywordDetail: String {
        guard let draft else {
            return L10n.text("Settings.0746")
        }
        if draft.keyword.isEmpty, draft.template.isEmpty {
            return L10n.text("Settings.0747")
        }
        return draftProblem ?? L10n.text("Settings.0748", String(describing: draft.keyword.trimmingCharacters(in: .whitespacesAndNewlines)), String(describing: draft.name))
    }

    private func saveDraft() {
        guard let current = draft, draftProblem == nil else { return }
        prefs.keywords.append(Keyword(
            keyword: current.keyword.trimmingCharacters(in: .whitespacesAndNewlines),
            template: current.template.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        draft = nil
    }

    private var suggestDetail: String {
        guard EngineSuggest.endpoint(for: prefs.engine) != nil else {
            return L10n.text("suggestions.customDetail")
        }
        return L10n.text("suggestions.detail", prefs.engine.name(custom: prefs.customEngine))
    }

    private var searchDetail: String {
        guard prefs.engine == .custom else { return L10n.text("Settings.0749") }
        guard Engine.accepts(prefs.customEngine) else {
            return L10n.text("Settings.0750")
        }
        return L10n.text("Settings.0751", String(describing: prefs.engine.name(custom: prefs.customEngine)))
    }

    // MARK: - tabs

    /// Where back, forward and reload sit with the tabs across the top. With
    /// the sidebar they are already beside the window's buttons: nothing to
    /// move, and the line isn't shown.
    private var toolbar: some View {
        Card {
            Line(L10n.text("Settings.0752"), L10n.text("Settings.0753")) {
                Switch(on: $prefs.navigationLeft)
            }
        }
    }

    private var tabs: some View {
        Card {
            NewTabPageLine()
            Line(L10n.text("Settings.0754"), L10n.text("Settings.0755", String(describing: prefs.sidePosition.rawValue))) {
                Switch(on: Binding(
                    get: { prefs.sidebar },
                    set: { on in withAnimation(Motion.glide) { prefs.sidebar = on } }
                ))
            }
            if prefs.sidebar {
                Rule()
                Line(L10n.text("Settings.0756"), L10n.text("Settings.0757", String(describing: prefs.sidePosition.rawValue))) {
                    Segmented(options: SidebarPosition.allCases.map { ($0, $0.title) }, selection: $prefs.sidePosition)
                }
                Rule()
                Line(L10n.text("Settings.0758"), L10n.text("Settings.0759", String(describing: prefs.sidePosition.rawValue))) {
                    Switch(on: $prefs.sideHides)
                }
                Rule()
                Line(L10n.text("sync.settings.cards"), L10n.text("sync.settings.cards.detail")) {
                    Switch(on: Binding(
                        get: { prefs.cards },
                        set: { on in withAnimation(Motion.glide) { prefs.cards = on } }
                    ))
                }
                Rule()
                Line(L10n.text("sync.settings.roomy"), L10n.text("sync.settings.roomy.detail")) {
                    Switch(on: Binding(
                        get: { prefs.roomyTabs },
                        set: { on in withAnimation(Motion.glide) { prefs.roomyTabs = on } }
                    ))
                }
            }
            Rule()
            Line(L10n.text("Settings.0760"), L10n.text("Settings.0761")) {
                Segmented(options: Glyph.allCases.map { ($0, $0.title) }, selection: $prefs.glyph)
            }
            Rule()
            Line(L10n.text("Settings.0762"), L10n.text("Settings.0763")) {
                Switch(on: $prefs.bookmarksBar)
            }
            Rule()
            Line(L10n.text("bookmarks.bar.compact.title"), L10n.text("bookmarks.bar.compact.detail")) {
                Switch(on: $prefs.compactBookmarksBar)
            }
            Rule()
            Line(L10n.text("bookmarks.bar.opening.title"), L10n.text("bookmarks.bar.opening.detail")) {
                Picker(L10n.text("bookmarks.bar.opening.title"), selection: $prefs.bookmarkBarOpening) {
                    ForEach(BookmarkBarOpening.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            Rule()
            Line(L10n.text("Settings.0764"), L10n.text("Settings.0765")) {
                Switch(on: $prefs.showsReading)
            }
            Rule()
            Line(L10n.text("Settings.0766"), L10n.text("sync.settings.sleep.detail")) {
                Switch(on: $prefs.sleepsTabs)
            }
            if prefs.sleepsTabs {
                Rule()
                Line(L10n.text("sync.settings.sleepPace"), prefs.sleepPace.detail) {
                    Segmented(options: SleepPace.allCases.map { ($0, $0.title) }, selection: $prefs.sleepPace)
                }
            }
            Rule()
            Line(L10n.text("sync.settings.tabLife"), L10n.text("sync.settings.tabLife.detail")) {
                Picker("", selection: $prefs.tabLife) {
                    ForEach(TabLife.allCases) { life in
                        Text(life.title).tag(life)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            Rule()
            Line(L10n.text("sync.settings.keepAwake"), L10n.text("sync.settings.keepAwake.detail")) {
                Switch(on: $prefs.keepsSitesAwake)
                    .accessibilityRepresentation { Toggle(L10n.text("sync.settings.keepAwake"), isOn: $prefs.keepsSitesAwake) }
                    .focusable()
                    .onKeyPress(.space) { prefs.keepsSitesAwake.toggle(); return .handled }
            }
            Rule()
            Line(L10n.text("Settings.0768"), L10n.text("Settings.0769")) {
                Switch(on: $prefs.lazyTabs)
            }
            Rule()
            Line(L10n.text("sync.settings.afterLast"), L10n.text("sync.settings.afterLast.detail")) {
                Switch(on: $prefs.newTabAfterLast)
            }
            Rule()
            Line(L10n.text("sync.settings.newPlace"), L10n.text("sync.settings.newPlace.detail")) {
                Picker(L10n.text("sync.settings.newPlace"), selection: $prefs.newTabPlace) {
                    Text(L10n.text("sync.settings.next")).tag(NewTabPlace.next)
                    Text(prefs.sidebar ? L10n.text("sync.settings.top") : L10n.text("sync.settings.leftmost")).tag(NewTabPlace.top)
                    Text(prefs.sidebar ? L10n.text("sync.settings.bottom") : L10n.text("sync.settings.rightmost")).tag(NewTabPlace.end)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            Rule()
            Line(L10n.text("Settings.0770"), L10n.text("Settings.0771")) {
                Switch(on: $prefs.searchesSites)
            }
            Rule()
            Line(L10n.text("Settings.0772"), L10n.text("Settings.0773")) {
                Switch(on: $prefs.startsFresh)
            }
            Rule()
            Line(L10n.text("Settings.0774"), L10n.text("Settings.0775")) {
                Switch(on: $prefs.usesSpaces)
            }
            if prefs.usesSpaces {
                Rule()
                Line(L10n.text("sync.settings.sharedPins"), L10n.text("sync.settings.sharedPins.detail")) {
                    Switch(on: $prefs.sharesPins)
                }
            }
            Rule()
            Line(L10n.text("Settings.0776"), L10n.text("Settings.0777")) {
                Switch(on: $prefs.usesTabGroups)
            }
            if prefs.sidebar {
                Rule()
                Line(L10n.text("Settings.0778"), L10n.text("Settings.0779")) {
                    Switch(on: $prefs.listsPins)
                }
            }
            Rule()
            Line(L10n.text("sync.settings.pinsHome"), L10n.text("sync.settings.pinsHome.detail")) {
                Switch(on: $prefs.pinsGoHome)
            }
            Rule()
            Line(L10n.text("pins.peek.title"), L10n.text("pins.peek.detail")) {
                Switch(on: $prefs.pinsPeek)
            }
            Rule()
            Line(L10n.text("Settings.0780"), L10n.text("Settings.0781")) {
                Switch(on: $prefs.splitView)
            }
            Rule()
            Line(L10n.text("sync.settings.switcherKeys"), L10n.text("sync.settings.switcherKeys.detail")) {
                Switch(on: $prefs.switcherKeys)
            }
        }
    }

    // MARK: - passwords

    /// Says so when a password manager extension has taken the saving over.
    private var savingDetail: String {
        if #available(macOS 15.4, *), let name = Extensions.shared.passwordSavingTakenBy {
            return L10n.text("Settings.0782", String(describing: name))
        }
        return L10n.text("Settings.0783")
    }

    private var passwords: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Line(L10n.text("Settings.0784"), L10n.text("Settings.0785")) {
                    Pill(L10n.text("Settings.0786")) {
                        browser.tuning = false
                        browser.managing = true
                    }
                }
                Rule()
                Line(L10n.text("Settings.0787"), savingDetail) {
                    Switch(on: $prefs.savesPasswords)
                }
                Rule()
                Line(L10n.text("Settings.0788"), L10n.text("Settings.0789")) {
                    Switch(on: $prefs.fillsPasswords)
                }
                Rule()
                Line(
                    L10n.text("Settings.0790"),
                    !prefs.passkeysPossible
                        ? L10n.text("Settings.0791")
                        : Passkeys.access == .denied
                        ? L10n.text("Settings.0792")
                        : L10n.text("Settings.0793")
                ) {
                    Switch(on: $prefs.passkeys)
                }
                if !Vault.never.isEmpty {
                    Rule()
                    Line(L10n.text("Settings.0794"), L10n.text("Settings.0795", String(describing: Vault.never.count))) {
                        Pill(L10n.text("Settings.0796")) {
                            Vault.never = []
                            browser.announce(L10n.text("Settings.0797"))
                        }
                    }
                }
            }
            Card {
                Line(L10n.text("Settings.0798"), L10n.text("Settings.0799")) {
                    Pill(L10n.text("Settings.0800")) {
                        browser.tuning = false
                        browser.bringingIn = ""
                    }
                }
            }
        }
    }

    // MARK: - downloads

    private var downloads: some View {
        Card {
            Line(L10n.text("Settings.0801"), prefs.downloads.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                Pill(L10n.text("Settings.0802")) { chooseFolder() }
            }
            Rule()
            Line(L10n.text("Settings.0803")) {
                Switch(on: $prefs.asksWhereToSave)
            }
            Rule()
            Line(L10n.text("Settings.0804"), L10n.text("Settings.0805")) {
                Switch(on: $prefs.alwaysShowsDownloads)
            }
        }
    }

    // MARK: - privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Line(L10n.text("Settings.0806"), shield.trouble ?? L10n.text("Settings.0807")) {
                    Switch(on: $prefs.shielded)
                }
                if let trouble = shield.trouble {
                    Rule()
                    Line(trouble, L10n.text("Settings.0808")) {
                        Pill(L10n.text("Settings.0809")) { shield.compile() }
                    }
                }
                if let host = browser.hereHost, prefs.shielded, shield.trouble == nil {
                    Rule()
                    Line(L10n.text("Settings.0810", String(describing: host)), L10n.text("Settings.0811")) {
                        Switch(on: Binding(
                            get: { !Shield.shared.isPaused(on: host) },
                            set: { on in
                                Shield.shared.pause(host, !on)
                                browser.reload()
                            }
                        ))
                    }
                }
                Rule()
                Line(L10n.text("Settings.0812"), L10n.text("Settings.0813")) {
                    Switch(on: Binding(get: { !prefs.keepsSignIns }, set: { prefs.keepsSignIns = !$0 }))
                }
                Rule()
                Line(L10n.text("Settings.0814"), L10n.text("Settings.0815")) {
                    Pill(L10n.text("Settings.0816")) { browser.forgetCaptureChoices() }
                }
                Rule()
                Line(L10n.text("Settings.0817"), L10n.text("Settings.0818")) {
                    Switch(on: $prefs.siteNotifications)
                }
                NotificationSites()
                PopupSiteList(prefs: prefs)
            }
            Card {
                Line(L10n.text("Settings.0819"), L10n.text("Settings.0820")) {
                    Pill(L10n.text("Settings.0821")) { browser.clearHistory() }
                }
                Rule()
                Line(L10n.text("Settings.0822"), L10n.text("Settings.0823")) {
                    Pill(L10n.text("Settings.0824")) { browser.clearSites() }
                }
                Rule()
                Line(L10n.text("Settings.0825"), L10n.text("Settings.0826")) {
                    Pill(L10n.text("Settings.0827")) { browser.clearCache() }
                }
            }
        }
    }

    // MARK: - about

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AppLogo()
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SearcheXtra")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(L10n.text("Settings.0828", String(describing: Updater.version)))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.bottom, 2)

            Card {
                Line(versionTitle, versionDetail) { versionControl }
                Rule()
                Line(L10n.text("updates.github.title"), L10n.text("updates.github.detail")) {
                    Pill("GitHub Releases") { NSWorkspace.shared.open(URL(string: "https://github.com/small32/SearcheXtra/releases/latest")!) }
                }
                Rule()
                Line(L10n.text("Settings.0831"), L10n.text("Settings.0832")) {
                    Pill(L10n.text("Settings.0833")) { Links.writeFeedback() }
                }
                Rule()
                Line(L10n.text("Settings.0834"), L10n.text("Settings.0835")) {
                    Pill(L10n.text("Settings.0836")) { browser.notesShowing = true }
                }
            }

            Card {
                Shortcut("⌘L", L10n.text("Settings.0837"))
                Rule()
                Shortcut("⌘K", L10n.text("Settings.0838"))
                Rule()
                Shortcut("⌘T  ⌘W  ⇧⌘T", L10n.text("Settings.0839"))
                Rule()
                Shortcut("⇧⌘V", L10n.text("Settings.0840"))
                Rule()
                Shortcut("⇧⌘C", L10n.text("Settings.0841"))
                Rule()
                Shortcut("⌃⇥  ⌘1–9", L10n.text("Settings.0842"))
                Rule()
                Shortcut("⇧⌘S", L10n.text("Settings.0843"))
                Rule()
                Shortcut("⌘S", L10n.text("Settings.0844"))
                Rule()
                Shortcut("⇧⌘R", L10n.text("Settings.0845"))
                Rule()
                Shortcut("⇧⌘H", L10n.text("Settings.0846"))
                Rule()
                Shortcut("⇧⌘P", L10n.text("Settings.0847"))
                Rule()
                Shortcut("⇧⌘⌫", L10n.text("Settings.0848"))
            }
        }
    }

    /// The version line follows the newer build from found to fetched to
    /// in place; with none, it is simply this one.
    private var versionTitle: String {
        switch updater.stage {
        case .none: return L10n.text("Settings.0849")
        case .fetching(let next): return L10n.text("Settings.0850", String(describing: next.version))
        case .ready(let next): return L10n.text("Settings.0851", String(describing: next.version))
        case .offered(let next), .waiting(let next): return L10n.text("Settings.0852", String(describing: next.version))
        }
    }

    private var versionDetail: String {
        if updater.checkFailed { return L10n.text("Updater.checkFailed") }
        switch updater.stage {
        case .none:
            return updater.lastChecked.map { L10n.text("Settings.0853", String(describing: $0.formatted(.relative(presentation: .named)))) }
                ?? L10n.text("Settings.0854")
        case .fetching(let next):
            return next.notes ?? L10n.text("Settings.0855")
        case .ready(let next):
            return next.notes ?? L10n.text("Settings.0856")
        case .offered(let next):
            return next.notes ?? L10n.text("Settings.0857")
        case .waiting(let next):
            return next.notes ?? L10n.text("Settings.0858")
        }
    }

    @ViewBuilder
    private var versionControl: some View {
        switch updater.stage {
        case .none:
            Pill(updater.checking ? L10n.text("Settings.0859") : L10n.text("Settings.0860")) {
                updater.check { found in
                    if found == nil, !updater.checkFailed { browser.announce(L10n.text("Settings.0861")) }
                }
            }
            .disabled(updater.checking)
        case .fetching:
            Ring(size: 12)
        case .ready:
            Pill(L10n.text("Settings.0862"), filled: true) { updater.relaunch() }
        case .offered:
            Pill(updater.fetchingDisk ? L10n.text("Settings.0863") : L10n.text("Settings.0864"), filled: true) { updater.openDisk() }
                .disabled(updater.fetchingDisk)
        case .waiting:
            Pill(L10n.text("Settings.0865"), filled: true) { updater.install() }
        }
    }

    // MARK: - doing

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = prefs.downloads
        panel.prompt = L10n.text("Settings.0866")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.downloads = url
    }

    // MARK: - pieces

    /// A keystroke and what it does.
    private struct Shortcut: View {
        let keys: String
        let does: String
        init(_ keys: String, _ does: String) { self.keys = keys; self.does = does }

        var body: some View {
            HStack {
                Text(does)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(keys)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }
}

/// A row of choices in a grey track, one of them lifted out in white. The
/// white slides to the one you pick rather than appearing there.
struct Segmented<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option
    /// True when the control has the whole width to itself, so the choices
    /// share it evenly instead of each taking only what its word needs.
    var wide = false

    @Namespace private var slide

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option, title in
                Text(title)
                    .font(.system(size: 11.5, weight: option == selection ? .medium : .regular))
                    .foregroundStyle(option == selection ? Palette.ink : Palette.muted)
                    .lineLimit(1)
                    .fixedSize(horizontal: !wide, vertical: false)
                    .frame(maxWidth: wide ? .infinity : nil)
                    .padding(.horizontal, wide ? 4 : 10)
                    .padding(.vertical, 5)
                    .background {
                        if option == selection {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Palette.ground)
                                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "chosen", in: slide)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .onTapGesture {
                        withAnimation(Motion.settle) { selection = option }
                    }
            }
        }
        .padding(2)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(Motion.settle, value: selection)
    }
}

/// On or off, in ink rather than in blue.
struct Switch: View {
    @Binding var on: Bool

    var body: some View {
        Capsule()
            .fill(on ? Palette.ink : Palette.faint)
            .frame(width: 30, height: 18)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(Palette.ground)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                    .padding(2)
            }
            .contentShape(Capsule())
            .onTapGesture { withAnimation(Motion.settle) { on.toggle() } }
            .animation(Motion.settle, value: on)
    }
}

/// A value moved one stop at a time: − and + either side of it, in the same
/// outlined capsule as a pill. Pressing the value itself takes it home.
struct Steps: View {
    let stops: [Double]
    @Binding var value: Double
    let home: Double
    let label: (Double) -> String

    /// The nearest stop either way — a value between stops, from before
    /// there were stops, still moves to a round one.
    private var below: Double? { stops.last { $0 < value - 0.001 } }
    private var above: Double? { stops.first { $0 > value + 0.001 } }

    var body: some View {
        HStack(spacing: 0) {
            Step(icon: "minus", to: below) { value = $0 }
            Button { value = home } label: {
                Text(label(value))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .frame(minWidth: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.text("Settings.0867", String(describing: label(home))))
            Step(icon: "plus", to: above) { value = $0 }
        }
        .padding(.horizontal, 2)
        .frame(height: 24)
        .background(Palette.ground, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private struct Step: View {
        let icon: String
        let to: Double?
        let act: (Double) -> Void
        @State private var hovering = false

        var body: some View {
            Button { if let to { act(to) } } label: {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(to == nil ? Palette.faint : Palette.ink)
                    .frame(width: 20, height: 20)
                    .background(hovering && to != nil ? Palette.hover : .clear, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(to == nil)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }
}

/// A small capsule that does one thing. Outlined by default; filled in ink
/// when it is the thing you came here to press.
struct Pill: View {
    let title: String
    var filled = false
    var tint: Color = Palette.ink
    let action: () -> Void

    @State private var hovering = false

    init(_ title: String, filled: Bool = false, tint: Color = Palette.ink, action: @escaping () -> Void) {
        self.title = title
        self.filled = filled
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(filled ? Palette.ground : tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(filled ? Palette.ink : (hovering ? Palette.hover : Palette.ground), in: Capsule())
                .overlay(Capsule().strokeBorder(filled ? .clear : Palette.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}

/// Settings › Privacy: the sites allowed to send notifications, each with a
/// way to take it back.
private struct NotificationSites: View {
    @ObservedObject private var notifications = SiteNotifications.shared

    var body: some View {
        let sites = SiteNotifications.allowed
        if !sites.isEmpty {
            ForEach(sites, id: \.self) { site in
                Rule()
                Line(URL(string: site).map(SiteCard.site) ?? site, L10n.text("Settings.0868")) {
                    Pill(L10n.text("Settings.0869")) { SiteNotifications.forget(site) }
                }
            }
        }
    }
}
