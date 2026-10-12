using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private readonly SemaphoreSlim permissionGate = new(1, 1);

    private async Task HandleSitePermissionAsync(BrowserTab tab, PageView view, CoreWebView2PermissionRequestedEventArgs args)
    {
        // A dismissed or unavailable prompt is a denial for this request only.
        args.State = CoreWebView2PermissionState.Deny;
        if (!Uri.TryCreate(args.Uri, UriKind.Absolute, out var uri)) return;
        var document = tab.Url;
        var entered = false;
        try
        {
            await permissionGate.WaitAsync(view.Lifetime);
            entered = true;
            while (OverlayLayer.Visibility == Visibility.Visible)
            {
                var changed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                var callback = OverlayLayer.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) => changed.TrySetResult());
                try
                {
                    if (OverlayLayer.Visibility == Visibility.Visible) await changed.Task.WaitAsync(view.Lifetime);
                }
                finally { OverlayLayer.UnregisterPropertyChangedCallback(UIElement.VisibilityProperty, callback); }
            }
            if (closing || view.IsDisposed || active != tab || tab.Url != document) return;
            var content = new TextBlock { Text = T("This site requests: ", "此网站请求：") + SitePermissionName(args.PermissionKind.ToString()), TextWrapping = TextWrapping.Wrap };
            var pending = ShowCardAsync(uri.Host, content, T("Allow", "允许"), secondary: T("Block", "阻止"));
            var closePrompt = overlayClose;
            using var cancelled = view.Lifetime.Register(() => DispatcherQueue.TryEnqueue(() => { if (overlayClose == closePrompt) closePrompt?.Invoke(); }));
            var result = await pending;
            if (closing || view.IsDisposed || tab.Url != document || result == ContentDialogResult.None) return;
            var origin = uri.GetLeftPart(UriPartial.Authority);
            args.State = result == ContentDialogResult.Primary ? CoreWebView2PermissionState.Allow : CoreWebView2PermissionState.Deny;
            if (tab.IsPrivate)
                await view.Control.CoreWebView2.Profile.SetPermissionStateAsync(args.PermissionKind, origin, args.State);
            else
            {
                GetSite(origin).Permissions[args.PermissionKind.ToString()] = result == ContentDialogResult.Primary ? "allow" : "deny";
                ScheduleSave();
            }
        }
        catch (OperationCanceledException) when (view.IsDisposed) { }
        finally { if (entered) permissionGate.Release(); }
    }
}
