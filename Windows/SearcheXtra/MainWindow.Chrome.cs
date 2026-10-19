using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Windowing;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    public static ImageSource? Icon(string uri) => AddressParser.IsWeb(uri) ? new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(uri)) : null;
    internal void OpenExternal(string url) { if (active == null || active.Url is "" or "about:blank") _ = NavigateAsync(url); else AddTab(url); }
    private Action? overlayClose;
    private DateTimeOffset overlayOpened;
    private bool sidebarFolded;
    private Microsoft.UI.Xaml.Controls.Primitives.Thumb? sideSizer;
    private Microsoft.UI.Xaml.Shapes.Rectangle? edgeReveal;
    private void SetupSidebar()
    {
        sideSizer = new() { Width = 7, Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Stretch };
        Grid.SetRowSpan(sideSizer, 4); Sidebar.Children.Add(sideSizer);
        sideSizer.DragDelta += (_, e) =>
        {
            Settings.SidebarWidth = Math.Clamp(Settings.SidebarWidth + (Settings.SidebarRight ? -e.HorizontalChange : e.HorizontalChange), 176, 440);
            UpdateSidebarFold();
            RefreshPins(tabs.Where(tab => tab.Space == space).OrderByDescending(tab => tab.Pinned).ThenBy(tab => tab.Group));
        };
        sideSizer.DragCompleted += (_, _) => ScheduleSave();
        edgeReveal = new() { Width = 6, Fill = new SolidColorBrush(Microsoft.UI.Colors.Transparent), HorizontalAlignment = HorizontalAlignment.Left, Visibility = Visibility.Collapsed };
        Grid.SetColumnSpan(edgeReveal, 3); Canvas.SetZIndex(edgeReveal, 20); Body.Children.Add(edgeReveal);
        edgeReveal.PointerEntered += (_, _) => { sidebarFolded = false; UpdateSidebarFold(); };
        Sidebar.PointerExited += (_, e) => { if (Settings.SidebarAutoHide && !e.GetCurrentPoint(Sidebar).Properties.IsLeftButtonPressed) { sidebarFolded = true; UpdateSidebarFold(); } };
        Root.SizeChanged += (_, _) => SideTabs.MaxHeight = Math.Max(40, Root.ActualHeight - 130 - PinRow.ActualHeight);
    }
    private void UpdateSidebarFold()
    {
        var show = Settings.Sidebar && (!Settings.SidebarAutoHide || !sidebarFolded);
        Sidebar.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
        SidebarColumn.Width = new(show && !Settings.SidebarRight ? Settings.SidebarWidth : 0);
        RightSidebarColumn.Width = new(show && Settings.SidebarRight ? Settings.SidebarWidth : 0);
        if (edgeReveal != null) { edgeReveal.Visibility = Settings.Sidebar && Settings.SidebarAutoHide ? Visibility.Visible : Visibility.Collapsed; edgeReveal.HorizontalAlignment = Settings.SidebarRight ? HorizontalAlignment.Right : HorizontalAlignment.Left; }
        if (sideSizer != null) sideSizer.HorizontalAlignment = Settings.SidebarRight ? HorizontalAlignment.Left : HorizontalAlignment.Right;
    }
    private SolidColorBrush Brush(string name, double opacity = 1)
    {
        var dark = Root.ActualTheme == ElementTheme.Dark;
        var value = name switch { "Ink" => dark ? 237 : 23, "Wash" => dark ? 45 : 239, "Hairline" => dark ? 51 : 232, _ => dark ? 28 : 255 };
        return new(global::Windows.UI.Color.FromArgb((byte)(255 * opacity), (byte)value, (byte)value, (byte)value));
    }
    private void LayoutChrome()
    {
        Toolbar.Visibility = Visibility.Visible;
        TopStrip.Visibility = Settings.Sidebar ? Visibility.Collapsed : Visibility.Visible;
        TopSettings.Visibility = Visibility.Visible;
        ExtensionsButton.Visibility = Visibility.Visible;
        Toolbar.ColumnDefinitions[1].Width = Settings.NavigationLeft ? GridLength.Auto : new(1, GridUnitType.Star);
        Toolbar.ColumnDefinitions[2].Width = Settings.NavigationLeft ? new(1, GridUnitType.Star) : GridLength.Auto;
        Grid.SetColumn(Helm, Settings.NavigationLeft ? 1 : 2);
        Grid.SetColumn(TopStrip, Settings.NavigationLeft ? 2 : 1);
        Helm.Margin = new(8, 0, 10, 0);
        Helm.HorizontalAlignment = Settings.NavigationLeft ? HorizontalAlignment.Left : HorizontalAlignment.Right;
        SidebarHeader.Visibility = Visibility.Collapsed;
        Sidebar.RowDefinitions[0].Height = new(0);
        UpdateTitleBarRegions();
        SpacesButton.Visibility = Settings.UsesSpaces ? Visibility.Visible : Visibility.Collapsed;
        UpdateSidebarFold();
    }
    private void RefreshPins(IEnumerable<BrowserTab> visible)
    {
        PinRow.Children.Clear(); PinRow.RowDefinitions.Clear(); PinRow.ColumnDefinitions.Clear();
        var columnCount = Math.Max(1, (int)((Settings.SidebarWidth - 16) / 38)); for (var i = 0; i < columnCount; i++) PinRow.ColumnDefinitions.Add(new() { Width = new(38) });
        var pinIndex = 0;
        if (Settings.ListsPins) return;
        foreach (var tab in visible.Where(t => t.Pinned && t != editingAddressTab))
        {
            var button = new Button { Content = tab.Letter, Tag = tab, Width = 34, Height = 34, Padding = new(0), CornerRadius = new(7), BorderThickness = new(0), Background = Brush(active == tab ? "Hairline" : "Wash"), FontSize = 12 };
            button.Click += (_, _) => { if (active == tab) FocusAddress(); else _ = SelectAsync(tab); };
            button.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler(Tab_PointerPressed), true);
            button.ContextFlyout = tabMenus[tab.Id];
            if (Settings.IconGlyphs && Icon(tab.Favicon) is { } icon) button.Content = new Image { Source = icon, Width = 16, Height = 16 };
            if (pinIndex % columnCount == 0) PinRow.RowDefinitions.Add(new() { Height = new(38) }); Grid.SetColumn(button, pinIndex % columnCount); Grid.SetRow(button, pinIndex / columnCount); pinIndex++;
            ToolTipService.SetToolTip(button, tab.Label); PinRow.Children.Add(button);
        }
    }
    private void TabContainer_Changed(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.Item is not BrowserTab tab) return;
        args.ItemContainer.ContextFlyout = tabMenus.GetValueOrDefault(tab.Id);
        if (args.ItemContainer.Tag == null)
        {
            args.ItemContainer.Tag = true;
            args.ItemContainer.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler(Tab_PointerPressed), true);
            static void ShowCross(DependencyObject root, double opacity) { if (FindAddressPart<Button>(root, "TabClose") is { } cross) cross.Opacity = opacity; }
            args.ItemContainer.PointerEntered += (source, _) => ShowCross((DependencyObject)source, .55);
            args.ItemContainer.PointerExited += (source, _) => ShowCross((DependencyObject)source, 0);
        }
        if (sender == TopTabs) args.ItemContainer.Width = TabWidth(tab);
        if (tab == editingAddressTab && sender == AddressList) DispatcherQueue.TryEnqueue(() => AttachAddressEditor(false));
    }
    private void Tab_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (sender is not FrameworkElement element ||
            e.GetCurrentPoint(element).Properties.PointerUpdateKind != Microsoft.UI.Input.PointerUpdateKind.MiddleButtonPressed) return;
        // Read the current item: WinUI recycles list containers when tabs move or close.
        var tab = sender switch { ListViewItem { Content: BrowserTab item } => item, Button { Tag: BrowserTab item } => item, _ => null };
        if (tab == null) return;
        e.Handled = true;
        CloseTab(tab);
    }
    private void TabCross_Click(object sender, RoutedEventArgs e) { if (sender is Button { Tag: BrowserTab tab }) CloseTab(tab); }
    private async void Settings_Click(object sender, RoutedEventArgs e) => await ShowSettingsAsync();
    private void Card_Tapped(object sender, TappedRoutedEventArgs e) => e.Handled = true;
    private void OverlayBackdrop_Tapped(object sender, TappedRoutedEventArgs e) { if (DateTimeOffset.Now - overlayOpened > TimeSpan.FromMilliseconds(250)) DismissOverlay(); }
    private void DismissOverlay() { overlayClose?.Invoke(); EndAddressEdit(); }
    private SearchSite? searchSite;
    private SearchSite? siteOffer;
    private void SiteSearch_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == global::Windows.System.VirtualKey.Tab && Settings.SearchesSites && siteOffer != null)
        { searchSite = siteOffer; Address.Text = ""; Address.PlaceholderText = T("Search ", "搜索 ") + searchSite.Name; Address.Focus(FocusState.Programmatic); e.Handled = true; }
        else if (e.Key == global::Windows.System.VirtualKey.Back && Address.Text.Length == 0) { searchSite = null; Address.PlaceholderText = T("Address or search", "网址或搜索"); }
    }
    private Uri ResolveAddress(string text)
    {
        if (searchSite != null) { var site = searchSite; searchSite = null; Address.PlaceholderText = T("Address or search", "网址或搜索"); return new Uri(site.Template.Replace("%s", Uri.EscapeDataString(text.Trim()))); }
        var parts = text.Trim().Split(' ', 2, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 2 && Settings.Keywords.FirstOrDefault(k => k.Keyword.Equals(parts[0], StringComparison.OrdinalIgnoreCase)) is { } keyword)
            return new(keyword.Template.Replace("%s", Uri.EscapeDataString(parts[1])));
        return AddressParser.Resolve(text, Settings.SearchTemplate.Replace("%s", "{0}"));
    }
    private async Task<ContentDialogResult> ShowCardAsync(string title, UIElement content, string? primary = null, bool fitWindow = false, string? secondary = null)
    {
        if (closing || OverlayLayer.Visibility == Visibility.Visible) return ContentDialogResult.None;
        var done = new TaskCompletionSource<ContentDialogResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        var panel = new Grid { Width = content is FrameworkElement { Width: > 560 } sized ? sized.Width + 44 : 560, MaxHeight = 650, Padding = new(22), RowSpacing = 16 };
        if (fitWindow && content is FrameworkElement popup) { panel.Width = popup.Width + 44; panel.MaxHeight = Math.Max(120, Root.ActualHeight - 32); }
        panel.RowDefinitions.Add(new() { Height = GridLength.Auto }); panel.RowDefinitions.Add(new() { Height = new(1, GridUnitType.Star) }); panel.RowDefinitions.Add(new() { Height = GridLength.Auto });
        var header = new Grid(); var heading = new TextBlock { Text = title, FontSize = 17, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold };
        header.Children.Add(heading); var close = QuietButton("×"); close.HorizontalAlignment = HorizontalAlignment.Right; close.Click += (_, _) => overlayClose?.Invoke(); header.Children.Add(close); panel.Children.Add(header);
        Grid.SetRow((FrameworkElement)content, 1); panel.Children.Add(content);
        if (primary != null) { var button = QuietButton(primary); button.HorizontalAlignment = HorizontalAlignment.Right; Grid.SetRow(button, 2); button.Click += (_, _) => Finish(ContentDialogResult.Primary); panel.Children.Add(button); }
        if (secondary != null) { var button = QuietButton(secondary); button.HorizontalAlignment = HorizontalAlignment.Left; Grid.SetRow(button, 2); button.Click += (_, _) => Finish(ContentDialogResult.Secondary); panel.Children.Add(button); }
        void Finish(ContentDialogResult result) { OverlayLayer.Children.Clear(); OverlayLayer.Visibility = Visibility.Collapsed; overlayClose = null; done.TrySetResult(result); }
        overlayClose = () => Finish(ContentDialogResult.None);
        var card = new Border { Background = Brush("Ground"), BorderBrush = Brush("Hairline"), BorderThickness = new(1), CornerRadius = new(16), Child = panel, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        card.Tapped += Card_Tapped; OverlayLayer.Children.Add(card); OverlayLayer.Visibility = Visibility.Visible; overlayOpened = DateTimeOffset.Now;
        return await done.Task;
    }
    private Button QuietButton(string label)
        => new() { Content = label, FontSize = 12, Padding = new(10, 5, 10, 5), MinHeight = 26, MinWidth = 26, CornerRadius = new(7), Background = Brush("Wash"), BorderThickness = new(0) };
}
