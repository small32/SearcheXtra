using System.Text.Json;
using System.Text.Json.Serialization;

namespace SearcheXtra.Windows;

public sealed record SuperDragRule(string Object, string Direction, string Modifier, string Action, string Region = "page");
public sealed class SuperDragConfig
{
    public int Version { get; set; } = 1;
    public bool Enabled { get; set; } = true;
    public double MinDistance { get; set; } = 10;
    public string DirectionMode { get; set; } = "8-way";
    public bool ShowHints { get; set; } = true;
    public bool AllowRemote { get; set; }
    public string TranslationTemplate { get; set; } = "https://translate.google.com/?sl=auto&tl=zh-CN&text=%s&op=translate";
    public string ImageSearchTemplate { get; set; } = "https://lens.google.com/uploadbyurl?url=%s";
    public List<string> Exceptions { get; set; } = ["maps.google.com", "docs.google.com", "drive.google.com", "figma.com", "canva.com", "vscode.dev", "onedrive.live.com", "maps.baidu.com"];
    public List<SuperDragRule> Rules { get; set; } = Defaults();
    public static List<SuperDragRule> Defaults() => [
        new("text","up","none","search"),new("text","down","none","copy"),new("text","left","none","translate"),new("text","right","none","siteSearch"),
        new("link","up","none","openForegroundTab"),new("link","down","none","openBackgroundTab"),new("link","left","none","copy"),new("link","right","none","download"),
        new("image","up","none","openForegroundTab"),new("image","down","none","saveImage"),new("image","left","none","copy"),new("image","right","none","imageSearch")];
    public void Validate()
    {
        if (Version != 1 || !double.IsFinite(MinDistance) || MinDistance < 1 || MinDistance > 200 || !SuperDrag.Modes.Contains(DirectionMode) || Rules == null || Exceptions == null || Rules.Count > 200 || Exceptions.Count > 200) throw new FormatException("Invalid super drag configuration");
        if (new[] { TranslationTemplate, ImageSearchTemplate }.Any(t => string.IsNullOrEmpty(t) || !t.Contains("%s") || !AddressParser.IsWeb(t.Replace("%s", "test")))) throw new FormatException("Invalid service address");
        foreach (var r in Rules) if (r == null || !SuperDrag.Objects.Contains(r.Object) || !SuperDrag.Directions.Contains(r.Direction) || !SuperDrag.Modifiers.Contains(r.Modifier) || !SuperDrag.Actions.Contains(r.Action) || !SuperDrag.Regions.Contains(r.Region)) throw new FormatException("Invalid rule");
        if (Rules.GroupBy(r => (r.Object,r.Direction,r.Modifier,r.Region)).Any(g => g.Count() > 1)) throw new FormatException("Duplicate rule");
        Exceptions = Exceptions.Select(s => (s ?? "").Trim().TrimStart('.').ToLowerInvariant()).Where(s => s.Length > 0).Distinct().ToList();
        if (Exceptions.Any(s => Uri.CheckHostName(s) == UriHostNameType.Unknown)) throw new FormatException("Invalid exception domain");
    }
}
public sealed record SuperDragRequest(string Phase = "finish", string Object = "", string Value = "", double Dx = 0, double Dy = 0, string Direction = "", string Modifier = "none", string Region = "page", double ScreenX = 0, double ScreenY = 0);
public static class SuperDrag
{
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    public static readonly string[] Objects = ["text","link","image","element"], Directions = ["up","down","left","right","upLeft","upRight","downLeft","downRight"], Modes = ["4-way","8-way"], Regions = ["page","address","tabs","bookmarks","search"],
        Modifiers = ["none","ctrl","alt","shift","meta","ctrl+alt","ctrl+shift","alt+shift","shift+meta","alt+meta","ctrl+meta","ctrl+alt+shift","alt+shift+meta","ctrl+shift+meta","ctrl+alt+meta","ctrl+alt+shift+meta"],
        Actions = ["none","search","siteSearch","copy","translate","openForegroundTab","openBackgroundTab","download","saveImage","imageSearch","bookmark"];
    public static string Direction(double dx, double dy, string mode) => mode == "4-way"
        ? Math.Abs(dx) > Math.Abs(dy) ? dx > 0 ? "right" : "left" : dy > 0 ? "down" : "up"
        : new[] { "right","downRight","down","downLeft","left","upLeft","up","upRight" }[((int)Math.Floor(Math.Atan2(dy,dx) / (Math.PI / 4) + .5) + 8) % 8];
    public static bool EnabledOn(SuperDragConfig c, string url) => c.Enabled && AddressParser.IsWeb(url) && Uri.TryCreate(url,UriKind.Absolute,out var u) && !new[] {"chromewebstore.google.com","microsoftedge.microsoft.com"}.Contains(u.Host) && !c.Exceptions.Any(h => u.Host.Equals(h,StringComparison.OrdinalIgnoreCase) || u.Host.EndsWith("."+h,StringComparison.OrdinalIgnoreCase));
    public static SuperDragRule? Resolve(SuperDragConfig c, SuperDragRequest p, string page)
    {
        if (!EnabledOn(c,page) || !double.IsFinite(p.Dx) || !double.IsFinite(p.Dy) || Math.Sqrt(p.Dx*p.Dx+p.Dy*p.Dy) < c.MinDistance || p.Value.Length is 0 or > 32768 || !Objects.Contains(p.Object) || !Regions.Contains(p.Region) || !Modifiers.Contains(p.Modifier)) return null;
        if (p.Object is "link" or "image" && !AddressParser.IsWeb(p.Value)) return null;
        var direction = Direction(p.Dx,p.Dy,c.DirectionMode);
        var rule = c.Rules.FirstOrDefault(r => r.Object == p.Object && r.Modifier == p.Modifier && r.Direction == direction && r.Region == p.Region);
        if (rule == null && direction.Any(char.IsUpper)) { direction = Direction(p.Dx,p.Dy,"4-way"); rule = c.Rules.FirstOrDefault(r => r.Object == p.Object && r.Modifier == p.Modifier && r.Direction == direction && r.Region == p.Region); }
        return rule?.Action == "none" ? null : rule;
    }
}
