using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using global::Windows.Storage.Streams;

namespace SearcheXtra.Windows;

// Called on the UI thread so decoded images can be shared by bookmark controls.
public sealed class BookmarkIcons
{
    public static BookmarkIcons Shared { get; } = new();
    private static readonly HttpClient Client = new(new HttpClientHandler { UseCookies = false }) { Timeout = TimeSpan.FromSeconds(12) };
    private static readonly Regex Tags = new(@"<(?:base|link)\b[^>]*>", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex Attributes = new("""(?<name>[\w:-]+)\s*=\s*(?:"(?<value>[^"]*)"|'(?<value>[^']*)'|(?<value>[^\s"'=<>`]+))""", RegexOptions.Compiled);
    private readonly Dictionary<string, Entry> entries = new(StringComparer.Ordinal);
    private static string CacheFolder => Path.Combine(DataStore.Root, "bookmark-icons");
    public event Action<string>? Changed;

    private sealed class Entry
    {
        public Task<ImageSource?>? Image;
        public string? Source;
        public int Revision;
        public int Adoption;
        public readonly SemaphoreSlim WriteGate = new(1);
    }
    private sealed record StoredIcon(string Source);

    public Task<ImageSource?> GetAsync(string pageUrl)
    {
        if (!TryPage(pageUrl, out var page, out var origin)) return Task.FromResult<ImageSource?>(null);
        if (!entries.TryGetValue(origin, out var entry)) entries[origin] = entry = new();
        return entry.Image ??= LoadAsync(page!, origin, entry, entry.Revision);
    }

    public string? SourceUrl(string pageUrl) => TryPage(pageUrl, out _, out var origin) && entries.TryGetValue(origin, out var entry) ? entry.Source : null;
    internal static string? OriginFor(string pageUrl) => TryPage(pageUrl, out _, out var origin) ? origin : null;

    public async Task AdoptAsync(string pageUrl, string iconUrl, byte[] png, bool persist = true)
    {
        if (!TryPage(pageUrl, out _, out var origin) || png.Length == 0) return;
        if (!entries.TryGetValue(origin, out var entry)) entries[origin] = entry = new();
        var adoption = ++entry.Adoption;
        var image = await DecodeAsync(png);
        if (image == null || entry.Adoption != adoption) return;
        var revision = ++entry.Revision;
        entry.Source = iconUrl;
        entry.Image = Task.FromResult<ImageSource?>(image);
        Changed?.Invoke(origin);
        if (persist) await PersistAsync(origin, entry, revision, iconUrl, png);
    }

    private async Task<ImageSource?> LoadAsync(Uri page, string origin, Entry entry, int revision)
    {
        var key = Key(origin);
        try
        {
            var data = await File.ReadAllBytesAsync(Path.Combine(CacheFolder, key + ".bin"));
            var saved = JsonSerializer.Deserialize<StoredIcon>(await File.ReadAllTextAsync(Path.Combine(CacheFolder, key + ".json")));
            var cached = await DecodeAsync(data);
            if (cached != null && saved != null)
            {
                if (entry.Revision != revision) return await entry.Image!;
                entry.Source = saved.Source;
                return cached;
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException) { }

        foreach (var icon in await IconCandidatesAsync(page))
        {
            var bytes = await FetchAsync(icon, 4 * 1024 * 1024);
            if (bytes == null || await DecodeAsync(bytes) is not { } image) continue;
            if (entry.Revision != revision) return await entry.Image!;
            entry.Source = icon.AbsoluteUri;
            await PersistAsync(origin, entry, revision, icon.AbsoluteUri, bytes);
            return entry.Revision == revision ? image : await entry.Image!;
        }
        return entry.Revision == revision ? null : await entry.Image!;
    }

    private static async Task<List<Uri>> IconCandidatesAsync(Uri page)
    {
        var icons = new List<Uri>();
        var touchIcons = new List<Uri>();
        var finalPage = page;
        try
        {
            using var response = await Client.GetAsync(page, HttpCompletionOption.ResponseHeadersRead);
            finalPage = response.RequestMessage?.RequestUri ?? page;
            if (response.IsSuccessStatusCode && await ReadAsync(response, 1024 * 1024, truncate: true) is { } bytes)
            {
                var html = Encoding.UTF8.GetString(bytes);
                var basis = finalPage;
                var tags = Tags.Matches(html).Select(m => m.Value).ToList();
                foreach (var tag in tags.Where(t => t.StartsWith("<base", StringComparison.OrdinalIgnoreCase)))
                {
                    var attributes = ReadAttributes(tag);
                    if (attributes.TryGetValue("href", out var href) && Uri.TryCreate(basis, href, out var address) && IsWeb(address)) { basis = address; break; }
                }
                foreach (var tag in tags.Where(t => t.StartsWith("<link", StringComparison.OrdinalIgnoreCase)))
                {
                    var attributes = ReadAttributes(tag);
                    if (!attributes.TryGetValue("href", out var href) || !attributes.TryGetValue("rel", out var rel) || !Uri.TryCreate(basis, href, out var address) || !IsWeb(address)) continue;
                    var relations = rel.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
                    if (relations.Contains("icon", StringComparer.OrdinalIgnoreCase)) icons.Add(address);
                    else if (relations.Any(r => r.Equals("apple-touch-icon", StringComparison.OrdinalIgnoreCase) || r.Equals("apple-touch-icon-precomposed", StringComparison.OrdinalIgnoreCase))) touchIcons.Add(address);
                }
            }
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException or TaskCanceledException) { }
        icons.AddRange(touchIcons);
        icons.Add(new Uri(finalPage.GetLeftPart(UriPartial.Authority) + "/favicon.ico"));
        return icons.Distinct().ToList();
    }

    private static Dictionary<string, string> ReadAttributes(string tag)
    {
        var attributes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (Match match in Attributes.Matches(tag)) attributes.TryAdd(match.Groups["name"].Value, WebUtility.HtmlDecode(match.Groups["value"].Value));
        return attributes;
    }

    private static async Task<byte[]?> FetchAsync(Uri uri, int limit)
    {
        try
        {
            using var response = await Client.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead);
            return response.IsSuccessStatusCode ? await ReadAsync(response, limit) : null;
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException or TaskCanceledException) { return null; }
    }

    private static async Task<byte[]?> ReadAsync(HttpResponseMessage response, int limit, bool truncate = false)
    {
        await using var stream = await response.Content.ReadAsStreamAsync();
        using var bytes = new MemoryStream();
        var buffer = new byte[8192];
        int count;
        while ((count = await stream.ReadAsync(buffer.AsMemory(0, Math.Min(buffer.Length, limit + 1 - (int)bytes.Length)))) > 0)
        {
            bytes.Write(buffer, 0, count);
            if (bytes.Length > limit) return truncate ? bytes.ToArray()[..limit] : null;
        }
        return bytes.ToArray();
    }

    private static async Task<ImageSource?> DecodeAsync(byte[] bytes)
    {
        try
        {
            using var stream = new InMemoryRandomAccessStream();
            using (var writer = new DataWriter(stream)) { writer.WriteBytes(bytes); await writer.StoreAsync(); writer.DetachStream(); }
            stream.Seek(0);
            if (Encoding.UTF8.GetString(bytes, 0, Math.Min(bytes.Length, 512)).Contains("<svg", StringComparison.OrdinalIgnoreCase))
            {
                var svg = new SvgImageSource();
                return await svg.SetSourceAsync(stream) == SvgImageSourceLoadStatus.Success ? svg : null;
            }
            var bitmap = new BitmapImage { DecodePixelWidth = 32 };
            await bitmap.SetSourceAsync(stream);
            return bitmap;
        }
        catch (Exception ex) when (ex is ArgumentException or InvalidOperationException or System.Runtime.InteropServices.COMException) { return null; }
    }

    private static async Task PersistAsync(string origin, Entry entry, int revision, string source, byte[] bytes)
    {
        await entry.WriteGate.WaitAsync();
        try
        {
            if (entry.Revision != revision) return;
            Directory.CreateDirectory(CacheFolder);
            var path = Path.Combine(CacheFolder, Key(origin));
            await File.WriteAllBytesAsync(path + ".bin.tmp", bytes);
            File.Move(path + ".bin.tmp", path + ".bin", true);
            await File.WriteAllTextAsync(path + ".json.tmp", JsonSerializer.Serialize(new StoredIcon(source)));
            File.Move(path + ".json.tmp", path + ".json", true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
        finally { entry.WriteGate.Release(); }
    }

    private static string Key(string origin) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(origin))).ToLowerInvariant();
    private static bool IsWeb(Uri address) => address.Scheme is "http" or "https";
    private static bool TryPage(string pageUrl, out Uri? page, out string origin)
    {
        origin = "";
        if (!Uri.TryCreate(pageUrl, UriKind.Absolute, out page) || !IsWeb(page)) return false;
        origin = new UriBuilder(page.Scheme, page.IdnHost, page.IsDefaultPort ? -1 : page.Port).Uri.GetLeftPart(UriPartial.Authority);
        return true;
    }
}
