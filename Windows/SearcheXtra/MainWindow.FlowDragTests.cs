using System.Text.Json;
using Microsoft.UI.Xaml;
using Windows.ApplicationModel.DataTransfer;
namespace SearcheXtra.Windows;
public sealed partial class MainWindow
{
    private async Task VerifyFlowDragAsync(string fixture,Action<bool,string> check)
    {
        var old=Settings.FlowDrag;var oldSearch=Settings.SearchTemplate;var oldFolder=Settings.DownloadsFolder;var oldLazy=Settings.LazyBackgroundTabs;
        var savedClipboard=Clipboard.GetContent();var oldText=savedClipboard.Contains(StandardDataFormats.Text)?await savedClipboard.GetTextAsync():null;
        async Task Wait(Func<bool> ready){var deadline=DateTime.UtcNow.AddSeconds(15);while(!ready()){if(DateTime.UtcNow>deadline)throw new TimeoutException("Flow drag integration timed out");await Task.Delay(25);}}
        try {
            Settings.FlowDrag=new(){ShowHints=false};Settings.SearchTemplate=fixture+"search?q={0}";Settings.LazyBackgroundTabs=true;
            var source=AddTab(fixture+"flow-source",false);await SelectAsync(source);await Wait(()=>!source.Loading&&source.Title=="SearcheXtra fixture");
            var view=views[source.Id];var core=view.Control.CoreWebView2;
            check(await core.ExecuteScriptAsync("typeof window.__sxFlowDrag.configure")=="\"function\"","Flow drag script is injected into actual web content");
            await core.ExecuteScriptAsync("document.body.innerHTML='<a id=draglink style=\"position:fixed;left:60px;top:70px;padding:12px\" href=\""+fixture+"target\">Selected link words</a><span id=dragtext style=\"position:fixed;left:70px;top:200px;padding:12px\">Flow drag 中文 search</span><img id=dragimage style=\"position:fixed;left:300px;top:70px;width:50px;height:50px\" src=\""+fixture+"flow-image.png\">'");
            async Task SelectText(string selector,string? words=null,bool frame=false) {
                var doc=frame?"document.querySelector('#dragframe').contentDocument":"document";
                await core.ExecuteScriptAsync("(()=>{const d="+doc+";const el=d.querySelector("+JsonSerializer.Serialize(selector)+");"+(words!=null?"el.textContent="+JsonSerializer.Serialize(words)+";":"")+"const range=d.createRange();range.selectNodeContents(el);d.defaultView.getSelection().removeAllRanges();d.defaultView.getSelection().addRange(range)})()");
            }
            async Task Drag(string selector,(double X,double Y)[] offsets,bool frame=false,Func<Task>? beforeRelease=null) {
                var doc=frame?"document.querySelector('#dragframe').contentDocument":"document";
                var coordinates=JsonSerializer.Deserialize<double[]>(await core.ExecuteScriptAsync("(()=>{const d="+doc+",r=d.querySelector("+JsonSerializer.Serialize(selector)+").getBoundingClientRect();const f="+(frame?"document.querySelector('#dragframe').getBoundingClientRect()":"{x:0,y:0}")+";return [r.x+r.width/2+f.x,r.y+r.height/2+f.y]})()"))!;
                async Task Mouse(string type,double x,double y,int buttons)=>await core.CallDevToolsProtocolMethodAsync("Input.dispatchMouseEvent",JsonSerializer.Serialize(new{type,x,y,button="left",buttons,clickCount=1}));
                await Mouse("mousePressed",coordinates[0],coordinates[1],1);
                (double X,double Y) previous=(0,0);
                foreach(var offset in offsets) {
                    for(var i=1;i<=8;i++){await Mouse("mouseMoved",coordinates[0]+previous.X+(offset.X-previous.X)*i/8,coordinates[1]+previous.Y+(offset.Y-previous.Y)*i/8,1);await Task.Delay(10);}
                    previous=offset;
                }
                if(beforeRelease!=null)await beforeRelease();
                var end=offsets.Last();await Mouse("mouseReleased",coordinates[0]+end.X,coordinates[1]+end.Y,0);
                await Task.Delay(150);
            }
            void Rule(string type,string pattern,string action,bool foreground=false){Settings.FlowDrag.Rules.RemoveAll(r=>r.Object==type&&r.Pattern==pattern);Settings.FlowDrag.Rules.Add(new(type,pattern,action,Active:foreground,AutoDetectUrl:false));view.ApplySettings();}
            foreach(var (pattern,dx,dy) in new (string,double,double)[]{("↑",0,-70),("↓",0,70),("←",-45,0),("→",70,0)}) {
                Rule("text",pattern,"search");await Task.Delay(50);var words="后台搜索 "+pattern;await SelectText("#dragtext",words);
                Func<Task>? previewCheck=null;
                if(pattern=="↑")previewCheck=async()=>{
                    check(await core.ExecuteScriptAsync("(()=>{const p=document.querySelector('[data-searchextra-flow-drag-preview]'),r=p?.getBoundingClientRect(),m=document.querySelector('[data-searchextra-flow-drag-marker]'),b=m?.getBoundingClientRect();return p?.textContent==="+JsonSerializer.Serialize(words)+"&&getComputedStyle(p).pointerEvents==='none'&&Number(getComputedStyle(p).opacity)>0&&Number(getComputedStyle(p).opacity)<1&&r.width>0&&Math.abs(r.left+r.width/2-parseFloat(p.style.left))<1&&Math.abs(r.bottom-parseFloat(p.style.top))<1&&m&&getComputedStyle(m).pointerEvents==='none'&&b.width>0&&b.width<=10&&b.height>0&&b.height<=10&&b.left>=parseFloat(p.style.left)&&b.left<parseFloat(p.style.left)+20&&b.top>parseFloat(p.style.top)+10&&b.top<parseFloat(p.style.top)+40&&!document.querySelector('[data-searchextra-flow-drag]')})()") == "true","Dragged text appears above the pointer with a small drag box below it, independently of action hints and trails");
                    var folder=await global::Windows.Storage.StorageFolder.GetFolderFromPathAsync(DataStore.Root);
                    var file=await folder.CreateFileAsync("flow-drag-preview.png",global::Windows.Storage.CreationCollisionOption.ReplaceExisting);
                    using var screenshot=await file.OpenAsync(global::Windows.Storage.FileAccessMode.ReadWrite);
                    await core.CapturePreviewAsync(Microsoft.Web.WebView2.Core.CoreWebView2CapturePreviewImageFormat.Png,screenshot);
                };
                var before=tabs.ToHashSet();await Drag("#dragtext",[(dx,dy)],beforeRelease:previewCheck);
                var result=tabs.Single(t=>!before.Contains(t));var expected=fixture+"search?q="+Uri.EscapeDataString(words);
                await Wait(()=>views.TryGetValue(result.Id,out var loaded)&&!result.Loading&&result.Title=="SearcheXtra fixture"&&loaded.Control.CoreWebView2.Source==expected);
                check(active==source&&views[result.Id].Control.Visibility==Visibility.Collapsed,"Selected text "+pattern+" starts a real background search while lazy tabs are enabled");
                if(pattern=="↑")check(await core.ExecuteScriptAsync("!document.querySelector('[data-searchextra-flow-drag-preview],[data-searchextra-flow-drag-marker]')")=="true","Releasing the mouse removes the dragged content preview and cursor drag box");
            }
            Rule("text","→","search");await Task.Delay(50);await SelectText("#draglink");var selectedTabs=tabs.ToHashSet();await Drag("#draglink",[(70,0)],beforeRelease:async()=>check(await core.ExecuteScriptAsync("document.querySelector('[data-searchextra-flow-drag-preview]')?.textContent==='Selected link words'")=="true","Selected link words appear as text in the drag preview"));
            var selectedResult=tabs.Single(t=>!selectedTabs.Contains(t));
            check(active==source&&selectedResult.Url.Contains("search?q=Selected%20link%20words"),"Dragging selected link text searches its words instead of opening the link");
            Rule("text","↑→","copy");await Task.Delay(50);await SelectText("#dragtext","sequence clipboard");await Drag("#dragtext",[(0,-65),(65,-65)]);
            check(await Clipboard.GetContent().GetTextAsync()=="sequence clipboard","Continuous direction sequences invoke the configured action");
            Rule("text","*","copy");Settings.FlowDrag.Rules.RemoveAll(r=>r.Object=="text"&&r.Pattern=="↓");view.ApplySettings();await Task.Delay(50);await SelectText("#dragtext","wildcard clipboard");await Drag("#dragtext",[(0,65)]);
            check(await Clipboard.GetContent().GetTextAsync()=="wildcard clipboard","Wildcard handles an unconfigured direction");
            Rule("text","↓","none");await Task.Delay(50);await SelectText("#dragtext","do not copy");var noneCount=tabs.Count;await Drag("#dragtext",[(0,65)]);
            check(tabs.Count==noneCount&&await Clipboard.GetContent().GetTextAsync()=="wildcard clipboard","No action suppresses the wildcard rule");
            await core.ExecuteScriptAsync("getSelection().removeAllRanges()");Rule("link","→","openTab");await Task.Delay(50);
            var linkTabs=tabs.ToHashSet();await Drag("#draglink",[(70,0)],beforeRelease:async()=>check(await core.ExecuteScriptAsync("document.querySelector('[data-searchextra-flow-drag-preview]')?.textContent==='Selected link words'")=="true","Link drags show the dragged link label beside the pointer"));
            var linkResult=tabs.Single(t=>!linkTabs.Contains(t));await Wait(()=>linkResult.Title=="SearcheXtra fixture"&&!linkResult.Loading);
            check(active==source&&linkResult.Url==fixture+"target","Mouse-release link drag opens and loads the link in the background");
            Rule("image","→","saveImage");Settings.DownloadsFolder=Path.Combine(DataStore.Root,"flow-downloads");await Task.Delay(50);
            var imageDeadline=DateTime.UtcNow.AddSeconds(15);while(await core.ExecuteScriptAsync("document.querySelector('#dragimage').naturalWidth>0")!="true"){if(DateTime.UtcNow>imageDeadline)throw new TimeoutException("Image fixture failed to load");await Task.Delay(25);}
            await Drag("#dragimage",[(70,0)],beforeRelease:async()=>check(await core.ExecuteScriptAsync("(()=>{const p=document.querySelector('[data-searchextra-flow-drag-preview]'),c=p?.querySelector('canvas'),r=p?.getBoundingClientRect();return !!c&&c.width>0&&c.width<=120&&c.height>0&&c.height<=96&&Math.abs(r.left+r.width/2-parseFloat(p.style.left))<1&&Math.abs(r.bottom-parseFloat(p.style.top))<1&&c.getContext('2d').getImageData(Math.floor(c.width/2),Math.floor(c.height/2),1,1).data[3]>0})()") == "true","Image drags show a scaled thumbnail centered directly above the pointer"));await Wait(()=>Directory.Exists(Settings.DownloadsFolder)&&Directory.GetFiles(Settings.DownloadsFolder).Length>0);
            check((await File.ReadAllBytesAsync(Directory.GetFiles(Settings.DownloadsFolder).Single())).SequenceEqual(await File.ReadAllBytesAsync(Path.Combine(AppContext.BaseDirectory,"Assets","AppIcon.png"))),"Image saving downloads original image bytes");
            Rule("text","→","search");
            await core.ExecuteScriptAsync("const f=document.createElement('iframe');f.id='dragframe';f.style.cssText='position:fixed;left:360px;top:130px;width:300px;height:240px;border:0';f.src='"+fixture+"frame';document.body.append(f)");
            await Task.Delay(500);await core.ExecuteScriptAsync("document.querySelector('#dragframe').contentDocument.body.innerHTML='<span id=frametext style=\"position:fixed;left:30px;top:50px\">Frame search words</span>'");view.ApplySettings();await Task.Delay(80);await SelectText("#frametext",null,true);
            var frameTabs=tabs.ToHashSet();await Drag("#frametext",[(65,0)],true);await Wait(()=>tabs.Count==frameTabs.Count+1);
            var frameResult=tabs.Single(t=>!frameTabs.Contains(t));check(active==source&&frameResult.Url.Contains("search?q=Frame%20search%20words"),"Text drag inside an iframe reaches the native browser bridge");
            var panel=new Microsoft.UI.Xaml.Controls.StackPanel();BuildFlowDragSettings(panel,_=>{});check(panel.Children.OfType<Microsoft.UI.Xaml.Controls.Border>().Any(),"The native super-drag overview builds its settings card");
            var home=(Microsoft.UI.Xaml.Controls.StackPanel)panel.Children.OfType<Microsoft.UI.Xaml.Controls.Border>().Single().Child;
            var configure=home.Children.OfType<Microsoft.UI.Xaml.Controls.Button>().Single(b=>b.Name=="FlowDrag_rules");
            var peer=new Microsoft.UI.Xaml.Automation.Peers.ButtonAutomationPeer(configure);((Microsoft.UI.Xaml.Automation.Provider.IInvokeProvider)peer.GetPattern(Microsoft.UI.Xaml.Automation.Peers.PatternInterface.Invoke)).Invoke();
            var directions=panel.Children.OfType<Microsoft.UI.Xaml.Controls.Border>().Select(b=>(Microsoft.UI.Xaml.Controls.StackPanel)b.Child).SelectMany(p=>p.Children.OfType<Microsoft.UI.Xaml.Controls.Grid>()).ToArray();
            check(new[]{"↑","↓","←","→"}.All(pattern=>directions.SelectMany(g=>g.Children.OfType<Microsoft.UI.Xaml.Controls.ComboBox>()).Any(c=>Equals(c.Tag,pattern))),"Configure actions presents all four direction editors without invalid control names");
            var choose=directions.SelectMany(g=>g.Children.OfType<Microsoft.UI.Xaml.Controls.ComboBox>()).Single(c=>c.Name=="FlowDragAction_up");choose.SelectedIndex=Array.IndexOf(FlowDrag.Actions("text"),"copy");
            check(Settings.FlowDrag.Rules.Single(r=>r.Object=="text"&&r.Pattern=="↑").Action=="copy","Changing a direction in the native settings page immediately updates its saved action");
            Settings.SettingsPage="flowDrag";var settings=ShowSettingsAsync();await Task.Delay(80);check(OverlayLayer.Visibility==Visibility.Visible,"Super drag settings open through the tabs settings subpage");DismissOverlay();await settings;
            Settings.FlowDrag.Enabled=false;view.ApplySettings();await Task.Delay(60);await core.ExecuteScriptAsync("document.querySelector('#dragframe').remove()");await SelectText("#dragtext","disabled drag");var disabledCount=tabs.Count;await Drag("#dragtext",[(70,0)]);
            check(tabs.Count==disabledCount,"Disabling the feature stops mouse-release drag actions immediately");
        } finally {
            Settings.FlowDrag=old;Settings.SearchTemplate=oldSearch;Settings.DownloadsFolder=oldFolder;Settings.LazyBackgroundTabs=oldLazy;
            if(oldText!=null){var data=new DataPackage();data.SetText(oldText);Clipboard.SetContent(data);}
        }
    }
}
