using Microsoft.UI.Xaml;
using System.Runtime.InteropServices;
using System.Text.Json;
using Windows.ApplicationModel.DataTransfer;
using WinRT.Interop;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    private async Task VerifySuperDragAsync(string fixture,Action<bool,string> check)
    {
        var old=Settings.SuperDrag;var previous=active;var original=tabs.ToHashSet();
        var oldFolder=Settings.DownloadsFolder;
        var oldSearch=Settings.SearchTemplate;
        var downloadFolder=Path.Combine(DataStore.Root,"super-drag-downloads");
        GetCursorPos(out var previousPointer);
        var savedClipboard=Clipboard.GetContent();
        var oldText=savedClipboard.Contains(StandardDataFormats.Text) ? await savedClipboard.GetTextAsync():null;
        BrowserTab? tab=null;
        try {
            ShowWindow(WindowNative.GetWindowHandle(this),9);Activate();
            SetForegroundWindow(WindowNative.GetWindowHandle(this));
            await Task.Delay(200);
            Settings.SuperDrag=new SuperDragConfig {AllowRemote=true};
            tab=AddTab(fixture+"super-drag",false);await SelectAsync(tab);
            var view=await GetViewAsync(tab);var core=view.Control.CoreWebView2;
            var deadline=DateTime.UtcNow.AddSeconds(15);
            while (await core.ExecuteScriptAsync("typeof window.__sxSuperDrag")!="\"object\"") {
                if(DateTime.UtcNow>deadline) {
                    var script=(string)typeof(PageView).GetMethod("SuperDragScript",System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic)!.Invoke(view,null)!;
                    var error=await core.ExecuteScriptAsync("(()=>{try{eval("+JsonSerializer.Serialize(script)+");return 'script valid'}catch(e){return e.name+':'+e.message}})()");
                    throw new TimeoutException("Super drag script missing at "+core.Source+"; diagnostic "+error);
                }
                await Task.Delay(25);
            }
            check(true,"Super drag shared script is injected into HTTP pages");
            await core.ExecuteScriptAsync("document.body.innerHTML='<a id=draglink style=\"position:fixed;left:70px;top:90px;padding:12px;background:lightblue\" href=\""+fixture+"drag-target\">Drag this link</a>';document.body.style.zoom=1");
            Root.UpdateLayout();SetForegroundWindow(WindowNative.GetWindowHandle(this));
            async Task DragLink(double distance,string selector="#draglink") {
                var coordinates=JsonSerializer.Deserialize<double[]>(await core.ExecuteScriptAsync("(()=>{const r=document.querySelector("+JsonSerializer.Serialize(selector)+").getBoundingClientRect();return [r.x+r.width/2,r.y+r.height/2]})()"))!;
                string? dragData=null;
                var receiver=core.GetDevToolsProtocolEventReceiver("Input.dragIntercepted");
                void Received(object? sender,Microsoft.Web.WebView2.Core.CoreWebView2DevToolsProtocolEventReceivedEventArgs args) { using var data=JsonDocument.Parse(args.ParameterObjectAsJson);dragData=data.RootElement.GetProperty("data").GetRawText(); }
                receiver.DevToolsProtocolEventReceived+=Received;
                await core.CallDevToolsProtocolMethodAsync("Input.setInterceptDrags","{\"enabled\":true}");
                async Task Mouse(string type,double y,int buttons) => await core.CallDevToolsProtocolMethodAsync("Input.dispatchMouseEvent",JsonSerializer.Serialize(new {type,x=coordinates[0],y,button="left",buttons,clickCount=1}));
                await Mouse("mousePressed",coordinates[1],1);
                for(var i=1;i<=8;i++){await Mouse("mouseMoved",coordinates[1]+distance*i/8,1);await Task.Delay(15);}
                if(dragData!=null) foreach(var type in new[]{"dragEnter","dragOver","drop"}) await core.CallDevToolsProtocolMethodAsync("Input.dispatchDragEvent","{\"type\":"+JsonSerializer.Serialize(type)+",\"x\":"+coordinates[0].ToString(System.Globalization.CultureInfo.InvariantCulture)+",\"y\":"+(coordinates[1]+distance).ToString(System.Globalization.CultureInfo.InvariantCulture)+",\"data\":"+dragData+"}");
                await Mouse("mouseReleased",coordinates[1]+distance,0);
                await core.CallDevToolsProtocolMethodAsync("Input.setInterceptDrags","{\"enabled\":false}");
                receiver.DevToolsProtocolEventReceived-=Received;
                await Task.Delay(250);
            }
            var count=tabs.Count;
            await DragLink(75);
            check(tabs.Count==count+1 && active==tab && tabs.Last().Url==fixture+"drag-target","Native left-button link drag down opens one background tab");
            Settings.DownloadsFolder=downloadFolder;
            await core.ExecuteScriptAsync("const img=document.createElement('img');img.id='dragimage';img.style.cssText='position:fixed;left:300px;top:90px;width:50px;height:50px';img.src="+JsonSerializer.Serialize(fixture+"super-drag.png")+";document.body.append(img)");
            var imageDeadline=DateTime.UtcNow.AddSeconds(10);
            while(await core.ExecuteScriptAsync("document.querySelector('#dragimage').naturalWidth>0")!="true") {if(DateTime.UtcNow>imageDeadline)throw new TimeoutException("Drag image fixture did not load");await Task.Delay(25);}
            await DragLink(90,"#dragimage");
            var file=Path.Combine(downloadFolder,"super-drag.png");
            imageDeadline=DateTime.UtcNow.AddSeconds(10);
            while(!File.Exists(file)){if(DateTime.UtcNow>imageDeadline)throw new TimeoutException("Image drag did not download");await Task.Delay(25);}
            check((await File.ReadAllBytesAsync(file)).SequenceEqual(await File.ReadAllBytesAsync(Path.Combine(AppContext.BaseDirectory,"Assets","AppIcon.png"))),"Native image drag down saves the original image in the download folder");
            Settings.SearchTemplate=fixture+"search?q={0}";
            await core.ExecuteScriptAsync("const span=document.createElement('span');span.id='dragtext';span.textContent='super drag selected text';span.style.cssText='position:fixed;left:70px;top:280px;padding:12px';document.body.append(span);const range=document.createRange();range.selectNodeContents(span);getSelection().removeAllRanges();getSelection().addRange(range)");
            var textCount=tabs.Count;
            await DragLink(-75,"#dragtext");
            check(tabs.Count==textCount+1 && active!=tab && tabs.Last().Url.Contains("search?q=super%20drag%20selected%20text"),"Native selected text drag up opens the default search engine in a new tab");
            await SelectAsync(tab);
            await core.ExecuteScriptAsync("getSelection().removeAllRanges()");
            Settings.SuperDrag.Enabled=false;view.ApplySettings();await Task.Delay(60);count=tabs.Count;await DragLink(75);
            check(tabs.Count==count,"Disabling super drag immediately stops native page drags");
            Settings.SuperDrag.Enabled=true;Settings.SuperDrag.Exceptions.Add("127.0.0.1");view.ApplySettings();await Task.Delay(60);count=tabs.Count;await DragLink(75);
            check(tabs.Count==count,"Adding current domain excludes real drags without navigation");
            Settings.SuperDrag.Exceptions.Remove("127.0.0.1");view.ApplySettings();await Task.Delay(60);
            count=tabs.Count;
            await core.ExecuteScriptAsync("chrome.webview.postMessage({type:'super-drag',token:'forged',phase:'finish',object:'link',value:'https://evil.example',dx:0,dy:70,region:'page',modifier:'none'})");await Task.Delay(80);
            check(tabs.Count==count,"Page-forged super drag bridge messages are rejected");
            var text=new SuperDragRequest(Object:"text",Value:"local copy fixture",Dy:40,Direction:"down");
            await ExecuteSuperDragAsync(tab,view,text);
            check(await Clipboard.GetContent().GetTextAsync()==text.Value,"Text down copies locally through the native clipboard");
            Settings.SuperDrag.AllowRemote=false;
            var consent=ExecuteSuperDragAsync(tab,view,text with {Dy=-40,Direction="up"});await Task.Delay(80);
            check(tabs.Count==count && OverlayLayer.Visibility==Visibility.Visible,"Search waits for consent before sending dragged text");DismissOverlay();await consent;
            check(tabs.Count==count && !Settings.SuperDrag.AllowRemote,"Dismissed consent leaves online actions disabled");
            var duplicate=JsonSerializer.Deserialize<SuperDragConfig>(JsonSerializer.Serialize(Settings.SuperDrag,SuperDrag.Json),SuperDrag.Json)!;
            check(duplicate.Rules.SequenceEqual(Settings.SuperDrag.Rules),"Active super drag rules survive export and import");
        } finally {
            SendInput(1,[new BookmarkInput {Mouse=new BookmarkMouseInput {Flags=4}}],Marshal.SizeOf<BookmarkInput>());
            SetCursorPos(previousPointer.X,previousPointer.Y);
            if(oldText!=null){var data=new DataPackage();data.SetText(oldText);Clipboard.SetContent(data);}
            Settings.SuperDrag=old;
            Settings.DownloadsFolder=oldFolder;
            Settings.SearchTemplate=oldSearch;
            foreach(var candidate in tabs.Where(candidate=>!original.Contains(candidate)).ToArray())CloseTab(candidate);
            foreach(var view in views.Values){view.ApplySettings();_=view.UpdateDocumentScriptAsync();}
            if(previous!=null&&tabs.Contains(previous))await SelectAsync(previous);
        }
    }
}
