using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.Web.WebView2.Core;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private async Task VerifySitePermissionsAsync(string fixture, Action<bool, string> check)
    {
        static IEnumerable<T> Children<T>(DependencyObject parent) where T : DependencyObject
        {
            for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
            {
                var child = VisualTreeHelper.GetChild(parent, i);
                if (child is T item) yield return item;
                foreach (var nested in Children<T>(child)) yield return nested;
            }
        }
        static async Task Wait(Func<Task<bool>> condition)
        {
            var deadline = DateTime.UtcNow.AddSeconds(15);
            while (!await condition()) { if (DateTime.UtcNow > deadline) throw new TimeoutException("Permission regression timed out"); await Task.Delay(25); }
        }
        Task Visible() => Wait(() => Task.FromResult(OverlayLayer.Visibility == Visibility.Visible));
        void Click(string label)
        {
            Root.UpdateLayout();
            var button = Children<Button>(OverlayLayer).Single(button => Equals(button.Content, label));
            var peer = new ButtonAutomationPeer(button);
            ((IInvokeProvider)peer.GetPattern(PatternInterface.Invoke)).Invoke();
        }
        ComboBox Location()
        {
            Root.UpdateLayout();
            return Children<ComboBox>(OverlayLayer).Single(combo => Equals(combo.Header, SitePermissionName("Geolocation")));
        }
        var previous = active;
        var origin = new Uri(fixture).GetLeftPart(UriPartial.Authority);
        var site = GetSite(origin);
        var oldPermission = site.Permissions.GetValueOrDefault("Geolocation");
        var normal = AddTab(fixture + "permission-tests", false);
        var privateTabs = new List<BrowserTab>();
        try
        {
            await SelectAsync(normal);
            var view = await GetViewAsync(normal);
            var core = view.Control.CoreWebView2;
            await Wait(() => Task.FromResult(!normal.Loading && core.Source == fixture + "permission-tests"));
            await core.Profile.SetPermissionStateAsync(CoreWebView2PermissionKind.Geolocation, origin, CoreWebView2PermissionState.Default);
            site.Permissions.Remove("Geolocation");
            var requested = 0;
            core.PermissionRequested += (_, _) => requested++;
            var settings = ShowSettingsAsync(); await Visible();
            await core.ExecuteScriptAsync("navigator.geolocation.getCurrentPosition(()=>{},()=>{})");
            await Wait(() => Task.FromResult(requested > 0));
            await Task.Delay(100);
            check(!site.Permissions.ContainsKey("Geolocation") && OverlayLayer.Visibility == Visibility.Visible, "Website permission waits for the existing settings overlay without saving a denial");
            DismissOverlay(); await settings; await Visible();
            Click(T("Block", "阻止"));
            await Wait(() => Task.FromResult(site.Permissions.GetValueOrDefault("Geolocation") == "deny"));
            check(site.Permissions["Geolocation"] == "deny", "Explicit permission block is saved");

            site.Permissions.Remove("Geolocation");
            await core.Profile.SetPermissionStateAsync(CoreWebView2PermissionKind.Geolocation, origin, CoreWebView2PermissionState.Default);
            view.Navigate(fixture + "permission-dismiss"); await Wait(() => Task.FromResult(!normal.Loading && core.Source == fixture + "permission-dismiss"));
            var before = requested;
            await core.ExecuteScriptAsync("navigator.geolocation.getCurrentPosition(()=>{},()=>{})");
            await Wait(() => Task.FromResult(requested > before)); await Visible();
            DismissOverlay();
            await Wait(() => Task.FromResult(permissionGate.CurrentCount == 1));
            check(!site.Permissions.ContainsKey("Geolocation"), "Dismissing a permission prompt keeps the saved state at Ask");

            var closingTab = AddTab(fixture + "permission-close", false); privateTabs.Add(closingTab);
            await SelectAsync(closingTab); var closingCore = (await GetViewAsync(closingTab)).Control.CoreWebView2;
            await Wait(() => Task.FromResult(!closingTab.Loading && closingCore.Source == fixture + "permission-close"));
            var closingRequested = false; closingCore.PermissionRequested += (_, _) => closingRequested = true;
            settings = ShowSettingsAsync(); await Visible();
            await closingCore.ExecuteScriptAsync("navigator.geolocation.getCurrentPosition(()=>{},()=>{})");
            await Wait(() => Task.FromResult(closingRequested)); CloseTab(closingTab);
            await Wait(() => Task.FromResult(permissionGate.CurrentCount == 1));
            check(!site.Permissions.ContainsKey("Geolocation") && OverlayLayer.Visibility == Visibility.Visible, "Closing a tab cancels its queued permission without closing settings or saving a denial");
            DismissOverlay(); await settings;

            var privateTab = AddTab(fixture + "permission-private", false, true); privateTabs.Add(privateTab);
            await SelectAsync(privateTab); var privateView = await GetViewAsync(privateTab); var privateProfile = privateView.Control.CoreWebView2.Profile;
            await Wait(() => Task.FromResult(!privateTab.Loading && privateView.Control.CoreWebView2.Source == fixture + "permission-private"));
            await privateProfile.SetPermissionStateAsync(CoreWebView2PermissionKind.Geolocation, origin, CoreWebView2PermissionState.Default);
            var details = ShowSiteCardAsync(); await Visible(); Location().SelectedIndex = 1;
            await Wait(async () => (await privateProfile.GetNonDefaultPermissionSettingsAsync()).Any(permission => permission.PermissionKind == CoreWebView2PermissionKind.Geolocation && PageView.PermissionOriginMatches(permission.PermissionOrigin, origin) && permission.PermissionState == CoreWebView2PermissionState.Allow));
            check(!(await core.Profile.GetNonDefaultPermissionSettingsAsync()).Any(permission => permission.PermissionKind == CoreWebView2PermissionKind.Geolocation && PageView.PermissionOriginMatches(permission.PermissionOrigin, origin)), "Granting private permission does not grant the normal profile permission");
            DismissOverlay(); await details;
            details = ShowSiteCardAsync(); await Visible();
            check(Location().SelectedIndex == 1, "Private site settings read back the actual Allow state");
            DismissOverlay(); await details;
            var sibling = AddTab(fixture + "permission-private-sibling", false, true); privateTabs.Add(sibling);
            await SelectAsync(sibling); var siblingProfile = (await GetViewAsync(sibling)).Control.CoreWebView2.Profile;
            details = ShowSiteCardAsync(); await Visible();
            check(Location().SelectedIndex == 1, "Private tabs sharing one profile share temporary permission settings");
            Location().SelectedIndex = 0;
            await Wait(async () => !(await privateProfile.GetNonDefaultPermissionSettingsAsync()).Any(permission => permission.PermissionKind == CoreWebView2PermissionKind.Geolocation && PageView.PermissionOriginMatches(permission.PermissionOrigin, origin)));
            DismissOverlay(); await details;
            check(!site.Permissions.ContainsKey("Geolocation") && !(await core.Profile.GetNonDefaultPermissionSettingsAsync()).Any(permission => permission.PermissionKind == CoreWebView2PermissionKind.Geolocation && PageView.PermissionOriginMatches(permission.PermissionOrigin, origin)), "Private permission changes leave the normal profile and persisted site permissions unchanged");
            details = ShowSiteCardAsync(); await Visible(); check(Location().SelectedIndex == 0, "Private permission can be reset to Ask"); DismissOverlay(); await details;

            var privateCore = (await GetViewAsync(sibling)).Control.CoreWebView2;
            privateCore.Navigate(fixture + "permission-private-consent");
            await Wait(() => Task.FromResult(!sibling.Loading && privateCore.Source == fixture + "permission-private-consent"));
            await privateCore.ExecuteScriptAsync("navigator.geolocation.getCurrentPosition(()=>{},()=>{})"); await Visible(); Click(T("Allow", "允许"));
            await Wait(async () => (await siblingProfile.GetNonDefaultPermissionSettingsAsync()).Any(permission => permission.PermissionKind == CoreWebView2PermissionKind.Geolocation && PageView.PermissionOriginMatches(permission.PermissionOrigin, origin) && permission.PermissionState == CoreWebView2PermissionState.Allow));
            details = ShowSiteCardAsync(); await Visible();
            check(Location().SelectedIndex == 1 && !site.Permissions.ContainsKey("Geolocation"), "Private permission granted by a prompt is visible in site settings and remains temporary");
            Location().SelectedIndex = 0;
            await Wait(async () => !(await siblingProfile.GetNonDefaultPermissionSettingsAsync()).Any(permission => permission.PermissionKind == CoreWebView2PermissionKind.Geolocation && PageView.PermissionOriginMatches(permission.PermissionOrigin, origin)));
            DismissOverlay(); await details;

            var oldPrivateExtensions = Settings.ExtensionsInPrivate;
            var extension = new InstalledExtension { Id = new string('a', 32), Name = "Private override fixture", Enabled = true, NewTab = "newtab.html" };
            Settings.Extensions.Insert(0, extension); Settings.ExtensionsInPrivate = true;
            try
            {
                var blank = AddTab(null, false, true); privateTabs.Add(blank); await SelectAsync(blank);
                check(blank.IsPrivate && blank.Url is "" or "about:blank" && (await GetViewAsync(blank)).Control.CoreWebView2.Profile.IsInPrivateModeEnabled, "Unsupported private extension overrides keep the new page blank and InPrivate");
            }
            finally { Settings.Extensions.Remove(extension); Settings.ExtensionsInPrivate = oldPrivateExtensions; }
        }
        finally
        {
            DismissOverlay();
            foreach (var tab in privateTabs) if (tabs.Contains(tab)) CloseTab(tab);
            if (tabs.Contains(normal)) CloseTab(normal);
            if (oldPermission == null) site.Permissions.Remove("Geolocation"); else site.Permissions["Geolocation"] = oldPermission;
            if (previous != null && tabs.Contains(previous)) await SelectAsync(previous);
        }
    }

    private async Task VerifyBookmarkSiteIconAsync(Action<bool, string> check)
    {
        var previous = active;
        var bookmarks = store.Bookmarks;
        var flags = (Settings.IconGlyphs, Settings.BookmarksBar, Settings.BookmarkWebsiteIcons);
        var server = new TcpListener(IPAddress.Loopback, 0);
        using var cancellation = new CancellationTokenSource();
        var png = await File.ReadAllBytesAsync(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.png"));
        server.Start();
        var fixture = $"http://127.0.0.1:{((IPEndPoint)server.LocalEndpoint).Port}/";
        var serving = Task.Run(async () =>
        {
            try
            {
                while (!cancellation.IsCancellationRequested)
                {
                    var client = await server.AcceptTcpClientAsync(cancellation.Token);
                    _ = Task.Run(async () =>
                    {
                        using (client)
                        {
                            try
                            {
                                using var stream = client.GetStream();
                                var request = new byte[4096]; var length = await stream.ReadAsync(request, cancellation.Token);
                                var icon = Encoding.ASCII.GetString(request, 0, length).StartsWith("GET /custom.png ");
                                var body = icon ? png : Encoding.UTF8.GetBytes("<!doctype html><head><title>Bookmark icon fixture</title><link rel=icon href=/custom.png></head><body>Bookmark icon</body>");
                                var header = Encoding.ASCII.GetBytes($"HTTP/1.1 200 OK\r\nContent-Type: {(icon ? "image/png" : "text/html")}\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n");
                                await stream.WriteAsync(header, cancellation.Token); await stream.WriteAsync(body, cancellation.Token);
                            }
                            catch (IOException) { }
                            catch (OperationCanceledException) { }
                        }
                    });
                }
            }
            catch (OperationCanceledException) { }
            catch (SocketException) when (cancellation.IsCancellationRequested) { }
        });
        BrowserTab? tab = null;
        try
        {
            Settings.IconGlyphs = false; Settings.BookmarksBar = true; Settings.BookmarkWebsiteIcons = true;
            store.Bookmarks = [new() { Title = "Site icon", Url = fixture }]; ApplySettings();
            tab = AddTab(fixture, false); await SelectAsync(tab); var core = (await GetViewAsync(tab)).Control.CoreWebView2;
            var deadline = DateTime.UtcNow.AddSeconds(15);
            Image? image;
            do
            {
                Root.UpdateLayout();
                image = BookmarkRow.Children.Count > 0 ? FindAddressPart<Image>(BookmarkRow.Children[0]) : null;
                if (core.FaviconUri == fixture + "custom.png" && image?.Source is Microsoft.UI.Xaml.Media.Imaging.BitmapImage { PixelWidth: > 0 } && BookmarkIcons.Shared.SourceUrl(fixture) == fixture + "custom.png" && !tab.Loading) break;
                if (DateTime.UtcNow > deadline) throw new TimeoutException("Bookmark site icon did not update");
                await Task.Delay(25);
            } while (true);
            check(image!.Source is Microsoft.UI.Xaml.Media.Imaging.BitmapImage { PixelWidth: > 0 } && BookmarkIcons.Shared.SourceUrl(fixture) == fixture + "custom.png", "Real site icon refreshes bookmarks while tabs show letters");
            check(tab.Favicon == "" && tab.LetterDisplay == "B", "Letter mode remains active after the real favicon update");
        }
        finally
        {
            if (tab != null && tabs.Contains(tab)) CloseTab(tab);
            store.Bookmarks = bookmarks;
            (Settings.IconGlyphs, Settings.BookmarksBar, Settings.BookmarkWebsiteIcons) = flags;
            ApplySettings();
            if (previous != null && tabs.Contains(previous)) await SelectAsync(previous);
            cancellation.Cancel(); server.Stop(); await serving;
        }
    }
}
