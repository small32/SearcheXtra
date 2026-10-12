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
}
