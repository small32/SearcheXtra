using Microsoft.Web.WebView2.Core;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace SearcheXtra.Windows;

internal sealed record UserScriptPageRegistration(string ExtensionId, string Folder, JsonArray Scripts, JsonArray Worlds);

// A DevTools isolated world has its own JS globals and no extension or WebView host APIs.
// Only this world's context-scoped binding can reach its owning extension's runtime.
internal sealed class UserScriptPageHost : IDisposable
{
    private const string Binding = "__sxUserScriptWorldPost";
    private readonly CoreWebView2 core;
    private readonly Func<string, bool> allowed;
    private readonly Func<string, int, JsonObject, Task<JsonNode?>> message;
    private readonly SemaphoreSlim gate = new(1, 1);
    private readonly Dictionary<string, World> worlds = new(StringComparer.Ordinal);
    private readonly Dictionary<int, Context> contexts = [];
    private readonly Dictionary<int, MainWorldContext> mainContexts = [];
    private readonly Dictionary<(string Session, int Id), (string Frame, string Extension, string Unique)> nativeContexts = [];
    private readonly Dictionary<string, JsonObject> identities = [];
    private readonly Dictionary<string, string> identitySessions = [];
    private readonly Dictionary<string, TaskCompletionSource<JsonObject>> identityWaiters = [];
    private readonly Dictionary<string, Session> sessions = new(StringComparer.Ordinal) { [""] = new("") };
    private readonly List<(string Source, string? World, string Extension)> sources = [];
    private readonly List<Action> unlisten = [];
    private bool disposed;
    private bool initialized;
    private IReadOnlyList<UserScriptPageRegistration> registrations = [];
    private int nextContext;
    internal event Action<int>? ContextClosed;

    private sealed record World(string ExtensionId, string WorldId, string Name, bool Messaging);
    private sealed record Context(int Id, int RemoteId, string Session, string Frame, string Origin, World World);
    private sealed record MainWorldContext(int RemoteId, string Session, string Frame);
    private sealed record Session(string Id) { internal List<string> Scripts { get; } = []; }

    internal UserScriptPageHost(CoreWebView2 core, Func<string, bool> allowed,
        Func<string, int, JsonObject, Task<JsonNode?>> message)
    { this.core = core; this.allowed = allowed; this.message = message; }

    internal async Task InitializeAsync()
    {
        if (initialized || disposed) return;
        initialized = true;
        if (Environment.GetEnvironmentVariable("SEARCHEXTRA_MV3_TEST_ONLY") == "1")
        {
            Listen("Runtime.exceptionThrown", data => File.AppendAllText(Path.Combine(DataStore.Root, "user-scripts-page.log"), "exception " + data.ToJsonString() + "\n"));
            Listen("Runtime.consoleAPICalled", data => File.AppendAllText(Path.Combine(DataStore.Root, "user-scripts-page.log"), "console " + data.ToJsonString() + "\n"));
        }
        Listen("Runtime.executionContextCreated", ContextCreated);
        Listen("Runtime.executionContextDestroyed", ContextDestroyed);
        Listen("Runtime.executionContextsCleared", data => ClearContexts(Text(data, "_session")));
        Listen("Runtime.bindingCalled", BindingCalled);
        Listen("Page.frameNavigated", FrameNavigated);
        Listen("Target.attachedToTarget", TargetAttached);
        Listen("Target.detachedFromTarget", TargetDetached);
        await InitializeSession("");
    }

    internal async Task RefreshAsync(IReadOnlyList<UserScriptPageRegistration> requested)
    {
        if (!initialized && requested.Count == 0) return;
        await InitializeAsync();
        await gate.WaitAsync();
        try
        {
            if (disposed) return;
            var next = requested.Where(item => allowed(item.ExtensionId)).ToArray();
            if (next.Length == registrations.Count && next.Zip(registrations).All(pair =>
                pair.First.ExtensionId == pair.Second.ExtensionId && pair.First.Folder == pair.Second.Folder &&
                JsonNode.DeepEquals(pair.First.Scripts, pair.Second.Scripts) && JsonNode.DeepEquals(pair.First.Worlds, pair.Second.Worlds))) return;
            foreach (var session in sessions.Values.ToArray())
            {
                foreach (var id in session.Scripts) await Call("Page.removeScriptToEvaluateOnNewDocument", new() { ["identifier"] = id }, session.Id);
                session.Scripts.Clear();
            }
            sources.Clear();
            var nextWorlds = new Dictionary<string, World>(StringComparer.Ordinal);
            foreach (var registration in next)
            {
                var configs = registration.Worlds.OfType<JsonObject>().ToDictionary(item => Text(item, "worldId"), StringComparer.Ordinal);
                var worldIds = registration.Scripts.OfType<JsonObject>().Where(script => Text(script, "world", "USER_SCRIPT") != "MAIN")
                    .Select(script => Text(script, "worldId")).Concat(configs.Keys).Append("").Distinct(StringComparer.Ordinal);
                foreach (var worldId in worldIds)
                {
                    configs.TryGetValue(worldId, out var config);
                    var name = WorldName(registration.ExtensionId, worldId);
                    var world = new World(registration.ExtensionId, worldId, name, Flag(config, "messaging"));
                    nextWorlds[name] = world;
                    worlds[name] = world;
                    foreach (var session in sessions.Values.ToArray()) await Call("Runtime.addBinding", new() { ["name"] = Binding, ["executionContextName"] = name }, session.Id);
                    await AddSource(WorldBootstrap(world), name, registration.ExtensionId);
                }
                foreach (var script in registration.Scripts.OfType<JsonObject>())
                {
                    var source = await ScriptSource(registration.Folder, script["js"] as JsonArray);
                    var main = Text(script, "world", "USER_SCRIPT") == "MAIN";
                    await AddSource(RegisteredSource(registration.ExtensionId, script, source), main ? null : WorldName(registration.ExtensionId, Text(script, "worldId")), registration.ExtensionId);
                }
            }
            foreach (var old in worlds.Values.Where(item => !nextWorlds.ContainsKey(item.Name)).ToArray())
            {
                // Disable existing documents too; unregister only removes future injections.
                foreach (var context in contexts.Values.Where(item => item.World.Name == old.Name).ToArray())
                    await Evaluate(context.Id, "globalThis.__sxUserScriptWorldDisable?.()");
            }
            worlds.Clear();
            foreach (var pair in nextWorlds) worlds[pair.Key] = pair.Value;
            registrations = next;
        }
        finally { gate.Release(); }
    }

    internal JsonObject Sender(int contextId)
    {
        if (!contexts.TryGetValue(contextId, out var context)) throw new InvalidOperationException("User-script document is no longer available.");
        var sender = identities.GetValueOrDefault(IdentityKey(context.World.ExtensionId, context.Frame))?.DeepClone() as JsonObject ?? new JsonObject();
        sender["id"] = context.World.ExtensionId;
        sender["worldId"] = context.World.WorldId;
        return sender;
    }

    internal async Task<JsonArray> ExecuteAsync(string extensionId, JsonObject injection)
    {
        if (!allowed(extensionId)) throw new InvalidOperationException("User scripts are not allowed for this extension.");
        if (injection["target"] is not JsonObject target) throw new InvalidOperationException("A user-script target is required.");
        var tabId = target["tabId"]?.GetValue<int>() ?? throw new InvalidOperationException("A target tab is required.");
        var worldId = Text(injection, "worldId");
        var main = Text(injection, "world", "USER_SCRIPT") == "MAIN";
        var frameIds = (target["frameIds"] as JsonArray)?.Select(node => node!.GetValue<int>()).ToHashSet();
        var documentIds = (target["documentIds"] as JsonArray)?.Select(node => node!.GetValue<string>()).ToHashSet();
        var selected = identities.Where(pair => pair.Key.StartsWith(extensionId + ":", StringComparison.Ordinal)
            && pair.Value["tab"]?["id"]?.GetValue<int>() == tabId
            && (documentIds != null ? documentIds.Contains(pair.Value["documentId"]?.GetValue<string>() ?? "")
                : frameIds?.Contains(pair.Value["frameId"]?.GetValue<int>() ?? -1) ?? (Flag(target, "allFrames") || pair.Value["frameId"]?.GetValue<int>() == 0))).ToArray();
        var results = new JsonArray();
        var source = string.Join("\n;\n", (injection["js"] as JsonArray ?? []).OfType<JsonObject>().Select(item => Text(item, "code")));
        foreach (var pair in selected)
        {
            var frame = pair.Key[(extensionId.Length + 1)..];
            var world = worlds.GetValueOrDefault(WorldName(extensionId, worldId));
            if (!main && world == null)
            {
                var name = WorldName(extensionId, worldId);
                worlds[name] = world = new World(extensionId, worldId, name, false);
                foreach (var session in sessions.Values.ToArray()) await Call("Runtime.addBinding", new() { ["name"] = Binding, ["executionContextName"] = name }, session.Id);
            }
            var contextId = main ? await MainContext(frame) : await IsolatedContext(world!, frame);
            var hosts = injection["_hostMatches"] as JsonArray ?? [];
            var permission = JsonNode.Parse(await Evaluate(contextId, "(()=>{" + MatchSource + "return (location.protocol!=='file:'||" + (Flag(injection, "_fileAccess") ? "true" : "false") + ")&&" + hosts.ToJsonString() + ".some(p=>pattern(p,location.href));})()"));
            if (permission?["result"]?["value"]?.GetValue<bool>() != true) throw new InvalidOperationException("The extension does not have access to this document.");
            var evaluated = JsonNode.Parse(await Evaluate(contextId, source, true));
            if (evaluated?["exceptionDetails"] is { } error) throw new InvalidOperationException(error["exception"]?["description"]?.GetValue<string>() ?? "User-script execution failed.");
            results.Add(new JsonObject { ["frameId"] = pair.Value["frameId"]?.DeepClone(), ["documentId"] = pair.Value["documentId"]?.DeepClone(), ["result"] = evaluated?["result"]?["value"]?.DeepClone() });
        }
        return results;
    }

    internal async Task DeliverPortAsync(int contextId, string portId, string type, JsonNode? value, string? error = null)
    {
        if (disposed || !contexts.ContainsKey(contextId)) return;
        try { await Evaluate(contextId, "globalThis.__sxUserScriptWorldPort?.(" + JsonSerializer.Serialize(portId) + "," + JsonSerializer.Serialize(type) + "," + (value?.ToJsonString() ?? "null") + "," + JsonSerializer.Serialize(error) + ")"); }
        catch (Exception failure) when (failure is System.Runtime.InteropServices.COMException or InvalidOperationException) { }
    }

    private async Task InitializeSession(string session)
    {
        await Call("Runtime.enable", new(), session);
        await Call("Page.enable", new(), session);
        await Call("Target.setAutoAttach", new()
        {
            ["autoAttach"] = true, ["waitForDebuggerOnStart"] = true, ["flatten"] = true,
            ["filter"] = new JsonArray(new JsonObject { ["type"] = "iframe", ["exclude"] = false }, new JsonObject { ["exclude"] = true })
        }, session);
    }

    private async void TargetAttached(JsonObject data)
    {
        if (Text(data["targetInfo"] as JsonObject, "type") != "iframe") return;
        var id = Text(data, "sessionId");
        await gate.WaitAsync();
        try
        {
            if (disposed) return;
            var session = new Session(id);
            sessions[id] = session;
            await InitializeSession(id);
            foreach (var world in worlds.Values) await Call("Runtime.addBinding", new() { ["name"] = Binding, ["executionContextName"] = world.Name }, id);
            foreach (var (source, world, extension) in sources) if (allowed(extension)) await AddScript(source, world, session, true);
        }
        catch (Exception error) when (error is System.Runtime.InteropServices.COMException or InvalidOperationException) { }
        finally
        {
            gate.Release();
            try { await Call("Runtime.runIfWaitingForDebugger", new(), id); }
            catch (Exception error) when (error is System.Runtime.InteropServices.COMException or InvalidOperationException) { }
        }
    }

    private void TargetDetached(JsonObject data)
    {
        var session = Text(data, "sessionId");
        sessions.Remove(session); ClearContexts(session);
    }

    private void Listen(string name, Action<JsonObject> receive)
    {
        var receiver = core.GetDevToolsProtocolEventReceiver(name);
        async void Handler(object? sender, CoreWebView2DevToolsProtocolEventReceivedEventArgs args)
        {
            if (disposed) return;
            try
            {
                if (JsonNode.Parse(args.ParameterObjectAsJson) is not JsonObject data) return;
                data["_session"] = args.SessionId ?? "";
                // WinRT dispatch holds its event subscription lock until this
                // callback returns. Reentering DevTools here can deadlock it.
                await Task.Yield();
                if (!disposed) receive(data);
            }
            catch (JsonException) { }
        }
        receiver.DevToolsProtocolEventReceived += Handler;
        unlisten.Add(() => receiver.DevToolsProtocolEventReceived -= Handler);
    }

    private void ContextCreated(JsonObject data)
    {
        if (data["context"] is not JsonObject context || context["auxData"] is not JsonObject auxiliary) return;
        var id = context["id"]!.GetValue<int>();
        var session = Text(data, "_session");
        var frame = Text(auxiliary, "frameId");
        var origin = Text(context, "origin");
        if (Flag(auxiliary, "isDefault")) mainContexts[++nextContext] = new(id, session, frame);
        if (worlds.TryGetValue(Text(context, "name"), out var world)) { var handle = ++nextContext; contexts[handle] = new(handle, id, session, frame, origin, world); }
        if (Uri.TryCreate(origin, UriKind.Absolute, out var extension) && extension.Scheme == "chrome-extension" && allowed(extension.Host))
        {
            var unique = Text(context, "uniqueId");
            nativeContexts[(session, id)] = (frame, extension.Host, unique);
            _ = ReadIdentity(id, session, frame, extension.Host, unique);
        }
    }

    private async Task ReadIdentity(int contextId, string session, string frame, string extensionId, string unique)
    {
        try
        {
            var response = JsonNode.Parse(await EvaluateRemote(contextId, session, "chrome.runtime.sendMessage({__sxUserScriptPageIdentity:true})", true));
            if (response?["result"]?["value"] is not JsonObject sender || sender["tab"]?["id"] == null || !allowed(extensionId) || disposed
                || !nativeContexts.TryGetValue((session, contextId), out var current) || current.Unique != unique) return;
            var key = IdentityKey(extensionId, frame);
            identities[key] = (JsonObject)sender.DeepClone();
            identitySessions[key] = session;
            if (identityWaiters.Remove(key, out var waiting)) waiting.TrySetResult(sender);
        }
        catch (Exception error) when (error is System.Runtime.InteropServices.COMException or InvalidOperationException or JsonException) { }
    }

    private void ContextDestroyed(JsonObject data)
    {
        if (data["executionContextId"] is not JsonValue id) return;
        var session = Text(data, "_session");
        nativeContexts.Remove((session, id.GetValue<int>()));
        foreach (var pair in contexts.Where(pair => pair.Value.RemoteId == id.GetValue<int>() && pair.Value.Session == session).ToArray()) CloseContext(pair.Key);
        foreach (var pair in mainContexts.Where(pair => pair.Value.RemoteId == id.GetValue<int>() && pair.Value.Session == session).ToArray()) mainContexts.Remove(pair.Key);
    }

    private void ClearContexts(string? session = null)
    {
        var frames = contexts.Values.Where(context => session == null || context.Session == session).Select(context => context.Frame)
            .Concat(mainContexts.Values.Where(context => session == null || context.Session == session).Select(context => context.Frame)).ToHashSet();
        foreach (var pair in contexts.Where(pair => session == null || pair.Value.Session == session).ToArray()) CloseContext(pair.Key);
        foreach (var pair in mainContexts.Where(pair => session == null || pair.Value.Session == session).ToArray()) mainContexts.Remove(pair.Key);
        foreach (var key in nativeContexts.Keys.Where(key => session == null || key.Session == session).ToArray()) nativeContexts.Remove(key);
        foreach (var key in identities.Keys.Where(key => session == null || identitySessions.GetValueOrDefault(key) == session).ToArray()) { identities.Remove(key); identitySessions.Remove(key); }
        foreach (var key in identityWaiters.Keys.Where(key => session == null || frames.Any(frame => key.EndsWith(":" + frame, StringComparison.Ordinal))).ToArray())
            if (identityWaiters.Remove(key, out var waiter)) waiter.TrySetCanceled();
    }

    private void CloseContext(int context)
    {
        if (contexts.Remove(context)) ContextClosed?.Invoke(context);
    }

    private void FrameNavigated(JsonObject data)
    {
        if (data["frame"] is not JsonObject frame) return;
        var id = Text(frame, "id");
        foreach (var key in identities.Keys.Where(key => key.EndsWith(":" + id, StringComparison.Ordinal)).ToArray()) { identities.Remove(key); identitySessions.Remove(key); }
        // Blink can keep an iframe's about:blank globals for its first same-origin
        // document. CDP's creation script ran before the real URL was available,
        // so retry the guarded sources in that retained context after commit.
        if (mainContexts.Values.Any(context => context.Frame == id)) _ = RestoreReusedFrameAsync(id);
    }

    private async Task RestoreReusedFrameAsync(string frame)
    {
        await Task.Yield();
        await gate.WaitAsync();
        try
        {
            if (disposed || !mainContexts.Values.Any(context => context.Frame == frame)) return;
            foreach (var (source, worldName, extension) in sources)
            {
                if (!allowed(extension)) continue;
                int context;
                if (worldName == null) context = await MainContext(frame);
                else
                {
                    if (!worlds.TryGetValue(worldName, out var world) || !allowed(world.ExtensionId)) continue;
                    context = await IsolatedContext(world, frame);
                }
                await Evaluate(context, source);
            }
        }
        catch (Exception error) when (error is System.Runtime.InteropServices.COMException or InvalidOperationException) { }
        finally { gate.Release(); }
    }

    private async void BindingCalled(JsonObject data)
    {
        if (Text(data, "name") != Binding || data["executionContextId"] is not JsonValue value) return;
        var context = contexts.Values.FirstOrDefault(context => context.RemoteId == value.GetValue<int>() && context.Session == Text(data, "_session"));
        if (context == null) return;
        string requestId = "";
        try
        {
            if (JsonNode.Parse(Text(data, "payload")) is not JsonObject request) return;
            requestId = Text(request, "id");
            if (!allowed(context.World.ExtensionId) || !worlds.TryGetValue(context.World.Name, out var current) || !current.Messaging) throw new InvalidOperationException("User-script messaging is disabled.");
            var key = IdentityKey(context.World.ExtensionId, context.Frame);
            if (!identities.ContainsKey(key))
            {
                if (!identityWaiters.TryGetValue(key, out var waiting)) identityWaiters[key] = waiting = new(TaskCreationOptions.RunContinuationsAsynchronously);
                await waiting.Task.WaitAsync(TimeSpan.FromSeconds(10));
            }
            if (disposed || !contexts.ContainsKey(context.Id) || !allowed(context.World.ExtensionId)) return;
            var result = await message(context.World.ExtensionId, context.Id, request);
            await Reply(context.Id, requestId, result, null);
        }
        catch (Exception error)
        {
            if (!disposed && requestId.Length != 0)
                try { await Reply(context.Id, requestId, null, error.Message); }
                catch (Exception failure) when (failure is System.Runtime.InteropServices.COMException or InvalidOperationException) { }
        }
    }

    private Task Reply(int context, string id, JsonNode? result, string? error) =>
        Evaluate(context, "globalThis.__sxUserScriptWorldReply?.(" + JsonSerializer.Serialize(id) + "," + (result?.ToJsonString() ?? "null") + "," + JsonSerializer.Serialize(error) + ")");

    private async Task AddSource(string source, string? world, string extension)
    {
        sources.Add((source, world, extension));
        foreach (var session in sessions.Values.ToArray()) await AddScript(source, world, session);
    }

    private async Task AddScript(string source, string? world, Session session, bool runImmediately = false)
    {
        var options = new JsonObject { ["source"] = source, ["runImmediately"] = runImmediately };
        if (world != null) options["worldName"] = world;
        var added = JsonNode.Parse(await Call("Page.addScriptToEvaluateOnNewDocument", options, session.Id));
        if (added?["identifier"]?.GetValue<string>() is { } id) session.Scripts.Add(id);
    }

    private async Task<int> IsolatedContext(World world, string frame)
    {
        var existing = contexts.Values.FirstOrDefault(context => context.Frame == frame && context.World.Name == world.Name);
        if (existing != null) return existing.Id;
        var session = mainContexts.Values.FirstOrDefault(context => context.Frame == frame)?.Session ?? "";
        var created = JsonNode.Parse(await Call("Page.createIsolatedWorld", new() { ["frameId"] = frame, ["worldName"] = world.Name, ["grantUniveralAccess"] = false }, session));
        var remoteId = created?["executionContextId"]?.GetValue<int>() ?? throw new InvalidOperationException("Could not create a user-script world.");
        var context = contexts.Values.FirstOrDefault(context => context.Session == session && context.RemoteId == remoteId);
        if (context == null) { var handle = ++nextContext; contexts[handle] = context = new(handle, remoteId, session, frame, "", world); }
        await Evaluate(context.Id, WorldBootstrap(world));
        return context.Id;
    }

    private Task<int> MainContext(string frame) => Task.FromResult(mainContexts.FirstOrDefault(pair => pair.Value.Frame == frame).Key is > 0 and var id
        ? id : throw new InvalidOperationException("The MAIN execution context is not available."));

    private Task<string> Evaluate(int context, string expression, bool awaitPromise = false)
    {
        if (contexts.TryGetValue(context, out var isolated)) return EvaluateRemote(isolated.RemoteId, isolated.Session, expression, awaitPromise);
        if (mainContexts.TryGetValue(context, out var main)) return EvaluateRemote(main.RemoteId, main.Session, expression, awaitPromise);
        throw new InvalidOperationException("The user-script document is no longer available.");
    }
    private Task<string> EvaluateRemote(int context, string session, string expression, bool awaitPromise = false) =>
        Call("Runtime.evaluate", new() { ["contextId"] = context, ["expression"] = expression, ["awaitPromise"] = awaitPromise, ["returnByValue"] = true }, session);
    private async Task<string> Call(string method, JsonObject args, string session = "") => await core.CallDevToolsProtocolMethodForSessionAsync(session, method, args.ToJsonString());

    private static string WorldName(string extension, string world) => "SearcheXtra.user." + extension + "." + Convert.ToHexString(System.Text.Encoding.UTF8.GetBytes(world));
    private static string IdentityKey(string extension, string frame) => extension + ":" + frame;
    private static string Text(JsonObject? value, string property, string fallback = "") => value?[property]?.GetValue<string>() ?? fallback;
    private static bool Flag(JsonObject? value, string property) => value?[property]?.GetValue<bool>() ?? false;

    private static async Task<string> ScriptSource(string folder, JsonArray? files)
    {
        var result = new List<string>();
        var root = Path.GetFullPath(folder) + Path.DirectorySeparatorChar;
        foreach (var item in files?.OfType<JsonObject>() ?? [])
        {
            if (item["code"] is JsonValue code) { result.Add(code.GetValue<string>()); continue; }
            var path = Path.GetFullPath(Path.Combine(folder, Text(item, "file").TrimStart('/', '\\')));
            if (!path.StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("User-script source must be inside its extension.");
            result.Add(await File.ReadAllTextAsync(path));
        }
        return string.Join("\n;\n", result);
    }

    private static string RegisteredSource(string extension, JsonObject script, string source)
    {
        var options = (JsonObject)script.DeepClone();
        options.Remove("js");
        return "(() => {const s=" + options.ToJsonString() + ";" + MatchSource + "if(!matches(s))return;const marker=" + JsonSerializer.Serialize("SearcheXtra.user.ran." + extension + "." + Text(script, "id")) + ";if(globalThis[marker]===document)return;Object.defineProperty(globalThis,marker,{value:document,configurable:true});const run=()=>{\n" + source + "\n};if(s.runAt==='document_end'){if(document.readyState==='loading')addEventListener('DOMContentLoaded',run,{once:true});else run();}else if(s.runAt==='document_idle'||!s.runAt){if(document.readyState==='complete')setTimeout(run,0);else addEventListener('load',()=>setTimeout(run,0),{once:true});}else run();})();";
    }

    private const string MatchSource = """
        const glob=(p,u)=>new RegExp('^'+p.replace(/[.+^${}()|[\]\\]/g,'\\$&').replace(/\*/g,'.*').replace(/\?/g,'.')+'$').test(u);
        const pattern=(p,u)=>{try{let x=new URL(u);if(p==='<all_urls>')return /^(https?|file|ftp):$/.test(x.protocol);let m=p.match(/^(\*|https?|file|ftp):\/\/([^/]*)(\/.*)$/);if(!m)return false;if(m[1]==='*'?!/^https?:$/.test(x.protocol):x.protocol!==m[1]+':')return false;let h=m[2];if(h!=='*'&&!(h.startsWith('*.')?(x.hostname===h.slice(2)||x.hostname.endsWith(h.slice(1))):x.hostname===h))return false;return glob(m[3],x.pathname+x.search);}catch{return false;}};
        const matches=s=>{if(!s.allFrames&&self!==top)return false;let u=location.href;if(s.matchOriginAsFallback&&/^(about|blob|data):/.test(u)){try{u=parent.location.href}catch{u=document.referrer}}if(u.startsWith('file:')&&!s._fileAccess)return false;return (s._hostMatches||[]).some(p=>pattern(p,u))&&(s.matches||[]).some(p=>pattern(p,u))&&!(s.excludeMatches||[]).some(p=>pattern(p,u))&&(!s.includeGlobs?.length||s.includeGlobs.some(p=>glob(p,u)))&&!(s.excludeGlobs||[]).some(p=>glob(p,u));};
        """;

    private static string WorldBootstrap(World world) => "(() => {const extensionId=" + JsonSerializer.Serialize(world.ExtensionId) + ",enabled=" + (world.Messaging ? "true" : "false") + ";" + RuntimeSource + "})();";
    private const string RuntimeSource = """
        if(globalThis.__sxUserScriptWorldState){globalThis.__sxUserScriptWorldState.enabled=enabled;return;}
        const state={enabled},pending=new Map(),ports=new Map();let seq=0,lastError;
        Object.defineProperty(globalThis,'__sxUserScriptWorldState',{value:state});
        const event=()=>{const listeners=new Set();return {addListener:f=>listeners.add(f),removeListener:f=>listeners.delete(f),hasListener:f=>listeners.has(f),hasListeners:()=>listeners.size,fire:(...a)=>{for(const f of [...listeners])f(...a);}};};
        const ask=o=>new Promise((resolve,reject)=>{if(!state.enabled)return reject(new Error('User-script messaging is disabled.'));const id=String(++seq);pending.set(id,{resolve,reject});try{__sxUserScriptWorldPost(JSON.stringify({...o,id}));}catch(e){pending.delete(id);reject(e);}});
        Object.defineProperty(globalThis,'__sxUserScriptWorldReply',{value:(id,value,error)=>{const p=pending.get(id);if(!p)return;pending.delete(id);if(error)p.reject(new Error(error));else p.resolve(value);}});
        Object.defineProperty(globalThis,'__sxUserScriptWorldPort',{value:(id,type,value,error)=>{const port=ports.get(id);if(!port)return;if(type==='message')port.onMessage.fire(value,port);else{ports.delete(id);lastError=error?{message:error}:undefined;port.onDisconnect.fire(port);lastError=undefined;}}});
        Object.defineProperty(globalThis,'__sxUserScriptWorldDisable',{value:()=>{state.enabled=false;for(const p of pending.values())p.reject(new Error('User scripts are disabled.'));pending.clear();for(const p of ports.values())p.onDisconnect.fire(p);ports.clear();}});
        if(!enabled)return;
        const runtime={id:extensionId,get lastError(){return lastError;},getURL:p=>'chrome-extension://'+extensionId+'/'+String(p).replace(/^\//,''),
          sendMessage(...a){const callback=typeof a[a.length-1]==='function'?a.pop():null;if(typeof a[0]==='string'&&a.length>1&&a[0]===extensionId)a.shift();const promise=ask({op:'sendMessage',message:a[0]});if(!callback)return promise;promise.then(callback,e=>{lastError={message:e.message};try{callback();}finally{lastError=undefined;}});},
          connect(...a){if(typeof a[0]==='string'){if(a.shift()!==extensionId)throw new Error('User scripts can only connect to their owning extension.');}const options=a[0]||{},portId='p'+(++seq);let queue;const enqueue=operation=>{queue=queue.then(()=>ask(operation));queue.catch(e=>globalThis.__sxUserScriptWorldPort(portId,'disconnect',null,e.message));};const port={name:options.name||'',onMessage:event(),onDisconnect:event(),postMessage:message=>{if(!ports.has(portId))throw new Error('The user-script port is disconnected.');enqueue({op:'portMessage',portId,message});},disconnect:()=>{if(!ports.has(portId))return;ports.delete(portId);enqueue({op:'portDisconnect',portId});}};ports.set(portId,port);queue=ask({op:'connect',portId,name:port.name});queue.catch(e=>globalThis.__sxUserScriptWorldPort(portId,'disconnect',null,e.message));return port;}};
        if(!globalThis.chrome)globalThis.chrome={};Object.defineProperty(chrome,'runtime',{configurable:true,value:runtime});
        """;

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        foreach (var stop in unlisten) stop();
        unlisten.Clear(); ClearContexts();
        sources.Clear(); worlds.Clear(); sessions.Clear(); registrations = [];
    }
}
