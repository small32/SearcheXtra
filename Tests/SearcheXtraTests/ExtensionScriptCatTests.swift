import AppKit
import Foundation
import WebKit
import XCTest
@testable import SearcheXtra

/// Optional integration against the unmodified official MV3 package. The CI
/// supplies the pinned, hash-checked ZIP/folder; production install/prepare is
/// the only code allowed to change the package before WebKit loads it.
@available(macOS 15.4, *)
@MainActor
final class ExtensionScriptCatTests: XCTestCase {
    func testOriginalMV3RunsGMStorageXHRFramesAlongsideMV2() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=interface-tests") }
        guard let input = ProcessInfo.processInfo.environment["SEARCHEXTRA_TEST_MV3_FOLDER"], !input.isEmpty else {
            throw XCTSkip("Set SEARCHEXTRA_TEST_MV3_FOLDER to the original ScriptCat 1.4.0 Chrome ZIP or folder")
        }
        trace("starting AppKit")
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        // The first real tab must load saved drag settings without recursively
        // refreshing itself during FlowDragSettings.shared initialization.
        let previousDragSettings = Store.settings.data(forKey: "flowDrag.config")
        var savedDragSettings = FlowDragConfig()
        savedDragSettings.distanceThreshold = 47
        Store.settings.set(try JSONEncoder().encode(savedDragSettings), forKey: "flowDrag.config")
        defer {
            if let previousDragSettings { Store.settings.set(previousDragSettings, forKey: "flowDrag.config") }
            else { Store.settings.removeObject(forKey: "flowDrag.config") }
        }
        trace("preparing official package")
        let files = FileManager.default
        let scratch = files.temporaryDirectory.appendingPathComponent("scriptcat-native-\(UUID().uuidString)", isDirectory: true)
        let package = scratch.appendingPathComponent("scriptcat", isDirectory: true)
        try files.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: scratch) }
        var directory: ObjCBool = false
        guard files.fileExists(atPath: input, isDirectory: &directory) else { throw FixtureFailure("ScriptCat fixture is missing") }
        if directory.boolValue { try files.copyItem(at: URL(fileURLWithPath: input), to: package) }
        else { try Crx.unpack(Data(contentsOf: URL(fileURLWithPath: input)), into: package) }
        trace("official package unpacked")
        let manifest = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: package.appendingPathComponent("manifest.json"))) as? [String: Any])
        XCTAssertEqual(manifest["manifest_version"] as? Int, 3)
        XCTAssertEqual(manifest["version"] as? String, "1.4.0")
        let identifier = Crx.unpackedID(for: package)
        trace("constructing browser")
        let browser = Browser(record: WindowRecord(), opensStartPage: false)
        let previousFront = Front.shared.browser
        trace("constructing native window")
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 900, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        browser.window = window
        trace("registering native window")
        Browsers.register(browser)
        Front.shared.set(browser)
        trace("native browser registered")
        var installed = [identifier]
        defer {
            for id in installed { Extensions.shared.remove(id) }
            // Retire this fixture without adding a restorable user window.
            browser.extensionPopup = "scriptcat-native-fixture"
            Browsers.closing(window)
            browser.closeAll(); browser.dozing?.invalidate()
            window.contentView = nil; window.close()
            Front.shared.set(previousFront)
        }
        func show(_ tab: Tab) {
            browser.select(tab, floatPrevious: false)
            tab.web.frame = NSRect(x: 0, y: 0, width: 900, height: 650)
            window.contentView = tab.web
        }
        trace("starting loopback servers")
        let pageServer = try LocalDownloadServer(size: 1024)
        let xhrServer = try LocalDownloadServer(size: 1024)
        defer { pageServer.stop(); xhrServer.stop() }
        trace("opening initial local website")
        let website = browser.open(pageServer.url("/page"), foreground: true)
        XCTAssertEqual(FlowDragSettings.shared.config, savedDragSettings)
        trace("attaching initial WebView")
        show(website)
        try await until("initial local website") { !website.web.isLoading && website.web.url == pageServer.url("/page") }
        trace("initial local website loaded")
        var restoredRuntime: [String: Any] = [:]
        var diagnosticOptions: Tab?
        var permissionPhase = "not started"
        func nativeRelayState(_ options: Tab) async throws -> Any? {
            try await evaluate(options.web, #"""
            const scripts = await chrome.scripting.getRegisteredContentScripts();
            const tab = (await chrome.tabs.query({})).find(tab => tab.url === website);
            if (!tab) return { scripts, tab: 'unavailable' };
            const isolated = await chrome.scripting.executeScript({ target: { tabId: tab.id },
              func: () => ({ url: location.href, id: globalThis.chrome?.runtime?.id || null,
                shim: globalThis.__searchShim === true, sendMessage: typeof globalThis.chrome?.runtime?.sendMessage,
                connect: typeof globalThis.chrome?.runtime?.connect }) });
            return { scripts, isolated };
            """#, arguments: ["website": pageServer.url("/page").absoluteString])
        }
        func waitForRuntime(_ options: Tab, _ label: String) async throws -> [String: Any] {
            var service: [String: Any] = [:]
            try await until("ScriptCat runtime initialization: \(label)") {
                service = try await self.evaluate(options.web, #"""
                return await chrome.runtime.sendMessage({ action: 'serviceWorker/runtime/pageLoad', data: {} });
                """#) as? [String: Any] ?? [:]
                return service["code"] as? Int == 0 && (service["data"] as? [String: Any])?["ok"] is Bool
            }
            return service
        }
        do {
            trace("installing original ScriptCat")
            let install = try XCTUnwrap(Extensions.shared.installFolder(at: package, confirm: false))
            await install.value
            trace("original ScriptCat installed")
            let first = try XCTUnwrap(Extensions.shared.contexts[identifier])
            XCTAssertFalse(Extensions.userScriptsAllowed(identifier))
            trace("loading initial native background")
            try await loadBackground(first, "initial installation")
            trace("initial native background loaded")
            let firstOptions = browser.open(try XCTUnwrap(first.optionsPageURL), foreground: true)
            diagnosticOptions = firstOptions
            show(firstOptions)
            try await until("ScriptCat options API") {
                (try? await self.evaluate(firstOptions.web, "return document.readyState === 'complete' && typeof chrome.userScripts?.getScripts === 'function';")) as? Bool == true
            }
            let denied = try await evaluate(firstOptions.web, "try { await chrome.userScripts.getScripts(); return false; } catch { return true; }")
            XCTAssertEqual(denied as? Bool, true)
            // API availability does not establish background readiness. This
            // service waits for ScriptCat's initReady even while user scripts
            // are denied; no matching script is a valid { ok: false } reply.
            trace("waiting for initial ScriptCat background readiness")
            _ = try await waitForRuntime(firstOptions, "initial installation")
            trace("initial ScriptCat background ready")
            // Installing can finish before the first-window startup callback.
            // Its deferred work must not clear this already running worker.
            try await until("deferred extension startup") { !Extensions.shared.starting }
            _ = try await waitForRuntime(firstOptions, "after deferred extension startup")
            trace("initial ScriptCat background survived deferred startup")
            trace("enabling user-script permission")
            let enable = try XCTUnwrap(Extensions.shared.setUserScriptsAllowed(identifier, true))
            trace("user-script permission setter returned")
            let enabled = await enable.value
            trace("user-script permission reload completed: \(enabled)")
            XCTAssertTrue(enabled)
            var context = try XCTUnwrap(Extensions.shared.contexts[identifier])
            trace("loading reloaded native background")
            try await loadBackground(context, "first permission grant")
            trace("reloaded native background loaded")
            trace("closing initial ScriptCat options")
            browser.close(firstOptions)
            trace("initial ScriptCat options closed")
            trace("opening reloaded ScriptCat options")
            var options = browser.open(try XCTUnwrap(context.optionsPageURL), foreground: true)
            diagnosticOptions = options
            trace("reloaded ScriptCat options opened")
            show(options)
            trace("reloaded ScriptCat options attached")
            try await until("reloaded ScriptCat options API") {
                (try? await self.evaluate(options.web, "return document.readyState === 'complete' && typeof chrome.userScripts?.getScripts === 'function';")) as? Bool == true
            }
            // MV3 background initialization can outlive controller loading. A
            // runtime service wakes it if needed and waits for initReady.
            trace("waiting for reloaded ScriptCat background readiness")
            _ = try await waitForRuntime(options, "first permission grant")
            trace("reloaded ScriptCat background ready")
            try await until("ScriptCat native user-world registration") {
                let scripts = try await ExtensionUserScripts.call("userScripts.list", args: [], context: context) as? [[String: Any]] ?? []
                return scripts.contains { $0["id"] as? String == "scriptcat-content" }
            }
            trace("ScriptCat native user world registered")
            let userCode = #"""
            // ==UserScript==
            // @name SearcheXtra native MV3 regression
            // @namespace https://searchextra.test/
            // @version 1.0
            // @match http://127.0.0.1/*
            // @run-at document-end
            // @grant GM.getValue
            // @grant GM.setValue
            // @grant GM_xmlhttpRequest
            // @connect 127.0.0.1
            // ==/UserScript==
            (async () => {
              document.documentElement.setAttribute('data-sx-scriptcat-started', 'true');
              const count = Number(await GM.getValue('searchextra-native-test-count', 0)) + 1;
              document.documentElement.setAttribute('data-sx-scriptcat-read', String(count - 1));
              document.documentElement.setAttribute('data-sx-scriptcat-writing', String(count));
              await GM.setValue('searchextra-native-test-count', count);
              document.documentElement.setAttribute('data-sx-scriptcat-wrote', 'true');
              document.documentElement.setAttribute('data-sx-scriptcat-count', String(count));
              GM_xmlhttpRequest({ method: 'GET', url: XHR_URL,
                onload: response => document.documentElement.setAttribute('data-sx-scriptcat-xhr', response.status + ':' + response.responseText.includes('Local test page')),
                onerror: error => document.documentElement.setAttribute('data-sx-scriptcat-error', 'xhr:' + String(error.error || error)) });
            })().catch(error => document.documentElement.setAttribute('data-sx-scriptcat-error', String(error)));
            """#.replacingOccurrences(of: "XHR_URL", with: quoted(xhrServer.url("/page").absoluteString))
            let response = try await evaluate(options.web, #"""
            const now = Date.now(), uuid = crypto.randomUUID();
            const script = { uuid, name: 'SearcheXtra native MV3 regression', namespace: 'https://searchextra.test/', origin: '', originDomain: '',
              checkUpdateUrl: '', downloadUrl: '', metadata: { name: ['SearcheXtra native MV3 regression'], namespace: ['https://searchextra.test/'],
                version: ['1.0'], match: ['http://127.0.0.1/*'], 'run-at': ['document-end'], grant: ['GM.getValue', 'GM.setValue', 'GM_xmlhttpRequest'], connect: ['127.0.0.1'] },
              selfMetadata: {}, sort: -1, type: 1, status: 1, runStatus: 'complete', createtime: now, updatetime: now, checktime: now };
            const result = await chrome.runtime.sendMessage({ action: 'serviceWorker/script/install', data: { script, code, upsertBy: 'user' } });
            if (!result || result.code) throw new Error(JSON.stringify(result));
            return { uuid, result };
            """#, arguments: ["code": userCode]) as? [String: Any]
            let scriptID = try XCTUnwrap(response?["uuid"] as? String)
            trace("real GM user script installed")
            try await until("real installed user-script registration") {
                let scripts = try await ExtensionUserScripts.call("userScripts.list", args: [], context: context) as? [[String: Any]] ?? []
                return scripts.contains { $0["id"] as? String == scriptID }
            }
            show(website)
            try await reload(website, in: window)
            func state() async throws -> [String: Any] {
                try await self.evaluate(website.web, "return { started: document.documentElement.getAttribute('data-sx-scriptcat-started'), read: document.documentElement.getAttribute('data-sx-scriptcat-read'), writing: document.documentElement.getAttribute('data-sx-scriptcat-writing'), wrote: document.documentElement.getAttribute('data-sx-scriptcat-wrote'), count: document.documentElement.getAttribute('data-sx-scriptcat-count'), xhr: document.documentElement.getAttribute('data-sx-scriptcat-xhr'), error: document.documentElement.getAttribute('data-sx-scriptcat-error') };") as? [String: Any] ?? [:]
            }
            func permissionCycle(_ label: String, mv2: Bool) async throws {
                permissionPhase = label
                let previousCount = Int((try await state())["count"] as? String ?? "0") ?? 0
                let previousView = website.web
                trace("permission cycle starting: \(label), previous count \(previousCount)")
                let disable = try XCTUnwrap(Extensions.shared.setUserScriptsAllowed(identifier, false))
                let disabled = await disable.value
                XCTAssertTrue(disabled)
                XCTAssertTrue(website.built === previousView, "Changing permission leaves the current document untouched")
                try await reload(website, in: window)
                XCTAssertFalse(website.built === previousView, "A native refresh replaces the unloaded extension worlds")
                let revoked = try await evaluate(website.web, "return document.documentElement.getAttribute('data-sx-scriptcat-started') === null && (!mv2 || document.documentElement.getAttribute('data-sx-mv2') === 'native');", arguments: ["mv2": mv2])
                XCTAssertEqual(revoked as? Bool, true)
                let reenable = try XCTUnwrap(Extensions.shared.setUserScriptsAllowed(identifier, true))
                let reenabled = await reenable.value
                XCTAssertTrue(reenabled)
                let restoredContext = try XCTUnwrap(Extensions.shared.contexts[identifier])
                try await until("real user-script registrations: \(label)") {
                    let scripts = try await ExtensionUserScripts.call("userScripts.list", args: [], context: restoredContext) as? [[String: Any]] ?? []
                    return scripts.contains { $0["id"] as? String == scriptID }
                }
                let restoredOptions = browser.open(try XCTUnwrap(restoredContext.optionsPageURL), foreground: true)
                diagnosticOptions = restoredOptions
                show(restoredOptions)
                try await until("native ScriptCat content registration: \(label)") {
                    restoredRuntime = try await self.evaluate(restoredOptions.web, #"""
                    return { scripts: await chrome.scripting.getRegisteredContentScripts(),
                      worlds: await chrome.userScripts.getWorldConfigurations() };
                    """#) as? [String: Any] ?? [:]
                    return (restoredRuntime["scripts"] as? [[String: Any]])?.contains { $0["id"] as? String == "scriptcat-scripting" } == true
                }
                trace("permission cycle native registrations: \(label) \(restoredRuntime)")
                // A persisted ID does not establish worker readiness. This
                // real service waits for ScriptCat's initReady middleware.
                restoredRuntime["service"] = try await waitForRuntime(restoredOptions, label)
                context = restoredContext
                options = restoredOptions
                show(website)
                try await reload(website, in: window)
                trace("permission cycle actual native page relay: \(label) \(try await nativeRelayState(restoredOptions) ?? "unavailable")")
                try await until("GM storage and XHR recover: \(label)") {
                    let value = try await state()
                    return (Int(value["count"] as? String ?? "0") ?? 0) > previousCount && value["xhr"] as? String == "200:true"
                }
                trace("permission cycle GM storage and XHR succeeded: \(label)")
            }
            try await until("real GM storage and cross-origin GM_xmlhttpRequest") {
                let value = try await state()
                if let error = value["error"] as? String { throw FixtureFailure("User script: " + error) }
                return value["count"] as? String != nil && value["xhr"] as? String == "200:true"
            }
            let firstState = try await state()
            trace("real GM storage and cross-origin XHR succeeded")
            let firstCount = Int(try XCTUnwrap(firstState["count"] as? String)) ?? 0
            XCTAssertGreaterThan(firstCount, 0)
            XCTAssertGreaterThan(xhrServer.count("/page"), 0)
            try await reload(website, in: window)
            try await until("GM value persists across navigation") {
                let current = try await state()
                return (Int(current["count"] as? String ?? "0") ?? 0) > firstCount
            }
            trace("GM storage survived reload")
            _ = try await evaluate(website.web, "const frame = document.createElement('iframe'); frame.id = 'scriptcat-native-child'; frame.src = location.href; document.body.appendChild(frame); return true;")
            try await until("real ScriptCat GM storage in a matching iframe") {
                try await self.evaluate(website.web, "return Boolean(document.querySelector('#scriptcat-native-child')?.contentDocument?.documentElement?.getAttribute('data-sx-scriptcat-count'));") as? Bool == true
            }
            trace("real GM script executed in matching iframe")
            let execution = try await evaluate(options.web, #"""
            const tabs = await chrome.tabs.query({});
            const tab = tabs.find(tab => tab.url === website);
            if (!tab) throw new Error('Native website tab is unavailable');
            const all = await chrome.userScripts.execute({ target: { tabId: tab.id, allFrames: true },
              js: [{ code: "({ url: location.href, id: chrome.runtime.id, pageBridge: typeof globalThis.webkit?.messageHandlers?.officeFlowDrag })" }] });
            if (all.some(frame => frame.error)) throw new Error(JSON.stringify(all));
            const child = all.find(frame => frame.frameId !== 0);
            if (!child) throw new Error('Native iframe result is missing: ' + JSON.stringify(all));
            const byFrame = await chrome.userScripts.execute({ target: { tabId: tab.id, frameIds: [child.frameId] }, js: [{ code: "'frame-result'" }] });
            const byDocument = await chrome.userScripts.execute({ target: { tabId: tab.id, documentIds: [child.documentId] }, js: [{ code: "'document-result'" }] });
            const main = await chrome.userScripts.execute({ target: { tabId: tab.id }, world: 'MAIN',
              js: [{ code: "document.documentElement.setAttribute('data-sx-execute-main', 'true'); 'main-result'" }] });
            return { all, byFrame, byDocument, main };
            """#, arguments: ["website": pageServer.url("/page").absoluteString]) as? [String: Any]
            let allExecutions = try XCTUnwrap(execution?["all"] as? [[String: Any]])
            XCTAssertEqual(allExecutions.count, 2)
            XCTAssertEqual(Set(allExecutions.compactMap { $0["frameId"] as? Int }).count, 2)
            XCTAssertEqual(Set(allExecutions.compactMap { $0["documentId"] as? String }).count, 2)
            for result in allExecutions {
                let value = try XCTUnwrap(result["result"] as? [String: Any])
                XCTAssertEqual(value["id"] as? String, identifier)
                XCTAssertEqual(value["pageBridge"] as? String, "undefined")
            }
            for (key, value) in [("byFrame", "frame-result"), ("byDocument", "document-result"), ("main", "main-result")] {
                let results = try XCTUnwrap(execution?[key] as? [[String: Any]])
                XCTAssertEqual(results.count, 1)
                XCTAssertEqual(results.first?["result"] as? String, value)
            }
            let mainExecuted = try await evaluate(website.web, "return document.documentElement.getAttribute('data-sx-execute-main') === 'true';")
            XCTAssertEqual(mainExecuted as? Bool, true)
            trace("native allFrames, frameId, documentId and MAIN execution succeeded")
            try await permissionCycle("before runtime.reload", mv2: false)
            let countBeforeExtensionReload = Int((try await state())["count"] as? String ?? "0") ?? 0
            let runtimeContext = context
            // The cycle already loaded this page and called its native API.
            // A new tab initially contains about:blank and has no chrome.
            let runtimeOptions = options
            diagnosticOptions = runtimeOptions
            trace("runtime.reload requested from context \(ObjectIdentifier(runtimeContext))")
            show(runtimeOptions)
            let runtimeAssembly = try await evaluate(runtimeOptions.web, #"""
            const descriptor = (object, key) => {
              const d = Object.getOwnPropertyDescriptor(object, key);
              return d && { configurable: d.configurable, enumerable: d.enumerable, writable: d.writable,
                getter: typeof d.get === 'function', value: typeof d.value === 'function' ? String(d.value) : typeof d.value };
            };
            return { installed: globalThis.__searchUserScriptRuntimeInstall,
              reload: String(chrome.runtime.reload), browserReload: String(browser.runtime.reload),
              nativeEvents: chrome.runtime.onMessage === browser.runtime.onMessage,
              chrome: descriptor(globalThis, 'chrome'), browser: descriptor(globalThis, 'browser'),
              runtime: descriptor(chrome, 'runtime'), method: descriptor(chrome.runtime, 'reload') };
            """#) as? [String: Any]
            print("ScriptCat native runtime assembly: \(runtimeAssembly ?? [:])")
            XCTAssertEqual(runtimeAssembly?["nativeEvents"] as? Bool, true)
            guard (runtimeAssembly?["installed"] as? [String: Any])?["installed"] as? Bool == true,
                  (runtimeAssembly?["reload"] as? String)?.contains("native(\"runtime.reload\"") == true else {
                throw FixtureFailure("The app runtime.reload method was not installed in the real extension page")
            }
            let reloadSource = try await evaluate(runtimeOptions.web, "const source = Function.prototype.toString.call(chrome.runtime.reload); chrome.runtime.reload(); return source;")
            trace("runtime.reload dispatched: \(reloadSource ?? "unavailable")")
            try await until("a fresh runtime and original ScriptCat registration after chrome.runtime.reload") {
                guard let current = Extensions.shared.contexts[identifier], current !== runtimeContext else { return false }
                let scripts = try await ExtensionUserScripts.call("userScripts.list", args: [], context: current) as? [[String: Any]] ?? []
                return scripts.contains { $0["id"] as? String == "scriptcat-content" } && scripts.contains { $0["id"] as? String == scriptID }
            }
            // runtime.reload returns before the replacement worker finishes
            // initialization. As in permissionCycle, persisted registrations
            // are not a service-ready signal, and the old options page belongs
            // to the unloaded context.
            context = try XCTUnwrap(Extensions.shared.contexts[identifier])
            let runtimeReadyOptions = browser.open(try XCTUnwrap(context.optionsPageURL), foreground: true)
            options = runtimeReadyOptions
            diagnosticOptions = runtimeReadyOptions
            show(runtimeReadyOptions)
            try await until("native ScriptCat content registration after runtime.reload") {
                let scripts = try await self.evaluate(runtimeReadyOptions.web, "return await chrome.scripting.getRegisteredContentScripts();") as? [[String: Any]] ?? []
                return scripts.contains { $0["id"] as? String == "scriptcat-scripting" }
            }
            _ = try await waitForRuntime(runtimeReadyOptions, "native runtime.reload")
            trace("replacement ScriptCat background ready after runtime.reload")
            show(website)
            try await reload(website, in: window)
            try await until("GM storage and XHR after native chrome.runtime.reload") {
                let value = try await state()
                return (Int(value["count"] as? String ?? "0") ?? 0) > countBeforeExtensionReload && value["xhr"] as? String == "200:true"
            }
            trace("GM storage and native transport survived chrome.runtime.reload")
            let mv2 = scratch.appendingPathComponent("mv2", isDirectory: true)
            try files.createDirectory(at: mv2, withIntermediateDirectories: true)
            try #"{"manifest_version":2,"name":"SearcheXtra native MV2 fixture","version":"1.0","content_scripts":[{"matches":["http://127.0.0.1/*"],"js":["content.js"],"run_at":"document_end"}]}"#.write(to: mv2.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try "document.documentElement.setAttribute('data-sx-mv2','native');".write(to: mv2.appendingPathComponent("content.js"), atomically: true, encoding: .utf8)
            installed.append(Crx.unpackedID(for: mv2))
            let mv2Install = try XCTUnwrap(Extensions.shared.installFolder(at: mv2, confirm: false))
            await mv2Install.value
            show(website)
            try await reload(website, in: window)
            try await until("MV2 and real ScriptCat MV3 run together") {
                try await self.evaluate(website.web, "return document.documentElement.getAttribute('data-sx-mv2') === 'native' && document.documentElement.getAttribute('data-sx-scriptcat-started') === 'true';") as? Bool == true
            }
            trace("native MV2 and ScriptCat MV3 coexist")
            try await permissionCycle("after runtime.reload", mv2: true)
            print("PASS: original ScriptCat MV3 1.4.0: installation, opt-in, real GM storage, cross-origin XHR, reload, iframe, native execute targets, native runtime.reload, MV2 coexistence, revocation and re-enable")
        } catch {
            print("ScriptCat permission phase: \(permissionPhase)")
            if !restoredRuntime.isEmpty { print("ScriptCat permission restore runtime: \(restoredRuntime)") }
            print("ScriptCat native errors: \(Extensions.shared.errors[identifier] ?? [])")
            if let current = Extensions.shared.contexts[identifier] {
                let scripts = try? await ExtensionUserScripts.call("userScripts.list", args: [], context: current) as? [[String: Any]]
                print("ScriptCat current context: \(ObjectIdentifier(current)); registrations: \(scripts?.compactMap { $0["id"] as? String } ?? [])")
            } else { print("ScriptCat current context: unloaded") }
            let stateBody = "return Object.fromEntries(['started', 'read', 'writing', 'wrote', 'count', 'xhr', 'error'].map(key => [key, document.documentElement.getAttribute('data-sx-scriptcat-' + key)]));"
            let lastState = try? await evaluate(website.web, stateBody)
            print("ScriptCat last website state: \(lastState ?? "unavailable")")
            if let diagnosticOptions {
                let nativeState = try? await nativeRelayState(diagnosticOptions)
                print("ScriptCat last native scripting state: \(nativeState ?? "unavailable")")
                let services = try? await evaluate(diagnosticOptions.web, #"""
                const probe = async (name, action) => {
                  try { return [name, await Promise.race([action(), new Promise((_, reject) => setTimeout(() => reject(new Error('probe timed out')), 2500))])]; }
                  catch (error) { return [name, { error: String(error) }]; }
                };
                return Object.fromEntries(await Promise.all([
                  probe('earlyEnvironment', () => chrome.runtime.sendMessage({ action: 'serviceWorker/getExtensionEnv', data: { requireUAD: false } })),
                  probe('platform', () => chrome.runtime.getPlatformInfo()),
                  probe('storageKeys', async () => Object.keys(await chrome.storage.local.get(null))),
                  probe('earlyConnections', () => chrome.runtime.sendMessage({ type: 'userScripts.LISTEN_CONNECTIONS' }))
                ]));
                """#)
                print("ScriptCat worker service diagnostics: \(services ?? "unavailable")")
            }
            if permissionPhase != "not started" {
                // Keep the failing document for diagnosis, and check a new
                // native WebView under the same extension context. This
                // distinguishes a reused page/world from a worker-wide issue.
                let fresh = browser.open(pageServer.url("/page"), foreground: true)
                show(fresh)
                let deadline = Date().addingTimeInterval(15)
                var freshState: [String: Any] = [:]
                repeat {
                    if !fresh.web.isLoading {
                        freshState = (try? await evaluate(fresh.web, stateBody)) as? [String: Any] ?? [:]
                        if freshState["xhr"] as? String == "200:true" { break }
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                } while Date() < deadline
                print("ScriptCat fresh WebView comparison: \(freshState)")
            }
            throw error
        }
    }

    private func trace(_ stage: String) {
        FileHandle.standardError.write(Data(("ScriptCat native stage: " + stage + "\n").utf8))
    }

    private func loadBackground(_ context: WKWebExtensionContext, _ label: String) async throws {
        // Controller loading and background loading have separate completions.
        // Bound the native callback as well as the subsequent JS service wait.
        var completed = false
        var failure: Error?
        context.loadBackgroundContent { error in
            MainActor.assumeIsolated { failure = error; completed = true }
        }
        try await until("native ScriptCat background loading: \(label)") { completed }
        if let failure { throw failure }
    }

    private func until(_ label: String, _ predicate: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(60)
        var last = ""
        repeat {
            do { if try await predicate() { return } } catch { last = error.localizedDescription }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while Date() < deadline
        throw FixtureFailure("Timed out: \(label). \(last)")
    }

    private func evaluate(_ web: WKWebView, _ body: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await web.callAsyncJavaScript("return await Promise.race([(async () => {\n" + body + "\n})(), new Promise((_, reject) => setTimeout(() => reject(new Error('ScriptCat fixture JavaScript timed out')), 15000))]);",
                                         arguments: arguments, in: nil, contentWorld: .page)
    }

    private func reload(_ tab: Tab, in window: NSWindow) async throws {
        let web = tab.web
        let expected = try XCTUnwrap(web.url).absoluteString
        let marker = UUID().uuidString
        _ = try await evaluate(web, "document.documentElement.setAttribute('data-sx-before-reload', marker); return true;", arguments: ["marker": marker])
        web.reload()
        try await until("a new document completes navigation") {
            let web = tab.web
            if window.contentView !== web {
                web.frame = NSRect(x: 0, y: 0, width: 900, height: 650)
                window.contentView = web
            }
            guard !web.isLoading else { return false }
            return (try await self.evaluate(web, "return location.href === expected && document.readyState === 'complete' && document.documentElement.getAttribute('data-sx-before-reload') !== marker;", arguments: ["marker": marker, "expected": expected])) as? Bool == true
        }
    }

    private func quoted(_ string: String) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed]), encoding: .utf8)!
    }

    private struct FixtureFailure: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }
}
