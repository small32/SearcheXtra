using Microsoft.UI.Xaml;
using Windows.ApplicationModel.DataTransfer;
namespace SearcheXtra.Windows;
public sealed partial class MainWindow
{
    private async Task ExecuteFlowDragAsync(BrowserTab source,PageView view,FlowDragRequest request)
    {
        var rule=FlowDrag.Resolve(Settings.FlowDrag,request);
        if(rule==null||rule.Action=="none"||view.IsDisposed||!tabs.Contains(source))return;
        try {
            string? target=null,copy=null;
            switch(rule.Action) {
                case "search":
                    target=FlowDrag.Search(request.Text,FlowDrag.Template(rule.Engine,Settings.SearchTemplate,rule.Url));
                    var detected=request.Text.Trim();if(rule.AutoDetectUrl&&!detected.Any(char.IsWhiteSpace)&&(AddressParser.IsWeb(detected)||!detected.Contains("@")&&(detected.Contains(".")||detected.StartsWith("localhost",StringComparison.OrdinalIgnoreCase)))){var parsed=AddressParser.Resolve(detected,Settings.SearchTemplate);if(AddressParser.IsWeb(parsed.AbsoluteUri))target=parsed.AbsoluteUri;}
                    break;
                case "openTab": target=request.LinkUrl;break;
                case "openImage": target=rule.PreferLink&&AddressParser.IsWeb(request.LinkUrl)?request.LinkUrl:request.ImageUrl;break;
                case "openLink": target=AddressParser.IsWeb(request.LinkUrl)?request.LinkUrl:request.ImageUrl;break;
                case "imageSearch": target=FlowDrag.Search(request.ImageUrl,FlowDrag.Template(rule.Engine,Settings.SearchTemplate,rule.Url,true));break;
                case "copy":copy=request.Text;break;
                case "copyLink":copy=request.LinkUrl;break;
                case "copyImageUrl":copy=request.ImageUrl;break;
                case "copyLinkText":copy=request.LinkText;break;
                case "copyLinkAndText":copy=rule.AsMarkdown?"["+request.LinkText.Replace("\\","\\\\").Replace("[","\\[").Replace("]","\\]")+"]("+request.LinkUrl+")":request.LinkText+"\n"+request.LinkUrl;break;
                case "bookmarkLink":
                    if(!AddressParser.IsWeb(request.LinkUrl))throw new InvalidOperationException();
                    List<Bookmark> Folder(List<Bookmark> nodes){foreach(var node in nodes.Where(n=>n.Children!=null)){if(node.Id.ToString()==rule.FolderId)return node.Children!;var found=Folder(node.Children!);if(found!=store.Bookmarks)return found;}return store.Bookmarks;}
                    Folder(store.Bookmarks).Add(new Bookmark{Title=request.LinkText.Length>0?request.LinkText:request.LinkUrl,Url=request.LinkUrl});store.Notify();ScheduleSave();break;
                case "saveImage":await SaveFlowDragImageAsync(view,request.ImageUrl,rule.Subdir,source.IsPrivate);break;
            }
            if(copy!=null){var data=new DataPackage();data.SetText(copy);Clipboard.SetContent(data);}
            if(target!=null) {
                if(!AddressParser.IsWeb(target))throw new InvalidOperationException();
                var privately=source.IsPrivate||rule.Incognito;
                if(rule.Position=="current"&&privately==source.IsPrivate){source.Url=target;await SelectAsync(source);view.Navigate(target);}
                else {
                    var opened=AddTab(target,rule.Active,privately,loadBackground:false);
                    var index=rule.Position switch {"first"=>0,"left"=>tabs.IndexOf(source),"right"=>tabs.IndexOf(source)+1,_=>tabs.Count-1};
                    tabs.Move(tabs.IndexOf(opened),Math.Clamp(index,0,tabs.Count-1));RefreshTabLists();
                    if(!rule.Active)await LoadBackgroundAsync(opened);
                }
            }
            Status.Text=strings.Key("flowDrag.done");
        } catch(Exception error) when(error is HttpRequestException or IOException or UnauthorizedAccessException or InvalidOperationException or ArgumentException or OperationCanceledException or System.Runtime.InteropServices.COMException) {Status.Text=strings.Key("flowDrag.failed");}
    }
    private async Task SaveFlowDragImageAsync(PageView view,string url,string subdir,bool privately)
    {
        if(!AddressParser.IsWeb(url))throw new InvalidOperationException();
        var cookies=new System.Net.CookieContainer();
        foreach(var c in await view.Control.CoreWebView2.CookieManager.GetCookiesAsync(url)){try{cookies.Add(new System.Net.Cookie(c.Name,c.Value,c.Path,c.Domain){Secure=c.IsSecure,HttpOnly=c.IsHttpOnly});}catch(System.Net.CookieException){}}
        using var client=new HttpClient(new HttpClientHandler{CookieContainer=cookies}){Timeout=TimeSpan.FromMinutes(5)};
        using var response=await client.GetAsync(url,HttpCompletionOption.ResponseHeadersRead,view.Lifetime);response.EnsureSuccessStatusCode();
        var name=response.Content.Headers.ContentDisposition?.FileNameStar??response.Content.Headers.ContentDisposition?.FileName?.Trim('"')??Uri.UnescapeDataString(new Uri(url).AbsolutePath.Split('/').Last());
        name=string.Concat(name.Select(c=>Path.GetInvalidFileNameChars().Contains(c)?'_':c));if(string.IsNullOrWhiteSpace(name)||name is "." or "..")name="image";
        var directory=Path.Combine(Settings.DownloadsFolder,subdir);Directory.CreateDirectory(directory);
        var path=Path.Combine(directory,name);for(var i=1;File.Exists(path);i++)path=Path.Combine(directory,$"{Path.GetFileNameWithoutExtension(name)} ({i}){Path.GetExtension(name)}");
        await using(var file=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None)){try{await response.Content.CopyToAsync(file,view.Lifetime);}catch{file.Close();File.Delete(path);throw;}}
        try{await File.WriteAllTextAsync(path+":Zone.Identifier","[ZoneTransfer]\r\nZoneId=3\r\n");}catch(IOException){}
        if(!privately){store.Downloads.Insert(0,new(path,url,DateTimeOffset.Now));ScheduleSave();}
    }
}
