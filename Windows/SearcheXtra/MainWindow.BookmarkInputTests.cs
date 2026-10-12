using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System.Runtime.InteropServices;
using WinRT.Interop;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    [StructLayout(LayoutKind.Sequential)] private struct BookmarkMousePoint { public int X, Y; }
    [DllImport("user32.dll")] private static extern bool ClientToScreen(nint window, ref BookmarkMousePoint point);
    [DllImport("user32.dll")] private static extern nint WindowFromPoint(BookmarkMousePoint point);
    [StructLayout(LayoutKind.Sequential)] private struct BookmarkMouseInput { public int X, Y; public uint Data, Flags, Time; public nint Extra; }
    [StructLayout(LayoutKind.Sequential)] private struct BookmarkInput { public uint Type; public BookmarkMouseInput Mouse; }
    [DllImport("user32.dll")] private static extern uint SendInput(uint count, BookmarkInput[] inputs, int size);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out BookmarkMousePoint point);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(nint window);
    [DllImport("user32.dll")] private static extern bool ShowWindow(nint window,int command);
    [DllImport("user32.dll")] private static extern nint GetAncestor(nint window,uint flags);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint window,out uint process);

    private async Task VerifyBookmarkMiddleInputAsync(string fixture, Action<bool, string> check)
    {
        var old = (Settings.BookmarksBar, Settings.BookmarkOpening, Settings.BookmarkWebsiteIcons);
        var previous = active;
        var bookmarks = store.Bookmarks;
        var originalTabs = tabs.ToHashSet();
        var leaf = new Bookmark { Title = "Middle click fixture", Url = fixture + "bookmark-middle" };
        MenuFlyout? menu = null;
        GetCursorPos(out var previousPointer);
        ShowWindow(WindowNative.GetWindowHandle(this),9);
        Activate();
        SetForegroundWindow(WindowNative.GetWindowHandle(this));
        try {
            Settings.BookmarksBar = true; Settings.BookmarkWebsiteIcons = false;
            store.Bookmarks = [leaf, new Bookmark { Title = "Folder", Children = [leaf] }];
            ApplySettings(); Root.UpdateLayout();
            await Task.Delay(150);
            async Task Click(FrameworkElement target, string label) {
                Root.UpdateLayout();
                var point = target.TransformToVisual(Root).TransformPoint(new(target.ActualWidth / 2, target.ActualHeight / 2));
                var screen = new BookmarkMousePoint { X = (int)(point.X * Root.XamlRoot.RasterizationScale), Y = (int)(point.Y * Root.XamlRoot.RasterizationScale) };
                ClientToScreen(WindowNative.GetWindowHandle(this), ref screen);
                var window = WindowFromPoint(screen);
                check(window != 0, label + " has a native mouse target");
                GetWindowThreadProcessId(window,out var process);
                check(process==Environment.ProcessId,label+$" targets the test process (screen {screen.X},{screen.Y}; window {window}; pid {process}/{Environment.ProcessId}; position {AppWindow.Position.X},{AppWindow.Position.Y}; scale {Root.XamlRoot.RasterizationScale})");
                var count = tabs.Count; var selected = active;
                SetCursorPos(screen.X, screen.Y);
                await Task.Delay(50);
                check(SendInput(1, [new() { Mouse = new() { Flags = 0x20 } }], Marshal.SizeOf<BookmarkInput>()) == 1, label + " receives a native middle press");
                await Task.Delay(40);
                SendInput(1, [new() { Mouse = new() { Flags = 0x40 } }], Marshal.SizeOf<BookmarkInput>());
                var deadline = DateTime.UtcNow.AddSeconds(2);
                while (tabs.Count == count && DateTime.UtcNow < deadline) await Task.Delay(25);
                check(tabs.Count == count + 1 && active == selected && tabs.Last().Url == leaf.Url, label + $" opens exactly one background tab (count {count}->{tabs.Count}, active unchanged {active==selected})");
            }
            foreach (var opening in Enum.GetValues<BookmarkOpening>()) {
                Settings.BookmarkOpening = opening;
                await Click((FrameworkElement)BookmarkRow.Children[0], "Bar middle click with " + opening);
                var folder = (Button)BookmarkRow.Children[1];
                menu = (MenuFlyout)folder.Flyout;
                menu.ShowAt(folder); await Task.Delay(100);
                await Click((MenuFlyoutItem)menu.Items[0], "Dropdown middle click with " + opening);
                menu.Hide(); menu = null;
            }
        } finally {
            menu?.Hide();
            SetCursorPos(previousPointer.X, previousPointer.Y);
            foreach (var tab in tabs.Where(tab => !originalTabs.Contains(tab)).ToArray()) CloseTab(tab);
            store.Bookmarks = bookmarks;
            (Settings.BookmarksBar, Settings.BookmarkOpening, Settings.BookmarkWebsiteIcons) = old;
            ApplySettings();
            if (previous != null && tabs.Contains(previous)) await SelectAsync(previous);
        }
    }
}
