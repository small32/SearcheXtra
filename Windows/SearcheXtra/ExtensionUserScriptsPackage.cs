using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace SearcheXtra.Windows;

/// <summary>Installs a narrowly scoped bridge without relocating the extension or its worker.</summary>
public static class ExtensionUserScriptsPackage
{
    public const string BridgePath = "searchextra-user-scripts/bridge.html";
    public const string Version = "1";
    private const string DirectoryName = "searchextra-user-scripts";
    private const string Marker = "/* SearcheXtra userScripts bootstrap */";
    private sealed record ModifiedFile(string Original, string PatchedHash);
    private sealed record Preparation(string Version, Dictionary<string, ModifiedFile> Files, string? Token = null);

    // Keep the bridge stable between browser launches. Rewriting an installed
    // extension on every launch would force Chromium to reload it unnecessarily.
    public static string TokenFor(string folder)
    {
        var statePath = Path.Combine(folder, DirectoryName, "preparation.json");
        var previous = File.Exists(statePath) ? JsonSerializer.Deserialize<Preparation>(File.ReadAllText(statePath)) : null;
        return previous?.Token is { Length: > 0 } token ? token : Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
    }

    public static bool Prepare(string folder, string token)
    {
        var root = CrxInstaller.ValidateFolder(folder);
        var generated = Path.Combine(root, DirectoryName);
        var statePath = Path.Combine(generated, "preparation.json");
        var previous = File.Exists(statePath) ? JsonSerializer.Deserialize<Preparation>(File.ReadAllText(statePath)) : null;
        if (Directory.Exists(generated) && previous == null) throw new InvalidDataException("The extension uses a reserved user script bridge path.");
        string Original(string relative)
        {
            var current = File.ReadAllText(SafePath(root, relative));
            return previous?.Files.TryGetValue(relative, out var item) == true && item.PatchedHash == Hash(current) ? item.Original : current;
        }
        var manifestText = Original("manifest.json");
        using var manifest = JsonDocument.Parse(manifestText);
        var mv3 = manifest.RootElement.TryGetProperty("manifest_version", out var version) && version.GetInt32() == 3;
        if (!mv3 || !ExtensionPermissions.DeclaresUserScripts(manifest.RootElement)) return false;
        Directory.CreateDirectory(generated);
        var files = new Dictionary<string, ModifiedFile>();
        void Patch(string relative, string original, string patched)
        {
            files[relative] = new(original, Hash(patched));
            WriteIfChanged(SafePath(root, relative), patched);
        }
        // A native content context gives CDP a real extension identity. Its
        // match patterns stay within this package's existing declared access.
        var amended = JsonNode.Parse(manifestText)!.AsObject();
        var matches = new HashSet<string>(StringComparer.Ordinal);
        if (amended["host_permissions"] is JsonArray hosts) foreach (var host in hosts) if (host?.GetValue<string>() is { } match) matches.Add(match);
        if (amended["content_scripts"] is JsonArray contents) foreach (var content in contents) if (content?["matches"] is JsonArray patterns) foreach (var pattern in patterns) if (pattern?.GetValue<string>() is { } match) matches.Add(match);
        if (matches.Count > 0)
        {
            var contentsArray = amended["content_scripts"] as JsonArray ?? new JsonArray();
            if (amended["content_scripts"] == null) amended["content_scripts"] = contentsArray;
            contentsArray.Add(new JsonObject { ["matches"] = new JsonArray(matches.Select(match => JsonValue.Create(match)).ToArray()), ["js"] = new JsonArray(DirectoryName + "/identity.js"), ["run_at"] = "document_start", ["all_frames"] = true, ["match_about_blank"] = true });
            Patch("manifest.json", manifestText, amended.ToJsonString());
        }
        if (manifest.RootElement.TryGetProperty("background", out var background) && background.TryGetProperty("service_worker", out var worker) && worker.GetString() is { Length: > 0 } workerPath)
        {
            var original = Original(workerPath);
            var module = background.TryGetProperty("type", out var type) && type.GetString() == "module";
            var bootstrap = module ? $"import '/{DirectoryName}/client.js';" : $"importScripts(chrome.runtime.getURL('{DirectoryName}/client.js'));";
            Patch(workerPath, original, Marker + "\n" + bootstrap + "\n" + original);
        }
        foreach (var html in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories).Where(p => Path.GetExtension(p).Equals(".html", StringComparison.OrdinalIgnoreCase) || Path.GetExtension(p).Equals(".htm", StringComparison.OrdinalIgnoreCase)).ToArray())
        {
            if (html.StartsWith(generated + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) continue;
            var relative = Path.GetRelativePath(root, html);
            var original = Original(relative);
            var tag = $"<script src=\"/{DirectoryName}/client.js\"></script>";
            var head = Regex.Match(original, @"<head\b[^>]*>", RegexOptions.IgnoreCase);
            var position = head.Success ? head.Index + head.Length : Regex.Match(original, @"<script\b", RegexOptions.IgnoreCase) is { Success: true } script ? script.Index : 0;
            Patch(relative, original, original.Insert(position, tag));
        }
        WriteIfChanged(Path.Combine(generated, "client.js"), File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Assets", "extension-user-scripts.js")));
        WriteIfChanged(Path.Combine(generated, "identity.js"), "/* Native extension context for the SearcheXtra userScripts host. */\nvoid 0;\n");
        WriteIfChanged(Path.Combine(generated, "bridge.html"), "<!doctype html><meta charset=\"utf-8\"><title>SearcheXtra user scripts</title><script src=\"bridge.js\"></script>");
        WriteIfChanged(Path.Combine(generated, "bridge.js"), BridgeScript.Replace("__TOKEN_JSON__", JsonSerializer.Serialize(token)));
        WriteIfChanged(statePath, JsonSerializer.Serialize(new Preparation(Version, files, token)));
        return true;
    }

    private static void WriteIfChanged(string path, string text)
    {
        if (!File.Exists(path) || File.ReadAllText(path) != text) File.WriteAllText(path, text, new UTF8Encoding(false));
    }

    private static string Hash(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text)));
    private static string SafePath(string root, string relative)
    {
        var path = Path.GetFullPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)));
        if (!path.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Invalid extension script path.");
        return path;
    }

    private const string BridgeScript = """
    (() => {
      'use strict';
      const runtime = chrome.runtime, marker = '__searchextraUserScripts', token = __TOKEN_JSON__;
      const pending = new Map(), ports = new Map();
      const host = packet => chrome.webview.postMessage({ ...packet, token, extensionId: runtime.id });
      runtime.onMessage.addListener((packet, sender, sendResponse) => {
        if (sender.id !== runtime.id || packet?.[marker] !== 1 || typeof packet.api !== 'string') return;
        const requestId = crypto.randomUUID();
        const timeout = setTimeout(() => { pending.delete(requestId); sendResponse({ [marker]: 1, error: 'The user script request timed out.' }); }, 60000);
        pending.set(requestId, { sendResponse, timeout });
        host({ kind: 'extensionUserScripts', requestId, api: packet.api, args: packet.args, sender: { id: sender.id, url: sender.url, tab: sender.tab, frameId: sender.frameId, documentId: sender.documentId } });
        return true;
      });
      globalThis.__searchextraUserScriptsReply = answer => {
        const request = pending.get(answer.requestId);
        if (!request) return;
        pending.delete(answer.requestId); clearTimeout(request.timeout);
        request.sendResponse({ [marker]: 1, result: answer.result, error: answer.error });
      };
      globalThis.__searchextraUserScriptsEvent = async event => {
        if (event.type === 'message') {
          try {
            const result = await runtime.sendMessage({ [marker]: 1, event: 'message', message: event.message, sender: event.sender });
            host({ kind: 'extensionUserScriptsEventResult', eventId: event.eventId, result });
          } catch (error) { host({ kind: 'extensionUserScriptsEventResult', eventId: event.eventId, error: error.message }); }
        } else if (event.type === 'connect') {
          const port = runtime.connect({ name: '__searchextraUserScriptPort:' + event.portId });
          ports.set(event.portId, port);
          port.onMessage.addListener(message => host({ kind: 'extensionUserScriptsPortMessage', portId: event.portId, message }));
          port.onDisconnect.addListener(() => { ports.delete(event.portId); host({ kind: 'extensionUserScriptsPortDisconnect', portId: event.portId }); });
          port.postMessage({ [marker]: 1, event: 'connect', name: event.name, sender: event.sender });
        } else if (event.type === 'portMessage') ports.get(event.portId)?.postMessage(event.message);
        else if (event.type === 'portDisconnect') { ports.get(event.portId)?.disconnect(); ports.delete(event.portId); }
      };
      async function publishPermissions() {
        const grants = await chrome.permissions.getAll();
        const fileAccess = await new Promise(resolve => chrome.extension.isAllowedFileSchemeAccess(resolve));
        host({ kind: 'extensionUserScriptsReady', permissions: grants.permissions || [], origins: grants.origins || [], fileAccess });
      }
      chrome.permissions.onAdded.addListener(publishPermissions);
      chrome.permissions.onRemoved.addListener(publishPermissions);
      publishPermissions();
    })();
    """;
}
