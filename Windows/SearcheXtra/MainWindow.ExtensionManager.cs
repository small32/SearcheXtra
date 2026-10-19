using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private async Task ShowExtensionManagerAsync()
    {
        var confirmations = new List<TaskCompletionSource<bool>>();
        var managerOpen = true;
        var body = new Grid { Width = Math.Min(880, Math.Max(280, Root.ActualWidth - 100)), Height = Math.Min(520, Math.Max(200, Root.ActualHeight - 160)), RowSpacing = 18 };
        body.RowDefinitions.Add(new() { Height = GridLength.Auto }); body.RowDefinitions.Add(new() { Height = new(1, GridUnitType.Star) });
        var search = new TextBox { PlaceholderText = T("Search extensions", "搜索扩展"), Padding = new(12, 8, 12, 8), CornerRadius = new(8) };
        body.Children.Add(search);
        var cards = new Grid { RowSpacing = 16, ColumnSpacing = 16, VerticalAlignment = VerticalAlignment.Top };
        var scroll = new ScrollViewer { Content = cards, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }; Grid.SetRow(scroll, 1); body.Children.Add(scroll);
        void Render()
        {
            cards.Children.Clear(); cards.RowDefinitions.Clear(); cards.ColumnDefinitions.Clear();
            var columns = body.Width >= 640 ? 2 : 1;
            for (var i = 0; i < columns; i++) cards.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });
            var items = Settings.Extensions.Where(e => e.Name.Contains(search.Text.Trim(), StringComparison.CurrentCultureIgnoreCase)).ToArray();
            if (items.Length == 0) cards.Children.Add(new TextBlock { Text = T("No extensions found", "没有找到扩展"), Opacity = .65, Margin = new(0, 20, 0, 0) });
            for (var index = 0; index < items.Length; index++)
            {
                var item = items[index];
                if (index % columns == 0) cards.RowDefinitions.Add(new() { Height = GridLength.Auto });
                var content = new StackPanel { Spacing = 18, Padding = new(16) };
                var header = new Grid { ColumnSpacing = 14 }; header.ColumnDefinitions.Add(new() { Width = new(32) }); header.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });
                if (ExtensionIconPath(item) is { } icon) header.Children.Add(new Image { Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(icon)), Width = 32, Height = 32 });
                else header.Children.Add(new TextBlock { Text = item.Name.Length > 0 ? item.Name[..1] : "◇", FontSize = 24, VerticalAlignment = VerticalAlignment.Center });
                var words = new StackPanel { Spacing = 4 };
                words.Children.Add(new TextBlock { Text = item.Name, FontSize = 14, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
                var version = new TextBlock { Text = T("Version ", "版本 ") + item.Version, FontSize = 12, Opacity = .6 };
                words.Children.Add(version); Grid.SetColumn(words, 1); header.Children.Add(words); content.Children.Add(header);
                var actions = new Grid(); actions.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) }); actions.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
                var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                var detailsButton = QuietButton(T("Details", "详情")); var remove = QuietButton(T("Remove", "移除")); buttons.Children.Add(detailsButton); buttons.Children.Add(remove); actions.Children.Add(buttons);
                var toggle = new ToggleSwitch { IsOn = item.Enabled, OnContent = "", OffContent = "", Width = 40, MinWidth = 40, VerticalAlignment = VerticalAlignment.Center, Tag = item.Id };
                Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(toggle, T("Enable ", "启用 ") + item.Name);
                Grid.SetColumn(toggle, 1); actions.Children.Add(toggle); content.Children.Add(actions);
                var status = new TextBlock { FontSize = 12, Opacity = .65, TextWrapping = TextWrapping.Wrap, Text = item.Enabled ? T("Enabled", "已启用") : T("Disabled", "已停用") }; content.Children.Add(status);
                var details = new StackPanel { Spacing = 10, Visibility = Visibility.Collapsed };
                if (ExtensionPermissions.DeclaresUserScripts(item.Folder))
                {
                    if (ExtensionUserScripts.Failed(item.Id)) status.Text = T("Could not load this extension's user-script configuration. Its data has been preserved.", "无法加载此扩展的用户脚本配置，原有数据已保留。");
                    var userScripts = new ToggleSwitch { Header = T("Allow user scripts", "允许用户脚本"), IsOn = item.AllowUserScripts, OnContent = "", OffContent = "" };
                    Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(userScripts, T("Allow user scripts", "允许用户脚本"));
                    details.Children.Add(userScripts);
                    details.Children.Add(new TextBlock { Text = T("Allow this extension to run user scripts on websites. Changing this setting reloads the extension. Refresh open webpages to apply it.", "允许此扩展在网站上运行用户脚本。更改后会重新加载扩展，请刷新已打开的网页使其生效。"), FontSize = 12, Opacity = .65, TextWrapping = TextWrapping.Wrap });
                    var changingScripts = false;
                    userScripts.Toggled += async (_, _) =>
                    {
                        if (changingScripts) return;
                        changingScripts = true; userScripts.IsEnabled = toggle.IsEnabled = false;
                        var previous = item.AllowUserScripts;
                        try { await SetUserScriptsAllowedAsync(item, userScripts.IsOn); status.Text = T("User-script permission updated. Refresh open webpages.", "用户脚本权限已更新，请刷新已打开的网页。"); }
                        catch { item.AllowUserScripts = previous; userScripts.IsOn = previous; ScheduleSave(); status.Text = T("Could not change user-script permission. Try again.", "无法更改用户脚本权限，请重试。"); }
                        finally { changingScripts = false; userScripts.IsEnabled = toggle.IsEnabled = true; }
                    };
                }
                var pin = new CheckBox { Content = T("Pin to title bar", "固定到标题栏"), IsChecked = item.Pinned };
                pin.Checked += (_, _) => SetExtensionPinned(item, true); pin.Unchecked += (_, _) => SetExtensionPinned(item, false); details.Children.Add(pin);
                var open = QuietButton(T("Open extension", "打开扩展")); open.HorizontalAlignment = HorizontalAlignment.Left;
                open.Click += async (_, _) => { DismissOverlay(); await OpenExtensionPopupAsync(item); }; details.Children.Add(open);
                if (item.Options.Length > 0)
                {
                    var options = QuietButton(T("Extension options", "扩展选项")); options.HorizontalAlignment = HorizontalAlignment.Left;
                    options.Click += (_, _) => { DismissOverlay(); AddTab($"chrome-extension://{item.Id}/{item.Options}"); }; details.Children.Add(options);
                }
                if (item.StoreId != null)
                {
                    var update = QuietButton(T("Update from store", "从商店更新")); update.HorizontalAlignment = HorizontalAlignment.Left;
                    update.Click += async (_, _) =>
                    {
                        if (extensionBusy) return;
                        update.IsEnabled = search.IsEnabled = remove.IsEnabled = toggle.IsEnabled = detailsButton.IsEnabled = false;
                        try
                        {
                            await InstallStoreExtensionAsync(item.StoreId, message => status.Text = message, async permissions =>
                            {
                                if (!managerOpen) return false;
                                var done = new TaskCompletionSource<bool>(); confirmations.Add(done);
                                var consent = new StackPanel { Spacing = 8 };
                                foreach (var permission in permissions) consent.Children.Add(new TextBlock { Text = "• " + permission, TextWrapping = TextWrapping.Wrap });
                                var consentButtons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                                var accept = QuietButton(T("Update", "更新")); var cancel = QuietButton(T("Cancel", "取消"));
                                accept.Click += (_, _) => done.TrySetResult(true); cancel.Click += (_, _) => done.TrySetResult(false);
                                consentButtons.Children.Add(accept); consentButtons.Children.Add(cancel); consent.Children.Add(consentButtons); details.Children.Add(consent);
                                try { return await done.Task; }
                                finally { details.Children.Remove(consent); confirmations.Remove(done); }
                            });
                            version.Text = T("Version ", "版本 ") + item.Version;
                        }
                        finally { update.IsEnabled = search.IsEnabled = remove.IsEnabled = toggle.IsEnabled = detailsButton.IsEnabled = true; }
                    }; details.Children.Add(update);
                }
                content.Children.Add(details);
                detailsButton.Click += (_, _) => details.Visibility = details.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
                var changing = false;
                toggle.Toggled += async (_, _) =>
                {
                    if (changing) return; changing = true; toggle.IsEnabled = false;
                    try { await SetExtensionEnabledAsync(item, toggle.IsOn); status.Text = item.Enabled ? T("Enabled", "已启用") : T("Disabled", "已停用"); }
                    catch { toggle.IsOn = item.Enabled; status.Text = T("Could not change extension state. Try again.", "无法更改扩展状态，请重试。"); }
                    finally { changing = false; toggle.IsEnabled = true; }
                };
                remove.Click += async (_, _) =>
                {
                    remove.IsEnabled = false;
                    try { await RemoveExtensionAsync(item); Render(); }
                    catch { status.Text = T("Could not remove extension. Try again.", "无法移除扩展，请重试。"); remove.IsEnabled = true; }
                };
                var card = new Border { Tag = item.Id, CornerRadius = new(12), BorderBrush = Brush("Hairline"), BorderThickness = new(1), Background = Brush("Wash", .35), Child = content, VerticalAlignment = VerticalAlignment.Top };
                Grid.SetRow(card, index / columns); Grid.SetColumn(card, index % columns); cards.Children.Add(card);
            }
        }
        search.TextChanged += (_, _) => Render(); Render();
        try { await ShowCardAsync(T("Manage extensions", "扩展管理"), body, fitWindow: true); }
        finally { managerOpen = false; foreach (var confirmation in confirmations.ToArray()) confirmation.TrySetResult(false); }
    }
}
