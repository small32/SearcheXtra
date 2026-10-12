using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private static readonly (string, string, string)[] SettingsPages = { ("general", "General", "通用"), ("tabs", "Tabs", "标签页"), ("shortcuts", "Shortcuts", "快捷键"), ("bookmarks", "Bookmark manager", "书签管理器"), ("extensions", "Extensions", "扩展"), ("passwords", "Passwords", "密码"), ("downloads", "Downloads", "下载"), ("privacy", "Privacy", "隐私"), ("about", "About", "关于") };

    private async Task ShowSettingsAsync()
    {
        var pages = SettingsPages;
        if (OverlayLayer.Visibility == Visibility.Visible) return;
        var done = new TaskCompletionSource();
        var shell = new Grid { Width = 660, Height = 500 };
        shell.ColumnDefinitions.Add(new() { Width = new(168) }); shell.ColumnDefinitions.Add(new() { Width = new(1) }); shell.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });
        var rail = new StackPanel { Padding = new(8), Spacing = 2, Background = Brush("Wash", .45) };
        rail.Children.Add(new TextBlock { Text = T("Settings", "设置"), FontSize = 13, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Margin = new(10, 14, 10, 12) });
        shell.Children.Add(rail); var rule = new Border { Background = Brush("Hairline") }; Grid.SetColumn(rule, 1); shell.Children.Add(rule);
        var main = new Grid { Padding = new(22, 18, 22, 18), RowSpacing = 16 };
        main.RowDefinitions.Add(new() { Height = GridLength.Auto }); main.RowDefinitions.Add(new() { Height = new(1, GridUnitType.Star) }); Grid.SetColumn(main, 2); shell.Children.Add(main);
        var header = new Grid(); var title = new TextBlock { FontSize = 17, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold };
        header.Children.Add(title); var close = QuietButton("×"); close.HorizontalAlignment = HorizontalAlignment.Right; close.Click += (_, _) => DismissOverlay(); header.Children.Add(close); main.Children.Add(header);
        var body = new StackPanel { Spacing = 18 }; var scroll = new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Hidden }; Grid.SetRow(scroll, 1); main.Children.Add(scroll);
        var buttons = new Dictionary<string, Button>();
        foreach (var page in pages)
        {
            var button = new Button { Height = 30, Padding = new(10, 0, 10, 0), FontSize = 13, BorderThickness = new(0), CornerRadius = new(8), HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left };
            var content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 9 }; content.Children.Add(Glyph(page.Item1)); content.Children.Add(new TextBlock { Text = T(page.Item2, page.Item3), FontSize = 13, VerticalAlignment = VerticalAlignment.Center }); button.Content = content;
            button.Click += (_, _) => Render(page.Item1); rail.Children.Add(button); buttons[page.Item1] = button;
        }
        void Render(string page)
        {
            if (!buttons.ContainsKey(page)) page = "general";
            Settings.SettingsPage = page; ScheduleSave(); body.Children.Clear(); scroll.ChangeView(null, 0, null);
            foreach (var entry in pages) { buttons[entry.Item1].Opacity = entry.Item1 == page ? 1 : .58; buttons[entry.Item1].Background = Brush(entry.Item1 == page ? "Ground" : "Wash", entry.Item1 == page ? 1 : 0); buttons[entry.Item1].FontWeight = entry.Item1 == page ? Microsoft.UI.Text.FontWeights.Medium : Microsoft.UI.Text.FontWeights.Normal; }
            var name = pages.First(p => p.Item1 == page); title.Text = T(name.Item2, name.Item3);
            BuildSettingsPage(page, body, Render);
        }
        Render(Settings.SettingsPage);
        var card = new Border { Background = Brush("Ground"), BorderBrush = Brush("Hairline"), BorderThickness = new(1), CornerRadius = new(16), Child = shell, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        card.Tapped += Card_Tapped; OverlayLayer.Children.Add(card); OverlayLayer.Visibility = Visibility.Visible; overlayOpened = DateTimeOffset.Now;
        overlayClose = () => { OverlayLayer.Children.Clear(); OverlayLayer.Visibility = Visibility.Collapsed; overlayClose = null; done.TrySetResult(); };
        await done.Task;
    }
    private void BuildSettingsPage(string page, StackPanel body, Action<string> render)
    {
        var card = new StackPanel();
        body.Children.Add(new Border { CornerRadius = new(12), BorderBrush = Brush("Hairline"), BorderThickness = new(1), Child = card });
        void Changed() { store.Notify(); ScheduleSave(); }
        void Line(string label, string detail, UIElement? control = null)
        {
            (label, detail) = SettingsRowText(label, detail);
            if (card.Children.Count > 0) card.Children.Add(new Border { Height = 1, Background = Brush("Hairline"), Margin = new(14, 0, 14, 0) });
            var row = new Grid { Padding = new(14, 10, 14, 10), ColumnSpacing = 12 };
            row.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) }); row.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
            var words = new StackPanel { Spacing = 3 }; words.Children.Add(new TextBlock { Text = label, FontSize = 13, TextWrapping = TextWrapping.Wrap });
            if (detail.Length > 0) words.Children.Add(new TextBlock { Text = detail, FontSize = 11.5, Opacity = .58, TextWrapping = TextWrapping.Wrap });
            row.Children.Add(words); if (control != null) { Grid.SetColumn((FrameworkElement)control, 1); if (control is FrameworkElement element) element.VerticalAlignment = VerticalAlignment.Center; row.Children.Add(control); } card.Children.Add(row);
        }
        void Toggle(string en, string zh, bool value, Action<bool> set, string detail = "", bool enabled = true)
        {
            var toggle = new ToggleSwitch { IsEnabled = enabled, IsOn = value, OnContent = "", OffContent = "", MinWidth = 40, Width = 40 };
            toggle.Toggled += (_, _) => { set(toggle.IsOn); Changed(); }; Line(T(en, zh), detail, toggle);
        }
        void Choice(string en, string zh, string[] labels, int selected, Action<int> set)
        {
            var choice = new ComboBox { ItemsSource = labels, SelectedIndex = selected, MinWidth = 100, MaxWidth = 190, FontSize = 12, Padding = new(8, 4, 24, 4) };
            choice.SelectionChanged += (_, _) => { if (choice.SelectedIndex >= 0) { set(choice.SelectedIndex); Changed(); } }; Line(T(en, zh), "", choice);
        }
        void ActionRow(string en, string zh, string buttonText, Action action, string detail = "") { var button = QuietButton(buttonText); button.Click += (_, _) => action(); Line(T(en, zh), detail, button); }
        void Input(string en, string zh, string value, Action<string> set, string placeholder = "")
        {
            Line(T(en, zh), ""); var row = new Grid { Margin = new(14, 0, 14, 11), ColumnSpacing = 8 }; row.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) }); row.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
            var input = new TextBox { Text = value, PlaceholderText = placeholder, FontSize = 12.5, Padding = new(10, 7, 10, 7), Background = Brush("Wash"), BorderThickness = new(0), CornerRadius = new(9) };
            var save = QuietButton(T("Save", "保存")); save.Click += (_, _) => { set(input.Text.Trim()); Changed(); }; row.Children.Add(input); Grid.SetColumn(save, 1); row.Children.Add(save); card.Children.Add(row);
        }
        switch (page)
        {
            case "general":
                Choice("Language", "语言", [T("System", "系统"), "English", "简体中文"], Settings.Language switch { "en" => 1, "zh-Hans" => 2, _ => 0 }, i => { Settings.Language = new[] { "system", "en", "zh-Hans" }[i]; render(page); });
                Input("Start page", "起始页面", Settings.StartPage, value => { if (value.Length == 0) Settings.StartPage = ""; else if (AddressParser.IsWeb(value)) Settings.StartPage = value; else Status.Text = T("Enter a complete HTTP(S) address.", "请输入完整 HTTP(S) 网址。"); }, "https://example.com");
                ActionRow("Default browser", "默认浏览器", T("Set…", "设置…"), () => { WindowsIntegration.RegisterBrowser(); OpenSystem("ms-settings:defaultapps"); });
                ActionRow("Bring things over", "导入数据", T("Import…", "导入…"), async () => { DismissOverlay(); await ShowImportAsync(); });
                Choice("Search engine", "搜索引擎", ["Google", "DuckDuckGo", "Bing", "Baidu", T("Custom", "自定义")], Settings.SearchTemplate.Contains("google") ? 0 : Settings.SearchTemplate.Contains("duckduckgo") ? 1 : Settings.SearchTemplate.Contains("bing") ? 2 : Settings.SearchTemplate.Contains("baidu") ? 3 : 4, i => { if (i < 4) Settings.SearchTemplate = new[] { "https://www.google.com/search?q={0}", "https://duckduckgo.com/?q={0}", "https://www.bing.com/search?q={0}", "https://www.baidu.com/s?wd={0}" }[i]; else { Settings.SearchTemplate = "https://example.com/search?q={0}"; render(page); } });
                Input("Custom search address (%s)", "自定义搜索网址（%s）", Settings.SearchTemplate.Replace("{0}", "%s"), value => { if (value.Contains("%s") && AddressParser.IsWeb(value.Replace("%s", "test"))) Settings.SearchTemplate = value.Replace("%s", "{0}"); });
                ActionRow("Search keywords", "搜索关键词", T("Add", "添加"), async () => { DismissOverlay(); await AddKeywordAsync(); });
                foreach (var keyword in Settings.Keywords.ToArray()) ActionRow(keyword.Keyword, keyword.Keyword, "×", () => { Settings.Keywords.Remove(keyword); Changed(); render(page); }, keyword.Template);
                Choice("Appearance", "外观", [T("System", "系统"), T("Light", "浅色"), T("Dark", "深色")], Settings.Theme switch { "light" => 1, "dark" => 2, _ => 0 }, i => Settings.Theme = new[] { "system", "light", "dark" }[i]);
                Choice("Default page zoom", "默认网页缩放", ["50%", "75%", "100%", "125%", "150%", "200%", "300%"], Array.IndexOf(new[] { .5, .75, 1, 1.25, 1.5, 2, 3 }, Settings.PageZoom), i => Settings.PageZoom = new[] { .5, .75, 1, 1.25, 1.5, 2, 3 }[i]);
                Toggle("Correct spelling as you type", "输入时自动纠正拼写", Settings.Autocorrect, value => Settings.Autocorrect = value);
                Toggle("Open links from other apps in a small window", "在小窗口打开其他应用的链接", Settings.LittleLinks, value => Settings.LittleLinks = value);
                Toggle("Address bar commands", "地址栏命令", Settings.AddressCommands, value => Settings.AddressCommands = value);
                Toggle("Preview links with Shift-click", "Shift 点击预览链接", Settings.PeeksLinks, value => Settings.PeeksLinks = value);
                Toggle("Show link destinations", "显示链接目标地址", Settings.ShowsLinks, value => Settings.ShowsLinks = value);
                Line(T("Pages at 120 Hz", "以 120 Hz 刷新页面"), T("WebView2 follows the display refresh rate automatically.", "WebView2 自动跟随显示器刷新率。"));
                Toggle("Middle-click auto scroll", "鼠标中键自动滚动", Settings.AutoScroll, value => Settings.AutoScroll = value);
                Toggle("Wait for videos to play", "视频等待手动播放", Settings.WaitsForPlay, value => Settings.WaitsForPlay = value);
                Toggle("Float video when leaving a tab", "离开标签页时浮动视频", Settings.FloatsOnLeave, value => Settings.FloatsOnLeave = value);
                Toggle("Float video when switching apps", "切换应用时浮动视频", Settings.FloatsAway, value => Settings.FloatsAway = value);
                Toggle("Flick floating video to a corner", "浮动视频快速贴角", Settings.FloatFlicks, value => Settings.FloatFlicks = value);
                Toggle("History on navigation hold", "按住导航按钮选择历史页面", Settings.HoldsHistory, value => Settings.HoldsHistory = value);
                Toggle("Let scripts drive SearcheXtra", "允许脚本控制 SearcheXtra", Settings.Bench, value => Settings.Bench = value);
                break;
            case "tabs":
                Toggle("Sidebar", "侧边栏", Settings.Sidebar, value => { Settings.Sidebar = value; render(page); });
                if (Settings.Sidebar) { Choice("Sidebar position", "侧边栏位置", [T("Left", "左侧"), T("Right", "右侧")], Settings.SidebarRight ? 1 : 0, i => Settings.SidebarRight = i == 1); Toggle("Pinned tabs as rows", "固定标签页使用列表", Settings.ListsPins, value => { Settings.ListsPins = value; RefreshTabLists(); }); }
                if (!Settings.Sidebar) Toggle("Navigation buttons on the left", "左侧显示导航按钮", Settings.NavigationLeft, value => Settings.NavigationLeft = value);
                Toggle("Hide sidebar until pointer reaches edge", "指针靠近边缘时显示侧栏", Settings.SidebarAutoHide, value => Settings.SidebarAutoHide = value);
                Choice("Tabs show", "标签页显示", [T("Letters", "字母"), T("Icons", "图标")], Settings.IconGlyphs ? 1 : 0, i => { Settings.IconGlyphs = i == 1; RefreshTabLists(); });
                Toggle("Search a site from the address field", "在地址栏搜索网站", Settings.SearchesSites, value => Settings.SearchesSites = value);
                Toggle("Bookmarks bar", "书签栏", Settings.BookmarksBar, value => Settings.BookmarksBar = value);
                Toggle("Compact bookmarks bar", "紧凑书签栏", Settings.CompactBookmarksBar, value => Settings.CompactBookmarksBar = value);
                Choice("Open bookmarks from the bar", "书签栏打开方式", [T("Default", "默认"), T("New background tab", "新建后台标签页"), T("New foreground tab", "新建前台标签页")], (int)Settings.BookmarkOpening, i => Settings.BookmarkOpening = (BookmarkOpening)i);
                Toggle("Reading mode", "阅读模式", Settings.ShowsReading, value => Settings.ShowsReading = value);
                Toggle("Put idle tabs to sleep", "休眠闲置标签页", Settings.SuspendTabs, value => Settings.SuspendTabs = value);
                Choice("Sleep after", "闲置多久后休眠", [T("5 minutes", "5 分钟"), T("10 minutes", "10 分钟"), T("30 minutes", "30 分钟")], Settings.SuspendAfterMinutes == 5 ? 0 : Settings.SuspendAfterMinutes == 30 ? 2 : 1, i => Settings.SuspendAfterMinutes = new[] { 5, 10, 30 }[i]);
                Toggle("Load background tabs on demand", "按需加载后台标签页", Settings.LazyBackgroundTabs, value => Settings.LazyBackgroundTabs = value);
                Toggle("Start with a fresh window", "启动时打开全新窗口", !Settings.RestoreSession, value => Settings.RestoreSession = !value);
                Toggle("Spaces", "空间", Settings.UsesSpaces, value => Settings.UsesSpaces = value);
                Toggle("Tab groups", "标签组", Settings.UsesTabGroups, value => Settings.UsesTabGroups = value);
                Toggle("Split view", "分屏", Settings.SplitView, value => Settings.SplitView = value);
                break;
            case "bookmarks":
                ActionRow("Bookmark manager", "书签管理器", T("Open", "打开"), async () => { DismissOverlay(); await ShowBookmarksAsync(); }, T("Import, edit, delete and organize bookmarks and folders.", "导入、编辑、删除及整理书签和文件夹。"));
                break;
            case "shortcuts":
                BuildShortcutSettings(card); break;
            case "extensions":
                ActionRow("Chrome Web Store", "Chrome 扩展商店", T("Browse", "浏览"), () => { DismissOverlay(); AddTab("https://chromewebstore.google.com/"); });
                Input("Store link or extension ID", "商店链接或扩展 ID", "", async value => await InstallStoreExtensionAsync(value), "https://chromewebstore.google.com/detail/…");
                ActionRow("Unpacked extension", "未打包扩展", T("Choose folder…", "选择目录…"), async () => { await ChooseExtensionFolderAsync(); render(page); });
                ActionRow("Extension package (MV2 / MV3)", "扩展文件（MV2 / MV3）", T("Import CRX / ZIP…", "导入 CRX / ZIP…"), async () => { await ChooseExtensionPackageAsync(); render(page); });
                Toggle("Extensions in private tabs", "无痕标签页使用扩展", PageView.SupportsPrivateExtensions && Settings.ExtensionsInPrivate, value => Settings.ExtensionsInPrivate = value, T("Private tabs cannot run extensions on Windows.", "Windows 无痕标签页暂不支持扩展。"), PageView.SupportsPrivateExtensions);
                ActionRow("Manage extensions", "扩展管理", T("Open", "打开"), async () => { DismissOverlay(); await ShowExtensionManagerAsync(); });
                break;
            case "passwords":
                ActionRow("Saved passwords", "已保存的密码", T("Manage…", "管理…"), async () => { DismissOverlay(); await ShowPasswordsAsync(); });
                Toggle("Offer to save passwords", "提示保存密码", Settings.SavesPasswords, value => Settings.SavesPasswords = value);
                Toggle("Fill saved passwords", "自动填写已保存的密码", Settings.FillsPasswords, value => Settings.FillsPasswords = value);
                Toggle("Passkeys", "通行密钥", Settings.Passkeys, value => Settings.Passkeys = value, T("Uses WebView2 and Windows Hello.", "通过 WebView2 和 Windows Hello 使用。"));
                ActionRow("Bring passwords over", "导入密码", T("Import CSV…", "导入 CSV…"), async () => { DismissOverlay(); await ImportPasswordsAsync(); });
                break;
            case "downloads":
                ActionRow("Save files to", "文件保存位置", T("Choose…", "选择…"), async () => { var picker = new FolderPicker(); picker.FileTypeFilter.Add("*"); InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this)); var folder = await picker.PickSingleFolderAsync(); if (folder != null) { Settings.DownloadsFolder = folder.Path; Changed(); render(page); } }, Settings.DownloadsFolder);
                Toggle("Ask where to save each file", "每次询问保存位置", Settings.AskDownloadLocation, value => Settings.AskDownloadLocation = value);
                Toggle("Always show downloads button", "始终显示下载按钮", Settings.AlwaysShowsDownloads, value => Settings.AlwaysShowsDownloads = value);
                ActionRow("Downloaded files", "已下载文件", T("Show", "显示"), async () => { DismissOverlay(); await ShowDownloadsAsync(); });
                break;
            case "privacy":
                Toggle("Block ads and trackers", "拦截广告与跟踪器", Settings.BlockTrackers, value => Settings.BlockTrackers = value);
                if (active != null && AddressParser.IsWeb(active.Url)) { var host = new Uri(active.Url).Host; var site = GetSite(host); Toggle("Block on " + host, "在 " + host + " 上拦截", site.BlockTrackers != false, value => { site.BlockTrackers = value; ActiveView?.Control.CoreWebView2?.Reload(); }); }
                Toggle("Prevent cross-site tracking", "防止跨站跟踪", Settings.PreventTracking, value => Settings.PreventTracking = value);
                Toggle("Let sites ask to send notifications", "允许网站请求通知", Settings.SiteNotifications, value => Settings.SiteNotifications = value);
                ActionRow("Site permissions", "网站权限", T("Manage…", "管理…"), async () => { DismissOverlay(); await ShowSiteCardAsync(); });
                ActionRow("History", "历史记录", T("Clear", "清除"), () => { store.History.Clear(); Changed(); });
                ActionRow("Cookies and website data", "Cookie 与网站数据", T("Clear", "清除"), async () => await (await CurrentProfileAsync()).ClearBrowsingDataAsync(CoreWebView2BrowsingDataKinds.Cookies | CoreWebView2BrowsingDataKinds.AllDomStorage));
                ActionRow("Cache", "缓存", T("Clear", "清除"), async () => await (await CurrentProfileAsync()).ClearBrowsingDataAsync(CoreWebView2BrowsingDataKinds.DiskCache));
                break;
            case "about":
                Line("SearcheXtra", ReleaseUpdates.Version + " · Windows x86_64\nWinUI 3 · WebView2");
                ActionRow("Updates", "更新", T("Check", "检查"), async () => { var result = await ReleaseUpdates.LatestAsync(); DismissOverlay(); if (await ShowCardAsync(T("Updates", "更新"), new TextBlock { Text = result, TextWrapping = TextWrapping.Wrap }, T("Open releases", "打开发布页")) == ContentDialogResult.Primary) AddTab("https://github.com/small32/SearcheXtra/releases"); });
                ActionRow("Source code", "源代码", "GitHub", () => { DismissOverlay(); AddTab("https://github.com/small32/SearcheXtra"); });
                Line(T("License", "许可证"), "GPL-3.0"); break;
        }
    }
    private static void OpenSystem(string uri) => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(uri) { UseShellExecute = true });
}
