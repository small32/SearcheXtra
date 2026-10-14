using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private async Task VerifyBookmarkInteractionsAsync(string fixture, Action<bool, string> check)
    {
        var previousBookmarks = store.Bookmarks;
        var previousOpening = Settings.BookmarkOpening;
        var previousBar = Settings.BookmarksBar;
        var previousIcons = Settings.BookmarkWebsiteIcons;
        var previousLazy = Settings.LazyBackgroundTabs;
        var initialTabs = tabs.ToHashSet();
        var previousActive = active;
        async Task Wait(Func<bool> ready)
        {
            var deadline = DateTime.UtcNow.AddSeconds(15);
            while (!ready())
            {
                if (DateTime.UtcNow > deadline) throw new TimeoutException("Bookmark interaction test timed out");
                await Task.Delay(25);
            }
        }
        IEnumerable<T> Descendants<T>(DependencyObject root) where T : DependencyObject
        {
            if (root is T own) yield return own;
            for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
                foreach (var child in Descendants<T>(VisualTreeHelper.GetChild(root, i))) yield return child;
        }
        void InvokeButton(Button button) => ((IInvokeProvider)new ButtonAutomationPeer(button).GetPattern(PatternInterface.Invoke)).Invoke();
        void InvokeMenu(MenuFlyout menu, string en, string zh, FrameworkElement? anchor = null)
        {
            menu.ShowAt(anchor ?? BookmarkScroller);
            Root.UpdateLayout();
            var item = menu.Items.OfType<MenuFlyoutItem>().Single(entry => entry.Text == T(en, zh));
            ((IInvokeProvider)new MenuFlyoutItemAutomationPeer(item).GetPattern(PatternInterface.Invoke)).Invoke();
            menu.Hide();
        }
        async Task SavePrompt(string title, string value)
        {
            await Wait(() => OverlayLayer.Visibility == Visibility.Visible && Descendants<TextBlock>(OverlayLayer).Any(label => label.Text == title));
            Root.UpdateLayout();
            Descendants<TextBox>(OverlayLayer).Single().Text = value;
            InvokeButton(Descendants<Button>(OverlayLayer).Single(button => Equals(button.Content, T("Save", "保存"))));
        }
        try
        {
            Settings.BookmarksBar = true;
            Settings.BookmarkWebsiteIcons = false;
            Settings.LazyBackgroundTabs = true;
            var source = AddTab(fixture + "bookmark-source", false);
            await SelectAsync(source);
            await Wait(() => !source.Loading && source.Title == "SearcheXtra fixture");
            var leaf = new Bookmark { Title = "Top bookmark", Url = fixture + "bookmark-top" };
            var nestedLeaf = new Bookmark { Title = "Nested bookmark", Url = fixture + "bookmark-nested" };
            var deepLeaf = new Bookmark { Title = "Deep bookmark", Url = fixture + "bookmark-deep" };
            var deepFolder = new Bookmark { Title = "Deep folder", Children = [deepLeaf] };
            var folder = new Bookmark { Title = "Folder", Children = [nestedLeaf, deepFolder] };
            store.Bookmarks = [leaf, folder];
            ApplySettings();
            Root.UpdateLayout();
            check(BookmarkScroller.ContextFlyout is MenuFlyout && BookmarkRow.ContextFlyout is MenuFlyout &&
                BookmarkScroller.Background != null && BookmarkScroller.MinHeight >= 28,
                "The full bookmarks bar, including its empty area, exposes a context menu and a hit-testable surface");
            var leafButton = BookmarkRow.Children.OfType<Button>().Single(button => ReferenceEquals(button.Tag, leaf));
            var folderButton = BookmarkRow.Children.OfType<Button>().Single(button => ReferenceEquals(button.Tag, folder));
            var leafMenu = (MenuFlyout)leafButton.ContextFlyout;
            check(leafMenu.Items.OfType<MenuFlyoutItem>().Any(item => item.Text == T("Edit bookmark…", "修改书签…")) &&
                leafMenu.Items.OfType<MenuFlyoutItem>().Any(item => item.Text == T("Open in new tab", "在新标签页中打开")) &&
                leafMenu.Items.OfType<MenuFlyoutItem>().Any(item => item.Text == T("Delete", "删除")),
                "Top-level bookmark context menus include opening, address editing and removal");
            var dropdown = (MenuFlyout)folderButton.Flyout;
            var childItem = dropdown.Items.OfType<MenuFlyoutItem>().Single(item => ReferenceEquals(item.Tag, nestedLeaf));
            var subItem = dropdown.Items.OfType<MenuFlyoutSubItem>().Single(item => ReferenceEquals(item.Tag, deepFolder));
            var deepItem = subItem.Items.OfType<MenuFlyoutItem>().Single(item => ReferenceEquals(item.Tag, deepLeaf));
            check(childItem.ContextFlyout is MenuFlyout && subItem.ContextFlyout is MenuFlyout && deepItem.ContextFlyout is MenuFlyout,
                "Dropdown bookmarks and folders retain their own context menus at every nesting level");
            check(((MenuFlyout)subItem.ContextFlyout).Items.OfType<MenuFlyoutItem>().Any(item => item.Text == T("Rename…", "重命名…")),
                "Nested folder context menus include folder management actions");

            Settings.BookmarkOpening = BookmarkOpening.Default;
            var before = tabs.Count;
            InvokeButton(leafButton);
            await Wait(() => active == source && source.Url == leaf.Url && !source.Loading && views[source.Id].Control.CoreWebView2.Source == leaf.Url);
            check(tabs.Count == before, "Default left-click bookmark opening navigates the current tab without creating another tab");
            await NavigateAsync(fixture + "bookmark-source");
            await Wait(() => !source.Loading && views[source.Id].Control.CoreWebView2.Source == fixture + "bookmark-source");
            Settings.BookmarkOpening = BookmarkOpening.Foreground;
            var existing = tabs.ToHashSet();
            InvokeButton(leafButton);
            await Wait(() => tabs.Count == existing.Count + 1 && active != source);
            var foreground = tabs.Single(tab => !existing.Contains(tab));
            check(active == foreground && foreground.Url == leaf.Url, "Left-click bookmarks honor the foreground-tab preference");
            await SelectAsync(source);
            CloseTab(foreground);

            foreach (var opening in new[] { BookmarkOpening.Default, BookmarkOpening.Foreground })
            {
                Settings.BookmarkOpening = opening;
                existing = tabs.ToHashSet();
                OpenBookmarkInBackground(deepLeaf);
                var middle = tabs.Single(tab => !existing.Contains(tab));
                check(active == source && source.Url == fixture + "bookmark-source" && middle.Url == deepLeaf.Url &&
                    !middle.IsPrivate && !views.ContainsKey(middle.Id),
                    "Middle-click bookmark opening always creates one background tab with the " + opening + " left-click preference");
                CloseTab(middle);
            }
            before = tabs.Count;
            OpenBookmarkInBackground(folder);
            OpenBookmarkInBackground(new() { Title = "Invalid", Url = "javascript:alert(1)" });
            check(tabs.Count == before, "Middle-click opening ignores folders and non-web addresses");

            existing = tabs.ToHashSet();
            InvokeMenu((MenuFlyout)deepItem.ContextFlyout, "Open in new tab", "在新标签页中打开");
            await Wait(() => tabs.Count == existing.Count + 1);
            var menuTab = tabs.Single(tab => !existing.Contains(tab));
            check(active == source && menuTab.Url == deepLeaf.Url && Settings.BookmarkOpening == BookmarkOpening.Foreground,
                "A nested bookmark's explicit new-tab menu creates one background tab without changing the left-click preference");
            CloseTab(menuTab);

            var privateSource = AddTab(fixture + "bookmark-private", false, true);
            await SelectAsync(privateSource);
            await Wait(() => !privateSource.Loading && privateSource.Title == "SearcheXtra fixture");
            existing = tabs.ToHashSet();
            OpenBookmarkInBackground(leaf);
            var privateResult = tabs.Single(tab => !existing.Contains(tab));
            check(active == privateSource && privateResult.IsPrivate && privateResult.Url == leaf.Url,
                "Middle-click bookmarks preserve private browsing without switching the active page");
            await SelectAsync(source);
            CloseTab(privateResult);
            CloseTab(privateSource);

            InvokeMenu(leafMenu, "Edit bookmark…", "修改书签…");
            await SavePrompt(T("Edit bookmark…", "修改书签…"), "Edited bookmark");
            await SavePrompt(T("Bookmark address", "书签网址"), fixture + "bookmark-edited");
            await Wait(() => leaf.Title == "Edited bookmark" && leaf.Url == fixture + "bookmark-edited");
            check(leaf.Title == "Edited bookmark" && leaf.Url == fixture + "bookmark-edited",
                "Bookmark context-menu editing saves both the displayed title and destination address");
            InvokeMenu((MenuFlyout)subItem.ContextFlyout, "Add folder…", "添加文件夹…");
            await SavePrompt(T("New folder", "新建文件夹"), "Created inside deep folder");
            await Wait(() => deepFolder.Children!.Any(node => node.Title == "Created inside deep folder"));
            var created = deepFolder.Children!.Single(node => node.Title == "Created inside deep folder");
            check(created.Children is { Count: 0 } && !store.Bookmarks.Contains(created),
                "Creating a folder from a nested folder's context menu places it inside that folder");
            InvokeMenu(BookmarkBarContextMenu(created), "Rename…", "重命名…");
            await SavePrompt(T("Rename", "重命名"), "Renamed nested folder");
            await Wait(() => created.Title == "Renamed nested folder");
            check(created.Title == "Renamed nested folder", "Nested folder context-menu renaming updates its model");
            InvokeMenu((MenuFlyout)childItem.ContextFlyout, "Add page…", "添加网页…");
            await SavePrompt(T("Add bookmark", "添加书签"), "Sibling bookmark");
            await SavePrompt(T("Bookmark address", "书签网址"), fixture + "bookmark-sibling");
            await Wait(() => folder.Children!.Any(node => node.Title == "Sibling bookmark"));
            check(folder.Children!.Any(node => node.Url == fixture + "bookmark-sibling") &&
                store.Bookmarks.All(node => node.Url != fixture + "bookmark-sibling"),
                "A nested bookmark's add-page context action creates a sibling in its actual parent folder");
            InvokeMenu(BookmarkBarContextMenu(created), "Delete", "删除");
            await Wait(() => !deepFolder.Children!.Contains(created));
            check(!deepFolder.Children!.Contains(created), "Deleting a nested folder through its context menu removes it from the correct parent");

            var manager = ShowBookmarksAsync(folder.Id);
            try
            {
                await Wait(() => OverlayLayer.Visibility == Visibility.Visible);
                Root.UpdateLayout();
                var list = FindAddressPart<ListView>(OverlayLayer, "BookmarkManagerList")!;
                var managerItem = list.Items.Cast<ListViewItem>().Single(item => ReferenceEquals(item.Tag, nestedLeaf));
                check(managerItem.ContextFlyout is MenuFlyout && list.ContextFlyout is MenuFlyout,
                    "Bookmark manager rows and folder empty space expose their context menus");
                InvokeMenu((MenuFlyout)managerItem.ContextFlyout, "Edit bookmark…", "修改书签…", managerItem);
                await SavePrompt(T("Edit bookmark…", "修改书签…"), "Edited in manager");
                await SavePrompt(T("Bookmark address", "书签网址"), fixture + "bookmark-manager-edited");
                await Wait(() => FindAddressPart<ListView>(OverlayLayer, "BookmarkManagerList") != null && nestedLeaf.Title == "Edited in manager");
                Root.UpdateLayout();
                list = FindAddressPart<ListView>(OverlayLayer, "BookmarkManagerList")!;
                managerItem = list.Items.Cast<ListViewItem>().Single(item => ReferenceEquals(item.Tag, nestedLeaf));
                check(nestedLeaf.Url == fixture + "bookmark-manager-edited" &&
                    list.Items.Cast<ListViewItem>().Select(item => (Bookmark)item.Tag).SequenceEqual(folder.Children!) &&
                    Descendants<TextBlock>(managerItem).Any(label => label.Text.Contains("Edited in manager") && label.Text.Contains(nestedLeaf.Url)),
                    "Bookmark manager context editing saves the name and address and returns to the same folder with refreshed rows");
                InvokeMenu((MenuFlyout)list.ContextFlyout, "Add folder…", "添加文件夹…", list);
                await SavePrompt(T("New folder", "新建文件夹"), "Created in manager");
                await Wait(() => FindAddressPart<ListView>(OverlayLayer, "BookmarkManagerList") != null && folder.Children!.Any(node => node.Title == "Created in manager"));
                Root.UpdateLayout();
                list = FindAddressPart<ListView>(OverlayLayer, "BookmarkManagerList")!;
                check(list.Items.Cast<ListViewItem>().Select(item => (Bookmark)item.Tag).SequenceEqual(folder.Children!) &&
                    folder.Children!.Single(node => node.Title == "Created in manager").Children is { Count: 0 },
                    "Bookmark manager empty-space folder creation returns to the original directory and displays the new folder");
                managerItem = list.Items.Cast<ListViewItem>().Single(item => ReferenceEquals(item.Tag, nestedLeaf));
                InvokeMenu((MenuFlyout)managerItem.ContextFlyout, "Delete", "删除", managerItem);
                await Wait(() => !folder.Children!.Contains(nestedLeaf) && list.Items.Cast<ListViewItem>().All(item => !ReferenceEquals(item.Tag, nestedLeaf)));
                check(OverlayLayer.Visibility == Visibility.Visible && !folder.Children!.Contains(nestedLeaf),
                    "Bookmark manager context deletion refreshes the open list without dismissing the manager");
            }
            finally { DismissOverlay(); await manager; }
        }
        finally
        {
            DismissOverlay();
            if (previousActive != null && tabs.Contains(previousActive)) await SelectAsync(previousActive);
            foreach (var tab in tabs.Where(tab => !initialTabs.Contains(tab)).ToArray()) CloseTab(tab);
            store.Bookmarks = previousBookmarks;
            Settings.BookmarkOpening = previousOpening;
            Settings.BookmarksBar = previousBar;
            Settings.BookmarkWebsiteIcons = previousIcons;
            Settings.LazyBackgroundTabs = previousLazy;
            store.Notify();
        }
    }
}
