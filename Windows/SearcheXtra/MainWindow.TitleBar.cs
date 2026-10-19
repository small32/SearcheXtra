using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Windows.Foundation;
using Windows.Graphics;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private void SetupTitleBar()
    {
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(Toolbar);
        AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        Toolbar.SizeChanged += (_, _) => UpdateTitleBarRegions();
        TopStrip.SizeChanged += (_, _) => UpdateTitleBarRegions();
        Helm.SizeChanged += (_, _) => UpdateTitleBarRegions();
        TitleActions.SizeChanged += (_, _) => UpdateTitleBarRegions();
        Root.Loaded += (_, _) => UpdateTitleBarRegions();
        AppWindow.Changed += (_, _) => UpdateTitleBarRegions();
    }

    private void UpdateTitleBarColors()
    {
        var bar = AppWindow.TitleBar;
        bar.ButtonBackgroundColor = bar.ButtonInactiveBackgroundColor = Microsoft.UI.Colors.Transparent;
        bar.ButtonForegroundColor = Brush("Ink").Color;
        bar.ButtonInactiveForegroundColor = Brush("Ink", .55).Color;
        bar.ButtonHoverBackgroundColor = Brush("Wash").Color;
        bar.ButtonHoverForegroundColor = Brush("Ink").Color;
    }

    private void UpdateTitleBarRegions()
    {
        if (closing || Root.XamlRoot == null || Toolbar.ActualWidth <= 0) return;
        var pinnedRoom = Math.Max(0, (int)((Toolbar.ActualWidth - CaptionInset.Width.Value - Helm.ActualWidth - 380) / 30));
        for (var i = 0; i < PinnedExtensions.Children.Count; i++)
            PinnedExtensions.Children[i].Visibility = i < pinnedRoom ? Visibility.Visible : Visibility.Collapsed;
        var scale = Root.XamlRoot.RasterizationScale;
        CaptionInset.Width = new(AppWindow.TitleBar.RightInset / scale);
        // Reserve empty caption space for dragging even when the tabs overflow.
        TopTabs.MaxWidth = Math.Max(0, Toolbar.ActualWidth - CaptionInset.Width.Value - Helm.ActualWidth - TitleActions.ActualWidth - Toolbar.ColumnDefinitions[0].ActualWidth - 72);
        var visible = tabs.Where(t => t.Space == space).ToList();
        var pins = visible.Count(t => t.Pinned && t != editingAddressTab);
        var editing = visible.Contains(editingAddressTab!);
        addressTabWidth = Math.Min(372, TopTabs.MaxWidth);
        var normal = visible.Count - pins - (editing ? 1 : 0);
        normalTabWidth = normal == 0 ? 186 : Math.Clamp((TopTabs.MaxWidth - pins * 54 - (editing ? addressTabWidth : 0)) / normal, 80, 186);
        foreach (var tab in visible)
            if (TopTabs.ContainerFromItem(tab) is FrameworkElement item && item.Width != TabWidth(tab))
                item.Width = TabWidth(tab);
        TopTabs.Width = Math.Min(TopTabs.MaxWidth, visible.Sum(TabWidth));
        var regions = new List<RectInt32>();
        foreach (var element in new FrameworkElement[] { TopStrip, Helm, TitleActions })
        {
            if (element.Visibility != Visibility.Visible || element.ActualWidth <= 0) continue;
            var bounds = element.TransformToVisual(Root).TransformBounds(new Rect(0, 0, element.ActualWidth, element.ActualHeight));
            regions.Add(new((int)Math.Round(bounds.X * scale), (int)Math.Round(bounds.Y * scale),
                (int)Math.Round(bounds.Width * scale), (int)Math.Round(bounds.Height * scale)));
        }
        InputNonClientPointerSource.GetForWindowId(AppWindow.Id).SetRegionRects(NonClientRegionKind.Passthrough, regions.ToArray());
    }
}
