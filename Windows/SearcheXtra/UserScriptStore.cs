using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace SearcheXtra.Windows;

// One extension's user-script registrations in one ordinary browser profile.
// The extension's own storage remains managed by Chromium.
internal sealed class UserScriptStore
{
    private readonly string path;
    private readonly string? extensionVersion;
    public JsonArray Scripts { get; private set; } = [];
    public JsonArray Worlds { get; private set; } = [];

    public UserScriptStore(string root, string profile, string extensionId, string? extensionVersion = null)
    {
        path = FilePath(root, profile, extensionId);
        this.extensionVersion = string.IsNullOrEmpty(extensionVersion) ? null : extensionVersion;
        if (!File.Exists(path)) return;
        try
        {
            var saved = JsonNode.Parse(File.ReadAllText(path)) as JsonObject ?? throw new InvalidDataException("Invalid user-script registrations.");
            var scripts = saved["scripts"] == null ? [] : ScriptArray(saved["scripts"]);
            if (scripts.Select(Id).Distinct(StringComparer.Ordinal).Count() != scripts.Count) throw new InvalidDataException("Duplicate saved user script id.");
            var worlds = saved["worlds"] == null ? [] : saved["worlds"] as JsonArray ?? throw new InvalidDataException("Invalid saved user-script worlds.");
            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (var node in worlds)
            {
                var world = node as JsonObject ?? throw new InvalidDataException("Invalid saved user-script world.");
                ValidateWorld(world);
                if (!ids.Add(WorldId(world))) throw new InvalidDataException("Duplicate saved user-script world id.");
            }
            var previousVersion = saved["extensionVersion"]?.GetValue<string>();
            // Chrome clears user-script registrations when an extension updates,
            // while a browser restart retains them. Stores written before this
            // metadata was introduced are preserved and tagged on their next save.
            if (!string.IsNullOrEmpty(previousVersion) && this.extensionVersion != null && previousVersion != this.extensionVersion) return;
            this.extensionVersion ??= string.IsNullOrEmpty(previousVersion) ? null : previousVersion;
            Scripts = scripts; Worlds = worlds;
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or InvalidDataException or NotSupportedException or IOException or UnauthorizedAccessException)
        {
            // Preserve the original file. The profile host handles this extension's
            // failure independently, leaving other extensions and browser startup usable.
            throw new InvalidDataException("Could not load this extension's saved user scripts.", error);
        }
    }

    public void Reset() { Scripts = []; Worlds = []; }

    public JsonNode? Invoke(string api, JsonArray args)
    {
        var first = args.FirstOrDefault();
        switch (api)
        {
            case "getScripts":
                return new JsonArray(Selected(first).Select(s => s.DeepClone()).ToArray());
            case "getWorldConfigurations": return Worlds.DeepClone();
            case "register":
            {
                var additions = ScriptArray(first);
                var ids = Scripts.Select(Id).ToHashSet(StringComparer.Ordinal);
                foreach (var script in additions)
                    if (!ids.Add(Id(script))) throw new InvalidDataException("Duplicate user script id: " + Id(script));
                Scripts = new JsonArray(Scripts.Concat(additions).Select(s => s!.DeepClone()).ToArray());
                break;
            }
            case "update":
            {
                var updates = first as JsonArray ?? throw new InvalidDataException("Expected an array of user scripts.");
                var next = (JsonArray)Scripts.DeepClone();
                var seen = new HashSet<string>(StringComparer.Ordinal);
                foreach (var node in updates)
                {
                    var update = node as JsonObject ?? throw new InvalidDataException("Invalid user script.");
                    var id = Id(update);
                    if (!seen.Add(id)) throw new InvalidDataException("Duplicate user script id: " + id);
                    var index = next.Select((s, i) => (s, i)).FirstOrDefault(pair => Id(pair.s) == id, (null, -1)).i;
                    if (index < 0) throw new InvalidDataException("Unknown user script id: " + id);
                    var merged = (JsonObject)next[index]!.DeepClone();
                    foreach (var pair in update) merged[pair.Key] = pair.Value?.DeepClone();
                    Validate(merged); next[index] = merged;
                }
                Scripts = next;
                break;
            }
            case "unregister":
            {
                var ids = Selected(first).Select(Id).ToHashSet(StringComparer.Ordinal);
                Scripts = new JsonArray(Scripts.Where(s => !ids.Contains(Id(s))).Select(s => s!.DeepClone()).ToArray());
                break;
            }
            case "configureWorld":
            {
                var config = first as JsonObject ?? new JsonObject();
                var id = WorldId(config);
                var next = (JsonArray)Worlds.DeepClone();
                var previous = next.OfType<JsonObject>().FirstOrDefault(w => WorldId(w) == id);
                var merged = previous == null ? new JsonObject() : (JsonObject)previous.DeepClone();
                foreach (var pair in config) merged[pair.Key] = pair.Value?.DeepClone();
                ValidateWorld(merged);
                if (previous != null) next.Remove(previous);
                next.Add(merged); Worlds = next;
                break;
            }
            case "resetWorldConfiguration":
            {
                var id = first is JsonObject obj ? WorldId(obj) : ValidateWorldId(first);
                Worlds = new JsonArray(Worlds.OfType<JsonObject>().Where(w => WorldId(w) != id).Select(w => w.DeepClone()).ToArray());
                break;
            }
            default: throw new NotSupportedException("Unsupported userScripts method: " + api);
        }
        return null;
    }

    public async Task SaveAsync()
    {
        var text = new JsonObject { ["extensionVersion"] = extensionVersion, ["scripts"] = Scripts.DeepClone(), ["worlds"] = Worlds.DeepClone() }.ToJsonString();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".tmp";
        await File.WriteAllTextAsync(temporary, text);
        File.Move(temporary, path, true);
    }

    public void Delete() { if (File.Exists(path)) File.Delete(path); }
    internal static void Delete(string root, string profile, string extensionId)
    {
        var file = FilePath(root, profile, extensionId);
        if (File.Exists(file)) File.Delete(file);
    }
    private static string FilePath(string root, string profile, string extensionId)
    {
        var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(profile + "\n" + extensionId)));
        return Path.Combine(root, "UserScripts", key + ".json");
    }

    private IEnumerable<JsonNode> Selected(JsonNode? filter)
    {
        if (filter is not JsonObject obj || obj["ids"] == null) return Scripts.Select(s => s!);
        var ids = Strings(obj["ids"]).ToHashSet(StringComparer.Ordinal);
        return Scripts.Where(s => ids.Contains(Id(s))).Select(s => s!);
    }
    private static JsonArray ScriptArray(JsonNode? value)
    {
        var scripts = value as JsonArray ?? throw new InvalidDataException("Expected an array of user scripts.");
        foreach (var node in scripts) Validate(node as JsonObject ?? throw new InvalidDataException("Invalid user script."));
        return scripts;
    }
    internal static string Id(JsonNode? script)
    {
        var id = script?["id"]?.GetValue<string>();
        if (string.IsNullOrEmpty(id) || id.StartsWith('_')) throw new InvalidDataException("Invalid user script id.");
        return id;
    }
    internal static string WorldId(JsonObject value)
    {
        if (value.ContainsKey("worldId") && value["worldId"] == null) throw new InvalidDataException("Invalid user-script world id.");
        return ValidateWorldId(value["worldId"]);
    }
    private static string ValidateWorldId(JsonNode? value)
    {
        if (value == null) return "";
        if (value is not JsonValue node || !node.TryGetValue<string>(out var id) || Encoding.UTF8.GetByteCount(id) > 256 || id.StartsWith('_'))
            throw new InvalidDataException("Invalid user-script world id.");
        return id;
    }
    internal static string[] Strings(JsonNode? value) => value is JsonArray array ? array.Select(n => n?.GetValue<string>() ?? throw new InvalidDataException("Expected strings.")).ToArray() : throw new InvalidDataException("Expected an array.");

    internal static void Validate(JsonObject script)
    {
        _ = Id(script);
        var matches = Strings(script["matches"]);
        if (matches.Length == 0 || matches.Any(m => !ValidPattern(m))) throw new InvalidDataException("Invalid user-script match pattern.");
        if (script["excludeMatches"] is JsonNode exclusions && Strings(exclusions).Any(m => !ValidPattern(m)))
            throw new InvalidDataException("Invalid user-script exclusion pattern.");
        foreach (var name in new[] { "includeGlobs", "excludeGlobs" }) if (script[name] != null) _ = Strings(script[name]);
        ValidateWorldSelection(script);
        if (script["runAt"]?.GetValue<string>() is string runAt && runAt is not ("document_start" or "document_end" or "document_idle")) throw new InvalidDataException("Invalid user-script injection time.");
        ValidateSources(script["js"]);
    }

    public static void ValidateExecution(JsonObject injection)
    {
        ValidateWorldSelection(injection);
        ValidateSources(injection["js"]);
        OptionalBoolean(injection, "injectImmediately");
        if (injection["target"] is not JsonObject target || target["tabId"] is not JsonValue tab || !tab.TryGetValue<int>(out _))
            throw new InvalidDataException("A user-script target requires an integer tab id.");
        var allFrames = OptionalBoolean(target, "allFrames");
        var hasFrames = target.ContainsKey("frameIds");
        var hasDocuments = target.ContainsKey("documentIds");
        if ((hasFrames && hasDocuments) || (allFrames && (hasFrames || hasDocuments))) throw new InvalidDataException("User-script target frame selectors are mutually exclusive.");
        if (hasFrames && (target["frameIds"] is not JsonArray frames || frames.Count == 0 || frames.Any(node => node is not JsonValue frame || !frame.TryGetValue<int>(out var id) || id < 0)))
            throw new InvalidDataException("User-script frame ids must be a nonempty array of nonnegative integers.");
        if (hasDocuments && (target["documentIds"] is not JsonArray documents || documents.Count == 0 || documents.Any(node => node is not JsonValue document || !document.TryGetValue<string>(out var id) || string.IsNullOrEmpty(id))))
            throw new InvalidDataException("User-script document ids must be a nonempty array of strings.");
    }

    private static void ValidateWorldSelection(JsonObject script)
    {
        if (script.ContainsKey("world") && (script["world"] is not JsonValue world || !world.TryGetValue<string>(out var name) || name is not ("MAIN" or "USER_SCRIPT")))
            throw new InvalidDataException("Invalid user-script execution world.");
        _ = WorldId(script);
        if (script.ContainsKey("worldId") && script["world"]?.GetValue<string>() == "MAIN") throw new InvalidDataException("The MAIN world does not accept a user-script world id.");
    }

    private static void ValidateSources(JsonNode? value)
    {
        if (value is not JsonArray js || js.Count == 0 || js.Any(n => n is not JsonObject source || source.ContainsKey("code") == source.ContainsKey("file")))
            throw new InvalidDataException("User scripts require JavaScript code or files.");
        foreach (var source in js.OfType<JsonObject>())
        {
            if (source.ContainsKey("code"))
            {
                if (source["code"] is not JsonValue code || !code.TryGetValue<string>(out _)) throw new InvalidDataException("User-script code must be a string.");
            }
            else if (source["file"] is not JsonValue file || !file.TryGetValue<string>(out var name) || string.IsNullOrWhiteSpace(name)) throw new InvalidDataException("Invalid user-script file.");
        }
    }

    private static bool OptionalBoolean(JsonObject value, string key)
    {
        if (!value.ContainsKey(key)) return false;
        if (value[key] is not JsonValue node || !node.TryGetValue<bool>(out var result)) throw new InvalidDataException("Invalid user-script " + key + " value.");
        return result;
    }

    private static bool ValidPattern(string value) => value == "<all_urls>" || System.Text.RegularExpressions.Regex.IsMatch(value, @"^(\*|https?|file|ftp)://([^/]+|(?<=file://))/.*$");
    internal static bool SupportsCsp(string csp)
    {
        if (string.IsNullOrWhiteSpace(csp)) return true;
        var directives = csp.ToLowerInvariant().Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (directives.Length != 1) return false;
        var words = directives[0].Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        if (words.Length == 0 || words[0] != "script-src") return false;
        var tokens = words.Skip(1).ToHashSet(StringComparer.Ordinal);
        return tokens.SetEquals(["'self'", "'unsafe-eval'"]) || tokens.SetEquals(["'self'", "'unsafe-inline'", "'unsafe-eval'", "*"]);
    }
    private static void ValidateWorld(JsonObject config)
    {
        _ = WorldId(config);
        if (config.ContainsKey("messaging") && (config["messaging"] is not JsonValue messaging || !messaging.TryGetValue<bool>(out _)))
            throw new InvalidDataException("Invalid user-script messaging value.");
        if (!config.ContainsKey("csp")) return;
        if (config["csp"] is not JsonValue csp || !csp.TryGetValue<string>(out var policy)) throw new InvalidDataException("Invalid user-script content security policy.");
        if (!SupportsCsp(policy)) throw new NotSupportedException("This user-script execution environment does not support the requested CSP.");
    }
}
