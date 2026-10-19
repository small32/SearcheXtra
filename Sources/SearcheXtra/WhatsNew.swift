import SwiftUI

// What's new, once, after an update.
//
// New features start off, so someone who never opens Settings never meets
// them (a reply on X). The first time a newer version opens, a small card
// shows its new switches, each with a line of what it does and the switch
// itself, and — so nothing gets lost — the switches from earlier versions
// that are still off. Nothing else: few words (Drice). Closed, it
// doesn't come back for that version. Not after a fresh install: the welcome
// is for that. Every version's notes are in Settings › About › What's New…
//
// A release edits `toggles` (its new switches, marked with its version),
// `releases` (that it has a card) and `notes` (what it brought).

enum WhatsNew {
    /// A switch the card offers: the same setting as in Settings.
    struct Toggle {
        let title: String
        let detail: String
        /// The version it came in.
        let since: String
        let get: @MainActor (Preferences) -> Bool
        let set: @MainActor (Preferences, Bool) -> Void
    }

    /// A version that has a card.
    struct Release {
        let version: String
    }

    /// Every switch worth meeting, oldest last. The card shows this
    /// version's, and the older ones still off.
    static let toggles: [Toggle] = [
        Toggle(title: L10n.text("WhatsNew.1191"), detail: L10n.text("WhatsNew.1192"),
               since: "1.0.5", get: { $0.splitView }, set: { $0.splitView = $1 }),
        Toggle(title: L10n.text("WhatsNew.1193"), detail: L10n.text("WhatsNew.1194"),
               since: "1.0.5", get: { $0.searchesSites }, set: { $0.searchesSites = $1 }),
        Toggle(title: L10n.text("WhatsNew.1195"), detail: L10n.text("WhatsNew.1196"),
               since: "1.0.5", get: { $0.startsFresh }, set: { $0.startsFresh = $1 }),

        Toggle(title: L10n.text("WhatsNew.1197"), detail: L10n.text("WhatsNew.1198"),
               since: "1.0.4", get: { $0.usesTabGroups }, set: { $0.usesTabGroups = $1 }),
        Toggle(title: L10n.text("WhatsNew.1199"), detail: L10n.text("WhatsNew.1200"),
               since: "1.0.4", get: { $0.sidebar && $0.sidePosition == .right },
               set: { prefs, on in
                   if on { prefs.sidebar = true }
                   prefs.sidePosition = on ? .right : .left
               }),
        Toggle(title: L10n.text("WhatsNew.1201"), detail: L10n.text("WhatsNew.1202"),
               since: "1.0.4", get: { $0.waitsForPlay }, set: { $0.waitsForPlay = $1 }),
        Toggle(title: L10n.text("WhatsNew.1203"), detail: L10n.text("WhatsNew.1204"),
               since: "1.0.4", get: { $0.alwaysShowsDownloads }, set: { $0.alwaysShowsDownloads = $1 }),

        Toggle(title: L10n.text("WhatsNew.1205"), detail: L10n.text("WhatsNew.1206"),
               since: "1.0.1", get: { $0.usesSpaces }, set: { $0.usesSpaces = $1 }),
        Toggle(title: L10n.text("WhatsNew.1207"), detail: L10n.text("WhatsNew.1208"),
               since: "1.0.1", get: { $0.sidebar && $0.sideHides },
               set: { prefs, on in
                   if on { prefs.sidebar = true }
                   prefs.sideHides = on
               }),
        Toggle(title: L10n.text("WhatsNew.1209"), detail: L10n.text("WhatsNew.1210"),
               since: "1.0.2", get: { $0.bookmarksBar }, set: { $0.bookmarksBar = $1 }),
        Toggle(title: L10n.text("WhatsNew.1211"), detail: L10n.text("WhatsNew.1212"),
               since: "1.0.2", get: { $0.floatsAway }, set: { $0.floatsAway = $1 }),
        Toggle(title: L10n.text("WhatsNew.1213"), detail: L10n.text("WhatsNew.1214"),
               since: "1.0.2", get: { $0.fastPages != .never }, set: { $0.fastPages = $1 ? .always : .never }),
        Toggle(title: L10n.text("WhatsNew.1215"), detail: L10n.text("WhatsNew.1216"),
               since: "1.0.3", get: { $0.autoScroll }, set: { $0.autoScroll = $1 }),
    ]

    static let releases: [Release] = [
        Release(version: "1.0.4"),
    ]

    /// This version's card, when it has one.
    static var current: Release? { releases.first { $0.version == Updater.version } }

    /// Version strings in order: 1.0.10 after 1.0.9.
    static func older(_ one: String, than other: String) -> Bool {
        let a = one.split(separator: ".").compactMap { Int($0) }
        let b = other.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    private static let seenKey = "whatsnew.seen"

    /// At launch, once: whether the card is due. Not on a fresh install (the
    /// welcome is up, and this version counts as seen), nor in a test world
    /// unless the bench asks; otherwise once per version that has a card.
    @MainActor static func due(prefs: Preferences, welcoming: Bool) -> Bool {
        let store = Store.settings
        guard let current, !Store.testing else { return false }
        if welcoming {
            store.set(current.version, forKey: seenKey)
            return false
        }
        guard store.string(forKey: seenKey) != current.version else { return false }
        store.set(current.version, forKey: seenKey)
        return true
    }

    // MARK: - every version's notes

    /// What a version brought, for Settings › About › What's New…
    struct Notes {
        let version: String
        let date: String
        /// A sentence or two: what the version is about.
        let headline: String
        let new: [String]
        let better: [String]
        let fixed: [String]
    }

    /// Newest first.
    static let notes: [Notes] = [
        Notes(version: "1.0.0", date: "2026-10-04",
              headline: L10n.text("release100.headline"),
              new: [L10n.text("release100.language1"), L10n.text("release100.language2"),
                    L10n.text("release100.language3"), L10n.text("release100.start1"),
                    L10n.text("release100.start2"), L10n.text("release100.start3")],
              better: [], fixed: []),
        Notes(
            version: "1.0.4", date: L10n.text("WhatsNew.1217"),
            headline: L10n.text("WhatsNew.1218"),
            new: [
                L10n.text("WhatsNew.1219"),
                L10n.text("WhatsNew.1220"),
                L10n.text("WhatsNew.1221"),
                L10n.text("WhatsNew.1222"),
                L10n.text("WhatsNew.1223"),
                L10n.text("WhatsNew.1224"),
                L10n.text("WhatsNew.1225"),
                L10n.text("WhatsNew.1226"),
                L10n.text("WhatsNew.1227"),
                L10n.text("WhatsNew.1228"),
                L10n.text("WhatsNew.1229"),
            ],
            better: [
                L10n.text("WhatsNew.1230"),
                L10n.text("WhatsNew.1231"),
                L10n.text("WhatsNew.1232"),
                L10n.text("WhatsNew.1233"),
                L10n.text("WhatsNew.1234"),
            ],
            fixed: [
                L10n.text("WhatsNew.1235"),
                L10n.text("WhatsNew.1236"),
                L10n.text("WhatsNew.1237"),
                L10n.text("WhatsNew.1238"),
                L10n.text("WhatsNew.1239"),
                L10n.text("WhatsNew.1240"),
                L10n.text("WhatsNew.1241"),
            ]
        ),
        Notes(
            version: "1.0.3", date: L10n.text("WhatsNew.1242"),
            headline: L10n.text("WhatsNew.1243"),
            new: [
                L10n.text("WhatsNew.1244"),
            ],
            better: [
                L10n.text("WhatsNew.1245"),
                L10n.text("WhatsNew.1246"),
                L10n.text("WhatsNew.1247"),
                L10n.text("WhatsNew.1248"),
            ],
            fixed: [
                L10n.text("WhatsNew.1249"),
                L10n.text("WhatsNew.1250"),
                L10n.text("WhatsNew.1251"),
                L10n.text("WhatsNew.1252"),
            ]
        ),
        Notes(
            version: "1.0.2", date: L10n.text("WhatsNew.1253"),
            headline: L10n.text("WhatsNew.1254"),
            new: [
                L10n.text("WhatsNew.1255"),
                L10n.text("WhatsNew.1256"),
                L10n.text("WhatsNew.1257"),
                L10n.text("WhatsNew.1258"),
            ],
            better: [
                L10n.text("WhatsNew.1259"),
                L10n.text("WhatsNew.1260"),
            ],
            fixed: [
                L10n.text("WhatsNew.1261"),
                L10n.text("WhatsNew.1262"),
            ]
        ),
        Notes(
            version: "1.0.1", date: L10n.text("WhatsNew.1263"),
            headline: L10n.text("WhatsNew.1264"),
            new: [
                L10n.text("WhatsNew.1265"),
                L10n.text("WhatsNew.1266"),
            ],
            better: [],
            fixed: [
                L10n.text("WhatsNew.1267"),
                L10n.text("WhatsNew.1268"),
                L10n.text("WhatsNew.1269"),
            ]
        ),
        Notes(
            version: "1.0", date: L10n.text("WhatsNew.1270"),
            headline: L10n.text("WhatsNew.1271"),
            new: [
                L10n.text("WhatsNew.1272"),
                L10n.text("WhatsNew.1273"),
                L10n.text("WhatsNew.1274"),
                L10n.text("WhatsNew.1275"),
                L10n.text("WhatsNew.1276"),
                L10n.text("WhatsNew.1277"),
            ],
            better: [],
            fixed: []
        ),
    ]
}

/// The card: what's new in this version, its switches right there, and
/// the earlier ones still off.
struct WhatsNewCard: View {
    let release: WhatsNew.Release
    @ObservedObject var prefs: Preferences
    let close: () -> Void
    let notes: () -> Void

    /// Read once, as the card opens: a switch turned on here stays in the
    /// list rather than vanishing under the hand.
    @State private var earlier: [WhatsNew.Toggle]?

    private var fresh: [WhatsNew.Toggle] { WhatsNew.toggles.filter { $0.since == release.version } }

    var body: some View {
        Plate(L10n.text("WhatsNew.1278", String(describing: release.version)), width: 460, close: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    rows(fresh)
                    if let earlier, !earlier.isEmpty {
                        Caption(L10n.text("WhatsNew.1279"))
                            .padding(.top, 6)
                        rows(earlier)
                    }
                }
            }
            .frame(maxHeight: 470)
            .fixedSize(horizontal: false, vertical: true)
        } foot: {
            HStack {
                Button(action: notes) {
                    Text(L10n.text("WhatsNew.1280"))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
                Spacer()
                Pill(L10n.text("WhatsNew.1281"), filled: true, action: close)
            }
        }
        .onAppear {
            if earlier == nil {
                earlier = WhatsNew.toggles.filter { WhatsNew.older($0.since, than: release.version) && !$0.get(prefs) }
            }
        }
    }

    private func rows(_ toggles: [WhatsNew.Toggle]) -> some View {
        Card {
            ForEach(Array(toggles.enumerated()), id: \.offset) { index, toggle in
                if index > 0 { Rule() }
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(toggle.title)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.ink)
                        Text(toggle.detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Switch(on: Binding(get: { toggle.get(prefs) }, set: { toggle.set(prefs, $0) }))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }
}

/// Every version's notes, newest first: Settings › About › What's New…
struct ReleaseNotesPanel: View {
    let close: () -> Void

    var body: some View {
        Plate(L10n.text("WhatsNew.1282"), width: 560, close: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(WhatsNew.notes, id: \.version) { note in
                        version(note)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(maxHeight: 480)
        }
    }

    private func version(_ note: WhatsNew.Notes) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("SearcheXtra \(note.version)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                if !note.date.isEmpty {
                    Text(note.date)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.faint)
                }
            }
            Text(note.headline)
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            list(L10n.text("WhatsNew.1283"), note.new)
            list(L10n.text("WhatsNew.1284"), note.better)
            list(L10n.text("WhatsNew.1285"), note.fixed)
        }
    }

    @ViewBuilder
    private func list(_ title: String, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.muted)
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Palette.faint)
                        Text(line)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 12.5))
                }
            }
        }
    }
}
