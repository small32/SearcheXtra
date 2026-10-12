using System.Text.Json;

namespace SearcheXtra.Windows;

public sealed partial class PageView
{
    private readonly string superDragToken = Guid.NewGuid().ToString("N");
    private static readonly Lazy<string> superDragSource = new(() => File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"Assets","SuperDrag.js")));
    public event Func<SuperDragRequest, Task>? SuperDragRequested;
    public event Action? SuperDragSettingsRequested;
    private void AddSuperDragContextMenu(Microsoft.Web.WebView2.Core.CoreWebView2 core,Microsoft.Web.WebView2.Core.CoreWebView2ContextMenuRequestedEventArgs args)
    {
        if (!AddressParser.IsWeb(core.Source)) return;
        var labels=new Strings(store.Settings);
        var menu=core.Environment.CreateContextMenuItem(labels.Key("superDrag.title"),null,Microsoft.Web.WebView2.Core.CoreWebView2ContextMenuItemKind.Submenu);
        var enabled=core.Environment.CreateContextMenuItem(labels.Key("superDrag.enabled"),null,Microsoft.Web.WebView2.Core.CoreWebView2ContextMenuItemKind.CheckBox);
        enabled.IsChecked=store.Settings.SuperDrag.Enabled;
        enabled.CustomItemSelected+=(_,_)=>{store.Settings.SuperDrag.Enabled=!store.Settings.SuperDrag.Enabled;store.Notify();changed();};menu.Children.Add(enabled);
        var exclude=core.Environment.CreateContextMenuItem(labels.Key("superDrag.exceptSite"),null,Microsoft.Web.WebView2.Core.CoreWebView2ContextMenuItemKind.Command);
        exclude.CustomItemSelected+=(_,_)=>{var host=new Uri(core.Source).Host;if(!store.Settings.SuperDrag.Exceptions.Contains(host))store.Settings.SuperDrag.Exceptions.Add(host);store.Notify();changed();};menu.Children.Add(exclude);
        var settings=core.Environment.CreateContextMenuItem(labels.Key("superDrag.settings"),null,Microsoft.Web.WebView2.Core.CoreWebView2ContextMenuItemKind.Command);
        settings.CustomItemSelected+=(_,_)=>SuperDragSettingsRequested?.Invoke();menu.Children.Add(settings);
        var rules=core.Environment.CreateContextMenuItem(labels.Key("superDrag.rules"),null,Microsoft.Web.WebView2.Core.CoreWebView2ContextMenuItemKind.Submenu);
        foreach(var rule in store.Settings.SuperDrag.Rules) {var item=core.Environment.CreateContextMenuItem(labels.Key("superDrag."+rule.Object)+" · "+labels.Key("superDrag."+rule.Direction)+" → "+labels.Key("superDrag."+rule.Action),null,Microsoft.Web.WebView2.Core.CoreWebView2ContextMenuItemKind.Command);item.IsEnabled=false;rules.Children.Add(item);}menu.Children.Add(rules);
        args.MenuItems.Add(menu);
    }
    internal SuperDragRequest? PendingSuperDrag { get; private set; }
    private DateTimeOffset superDragStarted;
    private string SuperDragOptions() => JsonSerializer.Serialize(new { config = store.Settings.SuperDrag, labels = SuperDragLabels() },SuperDrag.Json);
    private Dictionary<string,string> SuperDragLabels()
    {
        var strings = new Strings(store.Settings);
        return SuperDrag.Actions.Concat(SuperDrag.Directions).ToDictionary(k => k,k => strings.Key("superDrag."+k));
    }
    private string SuperDragScript() => "(()=>{" + superDragSource.Value + ";const post=window.chrome.webview.postMessage.bind(window.chrome.webview);sxInstallSuperDrag(" + SuperDragOptions() + ",p=>post({...p,type:'super-drag',token:"+JsonSerializer.Serialize(superDragToken)+"}));})();";
    private async Task ReceiveSuperDragAsync(JsonElement data)
    {
        if (data.GetProperty("token").GetString() != superDragToken || disposed) return;
        var request = data.Deserialize<SuperDragRequest>(SuperDrag.Json);
        if (request == null) return;
        if (request.Phase == "cancel") { PendingSuperDrag = null; return; }
        if (request.Phase == "start") {
            if (SuperDrag.EnabledOn(store.Settings.SuperDrag,tab.Url) && request.Value.Length is > 0 and <= 32768 && SuperDrag.Objects.Contains(request.Object)) { PendingSuperDrag = request; superDragStarted = DateTimeOffset.UtcNow; }
            return;
        }
        if (request.Phase != "finish" || !MatchesPending(request)) return;
        PendingSuperDrag = null;
        if (SuperDragRequested != null) await SuperDragRequested(request);
    }
    internal bool MatchesPending(SuperDragRequest request) => PendingSuperDrag is { } pending && request.Value == pending.Value && request.Object == pending.Object && DateTimeOffset.UtcNow - superDragStarted < TimeSpan.FromMinutes(2);
    internal SuperDragRequest? TakeChromeDrop(string region, double screenX, double screenY)
    {
        if (PendingSuperDrag is not { } pending || !MatchesPending(pending)) return null;
        PendingSuperDrag = null;
        return pending with { Phase = "finish",Region = region,Dx = screenX - pending.ScreenX,Dy = screenY - pending.ScreenY,ScreenX = screenX,ScreenY = screenY };
    }
}
