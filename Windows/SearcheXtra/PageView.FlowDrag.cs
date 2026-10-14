using System.Text.Json;
using Microsoft.Web.WebView2.Core;
namespace SearcheXtra.Windows;
public sealed partial class PageView
{
    private readonly string flowDragToken=Guid.NewGuid().ToString("N");
    private static readonly Lazy<string> flowDragSource=new(()=>File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"Assets","FlowDrag.js")));
    private readonly List<CoreWebView2Frame> flowDragFrames=[];
    private FlowDragRequest? flowDragPending;
    private DateTimeOffset flowDragStarted;
    public event Func<FlowDragRequest,Task>? FlowDragRequested;
    private string FlowDragOptions()=>JsonSerializer.Serialize(new{pointerDrag=true,config=store.Settings.FlowDrag,labels=FlowDrag.Objects.SelectMany(FlowDrag.Actions).Distinct().ToDictionary(k=>k,k=>new Strings(store.Settings).Key("flowDrag.action."+k))},FlowDrag.Json);
    private string FlowDragScript()=>"(function(){"+flowDragSource.Value+";const post=chrome.webview.postMessage.bind(chrome.webview);sxInstallFlowDrag("+FlowDragOptions()+",p=>post({...p,type:'flow-drag',token:"+JsonSerializer.Serialize(flowDragToken)+"}));})();";
    private void BindFlowDragFrame(CoreWebView2Frame frame)
    {
        flowDragFrames.Add(frame);
        frame.WebMessageReceived+=async(_,args)=>{try{await ReceiveFlowDragAsync(args.WebMessageAsJson,args.Source);}catch(JsonException){}};
        frame.Destroyed+=(_,_)=>flowDragFrames.Remove(frame);
    }
    private void ConfigureFlowDrag()
    {
        var script="window.__sxFlowDrag?.configure("+FlowDragOptions()+")";
        if(Control.CoreWebView2 is {} core)_=core.ExecuteScriptAsync(script);
        foreach(var frame in flowDragFrames.ToArray())_=ConfigureFrame(frame,script);
        async Task ConfigureFrame(CoreWebView2Frame frame,string value){try{await frame.ExecuteScriptAsync(value);}catch(System.Runtime.InteropServices.COMException){}}
    }
    private async Task ReceiveFlowDragAsync(string json,string source)
    {
        using var doc=JsonDocument.Parse(json);var data=doc.RootElement;
        if(!data.TryGetProperty("type",out var type)||type.GetString()!="flow-drag"||!data.TryGetProperty("token",out var token)||token.GetString()!=flowDragToken||disposed)return;
        var request=data.Deserialize<FlowDragRequest>(FlowDrag.Json);if(request==null)return;
        if(request.Phase=="cancel"){if(request.Id==flowDragPending?.Id)flowDragPending=null;return;}
        if(request.PageUrl!=source)return;
        if(request.Phase=="ready"){ConfigureFlowDrag();return;}
        if(!FlowDrag.EnabledOn(store.Settings.FlowDrag,source,request.Object))return;
        if(request.Phase=="begin"){flowDragPending=request;flowDragStarted=DateTimeOffset.UtcNow;return;}
        if(request.Phase!="perform"||flowDragPending is not {} pending||(request with{Phase="",Pattern=""})!=(pending with{Phase="",Pattern=""})||DateTimeOffset.UtcNow-flowDragStarted>TimeSpan.FromMinutes(2))return;
        flowDragPending=null;
        if(FlowDrag.Resolve(store.Settings.FlowDrag,request) is {Action:not "none"}&&FlowDragRequested!=null)await FlowDragRequested(request);
    }
}
