using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private async Task VerifyPrivacyAndTitleRegressionsAsync(Action<bool, string> check)
    {
        var original = active!;
        var previousSidebar = Settings.Sidebar;
        var previousGlyphs = Settings.IconGlyphs;
        Settings.Sidebar = false;
        Settings.IconGlyphs = false;
        ApplySettings();

        var letterTab = AddTab("about:blank", false);
        await SelectAsync(letterTab);
        await Task.Delay(150);
        TopTabs.ScrollIntoView(letterTab);
        Root.UpdateLayout();
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (TopTabs.ContainerFromItem(letterTab) == null)
        {
            if (DateTime.UtcNow > deadline) throw new TimeoutException("Letter regression tab was not realized");
            await Task.Delay(25);
            Root.UpdateLayout();
        }
        var item = (ListViewItem)TopTabs.ContainerFromItem(letterTab);
        var letter = FindAddressPart<TextBlock>(item, "TabLetter")!;
        letterTab.Title = "Google";
        Root.UpdateLayout();
        check(letter.Text == "G", "Loaded title updates the visible letter without rebuilding tabs");
        await SelectAsync(original);
        CloseTab(letterTab);

        var privateTab = AddTab("about:blank", false, true);
        await SelectAsync(privateTab);
        var node = new Bookmark { Title = "Privacy regression", Children = [
            new() { Title = "First", Url = "http://127.0.0.1:1/private-first" },
            new() { Title = "Second", Url = "http://127.0.0.1:1/private-second" }
        ] };
        var menu = BookmarkBarContextMenu(node);
        var group = menu.Items.OfType<MenuFlyoutItem>().Single(entry => entry.Text ==
            T("Open all (2) in a new tab group", "在新标签页组中打开全部（2 个）网址"));
        var before = tabs.ToHashSet();
        menu.ShowAt(ExtensionsButton);
        var peer = new MenuFlyoutItemAutomationPeer(group);
        ((IInvokeProvider)peer.GetPattern(PatternInterface.Invoke)).Invoke();
        menu.Hide();
        var created = tabs.Where(tab => !before.Contains(tab)).ToArray();
        check(created.Length == 2 && created.All(tab => tab.IsPrivate), "Bookmark groups retain private browsing for every new tab");
        await SaveStateAsync();
        check(store.Session.Tabs.All(tab => !tab.Url.Contains("private-first") && !tab.Url.Contains("private-second")),
            "Private bookmark group addresses stay out of persisted sessions");
        foreach (var tab in created) CloseTab(tab);
        await SelectAsync(original);
        CloseTab(privateTab);

        var previousSpace = space;
        var privateSpace = "Private regression " + Guid.NewGuid().ToString("N");
        store.Spaces.Add(privateSpace);
        space = privateSpace;
        var lastPrivate = AddTab("http://127.0.0.1:1/private-last", false, true);
        await SelectAsync(lastPrivate);
        CloseTab(lastPrivate);
        var replacement = active!;
        check(replacement.IsPrivate && replacement.Url == "", "Closing the last private page leaves a private blank tab");
        await SelectAsync(original);
        space = previousSpace;
        CloseTab(replacement);
        store.Spaces.Remove(privateSpace);
        Settings.SpaceProfiles.Remove(privateSpace);
        Settings.Sidebar = previousSidebar;
        Settings.IconGlyphs = previousGlyphs;
        ApplySettings();
    }

    private async Task VerifyResourceRegressionsAsync(string fixture, Action<bool, string> check)
    {
        var previousDownloads = store.Downloads;
        var previousBlocking = Settings.BlockTrackers;
        var original = active;
        var viewTab = AddTab(fixture + "resource-test", false);
        async Task Wait(Func<bool> predicate)
        {
            var deadline = DateTime.UtcNow.AddSeconds(15);
            while (!predicate())
            {
                if (DateTime.UtcNow > deadline) throw new TimeoutException("Resource regression timed out");
                await Task.Delay(25);
            }
        }
        try
        {
            var first = new DownloadRecord("first-download.txt", fixture + "first-download", DateTimeOffset.Now);
            var incoming = new DownloadRecord("incoming-download.txt", fixture + "incoming-download", DateTimeOffset.Now);
            store.Downloads = [first];
            var downloadsPanel = ShowDownloadsAsync();
            try
            {
                Root.UpdateLayout();
                var history = FindAddressPart<ListView>(OverlayLayer, "DownloadHistoryList")!;
                history.SelectedIndex = 0;
                store.Downloads.Insert(0, incoming);
                var forget = FindButtons(OverlayLayer).Single(button => Equals(button.Content, T("Forget record", "删除记录")));
                ((IInvokeProvider)new ButtonAutomationPeer(forget).GetPattern(PatternInterface.Invoke)).Invoke();
                check(store.Downloads.SequenceEqual(new[] { incoming }),
                    "Deleting a displayed download retains a newer download added while the panel was open");
            }
            finally { DismissOverlay(); await downloadsPanel; }

            await SelectAsync(viewTab);
            var page = views[viewTab.Id];
            await Wait(() => !viewTab.Loading);
            var requests = 0;
            void Requested(Microsoft.Web.WebView2.Core.CoreWebView2 sender, Microsoft.Web.WebView2.Core.CoreWebView2WebResourceRequestedEventArgs args) => requests++;
            page.Control.CoreWebView2.WebResourceRequested += Requested;
            try
            {
                foreach (var enabled in new[] { false, true })
                {
                    Settings.BlockTrackers = enabled; page.ApplySettings(); requests = 0;
                    var address = fixture + "resource-test-" + enabled;
                    page.Navigate(address);
                    await Wait(() => !viewTab.Loading && page.Control.CoreWebView2.Source == address);
                    check(enabled ? requests > 0 : requests == 0,
                        enabled ? "Enabling tracker blocking restores native request filtering" : "Disabled tracker blocking avoids native request callbacks entirely");
                }
            }
            finally { page.Control.CoreWebView2.WebResourceRequested -= Requested; }

            var secondary = App.NewWindow();
            var pendingPanel = secondary.ShowDownloadsAsync();
            secondary.Close();
            await pendingPanel.WaitAsync(TimeSpan.FromSeconds(10));
            check(pendingPanel.IsCompletedSuccessfully, "Closing a window completes its downloads panel and releases its refresh timer");
        }
        finally
        {
            DismissOverlay(); store.Downloads = previousDownloads; Settings.BlockTrackers = previousBlocking;
            if (original != null && tabs.Contains(original)) await SelectAsync(original);
            CloseTab(viewTab); ApplySettings();
        }

        static IEnumerable<Button> FindButtons(DependencyObject root)
        {
            if (root is Button button) yield return button;
            for (var index = 0; index < Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(root); index++)
                foreach (var child in FindButtons(Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(root, index))) yield return child;
        }
    }
}
