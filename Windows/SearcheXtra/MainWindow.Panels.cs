using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using System.Diagnostics;
using System.Text.Json;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private async Task<string?> PromptAsync(string title, string placeholder, string value = "")
    {
        var box = new TextBox { PlaceholderText = placeholder, Text = value, MinWidth = 320 };
        return await ShowCardAsync(title, box, T("Save", "保存")) == ContentDialogResult.Primary ? box.Text.Trim() : null;
    }

    private void RefreshBookmarkBar()
    {
        BookmarkRow.Children.Clear();
        BookmarkRow.Spacing = Settings.CompactBookmarksBar ? 0 : 2;
        BookmarkRow.Padding = new(Settings.CompactBookmarksBar ? 6 : 10, 2, Settings.CompactBookmarksBar ? 6 : 10, 2);
        BookmarkRow.ContextFlyout = BookmarkBarContextMenu(null);
        foreach (var node in store.Bookmarks)
        {
            var button = new Button { Padding = new(Settings.CompactBookmarksBar ? 4 : 8, 3, Settings.CompactBookmarksBar ? 4 : 8, 3), MaxWidth = 190, Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent), BorderThickness = new(0) };
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = Settings.CompactBookmarksBar ? 3 : 6 };
            if (node.Children != null) {
                if (Settings.BookmarkBarFolderIcons) row.Children.Add(Glyph("folder"));
            } else if (Settings.BookmarkWebsiteIcons && node.Url is { } address && AddressParser.IsWeb(address)) {
                var site = new Uri(address);
                var iconUrl = views.Values.FirstOrDefault(page => AddressParser.IsWeb(page.Control.CoreWebView2?.Source ?? "") && new Uri(page.Control.CoreWebView2!.Source).GetLeftPart(UriPartial.Authority) == site.GetLeftPart(UriPartial.Authority))?.Control.CoreWebView2?.FaviconUri;
                if (!AddressParser.IsWeb(iconUrl ?? "")) iconUrl = site.GetLeftPart(UriPartial.Authority) + "/favicon.ico";
                var icon = new Image { Source = Icon(iconUrl!), Width = 13, Height = 13 };
                var fallback = new TextBlock { Text = site.Host.Replace("www.", "")[..1].ToUpperInvariant(), FontSize = 10, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
                var mark = new Grid { Width = 13, Height = 13 };
                mark.Children.Add(fallback); mark.Children.Add(icon);
                icon.ImageOpened += (_, _) => fallback.Visibility = Visibility.Collapsed;
                icon.ImageFailed += (_, _) => icon.Visibility = Visibility.Collapsed;
                row.Children.Add(mark);
            }
            row.Children.Add(new TextBlock { Text = node.Title, FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis });
            button.Content = row;
            button.ContextFlyout = BookmarkBarContextMenu(node);
            ToolTipService.SetToolTip(button, node.Url ?? node.Title);
            if (node.Children != null)
            {
                var menu = new MenuFlyout { Placement = Microsoft.UI.Xaml.Controls.Primitives.FlyoutPlacementMode.BottomEdgeAlignedLeft };
                foreach (var item in BookmarkMenuItems(node.Children)) menu.Items.Add(item);
                menu.Opening += (_, _) => {
                    var bottom = button.TransformToVisual(Root).TransformPoint(new(0, button.ActualHeight)).Y;
                    var style = new Style(typeof(MenuFlyoutPresenter));
                    style.Setters.Add(new Setter(FrameworkElement.MaxHeightProperty, Math.Max(1, Root.ActualHeight - bottom - 16)));
                    style.Setters.Add(new Setter(FrameworkElement.MinHeightProperty, 0d));
                    if (Settings.CompactBookmarksBar) style.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(4)));
                    menu.MenuFlyoutPresenterStyle = style;
                };
                button.Flyout = menu;
            }
            else button.Click += (_, _) => OpenBookmark(node.Url!);
            button.PointerPressed += (_, args) =>
            {
                var properties = args.GetCurrentPoint(button).Properties;
                if (properties.IsMiddleButtonPressed && node.Url != null)
                {
                    var foreground = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(global::Windows.System.VirtualKey.Shift).HasFlag(global::Windows.UI.Core.CoreVirtualKeyStates.Down);
                    AddTab(node.Url, foreground, active?.IsPrivate == true); args.Handled = true;
                }
            };
            BookmarkRow.Children.Add(button);
        }
    }
    private IEnumerable<MenuFlyoutItemBase> BookmarkMenuItems(IEnumerable<Bookmark> nodes)
    {
        foreach (var node in nodes)
        {
            if (node.Children != null)
            {
                var sub = new MenuFlyoutSubItem { Text = node.Title };
                CompactBookmarkMenuItem(sub);
                foreach (var child in BookmarkMenuItems(node.Children)) sub.Items.Add(child);
                yield return sub;
            }
            else
            {
                var item = new MenuFlyoutItem { Text = node.Title };
                CompactBookmarkMenuItem(item);
                item.Click += (_, _) => OpenBookmark(node.Url!);
                yield return item;
            }
        }
    }
    private void CompactBookmarkMenuItem(Control item)
    {
        if (!Settings.CompactBookmarksBar) return;
        item.MinHeight = 24;
        item.Padding = new(8, 2, 8, 2);
        item.FontSize = 12;
    }
    private void OpenBookmark(string url)
    {
        if (!AddressParser.IsWeb(url)) return;
        var control = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(global::Windows.System.VirtualKey.Control).HasFlag(global::Windows.UI.Core.CoreVirtualKeyStates.Down);
        if (control) { AddTab(url, false, active?.IsPrivate == true); return; }
        switch (Settings.BookmarkOpening)
        {
            case BookmarkOpening.Background: AddTab(url, false, active?.IsPrivate == true); break;
            case BookmarkOpening.Foreground: AddTab(url, true, active?.IsPrivate == true); break;
            default: _ = NavigateAsync(url); break;
        }
    }
    private async Task AddBookmarkAsync()
    {
        if (active == null || !AddressParser.IsWeb(active.Url)) return;
        var title = await PromptAsync(T("Add bookmark", "添加书签"), T("Name", "名称"), active.Title.Length > 0 ? active.Title : active.Url);
        if (string.IsNullOrWhiteSpace(title)) return;
        store.Bookmarks.Add(new() { Title = title, Url = active.Url });
        store.Notify(); ScheduleSave();
    }

    private async Task ShowBookmarksAsync(Guid? folderId = null)
    {
        var panel = new StackPanel { Spacing = 10, Width = Math.Min(620, Math.Max(280, Root.ActualWidth - 100)) };
        var search = new TextBox { PlaceholderText = T("Search bookmarks", "搜索书签") };
        var folderIconOption = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        folderIconOption.Children.Add(new TextBlock { Text = T("Bookmarks bar folder icons", "书签栏文件夹图标"), VerticalAlignment = VerticalAlignment.Center });
        var folderIconSwitch = new ToggleSwitch { IsOn = Settings.BookmarkBarFolderIcons, OnContent = "", OffContent = "" };
        folderIconSwitch.Toggled += (_, _) => { Settings.BookmarkBarFolderIcons = folderIconSwitch.IsOn; RefreshBookmarkBar(); ScheduleSave(); };
        folderIconOption.Children.Add(folderIconSwitch);
        folderIconOption.Children.Add(new TextBlock { Text = T("Show bookmark website icons", "书签显示网站图标"), VerticalAlignment = VerticalAlignment.Center });
        var websiteIconSwitch = new ToggleSwitch { IsOn = Settings.BookmarkWebsiteIcons, OnContent = "", OffContent = "" };
        websiteIconSwitch.Toggled += (_, _) => { Settings.BookmarkWebsiteIcons = websiteIconSwitch.IsOn; RefreshBookmarkBar(); ScheduleSave(); };
        folderIconOption.Children.Add(websiteIconSwitch);
        var list = new ListView { Name = "BookmarkManagerList", Height = Math.Clamp(Root.ActualHeight - 370, 100, 360), SelectionMode = ListViewSelectionMode.Multiple, AllowDrop = true, IsSwipeEnabled = false };
        Bookmark? currentFolder = BookmarkImport.Flatten(store.Bookmarks).FirstOrDefault(node => node.Id == folderId && node.Children != null);
        var folderRail = new StackPanel { Spacing = 4, Width = 160 };
        var content = new Grid();
        content.ColumnDefinitions.Add(new() { Width = new(174) });
        content.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });
        var folderScroll = new ScrollViewer { Content = folderRail, Height = list.Height };
        content.Children.Add(folderScroll); Grid.SetColumn(list, 1); content.Children.Add(list);
        List<Bookmark> filtered = [];
        List<Bookmark> draggingBookmarks = [];
        bool CanDrop(Bookmark? target) => draggingBookmarks.Count > 0 && !draggingBookmarks.Any(node => node == target || node.Children != null && target != null && BookmarkImport.Flatten(node.Children).Contains(target));
        void DropOn(Bookmark? folder, int? index = null) {
            if (BookmarkImport.Move(store.Bookmarks, draggingBookmarks.Select(node => node.Id), folder?.Id, index)) Changed();
            draggingBookmarks.Clear();
        }
        void BeginDrag(Bookmark node, DragStartingEventArgs args) {
            var selected = Selected();
            draggingBookmarks = selected.Contains(node) ? selected : [node];
            args.AllowedOperations = global::Windows.ApplicationModel.DataTransfer.DataPackageOperation.Move;
            args.Data.RequestedOperation = global::Windows.ApplicationModel.DataTransfer.DataPackageOperation.Move;
            args.Data.SetText(string.Join(",", draggingBookmarks.Select(node => node.Id)));
        }
        list.DragOver += (_, args) => { args.AcceptedOperation = CanDrop(currentFolder) ? global::Windows.ApplicationModel.DataTransfer.DataPackageOperation.Move : global::Windows.ApplicationModel.DataTransfer.DataPackageOperation.None; args.Handled = true; };
        list.Drop += (_, args) => { if (CanDrop(currentFolder)) DropOn(currentFolder); args.Handled = true; };
        List<Bookmark> Current() => currentFolder?.Children ?? store.Bookmarks;
        void Changed() { store.Notify(); ScheduleSave(); Refresh(); }
        List<Bookmark>? Parent(Bookmark item, List<Bookmark> nodes) => nodes.Contains(item) ? nodes : nodes.Select(b => b.Children == null ? null : Parent(item, b.Children)).FirstOrDefault(p => p != null);
        List<Bookmark> Selected() => list.SelectedItems.OfType<ListViewItem>().Select(item => (Bookmark)item.Tag).ToList();
        void Refresh()
        {
            if (currentFolder != null && !BookmarkImport.Flatten(store.Bookmarks).Contains(currentFolder)) currentFolder = null;
            folderRail.Children.Clear();
            void FolderButton(Bookmark? folder, int depth) {
                var button = QuietButton(new string(' ', depth * 2) + (folder?.Title ?? T("Bookmarks bar", "书签栏")));
                button.HorizontalAlignment = HorizontalAlignment.Stretch;
                button.HorizontalContentAlignment = HorizontalAlignment.Left;
                button.MaxWidth = 160;
                button.Opacity = folder == currentFolder ? 1 : .65;
                button.Click += (_, _) => { currentFolder = folder; search.Text = ""; Refresh(); };
                button.AllowDrop = true;
                if (folder != null) {
                    button.CanDrag = true;
                    button.DragStarting += (_, args) => BeginDrag(folder, args);
                    button.DropCompleted += (_, _) => draggingBookmarks.Clear();
                }
                button.DragOver += (_, args) => { args.AcceptedOperation = CanDrop(folder) ? global::Windows.ApplicationModel.DataTransfer.DataPackageOperation.Move : global::Windows.ApplicationModel.DataTransfer.DataPackageOperation.None; args.Handled = true; };
                button.Drop += (_, args) => { if (CanDrop(folder)) DropOn(folder); args.Handled = true; };
                folderRail.Children.Add(button);
            }
            void Folders(IEnumerable<Bookmark> nodes, int depth) { foreach (var folder in nodes.Where(b => b.Children != null)) { FolderButton(folder, depth); Folders(folder.Children!, depth + 1); } }
            FolderButton(null, 0); Folders(store.Bookmarks, 1);
            filtered = (search.Text.Trim().Length == 0 ? Current() : BookmarkImport.Flatten(store.Bookmarks).Where(b => b.Title.Contains(search.Text.Trim(), StringComparison.OrdinalIgnoreCase) || (b.Url?.Contains(search.Text.Trim(), StringComparison.OrdinalIgnoreCase) ?? false))).ToList();
            list.ItemsSource = filtered.Select(node => {
                var label = new Border { CanDrag = true, Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent), Padding = new(4), Child = new TextBlock { Text = (node.Children != null ? "▱ " : "") + node.Title + "\n" + node.Url, TextTrimming = TextTrimming.CharacterEllipsis } };
                label.DragStarting += (_, args) => BeginDrag(node, args);
                label.DropCompleted += (_, _) => draggingBookmarks.Clear();
                var item = new ListViewItem { Tag = node, AllowDrop = true, HorizontalContentAlignment = HorizontalAlignment.Stretch, Content = label };
                (Bookmark? folder, int? index) Target(DragEventArgs args) {
                    var y = args.GetPosition(item).Y / Math.Max(1, item.ActualHeight);
                    if (node.Children != null && y >= .25 && y <= .75) return (node, null);
                    var siblings = Parent(node, store.Bookmarks)!;
                    var owner = BookmarkImport.Flatten(store.Bookmarks).FirstOrDefault(folder => folder.Children == siblings);
                    return (owner, siblings.IndexOf(node) + (y >= .5 ? 1 : 0));
                }
                item.DragOver += (_, args) => { var target = Target(args); args.AcceptedOperation = CanDrop(target.folder) && !draggingBookmarks.Contains(node) ? global::Windows.ApplicationModel.DataTransfer.DataPackageOperation.Move : global::Windows.ApplicationModel.DataTransfer.DataPackageOperation.None; args.Handled = true; };
                item.Drop += (_, args) => { var target = Target(args); if (CanDrop(target.folder) && !draggingBookmarks.Contains(node)) DropOn(target.folder, target.index); args.Handled = true; };
                return item;
            }).ToList();
        }
        list.DoubleTapped += (_, _) => {
            if (list.SelectedIndex < 0) return;
            var node = filtered[list.SelectedIndex];
            if (node.Children != null) { currentFolder = node; search.Text = ""; Refresh(); }
            else if (node.Url is { } address) OpenBookmark(address);
        };
        search.TextChanged += (_, _) => Refresh(); Refresh();
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var selectAll = QuietButton(T("Select all", "全选"));
        selectAll.Name = "BookmarkManagerSelectAll";
        selectAll.Click += (_, _) => list.SelectAll();
        panel.KeyDown += (_, args) => {
            if (args.Key == global::Windows.System.VirtualKey.A && args.OriginalSource is not TextBox && Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(global::Windows.System.VirtualKey.Control).HasFlag(global::Windows.UI.Core.CoreVirtualKeyStates.Down)) { list.SelectAll(); args.Handled = true; }
        };
        var open = new Button { Content = T("Open", "打开") };
        open.Click += (_, _) => { if (list.SelectedIndex >= 0 && filtered[list.SelectedIndex].Url is { } url) OpenBookmark(url); };
        var remove = new Button { Content = T("Delete", "删除") };
        remove.Click += (_, _) =>
        {
            var selected = Selected();
            foreach (var node in selected) Parent(node, store.Bookmarks)?.Remove(node);
            if (selected.Count > 0) Changed();
        };
        var edit = QuietButton(T("Edit", "编辑"));
        var create = QuietButton(T("New folder", "新建文件夹"));
        async Task Edit(Bookmark? node, bool newSite = false)
        {
            DismissOverlay();
            var title = new TextBox { Header = T("Name", "名称"), Text = node?.Title ?? "" };
            var url = new TextBox { Header = T("Address", "网址"), Text = node?.Url ?? "", Visibility = newSite || node?.Url != null ? Visibility.Visible : Visibility.Collapsed };
            var folders = new List<Bookmark?> { null }; folders.AddRange(BookmarkImport.Flatten(store.Bookmarks).Where(b => b.Children != null && b != node && (node == null || !BookmarkImport.Flatten([node]).Contains(b))));
            List<Bookmark>? Parent(List<Bookmark> nodes) { if (node != null && nodes.Contains(node)) return nodes; foreach (var b in nodes) if (b.Children != null && Parent(b.Children) is { } result) return result; return null; }
            var original = node == null ? Current() : Parent(store.Bookmarks) ?? store.Bookmarks;
            var folder = new ComboBox { Header = T("Folder", "文件夹"), ItemsSource = folders.Select(b => b?.Title ?? T("Bookmarks bar", "书签栏")).ToList(), SelectedIndex = Math.Max(0, folders.FindIndex(b => b?.Children == original)) };
            var form = new StackPanel { Spacing = 10 }; form.Children.Add(title); form.Children.Add(url); form.Children.Add(folder);
            if (await ShowCardAsync(node == null ? (newSite ? T("New bookmark", "新建书签") : T("New folder", "新建文件夹")) : T("Edit bookmark", "编辑书签"), form, T("Save", "保存")) == ContentDialogResult.Primary && title.Text.Trim().Length > 0 && (!newSite && node?.Url == null || AddressParser.IsWeb(url.Text.Trim())))
            {
                var target = folders[Math.Max(0, folder.SelectedIndex)]?.Children ?? store.Bookmarks;
                if (node == null) target.Add(new() { Title = title.Text.Trim(), Url = newSite ? url.Text.Trim() : null, Children = newSite ? null : [] });
                else { node.Title = title.Text.Trim(); if (node.Url != null) node.Url = url.Text.Trim(); if (target != original) { original.Remove(node); target.Add(node); } }
                store.Notify(); ScheduleSave();
            }
            await ShowBookmarksAsync(currentFolder?.Id);
        }
        edit.Click += async (_, _) => { if (list.SelectedIndex >= 0) await Edit(filtered[list.SelectedIndex]); }; create.Click += async (_, _) => await Edit(null);
        var add = QuietButton(T("New bookmark", "新建书签"));
        add.Click += async (_, _) => await Edit(null, true);
        var sort = QuietButton(T("Sort by name", "按名称排序"));
        sort.Name = "BookmarkManagerSort";
        sort.Click += (_, _) => { BookmarkImport.SortByName(Current()); Changed(); };
        var up = QuietButton(T("Move up", "上移"));
        var down = QuietButton(T("Move down", "下移"));
        void Move(int delta) { if (Selected() is not { Count: 1 } chosen) return; var siblings = Parent(chosen[0], store.Bookmarks); if (siblings == null) return; var index = siblings.IndexOf(chosen[0]); var target = index + delta; if (target < 0 || target >= siblings.Count) return; siblings.RemoveAt(index); siblings.Insert(target, chosen[0]); Changed(); list.SelectedIndex = filtered.IndexOf(chosen[0]); }
        up.Click += (_, _) => Move(-1); down.Click += (_, _) => Move(1);
        var import = new Button { Content = T("Import HTML", "导入 HTML") };
        import.Click += async (_, _) =>
        {
            var picker = new FileOpenPicker(); picker.FileTypeFilter.Add(".html"); picker.FileTypeFilter.Add(".htm");
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
            var file = await picker.PickSingleFileAsync();
            if (file == null) return;
            try { var html = await File.ReadAllTextAsync(file.Path); var nodes = await Task.Run(() => BookmarkImport.ParseHtml(html)); store.Bookmarks.AddRange(nodes); store.Notify(); ScheduleSave(); Refresh(); }
            catch (Exception ex) { Status.Text = ex.Message; }
        };
        var export = new Button { Content = T("Export", "导出") };
        export.Click += async (_, _) =>
        {
            var picker = new FileSavePicker { SuggestedFileName = "SearcheXtra-bookmarks" }; picker.FileTypeChoices.Add("HTML", new List<string> { ".html" });
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
            var file = await picker.PickSaveFileAsync(); if (file == null) return;
            string Encode(string value) => System.Net.WebUtility.HtmlEncode(value);
            string Render(List<Bookmark> nodes) => "<DL><p>\n" + string.Join("\n", nodes.Select(b => b.Children != null ? "<DT><H3>" + Encode(b.Title) + "</H3>" + Render(b.Children) : "<DT><A HREF=\"" + Encode(b.Url!) + "\">" + Encode(b.Title) + "</A>")) + "\n</DL><p>";
            await File.WriteAllTextAsync(file.Path, "<!DOCTYPE NETSCAPE-Bookmark-file-1><META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\"><TITLE>Bookmarks</TITLE>" + Render(store.Bookmarks));
        };
        foreach (var button in new[] { selectAll, open, edit, remove, up, down }) buttons.Children.Add(button);
        var tools = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        foreach (var button in new[] { add, create, sort, import, export }) tools.Children.Add(button);
        panel.Children.Add(search); panel.Children.Add(folderIconOption); panel.Children.Add(tools); panel.Children.Add(content); panel.Children.Add(buttons);
        var scroll = new ScrollViewer { Content = panel, Width = panel.Width, MaxHeight = Math.Max(120, Root.ActualHeight - 150), HorizontalScrollBarVisibility = ScrollBarVisibility.Auto };
        await ShowCardAsync(T("Bookmark manager", "书签管理器"), scroll, fitWindow: true);
    }
    private async Task ShowHistoryAsync()
    {
        var panel = new StackPanel { Spacing = 10, MinWidth = 460 };
        var search = new TextBox { PlaceholderText = T("Search history", "搜索历史记录") };
        var list = new ListView { Height = 360 };
        List<HistoryEntry> filtered = [];
        void Refresh() { filtered = store.History.Where(h => h.Title.Contains(search.Text, StringComparison.OrdinalIgnoreCase) || h.Url.Contains(search.Text, StringComparison.OrdinalIgnoreCase)).Take(1000).ToList(); list.ItemsSource = filtered.Select(h => h.Title + "\n" + h.Url).ToList(); }
        search.TextChanged += (_, _) => Refresh(); Refresh();
        var open = new Button { Content = T("Open selected", "打开选中项") };
        open.Click += (_, _) => { if (list.SelectedIndex >= 0) AddTab(filtered[list.SelectedIndex].Url); };
        var clear = new Button { Content = T("Clear history", "清空历史记录") };
        clear.Click += (_, _) => { store.History.Clear(); ScheduleSave(); Refresh(); };
        panel.Children.Add(search); panel.Children.Add(list); panel.Children.Add(open); panel.Children.Add(clear);
        await ShowCardAsync(T("History", "历史记录"), panel);
    }
    private async Task ShowTabSearchAsync()
    {
        var panel = new StackPanel { Spacing = 10, MinWidth = 420 };
        var search = new TextBox { PlaceholderText = T("Search open tabs", "查找已打开的标签页") };
        var list = new ListView { Height = 320 }; List<BrowserTab> filtered = [];
        void Refresh() { filtered = tabs.Where(t => t.Title.Contains(search.Text, StringComparison.OrdinalIgnoreCase) || t.Url.Contains(search.Text, StringComparison.OrdinalIgnoreCase)).ToList(); list.ItemsSource = filtered.Select(t => t.DisplayTitle).ToList(); }
        search.TextChanged += (_, _) => Refresh(); Refresh(); panel.Children.Add(search); panel.Children.Add(list);
        if (await ShowCardAsync(T("Open tabs", "已打开的标签页"), panel, T("Switch", "切换")) == ContentDialogResult.Primary && list.SelectedIndex >= 0) await SelectAsync(filtered[list.SelectedIndex]);
    }
    private async Task FindAsync()
    {
        var input = new TextBox { PlaceholderText = T("Text", "文字"), MinWidth = 320 };
        if (await ShowCardAsync(T("Find in page", "页面内查找"), input, T("Find next", "查找下一个")) != ContentDialogResult.Primary || ActiveView?.Control.CoreWebView2 is not { } core) return;
        await core.ExecuteScriptAsync("window.find(" + JsonSerializer.Serialize(input.Text) + ",false,false,true,false,false,false)");
    }
    private async Task ShowDownloadsAsync()
    {
        var panel = new StackPanel { Spacing = 8, MinWidth = 460 };
        var list = new ListView { Height = 210 };
        var timer = DispatcherQueue.CreateTimer(); timer.Interval = TimeSpan.FromMilliseconds(500);
        void Refresh() { var selected = list.SelectedIndex; list.ItemsSource = downloads.Select(d => d.Progress).ToList(); list.SelectedIndex = selected; }
        timer.Tick += (_, _) => Refresh(); timer.Start(); Refresh();
        var controls = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        void Button(string text, Action<DownloadItem> action) { var button = new Button { Content = text }; button.Click += (_, _) => { if (list.SelectedIndex >= 0) action(downloads[list.SelectedIndex]); }; controls.Children.Add(button); }
        Button(T("Pause", "暂停"), d => { if (d.Operation.State == Microsoft.Web.WebView2.Core.CoreWebView2DownloadState.InProgress) d.Operation.Pause(); });
        Button(T("Resume", "继续"), d => { if (d.Operation.CanResume) d.Operation.Resume(); });
        Button(T("Cancel", "取消"), d => { if (d.Operation.State != Microsoft.Web.WebView2.Core.CoreWebView2DownloadState.Completed) d.Operation.Cancel(); });
        Button(T("Show file", "显示文件"), d => Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + d.Path + "\"") { UseShellExecute = true }));
        panel.Children.Add(list); panel.Children.Add(controls);
        var kept = new ListView { Height = 160, ItemsSource = store.Downloads.Select(d => Path.GetFileName(d.Path) + " · " + d.Date.ToLocalTime().ToString("g")).ToList() };
        panel.Children.Add(kept); var keptControls = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var openFile = QuietButton(T("Open saved file", "打开已保存文件")); openFile.Click += (_, _) => { if (kept.SelectedIndex >= 0 && File.Exists(store.Downloads[kept.SelectedIndex].Path)) Process.Start(new ProcessStartInfo(store.Downloads[kept.SelectedIndex].Path) { UseShellExecute = true }); };
        var forget = QuietButton(T("Forget record", "删除记录")); forget.Click += (_, _) => { if (kept.SelectedIndex >= 0) { store.Downloads.RemoveAt(kept.SelectedIndex); kept.ItemsSource = store.Downloads.Select(d => Path.GetFileName(d.Path) + " · " + d.Date.ToLocalTime().ToString("g")).ToList(); ScheduleSave(); } };
        keptControls.Children.Add(openFile); keptControls.Children.Add(forget); panel.Children.Add(keptControls);
        try { await ShowCardAsync(T("Downloads", "下载"), panel); } finally { timer.Stop(); }
    }
    private void Spaces_Click(object sender, RoutedEventArgs e)
    {
        var menu = new MenuFlyout();
        foreach (var name in store.Spaces)
            AddMenu(menu, name == "Default" ? T("Default", "默认空间") : name, () =>
            {
                space = name; split = null; ApplySettings(); RefreshTabLists();
                var tab = tabs.FirstOrDefault(t => t.Space == name); if (tab != null) _ = SelectAsync(tab); else AddTab();
            });
        AddMenu(menu, T("New space…", "新建空间…"), async () =>
        {
            var name = await PromptAsync(T("New space", "新建空间"), T("Name", "名称"));
            if (string.IsNullOrWhiteSpace(name) || store.Spaces.Contains(name)) return;
            store.Spaces.Add(name); space = name; split = null; ApplySettings(); RefreshTabLists(); AddTab(); store.Notify(); ScheduleSave();
        });
        if (space != "Default")
        {
            AddMenu(menu, T("Rename space…", "重命名空间…"), async () =>
            {
                var old = space; var name = await PromptAsync(T("Rename space", "重命名空间"), T("Name", "名称"), old);
                if (string.IsNullOrWhiteSpace(name) || name == old || store.Spaces.Contains(name)) return;
                var profile = PageView.ProfileName(Settings, old); Settings.SpaceProfiles.Remove(old); Settings.SpaceProfiles[name] = profile;
                store.Spaces[store.Spaces.IndexOf(old)] = name; foreach (var tab in tabs.Where(t => t.Space == old)) tab.Space = name;
                foreach (var session in store.WindowSessions) { if (session.Space == old) session.Space = name; session.Tabs = session.Tabs.Select(t => t.Space == old ? t with { Space = name } : t).ToList(); }
                space = name; ApplySettings(); RefreshTabLists(); store.Notify(); ScheduleSave();
            });
            AddMenu(menu, T("Delete space…", "删除空间…"), async () =>
            {
                var old = space; if (await ShowCardAsync(T("Delete space", "删除空间"), new TextBlock { Text = old }, T("Delete", "删除")) != ContentDialogResult.Primary) return;
                space = "Default"; foreach (var tab in tabs.Where(t => t.Space == old).ToArray()) CloseTab(tab);
                store.Spaces.Remove(old); Settings.SpaceProfiles.Remove(old); ApplySettings(); RefreshTabLists(); store.Notify(); ScheduleSave();
            });
        }
        menu.ShowAt(SpacesButton);
    }
    private async Task MoveTabAsync(BrowserTab tab)
    {
        var choices = new ComboBox { ItemsSource = store.Spaces, SelectedItem = tab.Space, MinWidth = 320 };
        if (await ShowCardAsync(T("Move to space", "移至空间"), choices, T("Move", "移动")) != ContentDialogResult.Primary) return;
        if (views.Remove(tab.Id, out var oldView)) { Pages.Children.Remove(oldView.Control); oldView.Dispose(); }
        tab.Space = (string)choices.SelectedItem; split = null; RefreshTabLists();
        if (active == tab) { var next = tabs.FirstOrDefault(t => t.Space == space); if (next != null) await SelectAsync(next); else AddTab(); }
        ScheduleSave();
    }
    private async Task ShowPasswordsAsync()
    {
        if (active?.IsPrivate == true) { Status.Text = T("Password storage is disabled in private tabs.", "无痕标签页不保存密码。"); return; }
        List<Login> logins;
        try { logins = await PasswordStore.ReadAsync(); } catch (Exception ex) { Status.Text = ex.Message; return; }
        var panel = new StackPanel { Spacing = 8, MinWidth = 430 };
        var origin = new TextBox { Header = T("Website origin", "网站来源"), Text = AddressParser.IsWeb(active?.Url ?? "") ? new Uri(active!.Url).GetLeftPart(UriPartial.Authority) : "https://" };
        var username = new TextBox { Header = T("Username", "用户名") };
        var password = new PasswordBox { Header = T("Password", "密码") };
        var list = new ListView { Height = 180, ItemsSource = logins.Select(l => l.Origin + " · " + l.Username).ToList() };
        list.SelectionChanged += (_, _) => { if (list.SelectedIndex >= 0) { var login = logins[list.SelectedIndex]; origin.Text = login.Origin; username.Text = login.Username; password.Password = login.Password; } };
        var fill = new Button { Content = T("Fill on this website", "填写到当前网站") };
        fill.Click += async (_, _) =>
        {
            if (ActiveView?.Control.CoreWebView2 is not { } core || !AddressParser.IsWeb(core.Source)) return;
            var actual = new Uri(core.Source).GetLeftPart(UriPartial.Authority);
            if (!string.Equals(actual, origin.Text.TrimEnd('/'), StringComparison.OrdinalIgnoreCase)) { Status.Text = T("Website origin does not match.", "网站来源不匹配。"); return; }
            await core.ExecuteScriptAsync("(()=>{if(location.origin!==" + JsonSerializer.Serialize(actual) + ")return;const u=document.querySelector('input[autocomplete=username],input[type=email],input[name*=user],input[type=text]');const p=document.querySelector('input[type=password]');const set=(e,v)=>{if(!e)return;Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(e,v);e.dispatchEvent(new Event('input',{bubbles:true}));};set(u," + JsonSerializer.Serialize(username.Text) + ");set(p," + JsonSerializer.Serialize(password.Password) + ");})()");
        };
        var delete = new Button { Content = T("Delete selected", "删除选中项") };
        delete.Click += async (_, _) => { if (list.SelectedIndex >= 0) { var selected = logins[list.SelectedIndex]; await PasswordStore.UpdateAsync(current => current.RemoveAll(login => login.Origin == selected.Origin && login.Username == selected.Username)); logins = await PasswordStore.ReadAsync(); list.ItemsSource = logins.Select(l => l.Origin + " · " + l.Username).ToList(); } };
        foreach (var element in new UIElement[] { list, origin, username, password, fill, delete }) panel.Children.Add(element);
        if (await ShowCardAsync(T("Passwords · encrypted for your Windows account", "密码 · 使用 Windows 账户加密"), panel, T("Save login", "保存账号")) == ContentDialogResult.Primary && AddressParser.IsWeb(origin.Text) && password.Password.Length > 0)
        {
            var site = new Uri(origin.Text).GetLeftPart(UriPartial.Authority);
            await PasswordStore.SaveAsync(new(site, username.Text, password.Password));
        }
        password.Password = "";
    }
}
