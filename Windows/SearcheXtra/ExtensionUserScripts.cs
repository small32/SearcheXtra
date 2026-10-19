using Microsoft.Web.WebView2.Core;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace SearcheXtra.Windows;

// Native extension pages carry messages to the worker. Untrusted webpage
// JavaScript never receives either this bridge's token or extension privileges.
internal static class ExtensionUserScripts
{
    private sealed class Entry(InstalledExtension item, UserScriptStore store, string token)
    {
        public InstalledExtension Item = item;
        public readonly string Version = item.Version;
        public string Folder = item.Folder;
        public UserScriptStore Store = store;
        public string Token = token;
        public CoreWebView2Controller? Controller;
        public CoreWebView2? Core;
        public TaskCompletionSource? Ready;
        public readonly SemaphoreSlim Requests = new(1, 1);
        public readonly Dictionary<string, (TaskCompletionSource<JsonNode?> Reply, UserScriptPageHost Host, int Context)> Replies = [];
        public readonly Dictionary<string, (UserScriptPageHost Host, int Context, string LocalId)> Ports = [];
        public string[] Origins = RequiredOrigins(item.Folder);
        public bool FileAccess;
    }
    private sealed class Profile(CoreWebView2 source, BrowserSettings settings)
    {
        public readonly string Name = source.Profile.ProfileName;
        public readonly CoreWebView2Environment Environment = source.Environment;
        public readonly CoreWebView2Profile Native = source.Profile;
        public readonly BrowserSettings Settings = settings;
        public readonly Dictionary<string, Entry> Entries = [];
        public readonly HashSet<string> Failures = [];
        public readonly SemaphoreSlim Setup = new(1, 1);
    }
    private static readonly Dictionary<string, Profile> Profiles = [];
    private static readonly Dictionary<UserScriptPageHost, string> Pages = [];
    private static readonly Dictionary<string, (string Token, bool Prepared)> Packages = new(StringComparer.OrdinalIgnoreCase);
    private static readonly SemaphoreSlim Preparation = new(1, 1);
    private static IntPtr hiddenWindow;
    private static void Trace(string text)
    {
        if (Environment.GetEnvironmentVariable("SEARCHEXTRA_MV3_TEST_ONLY") == "1")
            File.AppendAllText(Path.Combine(DataStore.Root, "user-scripts-host.log"), DateTime.UtcNow.ToString("O") + " " + text + "\n");
    }

    internal static async Task<bool> PrepareAsync(string folder, bool reload = false)
    {
        folder = Path.GetFullPath(folder);
        await Preparation.WaitAsync();
        try
        {
            // Package contents change on install/reload, not when another tab
            // joins the profile. Avoid rescanning every extension per tab.
            if (!reload && Packages.TryGetValue(folder, out var package)) return package.Prepared;
            var token = ExtensionUserScriptsPackage.TokenFor(folder);
            var prepared = await Task.Run(() => ExtensionUserScriptsPackage.Prepare(folder, token));
            Packages[folder] = (token, prepared);
            return prepared;
        }
        finally { Preparation.Release(); }
    }

    internal static bool Allowed(string profile, string id) => Profiles.TryGetValue(profile, out var owner) &&
        owner.Entries.TryGetValue(id, out var entry) && entry.Item.Enabled && entry.Item.AllowUserScripts;
    internal static bool Failed(string id) => Profiles.Values.Any(profile => profile.Failures.Contains(id));

    internal static async Task<UserScriptPageHost> AttachAsync(CoreWebView2 core, BrowserSettings settings)
    {
        UserScriptPageHost? host = null;
        var name = core.Profile.ProfileName;
        host = new(core, id => Allowed(name, id), (id, context, request) => RouteWorldAsync(name, host!, id, context, request));
        Pages[host] = name;
        host.ContextClosed += context => ForgetContext(host, context);
        try
        {
            await EnsureAsync(core, settings);
            await host.RefreshAsync(Snapshots(name));
            return host;
        }
        catch { Detach(host); throw; }
    }

    internal static async Task EnsureAsync(CoreWebView2 core, BrowserSettings settings)
    {
        if (core.Profile.IsInPrivateModeEnabled) return;
        var name = core.Profile.ProfileName;
        if (!Profiles.TryGetValue(name, out var profile)) Profiles[name] = profile = new(core, settings);
        await EnsureProfileAsync(profile);
    }

    private static async Task EnsureProfileAsync(Profile profile)
    {
        var settings = profile.Settings;
        var name = profile.Name;
        await profile.Setup.WaitAsync();
        try
        {
            if (!Profiles.TryGetValue(name, out var current) || current != profile) return;
            foreach (var item in settings.Extensions.ToArray())
            {
                try
                {
                    var folder = item.Folder;
                    var prepared = item.Enabled && Directory.Exists(folder) && await PrepareAsync(folder);
                    if (!settings.Extensions.Contains(item) || item.Folder != folder) continue;
                    if (!item.Enabled || !prepared)
                    {
                        if (profile.Entries.Remove(item.Id, out var obsolete)) CloseBridge(obsolete);
                        continue;
                    }
                    if (profile.Entries.TryGetValue(item.Id, out var previous) && previous.Version != item.Version)
                    {
                        profile.Entries.Remove(item.Id);
                        CloseBridge(previous);
                        await previous.Requests.WaitAsync();
                        previous.Requests.Release();
                        if (!settings.Extensions.Contains(item) || !item.Enabled || item.Folder != folder) continue;
                    }
                    if (!profile.Entries.TryGetValue(item.Id, out var entry))
                        profile.Entries[item.Id] = entry = new(item, new UserScriptStore(DataStore.Root, name, item.Id, item.Version), Packages[Path.GetFullPath(item.Folder)].Token);
                    if (entry.Folder != item.Folder || entry.Token != Packages[Path.GetFullPath(item.Folder)].Token) CloseBridge(entry);
                    entry.Item = item;
                    entry.Folder = item.Folder;
                    entry.Token = Packages[Path.GetFullPath(item.Folder)].Token;
                    if (entry.Controller == null) await OpenBridgeAsync(profile, entry);
                    profile.Failures.Remove(item.Id);
                }
                catch (Exception error) when (error is InvalidDataException or IOException or JsonException or UnauthorizedAccessException or COMException or TimeoutException)
                {
                    if (profile.Entries.Remove(item.Id, out var failed)) CloseBridge(failed);
                    profile.Failures.Add(item.Id);
                    System.Diagnostics.Debug.WriteLine("Could not load extension user scripts: " + error.Message);
                }
            }
            foreach (var id in profile.Entries.Keys.Where(id => !settings.Extensions.Any(i => i.Id == id && i.Enabled)).ToArray())
            {
                CloseBridge(profile.Entries[id]); profile.Entries.Remove(id);
            }
            profile.Failures.RemoveWhere(id => !settings.Extensions.Any(item => item.Id == id && item.Enabled));
        }
        finally { profile.Setup.Release(); }
        await RefreshAsync(name);
    }

    private static async Task OpenBridgeAsync(Profile profile, Entry entry)
    {
        if (hiddenWindow == IntPtr.Zero)
        {
            hiddenWindow = CreateWindowEx(0, "STATIC", "SearcheXtra extension scripts", 0, 0, 0, 1, 1, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            if (hiddenWindow == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
        var environment = profile.Environment;
        var options = environment.CreateCoreWebView2ControllerOptions(); options.ProfileName = profile.Name;
        var controller = await environment.CreateCoreWebView2ControllerAsync(CoreWebView2ControllerWindowReference.CreateFromWindowHandle(unchecked((ulong)hiddenWindow.ToInt64())), options);
        if (!Profiles.TryGetValue(profile.Name, out var owner) || owner != profile || !entry.Item.Enabled ||
            !profile.Entries.TryGetValue(entry.Item.Id, out var activeEntry) || activeEntry != entry)
        { controller.Close(); return; }
        controller.IsVisible = false;
        entry.Controller = controller;
        entry.Ready = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var core = controller.CoreWebView2;
        // Keep the WinRT event source alive with its controller. The projected
        // CoreWebView2 getter does not keep this managed wrapper rooted.
        entry.Core = core;
        Trace("controller profile=" + core.Profile.ProfileName + " expected=" + profile.Name + " private=" + core.Profile.IsInPrivateModeEnabled);
        var address = $"chrome-extension://{entry.Item.Id}/{ExtensionUserScriptsPackage.BridgePath}";
        core.NewWindowRequested += (_, e) => e.Handled = true;
        core.NavigationStarting += async (_, e) =>
        {
            if (e.Uri.StartsWith(address, StringComparison.Ordinal)) return;
            e.Cancel = true;
            Trace("bridge navigation " + e.Uri + " ready=" + (entry.Ready?.Task.IsCompletedSuccessfully == true));
            // WebView2 sends the hidden page to its new-tab URL when the
            // extension reloads. Its old runtime object then remains present
            // but can no longer receive messages from the new worker.
            await Task.Yield();
            if (entry.Controller != controller) return;
            CloseBridge(entry);
            try
            {
                if (!IsCurrent(profile, entry)) return;
                await PrepareAsync(entry.Folder, reload: true);
                await entry.Requests.WaitAsync();
                try
                {
                    if (!IsCurrent(profile, entry)) return;
                    // Chromium treats a reload of an unpacked extension as a
                    // new installation and clears scripts and every user world.
                    // Keep its native storage and IndexedDB installation intact.
                    entry.Store.Reset();
                    await entry.Store.SaveAsync();
                }
                finally { entry.Requests.Release(); }
                var native = (await profile.Native.GetBrowserExtensionsAsync()).FirstOrDefault(extension => extension.Id == entry.Item.Id);
                if (native?.IsEnabled == true && IsCurrent(profile, entry)) await EnsureProfileAsync(profile);
            }
            catch (Exception error) when (error is COMException or InvalidOperationException or IOException or UnauthorizedAccessException)
            { System.Diagnostics.Debug.WriteLine("Could not reconnect extension user scripts: " + error.Message); }
        };
        core.WebMessageReceived += async (_, e) =>
        {
            if (entry.Controller != controller || !Uri.TryCreate(e.Source, UriKind.Absolute, out var source) || source.GetLeftPart(UriPartial.Path) != address) return;
            JsonObject? message;
            try { message = JsonNode.Parse(e.WebMessageAsJson) as JsonObject; }
            catch (JsonException) { return; }
            if (message?["token"]?.GetValue<string>() != entry.Token || message["extensionId"]?.GetValue<string>() != entry.Item.Id) return;
            // Leave native event dispatch before invoking WebView2 again.
            await Task.Yield();
            if (entry.Controller != controller) return;
            try { await BridgeMessageAsync(profile, entry, message); }
            catch (Exception error) { Trace("bridge error " + error.Message); System.Diagnostics.Debug.WriteLine("User-script bridge: " + error.Message); }
        };
        core.Navigate(address + "?session=" + entry.Token);
        await entry.Ready.Task.WaitAsync(TimeSpan.FromSeconds(20));
    }

    private static async Task BridgeMessageAsync(Profile profile, Entry entry, JsonObject message)
    {
        switch (message["kind"]?.GetValue<string>())
        {
            case "extensionUserScriptsReady":
                Trace("bridge ready " + entry.Item.Id);
                entry.Origins = message["origins"] is JsonArray origins ? UserScriptStore.Strings(origins) : RequiredOrigins(entry.Item.Folder);
                entry.FileAccess = message["fileAccess"]?.GetValue<bool>() == true;
                entry.Ready?.TrySetResult();
                await RefreshAsync(profile.Name);
                return;
            case "extensionUserScriptsEventResult":
                if (entry.Replies.Remove(message["eventId"]!.GetValue<string>(), out var reply))
                {
                    if (message["error"] != null) reply.Reply.TrySetException(new InvalidOperationException(message["error"]!.GetValue<string>()));
                    else reply.Reply.TrySetResult(message["result"]?.DeepClone());
                }
                return;
            case "extensionUserScriptsPortMessage":
            case "extensionUserScriptsPortDisconnect":
                if (entry.Ports.TryGetValue(message["portId"]!.GetValue<string>(), out var peer))
                {
                    var disconnect = message["kind"]!.GetValue<string>() == "extensionUserScriptsPortDisconnect";
                    await peer.Host.DeliverPortAsync(peer.Context, peer.LocalId, disconnect ? "disconnect" : "message", message["message"]?.DeepClone(), message["error"]?.GetValue<string>());
                    if (disconnect) entry.Ports.Remove(message["portId"]!.GetValue<string>());
                }
                return;
            case "extensionUserScripts":
                var id = message["requestId"]!.GetValue<string>();
                Trace("request " + message["api"]?.GetValue<string>());
                JsonNode? result = null; string? error = null;
                try { result = await ApiAsync(profile, entry, message["api"]!.GetValue<string>(), message["args"] as JsonArray ?? []); }
                catch (Exception ex) { error = ex.Message; Trace("request error " + ex); }
                await PostAsync(entry, "__searchextraUserScriptsReply", new JsonObject { ["requestId"] = id, ["result"] = result, ["error"] = error });
                return;
        }
    }

    private static async Task<JsonNode?> ApiAsync(Profile profile, Entry entry, string api, JsonArray args)
    {
        if (api == "isAllowed") return JsonValue.Create(IsActive(profile, entry));
        var bridge = entry.Core;
        if (!IsActive(profile, entry)) throw new InvalidOperationException("User scripts are disabled. Enable Allow user scripts in this extension's details.");
        if (api == "execute")
        {
            var injection = (JsonObject)(args.FirstOrDefault()?.DeepClone() ?? throw new InvalidDataException("Missing user-script injection."));
            UserScriptStore.ValidateExecution(injection);
            ResolveFiles(injection, entry.Item.Folder);
            injection["_hostMatches"] = new JsonArray(entry.Origins.Select(s => (JsonNode?)JsonValue.Create(s)).ToArray());
            injection["_fileAccess"] = entry.FileAccess;
            var results = new JsonArray();
            foreach (var page in Pages.Where(p => p.Value == profile.Name).Select(p => p.Key).ToArray())
                foreach (var item in await page.ExecuteAsync(entry.Item.Id, injection)) results.Add(item?.DeepClone());
            if (results.Count == 0) throw new InvalidOperationException("No permitted target frame was found.");
            return results;
        }
        await entry.Requests.WaitAsync();
        try
        {
            if (!IsActive(profile, entry) || entry.Core != bridge) throw new InvalidOperationException("The extension was reloaded, removed or user scripts were disabled.");
            var result = entry.Store.Invoke(api, args);
            if (api is not ("getScripts" or "getWorldConfigurations"))
            {
                await entry.Store.SaveAsync();
                await RefreshAsync(profile.Name);
            }
            return result;
        }
        finally { entry.Requests.Release(); }
    }

    private static bool IsActive(Profile profile, Entry entry) => entry.Item.Enabled && entry.Item.AllowUserScripts &&
        profile.Entries.TryGetValue(entry.Item.Id, out var current) && current == entry;

    private static bool IsCurrent(Profile profile, Entry entry) => entry.Item.Enabled &&
        Profiles.TryGetValue(profile.Name, out var owner) && owner == profile &&
        profile.Entries.TryGetValue(entry.Item.Id, out var current) && current == entry;

    internal static IReadOnlyList<UserScriptPageRegistration> Snapshots(string profile)
    {
        if (!Profiles.TryGetValue(profile, out var owner)) return [];
        return owner.Entries.Values.Where(e => e.Item.Enabled && e.Item.AllowUserScripts).Select(entry =>
        {
            var scripts = (JsonArray)entry.Store.Scripts.DeepClone();
            foreach (var script in scripts.OfType<JsonObject>())
            {
                script["_hostMatches"] = new JsonArray(entry.Origins.Select(s => (JsonNode?)JsonValue.Create(s)).ToArray());
                script["_fileAccess"] = entry.FileAccess;
            }
            return new UserScriptPageRegistration(entry.Item.Id, entry.Item.Folder, scripts, (JsonArray)entry.Store.Worlds.DeepClone());
        }).ToArray();
    }

    internal static async Task RefreshAsync(string profile)
    {
        var snapshot = Snapshots(profile);
        foreach (var page in Pages.Where(p => p.Value == profile).Select(p => p.Key).ToArray()) await page.RefreshAsync(snapshot);
    }

    private static async Task<JsonNode?> RouteWorldAsync(string profile, UserScriptPageHost page, string id, int context, JsonObject request)
    {
        if (!Allowed(profile, id)) throw new InvalidOperationException("User scripts are disabled.");
        var entry = Profiles[profile].Entries[id];
        var sender = page.Sender(context);
        Trace("world " + request["op"]?.GetValue<string>() + " " + id);
        switch (request["op"]?.GetValue<string>())
        {
            case "sendMessage":
                var eventId = Guid.NewGuid().ToString("N");
                var reply = new TaskCompletionSource<JsonNode?>(TaskCreationOptions.RunContinuationsAsynchronously);
                entry.Replies[eventId] = (reply, page, context);
                try
                {
                    await PostAsync(entry, "__searchextraUserScriptsEvent", new JsonObject { ["type"] = "message", ["eventId"] = eventId, ["message"] = request["message"]?.DeepClone(), ["sender"] = sender });
                    return await reply.Task.WaitAsync(TimeSpan.FromMinutes(5));
                }
                finally { entry.Replies.Remove(eventId); }
            case "connect":
                var localId = request["portId"]!.GetValue<string>();
                var portId = Guid.NewGuid().ToString("N");
                entry.Ports[portId] = (page, context, localId);
                await PostAsync(entry, "__searchextraUserScriptsEvent", new JsonObject { ["type"] = "connect", ["portId"] = portId, ["name"] = request["name"]?.DeepClone(), ["sender"] = sender });
                return null;
            case "portMessage":
            case "portDisconnect":
                var peer = entry.Ports.FirstOrDefault(pair => pair.Value.Host == page && pair.Value.Context == context && pair.Value.LocalId == request["portId"]?.GetValue<string>());
                if (peer.Key == null) throw new InvalidOperationException("The user-script port is disconnected.");
                var closing = request["op"]!.GetValue<string>() == "portDisconnect";
                await PostAsync(entry, "__searchextraUserScriptsEvent", new JsonObject { ["type"] = closing ? "portDisconnect" : "portMessage", ["portId"] = peer.Key, ["message"] = request["message"]?.DeepClone() });
                if (closing) entry.Ports.Remove(peer.Key);
                return null;
            default: throw new InvalidOperationException("Unknown user-script message operation.");
        }
    }

    private static async Task PostAsync(Entry entry, string method, JsonObject value)
    {
        var core = entry.Core ?? throw new InvalidOperationException("The user-script extension bridge is closed.");
        await core.ExecuteScriptAsync("globalThis." + method + "(" + value.ToJsonString() + ")");
    }

    internal static async Task RestartAsync(string id, BrowserSettings settings)
    {
        foreach (var profile in Profiles.Values.ToArray())
        {
            if (profile.Entries.TryGetValue(id, out var entry)) CloseBridge(entry);
            var native = (await profile.Native.GetBrowserExtensionsAsync()).FirstOrDefault(e => e.Id == id);
            if (native != null && settings.Extensions.FirstOrDefault(e => e.Id == id)?.Enabled == true)
            { await native.EnableAsync(false); await native.EnableAsync(true); }
            await EnsureProfileAsync(profile);
        }
    }

    internal static async Task SynchronizeAsync()
    {
        foreach (var profile in Profiles.Values.ToArray()) await EnsureProfileAsync(profile);
    }

    internal static void Detach(UserScriptPageHost page)
    {
        Pages.Remove(page, out var name); page.Dispose();
        foreach (var profile in Profiles.Values)
            foreach (var entry in profile.Entries.Values)
                foreach (var port in entry.Ports.Where(p => p.Value.Host == page).Select(p => p.Key).ToArray()) entry.Ports.Remove(port);
        // A space/profile with no pages must not keep its hidden extension
        // controllers alive until the entire browser is closed.
        if (name != null && !Pages.Values.Contains(name) && Profiles.Remove(name, out var unused))
            foreach (var entry in unused.Entries.Values) CloseBridge(entry);
        if (Pages.Count != 0) return;
        foreach (var profile in Profiles.Values) foreach (var entry in profile.Entries.Values) CloseBridge(entry);
        Profiles.Clear();
        if (hiddenWindow != IntPtr.Zero) { DestroyWindow(hiddenWindow); hiddenWindow = IntPtr.Zero; }
    }

    private static void ForgetContext(UserScriptPageHost page, int context)
    {
        foreach (var profile in Profiles.Values)
            foreach (var entry in profile.Entries.Values)
            {
                foreach (var id in entry.Replies.Where(p => p.Value.Host == page && p.Value.Context == context).Select(p => p.Key).ToArray())
                    if (entry.Replies.Remove(id, out var pending)) pending.Reply.TrySetException(new InvalidOperationException("The source frame was closed."));
                foreach (var id in entry.Ports.Where(p => p.Value.Host == page && p.Value.Context == context).Select(p => p.Key).ToArray())
                {
                    entry.Ports.Remove(id);
                    _ = DisconnectPortAsync(entry, id);
                }
            }
    }

    private static async Task DisconnectPortAsync(Entry entry, string port)
    {
        try { await PostAsync(entry, "__searchextraUserScriptsEvent", new JsonObject { ["type"] = "portDisconnect", ["portId"] = port }); }
        catch (Exception error) when (error is COMException or InvalidOperationException) { }
    }

    internal static async Task RemovedAsync(string id, BrowserSettings settings, Func<Task> removeNative)
    {
        if (settings.Extensions.FirstOrDefault(item => item.Id == id) is { } removed) Packages.Remove(Path.GetFullPath(removed.Folder));
        var profiles = Profiles.Keys.Concat(settings.SpaceProfiles.Values).Concat(settings.ProfileExtensionFolders.Keys.Where(k => k.EndsWith(":regular", StringComparison.Ordinal)).Select(k => k[..^8])).Append("SearcheXtra").Distinct().ToArray();
        foreach (var profile in Profiles.Values.ToArray())
        {
            profile.Failures.Remove(id);
            if (profile.Entries.Remove(id, out var entry))
            {
                CloseBridge(entry);
                await entry.Requests.WaitAsync();
                entry.Requests.Release();
            }
            await RefreshAsync(profile.Name);
        }
        await removeNative();
        foreach (var name in profiles) UserScriptStore.Delete(DataStore.Root, name, id);
    }

    private static void CloseBridge(Entry entry)
    {
        var controller = entry.Controller; entry.Controller = null; controller?.Close(); entry.Core = null;
        entry.Ready?.TrySetException(new IOException("The extension was reloaded or disabled.")); entry.Ready = null;
        foreach (var reply in entry.Replies.Values) reply.Reply.TrySetException(new InvalidOperationException("The extension was reloaded or disabled."));
        entry.Replies.Clear();
        foreach (var port in entry.Ports.Values) _ = port.Host.DeliverPortAsync(port.Context, port.LocalId, "disconnect", null);
        entry.Ports.Clear();
    }

    private static string[] RequiredOrigins(string folder)
    {
        var manifest = JsonNode.Parse(File.ReadAllText(Path.Combine(folder, "manifest.json")))!.AsObject();
        return (manifest["host_permissions"] as JsonArray ?? []).Concat(manifest["permissions"] as JsonArray ?? [])
            .OfType<JsonValue>().Select(n => n.GetValue<string>()).Where(s => s == "<all_urls>" || s.Contains("://")).Distinct().ToArray();
    }

    private static void ResolveFiles(JsonObject injection, string folder)
    {
        var sources = injection["js"] as JsonArray ?? throw new InvalidDataException("Missing user-script sources.");
        var root = Path.GetFullPath(folder) + Path.DirectorySeparatorChar;
        foreach (var source in sources.OfType<JsonObject>())
        {
            if (source["file"] is not JsonNode file) continue;
            var path = Path.GetFullPath(Path.Combine(folder, file.GetValue<string>().TrimStart('/').Replace('/', Path.DirectorySeparatorChar)));
            if (!path.StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("User-script file is outside its extension.");
            source.Remove("file"); source["code"] = File.ReadAllText(path);
        }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowEx(uint exStyle, string className, string name, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr parameter);
    [DllImport("user32.dll")]
    private static extern bool DestroyWindow(IntPtr window);
}
