using System.Text.Json.Nodes;
using SearcheXtra.Windows;

public static class UserScriptStoreTests
{
    public static async Task RunAsync(Action<bool, string> check)
    {
        var root = Path.Combine(Path.GetTempPath(), "SearcheXtra-user-script-store-" + Guid.NewGuid().ToString("N"));
        var store = new UserScriptStore(root, "ordinary-profile", "one-extension");
        static JsonArray Args(string json) => JsonNode.Parse(json)!.AsArray();
        static bool Reject(Action action) { try { action(); return false; } catch (Exception error) when (error is InvalidDataException or NotSupportedException) { return true; } }
        check(store.Invoke("getScripts", [])!.AsArray().Count == 0, "Fresh user script registry is empty");
        var unpackedReload = new UserScriptStore(root, "reload-profile", "one-extension");
        unpackedReload.Invoke("register", Args("""[[{"id":"reload-script","matches":["<all_urls>"],"js":[{"code":"1"}]}]]"""));
        unpackedReload.Invoke("configureWorld", Args("""[{"messaging":true}]"""));
        unpackedReload.Invoke("configureWorld", Args("""[{"worldId":"named-world","messaging":true}]"""));
        unpackedReload.Reset();
        await unpackedReload.SaveAsync();
        var afterUnpackedReload = new UserScriptStore(root, "reload-profile", "one-extension");
        check(afterUnpackedReload.Scripts.Count == 0 && afterUnpackedReload.Worlds.Count == 0, "Unpacked extension reload clears persisted scripts and every configured world");
        store.Invoke("register", Args("""[[{"id":"one","matches":["https://example.com/*"],"js":[{"code":"globalThis.probe = 1;"}],"world":"USER_SCRIPT","runAt":"document_start"},{"id":"two","matches":["<all_urls>"],"js":[{"file":"script.js"}]}]]"""));
        check(store.Invoke("getScripts", [])!.AsArray().Count == 2, "Register inline and packaged user scripts");
        var selected = store.Invoke("getScripts", Args("""[{"ids":["two"]}]"""))!.AsArray();
        check(selected.Count == 1 && selected[0]!["id"]!.GetValue<string>() == "two", "User script queries filter by id");
        selected[0]!["js"]![0]!["file"] = "mutated.js";
        check(store.Scripts[1]!["js"]![0]!["file"]!.GetValue<string>() == "script.js", "Query results cannot mutate stored registrations");
        var before = store.Scripts.ToJsonString();
        check(Reject(() => store.Invoke("register", Args("""[[{"id":"three","matches":["<all_urls>"],"js":[{"code":"3"}]},{"id":"one","matches":["<all_urls>"],"js":[{"code":"1"}]}]]"""))) && store.Scripts.ToJsonString() == before, "Duplicate registration batches reject atomically");
        check(Reject(() => store.Invoke("register", Args("""[[{"id":"three","matches":["<all_urls>"],"js":[{"code":"3"}]},{"id":"three","matches":["<all_urls>"],"js":[{"code":"4"}]}]]"""))) && store.Scripts.ToJsonString() == before, "Duplicates inside one registration batch do not partially install");
        store.Invoke("update", Args("""[[{"id":"one","allFrames":true}]]"""));
        check(store.Scripts[0]!["allFrames"]!.GetValue<bool>() && store.Scripts[0]!["runAt"]!.GetValue<string>() == "document_start", "Partial updates preserve existing script fields");
        before = store.Scripts.ToJsonString();
        check(Reject(() => store.Invoke("update", Args("""[[{"id":"one","allFrames":false},{"id":"missing","runAt":"document_end"}]]"""))) && store.Scripts.ToJsonString() == before, "Unknown update ids reject the entire batch");
        check(Reject(() => store.Invoke("update", Args("""[[{"id":"one","matches":[]}]]"""))) && store.Scripts.ToJsonString() == before, "Invalid updates preserve earlier registrations");
        store.Invoke("configureWorld", Args("""[{"csp":"script-src 'self' 'unsafe-inline' 'unsafe-eval' *","messaging":true}]"""));
        store.Invoke("configureWorld", Args("""[{"worldId":"other","messaging":false}]"""));
        store.Invoke("configureWorld", Args("""[{"worldId":"other","messaging":true}]"""));
        check(store.Worlds.Count == 2 && store.Worlds[0]!["csp"] != null && store.Worlds[1]!["messaging"]!.GetValue<bool>(), "ScriptCat CSP and separate messaging worlds are retained");
        var worldsBefore = store.Worlds.ToJsonString();
        check(Reject(() => store.Invoke("configureWorld", Args("""[{"worldId":"other","csp":"script-src 'none'"}]"""))) && store.Worlds.ToJsonString() == worldsBefore, "Unsupported CSP is rejected without silently weakening it");
        await store.SaveAsync();
        var reopened = new UserScriptStore(root, "ordinary-profile", "one-extension");
        check(reopened.Scripts.ToJsonString() == store.Scripts.ToJsonString() && reopened.Worlds.ToJsonString() == store.Worlds.ToJsonString(), "Registrations and world settings survive profile restart");
        check(new UserScriptStore(root, "other-profile", "one-extension").Scripts.Count == 0 && new UserScriptStore(root, "ordinary-profile", "other-extension").Scripts.Count == 0, "Extension ids and browser profiles have isolated registrations");
        reopened.Invoke("resetWorldConfiguration", Args("""["other"]"""));
        check(reopened.Worlds.Count == 1 && reopened.Worlds[0]!["worldId"] == null, "Reset one world preserves other world configurations");
        reopened.Invoke("unregister", Args("""[{"ids":["one"]}]"""));
        check(reopened.Scripts.Count == 1 && reopened.Scripts[0]!["id"]!.GetValue<string>() == "two", "Unregister selected ids preserves other scripts");
        reopened.Invoke("unregister", []);
        check(reopened.Scripts.Count == 0, "Unregister without ids clears registrations");
        reopened.Delete();
        check(new UserScriptStore(root, "ordinary-profile", "one-extension").Scripts.Count == 0, "Uninstall removes persisted user scripts");

        var versionRoot = Path.Combine(root, "versioned");
        var legacy = new UserScriptStore(versionRoot, "profile", "extension");
        legacy.Invoke("register", Args("""[[{"id":"bootstrap","matches":["<all_urls>"],"js":[{"code":"globalThis.oldBootstrap = true;"}]}]]"""));
        legacy.Invoke("configureWorld", Args("""[{"worldId":"old-world","messaging":true}]"""));
        await legacy.SaveAsync();
        var tagged = new UserScriptStore(versionRoot, "profile", "extension", "1.0.0");
        check(tagged.Scripts.Count == 1 && tagged.Worlds.Count == 1, "Legacy versionless stores retain registrations when version tracking starts");
        await tagged.SaveAsync();
        var versionPath = Directory.GetFiles(Path.Combine(versionRoot, "UserScripts"), "*.json").Single();
        check(JsonNode.Parse(File.ReadAllText(versionPath))!["extensionVersion"]!.GetValue<string>() == "1.0.0", "Saving a legacy store records the installed extension version");
        var sameVersion = new UserScriptStore(versionRoot, "profile", "extension", "1.0.0");
        check(sameVersion.Scripts.ToJsonString() == tagged.Scripts.ToJsonString() && sameVersion.Worlds.ToJsonString() == tagged.Worlds.ToJsonString(), "Same-version browser restart retains scripts and world configuration");
        await new UserScriptStore(versionRoot, "profile", "extension").SaveAsync();
        var updated = new UserScriptStore(versionRoot, "profile", "extension", "2.0.0");
        check(updated.Scripts.Count == 0 && updated.Worlds.Count == 0, "An extension version change clears prior scripts and worlds, including after a version-unspecified reload");
        updated.Invoke("register", Args("""[[{"id":"bootstrap","matches":["<all_urls>"],"js":[{"code":"globalThis.newBootstrap = true;"}]}]]"""));
        updated.Invoke("configureWorld", Args("""[{"worldId":"new-world","messaging":true}]"""));
        await updated.SaveAsync();
        var updatedReload = new UserScriptStore(versionRoot, "profile", "extension", "2.0.0");
        check(updatedReload.Scripts.Count == 1 && updatedReload.Scripts[0]!["js"]![0]!["code"]!.GetValue<string>() == "globalThis.newBootstrap = true;" && updatedReload.Worlds.Count == 1 && updatedReload.Worlds[0]!["worldId"]!.GetValue<string>() == "new-world", "The updated extension can reuse old script ids and persist only its new registrations");
        var invalidVersioned = """{"extensionVersion":"1.0.0","scripts":[{"id":"invalid","matches":[],"js":[{"code":"1"}]}],"worlds":[]}""";
        File.WriteAllText(versionPath, invalidVersioned);
        check(Reject(() => _ = new UserScriptStore(versionRoot, "profile", "extension", "2.0.0")) && File.ReadAllText(versionPath) == invalidVersioned, "A version change still rejects and preserves corrupt persisted registrations");

        var validation = new UserScriptStore(root, "validation", "one-extension");
        static JsonArray ScriptWithWorld(JsonNode? worldId, string world = "USER_SCRIPT") => new(new JsonArray(new JsonObject { ["id"] = "world-probe", ["matches"] = new JsonArray("<all_urls>"), ["js"] = new JsonArray(new JsonObject { ["code"] = "void 0;" }), ["world"] = world, ["worldId"] = worldId }));
        check(Reject(() => validation.Invoke("register", ScriptWithWorld("_reserved"))) && Reject(() => validation.Invoke("configureWorld", Args("""[{"worldId":"_reserved"}]"""))), "User script and world configuration ids reject the reserved underscore prefix");
        check(Reject(() => validation.Invoke("register", ScriptWithWorld(new string('x', 257)))) && Reject(() => validation.Invoke("configureWorld", new(new JsonObject { ["worldId"] = new string('x', 257) }))), "Registration and configuration reject world ids longer than 256 bytes");
        check(Reject(() => validation.Invoke("register", ScriptWithWorld(new string('界', 86)))) && Reject(() => validation.Invoke("configureWorld", new(new JsonObject { ["worldId"] = new string('界', 86) }))), "World id length follows Chromium UTF-8 byte limits for Unicode ids");
        check(Reject(() => validation.Invoke("register", ScriptWithWorld(42))) && Reject(() => validation.Invoke("configureWorld", Args("""[{"worldId":42}]"""))) && Reject(() => validation.Invoke("configureWorld", Args("""[{"worldId":null}]"""))), "World ids require strings");
        check(Reject(() => validation.Invoke("register", ScriptWithWorld("named", "MAIN"))) && Reject(() => validation.Invoke("register", ScriptWithWorld("", "MAIN"))), "MAIN world scripts cannot specify a world id, including an empty id");
        var maximum = new string('x', 256);
        validation.Invoke("register", ScriptWithWorld(maximum));
        validation.Invoke("configureWorld", new(new JsonObject { ["worldId"] = maximum, ["messaging"] = true }));
        check(validation.Scripts.Count == 1 && validation.Worlds.Count == 1, "Named user-script worlds accept the 256 byte boundary");
        check(Reject(() => validation.Invoke("configureWorld", Args("""[{"messaging":"true"}]"""))) && Reject(() => validation.Invoke("configureWorld", Args("""[{"messaging":1}]"""))) && Reject(() => validation.Invoke("configureWorld", Args("""[{"messaging":null}]"""))), "Messaging must be an actual boolean");
        check(Reject(() => validation.Invoke("configureWorld", Args("""[{"csp":42}]"""))) && Reject(() => validation.Invoke("configureWorld", Args("""[{"csp":null}]"""))), "World content security policies require strings");
        validation.Invoke("configureWorld", Args("""[{"csp":"script-src 'self' 'unsafe-eval'","messaging":false}]"""));
        check(validation.Worlds.Last()!["csp"]!.GetValue<string>() == "script-src 'self' 'unsafe-eval'", "Ordinary default user-script CSP is supported on both platforms");
        check(UserScriptStore.SupportsCsp(" SCRIPT-SRC 'unsafe-eval' 'SELF' 'self'; ") && UserScriptStore.SupportsCsp("script-src * 'unsafe-eval' 'unsafe-inline' 'self';") && UserScriptStore.SupportsCsp("  "), "CSP acceptance matches macOS token sets, case normalization and empty default");
        check(!UserScriptStore.SupportsCsp("script-src 'self' 'unsafe-eval'; connect-src *") && !UserScriptStore.SupportsCsp("default-src *"), "Unsupported CSP directives are rejected instead of ignored");
        check(Reject(() => validation.Invoke("resetWorldConfiguration", Args("""["_reserved"]"""))) && Reject(() => validation.Invoke("resetWorldConfiguration", Args("""[42]"""))), "World reset applies the same id validation as configuration");

        var damagedRoot = Path.Combine(root, "damaged");
        var damaged = new UserScriptStore(damagedRoot, "one-profile", "one-extension");
        await damaged.SaveAsync();
        var damagedPath = Directory.GetFiles(Path.Combine(damagedRoot, "UserScripts"), "*.json").Single();
        File.WriteAllText(damagedPath, "{ invalid JSON");
        check(Reject(() => _ = new UserScriptStore(damagedRoot, "one-profile", "one-extension")) && File.ReadAllText(damagedPath) == "{ invalid JSON", "Damaged registration JSON returns a recoverable extension error and preserves the original file");
        File.WriteAllText(damagedPath, """{"scripts":[{"id":"broken","matches":[],"js":[{"code":"1"}]}],"worlds":[]}""");
        check(Reject(() => _ = new UserScriptStore(damagedRoot, "one-profile", "one-extension")), "Invalid persisted registrations are rejected before any injection is restored");
        File.WriteAllText(damagedPath, """{"scripts":[],"worlds":[{"messaging":"true"}]}""");
        check(Reject(() => _ = new UserScriptStore(damagedRoot, "one-profile", "one-extension")) && new UserScriptStore(damagedRoot, "other-profile", "one-extension").Scripts.Count == 0, "Damaged world configuration affects only its extension and profile");

        static void Execute(string json) => UserScriptStore.ValidateExecution(JsonNode.Parse(json)!.AsObject());
        Execute("""{"target":{"tabId":1},"js":[{"code":"1"}],"world":"MAIN"}""");
        Execute("""{"target":{"tabId":1,"allFrames":false,"frameIds":[0,2]},"js":[{"file":"script.js"}],"worldId":"named"}""");
        Execute("""{"target":{"tabId":1,"documentIds":["document"]},"js":[{"code":"1"}],"injectImmediately":true}""");
        Execute("""{"target":{"tabId":1,"allFrames":true},"js":[{"code":"1"}]}""");
        check(true, "Immediate execution accepts main-frame, selected-frame, document and all-frame targets");
        check(Reject(() => Execute("""{"target":{},"js":[{"code":"1"}]}""")) && Reject(() => Execute("""{"target":{"tabId":"1"},"js":[{"code":"1"}]}""")) && Reject(() => Execute("""{"target":{"tabId":1.5},"js":[{"code":"1"}]}""")), "Immediate execution requires an integer tab id");
        check(Reject(() => Execute("""{"target":{"tabId":1,"allFrames":true,"frameIds":[0]},"js":[{"code":"1"}]}""")) && Reject(() => Execute("""{"target":{"tabId":1,"allFrames":true,"documentIds":["document"]},"js":[{"code":"1"}]}""")) && Reject(() => Execute("""{"target":{"tabId":1,"frameIds":[0],"documentIds":["document"]},"js":[{"code":"1"}]}""")), "Immediate execution rejects conflicting target selectors");
        check(Reject(() => Execute("""{"target":{"tabId":1,"frameIds":[]},"js":[{"code":"1"}]}""")) && Reject(() => Execute("""{"target":{"tabId":1,"frameIds":["0"]},"js":[{"code":"1"}]}""")) && Reject(() => Execute("""{"target":{"tabId":1,"documentIds":[""]},"js":[{"code":"1"}]}""")), "Immediate execution validates nonempty typed frame and document lists");
        check(Reject(() => Execute("""{"target":{"tabId":1},"js":[{"code":"1","file":"script.js"}]}""")) && Reject(() => Execute("""{"target":{"tabId":1},"js":[{"code":42}]}""")) && Reject(() => Execute("""{"target":{"tabId":1},"js":[]}""")), "Immediate execution shares source validation with registered scripts");
        check(Reject(() => Execute("""{"target":{"tabId":1},"js":[{"code":"1"}],"world":"MAIN","worldId":""}""")) && Reject(() => Execute("""{"target":{"tabId":1},"js":[{"code":"1"}],"worldId":"_reserved"}""")), "Immediate execution shares world restrictions with registered scripts");
        check(Reject(() => Execute("""{"target":{"tabId":1,"allFrames":"true"},"js":[{"code":"1"}]}""")) && Reject(() => Execute("""{"target":{"tabId":1},"js":[{"code":"1"}],"injectImmediately":1}""")), "Immediate execution timing and target flags require booleans");
    }
}
