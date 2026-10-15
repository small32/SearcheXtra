using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Windowing;
using System.Collections.ObjectModel;
using System.Diagnostics;
using Windows.System;
using WinRT.Interop;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow : Window
{
    private readonly DataStore store;
    private readonly Strings strings;
    private readonly ObservableCollection<BrowserTab> tabs = [];
    private readonly Dictionary<Guid, MenuFlyout> tabMenus = [];
    private readonly Dictionary<Guid, PageView> views = [];
    private readonly Stack<SavedTab> closedTabs = [];
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer saveTimer, sleepTimer;
    private BrowserTab? active, split, splitOwner;
    private double splitRatio = .5;
    private Thumb? divider;
    private string space;
    private bool selecting, closing, saving, saveAgain;
    private long selectionVersion;
    private readonly List<DownloadItem> downloads = [];
    private BrowserSettings Settings => store.Settings;
    private string T(string en, string zh) => strings.Text(en, zh);

    public MainWindow(DataStore store, bool restore, SessionState? session = null)
    {
        this.store = store;
        strings = new(Settings);
        var restored = session ?? store.Session;
        space = restore ? restored.Space : store.Spaces[0];
        InitializeComponent();
        SetupSidebar();
        SetupGlyphs();
        AppWindow.Resize(new global::Windows.Graphics.SizeInt32(1200, 820));
        ((OverlappedPresenter)AppWindow.Presenter).SetBorderAndTitleBar(true, true);
        SetupTitleBar();
        Root.ActualThemeChanged += (_, _) => { SetupGlyphs(); UpdateTitleBarColors(); };
        WindowsIntegration.SetWindowIcon(this);
        saveTimer = DispatcherQueue.CreateTimer();
        saveTimer.Interval = TimeSpan.FromMilliseconds(650);
        saveTimer.IsRepeating = false;
        saveTimer.Tick += async (_, _) => await SaveStateAsync();
        sleepTimer = DispatcherQueue.CreateTimer();
        sleepTimer.Interval = TimeSpan.FromSeconds(30);
        sleepTimer.Tick += async (_, _) => await SuspendIdleAsync();
        sleepTimer.Start();
        store.Changed += OnStoreChanged;
        AppWindow.Closing += async (_, args) =>
        {
            if (closing) return;
            args.Cancel = true; closing = true; selectionVersion++;
            sleepTimer.Stop(); saveTimer.Stop();
            await SaveStateAsync();
            while (saving) await Task.Delay(20);
            Close();
        };
        Closed += Window_Closed;
        BackButton.RightTapped += async (_, e) => { e.Handled = true; await ShowNavigationHistoryAsync(true, BackButton); };
        ForwardButton.RightTapped += async (_, e) => { e.Handled = true; await ShowNavigationHistoryAsync(false, ForwardButton); };
        ReopenButton.RightTapped += (_, e) => { e.Handled = true; ShowRecentHistory(); };
        TopSettings.RightTapped += (_, e) => { e.Handled = true; Menu_Click(this, new()); };
        ExtensionsButton.RightTapped += async (_, e) => { e.Handled = true; await ShowExtensionManagerAsync(); };
        InstallShortcuts();
        Activated += async (_, e) => { if (Settings.FloatsAway && e.WindowActivationState == WindowActivationState.Deactivated && ActiveView is { FloatingWindow: null } view && await view.Control.CoreWebView2.ExecuteScriptAsync("[...document.querySelectorAll('video')].some(v=>!v.paused)") == "true") await TogglePictureInPictureAsync(false); };
        if (Environment.GetEnvironmentVariable("SEARCHEXTRA_SMOKE_TEST") is { Length: > 0 } report)
            Root.Loaded += async (_, _) => await RunSmokeTestsAsync(report);
        Address.KeyDown += SiteSearch_KeyDown;
        Root.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler(AddressOutside_PointerPressed), true);
        Root.Loaded += (_, _) => { if (active?.Url is "" or "about:blank") FocusAddress(); };
        ApplySettings();
        if (restore)
            foreach (var saved in restored.Tabs.Where(t => Settings.RestoreSession || t.Pinned))
                AddTab(saved.Url, false, false, saved.Title, saved.Pinned, saved.Space, loadBackground: false, group: saved.Group);
        if (restore && restored.SplitIndices is [var left, var right] && left >= 0 && right >= 0 && left < tabs.Count && right < tabs.Count && left != right)
        {
            splitOwner = tabs[left]; split = tabs[right]; splitRatio = Math.Clamp(restored.SplitRatio, .15, .85);
        }
        var current = tabs.Where(t => t.Space == space).ToList();
        if (current.Count > 0)
        {
            var index = Math.Clamp(restored.ActiveIndex, 0, current.Count - 1);
            _ = SelectAsync(current[index]);
        }
        else AddTab(Settings.StartPage.Length > 0 ? Settings.StartPage : NewTabUrl());
    }

    private bool settingsRefreshPending;
    private void OnStoreChanged()
    {
        if (settingsRefreshPending) return;
        settingsRefreshPending = DispatcherQueue.TryEnqueue(() => { settingsRefreshPending = false; ApplySettings(); });
    }
    private void ApplySettings()
    {
        Root.RequestedTheme = Settings.Theme switch { "dark" => ElementTheme.Dark, "light" => ElementTheme.Light, _ => ElementTheme.Default };
        SetupGlyphs();
        UpdateTitleBarColors();
        TopTabs.Visibility = Settings.Sidebar ? Visibility.Collapsed : Visibility.Visible;
        LayoutChrome();
        Sidebar.Visibility = Settings.Sidebar ? Visibility.Visible : Visibility.Collapsed;
        SidebarColumn.Width = new(Settings.Sidebar && !Settings.SidebarRight ? Settings.SidebarWidth : 0);
        RightSidebarColumn.Width = new(Settings.Sidebar && Settings.SidebarRight ? Settings.SidebarWidth : 0);
        Grid.SetColumn(Sidebar, Settings.SidebarRight ? 2 : 0);
        BookmarkScroller.Visibility = Settings.BookmarksBar ? Visibility.Visible : Visibility.Collapsed;
        SideNew.Content = T("+  New tab", "+  新标签页");
        Address.PlaceholderText = T("Address or search", "网址或搜索");
        SpacesButton.Content = space == "Default" ? T("Default", "默认空间") : space;
        if (Settings.BookmarksBar) RefreshBookmarkBar();
        foreach (var tab in tabs) { tab.UseIcons = Settings.IconGlyphs; if (views.TryGetValue(tab.Id, out var page) && page.Control.CoreWebView2 is { } core) tab.Favicon = Settings.IconGlyphs ? core.FaviconUri : ""; if (!Settings.ShowsReading) tab.Reading = 0; }
        foreach (var view in views.Values.Concat(previewViews.Values.Select(preview => preview.View))) { view.ApplySettings(); _ = view.UpdateDocumentScriptAsync(); }
        UpdateSidebarFold();
        RefreshPinnedExtensions();
        UpdateBench();
    }

    private string NewTabUrl(bool isPrivate = false)
    {
        if (isPrivate && !PageView.SupportsPrivateExtensions) return "";
        if ((!isPrivate || Settings.ExtensionsInPrivate) && Settings.Extensions.FirstOrDefault(e => e.Enabled && e.NewTab.Length > 0) is { } newtab)
            return $"chrome-extension://{newtab.Id}/{newtab.NewTab}";
        return "";
    }
    private async Task GoHomeAsync()
    {
        var url = Settings.StartPage;
        if (active == null) { AddTab(url); return; }
        if (url.Length > 0) { await NavigateAsync(url); return; }
        ActiveView?.Navigate("about:blank");
        active.Url = ""; active.Title = ""; active.Loading = false; active.Reading = 0;
        await SelectAsync(active);
        FocusAddress();
    }

    private BrowserTab AddTab(string? url = null, bool foreground = true, bool isPrivate = false, string title = "", bool pinned = false, string? inSpace = null, bool loadBackground = true, string group = "")
    {
        url ??= NewTabUrl(isPrivate);
        var tab = new BrowserTab { Url = url, Title = title, Pinned = pinned, IsPrivate = isPrivate, Space = inSpace ?? space, Group = group, UseIcons = Settings.IconGlyphs };
        tabs.Add(tab);
        var menu = new MenuFlyout();
        AddMenu(menu, T("Pin / unpin", "固定 / 取消固定"), () => { tab.Pinned = !tab.Pinned; RefreshTabLists(); ScheduleSave(); });
        AddMenu(menu, T("Duplicate", "复制标签页"), () => AddTab(tab.Url, true, tab.IsPrivate));
        AddMenu(menu, T("Split beside current", "与当前页分屏"), () => { if (active != null && active != tab) { splitOwner = active; split = tab; _ = SelectAsync(active); } });
        AddMenu(menu, T("Move to space…", "移至空间…"), async () => await MoveTabAsync(tab));
        AddMenu(menu, T("Set tab group…", "设置标签组…"), async () => { var name = await PromptAsync(T("Tab group (empty to remove)", "标签组（留空移出分组）"), T("Group name", "组名"), tab.Group); if (name != null) { tab.Group = name; RefreshTabLists(); ScheduleSave(); } });
        AddMenu(menu, T("Close group", "关闭标签组"), () => CloseGroup(tab));
        AddMenu(menu, T("Close", "关闭"), () => CloseTab(tab));
        tab.PropertyChanged += (_, args) => {
            if (active == tab) UpdateChrome();
        };
        tabMenus[tab.Id] = menu;
        RefreshTabLists();
        if (foreground) _ = SelectAsync(tab);
        else if (loadBackground && !Settings.LazyBackgroundTabs && url.Length > 0) _ = LoadBackgroundAsync(tab);
        ScheduleSave();
        return tab;
    }

    private void RefreshTabLists()
    {
        ParkAddress();
        selecting = true;
        var visible = tabs.Where(t => t.Space == space).OrderByDescending(t => t.Pinned).ThenBy(t => t.Group).ToList();
        TopTabs.ItemsSource = new System.Collections.ObjectModel.ObservableCollection<BrowserTab>(visible);
        SideTabs.ItemsSource = new System.Collections.ObjectModel.ObservableCollection<BrowserTab>(Settings.ListsPins ? visible : visible.Where(t => !t.Pinned || t == editingAddressTab));
        RefreshPins(visible);
        if (active != null) { TopTabs.SelectedItem = active; SideTabs.SelectedItem = active; }
        selecting = false;
        UpdateTitleBarRegions();
    }

    private async Task<PageView> GetViewAsync(BrowserTab tab)
    {
        if (!views.TryGetValue(tab.Id, out var view))
        {
            view = new PageView(tab, store, () => ScheduleSave(), url => AddTab(url, true, tab.IsPrivate));
            view.StoreInstallRequested += async id => { await SelectAsync(tab); await InstallStoreExtensionAsync(id); };
            view.DownloadStarted += download => { downloads.Add(download); RefreshPinnedExtensions(); Status.Text = T("Downloading: ", "正在下载：") + download.Name; download.Operation.StateChanged += (_, _) => { if (download.Operation.State == Microsoft.Web.WebView2.Core.CoreWebView2DownloadState.Completed && !tab.IsPrivate) { store.Downloads.RemoveAll(d => d.Path == download.Path); store.Downloads.Insert(0, new(download.Path, download.Operation.Uri, DateTimeOffset.Now)); ScheduleSave(); } }; };
            view.NewWindowTarget += async _ => { var child = AddTab("", true, tab.IsPrivate); return (await GetViewAsync(child)).Control.CoreWebView2; };
            view.OpenLinkRequested += (url, foreground) => AddTab(url, foreground, tab.IsPrivate);
            view.HoveredLink += url => { if (active == tab) Status.Text = url; };
            view.PreviewRequested += async url => await PreviewLinkAsync(url, tab);
            view.PermissionRequested += args => HandleSitePermissionAsync(tab, view, args);
            view.FlowDragRequested += request=>ExecuteFlowDragAsync(tab,view,request);
            view.WebsiteIconChanged += () => { _ = AdoptBookmarkIconAsync(view, tab); };
            view.DownloadLocationRequested += async args =>
            {
                var picker = new global::Windows.Storage.Pickers.FileSavePicker { SuggestedFileName = Path.GetFileNameWithoutExtension(args.ResultFilePath) };
                picker.FileTypeChoices.Add("File", new List<string> { Path.GetExtension(args.ResultFilePath) is { Length: > 0 } extension ? extension : ".bin" });
                InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this)); var file = await picker.PickSaveFileAsync();
                if (file == null) args.Cancel = true; else args.ResultFilePath = file.Path;
            };
            view.PasswordOffered += async login =>
            {
                var passwords = await PasswordStore.ReadAsync();
                if (passwords.Any(p => p == login)) return;
                if (await ShowCardAsync(T("Save password", "保存密码"), new TextBlock { Text = login.Origin + "\n" + login.Username }, T("Save", "保存")) == ContentDialogResult.Primary)
                { await PasswordStore.SaveAsync(login); }
            };
            views.Add(tab.Id, view);
            view.Control.GotFocus += (_, _) =>
            {
                EndAddressEdit();
                if (active == tab || tab != split && tab != splitOwner) return;
                active = tab; tab.LastUsed = DateTimeOffset.Now;
                selecting = true; TopTabs.SelectedItem = tab; SideTabs.SelectedItem = tab; selecting = false;
                UpdateChrome(); ScheduleSave();
            };
            Pages.Children.Add(view.Control);
        }
        await view.InitializeAsync();
        return view;
    }

    private async Task LoadBackgroundAsync(BrowserTab tab)
    {
        try { var view = await GetViewAsync(tab); view.Control.Visibility = Visibility.Collapsed; }
        catch (Exception e) { Status.Text = e.Message; }
    }

    private async Task SelectAsync(BrowserTab tab)
    {
        if (closing || !tabs.Contains(tab)) return;
        if (active != tab) EndAddressEdit();
        if (active != tab && Settings.FloatsOnLeave && ActiveView is { FloatingWindow: null } previous && await previous.Control.CoreWebView2.ExecuteScriptAsync("[...document.querySelectorAll('video')].some(v=>!v.paused)") == "true") await TogglePictureInPictureAsync(false);
        var version = ++selectionVersion;
        if (active != null) active.LastUsed = DateTimeOffset.Now;
        active = tab;
        tab.LastUsed = DateTimeOffset.Now;
        if (space != tab.Space) { space = tab.Space; ApplySettings(); RefreshTabLists(); }
        selecting = true;
        TopTabs.SelectedItem = tab; SideTabs.SelectedItem = tab;
        selecting = false;
        foreach (var view in views.Values.Where(v => v.FloatingWindow == null)) view.Control.Visibility = Visibility.Collapsed;
        Pages.ColumnDefinitions.Clear();
        if (divider != null) { Pages.Children.Remove(divider); divider = null; }
        var pair = split != null && splitOwner != null && (tab == splitOwner || tab == split) && tabs.Contains(split) && tabs.Contains(splitOwner) && split.Space == space && splitOwner.Space == space;
        if (pair)
        {
            Pages.ColumnDefinitions.Add(new() { Width = new(splitRatio, GridUnitType.Star) });
            Pages.ColumnDefinitions.Add(new() { Width = new(6) });
            Pages.ColumnDefinitions.Add(new() { Width = new(1 - splitRatio, GridUnitType.Star) });
            divider = new Thumb { Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Gray), Opacity = .3, HorizontalAlignment = HorizontalAlignment.Stretch, VerticalAlignment = VerticalAlignment.Stretch };
            Grid.SetColumn(divider, 1); Pages.Children.Add(divider);
            divider.DragDelta += (_, e) =>
            {
                splitRatio = Math.Clamp(splitRatio + e.HorizontalChange / Math.Max(1, Pages.ActualWidth - 6), .15, .85);
                Pages.ColumnDefinitions[0].Width = new(splitRatio, GridUnitType.Star);
                Pages.ColumnDefinitions[2].Width = new(1 - splitRatio, GridUnitType.Star);
            };
            divider.DragCompleted += (_, _) => ScheduleSave();
        }
        Welcome.Visibility = tab.Url.Length == 0 || tab.Url == "about:blank" ? Visibility.Visible : Visibility.Collapsed;
        UpdateChrome();
        try
        {
            if (tab.Url.Length > 0)
            {
                var view = await GetViewAsync(tab);
                if (version != selectionVersion || closing) return;
                if (view.FloatingWindow != null) { view.FloatingWindow.Activate(); return; }
                view.Resume();
                Grid.SetColumn(view.Control, pair && tab == split ? 2 : 0);
                view.Control.Visibility = Visibility.Visible;
                if (pair)
                {
                    var otherTab = tab == splitOwner ? split! : splitOwner!;
                    var other = await GetViewAsync(otherTab);
                    if (version != selectionVersion || closing) return;
                    other.Resume(); Grid.SetColumn(other.Control, otherTab == split ? 2 : 0); other.Control.Visibility = Visibility.Visible;
                }
            }
            UpdateChrome();
            ScheduleSave();
        }
        catch (Exception e) { Status.Text = T("Could not open page: ", "无法打开页面：") + e.Message; }
    }

    private void UpdateChrome()
    {
        if (active == null) return;
        if (active.Url.Length > 0 && active.Url != "about:blank" && Welcome.Visibility == Visibility.Visible) { Welcome.Visibility = Visibility.Collapsed; }
        if (editingAddressTab == null) Address.Text = EditableTabAddress(active.Url);
        Title = (active.Title.Length > 0 ? active.Title + " — " : "") + "SearcheXtra" + (active.IsPrivate ? T(" · Private", " · 无痕") : "");
        LoadingBar.Visibility = active.Loading ? Visibility.Visible : Visibility.Collapsed;
        var core = ActiveView?.Control.CoreWebView2;
        BackButton.IsEnabled = core?.CanGoBack == true;
        ForwardButton.IsEnabled = core?.CanGoForward == true;
    }
    private PageView? ActiveView => active != null && views.TryGetValue(active.Id, out var view) ? view : null;

    private async Task NavigateAsync(string text)
    {
        if (await RunAddressCommandAsync(text)) return;

        var uri = ResolveAddress(text);
        EndAddressEdit();
        if (active == null) { AddTab(uri.AbsoluteUri); return; }
        active.Url = uri.AbsoluteUri;
        await SelectAsync(active);
        if (ActiveView?.Control.CoreWebView2?.Source != uri.AbsoluteUri) ActiveView?.Navigate(uri.AbsoluteUri);
    }

    private void CloseGroup(BrowserTab tab)
    {
        if (tab.Group.Length == 0) return;
        var batch = Guid.NewGuid(); var front = active;
        foreach (var member in tabs.Where(t => t.Group == tab.Group && t.Space == tab.Space && t.IsPrivate == tab.IsPrivate).Reverse().ToArray())
            CloseTab(member, batch, member == front);
    }
    private void CloseTab(BrowserTab tab, Guid? batch = null, bool wasActive = false)
    {
        if (editingAddressTab == tab) EndAddressEdit();
        if (!tabs.Contains(tab)) return;
        if (!tab.IsPrivate) closedTabs.Push(new(tab.Url, tab.Title, tab.Pinned, tab.Space, tab.Group) { ClosedBatch = batch, ClosedIndex = tabs.IndexOf(tab), WasActive = wasActive });
        if (views.Remove(tab.Id, out var view)) { Pages.Children.Remove(view.Control); view.Dispose(); }
        tabs.Remove(tab); tabMenus.Remove(tab.Id);
        if (split == tab || splitOwner == tab) { split = null; splitOwner = null; }
        if (active == tab) active = null;
        RefreshTabLists();
        var next = active ?? tabs.LastOrDefault(t => t.Space == space);
        if (next != null) _ = SelectAsync(next); else AddTab(isPrivate: tab.IsPrivate);
        ScheduleSave();
    }
    private void Reopen()
    {
        if (!closedTabs.TryPeek(out var saved)) return;
        if (saved.ClosedBatch is { } batch) RestoreClosedGroup(batch); else RestoreClosedTab(saved);
    }
    private void RestoreClosedTab(SavedTab saved)
    {
        var remaining = closedTabs.ToArray();
        if (!remaining.Any(tab => ReferenceEquals(tab, saved))) return;
        closedTabs.Clear();
        foreach (var tab in remaining.Reverse())
            if (!ReferenceEquals(tab, saved)) closedTabs.Push(tab);
        RestoreTab(saved, true);
    }
    private BrowserTab RestoreTab(SavedTab saved, bool foreground)
    {
        var tab = AddTab(saved.Url, false, false, saved.Title, saved.Pinned, saved.Space, loadBackground: false, group: saved.Group);
        if (saved.ClosedIndex >= 0) tabs.Move(tabs.IndexOf(tab), Math.Min(saved.ClosedIndex, tabs.Count - 1));
        RefreshTabLists();
        if (foreground) _ = SelectAsync(tab);
        return tab;
    }
    private void RestoreClosedGroup(Guid batch)
    {
        var members = closedTabs.Where(tab => tab.ClosedBatch == batch).OrderBy(tab => tab.ClosedIndex).ToArray();
        var remaining = closedTabs.Where(tab => tab.ClosedBatch != batch).Reverse().ToArray();
        closedTabs.Clear(); foreach (var tab in remaining) closedTabs.Push(tab);
        BrowserTab? front = null;
        foreach (var saved in members) { var tab = RestoreTab(saved, false); if (saved.WasActive) front = tab; }
        if (front != null) _ = SelectAsync(front);
    }
    private void ScheduleSave() { if (!closing) { saveTimer.Stop(); saveTimer.Start(); } }
    private async Task SaveStateAsync()
    {
        if (saving) { saveAgain = true; return; }
        saving = true;
        try
        {
            do
            {
                saveAgain = false;
                var open = App.Windows.Where(w => !w.closing).Select(w => w.SnapshotSession()).ToList();
                if (open.Count == 0) open.Add(SnapshotSession());
                store.WindowSessions = open;
                store.Session = open[0];
                await store.SaveAsync();
            } while (saveAgain);
        }
        catch (Exception e) { Status.Text = T("Could not save: ", "无法保存：") + e.Message; }
        finally { saving = false; }
    }
    private SessionState SnapshotSession()
    {
        var saved = tabs.Where(t => !t.IsPrivate).ToList();
        return new() { Tabs = saved.Select(t => new SavedTab(t.Url, t.Title, t.Pinned, t.Space, t.Group)).ToList(), ActiveIndex = saved.Where(t => t.Space == space).ToList().IndexOf(active!), Space = space,
            SplitIndices = split != null && splitOwner != null && saved.Contains(split) && saved.Contains(splitOwner) ? [saved.IndexOf(splitOwner), saved.IndexOf(split)] : [], SplitRatio = splitRatio };
    }
    private async Task SuspendIdleAsync()
    {
        if (!Settings.SuspendTabs || closing) return;
        foreach (var (id, view) in views.ToArray())
        {
            var tab = tabs.FirstOrDefault(t => t.Id == id);
            if (tab == null || tab == active || view.Control.Visibility == Visibility.Visible || tab.Loading) continue;
            if (DateTimeOffset.Now - tab.LastUsed < TimeSpan.FromMinutes(Settings.SuspendAfterMinutes)) continue;
            await view.TrySuspendAsync();
        }
    }
    private void Window_Closed(object sender, WindowEventArgs args)
    {
        closing = true; selectionVersion++;
        sleepTimer.Stop(); saveTimer.Stop(); store.Changed -= OnStoreChanged;
        benchCancellation?.Cancel(); benchCancellation?.Dispose(); benchCancellation = null;
        foreach (var view in views.Values) view.Dispose();
        views.Clear();
        foreach (var preview in previewViews.Values) preview.View.Dispose();
        previewViews.Clear();
    }

    private void Back_Click(object sender, RoutedEventArgs e) { if (ActiveView?.Control.CoreWebView2?.CanGoBack == true) ActiveView.Control.CoreWebView2.GoBack(); }
    private void Forward_Click(object sender, RoutedEventArgs e) { if (ActiveView?.Control.CoreWebView2?.CanGoForward == true) ActiveView.Control.CoreWebView2.GoForward(); }
    private void Reload_Click(object sender, RoutedEventArgs e) => ActiveView?.Control.CoreWebView2?.Reload();
    private async void Home_Click(object sender, RoutedEventArgs e) => await GoHomeAsync();
    private void Reopen_Click(object sender, RoutedEventArgs e) => Reopen();
    private void NewTab_Click(object sender, RoutedEventArgs e) { AddTab(isPrivate: active?.IsPrivate == true); FocusAddress(); }
    private void Tabs_DragCompleted(ListViewBase sender, DragItemsCompletedEventArgs args)
    {
        var order = sender.Items.Cast<BrowserTab>().ToList(); var positions = tabs.Select((tab, index) => (tab, index)).Where(x => order.Contains(x.tab)).Select(x => x.index).ToList();
        for (var i = 0; i < positions.Count; i++) tabs[positions[i]] = order[i];
        RefreshTabLists(); ScheduleSave();
    }
    private void TopTabs_SelectionChanged(object sender, SelectionChangedEventArgs e) { if (!selecting && TopTabs.SelectedItem is BrowserTab tab) _ = SelectAsync(tab); }
    private void SideTabs_SelectionChanged(object sender, SelectionChangedEventArgs e) { if (!selecting && SideTabs.SelectedItem is BrowserTab tab) _ = SelectAsync(tab); }
    private async void Address_KeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == VirtualKey.Enter) { args.Handled = true; await NavigateAsync(Address.Text); }
        else if (args.Key == VirtualKey.Escape) { args.Handled = true; EndAddressEdit(); }
    }
    private void Address_Changed(object sender, TextChangedEventArgs args)
    {
        var query = Address.Text.Trim();
        siteOffer = Settings.SearchesSites && searchSite == null ? SiteSearch.Match(Settings, query) : null;
        Address.PlaceholderText = searchSite != null ? T("Search ", "搜索 ") + searchSite.Name : siteOffer != null ? T("Tab to search ", "按 Tab 搜索 ") + siteOffer.Name : T("Address or search", "网址或搜索");
    }
    private void InstallShortcuts()
    {
        Root.KeyboardAccelerators.Clear();
        shortcutActions.Clear();
        void Key(VirtualKey key, VirtualKeyModifiers modifiers, Action action)
        {
            var name = ShortcutName(key, modifiers); shortcutActions[name] = action;
            if (Settings.Shortcuts.TryGetValue(name, out var custom) && ParseShortcut(custom, out var customKey, out var customModifiers)) { key = customKey; modifiers = customModifiers; }
            var accelerator = new KeyboardAccelerator { Key = key, Modifiers = modifiers };
            accelerator.Invoked += (_, e) => { action(); e.Handled = true; };
            Root.KeyboardAccelerators.Add(accelerator);
        }
        Key(VirtualKey.L, VirtualKeyModifiers.Control, FocusAddress);
        Key(VirtualKey.T, VirtualKeyModifiers.Control, () => NewTab_Click(this, new()));
        Key(VirtualKey.W, VirtualKeyModifiers.Control, () => { if (active != null) CloseTab(active); });
        Key(VirtualKey.T, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, Reopen);
        Key(VirtualKey.N, VirtualKeyModifiers.Control, () => App.NewWindow());
        Key(VirtualKey.N, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () => AddTab(isPrivate: true));
        Key(VirtualKey.R, VirtualKeyModifiers.Control, () => ActiveView?.Control.CoreWebView2?.Reload());
        Key(VirtualKey.D, VirtualKeyModifiers.Control, async () => await AddBookmarkAsync());
        Key(VirtualKey.H, VirtualKeyModifiers.Control, async () => await ShowHistoryAsync());
        Key(VirtualKey.J, VirtualKeyModifiers.Control, async () => await ShowDownloadsAsync());
        Key(VirtualKey.F, VirtualKeyModifiers.Control, async () => await FindAsync());
        Key(VirtualKey.K, VirtualKeyModifiers.Control, async () => await ShowTabSearchAsync());
        Key(VirtualKey.Left, VirtualKeyModifiers.Menu, () => Back_Click(this, new()));
        Key(VirtualKey.Right, VirtualKeyModifiers.Menu, () => Forward_Click(this, new()));
        Key(VirtualKey.Tab, VirtualKeyModifiers.Control, () => CycleTab(1));
        Key(VirtualKey.Tab, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () => CycleTab(-1));
        Key(VirtualKey.S, VirtualKeyModifiers.Control, () => { Settings.Sidebar = !Settings.Sidebar; store.Notify(); ScheduleSave(); });
        Key(VirtualKey.R, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, async () => { if (ActiveView != null) await ActiveView.ReaderAsync(); });
        Key(VirtualKey.H, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, async () => await ShowHiddenAsync());
        Key(VirtualKey.P, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, async () => await TogglePictureInPictureAsync());
        Key(VirtualKey.F11, VirtualKeyModifiers.None, ToggleFullscreen);
        Key(VirtualKey.Escape, VirtualKeyModifiers.None, () => { DismissOverlay(); UpdateChrome(); });
        Key((VirtualKey)188, VirtualKeyModifiers.Control, async () => await ShowSettingsAsync());
    }
    private void CycleTab(int delta)
    {
        var visible = tabs.Where(t => t.Space == space).ToList();
        if (visible.Count > 0) _ = SelectAsync(visible[(visible.IndexOf(active!) + delta + visible.Count) % visible.Count]);
    }
    private void ToggleFullscreen() => AppWindow.SetPresenter(AppWindow.Presenter.Kind == AppWindowPresenterKind.FullScreen ? AppWindowPresenterKind.Overlapped : AppWindowPresenterKind.FullScreen);
    private void AddMenu(MenuFlyout menu, string label, Action act)
    {
        var item = new MenuFlyoutItem { Text = label }; item.Click += (_, _) => act(); menu.Items.Add(item);
    }
    private void Menu_Click(object sender, RoutedEventArgs e)
    {
        var menu = new MenuFlyout();
        AddMenu(menu, T("New window", "新建窗口"), () => App.NewWindow());
        AddMenu(menu, T("New private tab", "新建无痕标签页"), () => AddTab(isPrivate: true));
        AddMenu(menu, T("Reopen closed tab", "恢复关闭的标签页"), Reopen);
        menu.Items.Add(new MenuFlyoutSeparator());
        AddMenu(menu, T("Bookmarks", "书签"), async () => await ShowBookmarksAsync());
        AddMenu(menu, T("History", "历史记录"), async () => await ShowHistoryAsync());
        AddMenu(menu, T("Downloads", "下载"), async () => await ShowDownloadsAsync());
        AddMenu(menu, T("Passwords", "密码"), async () => await ShowPasswordsAsync());
        AddMenu(menu, T("Find in page", "页面内查找"), async () => await FindAsync());
        menu.Items.Add(new MenuFlyoutSeparator());
        AddMenu(menu, T("Split current page", "拆分当前页面"), () => { if (active != null) { splitOwner = active; split = AddTab(active.Url, false, active.IsPrivate); _ = SelectAsync(active); } });
        AddMenu(menu, T("Separate split tabs", "分离分屏标签页"), () => { split = null; splitOwner = null; if (active != null) _ = SelectAsync(active); });
        AddMenu(menu, T("Reader mode", "阅读模式"), async () => { if (ActiveView != null) await ActiveView.ReaderAsync(); });
        AddMenu(menu, T("Picture in picture", "画中画"), async () => await TogglePictureInPictureAsync());
        AddMenu(menu, T("Review hidden elements", "管理隐藏元素"), async () => await ShowHiddenAsync());
        AddMenu(menu, T("Hide page element", "隐藏网页元素"), async () => { if (ActiveView != null) await ActiveView.PickHiddenElementAsync(); });
        AddMenu(menu, T("Reset hidden elements here", "清除此网站的隐藏规则"), async () => { if (active != null && Uri.TryCreate(active.Url, UriKind.Absolute, out var uri)) { store.HiddenElements.Remove(uri.Host); await SaveStateAsync(); foreach (var view in views.Values) await view.UpdateDocumentScriptAsync(); ActiveView?.Control.CoreWebView2?.Reload(); } });
        AddMenu(menu, T("Print", "打印"), () => ActiveView?.Control.CoreWebView2?.ShowPrintUI(Microsoft.Web.WebView2.Core.CoreWebView2PrintDialogKind.Browser));
        AddMenu(menu, T("Developer tools", "开发者工具"), () => ActiveView?.Control.CoreWebView2?.OpenDevToolsWindow());
        menu.Items.Add(new MenuFlyoutSeparator());
        AddMenu(menu, T("Site settings", "网站设置"), async () => await ShowSiteCardAsync());
        AddMenu(menu, T("Extensions", "扩展"), ExtensionsMenu);
        AddMenu(menu, T("Settings", "设置"), async () => await ShowSettingsAsync());
        AddMenu(menu, T("Check releases", "查看最新版本"), () => AddTab("https://github.com/small32/SearcheXtra/releases"));
        menu.ShowAt(Settings.Sidebar ? MenuButton : TopSettings);
    }
}
