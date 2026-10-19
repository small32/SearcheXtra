import AppKit
import CoreFoundation
import WebKit

/// Chrome's USER_SCRIPT world is neither a content-script world nor the
/// website's world. Keep it separate from both: ScriptCat creates functions
/// dynamically, and they must see the same small runtime as its bootstrap.
@available(macOS 15.4, *)
@MainActor
enum ExtensionUserScripts {
    private struct Registration {
        let context: WKWebExtensionContext
        var scripts: [[String: Any]]
        var worlds: [[String: Any]]
        let generation = UUID().uuidString
        var contentWorlds: [String: WKContentWorld] = [:]
        var host: Host?
        var compiled: [CompiledScript]?
    }
    private struct CompiledScript {
        let source: String
        let worldID: String?
        let atStart: Bool
        let mainFrameOnly: Bool
    }
    private final class Page {
        weak var tab: Tab?
        var handlers: [String: (String, WKContentWorld)] = [:]
        let discovery = "userScriptFrames_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var frames: [String: Frame] = [:]
        var mainDocument: String?
        init(_ tab: Tab) { self.tab = tab }
    }
    private struct Frame {
        let document: String
        let info: WKFrameInfo
        let url: URL
    }
    private struct TargetFrame {
        let frame: Frame
        let frameID: Int
        let documentID: String
        let url: URL
        let marker: String
    }
    private static var registrations: [String: Registration] = [:]
    private static var pages: [ObjectIdentifier: Page] = [:]
    private static var observers: [NSObjectProtocol] = []
    nonisolated static let hostPath = "_search/user-script-host.html"

    static func loaded(_ context: WKWebExtensionContext) {
        let id = context.uniqueIdentifier
        guard Extensions.declaresUserScripts(context.webExtension.manifest), Extensions.userScriptsAllowed(id) else { return }
        let directory = Extensions.folder(for: id).appendingPathComponent("_search")
        func read(_ name: String) -> [[String: Any]] {
            (try? JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent(name)))) as? [[String: Any]] ?? []
        }
        let worlds = read("worlds.json")
        let invalidWorlds = Set(worlds.filter { (try? validateWorld($0)) == nil }.map { $0["worldId"] as? String ?? "" })
        let scripts = read("userscripts.json").filter { script in
            !invalidWorlds.contains(script["worldId"] as? String ?? "") && (try? validate(script, folder: Extensions.folder(for: id))) != nil
        }
        if !invalidWorlds.isEmpty { Extensions.shared.noteError("An unsupported user-script content security policy was not loaded", for: id) }
        registrations[id] = Registration(context: context, scripts: scripts, worlds: worlds.filter { !invalidWorlds.contains($0["worldId"] as? String ?? "") })
        if observers.isEmpty {
            for name in [WKWebExtensionContext.permissionMatchPatternsWereGrantedNotification,
                         WKWebExtensionContext.permissionMatchPatternsWereDeniedNotification,
                         WKWebExtensionContext.grantedPermissionMatchPatternsWereRemovedNotification,
                         WKWebExtensionContext.deniedPermissionMatchPatternsWereRemovedNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                    MainActor.assumeIsolated {
                        guard let context = note.object as? WKWebExtensionContext,
                              var registration = registrations[context.uniqueIdentifier], registration.context === context else { return }
                        registration.compiled = nil
                        registrations[context.uniqueIdentifier] = registration
                        refresh()
                    }
                })
            }
        }
        refresh()
    }

    static func unloaded(_ id: String) {
        registrations.removeValue(forKey: id)?.host?.close()
        if registrations.isEmpty {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }
        refresh()
    }

    /// Native resource-folder reloads start a new installation of user
    /// scripts and worlds. Extension storage, including GM values, is kept.
    static func reset(_ id: String) throws {
        try persist([], name: "userscripts.json", id: id)
        try persist([], name: "worlds.json", id: id)
    }

    static func discard(_ web: WKWebView) {
        let controller = web.configuration.userContentController
        if let page = pages.removeValue(forKey: ObjectIdentifier(controller)) {
            for (name, world) in page.handlers.values { controller.removeScriptMessageHandler(forName: name, contentWorld: world) }
            controller.removeScriptMessageHandler(forName: page.discovery, contentWorld: Web.world)
        }
        for registration in registrations.values { registration.host?.discard(web) }
    }

    private static func refresh() {
        pages = pages.filter { $0.value.tab?.built != nil }
        for page in Array(pages.values) { page.tab?.refreshUserScripts() }
    }

    /// Called after Tab replaces its own user scripts. Register handlers in
    /// exactly the world that owns the script; no DOM event or page-global
    /// channel lends a website access to its extension's message transport.
    static func arm(_ tab: Tab, controller: WKUserContentController) {
        let key = ObjectIdentifier(controller)
        let page: Page
        if let found = pages[key] { page = found }
        else {
            page = Page(tab)
            controller.addScriptMessageHandler(FrameDiscovery(page: page), contentWorld: Web.world, name: page.discovery)
        }
        pages[key] = page
        let permitted = registrations.keys.sorted().filter { id in
            registrations[id].map { !tab.shy || $0.context.hasAccessToPrivateData } == true
        }
        var retained = Set<String>()
        controller.addUserScript(WKUserScript(source: discovery(channel: page.discovery), injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Web.world))
        for id in permitted {
            guard var registration = registrations[id], !tab.shy || registration.context.hasAccessToPrivateData else { continue }
            let scripts = registration.scripts
            let worldIDs = Set([""] + registration.worlds.map { $0["worldId"] as? String ?? "" } + scripts.filter { ($0["world"] as? String) != "MAIN" }.map { $0["worldId"] as? String ?? "" }).union(registration.contentWorlds.keys)
            for worldID in worldIDs {
                let world = registration.contentWorlds[worldID] ?? .world(name: "SearcheXtra.userScripts.\(id).\(registration.generation).\(worldID)")
                registration.contentWorlds[worldID] = world
                let handlerKey = id + ":" + worldID
                retained.insert(handlerKey)
                let channel = page.handlers[handlerKey]?.0 ?? ("userScripts_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""))
                if page.handlers[handlerKey] == nil {
                    controller.addScriptMessageHandler(FrameBridge(context: registration.context, generation: registration.generation, worldID: worldID, world: world, tab: tab), contentWorld: world, name: channel)
                    page.handlers[handlerKey] = (channel, world)
                }
                let properties = registration.worlds.first { ($0["worldId"] as? String ?? "") == worldID } ?? [:]
                if scripts.contains(where: { ($0["world"] as? String) != "MAIN" && ($0["worldId"] as? String ?? "") == worldID }) {
                    controller.addUserScript(WKUserScript(source: bootstrap(id: id, channel: channel, messaging: properties["messaging"] as? Bool == true),
                                                           injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world))
                }
            }
            if registration.compiled == nil {
                let granted = registration.context.currentPermissionMatchPatterns.map(\.string)
                let denied = Array(registration.context.deniedPermissionMatchPatterns.keys).map(\.string)
                registration.compiled = scripts.compactMap { script in
                    do {
                        return CompiledScript(source: try compiled(script, folder: Extensions.folder(for: id), granted: granted, denied: denied),
                                              worldID: (script["world"] as? String) == "MAIN" ? nil : script["worldId"] as? String ?? "",
                                              atStart: (script["runAt"] as? String) == "document_start", mainFrameOnly: script["allFrames"] as? Bool != true)
                    } catch { Extensions.shared.noteError(error.localizedDescription, for: id); return nil }
                }
            }
            registrations[id] = registration
            for script in registration.compiled ?? [] {
                let world = script.worldID.flatMap { registration.contentWorlds[$0] } ?? .page
                controller.addUserScript(WKUserScript(source: script.source, injectionTime: script.atStart ? .atDocumentStart : .atDocumentEnd,
                                                       forMainFrameOnly: script.mainFrameOnly, in: world))
            }
        }
        for (key, (name, world)) in page.handlers where !retained.contains(key) {
            controller.removeScriptMessageHandler(forName: name, contentWorld: world)
            page.handlers[key] = nil
        }
    }

    static func call(_ api: String, args: [Any], context: WKWebExtensionContext) async throws -> Any? {
        let id = context.uniqueIdentifier
        guard var registration = registrations[id], registration.context === context, Extensions.userScriptsAllowed(id) else {
            throw ExtensionShims.Unsupported(what: L10n.text("extensions.userScripts.disabled"))
        }
        let first = args.first
        func selected(_ scripts: [[String: Any]]) -> [[String: Any]] {
            guard let ids = (first as? [String: Any])?["ids"] as? [String] else { return scripts }
            return scripts.filter { ids.contains($0["id"] as? String ?? "") }
        }
        switch api {
        case "userScripts.list": return selected(registration.scripts)
        case "userScripts.worlds": return registration.worlds
        case "userScripts.register", "userScripts.update":
            guard let input = first as? [[String: Any]], !input.isEmpty else { throw invalid("Expected a nonempty script list") }
            var scripts = registration.scripts
            var seen = Set<String>()
            for proposed in input {
                guard let key = proposed["id"] as? String, !key.isEmpty, !key.hasPrefix("_"), seen.insert(key).inserted else { throw invalid("Invalid or duplicate script id") }
                let position = scripts.firstIndex { ($0["id"] as? String) == key }
                if api == "userScripts.register" {
                    guard position == nil else { throw invalid("Duplicate script id '\(key)'") }
                    try validate(proposed, folder: Extensions.folder(for: id))
                    scripts.append(proposed)
                } else {
                    guard let position else { throw invalid("Script with id '\(key)' does not exist") }
                    let merged = scripts[position].merging(proposed) { _, next in next }
                    try validate(merged, folder: Extensions.folder(for: id))
                    scripts[position] = merged
                }
            }
            try persist(scripts, name: "userscripts.json", id: id)
            registration.scripts = scripts
        case "userScripts.unregister":
            let removed = Set(selected(registration.scripts).compactMap { $0["id"] as? String })
            registration.scripts.removeAll { removed.contains($0["id"] as? String ?? "") }
            try persist(registration.scripts, name: "userscripts.json", id: id)
        case "userScripts.world":
            let properties = first as? [String: Any] ?? [:]
            guard properties["worldId"] == nil || properties["worldId"] is String else { throw invalid("Invalid world id") }
            let worldID = properties["worldId"] as? String ?? ""
            guard worldID.utf8.count <= 256, !worldID.hasPrefix("_") else { throw invalid("Invalid world id") }
            var worlds = registration.worlds
            if properties["reset"] as? Bool == true {
                worlds.removeAll { ($0["worldId"] as? String ?? "") == worldID }
            } else {
                let old = worlds.first { ($0["worldId"] as? String ?? "") == worldID } ?? [:]
                let merged = old.merging(properties) { _, next in next }
                try validateWorld(merged)
                worlds.removeAll { ($0["worldId"] as? String ?? "") == worldID }
                worlds.append(merged)
            }
            try persist(worlds, name: "worlds.json", id: id)
            registration.worlds = worlds
        default: throw invalid("Unknown userScripts method")
        }
        registration.compiled = nil
        registrations[id] = registration
        refresh()
        return nil
    }

    static func execute(_ injection: [String: Any], tab: Tab, context: WKWebExtensionContext) async throws -> Any {
        let id = context.uniqueIdentifier
        guard var registration = registrations[id], registration.context === context, Extensions.userScriptsAllowed(id),
              let view = tab.built,
              !tab.shy || context.hasAccessToPrivateData else { throw invalid("User-script context is not authorized") }
        let target = injection["target"] as? [String: Any] ?? [:]
        try validateTarget(target)
        let requestedWorld = injection["world"] as? String ?? "USER_SCRIPT"
        guard injection["world"] == nil || injection["world"] is String,
              ["MAIN", "USER_SCRIPT"].contains(requestedWorld) else { throw invalid("Invalid user-script execution world") }
        if let immediately = injection["injectImmediately"], !isBoolean(immediately) { throw invalid("Invalid injectImmediately value") }
        let main = requestedWorld == "MAIN"
        let worldID = injection["worldId"] as? String ?? ""
        var script: [String: Any] = ["id": "execute", "matches": ["<all_urls>"], "js": injection["js"] ?? [],
                                   "world": main ? "MAIN" : "USER_SCRIPT", "runAt": "document_start"]
        if injection["worldId"] != nil { script["worldId"] = injection["worldId"] }
        try validate(script, folder: Extensions.folder(for: id))
        let world: WKContentWorld
        var prefix = ""
        if main { world = .page }
        else {
            world = registration.contentWorlds[worldID] ?? .world(name: "SearcheXtra.userScripts.\(id).\(registration.generation).\(worldID)")
            registration.contentWorlds[worldID] = world
            registrations[id] = registration
            tab.refreshUserScripts()
            let page = pages[ObjectIdentifier(view.configuration.userContentController)]
            guard let channel = page?.handlers[id + ":" + worldID]?.0 else { throw invalid("User-script bridge is unavailable") }
            let properties = registration.worlds.first { ($0["worldId"] as? String ?? "") == worldID } ?? [:]
            prefix = bootstrap(id: id, channel: channel, messaging: properties["messaging"] as? Bool == true)
        }
        let host = try ExtensionUserScripts.host(for: id)
        let targets = try await host.targets(target, tab: tab)
        defer { host.clearTargets(targets, in: view) }
        let source = try code(script, folder: Extensions.folder(for: id))
        var results: [[String: Any]] = []
        for selected in targets {
            var result: [String: Any] = ["frameId": selected.frameID, "documentId": selected.documentID]
            do {
                guard tab.built === view, registrations[id]?.context === context,
                      registrations[id]?.generation == registration.generation, Extensions.userScriptsAllowed(id),
                      !tab.shy || context.hasAccessToPrivateData,
                      let permitted = permissionURL(selected.url, frame: selected.frame.info),
                      context.hasAccess(to: permitted, in: Extensions.shared.adapter(for: tab)) else { throw invalid("User-script frame access was revoked") }
                // Checking the per-document marker in the very evaluation
                // that runs the code prevents a navigation between lookup
                // and dispatch from injecting into a replacement document.
                let guardDocument = "if (location.href !== \(json(selected.url.absoluteString)) || document.documentElement?.getAttribute(\(json(selected.marker))) !== \(json(selected.frame.document))) throw new Error('The user-script document changed');\n"
                let value: Any?
                if main {
                    // Native page-world injection continues to obey the
                    // page's own dynamic-evaluation rules.
                    value = try await view.evaluateJavaScript(guardDocument + source, in: selected.frame.info, contentWorld: world)
                } else {
                    let identity = try await view.callAsyncJavaScript(guardDocument + prefix + "\nreturn globalThis.__searchUserWorldDocument;", in: selected.frame.info, contentWorld: world)
                    guard let document = identity as? String,
                          registrations[id]?.generation == registration.generation else { throw invalid("The user-script document was replaced") }
                    // Eval is explicitly available in the USER_SCRIPT
                    // policies accepted above. Its completion value and a
                    // returned promise become the API's injection result.
                    // The world-local identity is invisible to websites and
                    // rejects a new document even if it copies a DOM marker.
                    value = try await view.callAsyncJavaScript(guardDocument + "if (globalThis.__searchUserWorldDocument !== expectedDocument) throw new Error('The user-script document changed'); return await (0, eval)(source);",
                                                              arguments: ["source": source, "expectedDocument": document], in: selected.frame.info, contentWorld: world)
                }
                result["result"] = value ?? NSNull()
            } catch { result["error"] = error.localizedDescription }
            results.append(result)
        }
        return results
    }

    static func validateTarget(_ target: [String: Any]) throws {
        guard integer(target["tabId"]) != nil else { throw invalid("A user-script target needs a numeric tab identifier") }
        let hasFrames = target["frameIds"] != nil, hasDocuments = target["documentIds"] != nil
        if let all = target["allFrames"], !isBoolean(all) { throw invalid("Invalid allFrames value") }
        guard !(hasFrames && hasDocuments), !(target["allFrames"] as? Bool == true && (hasFrames || hasDocuments)) else {
            throw invalid("Specify only one of allFrames, frameIds or documentIds")
        }
        if hasFrames {
            guard let frames = target["frameIds"] as? [Any], !frames.isEmpty,
                  frames.allSatisfy({ integer($0).map { $0 >= 0 } == true }) else { throw invalid("Invalid frame identifiers") }
        }
        if hasDocuments {
            guard let documents = target["documentIds"] as? [String], !documents.isEmpty,
                  documents.allSatisfy({ UUID(uuidString: $0) != nil }) else { throw invalid("Invalid document identifiers") }
        }
    }

    private static func invalid(_ message: String) -> ExtensionShims.Unsupported { .init(what: message) }
    private static func permissionURL(_ url: URL, frame: WKFrameInfo) -> URL? {
        let scheme = url.scheme?.lowercased() ?? ""
        if ["http", "https", "file", "ftp"].contains(scheme) { return url }
        // about:blank / srcdoc and blob documents can inherit a website's
        // origin. Use WebKit's native security origin, never a parent URL
        // or an origin supplied by page/user-script JavaScript.
        guard ["about:blank", "about:srcdoc"].contains(url.absoluteString) || scheme == "blob" else { return nil }
        let origin = frame.securityOrigin
        guard ["http", "https", "file", "ftp"].contains(origin.protocol.lowercased()) else { return nil }
        var parts = URLComponents()
        parts.scheme = origin.protocol; parts.host = origin.host; parts.path = "/"
        if origin.port > 0 { parts.port = origin.port }
        return parts.url
    }
    private static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
    private static func integer(_ value: Any?) -> Int? {
        guard let value, !isBoolean(value), let number = value as? NSNumber else { return nil }
        return Int(exactly: number.doubleValue)
    }
    private static func persist(_ list: [[String: Any]], name: String, id: String) throws {
        let directory = Extensions.folder(for: id).appendingPathComponent("_search")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: list).write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    static func validateWorld(_ properties: [String: Any]) throws {
        if let id = properties["worldId"] {
            guard let text = id as? String, text.utf8.count <= 256, !text.hasPrefix("_") else { throw invalid("Invalid world id") }
        }
        if let messaging = properties["messaging"], !isBoolean(messaging) { throw invalid("Invalid messaging value") }
        if let csp = properties["csp"], !(csp is String) { throw invalid("Invalid user-script content security policy") }
        guard let csp = properties["csp"] as? String, !csp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let directives = csp.lowercased().split(separator: ";").map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }.filter { !$0.isEmpty }
        guard directives.count == 1, directives[0].first == "script-src" else { throw invalid("This user-script content security policy is not supported") }
        let tokens = Set(directives[0].dropFirst())
        let ordinary: Set<String> = ["'self'", "'unsafe-eval'"]
        let scriptCat: Set<String> = ["'self'", "'unsafe-inline'", "'unsafe-eval'", "*"]
        guard tokens == ordinary || tokens == scriptCat else { throw invalid("This user-script content security policy is not supported") }
    }

    static func validate(_ script: [String: Any], folder: URL) throws {
        guard let matches = script["matches"] as? [String], !matches.isEmpty else { throw invalid("Missing script match patterns") }
        for pattern in matches + (script["excludeMatches"] as? [String] ?? []) { _ = try WKWebExtension.MatchPattern(string: pattern) }
        guard ["MAIN", "USER_SCRIPT"].contains(script["world"] as? String ?? "USER_SCRIPT"),
              ["document_start", "document_end", "document_idle"].contains(script["runAt"] as? String ?? "document_idle"),
              let sources = script["js"] as? [[String: Any]], !sources.isEmpty else { throw invalid("Invalid user script") }
        let worldID = script["worldId"] as? String ?? ""
        guard script["worldId"] == nil || script["worldId"] is String,
              worldID.utf8.count <= 256, !worldID.hasPrefix("_"),
              (script["world"] as? String) != "MAIN" || script["worldId"] == nil else { throw invalid("Invalid user-script world") }
        _ = try code(script, folder: folder)
    }

    private static func code(_ script: [String: Any], folder: URL) throws -> String {
        try (script["js"] as? [[String: Any]] ?? []).map { source -> String in
            if let text = source["code"] as? String, source["file"] == nil { return text }
            guard source["code"] == nil, let file = source["file"] as? String else { throw invalid("A script source needs code or a file") }
            let root = folder.resolvingSymlinksInPath().standardizedFileURL
            let path = folder.appendingPathComponent(file).resolvingSymlinksInPath().standardizedFileURL
            guard path.path.hasPrefix(root.path + "/") else { throw invalid("Script file is outside its extension") }
            return try String(contentsOf: path, encoding: .utf8)
        }.joined(separator: "\n;\n")
    }

    private static func json(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    static func compiled(_ script: [String: Any], folder: URL, granted: [String], denied: [String] = []) throws -> String {
        let matching: [String: Any] = ["matches": script["matches"] ?? [], "excludeMatches": script["excludeMatches"] ?? [],
                                     "includeGlobs": script["includeGlobs"] ?? [], "excludeGlobs": script["excludeGlobs"] ?? [],
                                     "granted": granted, "denied": denied]
        let source = try code(script, folder: folder)
        // Idle scripts wait until load settles; document_end scripts run at
        // WebKit's document-end injection point without the extra task.
        let idle = (script["runAt"] as? String ?? "document_idle") == "document_idle"
        return #"""
        (() => {
          const rules = \#(json(matching)), href = location.href;
          const glob = value => new RegExp('^' + value.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.') + '$');
          const pathPattern = value => new RegExp('^' + value.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$');
          const match = value => {
            const url = new URL(href);
            if (!['http:', 'https:', 'file:', 'ftp:'].includes(url.protocol)) return false;
            if (value === '<all_urls>') return true;
            const parts = /^(\*|https?|file|ftp):\/\/([^/]*)(\/.*)$/.exec(value);
            if (!parts || (parts[1] === '*' ? !['http:', 'https:'].includes(url.protocol) : parts[1] + ':' !== url.protocol)) return false;
            const host = parts[2].toLowerCase();
            if (host !== '*' && host !== url.host.toLowerCase() && host !== url.hostname.toLowerCase()
              && !(host.startsWith('*.') && (url.hostname === host.slice(2) || url.hostname.endsWith('.' + host.slice(2))))) return false;
            return pathPattern(parts[3]).test(url.pathname + url.search);
          };
          if (!rules.granted.some(match) || rules.denied.some(match) || !rules.matches.some(match)
            || rules.excludeMatches.some(match) || (rules.includeGlobs.length && !rules.includeGlobs.some(g => glob(g).test(href)))
            || rules.excludeGlobs.some(g => glob(g).test(href))) return;
          const run = () => {
        \#(source)
          };
          \#(idle ? "if (document.readyState === 'complete') setTimeout(run, 0); else addEventListener('load', () => setTimeout(run, 0), { once: true });" : "run();")
        })();
        """#
    }

    static func discovery(channel: String) -> String {
        #"""
        (() => {
          if (typeof globalThis.__searchDiscoverFrame === 'function') { void __searchDiscoverFrame(); return; }
          const documentId = typeof crypto.randomUUID === 'function' ? crypto.randomUUID()
            : [...crypto.getRandomValues(new Uint32Array(4))].map(n => n.toString(16).padStart(8, '0')).join('');
          Object.defineProperty(globalThis, '__searchFrameDocument', { value: documentId });
          const post = webkit.messageHandlers[\#(json(channel))].postMessage.bind(webkit.messageHandlers[\#(json(channel))]);
          Object.defineProperty(globalThis, '__searchDiscoverFrame', { value: () => post({ phase: 'hello', documentId }) });
          addEventListener('pagehide', () => { void post({ phase: 'goodbye', documentId }); });
          addEventListener('pageshow', event => { if (event.persisted) void __searchDiscoverFrame(); });
          void __searchDiscoverFrame();
        })();
        """#
    }

    private final class FrameDiscovery: NSObject, WKScriptMessageHandlerWithReply {
        weak var page: Page?
        init(page: Page) { self.page = page }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            guard let page, let tab = page.tab, tab.built === message.webView,
                  let body = message.body as? [String: Any], let document = body["documentId"] as? String,
                  !document.isEmpty, document.count <= 128 else { return replyHandler(nil, "The browser frame was closed") }
            if body["phase"] as? String == "goodbye" { page.frames[document] = nil }
            else if body["phase"] as? String == "hello", let url = message.frameInfo.request.url {
                if message.frameInfo.isMainFrame {
                    if let previous = page.mainDocument, previous != document, let view = message.webView {
                        for registration in registrations.values { registration.host?.discard(view) }
                    }
                    page.mainDocument = document
                    // Keep child pageshow deliveries even if WebKit reports
                    // a restored child's lifecycle before its parent's.
                    page.frames = page.frames.filter { !$0.value.info.isMainFrame || $0.key == document }
                }
                page.frames[document] = Frame(document: document, info: message.frameInfo, url: url)
            }
            replyHandler(true, nil)
        }
    }

    static func bootstrap(id: String, channel: String, messaging: Bool) -> String {
        #"""
        (() => {
          if (globalThis.__searchUserWorldReady) return;
          Object.defineProperty(globalThis, '__searchUserWorldReady', { value: true });
          const uuid = () => typeof globalThis.crypto?.randomUUID === 'function' ? crypto.randomUUID()
            : [...crypto.getRandomValues(new Uint32Array(4))].map(n => n.toString(16).padStart(8, '0')).join('');
          const ports = new Map(), documentId = uuid();
          Object.defineProperty(globalThis, '__searchUserWorldDocument', { value: documentId });
          const post = webkit.messageHandlers[\#(json(channel))].postMessage.bind(webkit.messageHandlers[\#(json(channel))]);
          const call = (operation, args = {}) => post({ operation, documentId, ...args }).then(reply => {
            if (reply && reply.error) throw new Error(reply.error);
            return reply && reply.value;
          });
          const event = () => { const listeners = new Set(); return {
            addListener: f => { if (typeof f === 'function') listeners.add(f); }, removeListener: f => listeners.delete(f),
            hasListener: f => listeners.has(f), hasListeners: () => listeners.size > 0,
            emit: (...args) => { for (const f of [...listeners]) { try { f(...args); } catch (e) { console.error(e); } } }
          }; };
          Object.defineProperty(globalThis, '__searchUserPortEvent', { value: (id, kind, value) => {
            const entry = ports.get(id); if (!entry) return;
            if (kind === 'message') entry.port.onMessage.emit(value, entry.port);
            else entry.close();
          } });
          call('hello').catch(() => {});
          globalThis.addEventListener?.('pagehide', () => {
            for (const entry of [...ports.values()]) entry.port.disconnect();
            call('bye').catch(() => {});
          });
          globalThis.addEventListener?.('pageshow', event => { if (event.persisted) call('hello').catch(() => {}); });
          if (!\#(messaging ? "true" : "false")) return;
          const runtime = {
            id: \#(json(id)),
            sendMessage(message, ...rest) {
              const callback = typeof rest.at(-1) === 'function' ? rest.pop() : null;
              const sent = call('message', { message });
              if (!callback) return sent;
              sent.then(callback, error => { runtime.lastError = { message: error.message }; try { callback(); } finally { delete runtime.lastError; } });
            },
            connect(info = {}) {
              const id = uuid(), name = String(info.name || ''), onMessage = event(), onDisconnect = event();
              let closed = false;
              const ready = call('connect', { port: id, name });
              const port = { name, onMessage, onDisconnect,
                postMessage(message) { if (closed) throw new Error('Attempting to use a disconnected port'); ready.then(() => call('post', { port: id, message })).catch(() => close()); },
                disconnect() { if (closed) return; close(); ready.then(() => call('disconnect', { port: id })).catch(() => {}); }
              };
              const close = () => { if (closed) return; closed = true; ports.delete(id); onDisconnect.emit(port); };
              ports.set(id, { port, close }); ready.catch(error => { runtime.lastError = { message: error.message }; try { close(); } finally { delete runtime.lastError; } });
              return port;
            }
          };
          Object.defineProperty(globalThis, 'chrome', { value: { runtime }, configurable: true, writable: true });
          Object.defineProperty(globalThis, 'browser', { value: globalThis.chrome, configurable: true, writable: true });
        })();
        """#
    }

    private final class FrameBridge: NSObject, WKScriptMessageHandlerWithReply {
        let id: String
        let context: WKWebExtensionContext
        let generation: String
        let worldID: String
        let world: WKContentWorld
        weak var tab: Tab?
        private var documents = Set<String>()
        init(context: WKWebExtensionContext, generation: String, worldID: String, world: WKContentWorld, tab: Tab) {
            self.context = context; self.generation = generation; self.id = context.uniqueIdentifier; self.worldID = worldID; self.world = world; self.tab = tab
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            guard let tab, tab.built === message.webView, let body = message.body as? [String: Any],
                  let document = body["documentId"] as? String, document.count <= 128,
                  let operation = body["operation"] as? String, let url = message.frameInfo.request.url,
                  let registration = registrations[id], registration.context === context,
                  registration.generation == generation, Extensions.userScriptsAllowed(id),
                  (!tab.shy || registration.context.hasAccessToPrivateData),
                  let permitted = permissionURL(url, frame: message.frameInfo),
                  registration.context.hasAccess(to: permitted, in: Extensions.shared.adapter(for: tab)) else {
                return replyHandler(["error": "User-script context is no longer authorized"], nil)
            }
            if operation == "hello" {
                documents.insert(document)
                return replyHandler(["value": true], nil)
            }
            if operation == "bye" {
                documents.remove(document)
                if let view = message.webView { registration.host?.discard(view, document: document) }
                return replyHandler(["value": true], nil)
            }
            let properties = registration.worlds.first { ($0["worldId"] as? String ?? "") == worldID } ?? [:]
            guard properties["messaging"] as? Bool == true, documents.contains(document) else {
                return replyHandler(["error": "User-script messaging is disabled"], nil)
            }
            let source = Source(tab: tab, web: message.webView!, frame: message.frameInfo, world: world,
                                document: document, worldID: worldID, url: url)
            Task { @MainActor in
                do {
                    guard registrations[id]?.context === context, registrations[id]?.generation == generation else { throw invalid("Extension context was replaced") }
                    let host = try ExtensionUserScripts.host(for: id)
                    let value = try await host.call(operation, body: body, source: source)
                    replyHandler(["value": value ?? NSNull()], nil)
                } catch { replyHandler(["error": error.localizedDescription], nil) }
            }
        }
    }

    private struct Source {
        weak var tab: Tab?
        weak var web: WKWebView?
        let frame: WKFrameInfo
        let world: WKContentWorld
        let document: String
        let worldID: String
        let url: URL
    }

    private static let markFrame = #"""
    if (expected && globalThis.__searchFrameDocument !== expected) throw new Error('The document changed');
    if (!document.documentElement) await new Promise(resolve => {
      const observer = new MutationObserver(() => { if (document.documentElement) { observer.disconnect(); resolve(); } });
      observer.observe(document, { childList: true });
    });
    if (expected && globalThis.__searchFrameDocument !== expected) throw new Error('The document changed');
    document.documentElement.setAttribute(marker, token);
    return location.href;
    """#

    private static func host(for id: String) throws -> Host {
        guard var registration = registrations[id] else { throw invalid("Extension was unloaded") }
        if let host = registration.host, !host.closed { return host }
        let host = try Host(context: registration.context, generation: registration.generation)
        registration.host = host
        registrations[id] = registration
        return host
    }

    /// A genuine extension page relays to WebKit's native worker. Its native
    /// handler is never installed in a website or a user-script world.
    private final class Host: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKWebExtensionTab {
        let context: WKWebExtensionContext
        let generation: String
        let web: WKWebView
        private var ready = false
        fileprivate var closed = false
        private var waiting: [CheckedContinuation<Void, Error>] = []
        private var ports: [String: Source] = [:]
        private var deadline: Task<Void, Never>?

        init(context: WKWebExtensionContext, generation: String) throws {
            guard let configuration = context.webViewConfiguration else { throw invalid("No extension configuration") }
            self.context = context
            self.generation = generation
            // A copied WKWebViewConfiguration shares its user-content
            // controller. The private transport handler belongs to this
            // one hidden page, never every extension page or another host.
            configuration.userContentController = WKUserContentController()
            web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
            super.init()
            web.navigationDelegate = self
            web.configuration.userContentController.add(self, contentWorld: .page, name: "userScriptHost")
            context.didOpenTab(self)
            web.load(URLRequest(url: context.baseURL.appendingPathComponent(hostPath)))
            deadline = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, let self, !self.ready else { return }
                self.close()
            }
        }

        private func loaded() async throws {
            if ready { return }
            guard !closed else { throw invalid("User-script bridge was closed") }
            try await withCheckedThrowingContinuation { waiting.append($0) }
        }

        func close() {
            guard !closed else { return }
            closed = true
            deadline?.cancel()
            web.stopLoading()
            web.navigationDelegate = nil
            web.configuration.userContentController.removeScriptMessageHandler(forName: "userScriptHost", contentWorld: .page)
            context.didCloseTab(self, windowIsClosing: false)
            for (key, source) in ports { deliver(key, kind: "disconnect", value: NSNull(), source: source) }
            ports.removeAll()
            let waiters = waiting; waiting.removeAll()
            waiters.forEach { $0.resume(throwing: invalid("User-script bridge was closed")) }
        }

        func discard(_ view: WKWebView, document: String? = nil) {
            for (key, source) in ports where source.web === view && (document == nil || source.document == document) {
                deliver(key, kind: "disconnect", value: NSNull(), source: source)
                ports[key] = nil
                web.callAsyncJavaScript("return await globalThis.__searchUserScriptHost('disconnect', { port }, {}, {});",
                                        arguments: ["port": key], in: nil, in: .page) { _ in }
            }
        }

        private var current: Bool {
            !closed && registrations[context.uniqueIdentifier]?.context === context
                && registrations[context.uniqueIdentifier]?.generation == generation
                && Extensions.userScriptsAllowed(context.uniqueIdentifier)
        }

        private func authorized(_ source: Source) -> Bool {
            guard current,
                  let tab = source.tab, let view = source.web, tab.built === view,
                  !tab.shy || context.hasAccessToPrivateData else { return false }
            return permissionURL(source.url, frame: source.frame).map { context.hasAccess(to: $0, in: Extensions.shared.adapter(for: tab)) } ?? false
        }

        private func selector(for tab: Tab) throws -> [String: Any] {
            guard let browser = Extensions.shared.browser(of: tab),
                  let index = Extensions.shared.visibleTabs(of: browser).firstIndex(where: { $0 === tab }),
                  let frame = browser.window?.frame else { throw invalid("The user-script tab is no longer available") }
            let screenHeight = NSScreen.screens.first?.frame.height ?? 0
            return ["index": index, "left": frame.minX, "top": screenHeight - frame.maxY, "width": frame.width, "height": frame.height]
        }

        func targets(_ target: [String: Any], tab: Tab) async throws -> [TargetFrame] {
            try await loaded()
            guard current,
                  let view = tab.built, !tab.shy || context.hasAccessToPrivateData,
                  let page = pages[ObjectIdentifier(view.configuration.userContentController)] else { throw invalid("The user-script tab is no longer available") }
            // A view handed over by an opener can already have a document
            // when the browser adopts it. Its main frame can join discovery
            // immediately; normal tabs discover all frames at document-start.
            if !page.frames.values.contains(where: { $0.info.isMainFrame }) {
                _ = try await view.evaluateJavaScript(discovery(channel: page.discovery), in: nil, contentWorld: Web.world)
                _ = try await view.callAsyncJavaScript("return await globalThis.__searchDiscoverFrame();", in: nil, contentWorld: Web.world)
            }
            let marker = "data-searchextra-user-target-" + UUID().uuidString.lowercased()
            var marked: [String: TargetFrame] = [:]
            do {
                for frame in Array(page.frames.values) {
                    do {
                        let current = try await view.callAsyncJavaScript(markFrame,
                                                                        arguments: ["marker": marker, "token": frame.document, "expected": frame.document], in: frame.info, contentWorld: Web.world)
                        guard let text = current as? String, let url = URL(string: text),
                              let permitted = permissionURL(url, frame: frame.info),
                              context.hasAccess(to: permitted, in: Extensions.shared.adapter(for: tab)) else {
                            clearTargets([TargetFrame(frame: frame, frameID: -1, documentID: "", url: frame.url, marker: marker)], in: view)
                            continue
                        }
                        marked[frame.document] = TargetFrame(frame: frame, frameID: -1, documentID: "", url: url, marker: marker)
                    } catch { continue }
                }
                var lookup = try selector(for: tab)
                lookup["marker"] = marker
                guard current else { throw invalid("User-script context was revoked") }
                let value = try await web.callAsyncJavaScript("return await globalThis.__searchUserScriptHost('targets', { target }, selector, {});",
                                                              arguments: ["target": target, "selector": lookup], in: nil, contentWorld: .page)
                guard let rows = value as? [[String: Any]], !rows.isEmpty else { throw invalid("No matching user-script frames") }
                var selected: [TargetFrame] = []
                var used = Set<String>()
                for row in rows {
                    guard let token = row["token"] as? String, let native = marked[token], used.insert(token).inserted,
                          let frameID = row["frameId"] as? Int, frameID >= 0,
                          let documentID = row["documentId"] as? String, UUID(uuidString: documentID) != nil,
                          let href = row["url"] as? String, href == native.url.absoluteString else { throw invalid("The user-script document changed during frame lookup") }
                    selected.append(TargetFrame(frame: native.frame, frameID: frameID, documentID: documentID, url: native.url, marker: marker))
                }
                guard current, tab.built === view, !tab.shy || context.hasAccessToPrivateData else { throw invalid("User-script context was revoked") }
                clearTargets(marked.values.filter { !used.contains($0.frame.document) }, in: view)
                return selected.sorted { $0.frameID == 0 ? $1.frameID != 0 : ($1.frameID != 0 && $0.frameID < $1.frameID) }
            } catch {
                clearTargets(Array(marked.values), in: view)
                throw error
            }
        }

        func clearTargets(_ targets: [TargetFrame], in view: WKWebView) {
            for selected in targets {
                view.callAsyncJavaScript("if (document.documentElement?.getAttribute(marker) === token) document.documentElement.removeAttribute(marker);",
                                         arguments: ["marker": selected.marker, "token": selected.frame.document], in: selected.frame.info, in: Web.world) { _ in }
            }
        }

        func call(_ operation: String, body: [String: Any], source: Source) async throws -> Any? {
            try await loaded()
            guard authorized(source), let tab = source.tab else { throw invalid("The user-script tab is no longer available") }
            var selector = try self.selector(for: tab)
            // The window/index narrows the lookup, but is not an identity:
            // tabs can move while the native/extension messages are queued.
            // A short-lived marker in this exact native WKFrameInfo lets the
            // engine return both its actual tab and actual frame identifier.
            let marker = "data-searchextra-user-frame-" + UUID().uuidString.lowercased()
            let needsSender = operation == "connect" || operation == "message"
            var sourceURL = source.url
            defer {
                if needsSender, let view = source.web {
                    view.callAsyncJavaScript("if (document.documentElement?.getAttribute(marker) === token) document.documentElement.removeAttribute(marker);",
                                             arguments: ["marker": marker, "token": source.document], in: source.frame, in: source.world) { _ in }
                }
            }
            if needsSender {
                guard let view = source.web else { throw invalid("The user-script frame was closed") }
                let current = try await view.callAsyncJavaScript(markFrame,
                                                                 arguments: ["marker": marker, "token": source.document, "expected": ""], in: source.frame, contentWorld: source.world)
                guard let text = current as? String, let url = URL(string: text),
                      let permitted = permissionURL(url, frame: source.frame),
                      context.hasAccess(to: permitted, in: Extensions.shared.adapter(for: tab)) else { throw invalid("User-script frame access was revoked") }
                sourceURL = url
                selector["marker"] = marker
                selector["token"] = source.document
            }
            guard authorized(source) else { throw invalid("User-script context was revoked") }
            let origin = source.frame.securityOrigin
            let sender: [String: Any] = ["id": context.uniqueIdentifier, "url": sourceURL.absoluteString,
                                       "origin": Browser.origin(origin.protocol, origin.host, origin.port),
                                       "documentId": source.document, "worldId": source.worldID]
            let port = body["port"] as? String ?? ""
            if ["connect", "post", "disconnect"].contains(operation) {
                guard !port.isEmpty, port.count <= 128 else { throw invalid("Invalid user-script port") }
                if operation == "connect" { ports[port] = source }
                else { guard ports[port]?.document == source.document, ports[port]?.worldID == source.worldID else { throw invalid("Unknown user-script port") } }
            }
            var completed = false
            defer {
                if operation == "connect", !completed {
                    ports[port] = nil
                    web.callAsyncJavaScript("return await globalThis.__searchUserScriptHost('disconnect', { port }, {}, {});",
                                            arguments: ["port": port], in: nil, in: .page) { _ in }
                }
            }
            let value: Any = try await web.callAsyncJavaScript("return await globalThis.__searchUserScriptHost(operation, body, selector, sender);",
                                                              arguments: ["operation": operation, "body": body, "selector": selector, "sender": sender], in: nil, contentWorld: .page) ?? NSNull()
            guard authorized(source) else { throw invalid("User-script context was revoked") }
            if operation == "disconnect" { ports[port] = nil }
            completed = true
            return value
        }

        private func deliver(_ key: String, kind: String, value: Any, source: Source) {
            guard let view = source.web else { return }
            view.callAsyncJavaScript("globalThis.__searchUserPortEvent(port, kind, value);", arguments: ["port": key, "kind": kind, "value": value],
                                     in: source.frame, in: source.world) { _ in }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.webView === web, message.frameInfo.isMainFrame,
                  message.frameInfo.request.url == context.baseURL.appendingPathComponent(hostPath),
                  let body = message.body as? [String: Any], let key = body["port"] as? String,
                  let kind = body["kind"] as? String, let source = ports[key], authorized(source) else { return }
            deliver(key, kind: kind, value: body["value"] ?? NSNull(), source: source)
            if kind == "disconnect" { ports[key] = nil }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !closed else { return }
            ready = true; deadline?.cancel()
            let waiters = waiting; waiting.removeAll(); waiters.forEach { $0.resume() }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { close() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { close() }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { close() }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.targetFrame?.isMainFrame != false && navigationAction.request.url == context.baseURL.appendingPathComponent(hostPath) ? .allow : .cancel)
        }
        func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { nil }
        func indexInWindow(for context: WKWebExtensionContext) -> Int { NSNotFound }
        func webView(for context: WKWebExtensionContext) -> WKWebView? { web }
        func title(for context: WKWebExtensionContext) -> String? { "User-script bridge" }
        func url(for context: WKWebExtensionContext) -> URL? { web.url }
        func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !web.isLoading }
        func isSelected(for context: WKWebExtensionContext) -> Bool { false }
        func close(for context: WKWebExtensionContext) async throws { close() }
    }

    nonisolated static let hostHTML = "<!doctype html><meta charset=utf-8><script src='../search-shim.js'></script><script src='user-script-host.js'></script>"
    nonisolated static let hostScript = #"""
    (() => {
      const ports = new Map();
      const emit = (port, kind, value) => webkit.messageHandlers.userScriptHost.postMessage({ port, kind, value });
      const tabFor = async selector => {
        const windows = await chrome.windows.getAll({ populate: true });
        const candidates = windows.filter(w => ['left', 'top', 'width', 'height'].every(k => Math.abs(w[k] - selector[k]) <= 2));
        if (candidates.length !== 1) throw new Error('The user-script window is no longer available');
        const tab = (candidates[0].tabs || []).find(t => t.index === selector.index);
        if (!tab) throw new Error('The user-script tab is no longer available');
        return tab;
      };
      const senderFor = async (selector, sender) => {
        const tab = await tabFor(selector);
        const frames = await chrome.scripting.executeScript({ target: { tabId: tab.id, allFrames: true },
          func: (marker, token) => {
            const matched = document.documentElement?.getAttribute(marker) === token;
            if (matched) document.documentElement.removeAttribute(marker);
            return { matched, url: location.href };
          }, args: [selector.marker, selector.token] });
        const found = frames.filter(frame => frame.result?.matched && frame.result.url === sender.url);
        if (found.length !== 1) throw new Error('The user-script frame is no longer available');
        return { ...sender, tab, frameId: found[0].frameId, documentId: found[0].documentId || sender.documentId };
      };
      globalThis.__searchUserScriptHost = async (operation, body, selector, source) => {
        if (operation === 'targets') {
          const tab = await tabFor(selector), target = { tabId: tab.id };
          for (const key of ['allFrames', 'frameIds', 'documentIds']) if (body.target[key] !== undefined) target[key] = body.target[key];
          const frames = await chrome.scripting.executeScript({ target,
            func: marker => ({ token: document.documentElement?.getAttribute(marker), url: location.href }), args: [selector.marker] });
          if (!frames.length || frames.some(frame => !frame.result?.token || frame.error)) throw new Error('The user-script target document is no longer available');
          return frames.filter((frame, index) => frames.findIndex(other => other.frameId === frame.frameId && other.documentId === frame.documentId) === index)
            .map(frame => ({ frameId: frame.frameId, documentId: frame.documentId, token: frame.result.token, url: frame.result.url }));
        }
        if (operation === 'message') return chrome.runtime.sendMessage({ __searchUserScript: true, message: body.message, __searchUserSender: await senderFor(selector, source) });
        if (operation === 'connect') {
          const sender = await senderFor(selector, source);
          const port = chrome.runtime.connect({ name: 'search-us:' + String(body.name || '') });
          ports.set(body.port, port);
          port.onMessage.addListener(value => emit(body.port, 'message', value));
          port.onDisconnect.addListener(() => { ports.delete(body.port); emit(body.port, 'disconnect', null); });
          port.postMessage({ __searchUserHandshake: true, sender });
          return true;
        }
        const port = ports.get(body.port);
        if (!port) throw new Error('The user-script port is disconnected');
        if (operation === 'post') { port.postMessage(body.message); return true; }
        if (operation === 'disconnect') { ports.delete(body.port); port.disconnect(); return true; }
        throw new Error('Unknown user-script operation');
      };
    })();
    """#
}
