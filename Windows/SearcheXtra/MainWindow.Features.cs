using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.Web.WebView2.Core;
using System.Text.Json;
using Windows.Storage.Pickers;
using Windows.System;
using WinRT.Interop;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private string SitePermissionName(string kind) => kind switch
    {
        "Geolocation" => T("Location", "位置信息"),
        "Camera" => T("Camera", "摄像头"),
        "Microphone" => T("Microphone", "麦克风"),
        "Notifications" => T("Notifications", "通知"),
        "OtherSensors" => T("Device sensors", "设备传感器"),
        "ClipboardRead" => T("Read clipboard", "读取剪贴板"),
        "MultipleAutomaticDownloads" => T("Automatic downloads", "自动下载多个文件"),
        "FileReadWrite" => T("Read and write files", "读取和写入文件"),
        "Autoplay" => T("Autoplay media", "自动播放媒体"),
        "LocalFonts" => T("Local fonts", "本机字体"),
        "MidiSystemExclusiveMessages" => T("MIDI devices", "MIDI 设备"),
        "WindowManagement" => T("Window management", "窗口管理"),
        _ => T("Other site permissions", "其他网站权限")
    };
    private readonly Dictionary<Guid, (BrowserTab Tab, PageView View, BrowserTab Owner)> previewViews = [];
    private async Task PreviewLinkAsync(string url, BrowserTab? from = null)
    {
        var owner = from ?? active;
        if (owner == null || closing) return;
        var tab = new BrowserTab { Url = url, IsPrivate = owner.IsPrivate, Space = owner.Space };
        using var page = new PageView(tab, store, () => { }, link => { DismissOverlay(); AddTab(link, true, tab.IsPrivate, inSpace: tab.Space); }, recordVisits: false);
        var preview = page.Control;
        preview.Width = 720; preview.Height = 500; preview.Visibility = Visibility.Visible;
        page.FlowDragRequested += request => ExecuteFlowDragAsync(tab, page, request);
        page.OpenLinkRequested += (link, foreground) => { if (foreground) DismissOverlay(); AddTab(link, foreground, tab.IsPrivate, inSpace: tab.Space); };
        previewViews[tab.Id] = (tab, page, owner);
        var pending = ShowCardAsync(T("Link preview", "链接预览"), preview, T("Open in tab", "在标签页中打开"));
        try
        {
            await page.InitializeAsync();
            if (await pending == ContentDialogResult.Primary && !page.IsDisposed && !closing)
                AddTab(tab.Url, true, tab.IsPrivate, inSpace: tab.Space);
        }
        finally { previewViews.Remove(tab.Id); }
    }
    private SitePreferences GetSite(string host)
    {
        if (!Settings.Sites.TryGetValue(host, out var site)) Settings.Sites[host] = site = new(); return site;
    }
    private async Task AddKeywordAsync()
    {
        var word = new TextBox { PlaceholderText = "yt", MaxWidth = 100 }; var address = new TextBox { PlaceholderText = "https://example.com/search?q=%s" };
        var panel = new StackPanel { Spacing = 10 }; panel.Children.Add(word); panel.Children.Add(address);
        if (await ShowCardAsync(T("Search keyword", "搜索关键词"), panel, T("Save", "保存")) != ContentDialogResult.Primary) return;
        var keyword = word.Text.Trim(); var template = address.Text.Trim();
        if (keyword.Length == 0 || keyword.Any(char.IsWhiteSpace) || !template.Contains("%s") || !AddressParser.IsWeb(template.Replace("%s", "test"))) return;
        Settings.Keywords.RemoveAll(k => k.Keyword.Equals(keyword, StringComparison.OrdinalIgnoreCase)); Settings.Keywords.Add(new(keyword, template)); ScheduleSave();
    }
    private async Task ShowSiteCardAsync()
    {
        if (active == null || !AddressParser.IsWeb(active.Url) || ActiveView is not { } view || view.Control.CoreWebView2 is not { } core) return;
        var tab = active; var uri = new Uri(tab.Url); var origin = uri.GetLeftPart(UriPartial.Authority); var profile = core.Profile;
        var permissions = tab.IsPrivate ? new Dictionary<string, string>() : GetSite(origin).Permissions;
        if (tab.IsPrivate)
            foreach (var permission in await profile.GetNonDefaultPermissionSettingsAsync())
                if (PageView.PermissionOriginMatches(permission.PermissionOrigin, origin)) permissions[permission.PermissionKind.ToString()] = permission.PermissionState == CoreWebView2PermissionState.Allow ? "allow" : "deny";
        if (view.IsDisposed || active != tab) return;
        var site = GetSite(uri.Host); var panel = new StackPanel { Spacing = 10 };
        panel.Children.Add(new TextBlock { Text = uri.Scheme == "https" ? T("Secure connection", "安全连接") : T("Connection is not encrypted", "连接未加密"), FontSize = 13 });
        var zoom = new Slider { Header = T("Page zoom", "网页缩放"), Minimum = .5, Maximum = 3, StepFrequency = .05, Value = site.Zoom ?? Settings.PageZoom };
        zoom.ValueChanged += (_, _) => { site.Zoom = zoom.Value; view.ApplySettings(); ScheduleSave(); }; panel.Children.Add(zoom);
        foreach (var permission in new[] { "Camera", "Microphone", "Geolocation", "Notifications", "ClipboardRead" })
        {
            var options = new ComboBox { Header = SitePermissionName(permission), ItemsSource = new[] { T("Ask", "询问"), T("Allow", "允许"), T("Block", "阻止") }, SelectedIndex = permissions.GetValueOrDefault(permission) switch { "allow" => 1, "deny" => 2, _ => 0 } };
            options.SelectionChanged += async (_, _) =>
            {
                if (options.SelectedIndex < 0 || view.IsDisposed || !Enum.TryParse<CoreWebView2PermissionKind>(permission, out var kind)) return;
                await profile.SetPermissionStateAsync(kind, origin, options.SelectedIndex switch { 1 => CoreWebView2PermissionState.Allow, 2 => CoreWebView2PermissionState.Deny, _ => CoreWebView2PermissionState.Default });
                permissions[permission] = new[] { "ask", "allow", "deny" }[options.SelectedIndex];
                if (!tab.IsPrivate) ScheduleSave();
            }; panel.Children.Add(options);
        }
        var clear = QuietButton(T("Clear this site's data", "清除此网站数据"));
        clear.Click += async (_, _) => { if (!view.IsDisposed) { await ClearSiteDataAsync(core, uri); clear.Content = T("Site data cleared", "网站数据已清除"); } }; panel.Children.Add(clear);
        await ShowCardAsync(uri.Host, panel);
    }
    private async Task ShowImportAsync()
    {
        var panel = new StackPanel { Spacing = 12 };
        var showBar = QuietButton(T("Show the bookmarks bar", "显示书签栏")); showBar.Visibility = Visibility.Collapsed;
        showBar.Click += (_, _) => { Settings.BookmarksBar = true; ApplySettings(); ScheduleSave(); DismissOverlay(); };
        var profile = QuietButton(T("Chrome / Edge / Firefox / Brave profile folder", "Chrome / Edge / Firefox / Brave 配置目录"));
        profile.Click += async (_, _) =>
        {
            var picker = new FolderPicker(); picker.FileTypeFilter.Add("*"); InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this)); var folder = await picker.PickSingleFolderAsync(); if (folder == null) return;
            try { var result = await BrowserImport.ProfileAsync(folder.Path); store.Bookmarks.AddRange(result.Bookmarks); store.History = BrowserImport.MergeHistory(store.History, result.History); store.Notify(); ScheduleSave(); Status.Text = T("Imported bookmarks and history.", "已导入书签和历史记录。"); showBar.Visibility = result.Bookmarks.Count > 0 && !Settings.BookmarksBar ? Visibility.Visible : Visibility.Collapsed; }
            catch (Exception ex) { Status.Text = ex.Message; }
        };
        panel.Children.Add(profile);
        var bookmarks = QuietButton(T("Bookmarks HTML (Chrome, Edge, Firefox, Safari)", "书签 HTML（Chrome、Edge、Firefox、Safari）"));
        bookmarks.Click += async (_, _) => { DismissOverlay(); await ShowBookmarksAsync(); };
        var passwords = QuietButton(T("Passwords CSV", "密码 CSV")); passwords.Click += async (_, _) => { DismissOverlay(); await ImportPasswordsAsync(); };
        var extensions = QuietButton(T("Import extension folder", "导入扩展目录")); extensions.Click += async (_, _) => await ChooseExtensionFolderAsync();
        panel.Children.Add(bookmarks); panel.Children.Add(passwords); panel.Children.Add(extensions); panel.Children.Add(showBar); await ShowCardAsync(T("Bring things over", "导入数据"), panel);
    }
    private async Task ImportPasswordsAsync()
    {
        var picker = new FileOpenPicker(); picker.FileTypeFilter.Add(".csv"); InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this)); var file = await picker.PickSingleFileAsync(); if (file == null) return;
        try
        {
            var imported = CsvPasswords.Parse(await File.ReadAllTextAsync(file.Path));
            await PasswordStore.UpdateAsync(passwords => { foreach (var login in imported) { passwords.RemoveAll(p => p.Origin == login.Origin && p.Username == login.Username); passwords.Add(login); } }); Status.Text = T("Passwords imported: ", "已导入密码：") + imported.Count;
        }
        catch (Exception ex) { Status.Text = ex.Message; }
    }
    private readonly Dictionary<string, Action> shortcutActions = [];
    private static string ShortcutName(VirtualKey key, VirtualKeyModifiers modifiers) => (modifiers.HasFlag(VirtualKeyModifiers.Control) ? "Ctrl+" : "") + (modifiers.HasFlag(VirtualKeyModifiers.Shift) ? "Shift+" : "") + (modifiers.HasFlag(VirtualKeyModifiers.Menu) ? "Alt+" : "") + key;
    private static bool ParseShortcut(string value, out VirtualKey key, out VirtualKeyModifiers modifiers)
    {
        var parts = value.Split('+'); modifiers = VirtualKeyModifiers.None; key = VirtualKey.None;
        foreach (var part in parts[..^1]) modifiers |= part.Trim().ToLowerInvariant() switch { "ctrl" => VirtualKeyModifiers.Control, "shift" => VirtualKeyModifiers.Shift, "alt" => VirtualKeyModifiers.Menu, _ => VirtualKeyModifiers.None };
        return Enum.TryParse(parts[^1], true, out key) && key != VirtualKey.None;
    }
    private void BuildShortcutSettings(StackPanel panel)
    {
        foreach (var entry in shortcutActions)
        {
            var row = new Grid { Padding = new(14, 8, 14, 8), ColumnSpacing = 10 }; row.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) }); row.ColumnDefinitions.Add(new() { Width = new(180) });
            row.Children.Add(new TextBlock { Text = ShortcutLabel(entry.Key), VerticalAlignment = VerticalAlignment.Center, FontSize = 12 });
            var input = new TextBox { Text = Settings.Shortcuts.GetValueOrDefault(entry.Key, entry.Key), FontSize = 12, Padding = new(8, 4, 8, 4) }; Grid.SetColumn(input, 1);
            input.KeyDown += (_, e) => { if (e.Key is VirtualKey.Control or VirtualKey.Shift or VirtualKey.Menu) return; var modifiers = VirtualKeyModifiers.None; foreach (var pair in new[] { (VirtualKey.Control, VirtualKeyModifiers.Control), (VirtualKey.Shift, VirtualKeyModifiers.Shift), (VirtualKey.Menu, VirtualKeyModifiers.Menu) }) if (Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(pair.Item1).HasFlag(global::Windows.UI.Core.CoreVirtualKeyStates.Down)) modifiers |= pair.Item2; input.Text = ShortcutName(e.Key, modifiers); e.Handled = true; };
            input.LostFocus += (_, _) => { if (!ParseShortcut(input.Text, out _, out _) || Settings.Shortcuts.Any(k => k.Key != entry.Key && k.Value == input.Text)) { input.Text = Settings.Shortcuts.GetValueOrDefault(entry.Key, entry.Key); return; } Settings.Shortcuts[entry.Key] = input.Text; InstallShortcuts(); ScheduleSave(); };
            row.Children.Add(input); panel.Children.Add(row);
        }
        var reset = QuietButton(T("Restore defaults", "恢复默认")); reset.Margin = new(14); reset.Click += (_, _) => { Settings.Shortcuts.Clear(); InstallShortcuts(); ScheduleSave(); }; panel.Children.Add(reset);
    }
    private string ShortcutLabel(string key) => key switch
    {
        "Ctrl+L" => T("Address", "地址"), "Ctrl+T" => T("New tab", "新标签页"), "Ctrl+W" => T("Close tab", "关闭标签页"), "Ctrl+N" => T("New window", "新窗口"), "Ctrl+Shift+N" => T("Private tab", "无痕标签页"), "Ctrl+Shift+T" => T("Reopen tab", "恢复标签页"), "Ctrl+R" => T("Reload", "刷新"), "Ctrl+D" => T("Bookmark", "书签"), "Ctrl+H" => T("History", "历史"), "Ctrl+J" => T("Downloads", "下载"), "Ctrl+F" => T("Find", "查找"), "Ctrl+K" => T("Search tabs", "搜索标签页"), "Ctrl+OemComma" => T("Settings", "设置"), _ => key
    };
}
