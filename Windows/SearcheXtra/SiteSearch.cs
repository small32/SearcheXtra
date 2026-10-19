using System.Text.Json;
using System.Xml.Linq;
namespace SearcheXtra.Windows;
public sealed record SearchSite(string Name, string Host, string Template, string[] Aliases);
public static class SiteSearch
{
    private static readonly HttpClient Client = new(new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false }) { Timeout = TimeSpan.FromSeconds(10) };
    public static readonly SearchSite[] BuiltIn = [
        new("Reddit", "reddit.com", "https://www.reddit.com/search/?q=%s", []),
        new("YouTube", "youtube.com", "https://www.youtube.com/results?search_query=%s", ["yt"]),
        new("X", "x.com", "https://x.com/search?q=%s", ["twitter"]),
        new("ChatGPT", "chatgpt.com", "https://chatgpt.com/?q=%s", ["gpt", "openai"]),
        new("Claude", "claude.ai", "https://claude.ai/new?q=%s", []),
        new("Perplexity", "perplexity.ai", "https://www.perplexity.ai/search?q=%s", []),
        new("Wikipedia", "wikipedia.org", "https://" + System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName + ".wikipedia.org/w/index.php?search=%s", ["wiki"]),
        new("GitHub", "github.com", "https://github.com/search?q=%s", ["gh"]),
        new("Stack Overflow", "stackoverflow.com", "https://stackoverflow.com/search?q=%s", ["so"]),
        new("MDN", "developer.mozilla.org", "https://developer.mozilla.org/search?q=%s", []),
        new("Amazon", "amazon.com", "https://www.amazon.com/s?k=%s", []),
        new("Google Maps", "google.com/maps", "https://www.google.com/maps/search/%s", ["maps"]),
        new("IMDb", "imdb.com", "https://www.imdb.com/find/?q=%s", []),
        new("Spotify", "open.spotify.com", "https://open.spotify.com/search/%s", []),
        new("Figma Community", "figma.com/community", "https://www.figma.com/community/search?resource_type=mixed&sort_by=relevancy&query=%s", [])
    ];
    public static SearchSite? Match(BrowserSettings settings, string typed)
    {
        var word = typed.Trim().ToLowerInvariant(); if (word.Length < 2 || word.Any(char.IsWhiteSpace) || word.Contains('/')) return null;
        return BuiltIn.Where(s => new[] { s.Name.Replace(" ", "").ToLowerInvariant(), s.Host }.Concat(s.Aliases).Any(n => n.StartsWith(word))).OrderBy(s => s.Name.Length).FirstOrDefault()
            ?? settings.LearnedSearchSites.Where(s => s.Host.StartsWith(word, StringComparison.OrdinalIgnoreCase)).OrderBy(s => s.Host.Length).FirstOrDefault();
    }
    public static async Task LearnAsync(BrowserSettings settings, Uri page, string description)
    {
        if (page.Scheme != "https" || page.AbsolutePath != "/" || !Uri.TryCreate(description, UriKind.Absolute, out var address) || address.Scheme != "https" || address.Host != page.Host || settings.LearnedSearchSites.Any(s => s.Host == page.Host)) return;
        try
        {
            using var response = await Client.GetAsync(address, HttpCompletionOption.ResponseHeadersRead); if (!response.IsSuccessStatusCode) return;
            await using var stream = await response.Content.ReadAsStreamAsync(); var bytes = new byte[65537]; var count = 0; int n;
            while (count < bytes.Length && (n = await stream.ReadAsync(bytes.AsMemory(count))) > 0) count += n;
            if (count == bytes.Length) return;
            using var xmlStream = new MemoryStream(bytes, 0, count); using var reader = System.Xml.XmlReader.Create(xmlStream, new() { DtdProcessing = System.Xml.DtdProcessing.Prohibit, XmlResolver = null }); var xml = XDocument.Load(reader);
            var template = xml.Descendants().Where(e => e.Name.LocalName == "Url" && (string?)e.Attribute("type") == "text/html").Select(e => (string?)e.Attribute("template")).FirstOrDefault();
            if (template == null) return; template = template.Replace("{searchTerms}", "%s");
            if (template.Contains('{') || template.Split("%s").Length != 2 || !Uri.TryCreate(template.Replace("%s", "test"), UriKind.Absolute, out var search) || search.Scheme != "https" || search.Host != page.Host) return;
            settings.LearnedSearchSites.Add(new(page.Host, page.Host, template, [])); if (settings.LearnedSearchSites.Count > 40) settings.LearnedSearchSites.RemoveAt(0);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or System.Xml.XmlException) { }
    }
}
