using Microsoft.UI.Xaml;
using Microsoft.Web.WebView2.Core;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private async Task RunSmokeTestsAsync(string reportPath)
    {
        var checks = new List<string>();
        var measurements = new Dictionary<string, double>();
        var server = new TcpListener(IPAddress.Loopback, 0);
        var cancellation = new CancellationTokenSource();
        void Check(bool result, string label) { if (!result) throw new Exception(label); checks.Add(label); File.AppendAllText(reportPath + ".progress", label + "\n"); }
        async Task Wait(Func<bool> predicate)
        {
            var started = Stopwatch.StartNew();
            while (!predicate()) { if (started.Elapsed > TimeSpan.FromSeconds(20)) throw new TimeoutException("Page initialization timed out"); await Task.Delay(25); }
        }
        async Task WaitAsync(Func<Task<bool>> predicate)
        {
            var started = Stopwatch.StartNew();
            while (!await predicate()) { if (started.Elapsed > TimeSpan.FromSeconds(20)) throw new TimeoutException("Extension initialization timed out"); await Task.Delay(25); }
        }
        try
        {
            server.Start();
            var port = ((IPEndPoint)server.LocalEndpoint).Port;
            _ = Task.Run(async () =>
            {
                while (!cancellation.IsCancellationRequested)
                {
                    try
                    {
                        var client = await server.AcceptTcpClientAsync(cancellation.Token);
                        _ = Task.Run(async () =>
                        {
                            using (client)
                            {
                                try
                                {
                                    using var stream = client.GetStream();
                                    var request = new byte[4096];
                                    var length=await stream.ReadAsync(request,cancellation.Token);
                                    if (length == 0) return;
                                    var html = "<!doctype html><html><head><title>SearcheXtra fixture</title></head><body><nav>Navigation fixture</nav><article><h1>Local browser test</h1><p>Native Windows shell, WebView2 content. " + new string('x', 500) + "</p><p>Article paragraph " + new string('y', 400) + "</p><input value='original'><form><input autocomplete='username'><input type='password'></form><div id='hide-me'>Hidden element fixture</div></article></body></html>";
                                    var isDragImage=Encoding.ASCII.GetString(request,0,length).StartsWith("GET /super-drag.png ");
                                    var body = isDragImage ? await File.ReadAllBytesAsync(Path.Combine(AppContext.BaseDirectory,"Assets","AppIcon.png")):Encoding.UTF8.GetBytes(html);
                                    var header = Encoding.ASCII.GetBytes($"HTTP/1.1 200 OK\r\nContent-Type: {(isDragImage ? "image/png":"text/html; charset=utf-8")}\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n");
                                    await stream.WriteAsync(header, cancellation.Token); await stream.WriteAsync(body, cancellation.Token);
                                }
                                catch (OperationCanceledException) { }
                                catch (IOException) { }
                            }
                        });
                    }
                    catch (OperationCanceledException) { break; }
                    catch (ObjectDisposedException) { break; }
                }
            });
            var fixture = $"http://127.0.0.1:{port}/";
            if (Environment.GetEnvironmentVariable("SEARCHEXTRA_SUPER_DRAG_TEST_ONLY") == "1") {
                await Task.Delay(250);
                await VerifySuperDragAsync(fixture,Check);
                await VerifyBookmarkMiddleInputAsync(fixture,Check);
                await File.WriteAllTextAsync(reportPath,JsonSerializer.Serialize(new { success=true,checks,measurements }));
                return;
            }
            var watch = Stopwatch.StartNew();
            var first = AddTab(fixture, false);
            await SelectAsync(first);
            await Wait(() => !first.Loading && first.Title == "SearcheXtra fixture");
            measurements["FirstWebViewAndLocalNavigationMs"] = watch.Elapsed.TotalMilliseconds;
            Check(views.ContainsKey(first.Id), "Foreground page initialized");
            Root.UpdateLayout(); UpdateTitleBarRegions(); Root.UpdateLayout();
            if (TopTabs.ContainerFromIndex(TopTabs.Items.Count - 1) is FrameworkElement lastTab)
            {
                var end = lastTab.TransformToVisual(TopStrip).TransformPoint(new global::Windows.Foundation.Point(lastTab.ActualWidth, 0)).X;
                var plus = TopNew.TransformToVisual(TopStrip).TransformPoint(new global::Windows.Foundation.Point()).X;
                Check(Math.Abs(plus - end) < 2, "New tab button sits beside the last rendered tab without an empty gap");
            }
            else throw new Exception("Horizontal tab containers not realized");
            Check(ReopenButton.IsEnabled, "History menu is available without closed tabs");
            ShowRecentHistory();
            var emptyHistoryMenu = (Microsoft.UI.Xaml.Controls.MenuFlyout)ReopenButton.Tag;
            Check(emptyHistoryMenu.Items.OfType<Microsoft.UI.Xaml.Controls.MenuFlyoutItem>().Any(item => item.IsEnabled && item.Text == T("Open history", "打开历史记录")),
                "Empty closed-tab list still offers the full history entry");
            emptyHistoryMenu.Hide();
            Check(Helm.Children.IndexOf(HomeButton) == Helm.Children.IndexOf(ReloadButton) + 1 &&
                Helm.Children.IndexOf(ReopenButton) == Helm.Children.IndexOf(HomeButton) + 1, "Home and reopen buttons follow reload in order");
            var previousStart = Settings.StartPage;
            var previousLanguage = Settings.Language;
            Settings.Language = "zh-Hans";
            await views[first.Id].Control.CoreWebView2.ExecuteScriptAsync("navigator.geolocation.getCurrentPosition(()=>{},()=>{});true");
            await Wait(() => OverlayLayer.Visibility == Visibility.Visible);
            Check(OverlayLayer.Children[0] is Microsoft.UI.Xaml.Controls.Border { Child: Microsoft.UI.Xaml.Controls.Grid permissionCard } &&
                permissionCard.Children.OfType<Microsoft.UI.Xaml.Controls.TextBlock>().Any(t => t.Text == "此网站请求：位置信息"),
                "A real geolocation request displays a Chinese permission name");
            DismissOverlay(); Settings.Language = previousLanguage;
            var homeTabCount = tabs.Count;
            Settings.StartPage = fixture + "home";
            await GoHomeAsync();
            await Wait(() => !first.Loading && views[first.Id].Control.CoreWebView2.Source == fixture + "home");
            Check(active == first && tabs.Count == homeTabCount, "Home navigates the current tab to the configured start page");
            var blankNewTab = AddTab(foreground: false);
            Check(blankNewTab.Url == "", "New tabs default to blank even when a start page is configured");
            await SelectAsync(blankNewTab);
            Check(active == blankNewTab && Welcome.Visibility == Visibility.Visible && !views.ContainsKey(blankNewTab.Id) && Settings.StartPage == fixture + "home",
                "Blank new tab stays blank without loading the configured start page");
            await SelectAsync(first); CloseTab(blankNewTab); closedTabs.Pop();
            Settings.StartPage = "";
            await GoHomeAsync();
            await Wait(() => views[first.Id].Control.CoreWebView2.Source == "about:blank");
            Check(Welcome.Visibility == Visibility.Visible && tabs.Count == homeTabCount, "Home without a configured page restores the default welcome page");
            Settings.StartPage = previousStart;
            await NavigateAsync(fixture);
            await Wait(() => !first.Loading && first.Title == "SearcheXtra fixture");
            var olderClosed = AddTab(fixture + "older-closed", false);
            var lastClosed = AddTab(fixture + "last-closed", false, title: "Restored title", pinned: true, group: "Restored group");
            CloseTab(olderClosed); CloseTab(lastClosed);
            Check(ReopenButton.IsEnabled, "Closing a normal tab enables reopen");
            ShowRecentHistory();
            var historyMenu = (Microsoft.UI.Xaml.Controls.MenuFlyout)ReopenButton.Tag;
            var closedItems = historyMenu.Items.OfType<Microsoft.UI.Xaml.Controls.MenuFlyoutItem>().Where(item => item.IsEnabled).ToArray();
            Check(closedItems[1].Text == "Restored title" && closedItems[2].Text == (string.IsNullOrWhiteSpace(olderClosed.Title) ? olderClosed.Url : olderClosed.Title),
                "Closed tabs are listed newest first with their titles");
            var olderItem = closedItems[2];
            var olderPeer = new Microsoft.UI.Xaml.Automation.Peers.MenuFlyoutItemAutomationPeer(olderItem);
            ((Microsoft.UI.Xaml.Automation.Provider.IInvokeProvider)olderPeer.GetPattern(Microsoft.UI.Xaml.Automation.Peers.PatternInterface.Invoke)).Invoke();
            historyMenu.Hide();
            await Wait(() => active?.Url == fixture + "older-closed");
            Check(closedTabs.Count == 1 && closedTabs.Peek().Url == fixture + "last-closed",
                "Selecting an older closed tab restores only that tab and preserves the latest undo entry");
            var restoredOlder = active!;
            Reopen_Click(ReopenButton, new());
            await Wait(() => active?.Url == fixture + "last-closed");
            Check(active is { Pinned: true, Group: "Restored group" }, "Reopen restores the most recently closed tab and its metadata");
            var restoredClosed = active!;
            Reopen();
            Check(closedTabs.Count == 0 && active == restoredClosed && ReopenButton.IsEnabled, "Exhausted undo leaves the active tab intact and history available");
            ShowRecentHistory();
            historyMenu = (Microsoft.UI.Xaml.Controls.MenuFlyout)ReopenButton.Tag;
            var historyPeer = new Microsoft.UI.Xaml.Automation.Peers.MenuFlyoutItemAutomationPeer((Microsoft.UI.Xaml.Controls.MenuFlyoutItem)historyMenu.Items[0]);
            ((Microsoft.UI.Xaml.Automation.Provider.IInvokeProvider)historyPeer.GetPattern(Microsoft.UI.Xaml.Automation.Peers.PatternInterface.Invoke)).Invoke();
            historyMenu.Hide();
            await Wait(() => OverlayLayer.Visibility == Visibility.Visible);
            Check(FindAddressPart<Microsoft.UI.Xaml.Controls.TextBox>(OverlayLayer)?.PlaceholderText == T("Search history", "搜索历史记录"),
                "History menu opens the searchable history panel");
            DismissOverlay();
            CloseTab(restoredOlder); CloseTab(restoredClosed); closedTabs.Clear();
            var previousBookmarks = store.Bookmarks.ToList();
            var bookmarkFolder = new Bookmark { Title = "Folder", Children = [new() { Title = "Child", Url = fixture + "child" }] };
            store.Bookmarks = [new() { Title = "Zulu", Url = fixture + "z" }, bookmarkFolder, new() { Title = "Alpha", Url = fixture + "a" }];
            RefreshBookmarkBar();
            var bookmarkContext = (Microsoft.UI.Xaml.Controls.MenuFlyout)((Microsoft.UI.Xaml.Controls.Button)BookmarkRow.Children[1]).ContextFlyout;
            Check(bookmarkContext.Items.OfType<Microsoft.UI.Xaml.Controls.MenuFlyoutItem>().Any(item => item.Text == T("Rename…", "重命名…")) &&
                bookmarkContext.Items.OfType<Microsoft.UI.Xaml.Controls.MenuFlyoutItem>().Any(item => item.Text == T("Cut", "剪切")), "Bookmarks bar context menu includes rename and clipboard operations");
            Check(bookmarkContext.Items.OfType<Microsoft.UI.Xaml.Controls.MenuFlyoutSubItem>().Single().Items.Count == 4,
                "Bookmarks bar context menu provides visibility, compact spacing and folder icon controls");
            var tabsBeforeBookmarkOpen = tabs.ToArray();
            var activeBeforeBookmarkOpen = active;
            var openBookmarks = bookmarkContext.Items.OfType<Microsoft.UI.Xaml.Controls.MenuFlyoutItem>().Single(item => item.Text == T("Open all (1) bookmarks", "打开全部（1 个）书签"));
            var openBookmarksPeer = new Microsoft.UI.Xaml.Automation.Peers.MenuFlyoutItemAutomationPeer(openBookmarks);
            ((Microsoft.UI.Xaml.Automation.Provider.IInvokeProvider)openBookmarksPeer.GetPattern(Microsoft.UI.Xaml.Automation.Peers.PatternInterface.Invoke)).Invoke();
            Check(tabs.Count == tabsBeforeBookmarkOpen.Length + 1 && active == activeBeforeBookmarkOpen, "Bookmarks bar open-all creates background tabs without switching the active page");
            foreach (var tab in tabs.Where(tab => !tabsBeforeBookmarkOpen.Contains(tab)).ToArray()) CloseTab(tab);
            closedTabs.Clear();
            var bookmarkManager = ShowBookmarksAsync(); Root.UpdateLayout();
            try
            {
                var bookmarkList = FindAddressPart<Microsoft.UI.Xaml.Controls.ListView>(OverlayLayer, "BookmarkManagerList")!;
                Check(bookmarkList.Items.Count == 3 && bookmarkList.SelectionMode == Microsoft.UI.Xaml.Controls.ListViewSelectionMode.Multiple,
                    "Bookmark manager lists current folder and supports multiple selection");
                Check(bookmarkList.AllowDrop && bookmarkList.Items.Cast<Microsoft.UI.Xaml.Controls.ListViewItem>().All(item => item.Content is Microsoft.UI.Xaml.Controls.Border { CanDrag: true }), "Each bookmark row has an explicit native drag source");
                var selectAllButton = FindAddressPart<Microsoft.UI.Xaml.Controls.Button>(OverlayLayer, "BookmarkManagerSelectAll")!;
                var selectAllPeer = new Microsoft.UI.Xaml.Automation.Peers.ButtonAutomationPeer(selectAllButton);
                ((Microsoft.UI.Xaml.Automation.Provider.IInvokeProvider)selectAllPeer.GetPattern(Microsoft.UI.Xaml.Automation.Peers.PatternInterface.Invoke)).Invoke();
                Check(bookmarkList.SelectedItems.Count == 3, "Bookmark manager select-all button selects every current item");
                var sortButton = FindAddressPart<Microsoft.UI.Xaml.Controls.Button>(OverlayLayer, "BookmarkManagerSort")!;
                var sortPeer = new Microsoft.UI.Xaml.Automation.Peers.ButtonAutomationPeer(sortButton);
                ((Microsoft.UI.Xaml.Automation.Provider.IInvokeProvider)sortPeer.GetPattern(Microsoft.UI.Xaml.Automation.Peers.PatternInterface.Invoke)).Invoke();
                Check(store.Bookmarks[0].Title == "Alpha" && bookmarkFolder.Children![0].Title == "Child",
                    "Bookmark manager sorts current folder without flattening nested bookmarks");
                var bookmarkSearch = FindAddressPart<Microsoft.UI.Xaml.Controls.TextBox>(OverlayLayer)!;
                bookmarkSearch.Text = "child";
                await Wait(() => bookmarkList.Items.Count == 1);
                Check(bookmarkList.Items.Count == 1, "Bookmark manager searches inside nested folders");
            }
            finally { DismissOverlay(); await bookmarkManager; store.Bookmarks = previousBookmarks; store.Notify(); }
            await SelectAsync(first);
            var firstView = views[first.Id];
            var groupedFirst = AddTab(fixture + "group-first", false, loadBackground: false, group: "Batch group");
            var betweenGroups = AddTab(fixture + "between-groups", false, loadBackground: false);
            var groupedLast = AddTab(fixture + "group-last", false, loadBackground: false, group: "Batch group");
            await SelectAsync(groupedLast);
            CloseGroup(groupedFirst);
            Check(tabs.Contains(betweenGroups) && !tabs.Contains(groupedFirst) && !tabs.Contains(groupedLast), "Close group leaves unrelated tabs open");
            Reopen(); await Wait(() => active?.Url == fixture + "group-last");
            var restoredMembers = tabs.Where(tab => tab.Group == "Batch group").ToArray();
            Check(restoredMembers.Length == 2 && restoredMembers[0].Url == fixture + "group-first" && restoredMembers[1] == active,
                "One undo restores the entire group and its previously active member");
            Check(tabs.IndexOf(restoredMembers[0]) < tabs.IndexOf(betweenGroups) && tabs.IndexOf(betweenGroups) < tabs.IndexOf(restoredMembers[1]),
                "Group undo restores tabs around unrelated tabs in their original positions");
            foreach (var member in restoredMembers) CloseTab(member); CloseTab(betweenGroups); closedTabs.Clear();
            await SelectAsync(first);
            firstView.OpenLink(fixture + "behind-link", false);
            var behindLink = tabs.Last();
            Check(active == first && behindLink.Url == fixture + "behind-link", "Opening a link behind keeps the current page selected");
            firstView.OpenLink(fixture + "front-link", true); await Wait(() => active?.Url == fixture + "front-link");
            Check(active != first, "Explicit foreground link opening switches to the new tab");
            CloseTab(active!); CloseTab(behindLink); closedTabs.Clear(); await SelectAsync(first);
            await firstView.Control.CoreWebView2.ExecuteScriptAsync("window.testMarker=42");
            var blank = AddTab("", false); await SelectAsync(blank);
            watch.Restart(); await SelectAsync(first);
            measurements["WarmTabSwitchMs"] = watch.Elapsed.TotalMilliseconds;
            Check(ReferenceEquals(firstView, views[first.Id]), "Tab switch reuses WebView2 instance");
            Check(await firstView.Control.CoreWebView2.ExecuteScriptAsync("window.testMarker") == "42", "Tab switch preserves JavaScript state");
            Settings.LazyBackgroundTabs = true;
            Settings.BookmarkOpening = BookmarkOpening.Background;
            var count = tabs.Count; OpenBookmark(fixture + "background");
            var background = tabs.Last();
            Check(tabs.Count == count + 1 && active == first, "Background bookmark preserves current tab");
            Check(!views.ContainsKey(background.Id), "Background bookmark creates no WebView until selected");
            await SelectAsync(background); await Wait(() => !background.Loading && background.Title == "SearcheXtra fixture");
            Check(views.ContainsKey(background.Id), "Selecting deferred tab loads its page");
            Settings.BookmarkOpening = BookmarkOpening.Foreground;
            count = tabs.Count; OpenBookmark(fixture + "foreground");
            var foreground = tabs.Last(); await Wait(() => active == foreground && !foreground.Loading && foreground.Title == "SearcheXtra fixture");
            Check(tabs.Count == count + 1 && active == foreground, "Foreground bookmark selects new tab");
            Settings.BookmarkOpening = BookmarkOpening.Default;
            count = tabs.Count; OpenBookmark(fixture + "current");
            await Wait(() => active == foreground && foreground.Url.EndsWith("current") && !foreground.Loading);
            Check(tabs.Count == count, "Default bookmark navigates existing tab");
            splitOwner = first; split = background; await SelectAsync(first);
            Check(firstView.Control.Visibility == Visibility.Visible && views[background.Id].Control.Visibility == Visibility.Visible, "Split view shows both pages");
            Check(Pages.ColumnDefinitions.Count == 3 && divider != null, "Split view provides resize divider");
            await SelectAsync(foreground);
            Check(Pages.ColumnDefinitions.Count == 0 && views[background.Id].Control.Visibility == Visibility.Collapsed, "Unrelated tab does not join split pair");
            split = null; splitOwner = null;
            await Task.Delay(300); // WinUI delays hiding the native controller by 200 ms to avoid flashing.
            await firstView.TrySuspendAsync();
            Check(first.Sleeping, "Hidden idle page suspends");
            await SelectAsync(first);
            Check(!first.Sleeping && await firstView.Control.CoreWebView2.ExecuteScriptAsync("window.testMarker") == "42", "Suspended page resumes without losing state");
            await firstView.Control.CoreWebView2.ExecuteScriptAsync("document.querySelector('input').value='edited'");
            await SelectAsync(foreground); await firstView.TrySuspendAsync();
            Check(!first.Sleeping, "Edited form prevents suspension");
            await SelectAsync(first);
            store.HiddenElements["127.0.0.1"] = ["#hide-me"];
            await firstView.UpdateDocumentScriptAsync();
            var reloaded = new TaskCompletionSource<bool>();
            void Completed(Microsoft.Web.WebView2.Core.CoreWebView2 sender, Microsoft.Web.WebView2.Core.CoreWebView2NavigationCompletedEventArgs args) => reloaded.TrySetResult(args.IsSuccess);
            firstView.Control.CoreWebView2.NavigationCompleted += Completed;
            try { firstView.Control.CoreWebView2.Reload(); Check(await reloaded.Task.WaitAsync(TimeSpan.FromSeconds(20)), "Hidden-rule test reload completes"); }
            finally { firstView.Control.CoreWebView2.NavigationCompleted -= Completed; }
            Check(await firstView.Control.CoreWebView2.ExecuteScriptAsync("getComputedStyle(document.querySelector('#hide-me')).display") == "\"none\"", "Saved element rules apply to subsequent navigation");
            var extensionFolder = Path.Combine(DataStore.Root, "fixture-extension");
            Directory.CreateDirectory(extensionFolder);
            await File.WriteAllTextAsync(Path.Combine(extensionFolder, "manifest.json"), """
                {"manifest_version":3,"name":"SearcheXtra test extension","version":"1.0","content_scripts":[{"matches":["http://127.0.0.1/*"],"js":["content.js"]}]}
                """);
            await File.WriteAllTextAsync(Path.Combine(extensionFolder, "content.js"), "document.documentElement.dataset.searchextraExtension='loaded';");
            var extension = await firstView.Control.CoreWebView2.Profile.AddBrowserExtensionAsync(extensionFolder);
            Check(extension.IsEnabled, "Unpacked extension loads into WebView2 profile");
            reloaded = new TaskCompletionSource<bool>();
            firstView.Control.CoreWebView2.NavigationCompleted += Completed;
            try { firstView.Control.CoreWebView2.Reload(); Check(await reloaded.Task.WaitAsync(TimeSpan.FromSeconds(20)), "Extension test reload completes"); }
            finally { firstView.Control.CoreWebView2.NavigationCompleted -= Completed; }
            Check(await firstView.Control.CoreWebView2.ExecuteScriptAsync("document.documentElement.dataset.searchextraExtension") == "\"loaded\"", "Extension content script runs on webpage");
            measurements["WebView2RuntimeMajor"] = int.Parse(firstView.Control.CoreWebView2.Environment.BrowserVersionString.Split('.')[0]);
            var mv2Folder = Path.Combine(DataStore.Root, "fixture-mv2-extension"); Directory.CreateDirectory(mv2Folder);
            await File.WriteAllTextAsync(Path.Combine(mv2Folder, "manifest.json"), """
                {"manifest_version":2,"name":"SearcheXtra MV2 compatibility fixture","version":"1.0","permissions":["storage","webRequest","webRequestBlocking","http://127.0.0.1/*"],"background":{"scripts":["background.js"],"persistent":true},"browser_action":{"default_popup":"popup.html"},"content_scripts":[{"matches":["http://127.0.0.1/*"],"js":["content.js"]}]}
                """);
            await File.WriteAllTextAsync(Path.Combine(mv2Folder, "background.js"), """
                chrome.webRequest.onBeforeRequest.addListener(d=>({cancel:d.url.includes('/mv2-blocked')}),{urls:['http://127.0.0.1/*']},['blocking']);
                chrome.storage.local.set({probe:'MV2 persistent background'});
                const instance=crypto.randomUUID();chrome.runtime.onMessage.addListener((m,s,reply)=>{chrome.storage.local.get('probe',data=>reply({value:data.probe,instance}));return true;});
                """);
            await File.WriteAllTextAsync(Path.Combine(mv2Folder, "content.js"), "chrome.runtime.sendMessage({probe:true},r=>{document.documentElement.dataset.mv2Background=r?.value||'missing';document.documentElement.dataset.mv2Instance=r?.instance||'missing';});");
            await File.WriteAllTextAsync(Path.Combine(mv2Folder, "popup.html"), "<!doctype html><title>MV2 popup</title><body style='margin:0;width:520px;min-height:620px'><p id='status'></p><script src='popup.js'></script></body>");
            await File.WriteAllTextAsync(Path.Combine(mv2Folder, "popup.js"), "chrome.storage.local.get('probe',d=>document.querySelector('#status').textContent=d.probe);chrome.runtime.sendMessage({probe:true},r=>document.body.dataset.instance=r.instance);");
            await InstallExtensionFolderAsync(mv2Folder); var mv2 = Settings.Extensions.Single(e => e.Folder == mv2Folder);
            // Use a real icon file to verify title-bar pinning, persistence and removal.
            File.Copy(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.png"), Path.Combine(mv2Folder, "icon.png"));
            var iconManifest = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(await File.ReadAllTextAsync(Path.Combine(mv2Folder, "manifest.json")))!;
            iconManifest["icons"] = JsonSerializer.SerializeToElement(new Dictionary<string, string> { ["32"] = "icon.png" });
            await File.WriteAllTextAsync(Path.Combine(mv2Folder, "manifest.json"), JsonSerializer.Serialize(iconManifest));
            SetExtensionPinned(mv2, true); Root.UpdateLayout(); UpdateTitleBarRegions();
            Check(PinnedExtensions.Parent == TitleActions && TitleActions.Children.IndexOf(PinnedExtensions) + 1 == TitleActions.Children.IndexOf(ExtensionsButton), "Pinned extensions sit immediately beside the extensions button");
            Check(PinnedExtensions.Children.Single() is Microsoft.UI.Xaml.Controls.Button { Content: Microsoft.UI.Xaml.Controls.Image }, "Pinned extension displays its manifest icon");
            await store.SaveAsync();
            Check((await DataStore.LoadAsync()).Settings.Extensions.Single(e => e.Id == mv2.Id).Pinned, "Extension pin survives settings reload");
            await SetExtensionEnabledAsync(mv2, false); Check(PinnedExtensions.Children.Count == 0, "Disabled extension leaves the title bar");
            await SetExtensionEnabledAsync(mv2, true); Check(PinnedExtensions.Children.Count == 1, "Re-enabled extension retains its pin");
            SetExtensionPinned(mv2, false); Check(PinnedExtensions.Children.Count == 0, "Unpin removes the extension title-bar button");
            var managerTask = ShowExtensionManagerAsync(); Root.UpdateLayout();
            try
            {
                var enable = FindAddressPart<Microsoft.UI.Xaml.Controls.ToggleSwitch>(OverlayLayer)!;
                Check(enable.Tag as string == mv2.Id && enable.IsOn, "Extension management cards expose an enabled-state switch");
                enable.IsOn = false; await Wait(() => !mv2.Enabled && enable.IsEnabled);
                Check(!(await firstView.Control.CoreWebView2.Profile.GetBrowserExtensionsAsync()).Single(e => e.Id == mv2.Id).IsEnabled, "Management switch disables the real extension");
                enable.IsOn = true; await Wait(() => mv2.Enabled && enable.IsEnabled);
                Check((await firstView.Control.CoreWebView2.Profile.GetBrowserExtensionsAsync()).Single(e => e.Id == mv2.Id).IsEnabled, "Management switch re-enables the real extension");
                await store.SaveAsync(); Check((await DataStore.LoadAsync()).Settings.Extensions.Single(e => e.Id == mv2.Id).Enabled, "Extension management state persists after reload");
                var search = FindAddressPart<Microsoft.UI.Xaml.Controls.TextBox>(OverlayLayer)!;
                search.Text = "no-such-extension";
                await Wait(() => FindAddressPart<Microsoft.UI.Xaml.Controls.ToggleSwitch>(OverlayLayer) == null);
                Check(FindAddressPart<Microsoft.UI.Xaml.Controls.ToggleSwitch>(OverlayLayer) == null, "Extension management search filters cards");
                search.Text = "";
                await Wait(() => FindAddressPart<Microsoft.UI.Xaml.Controls.ToggleSwitch>(OverlayLayer) != null);
                Check(FindAddressPart<Microsoft.UI.Xaml.Controls.ToggleSwitch>(OverlayLayer)?.IsOn == true, "Clearing extension search restores its card");
            }
            finally { DismissOverlay(); await managerTask; }
            Check((await firstView.Control.CoreWebView2.Profile.GetBrowserExtensionsAsync()).Single(e => e.Id == mv2.Id).IsEnabled, "MV2 manifest loads without conversion");
            first.Loading = true; firstView.Control.CoreWebView2.Reload(); await Wait(() => !first.Loading); await Task.Delay(150);
            Check(await firstView.Control.CoreWebView2.ExecuteScriptAsync("document.documentElement.dataset.mv2Background") == "\"MV2 persistent background\"", "MV2 persistent background, messaging and storage work");
            await firstView.Control.CoreWebView2.ExecuteScriptAsync("window.mv2Blocked='pending';fetch('/mv2-blocked').then(()=>window.mv2Blocked='allowed').catch(()=>window.mv2Blocked='blocked');");
            await Task.Delay(250); Check(await firstView.Control.CoreWebView2.ExecuteScriptAsync("window.mv2Blocked") == "\"blocked\"", "MV2 blocking webRequest cancels a real request");
            var mv2Instance = await firstView.Control.CoreWebView2.ExecuteScriptAsync("document.documentElement.dataset.mv2Instance");
            var mv2Popup = AddTab($"chrome-extension://{mv2.Id}/popup.html", false); await SelectAsync(mv2Popup); await Wait(() => !mv2Popup.Loading && mv2Popup.Title == "MV2 popup"); await Task.Delay(150);
            FocusAddress();
            Check(Address.Text.Length == 0 && mv2Popup.Url.StartsWith("chrome-extension://") && editingAddressTab == mv2Popup,
                "Extension tabs keep their real page URL but show an empty editable address");
            Address.Text = fixture;
            Check(Address.Text == fixture, "Extension tab address still accepts a normal URL");
            EndAddressEdit();
            Check(await views[mv2Popup.Id].Control.CoreWebView2.ExecuteScriptAsync("document.querySelector('#status').textContent") == "\"MV2 persistent background\"", "MV2 browser_action popup accesses native extension storage");
            Check(mv2Instance != "null" && await views[mv2Popup.Id].Control.CoreWebView2.ExecuteScriptAsync("document.body.dataset.instance") == mv2Instance, "Opening another WebView preserves the running MV2 background instance");
            CloseTab(mv2Popup); await SelectAsync(first);
            var popupView = new Microsoft.UI.Xaml.Controls.WebView2 { Width = 360, Height = 480 };
            var popupTask = ShowExtensionCardAsync(popupView, firstView.Control.CoreWebView2, mv2);
            try
            {
                await Wait(() => popupView.Width >= 520); Root.UpdateLayout();
                Check(popupView.ActualWidth >= 520 && popupView.Height <= Root.ActualHeight - 140, "Extension popup fits its natural width and available window height");
                Check(await popupView.CoreWebView2.ExecuteScriptAsync("document.documentElement.scrollWidth <= innerWidth") == "true", "Wide extension popup is not clipped horizontally");
                await popupView.CoreWebView2.ExecuteScriptAsync("document.body.style.width='700px'");
                await Wait(() => popupView.Width >= 700); Root.UpdateLayout();
                Check(popupView.Parent is Microsoft.UI.Xaml.Controls.Grid panel && panel.Width == popupView.Width + 44, "Extension popup and its card resize together after content changes");
                await popupView.CoreWebView2.ExecuteScriptAsync("window.marked=false;chrome.storage.local.set({removedMarker:'must disappear'},()=>window.marked=true)");
                await WaitAsync(async () => await popupView.CoreWebView2.ExecuteScriptAsync("window.marked") == "true");
                await popupView.CoreWebView2.ExecuteScriptAsync("localStorage.setItem('removedSiteMarker','must disappear');window.fileAccess='pending';chrome.extension.isAllowedFileSchemeAccess(value=>window.fileAccess=value)");
                await WaitAsync(async () => await popupView.CoreWebView2.ExecuteScriptAsync("window.fileAccess") != "\"pending\"");
                measurements["NativeExtensionFileSchemeAccess"] = await popupView.CoreWebView2.ExecuteScriptAsync("window.fileAccess") == "true" ? 1 : 0;
                await popupView.CoreWebView2.ExecuteScriptAsync("window.filePermission='pending';chrome.permissions.contains({origins:['file:///*']},value=>window.filePermission=value)");
                await WaitAsync(async () => await popupView.CoreWebView2.ExecuteScriptAsync("window.filePermission") != "\"pending\"");
                Check(await popupView.CoreWebView2.ExecuteScriptAsync("window.filePermission") == "false", "A native extension with only HTTP permissions has no file-origin permission");
            }
            finally { DismissOverlay(); await popupTask; }
            await RemoveExtensionAsync(mv2);
            await InstallExtensionFolderAsync(mv2Folder);
            var reinstalled = Settings.Extensions.Single(extension => extension.Folder == mv2Folder);
            Check(reinstalled.Id == mv2.Id, "Loading the same extension folder keeps its native Chrome identity");
            var storageTab = AddTab($"chrome-extension://{reinstalled.Id}/popup.html");
            await Wait(() => !storageTab.Loading && storageTab.Title == "MV2 popup");
            var storageCore = views[storageTab.Id].Control.CoreWebView2;
            await storageCore.ExecuteScriptAsync("window.removedMarker='pending';chrome.storage.local.get('removedMarker',data=>window.removedMarker=data.removedMarker||'empty')");
            await WaitAsync(async () => await storageCore.ExecuteScriptAsync("window.removedMarker") != "\"pending\"");
            Check(await storageCore.ExecuteScriptAsync("window.removedMarker") == "\"empty\"", "Uninstalling an extension clears its native storage before reinstall");
            Check(await storageCore.ExecuteScriptAsync("localStorage.getItem('removedSiteMarker')") == "null", "Uninstalling an extension clears its page-origin storage before reinstall");
            CloseTab(storageTab); await SelectAsync(first); await RemoveExtensionAsync(reinstalled);
            await firstView.Control.CoreWebView2.ExecuteScriptAsync("""
                (async()=>{const canvas=document.createElement('canvas');canvas.width=320;canvas.height=180;canvas.getContext('2d').fillRect(0,0,320,180);const video=document.createElement('video');video.muted=true;video.srcObject=canvas.captureStream(5);document.body.appendChild(video);await video.play();})()
                """);
            await TogglePictureInPictureAsync();
            Check(firstView.FloatingWindow != null && !Pages.Children.Contains(firstView.Control), "Picture in picture reuses page in compact overlay");
            firstView.FloatingWindow!.Close(); await Task.Delay(300);
            Check(firstView.FloatingWindow == null && Pages.Children.Contains(firstView.Control), "Closing picture in picture restores original WebView");
            var historyCount = store.History.Count;
            var privateTab = AddTab(fixture + "private", false, true); await SelectAsync(privateTab);
            await Wait(() => !privateTab.Loading && privateTab.Title == "SearcheXtra fixture");
            Check(views[privateTab.Id].Control.CoreWebView2.Profile.IsInPrivateModeEnabled, "Private tab uses InPrivate profile");
            Check(store.History.Count == historyCount, "Private navigation is excluded from history");
            NewTab_Click(this, new());
            Check(active?.IsPrivate == true, "New-tab button preserves private browsing");
            var newPrivateTab = active!;
            await SelectAsync(privateTab); CloseTab(newPrivateTab);

            await SaveStateAsync();
            Check(store.Session.Tabs.All(t => !t.Url.EndsWith("private")), "Private tabs excluded from persisted session");
            Settings.CompactBookmarksBar = true;
            store.Bookmarks.Add(new() { Title = "Fixture bookmark", Url = fixture });
            RefreshBookmarkBar();
            Check(BookmarkRow.Spacing == 0 && BookmarkRow.Children.Count > 0, "Compact bookmark bar layout applied");
            Settings.Sidebar = true; ApplySettings();
            Check(Sidebar.Visibility == Visibility.Visible && TopTabs.Visibility == Visibility.Collapsed, "Vertical tab layout switches correctly");
            var realized = views.Count;
            watch.Restart();
            for (var i = 0; i < 50; i++) AddTab(fixture + "restored-" + i, false, loadBackground: false);
            measurements["Restore50TabModelsMs"] = watch.Elapsed.TotalMilliseconds;
            Check(views.Count == realized, "Restoring 50 tabs does not create 50 WebViews");
            await SelectAsync(first);
            var firstCore = views[first.Id].Control.CoreWebView2;
            Settings.SidebarRight = true; ApplySettings(); Check(Microsoft.UI.Xaml.Controls.Grid.GetColumn(Sidebar) == 2 && RightSidebarColumn.Width.Value == 232, "Right sidebar uses macOS width");
            Settings.NavigationLeft = true; Settings.Sidebar = false; ApplySettings(); Check(Microsoft.UI.Xaml.Controls.Grid.GetColumn(Helm) == 1, "Navigation buttons move before horizontal tabs");
            Check(AppWindow.Presenter is Microsoft.UI.Windowing.OverlappedPresenter { HasTitleBar: true, HasBorder: true, IsMinimizable: true, IsMaximizable: true }, "Windows owns native caption buttons and title bar dragging");
            Check(ExtendsContentIntoTitleBar && Toolbar.Height == 48 && editingAddressTab == null, "Tabs occupy the 48 point Windows title bar with no permanent address bar");
            Root.UpdateLayout(); UpdateTitleBarRegions(); Root.UpdateLayout();
            var plusX = TopNew.TransformToVisual(TopStrip).TransformPoint(new global::Windows.Foundation.Point()).X;
            Check(Math.Abs(plusX - TopTabs.ActualWidth) < 1, "New tab button directly follows the horizontal tab list");
            Check(TopSettings.Visibility == Visibility.Visible && ExtensionsButton.Visibility == Visibility.Visible && TitleActions.Parent == Toolbar, "Settings and extensions remain in the title bar");
            foreach (var navigationLeft in new[] { false, true })
            {
                Settings.NavigationLeft = navigationLeft; ApplySettings(); Root.UpdateLayout(); UpdateTitleBarRegions(); Root.UpdateLayout();
                var actionsEnd = TitleActions.TransformToVisual(Toolbar).TransformPoint(new global::Windows.Foundation.Point(TitleActions.ActualWidth, 0)).X;
                Check(Math.Abs(actionsEnd + 4 + CaptionInset.Width.Value - Toolbar.ActualWidth) < 1,
                    "Settings and extensions stay immediately left of native caption buttons, navigationLeft=" + navigationLeft);
            }
            foreach (var theme in new[] { ElementTheme.Light, ElementTheme.Dark })
            {
                Root.RequestedTheme = theme; SetupGlyphs();
                var glyph = (Microsoft.UI.Xaml.Shapes.Path)((Microsoft.UI.Xaml.Controls.Canvas)TopSettings.Content).Children[0];
                Check(((Microsoft.UI.Xaml.Media.SolidColorBrush)glyph.Stroke).Color == Brush("Ink").Color, "Toolbar glyph contrast follows " + theme);
            }
            Root.RequestedTheme = ElementTheme.Default; SetupGlyphs();
            foreach (var sidebar in new[] { false, true })
            {
                Settings.Sidebar = sidebar; ApplySettings(); FocusAddress(); Root.UpdateLayout();
                var item = AddressList.ContainerFromItem(active) as Microsoft.UI.Xaml.Controls.ListViewItem;
                var host = item == null ? null : FindAddressPart<Microsoft.UI.Xaml.Controls.Grid>(item, "TabAddressHost");
                Check(editingAddressTab == active && host != null && Address.Parent == host && OverlayLayer.Visibility == Visibility.Collapsed,
                    "Address edits inside the tab without a dialog, sidebar=" + sidebar);
                var editorBorder = FindAddressPart<Microsoft.UI.Xaml.Controls.Border>(Address);
                var editorContent = FindAddressPart<Microsoft.UI.Xaml.Controls.ScrollViewer>(Address, "ContentElement");
                Check((editorBorder == null || editorBorder.BorderThickness == new Thickness(0)) &&
                    editorContent is { ActualWidth: > 0, ActualHeight: > 0 },
                    "Tab address has no input border or focus underline, sidebar=" + sidebar + ", border=" + editorBorder?.BorderThickness + ", content=" + editorContent?.ActualWidth + "x" + editorContent?.ActualHeight);
                Check(sidebar || item != null && Math.Abs(item.ActualWidth - 372) < 1,
                    "Address editing doubles the default tab width: actual=" + item?.ActualWidth);
                Address.Text = "https://example.com/inline-address";
                Root.UpdateLayout();
                Check(FindAddressPart<Microsoft.UI.Xaml.Controls.TextBlock>(Address, "PlaceholderTextContentPresenter")?.Visibility == Visibility.Collapsed,
                    "Address placeholder disappears while typing");
                Check(Address.Text.EndsWith("inline-address") && Address.Parent == host && OverlayLayer.Visibility == Visibility.Collapsed,
                    "Typing keeps the address inside the tab, sidebar=" + sidebar);
                EndAddressEdit();
                Check(Address.Parent == AddressParking && editingAddressTab == null, "Ending address edit restores the tab label");
            }
            Settings.Sidebar = false; ApplySettings();
            FocusAddress(); Root.UpdateLayout();
            var infoItem = (Microsoft.UI.Xaml.Controls.ListViewItem)TopTabs.ContainerFromItem(active);
            var infoButton = FindAddressPart<Microsoft.UI.Xaml.Controls.Button>(infoItem, "TabSiteInfo")!;
            Check(infoButton.Visibility == Visibility.Visible, "Web tabs show the site information icon during address editing");
            SiteInfo_Click(infoButton, new());
            var siteFlyout = (Microsoft.UI.Xaml.Controls.Flyout)infoButton.Tag;
            var sitePanel = (Microsoft.UI.Xaml.Controls.StackPanel)siteFlyout.Content;
            Check(sitePanel.Children.OfType<Microsoft.UI.Xaml.Controls.Button>().Count() == 3 && editingAddressTab == active,
                "Site information flyout contains connection, cookies and settings without ending address editing");
            void InvokeSiteButton(Microsoft.UI.Xaml.Controls.Button button)
            {
                var peer = new Microsoft.UI.Xaml.Automation.Peers.ButtonAutomationPeer(button);
                ((Microsoft.UI.Xaml.Automation.Provider.IInvokeProvider)peer.GetPattern(Microsoft.UI.Xaml.Automation.Peers.PatternInterface.Invoke)).Invoke();
            }
            await firstCore.ExecuteScriptAsync("document.cookie='siteInfoFixture=original;path=/';localStorage.setItem('siteInfoFixture','stored');sessionStorage.setItem('siteInfoFixture','stored')");
            InvokeSiteButton(sitePanel.Children.OfType<Microsoft.UI.Xaml.Controls.Button>().Single(b => (string)b.Content == T("Cookies and site data  ›", "Cookie 和网站数据  ›")));
            await Wait(() => sitePanel.Children.OfType<Microsoft.UI.Xaml.Controls.ScrollViewer>().Any());
            var cookieList = (Microsoft.UI.Xaml.Controls.StackPanel)sitePanel.Children.OfType<Microsoft.UI.Xaml.Controls.ScrollViewer>().Single().Content;
            var cookieRow = cookieList.Children.OfType<Microsoft.UI.Xaml.Controls.StackPanel>().Single(row => row.Children.OfType<Microsoft.UI.Xaml.Controls.TextBlock>().Any(text => text.Text.StartsWith("siteInfoFixture\n")));
            cookieRow.Children.OfType<Microsoft.UI.Xaml.Controls.TextBox>().Single().Text = "modified";
            InvokeSiteButton(((Microsoft.UI.Xaml.Controls.StackPanel)cookieRow.Children.Last()).Children.OfType<Microsoft.UI.Xaml.Controls.Button>().First());
            await Wait(() => sitePanel.Children.OfType<Microsoft.UI.Xaml.Controls.TextBlock>().Any(text => text.Text == T("Cookie saved.", "Cookie 已保存。")));
            Check((await firstCore.CookieManager.GetCookiesAsync(fixture)).Single(cookie => cookie.Name == "siteInfoFixture").Value == "modified", "Cookie edits update the actual native cookie store");
            InvokeSiteButton(sitePanel.Children.OfType<Microsoft.UI.Xaml.Controls.Button>().Single(b => (string)b.Content == T("Clear this site's data", "清除此网站数据")));
            await Wait(() => sitePanel.Children.OfType<Microsoft.UI.Xaml.Controls.TextBlock>().Any(text => text.Text == T("Site data cleared. Reload to apply.", "网站数据已清除，刷新页面后生效。")));
            Check(!(await firstCore.CookieManager.GetCookiesAsync(fixture)).Any(cookie => cookie.Name == "siteInfoFixture") && await firstCore.ExecuteScriptAsync("localStorage.getItem('siteInfoFixture')===null&&sessionStorage.getItem('siteInfoFixture')===null") == "true",
                "Clearing site data removes cookies, local storage and session storage");
            InvokeSiteButton(sitePanel.Children.OfType<Microsoft.UI.Xaml.Controls.Button>().First());
            InvokeSiteButton(sitePanel.Children.OfType<Microsoft.UI.Xaml.Controls.Button>().Single(b => (string)b.Content == T("Site settings  ↗", "网站设置  ↗")));
            await Wait(() => OverlayLayer.Visibility == Visibility.Visible);
            var settingsGrid = (Microsoft.UI.Xaml.Controls.Grid)((Microsoft.UI.Xaml.Controls.Border)OverlayLayer.Children[0]).Child;
            var settingsPanel = settingsGrid.Children.OfType<Microsoft.UI.Xaml.Controls.StackPanel>().Single();
            var locationChoice = settingsPanel.Children.OfType<Microsoft.UI.Xaml.Controls.ComboBox>().Single(box => (string)box.Header == T("Location", "位置信息"));
            locationChoice.SelectedIndex = 1; await Task.Delay(100);
            Check((await firstCore.Profile.GetNonDefaultPermissionSettingsAsync()).Any(permission => permission.PermissionKind == CoreWebView2PermissionKind.Geolocation && permission.PermissionState == CoreWebView2PermissionState.Allow),
                "Site settings write actual native location permission");
            locationChoice.SelectedIndex = 2; await Task.Delay(100);
            DismissOverlay(); EndAddressEdit();
            Check(Root.KeyboardAcceleratorPlacementMode == Microsoft.UI.Xaml.Input.KeyboardAcceleratorPlacementMode.Hidden,
                "Window shortcuts do not generate a persistent Ctrl+L tooltip");
            var layoutTabs = Enumerable.Range(0, 6).Select(_ => AddTab("", false, inSpace: "Tab layout fixture", loadBackground: false)).ToList();
            await SelectAsync(layoutTabs[0]); Root.UpdateLayout(); UpdateTitleBarRegions(); Root.UpdateLayout();
            var crowdedWidth = normalTabWidth;
            Check(crowdedWidth < 186 && crowdedWidth >= 80 && TopTabs.Items.Cast<BrowserTab>().All(t =>
                TopTabs.ContainerFromItem(t) is Microsoft.UI.Xaml.Controls.ListViewItem { ActualWidth: > 0 } item && Math.Abs(item.ActualWidth - crowdedWidth) < 1),
                "All visible tabs shrink together to fit the title bar");
            FocusAddress(); Root.UpdateLayout(); UpdateTitleBarRegions(); Root.UpdateLayout();
            Check(TopTabs.ContainerFromItem(active) is Microsoft.UI.Xaml.Controls.ListViewItem editItem && Math.Abs(editItem.ActualWidth - 372) < 1 && normalTabWidth < crowdedWidth,
                "Editing reserves double width for the active tab and shrinks its neighbors");
            EndAddressEdit(); Root.UpdateLayout(); UpdateTitleBarRegions(); Root.UpdateLayout();
            Check(Math.Abs(normalTabWidth - crowdedWidth) < 1, "Ending address editing restores shared tab widths");
            AppWindow.Resize(new global::Windows.Graphics.SizeInt32(1000, 820));
            await Wait(() => { Root.UpdateLayout(); UpdateTitleBarRegions(); return normalTabWidth < crowdedWidth; });
            Root.UpdateLayout();
            Check(normalTabWidth < crowdedWidth, "Narrowing the window further shrinks the tabs");
            foreach (var tab in layoutTabs.Skip(3)) CloseTab(tab);
            Root.UpdateLayout(); UpdateTitleBarRegions(); Root.UpdateLayout();
            Check(normalTabWidth > crowdedWidth && normalTabWidth <= 186, "Closing tabs expands the remaining tabs up to the default width");
            foreach (var tab in layoutTabs.Skip(1).Take(2)) CloseTab(tab);
            Root.UpdateLayout(); UpdateTitleBarRegions(); Root.UpdateLayout();
            Check(normalTabWidth == 186 && TopTabs.ContainerFromItem(layoutTabs[0]) is Microsoft.UI.Xaml.Controls.ListViewItem lone && Math.Abs(lone.ActualWidth - 186) < 1,
                "An uncrowded tab returns to its default width");
            AppWindow.Resize(new global::Windows.Graphics.SizeInt32(1200, 820));
            await SelectAsync(first); CloseTab(layoutTabs[0]); Root.UpdateLayout();
            foreach (var page in new[] { "general", "tabs", "shortcuts", "extensions", "passwords", "downloads", "privacy", "about" })
            {
                Settings.SettingsPage = page; var panelTask = ShowSettingsAsync(); await Task.Delay(20);
                Check(OverlayLayer.Visibility == Visibility.Visible && OverlayLayer.Children[0] is Microsoft.UI.Xaml.Controls.Border { Child: Microsoft.UI.Xaml.Controls.Grid { Width: 660, Height: 500 } }, "Settings page renders: " + page);
                DismissOverlay(); await panelTask;
            }
            Settings.Keywords.Add(new("yt", "https://www.youtube.com/results?search_query=%s")); Check(ResolveAddress("yt cats & dogs").Query.Contains("cats%20%26%20dogs"), "Keyword search escapes query");
            Settings.SearchesSites = true; siteOffer = SiteSearch.Match(Settings, "gh"); searchSite = siteOffer; Check(ResolveAddress("C# & UI").AbsoluteUri.Contains("C%23%20%26%20UI"), "Tab-selected site search escapes user query");
            Settings.Sidebar = true; Settings.SidebarAutoHide = true; sidebarFolded = true; ApplySettings(); Check(Sidebar.Visibility == Visibility.Collapsed && SidebarColumn.Width.Value == 0 && RightSidebarColumn.Width.Value == 0, "Automatic sidebar folding survives settings refresh"); sidebarFolded = false; Settings.SidebarAutoHide = false; ApplySettings();
            Settings.AlwaysShowsDownloads = true; ApplySettings(); Check(DownloadsButton.Visibility == Visibility.Visible, "Always-show download preference creates usable button");
            Settings.Shortcuts["Ctrl+L"] = "Ctrl+Shift+L"; InstallShortcuts(); Check(Root.KeyboardAccelerators.Any(k => k.Key == global::Windows.System.VirtualKey.L && k.Modifiers.HasFlag(global::Windows.System.VirtualKeyModifiers.Shift)), "Custom shortcut replaces default accelerator"); Settings.Shortcuts.Clear(); InstallShortcuts();
            var otherSpace = AddTab(fixture, false, inSpace: "Isolated fixture"); await SelectAsync(otherSpace); await Wait(() => !otherSpace.Loading && otherSpace.Title == "SearcheXtra fixture");
            Check(views[otherSpace.Id].Control.CoreWebView2.Profile.ProfileName != firstCore.Profile.ProfileName, "Spaces use separate cookie and extension profiles");
            await SelectAsync(first); Settings.PageZoom = 1.25; ApplySettings(); await Task.Delay(100); Check(await firstCore.ExecuteScriptAsync("document.documentElement.style.zoom") == "\"1.25\"", "Default page zoom affects document"); Settings.PageZoom = 1;
            Settings.PreventTracking = false; ApplySettings(); Check(firstCore.Profile.PreferredTrackingPreventionLevel == Microsoft.Web.WebView2.Core.CoreWebView2TrackingPreventionLevel.None, "Tracking prevention preference reaches native profile"); Settings.PreventTracking = true;
            await PasswordStore.WriteAsync([new(fixture.TrimEnd('/'), "fixture-user", "fixture-password")]); first.Loading = true; firstCore.Reload(); await Wait(() => !first.Loading);
            var fillDeadline = Stopwatch.StartNew(); while (await firstCore.ExecuteScriptAsync("document.querySelector('input[type=password]')?.value") != "\"fixture-password\"") { if (fillDeadline.Elapsed > TimeSpan.FromSeconds(10)) throw new TimeoutException("Password autofill timed out"); await Task.Delay(25); }
            Check(await firstCore.ExecuteScriptAsync("document.querySelector('input[type=password]').value") == "\"fixture-password\"", "Saved password fills matching top-level origin");
            Check(!File.ReadAllText(Path.Combine(DataStore.Root, "settings.json")).Contains("fixture-password"), "Passwords are excluded from plain settings JSON");
            await PasswordStore.SaveAsync(new("https://concurrent.example", "new", "secret"));
            await PasswordStore.SaveAsync(new(fixture.TrimEnd('/'), "fixture-user", "updated"));
            Check((await PasswordStore.ReadAsync()).Any(login => login.Origin == "https://concurrent.example"), "Updating a login preserves concurrently added credentials");
            await PasswordStore.UpdateAsync(logins => logins.RemoveAll(login => login.Origin == "https://concurrent.example"));
            await views[first.Id].ReaderAsync(); Check(await firstCore.ExecuteScriptAsync("!!document.querySelector('#office-reader') && !document.querySelector('nav')") == "true", "Reader uses the macOS article extraction script");
            first.Loading = true; firstCore.Reload(); await Wait(() => !first.Loading); await Task.Delay(100);
            if (Environment.GetEnvironmentVariable("SEARCHEXTRA_TEST_STORE") == "1")
            {
                await VerifyStoreBridgeAsync(Check);
                const string storeId = "aapbdbdomjkkjkaonfhkkikfgjllcleb";
                var folder = await CrxInstaller.FetchAsync(storeId, Path.Combine(DataStore.Root, "StoreProbe")); await InstallExtensionFolderAsync(folder, storeId);
                var storeExtension = Settings.Extensions.Single(e => e.StoreId == storeId); Check(storeExtension.Id == storeId, "Real Chrome store extension installs with original ID");
                var installedFolder = storeExtension.Folder;
                var updateTask = InstallStoreExtensionAsync(storeId);
                await Wait(() => OverlayLayer.Visibility == Visibility.Visible); Root.UpdateLayout();
                Check(FindAddressPart<Microsoft.UI.Xaml.Controls.TextBlock>(OverlayLayer)?.Text == T("Already up to date", "已是最新版本"), "Checking the current store version shows latest-version feedback");
                DismissOverlay(); await updateTask;
                Check(storeExtension.Folder == installedFolder, "Checking an up-to-date store extension does not reinstall it");
                var inlineManager = ShowExtensionManagerAsync(); Root.UpdateLayout();
                var managerCard = OverlayLayer.Children[0];
                var updateMessages = new List<string>();
                await InstallStoreExtensionAsync(storeId, updateMessages.Add, _ => Task.FromResult(true));
                Check(OverlayLayer.Visibility == Visibility.Visible && OverlayLayer.Children[0] == managerCard, "Inline update checking keeps extension management open");
                Check(updateMessages.First() == T("Checking extension updates…", "正在检查扩展更新…") && updateMessages.Last() == T("Already up to date", "已是最新版本"), "Inline update reports progress and latest-version feedback");
                Check(storeExtension.Folder == installedFolder, "Inline latest-version checking does not reinstall the extension");
                var previousVersion = storeExtension.Version;
                storeExtension.Version = "0.0.1"; updateMessages.Clear();
                await InstallStoreExtensionAsync(storeId, updateMessages.Add, permissions =>
                {
                    Check(OverlayLayer.Children[0] == managerCard && permissions.Count > 0, "Update permission confirmation remains inside extension management");
                    return Task.FromResult(true);
                });
                Check(OverlayLayer.Visibility == Visibility.Visible && OverlayLayer.Children[0] == managerCard && storeExtension.Version == previousVersion && storeExtension.Folder != installedFolder,
                    "Installing a newer store package preserves the management page and updates the local version");
                Check(updateMessages.Last() == T("Updated to version ", "已更新至版本 ") + previousVersion, "Inline update displays its successful result and new version");
                DismissOverlay(); await inlineManager;
                await SetExtensionEnabledAsync(storeExtension, false); Check(!(await firstCore.Profile.GetBrowserExtensionsAsync()).Single(e => e.Id == storeId).IsEnabled, "Installed store extension disables natively");
                await SetExtensionEnabledAsync(storeExtension, true); Check((await firstCore.Profile.GetBrowserExtensionsAsync()).Single(e => e.Id == storeId).IsEnabled, "Installed store extension enables natively");
                await RemoveExtensionAsync(storeExtension); Check(!(await firstCore.Profile.GetBrowserExtensionsAsync()).Any(e => e.Id == storeId), "Store extension uninstalls natively");
            }
            if ((Environment.GetEnvironmentVariable("SEARCHEXTRA_TEST_MV2_PACKAGE") ?? Environment.GetEnvironmentVariable("SEARCHEXTRA_TEST_MV2_FOLDER")) is { Length: > 0 } realFolder)
            {
                if (File.Exists(realFolder)) realFolder = await CrxInstaller.ImportAsync(realFolder, Path.Combine(DataStore.Root, "RealMv2"));
                await SelectAsync(first); await InstallExtensionFolderAsync(realFolder); var real = Settings.Extensions.Single(e => e.Folder == Path.GetFullPath(realFolder));
                Check(real.ManifestVersion == 2 && (await firstCore.Profile.GetBrowserExtensionsAsync()).Single(e => e.Id == real.Id).IsEnabled, "Real MV2 extension loads unchanged: " + real.Name + " " + real.Version);
                var dashboard = AddTab($"chrome-extension://{real.Id}/dashboard.html", false); await SelectAsync(dashboard); await Wait(() => !dashboard.Loading && dashboard.Title.Contains("uBlock"));
                Check(await views[dashboard.Id].Control.CoreWebView2.ExecuteScriptAsync("typeof chrome.runtime.sendMessage === 'function' && typeof chrome.storage.local.get === 'function'") == "true", "Real uBlock Origin dashboard has native MV2 APIs");
                var dashboardCore = views[dashboard.Id].Control.CoreWebView2;
                // uBlock intentionally restarts on first Chromium installation (start.js).
                await Task.Delay(1000); dashboardCore.Navigate($"chrome-extension://{real.Id}/dashboard.html");
                var readyDeadline = Stopwatch.StartNew(); while (await dashboardCore.ExecuteScriptAsync("typeof vAPI?.messaging?.send") != "\"function\"") { if (readyDeadline.Elapsed > TimeSpan.FromSeconds(10)) throw new TimeoutException("uBlock dashboard did not recover after initial restart"); await Task.Delay(50); }
                await dashboardCore.ExecuteScriptAsync("window.mv2Rules='pending';(async()=>{while(!await vAPI.messaging.send('dashboard',{what:'readyToFilter'}))await new Promise(r=>setTimeout(r,100));await vAPI.messaging.send('dashboard',{what:'writeUserFilters',enabled:true,content:'*/ublock-test-blocked*'});await vAPI.messaging.send('dashboard',{what:'reloadAllFilters'});window.mv2Diagnostics={filters:await vAPI.messaging.send('dashboard',{what:'readUserFilters'}),tabs:await new Promise(r=>chrome.tabs.query({},r)),ready:await vAPI.messaging.send('dashboard',{what:'readyToFilter'})};window.mv2Rules='ready';})().catch(e=>window.mv2Rules=String(e));");
                var ruleDeadline = Stopwatch.StartNew(); while (await dashboardCore.ExecuteScriptAsync("window.mv2Rules") != "\"ready\"") { if (ruleDeadline.Elapsed > TimeSpan.FromSeconds(20)) throw new TimeoutException("uBlock filter initialization: " + await dashboardCore.ExecuteScriptAsync("JSON.stringify({state:window.mv2Rules,url:location.href,ready:document.readyState,vapi:typeof vAPI})")); await Task.Delay(50); }
                await SelectAsync(first); first.Loading = true; firstCore.Reload(); await Wait(() => !first.Loading); await Task.Delay(200);
                await firstCore.ExecuteScriptAsync("window.ublockResult='pending';fetch('/ublock-test-blocked').then(()=>window.ublockResult='allowed').catch(()=>window.ublockResult='blocked');");
                var fetchDeadline = Stopwatch.StartNew(); while (await firstCore.ExecuteScriptAsync("window.ublockResult") == "\"pending\"") { if (fetchDeadline.Elapsed > TimeSpan.FromSeconds(5)) break; await Task.Delay(25); }
                await dashboardCore.ExecuteScriptAsync("window.mv2DiagDone=false;(async()=>{window.mv2Diagnostics.lists=await vAPI.messaging.send('dashboard',{what:'getLists'});window.mv2Diagnostics.popup=await vAPI.messaging.send('popupPanel',{what:'getPopupData',tabId:window.mv2Diagnostics.tabs[0].id});window.mv2Diagnostics.background=Object.keys(chrome.extension.getBackgroundPage()?.vAPI?.net||{});window.mv2DiagDone=true;})().catch(e=>{window.mv2Diagnostics.error=String(e);window.mv2DiagDone=true;});");
                var diagnosticDeadline = Stopwatch.StartNew(); while (await dashboardCore.ExecuteScriptAsync("window.mv2DiagDone") != "true") { if (diagnosticDeadline.Elapsed > TimeSpan.FromSeconds(5)) break; await Task.Delay(25); }
                await File.WriteAllTextAsync(reportPath + ".mv2.json", JsonSerializer.Deserialize<string>(await dashboardCore.ExecuteScriptAsync("JSON.stringify(window.mv2Diagnostics)")) ?? "{}");
                Check(await firstCore.ExecuteScriptAsync("window.ublockResult") == "\"blocked\"", "Real uBlock Origin MV2 filter blocks a network request: " + await firstCore.ExecuteScriptAsync("window.ublockResult"));
                CloseTab(dashboard); await SelectAsync(first); await RemoveExtensionAsync(real);
            }
            await VerifySitePermissionsAsync(fixture, Check);
            await VerifyBookmarkSiteIconAsync(Check);
            await VerifyBookmarkMiddleInputAsync(fixture, Check);
            await VerifySuperDragAsync(fixture,Check);
            await VerifyPrivacyAndTitleRegressionsAsync(Check);
            await File.WriteAllTextAsync(reportPath, JsonSerializer.Serialize(new { success = true, checks, measurements }, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception ex)
        {
            await File.WriteAllTextAsync(reportPath, JsonSerializer.Serialize(new { success = false, checks, error = ex.ToString(), measurements }, new JsonSerializerOptions { WriteIndented = true }));
        }
        finally
        {
            cancellation.Cancel(); server.Stop(); Close();
        }
    }

    private async Task VerifyStoreBridgeAsync(Action<bool, string> check)
    {
        const string id = "aapbdbdomjkkjkaonfhkkikfgjllcleb";
        const string nextId = "cjpalhdlnbpafiamejdnhcphjbkeiagm";
        using var probe = new PageView(new BrowserTab(), store, () => { }, _ => { });
        Pages.Children.Add(probe.Control);
        try
        {
            await probe.InitializeAsync();
            var core = probe.Control.CoreWebView2;
            var requests = new List<string>(); var downloads = 0;
            probe.StoreInstallRequested += value => { requests.Add(value); return Task.CompletedTask; };
            probe.DownloadStarted += _ => downloads++;
            core.WebResourceRequested += async (_, args) =>
            {
                if (!args.Request.Uri.Contains("searchextra-store-fixture")) return;
                var html = "<!doctype html><title>Store fixture</title><button id='enabled'>Add to Chrome</button><button disabled id='disabled'>添加至 Chrome</button><script>window.originalClicks=0;document.addEventListener('click',()=>window.originalClicks++);</script>";
                var deferral = args.GetDeferral();
                try
                {
                    var stream = new global::Windows.Storage.Streams.InMemoryRandomAccessStream();
                    using var writer = new global::Windows.Storage.Streams.DataWriter(stream);
                    writer.WriteBytes(Encoding.UTF8.GetBytes(html)); await writer.StoreAsync(); writer.DetachStream(); stream.Seek(0);
                    args.Response = core.Environment.CreateWebResourceResponse(stream, 200, "OK", "Content-Type: text/html; charset=utf-8");
                }
                finally { deferral.Complete(); }
            };
            async Task Navigate(string url)
            {
                var loaded = new TaskCompletionSource<bool>();
                void Ready(CoreWebView2 sender, CoreWebView2NavigationCompletedEventArgs args) => loaded.TrySetResult(args.IsSuccess);
                core.NavigationCompleted += Ready;
                try { core.Navigate(url); check(await loaded.Task.WaitAsync(TimeSpan.FromSeconds(20)), "Store bridge fixture loads"); }
                finally { core.NavigationCompleted -= Ready; }
                await Task.Delay(200);
            }
            await Navigate($"https://chromewebstore.google.com/detail/searchextra-store-fixture/{id}");
            check(await core.ExecuteScriptAsync("document.querySelectorAll('button[data-search-store=add]').length") == "2", "Enabled and disabled Chrome install buttons are connected to SearcheXtra");
            await core.ExecuteScriptAsync("document.querySelector('button[data-search-store=add]').click()");
            await Task.Delay(100);
            check(requests.SequenceEqual(new[] { id }) && downloads == 0 && await core.ExecuteScriptAsync("window.originalClicks") == "0", "Store button invokes native installation without Chrome's download handler");
            await core.ExecuteScriptAsync($"history.pushState(null,'','/detail/searchextra-store-fixture/{nextId}')");
            await Task.Delay(100);
            await core.ExecuteScriptAsync("document.querySelector('button[data-search-store=add]').click()");
            await Task.Delay(100);
            check(requests.Last() == nextId, "Store SPA navigation installs the current listing");
            await core.ExecuteScriptAsync($"chrome.webview.postMessage({{type:'store-install',id:'{id}'}})");
            await Task.Delay(100);
            check(requests.Last() == nextId, "Store installation ignores IDs supplied by page messages");
            var count = requests.Count;
            await Navigate($"https://store-fixture.invalid/detail/searchextra-store-fixture/{id}");
            await core.ExecuteScriptAsync("chrome.webview.postMessage({type:'store-install'})");
            await Task.Delay(100);
            check(requests.Count == count, "Non-store origins cannot request extension installation");
        }
        finally { Pages.Children.Remove(probe.Control); }
    }
}
