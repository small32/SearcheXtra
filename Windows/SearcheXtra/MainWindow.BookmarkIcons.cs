using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.Web.WebView2.Core;
using global::Windows.Storage.Streams;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private HashSet<string>? bookmarkIconOrigins;
    private List<Bookmark>? bookmarkIconRoots;

    private bool HasBookmarkIconOrigin(string page)
    {
        if (BookmarkIcons.OriginFor(page) is not { } origin) return false;
        if (bookmarkIconOrigins == null || bookmarkIconRoots != store.Bookmarks)
        {
            bookmarkIconRoots = store.Bookmarks;
            bookmarkIconOrigins = BookmarkImport.Flatten(store.Bookmarks).Select(node => BookmarkIcons.OriginFor(node.Url ?? "")).OfType<string>().ToHashSet();
        }
        return bookmarkIconOrigins.Contains(origin);
    }

    private Grid BookmarkWebsiteIcon(string url, double size)
    {
        var mark = new Grid { Name = "BookmarkWebsiteIcon", Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center };
        var fallback = new FontIcon { Glyph = "\uE774", FontSize = size };
        var image = new Image { Width = size, Height = size, Stretch = Stretch.Uniform, Visibility = Visibility.Collapsed };
        mark.Children.Add(fallback);
        mark.Children.Add(image);
        BindBookmarkIcon(mark, url, source => {
            image.Source = source;
            image.Visibility = source == null ? Visibility.Collapsed : Visibility.Visible;
            fallback.Visibility = source == null ? Visibility.Visible : Visibility.Collapsed;
        });
        return mark;
    }

    private void BindBookmarkIcon(FrameworkElement host, string url, Action<ImageSource?> apply)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var page) || !AddressParser.IsWeb(url)) return;
        var origin = new UriBuilder(page.Scheme, page.IdnHost, page.IsDefaultPort ? -1 : page.Port).Uri.GetLeftPart(UriPartial.Authority);
        var observing = false;
        async Task RefreshAsync() {
            var source = await BookmarkIcons.Shared.GetAsync(url);
            if (host.IsLoaded) apply(source);
        }
        void Changed(string site) { if (site == origin) _ = RefreshAsync(); }
        void Loaded(object sender, RoutedEventArgs args) {
            if (!observing) { BookmarkIcons.Shared.Changed += Changed; observing = true; }
            _ = RefreshAsync();
        }
        host.Loaded += Loaded;
        host.Unloaded += (_, _) => {
            if (observing) { BookmarkIcons.Shared.Changed -= Changed; observing = false; }
        };
        if (host.IsLoaded) Loaded(host, new RoutedEventArgs());
    }

    private async Task AdoptBookmarkIconAsync(PageView view, BrowserTab tab)
    {
        var core = view.Control.CoreWebView2;
        if (core == null || !HasBookmarkIconOrigin(core.Source) || string.IsNullOrEmpty(core.FaviconUri)) return;
        var page = core.Source;
        var icon = core.FaviconUri;
        try {
            using var stream = await core.GetFaviconAsync(CoreWebView2FaviconImageFormat.Png);
            if (stream == null || stream.Size == 0 || stream.Size > 4 * 1024 * 1024) return;
            using var reader = new DataReader(stream.GetInputStreamAt(0));
            await reader.LoadAsync((uint)stream.Size);
            var png = new byte[(int)stream.Size];
            reader.ReadBytes(png);
            await BookmarkIcons.Shared.AdoptAsync(page, icon, png, persist: !tab.IsPrivate);
        }
        catch (Exception ex) when (ex is System.Runtime.InteropServices.COMException or InvalidOperationException or IOException) { }
    }
}
