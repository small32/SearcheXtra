using Microsoft.Data.Sqlite;
using System.Text.Json;

namespace SearcheXtra.Windows;

public sealed record ImportResult(List<Bookmark> Bookmarks, List<HistoryEntry> History);
public static class BrowserImport
{
    public static List<HistoryEntry> MergeHistory(IEnumerable<HistoryEntry> existing, IEnumerable<HistoryEntry> incoming)
    {
        var merged = existing.ToList();
        var seen = merged.Select(visit => (visit.Url, visit.Visited)).ToHashSet();
        var added = false;
        foreach (var visit in incoming)
            if (seen.Add((visit.Url, visit.Visited))) { merged.Add(visit); added = true; }
        return added ? merged.OrderByDescending(visit => visit.Visited).Take(10000).ToList() : merged;
    }

    public static List<Bookmark> ChromeBookmarks(string json)
    {
        using var doc = JsonDocument.Parse(json);
        Bookmark? Read(JsonElement node)
        {
            var title = node.TryGetProperty("name", out var name) ? name.GetString() ?? "" : "";
            if (node.TryGetProperty("children", out var children)) return new() { Title = title, Children = children.EnumerateArray().Select(Read).OfType<Bookmark>().ToList() };
            if (node.TryGetProperty("url", out var url) && AddressParser.IsWeb(url.GetString() ?? "")) return new() { Title = title, Url = url.GetString() };
            return null;
        }
        return doc.RootElement.GetProperty("roots").EnumerateObject().Select(p => Read(p.Value)).OfType<Bookmark>().ToList();
    }
    public static async Task<ImportResult> ProfileAsync(string folder)
    {
        var bookmarks = new List<Bookmark>(); var history = new List<HistoryEntry>();
        var chromeBookmarks = Path.Combine(folder, "Bookmarks"); var firefox = Path.Combine(folder, "places.sqlite");
        if (File.Exists(chromeBookmarks)) bookmarks.AddRange(ChromeBookmarks(await File.ReadAllTextAsync(chromeBookmarks)));
        var db = File.Exists(firefox) ? firefox : Path.Combine(folder, "History");
        if (!File.Exists(db)) return new(bookmarks, history);
        await using var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = db, Mode = SqliteOpenMode.ReadOnly }.ToString()); await connection.OpenAsync();
        if (File.Exists(firefox))
        {
            using var query = connection.CreateCommand(); query.CommandText = "SELECT b.id,b.parent,b.type,COALESCE(b.title,''),p.url,b.guid FROM moz_bookmarks b LEFT JOIN moz_places p ON b.fk=p.id WHERE b.type IN (1,2) ORDER BY b.position,b.id";
            using var reader = await query.ExecuteReaderAsync();
            var bookmarkRows = new List<FirefoxBookmark>();
            while (await reader.ReadAsync()) bookmarkRows.Add(new(reader.GetInt64(0), reader.GetInt64(1), reader.GetInt32(2), reader.GetString(3), reader.IsDBNull(4) ? null : reader.GetString(4), reader.IsDBNull(5) ? "" : reader.GetString(5)));
            var byParent = bookmarkRows.ToLookup(item => item.Parent);
            var ids = bookmarkRows.Select(item => item.Id).ToHashSet();
            var visited = new HashSet<long>();
            List<Bookmark> Read(IEnumerable<FirefoxBookmark> items)
            {
                var result = new List<Bookmark>();
                foreach (var item in items)
                {
                    if (item.Guid == "tags________" || !visited.Add(item.Id)) continue;
                    if (item.Type == 1)
                    {
                        if (AddressParser.IsWeb(item.Url ?? "")) result.Add(new() { Title = item.Title, Url = item.Url });
                        continue;
                    }
                    var children = byParent[item.Id];
                    // Internal containers are flattened; the bookmarks inside retain their order.
                    if (item.Guid == "root________") children = children.OrderBy(child => child.Guid switch { "toolbar_____" => 0, "menu________" => 1, _ => 2 });
                    var nested = Read(children);
                    if (item.Guid is "root________" or "toolbar_____" or "menu________") result.AddRange(nested);
                    else if (nested.Count > 0 || item.Guid is not ("unfiled_____" or "mobile______"))
                        result.Add(new() { Title = item.Title.Length > 0 ? item.Title : item.Guid switch { "unfiled_____" => "Other", "mobile______" => "Mobile", _ => "Folder" }, Children = nested });
                }
                return result;
            }
            bookmarks.AddRange(Read(bookmarkRows.Where(item => !ids.Contains(item.Parent))));
        }
        using var visits = connection.CreateCommand(); visits.CommandText = File.Exists(firefox) ? "SELECT url,COALESCE(title,''),last_visit_date FROM moz_places WHERE last_visit_date IS NOT NULL ORDER BY last_visit_date DESC LIMIT 10000" : "SELECT url,COALESCE(title,''),last_visit_time FROM urls ORDER BY last_visit_time DESC LIMIT 10000";
        using var rows = await visits.ExecuteReaderAsync();
        while (await rows.ReadAsync()) { var url = rows.GetString(0); if (!AddressParser.IsWeb(url)) continue; var milliseconds = rows.GetInt64(2) / 1000 - (File.Exists(firefox) ? 0 : 11644473600000L); if (milliseconds < -62135596800000L || milliseconds > 253402300799999L) continue; history.Add(new(url, rows.GetString(1), DateTimeOffset.FromUnixTimeMilliseconds(milliseconds))); }
        return new(bookmarks, history);
    }
    private sealed record FirefoxBookmark(long Id, long Parent, int Type, string Title, string? Url, string Guid);
}
