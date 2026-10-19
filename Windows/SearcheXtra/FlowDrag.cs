using System.Text.Json;
namespace SearcheXtra.Windows;
public sealed record FlowDragRule(string Object,string Pattern,string Action,string Engine="system",string Url="",bool Active=true,string Position="right",bool Incognito=false,bool AutoDetectUrl=true,bool PreferLink=false,bool AsMarkdown=false,string FolderId="",string Subdir="");
public sealed class FlowDragConfig
{
    public bool Enabled {get;set;}=true;
    public bool EnableText {get;set;}=true;
    public bool EnableLink {get;set;}=true;
    public bool EnableImage {get;set;}=true;
    public bool ShowHints {get;set;}=true;
    public bool ShowTrail {get;set;}
    public bool IgnoreEditable {get;set;}=true;
    public double DistanceThreshold {get;set;}=20;
    public List<string> ExcludedSites {get;set;}=[];
    public List<FlowDragRule> Rules {get;set;}=[new("text","→","search"),new("link","→","openTab"),new("image","→","openImage")];
    public void Validate()
    {
        if(!double.IsFinite(DistanceThreshold)||DistanceThreshold is <1 or >200||Rules==null||ExcludedSites==null||Rules.Count>200)throw new FormatException();
        foreach(var r in Rules)if(r==null||r.Url==null||r.Subdir==null||!FlowDrag.Objects.Contains(r.Object)||!FlowDrag.ValidPattern(r.Pattern)||!FlowDrag.Actions(r.Object).Contains(r.Action)||!FlowDrag.Positions.Contains(r.Position)||!FlowDrag.Engines.Contains(r.Engine)||r.Engine=="custom"&&(!r.Url.Contains("%s")||!AddressParser.IsWeb(r.Url.Replace("%s","x")))||r.Subdir.Split(['/','\\']).Any(p=>p is "." or "..")||Path.IsPathRooted(r.Subdir)||r.Subdir.Contains(':'))throw new FormatException();
        if(Rules.GroupBy(r=>(r.Object,r.Pattern)).Any(g=>g.Count()>1))throw new FormatException();
        if(ExcludedSites.Any(h=>h==null))throw new FormatException();
        ExcludedSites=ExcludedSites.Select(h=>h.Trim().TrimStart('.').ToLowerInvariant()).Where(h=>h.Length>0).Distinct().ToList();
        if(ExcludedSites.Any(h=>Uri.CheckHostName(h)==UriHostNameType.Unknown))throw new FormatException();
    }
}
public sealed record FlowDragRequest(string Phase="",string Id="",string Object="",string Pattern="",string Text="",string LinkUrl="",string ImageUrl="",string LinkText="",string PageUrl="");
public static class FlowDrag
{
    public static readonly JsonSerializerOptions Json=new(JsonSerializerDefaults.Web);
    public static readonly string[] Objects=["text","link","image"],Positions=["current","left","right","first","last"],Engines=["system","baidu","google","google_translate","bing","bing_translate","360","sogou","duckduckgo","yahoo","yahoo_jp","naver","seznam","tineye","yandex","saucenao","iqdb","trace","custom"];
    public static string[] EnginesFor(string type)=>type=="image"?["system","google","bing","tineye","yandex","saucenao","iqdb","trace","custom"]:Engines.Where(e=>!new[]{"tineye","saucenao","iqdb","trace"}.Contains(e)).ToArray();
    public static string[] Actions(string type)=>type switch {"text"=>["none","search","copy"],"link"=>["none","openTab","copyLink","copyLinkText","copyLinkAndText","bookmarkLink"],_=>["none","openImage","openLink","copyImageUrl","saveImage","imageSearch"]};
    public static bool ValidPattern(string? value)=>value=="*"||value!=null&&value.Length is >0 and <=32&&value.All(c=>"↑↓←→".Contains(c));
    public static bool EnabledOn(FlowDragConfig c,string page,string type)=>c.Enabled&&Objects.Contains(type)&&(type=="text"?c.EnableText:type=="link"?c.EnableLink:c.EnableImage)&&AddressParser.IsWeb(page)&&!c.ExcludedSites.Any(h=>new Uri(page).Host.Equals(h,StringComparison.OrdinalIgnoreCase)||new Uri(page).Host.EndsWith("."+h,StringComparison.OrdinalIgnoreCase));
    public static FlowDragRule? Resolve(FlowDragConfig c,FlowDragRequest p)=>EnabledOn(c,p.PageUrl,p.Object)&&ValidPattern(p.Pattern)?c.Rules.FirstOrDefault(r=>r.Object==p.Object&&r.Pattern==p.Pattern)??c.Rules.FirstOrDefault(r=>r.Object==p.Object&&r.Pattern=="*"):null;
    public static string Template(string engine,string current,string custom,bool image=false)=>engine switch {
        "custom"=>custom,"baidu"=>"https://www.baidu.com/s?wd=%s","bing"=>image?"https://www.bing.com/images/searchbyimage?cbir=sbi&imgurl=%s":"https://www.bing.com/search?q=%s",
        "google"=>image?"https://lens.google.com/uploadbyurl?url=%s":"https://www.google.com/search?q=%s","360"=>"https://www.so.com/s?q=%s","sogou"=>"https://www.sogou.com/web?query=%s","duckduckgo"=>"https://duckduckgo.com/?q=%s",
        "google_translate"=>"https://translate.google.com/?sl=auto&text=%s","bing_translate"=>"https://www.bing.com/translator/?text=%s","yahoo"=>"https://search.yahoo.com/search?p=%s","yahoo_jp"=>"https://search.yahoo.co.jp/search?p=%s","naver"=>"https://search.naver.com/search.naver?query=%s","seznam"=>"https://search.seznam.cz/?q=%s",
        "tineye"=>"https://tineye.com/search?url=%s","yandex"=>image?"https://yandex.com/images/search?rpt=imageview&url=%s":"https://yandex.com/search/?text=%s","saucenao"=>"https://saucenao.com/search.php?url=%s","iqdb"=>"https://iqdb.org/?url=%s","trace"=>"https://trace.moe/?url=%s",
        _=>image?"https://lens.google.com/uploadbyurl?url=%s":current};
    public static string Search(string text,string template)=>template.Replace("%s",Uri.EscapeDataString(text)).Replace("{0}",Uri.EscapeDataString(text));
    public static FlowDragConfig Import(string text)
    {
        try { return ImportCore(text); }
        catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException)
        {
            throw new FormatException("Invalid drag configuration.", error);
        }
    }
    private static FlowDragConfig ImportCore(string text)
    {
        using var doc=JsonDocument.Parse(text);var root=doc.RootElement;
        if(!root.TryGetProperty("textDragGestures",out _))return JsonSerializer.Deserialize<FlowDragConfig>(text,Json)??throw new FormatException();
        var result=new FlowDragConfig();result.Rules.Clear();
        bool Flag(string key,bool fallback)=>root.TryGetProperty(key,out var v)?v.GetBoolean():fallback;
        result.EnableText=Flag("enableTextDrag",true);result.EnableLink=Flag("enableLinkDrag",true);result.EnableImage=Flag("enableImageDrag",true);result.ShowHints=Flag("enableHUD",true);result.ShowTrail=Flag("enableTrail",false);result.IgnoreEditable=Flag("textDropIgnoreInput",true)||Flag("linkDropIgnoreInput",true);
        if(root.TryGetProperty("distanceThreshold",out var threshold))result.DistanceThreshold=threshold.GetDouble();
        foreach(var type in Objects)if(root.TryGetProperty(type+"DragGestures",out var list))foreach(var element in list.EnumerateArray()) {
            var fields=element.EnumerateObject().ToDictionary(p=>p.Name,p=>p.Value.Clone());fields["object"]=JsonSerializer.SerializeToElement(type);fields["pattern"]=fields.GetValueOrDefault("direction");
            if(type=="image"&&fields.GetValueOrDefault("action").GetString()=="openTab")fields["action"]=JsonSerializer.SerializeToElement("openImage");
            if(fields.TryGetValue("folderId",out var folder)&&folder.ValueKind==JsonValueKind.Object)fields["folderId"]=folder.TryGetProperty("id",out var id)?id:JsonSerializer.SerializeToElement("");
            var rule=JsonSerializer.Deserialize<FlowDragRule>(JsonSerializer.Serialize(fields),Json)??throw new FormatException();
            result.Rules.Add(rule);
        }
        result.Validate();return result;
    }
}
