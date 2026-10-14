using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private async Task VerifyBookmarkIconsAsync(Action<bool, string> check)
    {
        var previousBookmarks = store.Bookmarks;
        var previousFlags = (Settings.IconGlyphs, Settings.BookmarksBar, Settings.BookmarkWebsiteIcons);
        using var cancellation = new CancellationTokenSource();
        var server = new TcpListener(IPAddress.Loopback, 0);
        var handlers = new ConcurrentBag<Task>();
        var png = await File.ReadAllBytesAsync(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.png"));
        var pageRequests = 0;
        var iconRequests = 0;
        server.Start();
        var fixture = $"http://127.0.0.1:{((IPEndPoint)server.LocalEndpoint).Port}/";
        var serving = Task.Run(async () =>
        {
            try
            {
                while (!cancellation.IsCancellationRequested)
                {
                    var client = await server.AcceptTcpClientAsync(cancellation.Token);
                    handlers.Add(Task.Run(async () =>
                    {
                        using (client)
                        {
                            try
                            {
                                using var stream = client.GetStream();
                                var request = new byte[4096];
                                var length = await stream.ReadAsync(request, cancellation.Token);
                                if (length == 0) return;
                                var path = Encoding.ASCII.GetString(request, 0, length).Split(' ')[1];
                                var icon = path == "/custom.png";
                                var missing = path == "/favicon.ico";
                                if (icon) Interlocked.Increment(ref iconRequests);
                                else if (!missing) Interlocked.Increment(ref pageRequests);
                                var body = icon ? png : missing ? [] : Encoding.UTF8.GetBytes(
                                    "<!doctype html><html><head><title>Unvisited bookmark</title><link rel='icon' href='/custom.png'></head><body>Bookmark fixture</body></html>");
                                var header = Encoding.ASCII.GetBytes($"HTTP/1.1 {(missing ? "404 Not Found" : "200 OK")}\r\nContent-Type: {(icon ? "image/png" : "text/html; charset=utf-8")}\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n");
                                await Task.Delay(30, cancellation.Token);
                                await stream.WriteAsync(header, cancellation.Token);
                                await stream.WriteAsync(body, cancellation.Token);
                            }
                            catch (OperationCanceledException) { }
                            catch (IOException) { }
                        }
                    }));
                }
            }
            catch (OperationCanceledException) { }
            catch (SocketException) when (cancellation.IsCancellationRequested) { }
            catch (ObjectDisposedException) when (cancellation.IsCancellationRequested) { }
        });
        static IEnumerable<T> Descendants<T>(DependencyObject parent) where T : DependencyObject
        {
            if (parent is T item) yield return item;
            for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
                foreach (var child in Descendants<T>(VisualTreeHelper.GetChild(parent, i))) yield return child;
        }
        async Task Wait(Func<bool> ready, string description)
        {
            var deadline = DateTime.UtcNow.AddSeconds(15);
            while (!ready())
            {
                if (DateTime.UtcNow > deadline) throw new TimeoutException("Bookmark favicon test timed out: " + description);
                Root.UpdateLayout();
                await Task.Delay(25);
            }
        }
        static bool Decoded(ImageSource? source) => source is BitmapImage { PixelWidth: > 0, PixelHeight: > 0 };
        static Grid? Mark(DependencyObject parent) => Descendants<Grid>(parent).FirstOrDefault(grid => grid.Name == "BookmarkWebsiteIcon");
        static BitmapImage? Bitmap(DependencyObject parent) => Mark(parent) is { } mark ? Descendants<Image>(mark).Select(image => image.Source).OfType<BitmapImage>().FirstOrDefault() : null;
        static bool Shown(DependencyObject parent) => Mark(parent) is { Visibility: Visibility.Visible } mark && Descendants<Image>(mark).Any(image => image.Visibility == Visibility.Visible && Decoded(image.Source));
        Button BarButton(Bookmark bookmark) => BookmarkRow.Children.OfType<Button>().Single(button => ReferenceEquals(button.Tag, bookmark));
        void ShowFolder(Button button)
        {
            button.Flyout.ShowAt(button);
            Root.UpdateLayout();
        }
        void Expand(MenuFlyoutSubItem item)
        {
            var peer = FrameworkElementAutomationPeer.FromElement(item) ?? FrameworkElementAutomationPeer.CreatePeerForElement(item);
            if (peer?.GetPattern(PatternInterface.ExpandCollapse) is not IExpandCollapseProvider provider)
                throw new InvalidOperationException("The bookmark submenu does not expose its native expand/collapse automation pattern");
            provider.Expand();
            Root.UpdateLayout();
        }
        MenuFlyoutItem MenuLeaf(MenuFlyout menu, Bookmark bookmark) => menu.Items.OfType<MenuFlyoutItem>().Single(item => ReferenceEquals(item.Tag, bookmark));
        ListView ManagerList() => FindAddressPart<ListView>(OverlayLayer, "BookmarkManagerList")!;
        ListViewItem ManagerRow(Bookmark bookmark) => ManagerList().Items.Cast<ListViewItem>().Single(item => ReferenceEquals(item.Tag, bookmark));
        Task? manager = null;
        MenuFlyout? openedMenu = null;
        try
        {
            Settings.IconGlyphs = false;
            Settings.BookmarksBar = true;
            Settings.BookmarkWebsiteIcons = true;
            var top = new Bookmark { Title = "Unvisited top bookmark", Url = fixture + "unvisited-top" };
            var nested = new Bookmark { Title = "Unvisited nested bookmark", Url = fixture + "unvisited-nested" };
            var deep = new Bookmark { Title = "Unvisited deep bookmark", Url = fixture + "unvisited-deep" };
            var deepFolder = new Bookmark { Title = "Deep folder", Children = [deep] };
            var folder = new Bookmark { Title = "Folder", Children = [nested, deepFolder] };
            store.Bookmarks = [top, folder];
            check(!tabs.Any(tab => tab.Url.StartsWith(fixture, StringComparison.Ordinal)),
                "Bookmark icon fixture has never been opened as a browser tab");
            ApplySettings();
            Root.UpdateLayout();
            var concurrent = await Task.WhenAll(new[] { top.Url!, nested.Url!, deep.Url! }.Select(BookmarkIcons.Shared.GetAsync));
            await Wait(() => Shown(BarButton(top)), "unvisited bookmark bar image decode");
            check(Shown(BarButton(top)) && concurrent.All(Decoded),
                "An unvisited bookmark displays a decoded real website icon without opening its page or enabling tab icons");
            check(BookmarkIcons.Shared.SourceUrl(top.Url!) == fixture + "custom.png" && Volatile.Read(ref pageRequests) > 0,
                "Bookmark icons discover the page's custom rel=icon URL when favicon.ico is unavailable");
            check(Volatile.Read(ref iconRequests) == 1 && Volatile.Read(ref pageRequests) == 1,
                "Concurrent bookmark lookups on one origin fetch and decode its page and custom icon only once");
            check(!Settings.IconGlyphs && Settings.BookmarkWebsiteIcons,
                "Bookmark website icons remain independent of the tab letter/icon preference");

            openedMenu = (MenuFlyout)BarButton(folder).Flyout;
            ShowFolder(BarButton(folder));
            var nestedItem = MenuLeaf(openedMenu, nested);
            await Wait(() => nestedItem.Icon is ImageIcon icon && Decoded(icon.Source), "folder dropdown icon decode");
            check(nestedItem.IsLoaded && nestedItem.Icon is ImageIcon nestedIcon && Decoded(nestedIcon.Source),
                "A visible bookmark folder dropdown displays the real website icon beside its bookmarks");
            var submenu = openedMenu.Items.OfType<MenuFlyoutSubItem>().Single(item => ReferenceEquals(item.Tag, deepFolder));
            Expand(submenu);
            var deepItem = submenu.Items.OfType<MenuFlyoutItem>().Single(item => ReferenceEquals(item.Tag, deep));
            await Wait(() => deepItem.Icon is ImageIcon icon && Decoded(icon.Source), "deep submenu icon decode");
            check(deepItem.IsLoaded && deepItem.Icon is ImageIcon deepIcon && Decoded(deepIcon.Source),
                "Nested bookmark dropdowns retain decoded website icons at deeper folder levels");
            openedMenu.Hide(); openedMenu = null;

            manager = ShowBookmarksAsync(folder.Id);
            await Wait(() => OverlayLayer.Visibility == Visibility.Visible && FindAddressPart<ListView>(OverlayLayer, "BookmarkManagerList") != null, "bookmark manager open");
            await Wait(() => Shown(ManagerRow(nested)), "bookmark manager image decode");
            check(Shown(ManagerRow(nested)),
                "Bookmark manager rows display the same decoded website icons as the bookmarks bar and dropdowns");
            var original = Bitmap(ManagerRow(nested));
            await BookmarkIcons.Shared.AdoptAsync(top.Url!, fixture + "adopted.png", png);
            await Wait(() => Shown(ManagerRow(nested)) && !ReferenceEquals(original, Bitmap(ManagerRow(nested))), "live adopted favicon refresh");
            check(BookmarkIcons.Shared.SourceUrl(nested.Url!) == fixture + "adopted.png" && !ReferenceEquals(original, Bitmap(ManagerRow(nested))),
                "A newly adopted favicon refreshes the already-open bookmark manager without reopening it");
            var requestsBeforeReload = (Volatile.Read(ref pageRequests), Volatile.Read(ref iconRequests));
            var reloadedIcons = new BookmarkIcons();
            var reloadedImage = await reloadedIcons.GetAsync(nested.Url!);
            check(Decoded(reloadedImage) && reloadedIcons.SourceUrl(nested.Url!) == fixture + "adopted.png" &&
                requestsBeforeReload == (Volatile.Read(ref pageRequests), Volatile.Read(ref iconRequests)),
                "A fresh bookmark icon service restores the persisted decoded favicon and its URL without network requests");

            var option = Descendants<StackPanel>(OverlayLayer).Single(panel => panel.Children.OfType<TextBlock>().Any(label => label.Text == T("Show bookmark website icons", "书签显示网站图标")));
            var iconSwitch = option.Children.OfType<ToggleSwitch>().Last();
            iconSwitch.IsOn = false;
            await Wait(() => !Settings.BookmarkWebsiteIcons && !Shown(ManagerRow(nested)), "website icon switch disables live manager icons");
            check(!Shown(ManagerRow(nested)),
                "Turning off the website-icon switch hides icons immediately in the open bookmark manager");
            DismissOverlay(); await manager; manager = null;
            Root.UpdateLayout();
            check(!Shown(BarButton(top)) && Mark(BarButton(top)) == null,
                "Turning off website icons removes the bookmark bar icon without leaving an icon placeholder");
            openedMenu = (MenuFlyout)BarButton(folder).Flyout;
            ShowFolder(BarButton(folder));
            nestedItem = MenuLeaf(openedMenu, nested);
            submenu = openedMenu.Items.OfType<MenuFlyoutSubItem>().Single(item => ReferenceEquals(item.Tag, deepFolder));
            Expand(submenu);
            deepItem = submenu.Items.OfType<MenuFlyoutItem>().Single(item => ReferenceEquals(item.Tag, deep));
            check(nestedItem.Icon == null && deepItem.Icon == null,
                "The website-icon switch also hides icons throughout the bookmark folder dropdowns");
            openedMenu.Hide(); openedMenu = null;

            var previousRequests = (Volatile.Read(ref pageRequests), Volatile.Read(ref iconRequests));
            Settings.BookmarkWebsiteIcons = true;
            ApplySettings();
            await Wait(() => Shown(BarButton(top)), "cached favicon restores bar icon");
            check(previousRequests == (Volatile.Read(ref pageRequests), Volatile.Read(ref iconRequests)),
                "Re-enabling bookmark website icons uses the decoded cache without repeating network requests");
        }
        finally
        {
            openedMenu?.Hide();
            if (manager != null) { DismissOverlay(); await manager; }
            store.Bookmarks = previousBookmarks;
            (Settings.IconGlyphs, Settings.BookmarksBar, Settings.BookmarkWebsiteIcons) = previousFlags;
            ApplySettings();
            cancellation.Cancel();
            server.Stop();
            await serving;
            await Task.WhenAll(handlers.ToArray());
        }
    }
}
