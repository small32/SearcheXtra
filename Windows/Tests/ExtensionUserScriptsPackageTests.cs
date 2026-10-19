using System.Text.Json.Nodes;
using SearcheXtra.Windows;

public static class ExtensionUserScriptsPackageTests
{
    public static void Run(Action<bool, string> check)
    {
        var root = Path.Combine(Path.GetTempPath(), "SearcheXtra-user-scripts-package-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path.Combine(root, "worker"));
        Directory.CreateDirectory(Path.Combine(root, "pages"));
        const string manifest = """{"manifest_version":3,"name":"User script fixture","version":"1.0","permissions":["userScripts"],"host_permissions":["https://example.com/*"],"background":{"service_worker":"worker/background.js"}}""";
        const string worker = "importScripts('./dependency.js');\nself.extensionStarted = true;";
        const string html = "<!doctype html><html><head><script src=\"app.js\"></script></head><body>fixture</body></html>";
        File.WriteAllText(Path.Combine(root, "manifest.json"), manifest);
        File.WriteAllText(Path.Combine(root, "worker/background.js"), worker);
        File.WriteAllText(Path.Combine(root, "pages/options.html"), html);
        check(ExtensionUserScriptsPackage.Prepare(root, "first-token"), "MV3 userScripts package receives compatibility bootstrap");
        var patchedWorker = File.ReadAllText(Path.Combine(root, "worker/background.js"));
        var patchedHtml = File.ReadAllText(Path.Combine(root, "pages/options.html"));
        var patchedManifest = File.ReadAllText(Path.Combine(root, "manifest.json"));
        check(patchedWorker.EndsWith(worker) && patchedWorker.IndexOf("searchextra-user-scripts/client.js", StringComparison.Ordinal) < patchedWorker.IndexOf("dependency.js", StringComparison.Ordinal), "Bootstrap executes before original classic worker and preserves relative import base");
        check(patchedHtml.IndexOf("searchextra-user-scripts/client.js", StringComparison.Ordinal) < patchedHtml.IndexOf("app.js", StringComparison.Ordinal), "Extension page bootstrap precedes vendor scripts");
        var amended = JsonNode.Parse(patchedManifest)!;
        check(amended["background"]!["service_worker"]!.GetValue<string>() == "worker/background.js", "Original service worker path and extension identity remain stable");
        check(amended["content_scripts"]![0]!["matches"]!.AsArray().Single()!.GetValue<string>() == "https://example.com/*", "Native identity context does not expand declared host access");
        ExtensionUserScriptsPackage.Prepare(root, "second-token");
        check(File.ReadAllText(Path.Combine(root, "worker/background.js")) == patchedWorker && File.ReadAllText(Path.Combine(root, "pages/options.html")) == patchedHtml && File.ReadAllText(Path.Combine(root, "manifest.json")) == patchedManifest, "Repeated preparation is idempotent without duplicate scripts");
        check(File.ReadAllText(Path.Combine(root, "searchextra-user-scripts/bridge.js")).Contains("second-token"), "Bridge token rotates without regenerating extension identity");
        var bridgePath = Path.Combine(root, ExtensionUserScriptsPackage.BridgePath);
        var bridgeJs = Path.Combine(root, "searchextra-user-scripts/bridge.js");
        var beforeWriteTime = File.GetLastWriteTimeUtc(bridgeJs);
        var token = ExtensionUserScriptsPackage.TokenFor(root);
        ExtensionUserScriptsPackage.Prepare(root, token);
        check(token == "second-token" && File.GetLastWriteTimeUtc(bridgeJs) == beforeWriteTime && File.Exists(bridgePath), "Browser restart retains bridge token and does not rewrite unchanged installed extension files");
        const string changedWorker = "self.vendorUpdated = true;";
        File.WriteAllText(Path.Combine(root, "worker/background.js"), changedWorker);
        ExtensionUserScriptsPackage.Prepare(root, "third-token");
        check(File.ReadAllText(Path.Combine(root, "worker/background.js")).EndsWith(changedWorker), "In-place vendor update is preserved instead of restoring stale backup");
        var moduleRoot = Path.Combine(root, "module"); Directory.CreateDirectory(moduleRoot);
        File.WriteAllText(Path.Combine(moduleRoot, "manifest.json"), manifest.Replace("\"service_worker\":\"worker/background.js\"", "\"service_worker\":\"background.js\",\"type\":\"module\""));
        File.WriteAllText(Path.Combine(moduleRoot, "background.js"), "import './dependency.js';");
        ExtensionUserScriptsPackage.Prepare(moduleRoot, "module-token");
        check(File.ReadAllText(Path.Combine(moduleRoot, "background.js")).Contains("import '/searchextra-user-scripts/client.js';"), "Module worker uses ordered static imports supported by service workers");
        var legacyRoot = Path.Combine(root, "legacy"); Directory.CreateDirectory(legacyRoot);
        var legacyManifest = manifest.Replace("\"manifest_version\":3", "\"manifest_version\":2");
        File.WriteAllText(Path.Combine(legacyRoot, "manifest.json"), legacyManifest);
        check(!ExtensionUserScriptsPackage.Prepare(legacyRoot, "unused") && File.ReadAllText(Path.Combine(legacyRoot, "manifest.json")) == legacyManifest, "MV2 packages stay untouched by MV3 compatibility preparation");
    }
}
