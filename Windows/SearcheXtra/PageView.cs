using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using System.Text.Json;

namespace SearcheXtra.Windows;

public sealed partial class PageView : IDisposable
{
    private static Task<CoreWebView2Environment>? environment;
    private readonly BrowserTab tab;
    private readonly DataStore store;
    private readonly Action changed;
    private readonly Action<string> open;
    private readonly bool recordVisits;
    private Task? initialization;
    private bool disposed;
    private readonly CancellationTokenSource lifetime = new();
    private string? documentScript, documentScriptSource;
    private readonly SemaphoreSlim ScriptGate = new(1, 1);
    private CoreWebView2DevToolsProtocolEventReceiver? securityReceiver;
    public WebView2 Control { get; } = new() { Visibility = Visibility.Collapsed };
    public Window? FloatingWindow { get; set; }
    public bool IsDisposed => disposed;
    internal CancellationToken Lifetime => lifetime.Token;
    // WebView2 exposes no API for granting extensions access to an InPrivate profile.
    internal static bool SupportsPrivateExtensions => false;
    internal string WebsiteIcon { get; private set; } = "";
    public event Action? WebsiteIconChanged;
    public event Action<DownloadItem>? DownloadStarted;
    public event Func<string, Task>? StoreInstallRequested;
    public event Func<CoreWebView2PermissionRequestedEventArgs, Task>? PermissionRequested;
    public event Func<CoreWebView2DownloadStartingEventArgs, Task>? DownloadLocationRequested;
    public event Action<string>? PreviewRequested;
    public event Action<string>? HoveredLink;
    public event Func<Login, Task>? PasswordOffered;
    public event Func<string, Task<CoreWebView2>>? NewWindowTarget;
    public event Action<string, bool>? OpenLinkRequested;

    public PageView(BrowserTab tab, DataStore store, Action changed, Action<string> open, bool recordVisits = true)
    { this.tab = tab; this.store = store; this.changed = changed; this.open = open; this.recordVisits = recordVisits; }

    private static Task<CoreWebView2Environment> EnvironmentAsync() => environment ??= CoreWebView2Environment.CreateWithOptionsAsync("", Path.Combine(DataStore.Root, "WebView2"), new CoreWebView2EnvironmentOptions { AreBrowserExtensionsEnabled = true, EnableTrackingPrevention = true }).AsTask();
    public Task InitializeAsync() => initialization ??= InitializeCoreAsync();
    public string ConnectionSecurityState { get; private set; } = "unknown";
    private async Task InitializeCoreAsync()
    {
        var env = await EnvironmentAsync();
        if (disposed) return;
        var options = env.CreateCoreWebView2ControllerOptions();
        options.ProfileName = ProfileName(store.Settings, tab.Space);
        options.IsInPrivateModeEnabled = tab.IsPrivate;
        await Control.EnsureCoreWebView2Async(env, options);
        if (disposed) return;
        var core = Control.CoreWebView2;
        securityReceiver = core.GetDevToolsProtocolEventReceiver("Security.visibleSecurityStateChanged");
        securityReceiver.DevToolsProtocolEventReceived += (_, e) =>
        {
            using var data = JsonDocument.Parse(e.ParameterObjectAsJson);
            ConnectionSecurityState = data.RootElement.GetProperty("visibleSecurityState").GetProperty("securityState").GetString() ?? "unknown";
        };
        await core.CallDevToolsProtocolMethodAsync("Security.enable", "{}");
        core.Settings.IsStatusBarEnabled = false;
        core.Settings.IsPasswordAutosaveEnabled = !tab.IsPrivate && store.Settings.SavesPasswords;
        core.Settings.IsGeneralAutofillEnabled = !tab.IsPrivate && store.Settings.FillsPasswords;
        core.Profile.PreferredTrackingPreventionLevel = store.Settings.PreventTracking ? CoreWebView2TrackingPreventionLevel.Balanced : CoreWebView2TrackingPreventionLevel.None;
        core.Settings.IsSwipeNavigationEnabled = true;
        core.NavigationStarting += NavigationStarting;
        core.NavigationCompleted += NavigationCompleted;
        core.DocumentTitleChanged += TitleChanged;
        core.SourceChanged += SourceChanged;
        core.NewWindowRequested += NewWindowRequested;
        core.ContextMenuRequested += ContextMenuRequested;
        core.DownloadStarting += DownloadStarting;
        core.WebMessageReceived += MessageReceived;
        core.FrameCreated += (_,args)=>BindFlowDragFrame(args.Frame);
        core.ProcessFailed += ProcessFailed;
        core.FaviconChanged += FaviconChanged;
        core.PermissionRequested += CorePermissionRequested;
        core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
        core.WebResourceRequested += ResourceRequested;
        foreach (var extension in await core.Profile.GetBrowserExtensionsAsync()) if (store.Settings.RemovedExtensionIds.Contains(extension.Id)) await extension.RemoveAsync();
        ApplySettings();
        await UpdateDocumentScriptAsync();
        if (!tab.IsPrivate || SupportsPrivateExtensions && store.Settings.ExtensionsInPrivate)
        {
            await SynchronizeExtensionsAsync(core.Profile, store.Settings);
            foreach (var folder in store.Settings.ExtensionFolders.Where(folder => store.Settings.Extensions.All(item => item.Folder != folder)).ToArray())
            {
                if (!Directory.Exists(folder)) continue;
                try { await Task.Run(() => CrxInstaller.ValidateFolder(folder)); await core.Profile.AddBrowserExtensionAsync(folder); }
                catch { /* Legacy imports must not prevent browsing. */ }
            }
        }
        if (!disposed && tab.Url.Length > 0) Navigate(tab.Url);
    }
    private static readonly SemaphoreSlim ExtensionGate = new(1, 1);
    public static async Task SynchronizeExtensionsAsync(CoreWebView2Profile profile, BrowserSettings settings)
    {
        await ExtensionGate.WaitAsync();
        try
        {
            var key = profile.ProfileName + (profile.IsInPrivateModeEnabled ? ":private" : ":regular");
            if (!settings.ProfileExtensionFolders.TryGetValue(key, out var folders)) settings.ProfileExtensionFolders[key] = folders = [];
            var installed = (await profile.GetBrowserExtensionsAsync()).ToDictionary(extension => extension.Id);
            foreach (var item in settings.Extensions.ToArray())
            {
                if (!Directory.Exists(item.Folder)) continue;
                try
                {
                    installed.TryGetValue(item.Id, out var extension);
                    if (extension == null || folders.GetValueOrDefault(item.Id) != item.Folder)
                    {
                        await Task.Run(() => CrxInstaller.ValidateFolder(item.Folder));
                        if (extension != null) await extension.RemoveAsync();
                        extension = await profile.AddBrowserExtensionAsync(item.Folder);
                        folders[item.Id] = item.Folder;
                    }
                    if (extension.IsEnabled != item.Enabled) await extension.EnableAsync(item.Enabled);
                }
                catch { /* Keep browsing available if an extension is incompatible. */ }
            }
        }
        finally { ExtensionGate.Release(); }
    }
    public void Navigate(string url)
    {
        if (disposed) return;
        if (tab.IsPrivate && !SupportsPrivateExtensions && url.StartsWith("chrome-extension://", StringComparison.OrdinalIgnoreCase)) url = "about:blank";
        Control.CoreWebView2?.Navigate(url);
    }
    public static string ProfileName(BrowserSettings settings, string space)
    {
        if (!settings.SpaceProfiles.TryGetValue(space, out var name)) settings.SpaceProfiles[space] = name = space == "Default" ? "SearcheXtra" : "Space_" + Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(space)))[..24];
        return name;
    }
    internal static bool PermissionOriginMatches(string storedOrigin, string origin) =>
        Uri.TryCreate(storedOrigin, UriKind.Absolute, out var stored) && stored.GetLeftPart(UriPartial.Authority).Equals(origin, StringComparison.OrdinalIgnoreCase);
    public void ApplySettings()
    {
        ConfigureFlowDrag();
        if (Control.CoreWebView2 is not { } core) return;
        core.Profile.PreferredColorScheme = store.Settings.Theme switch { "dark" => CoreWebView2PreferredColorScheme.Dark, "light" => CoreWebView2PreferredColorScheme.Light, _ => CoreWebView2PreferredColorScheme.Auto };
        core.Settings.IsPasswordAutosaveEnabled = !tab.IsPrivate && store.Settings.SavesPasswords;
        core.Settings.IsGeneralAutofillEnabled = !tab.IsPrivate && store.Settings.FillsPasswords;
        core.Profile.PreferredTrackingPreventionLevel = store.Settings.PreventTracking ? CoreWebView2TrackingPreventionLevel.Balanced : CoreWebView2TrackingPreventionLevel.None;
        var site = Uri.TryCreate(tab.Url, UriKind.Absolute, out var uri) ? store.Settings.Sites.GetValueOrDefault(uri.Host) : null;
        _ = core.ExecuteScriptAsync("if(document.documentElement)document.documentElement.style.zoom=" + JsonSerializer.Serialize(site?.Zoom ?? store.Settings.PageZoom));
        _ = core.ExecuteScriptAsync("window.__searchPrefs=" + JsonSerializer.Serialize(ScriptOptions()));
    }
    private void NavigationStarting(CoreWebView2 sender, CoreWebView2NavigationStartingEventArgs args)
    {
        if (tab.IsPrivate && !SupportsPrivateExtensions && args.Uri.StartsWith("chrome-extension://", StringComparison.OrdinalIgnoreCase)) { args.Cancel = true; return; }
        tab.Loading = true; tab.Url = args.Uri; tab.Reading = 0;
    }
    private async void NavigationCompleted(CoreWebView2 sender, CoreWebView2NavigationCompletedEventArgs args)
    {
        tab.Loading = false;
        if (args.IsSuccess && recordVisits && !tab.IsPrivate && AddressParser.IsWeb(tab.Url))
        {
            store.History.Insert(0, new(tab.Url, tab.Title, DateTimeOffset.Now));
            if (store.History.Count > 10000) store.History.RemoveRange(10000, store.History.Count - 10000);
        }
        if (!args.IsSuccess) tab.Title = $"{args.WebErrorStatus}";
        changed();
        if (args.IsSuccess && recordVisits && !tab.IsPrivate && store.Settings.SearchesSites && Uri.TryCreate(tab.Url, UriKind.Absolute, out var page))
        { var description = JsonSerializer.Deserialize<string>(await sender.ExecuteScriptAsync("document.querySelector('link[rel~=search][type=\"application/opensearchdescription+xml\"]')?.href || ''")) ?? ""; await SiteSearch.LearnAsync(store.Settings, page, description); changed(); }
        ApplySettings();
        if (args.IsSuccess && !tab.IsPrivate && store.Settings.FillsPasswords && AddressParser.IsWeb(sender.Source))
        {
            var origin = new Uri(sender.Source).GetLeftPart(UriPartial.Authority);
            var login = (await PasswordStore.ReadAsync()).FirstOrDefault(p => p.Origin.Equals(origin, StringComparison.OrdinalIgnoreCase));
            if (login != null && !disposed && sender.Source == tab.Url) await sender.ExecuteScriptAsync(PageScripts.FillPassword(login));
        }
    }
    private void TitleChanged(CoreWebView2 sender, object args) { tab.Title = sender.DocumentTitle; changed(); }
    private void SourceChanged(CoreWebView2 sender, CoreWebView2SourceChangedEventArgs args) => tab.Url = sender.Source;
    private void FaviconChanged(CoreWebView2 sender, object args)
    {
        tab.Favicon = store.Settings.IconGlyphs ? sender.FaviconUri : "";
        if (WebsiteIcon == sender.FaviconUri) return;
        WebsiteIcon = sender.FaviconUri;
        WebsiteIconChanged?.Invoke();
    }
    private async void NewWindowRequested(CoreWebView2 sender, CoreWebView2NewWindowRequestedEventArgs args)
    {
        var deferral = args.GetDeferral();
        try { args.Handled = true; if (NewWindowTarget != null) args.NewWindow = await NewWindowTarget(args.Uri); else open(args.Uri); }
        finally { deferral.Complete(); }
    }
    private void ContextMenuRequested(CoreWebView2 sender, CoreWebView2ContextMenuRequestedEventArgs args)
    {
        if (!args.ContextMenuTarget.HasLinkUri) return;
        var link = args.ContextMenuTarget.LinkUri;
        var original = args.MenuItems.FirstOrDefault(item => item.Name is "openLinkInNewWindow" or "openLinkInNewTab");
        if (original == null) return;
        var index = args.MenuItems.IndexOf(original); args.MenuItems.Remove(original);
        var chinese = new Strings(store.Settings).Chinese;
        foreach (var foreground in new[] { false, true })
        {
            var label = foreground ? (chinese ? "在新标签页中打开链接并切换" : "Open link in new tab and go to it") : (chinese ? "在新标签页中打开链接" : "Open link in new tab");
            var item = sender.Environment.CreateContextMenuItem(label, null, CoreWebView2ContextMenuItemKind.Command);
            item.CustomItemSelected += (_, _) => OpenLink(link, foreground);
            args.MenuItems.Insert(index++, item);
        }
    }
    internal void OpenLink(string link, bool foreground) => OpenLinkRequested?.Invoke(link, foreground);
    private void ProcessFailed(CoreWebView2 sender, CoreWebView2ProcessFailedEventArgs args) { tab.Loading = false; tab.Title = "Page process stopped · Reload"; }

    private static readonly HashSet<string> Trackers = new(StringComparer.OrdinalIgnoreCase)
    { "doubleclick.net", "googlesyndication.com", "googleadservices.com", "googletagservices.com", "google-analytics.com", "googletagmanager.com", "adservice.google.com", "amazon-adsystem.com", "adnxs.com", "adsrvr.org", "criteo.com", "criteo.net", "taboola.com", "outbrain.com", "rubiconproject.com", "pubmatic.com", "openx.net", "casalemedia.com", "smartadserver.com", "sharethrough.com", "indexww.com", "bidswitch.net", "33across.com", "teads.tv", "moatads.com", "adroll.com", "scorecardresearch.com", "quantserve.com", "chartbeat.com", "hotjar.com", "mouseflow.com", "fullstory.com", "clarity.ms", "mixpanel.com", "amplitude.com", "segment.com", "segment.io", "branch.io", "appsflyer.com", "adjust.com", "analytics.tiktok.com", "connect.facebook.net", "ads-twitter.com", "analytics.twitter.com" };
    private void ResourceRequested(CoreWebView2 sender, CoreWebView2WebResourceRequestedEventArgs args)
    {
        if (!store.Settings.BlockTrackers || args.ResourceContext == CoreWebView2WebResourceContext.Document) return;
        if (Uri.TryCreate(tab.Url, UriKind.Absolute, out var top) && (store.Settings.Sites.GetValueOrDefault(top.Host)?.BlockTrackers == false || uriSameSite(args.Request.Uri, top.Host))) return;
        if (!Uri.TryCreate(args.Request.Uri, UriKind.Absolute, out var uri)) return;
        var host = uri.Host;
        if (Trackers.Any(domain => host.Equals(domain, StringComparison.OrdinalIgnoreCase) || host.EndsWith("." + domain, StringComparison.OrdinalIgnoreCase)))
            args.Response = sender.Environment.CreateWebResourceResponse(null, 403, "Blocked", "Content-Type: text/plain");
    }
    private static bool uriSameSite(string url, string top) => Uri.TryCreate(url, UriKind.Absolute, out var u) && u.Host == top;
    private async void DownloadStarting(CoreWebView2 sender, CoreWebView2DownloadStartingEventArgs args)
    {
        var deferral = args.GetDeferral();
        args.Handled = true;
        if (store.Settings.AskDownloadLocation && DownloadLocationRequested != null) { await DownloadLocationRequested(args); if (!args.Cancel) DownloadStarted?.Invoke(new(args.DownloadOperation, args.ResultFilePath)); deferral.Complete(); return; }
        Directory.CreateDirectory(store.Settings.DownloadsFolder);
        var file = Path.GetFileName(args.ResultFilePath);
        var path = Path.Combine(store.Settings.DownloadsFolder, file);
        var stem = Path.GetFileNameWithoutExtension(file);
        for (var i = 1; File.Exists(path); i++) path = Path.Combine(store.Settings.DownloadsFolder, $"{stem} ({i}){Path.GetExtension(file)}");
        args.ResultFilePath = path;
        DownloadStarted?.Invoke(new(args.DownloadOperation, path));
        deferral.Complete();
    }
    private async void MessageReceived(CoreWebView2 sender, CoreWebView2WebMessageReceivedEventArgs args)
    {
        // Only accept element selectors from the current top-level HTTP(S) document.
        try
        {
            using var doc = JsonDocument.Parse(args.WebMessageAsJson);
            var type = doc.RootElement.GetProperty("type").GetString();
            if(type=="flow-drag"){await ReceiveFlowDragAsync(args.WebMessageAsJson,args.Source);return;}
            if (!AddressParser.IsWeb(sender.Source) || args.Source != sender.Source) return;
            if (type == "store-install")
            {
                // Derive the ID from the trusted top-level store URL, never from page data.
                if (CrxInstaller.StoreId(sender.Source) is { } id && StoreInstallRequested != null) await StoreInstallRequested(id);
                return;
            }
            if (type == "reading") { if (store.Settings.ShowsReading) tab.Reading = Math.Clamp(doc.RootElement.GetProperty("value").GetDouble(), 0, 100); return; }
            if (type == "flick" && FloatingWindow != null && store.Settings.FloatFlicks) { var area = Microsoft.UI.Windowing.DisplayArea.GetFromWindowId(FloatingWindow.AppWindow.Id, Microsoft.UI.Windowing.DisplayAreaFallback.Nearest).WorkArea; var x = doc.RootElement.GetProperty("x").GetDouble(); var y = doc.RootElement.GetProperty("y").GetDouble(); var size = FloatingWindow.AppWindow.Size; FloatingWindow.AppWindow.Move(new global::Windows.Graphics.PointInt32(x < 0 ? area.X + 18 : area.X + area.Width - size.Width - 18, y < 0 ? area.Y + 18 : area.Y + area.Height - size.Height - 18)); return; }
            if (type == "hover") { if (store.Settings.ShowsLinks) HoveredLink?.Invoke(doc.RootElement.GetProperty("url").GetString() ?? ""); return; }
            if (type == "preview") { var url = doc.RootElement.GetProperty("url").GetString() ?? ""; if (store.Settings.PeeksLinks && AddressParser.IsWeb(url)) PreviewRequested?.Invoke(url); return; }
            if (type == "password") { if (tab.IsPrivate || !store.Settings.SavesPasswords) return; var origin = new Uri(sender.Source).GetLeftPart(UriPartial.Authority); var login = new Login(origin, doc.RootElement.GetProperty("username").GetString() ?? "", doc.RootElement.GetProperty("password").GetString() ?? ""); if (PasswordOffered != null && login.Password.Length > 0) await PasswordOffered(login); return; }
            if (type != "hide") return;
            var selector = doc.RootElement.GetProperty("selector").GetString();
            if (string.IsNullOrWhiteSpace(selector) || selector.Length > 2048) return;
            var host = new Uri(sender.Source).Host;
            if (!store.HiddenElements.TryGetValue(host, out var rules)) store.HiddenElements[host] = rules = [];
            if (!rules.Contains(selector)) rules.Add(selector);
            await UpdateDocumentScriptAsync();
            changed();
        }
        catch (JsonException) { }
        catch (KeyNotFoundException) { }
        catch (System.Runtime.InteropServices.COMException) when (disposed) { }
    }
    public async Task UpdateDocumentScriptAsync()
    {
        await ScriptGate.WaitAsync();
        try
        {
            if (disposed || Control.CoreWebView2 is not { } core) return;
            var source = FlowDragScript() + PageScripts.StoreBridge(new Strings(store.Settings).Text("Add to SearcheXtra", "添加至 SearcheXtra")) + PageScripts.HiddenRules(store.HiddenElements) + (store.Settings.BlockTrackers && (!Uri.TryCreate(tab.Url, UriKind.Absolute, out var page) || store.Settings.Sites.GetValueOrDefault(page.Host)?.BlockTrackers != false) ? PageScripts.Ads : "") + PageScripts.Capture + PageScripts.Features + "window.__searchPrefs=" + JsonSerializer.Serialize(ScriptOptions());
            if (source == documentScriptSource) return;
            var added = await core.AddScriptToExecuteOnDocumentCreatedAsync(source);
            if (disposed) return;
            if (documentScript != null) core.RemoveScriptToExecuteOnDocumentCreated(documentScript);
            documentScript = added;
            documentScriptSource = source;
        }
        catch (System.Runtime.InteropServices.COMException) when (disposed) { }
        finally { ScriptGate.Release(); }
    }
    private object ScriptOptions() => new { peek = store.Settings.PeeksLinks, links = store.Settings.ShowsLinks, scroll = store.Settings.AutoScroll, wait = store.Settings.WaitsForPlay, passkeys = store.Settings.Passkeys, passwords = store.Settings.SavesPasswords && !tab.IsPrivate, autocorrect = store.Settings.Autocorrect, reading = store.Settings.ShowsReading, flicks = store.Settings.FloatFlicks };
    public void Resume() { if (Control.CoreWebView2 is { } core) core.Resume(); tab.Sleeping = false; }
    public async Task TrySuspendAsync()
    {
        if (disposed || FloatingWindow != null || Control.Visibility == Visibility.Visible || tab.Sleeping || Control.CoreWebView2 is not { } core) return;
        try
        {
            // Keep media, capture and unsaved form interactions running.
            var busy = await core.ExecuteScriptAsync(PageScripts.Busy);
            if (busy == "true") return;
            if (disposed || Control.Visibility == Visibility.Visible) return;
            tab.Sleeping = await core.TrySuspendAsync();
        }
        catch (Exception) when (disposed || Control.CoreWebView2 == null) { }
        catch (System.Runtime.InteropServices.COMException ex) when (ex.HResult == unchecked((int)0x8007139F)) { /* Visibility changes may not have reached the native controller yet. Retry at the next idle tick. */ }
    }
    public async Task ReaderAsync() { if (Control.CoreWebView2 is { } core) await core.ExecuteScriptAsync(PageScripts.Reader); }
    private async void CorePermissionRequested(CoreWebView2 sender, CoreWebView2PermissionRequestedEventArgs args)
    {
        var deferral = args.GetDeferral();
        try
        {
            args.SavesInProfile = false;
            if (args.PermissionKind == CoreWebView2PermissionKind.Notifications && !store.Settings.SiteNotifications) { args.State = CoreWebView2PermissionState.Deny; return; }
            if (Uri.TryCreate(args.Uri, UriKind.Absolute, out var uri))
            {
                var origin = uri.GetLeftPart(UriPartial.Authority);
                if (tab.IsPrivate)
                {
                    var permissions = await sender.Profile.GetNonDefaultPermissionSettingsAsync();
                    if (permissions.FirstOrDefault(permission => permission.PermissionKind == args.PermissionKind && PermissionOriginMatches(permission.PermissionOrigin, origin)) is { } saved) { args.State = saved.PermissionState; return; }
                }
                else if (store.Settings.Sites.GetValueOrDefault(origin)?.Permissions.GetValueOrDefault(args.PermissionKind.ToString()) is { } saved && saved != "ask") { args.State = saved == "allow" ? CoreWebView2PermissionState.Allow : CoreWebView2PermissionState.Deny; return; }
            }
            if (PermissionRequested != null) await PermissionRequested(args); else args.State = CoreWebView2PermissionState.Deny;
        }
        catch { args.State = CoreWebView2PermissionState.Deny; }
        finally { deferral.Complete(); }
    }
    public async Task PickHiddenElementAsync() { if (Control.CoreWebView2 is { } core) await core.ExecuteScriptAsync(PageScripts.Hide); }
    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        lifetime.Cancel();
        FloatingWindow?.Close(); FloatingWindow = null;
        if (Control.CoreWebView2 is { } core)
        {
            core.NavigationStarting -= NavigationStarting; core.NavigationCompleted -= NavigationCompleted;
            core.DocumentTitleChanged -= TitleChanged; core.SourceChanged -= SourceChanged;
            core.NewWindowRequested -= NewWindowRequested; core.ContextMenuRequested -= ContextMenuRequested; core.DownloadStarting -= DownloadStarting;
            core.WebMessageReceived -= MessageReceived; core.ProcessFailed -= ProcessFailed;
            core.WebResourceRequested -= ResourceRequested;
            core.PermissionRequested -= CorePermissionRequested;
            core.FaviconChanged -= FaviconChanged;
            if (documentScript != null) core.RemoveScriptToExecuteOnDocumentCreated(documentScript);
        }
        Control.Close();
    }
}

public sealed class DownloadItem(CoreWebView2DownloadOperation operation, string path)
{
    public CoreWebView2DownloadOperation Operation { get; } = operation;
    public string Path { get; } = path;
    public string Name => System.IO.Path.GetFileName(Path);
    public string Progress => $"{Name} · {Operation.BytesReceived / 1024:N0} KB · {Operation.State}";
}
