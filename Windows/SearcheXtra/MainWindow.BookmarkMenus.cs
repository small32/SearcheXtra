using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using System.Text.Json;
using Windows.ApplicationModel.DataTransfer;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private const string BookmarkClipboardFormat = "SearcheXtra.Bookmarks";
    private static (Guid Id, string Json)? cutBookmark;

    private void OpenBookmarkInBackground(Bookmark node)
    {
        if (node.Url is { } url && AddressParser.IsWeb(url)) AddTab(url, false, active?.IsPrivate == true);
    }

    private void BindBookmarkInteractions(FrameworkElement target, Bookmark node, Action? changed = null, Func<Func<Task>, Task>? dialog = null)
    {
        target.Tag = node;
        target.ContextFlyout = BookmarkBarContextMenu(node, changed, dialog);
        target.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler((_, args) => {
            if (args.GetCurrentPoint(target).Properties.PointerUpdateKind != Microsoft.UI.Input.PointerUpdateKind.MiddleButtonPressed || node.Url == null) return;
            OpenBookmarkInBackground(node);
            args.Handled = true;
        }), true);
    }

    private List<Bookmark> BookmarkParent(Bookmark node)
    {
        List<Bookmark>? Find(List<Bookmark> nodes) {
            if (nodes.Contains(node)) return nodes;
            foreach (var folder in nodes) if (folder.Children is { } children && Find(children) is { } found) return found;
            return null;
        }
        return Find(store.Bookmarks) ?? store.Bookmarks;
    }

    private MenuFlyout BookmarkBarContextMenu(Bookmark? node, Action? changed = null, Func<Func<Task>, Task>? dialog = null)
    {
        var menu = new MenuFlyout();
        var parent = node?.Children ?? (node == null ? store.Bookmarks : BookmarkParent(node));
        var parentId = node?.Children != null ? node.Id : BookmarkImport.Flatten(store.Bookmarks).FirstOrDefault(folder => folder.Children == parent)?.Id;
        MenuFlyoutItem Action(string en, string zh, Action action, bool enabled = true) {
            var item = new MenuFlyoutItem { Text = T(en, zh), IsEnabled = enabled };
            item.Click += (_, _) => action(); menu.Items.Add(item); return item;
        }
        void Changed() { store.Notify(); ScheduleSave(); changed?.Invoke(); }
        void DialogAction(string en, string zh, Func<Task> action) => Action(en, zh, async () => { if (dialog == null) await action(); else await dialog(action); });
        DialogAction("Add page…", "添加网页…", async () => {
            var name = await PromptAsync(T("Add bookmark", "添加书签"), T("Name", "名称"), active?.Title ?? "");
            if (name == null) return;
            var url = await PromptAsync(T("Bookmark address", "书签网址"), "https://example.com", active?.Url ?? "");
            if (url != null && AddressParser.IsWeb(url)) { parent.Add(new() { Title = name, Url = url }); Changed(); }
        });
        DialogAction("Add folder…", "添加文件夹…", async () => {
            var name = await PromptAsync(T("New folder", "新建文件夹"), T("Name", "名称"));
            if (!string.IsNullOrWhiteSpace(name)) { parent.Add(new() { Title = name, Children = [] }); Changed(); }
        });
        menu.Items.Add(new MenuFlyoutSeparator());
        var urls = BookmarkImport.Flatten(node == null ? store.Bookmarks : [node]).Where(b => b.Url != null && AddressParser.IsWeb(b.Url)).Select(b => b.Url!).ToArray();
        var single = node is { Children: null, Url: not null };
        if (single) {
            Action("Open", "打开", () => OpenBookmark(node!.Url!));
            Action("Open in new tab", "在新标签页中打开", () => OpenBookmarkInBackground(node!));
        } else Action($"Open all ({urls.Length}) bookmarks", $"打开全部（{urls.Length} 个）书签", () => { foreach (var url in urls) AddTab(url, false, active?.IsPrivate == true); }, urls.Length > 0);
        void OpenWindow(bool isPrivate) {
            var window = App.NewWindow(initialUrl: isPrivate ? null : urls[0]);
            if (isPrivate) {
                var initial = window.tabs.ToArray();
                foreach (var url in urls) window.AddTab(url, window.tabs.Count == initial.Length, true);
                foreach (var tab in initial) window.CloseTab(tab);
            } else foreach (var url in urls.Skip(1)) window.AddTab(url, false);
        }
        Action(single ? "Open in new window" : $"Open all ({urls.Length}) in a new window", single ? "在新窗口中打开" : $"在新窗口中打开全部（{urls.Length} 个）书签", () => OpenWindow(false), urls.Length > 0);
        Action(single ? "Open in private window" : $"Open all ({urls.Length}) in a private window", single ? "在无痕窗口中打开" : $"在无痕窗口中打开全部（{urls.Length} 个）网址", () => OpenWindow(true), urls.Length > 0);
        Action($"Open all ({urls.Length}) in a new tab group", $"在新标签页组中打开全部（{urls.Length} 个）网址", () => {
            Settings.UsesTabGroups = true;
            var name = node?.Title ?? T("Bookmarks", "书签");
            var unique = name; var suffix = 2;
            while (tabs.Any(tab => tab.Group == unique && tab.Space == space)) unique = name + " " + suffix++;
            var isPrivate = active?.IsPrivate == true;
            foreach (var url in urls) AddTab(url, false, isPrivate, group: unique);
            ApplySettings(); ScheduleSave();
        }, urls.Length > 0);
        if (node != null) {
            menu.Items.Add(new MenuFlyoutSeparator());
            if (single) DialogAction("Edit bookmark…", "修改书签…", async () => {
                var name = await PromptAsync(T("Edit bookmark…", "修改书签…"), T("Name", "名称"), node.Title);
                if (string.IsNullOrWhiteSpace(name)) return;
                var url = await PromptAsync(T("Bookmark address", "书签网址"), "https://example.com", node.Url!);
                if (url != null && AddressParser.IsWeb(url)) { node.Title = name; node.Url = url; Changed(); }
            });
            else DialogAction("Rename…", "重命名…", async () => { var name = await PromptAsync(T("Rename", "重命名"), T("Name", "名称"), node.Title); if (!string.IsNullOrWhiteSpace(name)) { node.Title = name; Changed(); } });
            menu.Items.Add(new MenuFlyoutSeparator());
            void Copy(bool cut) {
                var json = JsonSerializer.Serialize(node);
                var data = new DataPackage(); data.SetData(BookmarkClipboardFormat, json);
                if (node.Url != null) data.SetText(node.Url);
                Clipboard.SetContent(data); cutBookmark = cut ? (node.Id, json) : null;
            }
            Action("Cut", "剪切", () => Copy(true)); Action("Copy", "复制", () => Copy(false));
        }
        var paste = Action("Paste", "粘贴", async () => {
            var content = Clipboard.GetContent();
            if (!content.Contains(BookmarkClipboardFormat)) return;
            var json = (string)await content.GetDataAsync(BookmarkClipboardFormat);
            if (cutBookmark is { } cut && cut.Json == json) {
                if (BookmarkImport.Move(store.Bookmarks, [cut.Id], parentId)) { cutBookmark = null; Changed(); }
            } else if (JsonSerializer.Deserialize<Bookmark>(json) is { } copied) {
                void Renew(Bookmark bookmark) { bookmark.Id = Guid.NewGuid(); if (bookmark.Children != null) foreach (var child in bookmark.Children) Renew(child); }
                Renew(copied); parent.Add(copied); Changed();
            }
        }, Clipboard.GetContent().Contains(BookmarkClipboardFormat));
        menu.Opening += (_, _) => paste.IsEnabled = Clipboard.GetContent().Contains(BookmarkClipboardFormat);
        if (node != null) {
            menu.Items.Add(new MenuFlyoutSeparator());
            Action("Delete", "删除", () => {
                void Remove(List<Bookmark> nodes) { nodes.Remove(node); foreach (var folder in nodes) if (folder.Children != null) Remove(folder.Children); }
                Remove(store.Bookmarks); Changed();
            });
        }
        menu.Items.Add(new MenuFlyoutSeparator());
        if (dialog == null) Action("Open bookmark manager", "打开书签管理器", async () => await ShowBookmarksAsync(node?.Children != null ? node.Id : null));
        var bar = new MenuFlyoutSubItem { Text = T("Bookmarks bar", "书签栏") };
        void Option(string en, string zh, bool value, Action<bool> change) {
            var item = new ToggleMenuFlyoutItem { Text = T(en, zh), IsChecked = value };
            item.Click += (_, _) => { change(item.IsChecked); ApplySettings(); ScheduleSave(); }; bar.Items.Add(item);
        }
        Option("Show bookmarks bar", "显示书签栏", Settings.BookmarksBar, value => Settings.BookmarksBar = value);
        Option("Compact bookmarks bar", "紧凑书签栏", Settings.CompactBookmarksBar, value => Settings.CompactBookmarksBar = value);
        Option("Bookmarks bar folder icons", "书签栏文件夹图标", Settings.BookmarkBarFolderIcons, value => Settings.BookmarkBarFolderIcons = value);
        Option("Show bookmark website icons", "书签显示网站图标", Settings.BookmarkWebsiteIcons, value => Settings.BookmarkWebsiteIcons = value);
        menu.Items.Add(bar);
        return menu;
    }
}
