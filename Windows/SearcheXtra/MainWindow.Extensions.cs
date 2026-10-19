using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using System.Text.Json;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private bool extensionBusy;
    private string ExtensionInstallError(Exception error) => error switch
    {
        HttpRequestException or OperationCanceledException => T("Could not download the extension. Check your connection and try again.", "扩展下载失败，请检查网络连接后重试。"),
        InvalidDataException or JsonException or System.Security.Cryptography.CryptographicException => T("The extension package is invalid or could not be verified. Choose a valid CRX or ZIP package.", "扩展包无效或无法通过校验，请选择有效的 CRX 或 ZIP 扩展包。"),
        IOException or UnauthorizedAccessException => T("Could not read or save the extension files. Check the file location and access permissions.", "无法读取或保存扩展文件，请检查文件位置和访问权限。"),
        _ => T("Could not install the extension. Check that it is compatible with this WebView2 Runtime and try again.", "扩展安装失败，请检查扩展与当前 WebView2 Runtime 的兼容性后重试。")
    };
    private async Task<CoreWebView2Profile> CurrentProfileAsync()
    {
        if (active == null) throw new InvalidOperationException("No active tab.");
        return (await GetViewAsync(active)).Control.CoreWebView2.Profile;
    }
    private async Task InstallStoreExtensionAsync(string text, Action<string>? progress = null, Func<IReadOnlyList<string>, Task<bool>>? confirmUpdate = null)
    {
        var id = CrxInstaller.Id(text);
        if (id == null || extensionBusy) return;
        extensionBusy = true;
        try
        {
            var installed = Settings.Extensions.FirstOrDefault(e => e.StoreId == id);
            async Task Latest()
            {
                if (progress != null) { progress(T("Already up to date", "已是最新版本")); return; }
                DismissOverlay();
                await ShowCardAsync(T("Already up to date", "已是最新版本"), new TextBlock { Text = installed!.Name + " · " + installed.Version, TextWrapping = TextWrapping.Wrap });
            }
            if (installed != null)
            {
                Status.Text = T("Checking extension updates…", "正在检查扩展更新…");
                progress?.Invoke(Status.Text);
                if (await CrxInstaller.CheckUpdateAsync(id, installed.Version) == null) { await Latest(); return; }
            }
            Status.Text = T("Downloading and verifying extension…", "正在下载并校验扩展…");
            progress?.Invoke(Status.Text);
            var folder = await CrxInstaller.FetchAsync(id, Path.Combine(DataStore.Root, "Extensions"));
            using var doc = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(folder, "manifest.json")));
            if (installed != null && !CrxInstaller.IsNewerVersion(doc.RootElement.GetProperty("version").GetString()!, installed.Version))
            {
                Directory.Delete(folder, true); await Latest(); return;
            }
            var permissions = ExtensionPermissions.Describe(doc.RootElement, strings.Chinese);
            if (confirmUpdate != null)
            {
                progress?.Invoke(T("Confirm update permissions", "请确认更新所需权限"));
                if (!await confirmUpdate(permissions)) { progress?.Invoke(T("Update cancelled", "已取消更新")); return; }
            }
            else
            {
                DismissOverlay();
                var explanation = new StackPanel { Spacing = 10, MaxWidth = 440 };
                explanation.Children.Add(new TextBlock { Text = T("This extension will be able to:", "安装后，此扩展可以："), TextWrapping = TextWrapping.Wrap });
                foreach (var permission in permissions)
                    explanation.Children.Add(new TextBlock { Text = "• " + permission, TextWrapping = TextWrapping.Wrap });
                if (permissions.Count == 0) explanation.Children.Add(new TextBlock { Text = T("No additional permissions requested.", "无需额外权限。"), TextWrapping = TextWrapping.Wrap });
                var content = new ScrollViewer { Content = explanation, MaxHeight = 340, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
                if (await ShowCardAsync(T("Install extension", "安装扩展"), content, T("Install", "安装")) != ContentDialogResult.Primary) return;
            }
            progress?.Invoke(T("Updating extension…", "正在更新扩展…"));
            await InstallExtensionFolderAsync(folder, id);
            progress?.Invoke(T("Updated to version ", "已更新至版本 ") + Settings.Extensions.First(e => e.StoreId == id).Version);
        }
        catch (Exception ex) { if (progress != null) progress(T("Could not check or install the update. Try again.", "检查或安装更新失败，请重试。")); else Status.Text = ExtensionInstallError(ex); }
        finally { extensionBusy = false; }
    }
    private async Task InstallExtensionFolderAsync(string folder, string? storeId = null)
    {
        try { folder = await Task.Run(() => CrxInstaller.ValidateFolder(folder)); }
        catch (InvalidDataException) { throw new InvalidDataException(T("The extension folder contains a link to files outside its package.", "扩展目录包含指向扩展包外文件的链接，无法安装。")); }
        using var doc = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(folder, "manifest.json")));
        var manifest = doc.RootElement;
        var manifestVersion = manifest.GetProperty("manifest_version").GetInt32();
        if (manifestVersion is not (2 or 3)) throw new InvalidDataException(T("Only Manifest V2 and V3 extensions are supported.", "仅支持 Manifest V2 和 V3 扩展。"));
        var regular = active?.IsPrivate == true ? tabs.FirstOrDefault(tab => !tab.IsPrivate && tab.Space == space) ?? AddTab("", false) : active;
        if (regular == null) return;
        var profile = (await GetViewAsync(regular)).Control.CoreWebView2.Profile;
        var userScriptPackage = await ExtensionUserScripts.PrepareAsync(folder, reload: true);
        CoreWebView2BrowserExtension native;
        try { native = await profile.AddBrowserExtensionAsync(folder); }
        catch (Exception ex)
        {
            if (storeId != null && Settings.Extensions.FirstOrDefault(e => e.StoreId == storeId) is { } restore && Directory.Exists(restore.Folder)) { var restored = await profile.AddBrowserExtensionAsync(restore.Folder); await restored.EnableAsync(restore.Enabled); }
            if (manifestVersion == 2 && ex is System.Runtime.InteropServices.COMException) throw new InvalidOperationException(T("This WebView2 Runtime rejected the MV2 extension. ", "当前 WebView2 Runtime 拒绝加载此 MV2 扩展。") + "Runtime: " + ActiveView?.Control.CoreWebView2.Environment.BrowserVersionString, ex);
            throw;
        }
        var item = Settings.Extensions.FirstOrDefault(e => e.Id == native.Id) ?? new InstalledExtension();
        if (item.Folder.Length > 0 && item.Folder != folder) Settings.ExtensionFolders.Remove(item.Folder);
        await native.EnableAsync(item.Enabled);
        Settings.RemovedExtensionIds.Remove(native.Id);
        item.ManifestVersion = manifestVersion;
        item.Id = native.Id; item.Name = native.Name; item.Folder = Path.GetFullPath(folder); item.StoreId = storeId;
        item.Version = manifest.GetProperty("version").GetString() ?? "";
        item.Popup = item.Options = item.NewTab = "";
        if (manifest.TryGetProperty("action", out var action) || manifest.TryGetProperty("browser_action", out action) || manifest.TryGetProperty("page_action", out action))
            if (action.TryGetProperty("default_popup", out var popup)) item.Popup = popup.GetString() ?? "";
        if (manifest.TryGetProperty("options_ui", out var options)) item.Options = options.GetProperty("page").GetString() ?? "";
        else if (manifest.TryGetProperty("options_page", out options)) item.Options = options.GetString() ?? "";
        if (manifest.TryGetProperty("chrome_url_overrides", out var overrides) && overrides.TryGetProperty("newtab", out var newtab)) item.NewTab = newtab.GetString() ?? "";
        if (!Settings.Extensions.Contains(item)) Settings.Extensions.Add(item);
        if (!Settings.ExtensionFolders.Contains(item.Folder)) Settings.ExtensionFolders.Add(item.Folder);
        var profileKey = profile.ProfileName + ":regular";
        if (!Settings.ProfileExtensionFolders.TryGetValue(profileKey, out var recorded)) Settings.ProfileExtensionFolders[profileKey] = recorded = [];
        recorded[item.Id] = item.Folder + (userScriptPackage ? "|userScripts:" + ExtensionUserScriptsPackage.Version : "");
        foreach (var loadedProfile in App.Windows.SelectMany(window => window.views.Values).Where(view => view.Control.CoreWebView2 != null).Select(view => view.Control.CoreWebView2.Profile).DistinctBy(p => (p.ProfileName, p.IsInPrivateModeEnabled)))
            if (!loadedProfile.IsInPrivateModeEnabled || PageView.SupportsPrivateExtensions && Settings.ExtensionsInPrivate) await PageView.SynchronizeExtensionsAsync(loadedProfile, Settings);
        foreach (var loadedView in App.Windows.SelectMany(window => window.views.Values).Where(view => view.Control.CoreWebView2 != null && !view.Control.CoreWebView2.Profile.IsInPrivateModeEnabled).DistinctBy(view => view.Control.CoreWebView2.Profile.ProfileName))
            await ExtensionUserScripts.EnsureAsync(loadedView.Control.CoreWebView2, Settings);
        Status.Text = T("Installed: ", "已安装：") + item.Name; store.Notify(); ScheduleSave();
    }
    private async Task SetExtensionEnabledAsync(InstalledExtension item, bool enabled)
    {
        var current = await CurrentProfileAsync();
        foreach (var profile in App.Windows.SelectMany(window => window.views.Values).Where(v => v.Control.CoreWebView2 != null).Select(v => v.Control.CoreWebView2.Profile).Append(current).DistinctBy(p => (p.ProfileName, p.IsInPrivateModeEnabled)))
        {
            var native = (await profile.GetBrowserExtensionsAsync()).FirstOrDefault(e => e.Id == item.Id);
            if (native != null) await native.EnableAsync(enabled);
        }
        item.Enabled = enabled; RefreshPinnedExtensions(); ScheduleSave();
        await ExtensionUserScripts.SynchronizeAsync();
    }
    private async Task SetUserScriptsAllowedAsync(InstalledExtension item, bool allowed)
    {
        var prefix = $"chrome-extension://{item.Id}/";
        var openPages = App.Windows.SelectMany(window => window.views.Values).Where(view => !view.IsDisposed && view.Control.CoreWebView2?.Source.StartsWith(prefix, StringComparison.Ordinal) == true)
            .Select(view => (View: view, Address: view.Control.CoreWebView2.Source)).ToArray();
        item.AllowUserScripts = allowed; ScheduleSave();
        await ExtensionUserScripts.RestartAsync(item.Id, Settings);
        if (allowed && ExtensionUserScripts.Failed(item.Id)) throw new InvalidOperationException("The extension's user-script configuration could not be loaded.");
        foreach (var (view, address) in openPages)
        {
            if (view.IsDisposed) continue;
            var core = view.Control.CoreWebView2;
            var ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            void Loaded(CoreWebView2 sender, CoreWebView2NavigationCompletedEventArgs args) { if (args.IsSuccess) ready.TrySetResult(); }
            core.NavigationCompleted += Loaded;
            try { core.Navigate(address); await ready.Task.WaitAsync(TimeSpan.FromSeconds(20)); }
            catch (Exception error) when (error is TimeoutException or System.Runtime.InteropServices.COMException) { System.Diagnostics.Debug.WriteLine(error.Message); }
            finally { core.NavigationCompleted -= Loaded; }
        }
    }
    private async Task RemoveExtensionAsync(InstalledExtension item)
    {
        var wasEnabled = item.Enabled;
        item.Enabled = false;
        try
        {
            await ExtensionUserScripts.RemovedAsync(item.Id, Settings, async () =>
            {
                // Extensions are per WebView2 profile, including every space currently open.
                foreach (var profile in App.Windows.SelectMany(window => window.views.Values).Where(v => v.Control.CoreWebView2 != null).Select(v => v.Control.CoreWebView2.Profile).DistinctBy(p => (p.ProfileName, p.IsInPrivateModeEnabled)).ToArray())
                {
                    var native = (await profile.GetBrowserExtensionsAsync()).FirstOrDefault(e => e.Id == item.Id);
                    if (native != null) await native.RemoveAsync();
                }
            });
        }
        catch { item.Enabled = wasEnabled; await ExtensionUserScripts.SynchronizeAsync(); throw; }
        if (!Settings.RemovedExtensionIds.Contains(item.Id)) Settings.RemovedExtensionIds.Add(item.Id);
        Settings.Extensions.Remove(item); Settings.ExtensionFolders.Remove(item.Folder); ScheduleSave(); store.Notify();
    }
    private async Task ChooseExtensionFolderAsync()
    {
        var picker = new FolderPicker(); picker.FileTypeFilter.Add("*"); InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        var folder = await picker.PickSingleFolderAsync(); if (folder == null) return;
        try { await InstallExtensionFolderAsync(folder.Path); }
        catch (Exception ex) { Status.Text = ExtensionInstallError(ex); }
    }
    private async Task ChooseExtensionPackageAsync()
    {
        var picker = new FileOpenPicker(); picker.FileTypeFilter.Add(".crx"); picker.FileTypeFilter.Add(".zip"); InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        var file = await picker.PickSingleFileAsync(); if (file == null) return;
        try { var folder = await CrxInstaller.ImportAsync(file.Path, Path.Combine(DataStore.Root, "Extensions")); await InstallExtensionFolderAsync(folder); }
        catch (Exception ex) { Status.Text = ExtensionInstallError(ex); }
    }
    private async Task OpenExtensionPopupAsync(InstalledExtension item)
    {
        if (!item.Enabled) return;
        if (active?.IsPrivate == true && !PageView.SupportsPrivateExtensions) { Status.Text = T("Extensions are unavailable in private tabs on Windows.", "Windows 的无痕标签页暂不支持扩展。"); return; }
        if (item.Popup.Length == 0) { if (item.Options.Length > 0) AddTab($"chrome-extension://{item.Id}/{item.Options}"); return; }
        DismissOverlay();
        var view = new WebView2 { Width = 360, Height = 480 };
        var source = ActiveView?.Control.CoreWebView2;
        if (source == null) return;
        await ShowExtensionCardAsync(view, source, item);
    }
    private async Task ShowExtensionCardAsync(WebView2 view, CoreWebView2 source, InstalledExtension item)
    {
        double width = 360, height = 480;
        void Resize()
        {
            view.Width = Math.Min(width, Math.Max(120, Root.ActualWidth - 80));
            view.Height = Math.Min(height, Math.Max(80, Root.ActualHeight - 140));
            if (view.Parent is Grid panel) { panel.Width = view.Width + 44; panel.MaxHeight = Math.Max(120, Root.ActualHeight - 32); }
        }
        void WindowResized(object sender, SizeChangedEventArgs args) => Resize();
        Resize();
        var pending = ShowCardAsync(item.Name, view, fitWindow: true);
        void PopupResized(CoreWebView2 sender, CoreWebView2WebMessageReceivedEventArgs args)
        {
            if (args.Source != sender.Source || !args.Source.StartsWith($"chrome-extension://{item.Id}/", StringComparison.Ordinal)) return;
            try
            {
                using var doc = JsonDocument.Parse(args.WebMessageAsJson);
                if (!doc.RootElement.TryGetProperty("type", out var type) || type.GetString() != "popup-size") return;
                var requestedWidth = doc.RootElement.GetProperty("width").GetDouble();
                var requestedHeight = doc.RootElement.GetProperty("height").GetDouble();
                if (!double.IsFinite(requestedWidth) || !double.IsFinite(requestedHeight)) return;
                width = Math.Clamp(requestedWidth, 160, 800); height = Math.Clamp(requestedHeight, 100, 800); Resize();
            }
            catch (JsonException) { }
        }
        Root.SizeChanged += WindowResized;
        try
        {
            var options = source.Environment.CreateCoreWebView2ControllerOptions(); options.ProfileName = source.Profile.ProfileName; options.IsInPrivateModeEnabled = source.Profile.IsInPrivateModeEnabled;
            await view.EnsureCoreWebView2Async(source.Environment, options);
            view.CoreWebView2.WebMessageReceived += PopupResized;
            await view.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync("""
                (()=>{
                  if(window!==top)return;
                  let queued=false,last='';
                  const measure=()=>{
                    queued=false;const body=document.body;if(!body)return;
                    const width=Math.ceil(Math.max(body.scrollWidth,body.getBoundingClientRect().width,document.documentElement.scrollWidth));
                    const height=Math.ceil(Math.max(body.scrollHeight,body.getBoundingClientRect().height));
                    const size=width+','+height;if(size===last)return;last=size;
                    chrome.webview.postMessage({type:'popup-size',width,height});
                  };
                  const queue=()=>{if(!queued){queued=true;requestAnimationFrame(measure);}};
                  document.addEventListener('DOMContentLoaded',()=>{new ResizeObserver(queue).observe(document.body);new MutationObserver(queue).observe(document.body,{childList:true,subtree:true,attributes:true});queue();},{once:true});
                  window.addEventListener('load',queue);
                })();
                """);
            view.CoreWebView2.Navigate($"chrome-extension://{item.Id}/{item.Popup}");
            await pending;
        }
        finally { Root.SizeChanged -= WindowResized; if (view.CoreWebView2 is { } core) core.WebMessageReceived -= PopupResized; view.Close(); }
    }
    private void RefreshPinnedExtensions()
    {
        PinnedExtensions.Children.Clear();
        foreach (var item in Settings.Extensions.Where(e => e.Enabled && e.Pinned))
        {
            var button = QuietButton(item.Name.Length > 0 ? item.Name[..1] : "◇"); ToolTipService.SetToolTip(button, item.Name);
            if (ExtensionIconPath(item) is { } path)
                button.Content = new Image { Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(path)), Width = 16, Height = 16 };
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, item.Name);
            var menu = new MenuFlyout();
            AddMenu(menu, T("Unpin from title bar", "从标题栏取消固定"), () => SetExtensionPinned(item, false));
            button.ContextFlyout = menu;
            button.Click += async (_, _) => await OpenExtensionPopupAsync(item); PinnedExtensions.Children.Add(button);
        }
        DownloadsButton.Visibility = Settings.AlwaysShowsDownloads || downloads.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
    }
    private void SetExtensionPinned(InstalledExtension item, bool pinned)
    {
        item.Pinned = pinned; RefreshPinnedExtensions(); store.Notify(); ScheduleSave();
    }
    private static string? ExtensionIconPath(InstalledExtension item)
    {
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(item.Folder, "manifest.json")));
            var manifest = doc.RootElement;
            JsonElement icon = default;
            var hasActionIcon = (manifest.TryGetProperty("action", out var action) || manifest.TryGetProperty("browser_action", out action) || manifest.TryGetProperty("page_action", out action)) && action.TryGetProperty("default_icon", out icon);
            if (!hasActionIcon && !manifest.TryGetProperty("icons", out icon)) return null;
            var relative = icon.ValueKind == JsonValueKind.String ? icon.GetString() :
                icon.ValueKind == JsonValueKind.Object ? icon.EnumerateObject().Where(p => int.TryParse(p.Name, out var size) && size > 0 && p.Value.ValueKind == JsonValueKind.String)
                    .OrderBy(p => Math.Abs(int.Parse(p.Name) - 32)).Select(p => p.Value.GetString()).FirstOrDefault() : null;
            if (string.IsNullOrWhiteSpace(relative)) return null;
            var folder = Path.GetFullPath(item.Folder) + Path.DirectorySeparatorChar;
            var path = Path.GetFullPath(Path.Combine(folder, relative));
            return path.StartsWith(folder, StringComparison.OrdinalIgnoreCase) && File.Exists(path) ? path : null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException or ArgumentException) { return null; }
    }
    private async void Downloads_Click(object sender, RoutedEventArgs e) => await ShowDownloadsAsync();
    private void Extensions_Click(object sender, RoutedEventArgs e) => ExtensionsMenu();
    private void ExtensionsMenu()
    {
        var menu = new MenuFlyout();
        foreach (var item in Settings.Extensions.Where(e => e.Enabled))
        {
            var entry = new MenuFlyoutSubItem { Text = item.Name };
            var open = new MenuFlyoutItem { Text = T("Open extension", "打开扩展"), IsEnabled = active?.IsPrivate != true || PageView.SupportsPrivateExtensions };
            open.Click += async (_, _) => await OpenExtensionPopupAsync(item);
            entry.Items.Add(open);
            if (item.Options.Length > 0)
            {
                var settings = new MenuFlyoutItem { Text = T("Extension settings", "扩展设置"), IsEnabled = active?.IsPrivate != true || PageView.SupportsPrivateExtensions };
                settings.Click += (_, _) => AddTab($"chrome-extension://{item.Id}/{item.Options}");
                entry.Items.Add(settings);
            }
            var pin = new ToggleMenuFlyoutItem { Text = T("Pin to title bar", "固定到标题栏"), IsChecked = item.Pinned };
            pin.Click += (_, _) => SetExtensionPinned(item, pin.IsChecked);
            entry.Items.Add(pin); menu.Items.Add(entry);
        }
        AddMenu(menu, T("Manage extensions", "扩展管理"), async () => await ShowExtensionManagerAsync());
        menu.Placement = Microsoft.UI.Xaml.Controls.Primitives.FlyoutPlacementMode.BottomEdgeAlignedRight;
        menu.ShowAt(ExtensionsButton);
    }
}
