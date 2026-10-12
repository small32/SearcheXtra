using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System.Runtime.InteropServices;
using System.Text.Json;
using Windows.ApplicationModel.DataTransfer;
using WinRT.Interop;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private readonly List<object> superDragDiagnostics = [];
    private bool superDragZonesReady;
    [StructLayout(LayoutKind.Sequential)] private struct SuperDragScreenPoint { public int X,Y; }
    [DllImport("user32.dll",EntryPoint="ClientToScreen")] private static extern bool SuperDragClientToScreen(nint window,ref SuperDragScreenPoint point);
    private void SetupSuperDragDropZones()
    {
        if (superDragZonesReady) return;
        superDragZonesReady=true;
        foreach (var (element,region) in new[] { ((UIElement)TopTabs,"tabs"), (SideTabs,"tabs"), (BookmarkRow,"bookmarks"), (Address,"address") }) {
            element.AllowDrop = true;
            string? addressBeforeDrag=null;
            element.AddHandler(UIElement.DragOverEvent,new DragEventHandler((_,e) => {
                if (active != null && views.TryGetValue(active.Id,out var view) && view.PendingSuperDrag != null && SuperDrag.EnabledOn(Settings.SuperDrag,active.Url)) {
                    e.AcceptedOperation = DataPackageOperation.Copy;
                    if(region=="address")addressBeforeDrag??=Address.Text;
                }
            }),true);
            element.AddHandler(UIElement.DropEvent,new DragEventHandler(async (_,e) => {
                if (active is not { } tab || !views.TryGetValue(tab.Id,out var view) || view.PendingSuperDrag == null) return;
                var position = e.GetPosition(Root); var scale = Root.XamlRoot.RasterizationScale;
                var point = new SuperDragScreenPoint { X=(int)(position.X*scale),Y=(int)(position.Y*scale) };
                SuperDragClientToScreen(WindowNative.GetWindowHandle(this),ref point);
                var request = view.TakeChromeDrop(region,point.X/scale,point.Y/scale);
                if (request != null) {
                    var keys=new[]{("ctrl",global::Windows.System.VirtualKey.Control),("alt",global::Windows.System.VirtualKey.Menu),("shift",global::Windows.System.VirtualKey.Shift),("meta",global::Windows.System.VirtualKey.LeftWindows)};
                    var modifiers=string.Join("+",keys.Where(k=>Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(k.Item2).HasFlag(global::Windows.UI.Core.CoreVirtualKeyStates.Down)).Select(k=>k.Item1));
                    request=request with {Modifier=modifiers.Length==0 ? "none":modifiers};
                    if(region=="address" && request.Object=="text" && SuperDrag.Resolve(Settings.SuperDrag,request with {Region="search"},tab.Url)!=null) request=request with {Region="search"};
                }
                if (request != null && SuperDrag.Resolve(Settings.SuperDrag,request,tab.Url) != null) {
                    e.Handled = true;
                    if(region=="address" && addressBeforeDrag!=null)Address.Text=addressBeforeDrag;
                    await ExecuteSuperDragAsync(tab,view,request);
                }
                addressBeforeDrag=null;
            }),true);
            element.DragLeave+=(_,_)=>addressBeforeDrag=null;
        }
    }
    private async Task ExecuteSuperDragAsync(BrowserTab tab, PageView view, SuperDragRequest request)
    {
        var config = Settings.SuperDrag;
        var rule = SuperDrag.Resolve(config,request,tab.Url);
        if (rule == null || view.IsDisposed || !tabs.Contains(tab)) return;
        var value = request.Value;
        var remote = rule.Action is "search" or "siteSearch" or "translate" or "imageSearch";
        try {
            if (remote && !config.AllowRemote) {
                var service=rule.Action=="translate" ? config.TranslationTemplate:rule.Action=="imageSearch" ? config.ImageSearchTemplate:Settings.SearchTemplate;
                var domain=Uri.TryCreate(service.Replace("%s","x").Replace("{0}","x"),UriKind.Absolute,out var uri) ? uri.Host:"";
                if (await ShowCardAsync(T("Super drag", "超级拖拽"),new TextBlock { Text=T("This action sends the dragged text or image URL to your selected search or translation service. Allow online actions?","此操作会将拖拽的文字或图片网址发送给所选搜索或翻译服务。允许联网操作吗？")+"\n"+domain,TextWrapping=TextWrapping.Wrap },T("Allow", "允许")) != ContentDialogResult.Primary) return;
                config.AllowRemote=true; ScheduleSave();
            }
            switch (rule.Action) {
                case "copy": var data = new DataPackage(); data.SetText(value); Clipboard.SetContent(data); break;
                case "search": AddTab(Search(value),true,tab.IsPrivate); break;
                case "siteSearch": AddTab(Search("site:"+new Uri(tab.Url).Host+" "+value),true,tab.IsPrivate); break;
                case "translate": AddTab(config.TranslationTemplate.Replace("%s",Uri.EscapeDataString(value)),true,tab.IsPrivate); break;
                case "imageSearch": if (request.Object != "image") throw new InvalidOperationException(); AddTab(config.ImageSearchTemplate.Replace("%s",Uri.EscapeDataString(value)),true,tab.IsPrivate); break;
                case "openForegroundTab": case "openBackgroundTab": if (!AddressParser.IsWeb(value)) throw new InvalidOperationException(); AddTab(value,rule.Action=="openForegroundTab",tab.IsPrivate); break;
                case "download": case "saveImage": if (!AddressParser.IsWeb(value)) throw new InvalidOperationException(); if(!await DownloadSuperDragAsync(tab,view,value))return; break;
                case "bookmark": if (!AddressParser.IsWeb(value)) throw new InvalidOperationException(); store.Bookmarks.Add(new Bookmark { Title=value,Url=value }); store.Notify(); ScheduleSave(); break;
            }
            await Report(true);
        } catch (Exception error) when (error is HttpRequestException or IOException or UnauthorizedAccessException or TaskCanceledException or InvalidOperationException or System.Runtime.InteropServices.COMException) { await Report(false); }
        string Search(string text) => Settings.SearchTemplate.Replace("%s",Uri.EscapeDataString(text)).Replace("{0}",Uri.EscapeDataString(text));
        async Task Report(bool success) {
            superDragDiagnostics.Add(new { time=DateTimeOffset.UtcNow, action=rule.Action, success });
            if (superDragDiagnostics.Count>200) superDragDiagnostics.RemoveAt(0);
            var text = success ? T("Super drag: done","超级拖拽：已完成") : T("Super drag failed. Check the address, service or download folder.","超级拖拽失败，请检查网址、服务或下载目录。");
            Status.Text = text;
            if (config.ShowHints && !view.IsDisposed && view.Control.CoreWebView2 is { } core) await core.ExecuteScriptAsync("window.__sxSuperDrag?.feedback("+JsonSerializer.Serialize(text)+")");
        }
    }
    private async Task<bool> DownloadSuperDragAsync(BrowserTab tab,PageView view,string url)
    {
        var cookieJar = new System.Net.CookieContainer();
        if (view.Control.CoreWebView2 is { } core) foreach (var cookie in await core.CookieManager.GetCookiesAsync(url)) {
            try { cookieJar.Add(new System.Net.Cookie(cookie.Name,cookie.Value,cookie.Path,cookie.Domain) { Secure=cookie.IsSecure,HttpOnly=cookie.IsHttpOnly }); } catch (System.Net.CookieException) { }
        }
        using var client = new HttpClient(new HttpClientHandler { CookieContainer=cookieJar }) { Timeout=TimeSpan.FromMinutes(10) };
        using var response = await client.GetAsync(url,HttpCompletionOption.ResponseHeadersRead,view.Lifetime); response.EnsureSuccessStatusCode();
        var name = response.Content.Headers.ContentDisposition?.FileNameStar ?? response.Content.Headers.ContentDisposition?.FileName?.Trim('"') ?? Uri.UnescapeDataString(new Uri(url).AbsolutePath.Split('/').Last());
        name = string.Concat(name.Select(c => Path.GetInvalidFileNameChars().Contains(c) ? '_' : c));
        if (string.IsNullOrWhiteSpace(name) || name is "." or "..") name="download";
        Directory.CreateDirectory(Settings.DownloadsFolder);
        var path=Path.Combine(Settings.DownloadsFolder,name); var index=1;
        while (File.Exists(path)) path=Path.Combine(Settings.DownloadsFolder,$"{Path.GetFileNameWithoutExtension(name)} ({index++}){Path.GetExtension(name)}");
        var overwrite=false;
        if(Settings.AskDownloadLocation) {
            var picker=new global::Windows.Storage.Pickers.FileSavePicker { SuggestedFileName=Path.GetFileNameWithoutExtension(name) };
            picker.FileTypeChoices.Add(T("File","文件"),new List<string>{Path.GetExtension(name) is {Length:>0} extension ? extension:".bin"});
            InitializeWithWindow.Initialize(picker,WindowNative.GetWindowHandle(this));
            if(await picker.PickSaveFileAsync() is not {} selected)return false;
            path=selected.Path;overwrite=true;
        }
        Status.Text=T("Downloading: ","正在下载：")+name;
        var created=false;
        try {
            await using var output = new FileStream(path,overwrite ? FileMode.Create:FileMode.CreateNew,FileAccess.Write,FileShare.None);
            created=true;
            await response.Content.CopyToAsync(output,view.Lifetime);
        } catch { if (created && File.Exists(path)) File.Delete(path); throw; }
        // Preserve Windows' normal Internet-file checks without saving the dragged URL in metadata.
        try {await File.WriteAllTextAsync(path+":Zone.Identifier","[ZoneTransfer]\r\nZoneId=3\r\n");}catch(IOException){}catch(NotSupportedException){}
        if (!tab.IsPrivate) { store.Downloads.Insert(0,new(path,url,DateTimeOffset.Now)); ScheduleSave(); }
        return true;
    }
}
