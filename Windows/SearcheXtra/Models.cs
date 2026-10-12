using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;

namespace SearcheXtra.Windows;

public enum BookmarkOpening { Default, Background, Foreground }
public sealed record Login(string Origin, string Username, string Password);
public sealed class BrowserSettings
{
    public SuperDragConfig SuperDrag { get; set; } = new();
    public string Language { get; set; } = "system";
    public string Theme { get; set; } = "system";
    public bool Sidebar { get; set; }
    public bool BookmarksBar { get; set; }
    public bool SidebarRight { get; set; }
    public double SidebarWidth { get; set; } = 232;
    public bool SidebarAutoHide { get; set; }
    public bool IconGlyphs { get; set; }
    public bool NavigationLeft { get; set; }
    public bool ListsPins { get; set; }
    public bool UsesSpaces { get; set; } = true;
    public bool UsesTabGroups { get; set; } = true;
    public bool SplitView { get; set; } = true;
    public bool ShowsReading { get; set; } = true;
    public bool ShowsLinks { get; set; } = true;
    public bool PeeksLinks { get; set; } = true;
    public bool AddressCommands { get; set; }
    public List<SearchSite> LearnedSearchSites { get; set; } = [];
    public bool SearchesSites { get; set; }
    public bool Autocorrect { get; set; } = true;
    public bool FastPages { get; set; }
    public bool HoldsHistory { get; set; }
    public bool FloatFlicks { get; set; } = true;
    public bool FloatsAway { get; set; }
    public bool LittleLinks { get; set; }
    public bool Bench { get; set; }
    public bool PreventTracking { get; set; } = true;
    public bool AutoScroll { get; set; }
    public bool WaitsForPlay { get; set; }
    public bool FloatsOnLeave { get; set; }
    public bool SavesPasswords { get; set; } = true;
    public bool FillsPasswords { get; set; } = true;
    public bool SiteNotifications { get; set; } = true;
    public bool Passkeys { get; set; } = true;
    public bool AskDownloadLocation { get; set; }
    public bool AlwaysShowsDownloads { get; set; }
    public double PageZoom { get; set; } = 1;
    public string SettingsPage { get; set; } = "general";
    public List<SearchKeyword> Keywords { get; set; } = [];
    public Dictionary<string, string> Shortcuts { get; set; } = [];
    public Dictionary<string, SitePreferences> Sites { get; set; } = [];
    public List<string> RemovedExtensionIds { get; set; } = [];
    public Dictionary<string, string> SpaceProfiles { get; set; } = [];
    public List<InstalledExtension> Extensions { get; set; } = [];
    public Dictionary<string, Dictionary<string, string>> ProfileExtensionFolders { get; set; } = [];
    public bool ExtensionsInPrivate { get; set; }
    public bool CompactBookmarksBar { get; set; }
    public bool BookmarkBarFolderIcons { get; set; } = true;
    public bool BookmarkWebsiteIcons { get; set; } = true;
    public BookmarkOpening BookmarkOpening { get; set; }
    public bool LazyBackgroundTabs { get; set; } = true;
    public bool SuspendTabs { get; set; } = true;
    public int SuspendAfterMinutes { get; set; } = 10;
    public bool BlockTrackers { get; set; } = true;
    public bool RestoreSession { get; set; } = true;
    public string StartPage { get; set; } = "";
    public string SearchTemplate { get; set; } = "https://www.bing.com/search?q={0}";
    public string DownloadsFolder { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
    public List<string> ExtensionFolders { get; set; } = [];
}
public sealed record SearchKeyword(string Keyword, string Template);
public sealed class SitePreferences
{
    public double? Zoom { get; set; }
    public bool? BlockTrackers { get; set; }
    public Dictionary<string, string> Permissions { get; set; } = [];
}
public sealed class InstalledExtension
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Version { get; set; } = "";
    public string Folder { get; set; } = "";
    public int ManifestVersion { get; set; }
    public string? StoreId { get; set; }
    public bool Enabled { get; set; } = true;
    public bool Pinned { get; set; }
    public string Popup { get; set; } = "";
    public string Options { get; set; } = "";
    public string NewTab { get; set; } = "";
}
public sealed class Bookmark
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = "";
    public string? Url { get; set; }
    public List<Bookmark>? Children { get; set; }
}
public sealed record HistoryEntry(string Url, string Title, DateTimeOffset Visited);
public sealed record DownloadRecord(string Path, string Url, DateTimeOffset Date);
public sealed record SavedTab(string Url, string Title, bool Pinned, string Space, string Group = "")
{
    [System.Text.Json.Serialization.JsonIgnore] public Guid? ClosedBatch { get; init; }
    [System.Text.Json.Serialization.JsonIgnore] public int ClosedIndex { get; init; } = -1;
    [System.Text.Json.Serialization.JsonIgnore] public bool WasActive { get; init; }
}
public sealed class SessionState
{
    public List<SavedTab> Tabs { get; set; } = [];
    public int ActiveIndex { get; set; }
    public string Space { get; set; } = "Default";
    public int[] SplitIndices { get; set; } = [];
    public double SplitRatio { get; set; } = .5;
}
public sealed class BrowserTab : INotifyPropertyChanged
{
    public Guid Id { get; } = Guid.NewGuid();
    private string title = "", url = "", group = "", icon = "";
    private double reading;
    private bool useIcons;
    private bool loading, pinned, sleeping;
    public string Title { get => title; set { if (title == value) return; title = value; Changed(); Changed(nameof(DisplayTitle)); Changed(nameof(Letter)); Changed(nameof(LetterDisplay)); Changed(nameof(Label)); } }
    public string Url { get => url; set { if (url == value) return; url = value; Changed(); } }
    public bool Loading { get => loading; set { if (loading == value) return; loading = value; Changed(); Changed(nameof(DisplayTitle)); Changed(nameof(Letter)); Changed(nameof(Label)); } }
    public bool Pinned { get => pinned; set { if (pinned == value) return; pinned = value; Changed(); Changed(nameof(DisplayTitle)); Changed(nameof(Letter)); Changed(nameof(Label)); } }
    public bool Sleeping { get => sleeping; set { if (sleeping == value) return; sleeping = value; Changed(); Changed(nameof(DisplayTitle)); Changed(nameof(Letter)); Changed(nameof(Label)); } }
    public bool IsPrivate { get; init; }
    public string Letter => (string.IsNullOrWhiteSpace(Title) ? "S" : Title.Trim()[..1]).ToUpperInvariant();
    public string Label => string.IsNullOrWhiteSpace(Title) ? "SearcheXtra" : Title;
    public string Favicon { get => icon; set { if (icon == value) return; icon = value; Changed(); Changed(nameof(LetterDisplay)); } }
    public bool UseIcons { get => useIcons; set { if (useIcons == value) return; useIcons = value; Changed(); Changed(nameof(LetterDisplay)); } }
    public string LetterDisplay => UseIcons && Favicon.Length > 0 ? "" : Letter;
    public double Reading { get => reading; set { if (reading == value) return; reading = value; Changed(); } }
    public string Space { get; set; } = "Default";
    public string Group { get => group; set { if (group == value) return; group = value; Changed(); Changed(nameof(DisplayTitle)); Changed(nameof(Letter)); Changed(nameof(Label)); } }
    public string DisplayTitle => $"{(Pinned ? "● " : "")}{(IsPrivate ? "◈ " : "")}{(Group.Length > 0 ? "[" + Group + "] " : "")}{(Loading ? "↻ " : Sleeping ? "◌ " : "")}{(string.IsNullOrWhiteSpace(Title) ? "SearcheXtra" : Title)}";
    [JsonIgnore] public DateTimeOffset LastUsed { get; set; } = DateTimeOffset.Now;
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Changed([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}
public static class AddressParser
{
    public static Uri Resolve(string input, string searchTemplate)
    {
        input = input.Trim();
        if (input.Length == 0) return new("about:blank");
        if (Uri.TryCreate(input, UriKind.Absolute, out var uri) && uri.Scheme is "https" or "http" or "about") return uri;
        if (!input.Any(char.IsWhiteSpace) && (input.Contains('.') || input.StartsWith("localhost", StringComparison.OrdinalIgnoreCase)))
        {
            var scheme = input.StartsWith("localhost", StringComparison.OrdinalIgnoreCase) || input.StartsWith("127.") ? "http://" : "https://";
            if (Uri.TryCreate(scheme + input, UriKind.Absolute, out uri)) return uri;
        }
        return new Uri(searchTemplate.Replace("{0}", Uri.EscapeDataString(input)));
    }
    public static bool IsWeb(string url) => Uri.TryCreate(url, UriKind.Absolute, out var u) && u.Scheme is "http" or "https";
}
