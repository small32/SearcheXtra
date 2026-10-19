using System.Text.Json;

namespace SearcheXtra.Windows;

internal static class ExtensionPermissions
{
    public static bool DeclaresUserScripts(JsonElement manifest)
    {
        if (manifest.ValueKind != JsonValueKind.Object) return false;
        return new[] { "permissions", "optional_permissions" }.Any(key =>
            manifest.TryGetProperty(key, out var values) && values.ValueKind == JsonValueKind.Array &&
            values.EnumerateArray().Any(value => value.ValueKind == JsonValueKind.String && value.GetString() == "userScripts"));
    }

    public static bool DeclaresUserScripts(string folder)
    {
        try
        {
            using var manifest = JsonDocument.Parse(File.ReadAllText(Path.Combine(folder, "manifest.json")));
            return DeclaresUserScripts(manifest.RootElement);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { return false; }
    }

    public static IReadOnlyList<string> Describe(JsonElement manifest, bool chinese)
    {
        var permissions = new List<string>();
        void Read(JsonElement parent, string key)
        {
            if (parent.TryGetProperty(key, out var values) && values.ValueKind == JsonValueKind.Array)
                permissions.AddRange(values.EnumerateArray().Where(v => v.ValueKind == JsonValueKind.String).Select(v => v.GetString()!));
        }
        Read(manifest, "permissions"); Read(manifest, "host_permissions");
        if (manifest.TryGetProperty("content_scripts", out var scripts) && scripts.ValueKind == JsonValueKind.Array)
            foreach (var script in scripts.EnumerateArray()) Read(script, "matches");
        string Text(string en, string zh) => chinese ? zh : en;
        var result = new List<string>();
        var allSites = permissions.Any(p => p is "<all_urls>" or "*://*/*" or "http://*/*" or "https://*/*");
        if (allSites) result.Add(Text("Read and change data on websites you visit", "读取和更改你访问的网站上的数据"));
        foreach (var permission in permissions.Distinct())
        {
            string description;
            if (permission == "<all_urls>" || permission.Contains("://"))
            {
                if (allSites) continue;
                var host = permission.Split("://", 2).Last().Split('/')[0];
                description = host.StartsWith("*.")
                    ? Text($"Read and change data on {host[2..]} and its subdomains", $"读取和更改 {host[2..]} 及其子域名上的数据")
                    : Text($"Read and change data on {host}", $"读取和更改 {host} 上的数据");
            }
            else description = permission switch
            {
                "downloads" or "downloads.open" or "downloads.shelf" => Text("Manage downloaded files", "管理下载的文件"),
                "storage" or "unlimitedStorage" => Text("Save extension settings and data", "保存扩展设置和数据"),
                "contextMenus" => Text("Add items to right-click menus", "在右键菜单中添加选项"),
                "notifications" => Text("Show notifications", "显示通知"),
                "webRequest" or "webRequestBlocking" or "declarativeNetRequest" or "declarativeNetRequestWithHostAccess" or "declarativeNetRequestFeedback" => Text("Monitor or modify website network requests", "查看或修改网站的网络请求"),
                "tabs" or "webNavigation" => Text("Access tabs and browsing activity", "访问标签页和网页浏览活动"),
                "history" => Text("Read and manage browsing history", "读取和管理浏览历史"),
                "bookmarks" => Text("Read and manage bookmarks", "读取和管理书签"),
                "cookies" => Text("Read and change website sign-in data and cookies", "读取和更改网站的登录状态及 Cookie"),
                "nativeMessaging" => Text("Communicate with other applications on this computer", "与电脑上的其他应用通信"),
                "scripting" or "activeTab" => Text("Run extension features on webpages", "在网页中运行扩展功能"),
                "userScripts" => Text("Run user scripts on webpages", "在网页中运行用户脚本"),
                "sidePanel" => Text("Show an extension side panel", "显示扩展侧边栏"),
                "alarms" => Text("Run scheduled extension tasks", "定时运行扩展任务"),
                "clipboardRead" => Text("Read clipboard contents", "读取剪贴板内容"),
                "clipboardWrite" => Text("Change clipboard contents", "更改剪贴板内容"),
                "management" => Text("Manage installed extensions", "管理已安装的扩展"),
                "privacy" => Text("Change browser privacy settings", "更改浏览器隐私设置"),
                "proxy" => Text("Change network proxy settings", "更改网络代理设置"),
                "debugger" => Text("Inspect and control webpages", "检查和控制网页"),
                "geolocation" => Text("Access your location", "获取你的位置"),
                _ => Text("Use additional browser features", "使用其他浏览器功能")
            };
            if (!result.Contains(description)) result.Add(description);
        }
        return result;
    }
}
