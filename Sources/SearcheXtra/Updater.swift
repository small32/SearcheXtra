import AppKit
import Combine
import CryptoKit
import Security

// Check SearcheXtra releases on GitHub and offer the matching macOS download.
// Automatic bundle replacement remains restricted to signed test feeds: public
// builds are ad-hoc signed and must not use the upstream Search signing identity.

@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    static let feed: URL = {
        if overridden, let set = ProcessInfo.processInfo.environment["SEARCH_FEED"], let url = URL(string: set) { return url }
        return URL(string: "https://api.github.com/repos/small32/SearcheXtra/releases/latest")!
    }()

    private static var overridden: Bool {
        Store.testing && ProcessInfo.processInfo.environment["SEARCH_FEED"] != nil
    }

    struct Release: Equatable {
        let version: String
        let build: Int
        /// The ZIP, for the updater.
        let archive: URL
        /// The disk image, for people.
        let dmg: URL
        /// Hex of the ZIP, when the feed gives one.
        let sha256: String?
        /// Hex of the disk image, for the one Search fetches itself.
        var dmgSha256: String? = nil
        let notes: String?
        let minimumSystemVersion: String?

        /// A release that wants a newer macOS than this one is not newer for
        /// this Mac, and is not offered.
        var runsHere: Bool {
            guard let need = minimumSystemVersion else { return true }
            let parts = need.split(separator: ".").map { Int($0) ?? 0 }
            let least = OperatingSystemVersion(
                majorVersion: parts.count > 0 ? parts[0] : 0,
                minorVersion: parts.count > 1 ? parts[1] : 0,
                patchVersion: parts.count > 2 ? parts[2] : 0
            )
            return ProcessInfo.processInfo.isOperatingSystemAtLeast(least)
        }
    }

    /// How far along the newer build is, when there is one.
    enum Stage: Equatable {
        /// None known, or this is the latest.
        case none
        /// The ZIP is on its way, or being looked over.
        case fetching(Release)
        /// Swapped in; it runs at the next launch.
        case ready(Release)
        /// Couldn't be swapped in from here, so the disk image is offered
        /// instead — the same as the first time.
        case offered(Release)
        /// Found, and waiting to be asked for: installing on its own is
        /// switched off in Settings; Install Update is in the Search menu.
        case waiting(Release)
    }

    @Published private(set) var stage: Stage = .none
    /// True while the file is being fetched.
    @Published private(set) var checking = false
    /// Failed requests are not evidence that this is the latest release.
    @Published private(set) var checkFailed = false
    /// When the file was last read, for the line in Settings.
    @Published private(set) var lastChecked: Date?

    /// What this app is: the version people read, and the build that
    /// decides whether another is newer.
    nonisolated static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    nonisolated static var build: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    private var lastKey: String { "update.checked" }
    nonisolated static let installKey = "update.install"
    /// Settings › About › Install updates on its own. On unless switched off.
    private var installsOnItsOwn: Bool { Store.settings.object(forKey: Updater.installKey) as? Bool ?? true }
    /// Where a line goes when there is one to say, handed over at launch.
    private var say: ((String) -> Void)?

    private let currentVersion: String
    private let currentBuild: Int
    private let fetchRelease: () async throws -> Release

    init(version: String = Updater.version, build: Int = Updater.build,
         fetchRelease: @escaping () async throws -> Release = Updater.fetch) {
        currentVersion = version
        currentBuild = build
        self.fetchRelease = fetchRelease
        // The bundle a swap set aside goes once this process is done with
        // it — see Swap.sweep for why not sooner.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in Swap.sweep() }
    }

    /// At launch, then every hour, quietly. A test run, pointed at its own feed,
    /// checks every time.
    func checkIfDue(then say: @escaping (String) -> Void) {
        self.say = say
        Swap.sweep()
        // And again every hour for as long as the app is up — a browser that
        // is left open for a week would otherwise never look.
        if clock == nil {
            clock = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkIfDue() }
            }
            clock?.tolerance = 60 * 5
        }
        // At every launch, whenever the last look was.
        check { _ in }
    }

    private var clock: Timer?

    /// Every hour, give or take the clock's tolerance: one small signed file.
    private func checkIfDue() {
        let last = Store.settings.object(forKey: lastKey) as? Date ?? .distantPast
        guard Updater.overridden || Date().timeIntervalSince(last) > 60 * 50 else { return }
        check { _ in }
    }

    /// Search › Check for Updates…: the result is said in the line at the
    /// foot of the window, and an available update is offered in the menu.
    func checkByHand() {
        switch stage {
        case .ready(let next):
            say?(L10n.text("Updater.1131", String(describing: next.version)))
            return
        case .fetching(let next):
            say?(L10n.text("Updater.1132", String(describing: next.version)))
            return
        default: break
        }
        guard !checking else { return }
        say?(L10n.text("Updater.1133"))
        check { [weak self] found in
            guard let self else { return }
            if found == nil, !self.checkFailed { self.say?(L10n.text("Updater.1134")); return }
            // The waiting branch or `take` announces the next state afterward.
        }
    }

    /// Now, because somebody asked. `done` gets the newer build the feed
    /// names, or nil when current or the request failed (`checkFailed`).
    /// What becomes of it is said through the line handed to `checkIfDue`.
    func check(then done: @escaping (Release?) -> Void) {
        guard !checking else { return }
        checking = true
        checkFailed = false
        let fetchRelease = self.fetchRelease
        Task { [weak self] in
            let found: Release
            do { found = try await fetchRelease() }
            catch {
                guard let self else { return }
                checking = false
                checkFailed = true
                // Keep both the last successful check and any release already
                // offered. A failed request must not erase an available update.
                say?(L10n.text("Updater.checkFailed"))
                done(nil)
                return
            }
            guard let self else { return }
            checking = false
            let checked = Date()
            lastChecked = checked
            Store.settings.set(checked, forKey: lastKey)
            guard (Updater.overridden ? found.build > currentBuild : (try? ExtensionVersion.isNewer(found.version, than: currentVersion)) == true), found.runsHere else {
                // A build already swapped in stays ready whatever the feed
                // says now.
                if case .ready = stage {} else { stage = .none }
                done(nil)
                return
            }
            done(found)
            if !Updater.overridden { stage = .offered(found); say?(L10n.text("Updater.1140", found.version)); return }
            guard !installsOnItsOwn else { take(found); return }
            switch stage {
            case .fetching, .ready: break
            case .waiting(let known) where known == found: break
            case .none, .offered, .waiting:
                stage = .waiting(found)
                say?(L10n.text("Updater.1135", String(describing: found.version)))
            }
        }
    }

    /// The disk image, when the bundle can't be swapped where it is: fetched
    /// by Search itself, never through a web page, and opened only if its
    /// hash is the signed feed's and its signature is Office Commun's.
    @Published private(set) var fetchingDisk = false
    /// What a test run decided about a disk image, for the bench.
    static var diskVerdict = ""

    func openDisk() {
        guard case .offered(let release) = stage, !fetchingDisk else { return }
        if !Updater.overridden { NSWorkspace.shared.open(release.dmg); return }
        fetchingDisk = true
        say?(L10n.text("Updater.1136", String(describing: release.version)))
        Task.detached(priority: .utility) {
            let result: Result<URL, Error>
            do { result = .success(try await Swap.disk(release)) } catch { result = .failure(error) }
            await MainActor.run { [weak self] in
                guard let self else { return }
                fetchingDisk = false
                switch result {
                case .success(let dmg):
                    if Store.testing { Updater.diskVerdict = "verified" } else { NSWorkspace.shared.open(dmg) }
                case .failure(let error):
                    Updater.diskVerdict = "refused: \(error)"
                    say?(L10n.text("Updater.1137"))
                }
            }
        }
    }

    /// Install, because somebody pressed it: the same fetch, checks and swap
    /// as on its own.
    func install() {
        guard case .waiting(let release) = stage else { return }
        take(release)
    }

    /// Fetch it, check it, swap it in — unless one is already on its way,
    /// or one is already in place. A second swap in the same run would pull
    /// the bundle this process is running from out from under it, so the
    /// next launch takes the next one.
    private func take(_ release: Release) {
        switch stage {
        case .fetching, .ready: return
        case .none, .offered, .waiting: break
        }
        stage = .fetching(release)
        say?(L10n.text("Updater.1138", String(describing: release.version)))
        Task.detached(priority: .utility) {
            let worked: Bool
            do {
                try await Swap.install(release)
                worked = true
            } catch {
                worked = false
            }
            await MainActor.run { [weak self] in self?.landed(release, worked: worked) }
        }
    }

    private func landed(_ release: Release, worked: Bool) {
        guard case .fetching(let fetching) = stage, fetching == release else { return }
        stage = worked ? .ready(release) : .offered(release)
        say?(worked
            ? L10n.text("Updater.1139", String(describing: release.version))
            : L10n.text("Updater.1140", String(describing: release.version)))
    }

    /// Quit, and come back as the new one. A shell waits for this process
    /// to be gone before asking macOS to open the bundle again — `open` on a
    /// running app only brings it forward. Quitting goes through NSApp so
    /// everything that is written on the way out is written, the same as ⌘Q.
    func relaunch(arguments: [String] = []) {
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = [
            "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; shift; exec \"$@\"",
            "sh", String(ProcessInfo.processInfo.processIdentifier),
        ] + Updater.reopen(arguments: arguments)
        do { try waiter.run(); NSApp.terminate(nil) }
        catch { NSSound.beep() }
    }

    /// `open` and what to give it: the bundle, and — for a test run — the
    /// variables that made it a test run, since `open` starts from a fresh
    /// environment and a relaunch must not land on the real data.
    static func reopen(arguments: [String] = []) -> [String] {
        var command = ["/usr/bin/open"]
        for key in ["SEARCH_PROBE", "SEARCH_FEED"] {
            if let value = ProcessInfo.processInfo.environment[key] {
                command += ["--env", "\(key)=\(value)"]
            }
        }
        return command + [Bundle.main.bundleURL.path] + (arguments.isEmpty ? [] : ["--args"] + arguments)
    }

    static func fetch() async throws -> Release {
        if !overridden {
            guard let data = await get(feed, limit: 1 << 20),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
                  let tag = json["tag_name"] as? String,
                  let page = json["html_url"] as? String, let releaseURL = URL(string: page),
                  releaseURL.host == "github.com", releaseURL.path.hasPrefix("/small32/SearcheXtra/releases/"),
                  let assets = json["assets"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
            #if arch(x86_64)
            let suffix = "-x86_64.zip"
            #else
            let suffix = "-arm64.zip"
            #endif
            guard let asset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(suffix) == true }),
                  let text = asset["browser_download_url"] as? String, let archive = URL(string: text),
                  archive.scheme == "https", archive.host == "github.com",
                  archive.path.hasPrefix("/small32/SearcheXtra/releases/download/") else { throw URLError(.cannotParseResponse) }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            _ = try ExtensionVersion.isNewer(version, than: "0")
            return Release(version: version, build: 0,
                           archive: archive, dmg: releaseURL, sha256: nil,
                           notes: json["body"] as? String, minimumSystemVersion: "14.0")
        }
        // The feed as Office Commun signed it: appcast.json.zip, next to the
        // plain one older builds read, holding the same file with its code
        // signature (build.sh). Only what comes out of it, checked, is read:
        // a feed a server or a hijacked answer made up is no feed at all.
        guard let packed = await get(feed.appendingPathExtension("zip"), limit: 1 << 20),
              let data = await Task.detached(priority: .utility, operation: { Updater.opened(packed) }).value,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String,
              let build = (json["build"] as? Int) ?? Int(json["build"] as? String ?? ""),
              let archive = link(json["url"]),
              let dmg = link(json["dmg"])
        else { throw URLError(.cannotParseResponse) }
        let sha = (json["sha256"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let dmgSha = (json["dmgSha256"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let notes = (json["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var release = Release(
            version: version,
            build: build,
            archive: archive,
            dmg: dmg,
            sha256: sha.flatMap { $0.isEmpty ? nil : $0 },
            notes: notes.flatMap { $0.isEmpty ? nil : $0 },
            minimumSystemVersion: json["minimumSystemVersion"] as? String
        )
        release.dmgSha256 = dmgSha.flatMap { $0.isEmpty ? nil : $0 }
        return release
    }

    private static func get(_ url: URL, limit: Int) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("SearcheXtra/" + version, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              data.count <= limit
        else { return nil }
        return data
    }

    /// The team that signs Search's releases, and with them its feed.
    nonisolated static let team = "7BYKA895MC"
    nonisolated static let feedIdentifier = "com.officecommun.search.appcast"

    /// The feed inside `packed`, if it is Office Commun's: appcast.json with
    /// a code signature (codesign keeps it in the file's extended attributes,
    /// and ditto carries those in the ZIP) that holds up and meets the
    /// Developer ID requirement for the team and the feed's own identifier.
    /// No new key to keep: the one that signs the app signs its feed.
    nonisolated static func opened(_ packed: Data) -> Data? {
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent("search-feed-\(UUID().uuidString)", isDirectory: true)
        guard (try? files.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return nil }
        defer { try? files.removeItem(at: folder) }
        let zip = folder.appendingPathComponent("appcast.json.zip")
        let out = folder.appendingPathComponent("out", isDirectory: true)
        guard (try? packed.write(to: zip)) != nil, (try? Swap.unzip(zip, into: out)) != nil else { return nil }
        let file = out.appendingPathComponent("appcast.json")
        // The file itself, not a link to one somewhere else.
        guard let kind = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              kind.isRegularFile == true, kind.isSymbolicLink != true,
              let data = try? Data(contentsOf: file), data.count <= 1 << 20
        else { return nil }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(file as CFURL, [], &code) == errSecSuccess, let code,
              let requirement = Swap.developerID(team: team, identifier: feedIdentifier),
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
        else { return nil }
        return data
    }

    /// An address from the feed: https, unless the feed itself was pointed
    /// at a test server, and on the feed's own host. The ZIP is checked
    /// again by hash and signature before it is ever run, but the DMG is
    /// only ever offered, under the app's own "is out" line - so a feed
    /// that a compromised host or a hijacked DNS answer could redirect must
    /// not be able to point that line at some other address.
    private static func link(_ value: Any?) -> URL? {
        guard let url = (value as? String).flatMap(URL.init(string:)) else { return nil }
        guard url.scheme == "https" || (overridden && url.scheme == "http") else { return nil }
        guard url.host == feed.host else { return nil }
        return url
    }
}

/// The part that touches the disk, off the main thread. Every step checks
/// before anything changes, and the only two things ever removed are the
/// scratch folder it made and the `.old` bundle it set aside.
private enum Swap {
    enum Refused: Error {
        case unsignedHere, readOnly, download, hash, archive, plist, wrongApp, notNewer, unsigned, wrongTeam, move
    }

    /// Where the bundle lives, and so where the new one goes.
    static var target: URL { Bundle.main.bundleURL }

    /// The bundle set aside during a swap: a sibling, so the move is a rename
    /// on the same volume and not a copy.
    static var aside: URL {
        target.deletingLastPathComponent().appendingPathComponent(target.lastPathComponent + ".old")
    }

    static func install(_ release: Updater.Release) async throws {
        let files = FileManager.default
        // No Team ID on this build means it was signed ad hoc — a development
        // build. Nothing is ever swapped in under an app that could not be
        // told apart from anything else.
        guard let team = teamID(of: target) else { throw Refused.unsignedHere }
        // The folder the app is in has to take a rename, or nothing here can
        // be done: /Applications owned by another account, a disk image.
        guard files.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            throw Refused.readOnly
        }

        // A scratch folder on the same volume as the app, so the last move is
        // a rename too. Cleared whatever happens.
        let scratch = (try? files.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true
        )) ?? files.temporaryDirectory.appendingPathComponent("search-update-\(release.build)", isDirectory: true)
        try files.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: scratch) }

        let zip = scratch.appendingPathComponent("SearcheXtra.zip")
        try await download(release.archive, to: zip)
        // A feed with no checksum is refused as a wrong one would be: build.sh
        // always writes it, so one missing is a feed that isn't ours.
        guard let expected = release.sha256, try digest(of: zip) == expected else { throw Refused.hash }
        let unpacked = scratch.appendingPathComponent("unpacked", isDirectory: true)
        try extract(zip, into: unpacked)
        guard let fresh = try files.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        else { throw Refused.archive }
        try verify(fresh, team: team)
        try swap(fresh)
    }

    static func download(_ url: URL, to file: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue("SearcheXtra/" + Updater.version, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        let (got, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
            throw Refused.download
        }
        // The session's copy lasts only until this returns.
        try FileManager.default.moveItem(at: got, to: file)
    }

    static func digest(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var sha = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            sha.update(data: chunk)
        }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// ditto, the way Archive Utility does it: permissions kept. Quarantine
    /// never comes into it — the app declares no LSFileQuarantineEnabled, so
    /// nothing it downloads carries the flag, and there is none to strip.
    /// Keep it that way: the checking is done here, in verify, not by
    /// Gatekeeper at the next launch.
    static func unzip(_ zip: URL, into folder: URL) throws { try extract(zip, into: folder) }

    private static func extract(_ zip: URL, into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, folder.path]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = FileHandle.nullDevice
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw Refused.archive }
    }

    /// A bundle is not trusted because it arrived. It is trusted because it
    /// is this app, newer, with a signature that holds up under the strict
    /// check for every architecture and meets Developer ID's requirement:
    /// a certificate chain that ends at Apple's root, through Apple's
    /// Developer ID authority, issued to the same team as the one running.
    /// A Team ID read from the signature alone is only what the certificate
    /// says, and anyone can make a certificate that says it.
    private static func verify(_ bundle: URL, team: String) throws {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw Refused.plist }
        guard info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw Refused.wrongApp
        }
        guard Int(info["CFBundleVersion"] as? String ?? "") ?? 0 > Updater.build else {
            throw Refused.notNewer
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else {
            throw Refused.unsigned
        }
        guard let identifier = Bundle.main.bundleIdentifier, let requirement = developerID(team: team, identifier: identifier)
        else { throw Refused.unsigned }
        let strict = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, strict, requirement) == errSecSuccess else { throw Refused.unsigned }
        guard teamID(of: bundle) == team else { throw Refused.wrongTeam }
    }

    /// The requirement every Developer ID app from this team meets, the one
    /// `codesign -d -r-` prints for a shipped Search: Apple's anchor, the
    /// Developer ID intermediate (…6.2.6) and a Developer ID Application
    /// leaf (…6.1.13), with this team in it, for this bundle id.
    /// The disk image, fetched, checked against the signed feed's hash and
    /// against Developer ID for the team. Its name is the build's own.
    static func disk(_ release: Updater.Release) async throws -> URL {
        guard let expected = release.dmgSha256 else { throw Refused.hash }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("search-disk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dmg = folder.appendingPathComponent("SearcheXtra \(release.version).dmg")
        try await download(release.dmg, to: dmg)
        guard try digest(of: dmg) == expected else { throw Refused.hash }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(dmg as CFURL, [], &code) == errSecSuccess, let code,
              let requirement = developerID(team: Updater.team, identifier: nil),
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
        else { throw Refused.unsigned }
        return dmg
    }

    static func developerID(team: String, identifier: String?) -> SecRequirement? {
        let text = "anchor apple generic" + (identifier.map { " and identifier \"\($0)\"" } ?? "")
            + " and certificate 1[field.1.2.840.113635.100.6.2.6]"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13]"
            + " and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    /// The team that signed a bundle, as the system reads it — nil for an
    /// ad-hoc signature, or none.
    private static func teamID(of bundle: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else {
            return nil
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess,
              let signing = info as? [String: Any]
        else { return nil }
        return signing[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Two renames, and the first one undone if the second fails. The app
    /// that is running keeps its files: the kernel follows the rename, so it
    /// goes on running from `.old` — and validating as itself, which is what
    /// its keychain items are checked against — until it quits.
    private static func swap(_ fresh: URL) throws {
        let files = FileManager.default
        sweep()
        guard !files.fileExists(atPath: aside.path) else { throw Refused.move }
        try files.moveItem(at: target, to: aside)
        do {
            try files.moveItem(at: fresh, to: target)
        } catch {
            try? files.moveItem(at: aside, to: target)
            throw Refused.move
        }
    }

    /// Removes the bundle a swap set aside, once nothing runs from it any
    /// more: at quit, and at the next launch in case the quit was not a
    /// clean one. Only ever a `.old` that is this app; nothing else is ever
    /// deleted here.
    static func sweep() {
        let plist = aside.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier
        else { return }
        try? FileManager.default.removeItem(at: aside)
    }
}
