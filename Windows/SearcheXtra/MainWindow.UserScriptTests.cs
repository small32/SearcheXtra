using Microsoft.Web.WebView2.Core;
using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace SearcheXtra.Windows;

public sealed partial class MainWindow
{
    // Opt-in native integration test. The supplied package is copied into the
    // isolated smoke-test data directory before the production installer sees it.
    private async Task RunUserScriptTestsAsync(string fixture, Action<bool, string> check)
    {
        var input = Environment.GetEnvironmentVariable("SEARCHEXTRA_TEST_MV3_FOLDER");
        if (string.IsNullOrWhiteSpace(input)) throw new InvalidOperationException("SEARCHEXTRA_TEST_MV3_FOLDER must identify an original ScriptCat MV3 folder or ZIP.");
        var packageRoot = Path.Combine(DataStore.Root, "ScriptCat-MV3-fixture-" + Guid.NewGuid().ToString("N"));
        string folder;
        if (File.Exists(input)) folder = await CrxInstaller.ImportAsync(input, packageRoot);
        else
        {
            var source = CrxInstaller.ValidateFolder(input);
            folder = packageRoot;
            await Task.Run(() =>
            {
                foreach (var file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
                {
                    var target = Path.Combine(folder, Path.GetRelativePath(source, file));
                    Directory.CreateDirectory(Path.GetDirectoryName(target)!); File.Copy(file, target);
                }
            });
        }
        using var manifest = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(folder, "manifest.json")));
        check(manifest.RootElement.GetProperty("manifest_version").GetInt32() == 3, "Native fixture uses the original ScriptCat MV3 manifest");
        var sourceVersion = manifest.RootElement.GetProperty("version").GetString();
        var website = AddTab(fixture, false); await SelectAsync(website);
        var websiteView = await GetViewAsync(website);
        await WaitUserScriptAsync(() => Task.FromResult(!website.Loading), "initial test webpage");
        await InstallExtensionFolderAsync(folder);
        var item = Settings.Extensions.Single(extension => extension.Folder == Path.GetFullPath(folder));
        check(item.ManifestVersion == 3 && item.Enabled && item.Version == sourceVersion, "Production installer enables the original ScriptCat MV3 package");
        check(!item.AllowUserScripts, "User-script access defaults to disabled");
        var options = AddTab($"chrome-extension://{item.Id}/{item.Options}", false); await SelectAsync(options);
        var optionsView = await GetViewAsync(options);
        var optionsCore = optionsView.Control.CoreWebView2;
        await WaitUserScriptAsync(() => Task.FromResult(!options.Loading && optionsCore.Source.StartsWith($"chrome-extension://{item.Id}/{item.Options}", StringComparison.Ordinal)), "ScriptCat options navigation completes");
        await WaitUserScriptAsync(async () => (await EvaluateUserScriptTestAsync(optionsCore, "document.readyState"))?.GetValue<string>() == "complete", "ScriptCat options document finishes loading");
        await SelectAsync(options);
        optionsView.Resume(); optionsView.Control.UpdateLayout();
        File.AppendAllText(Path.Combine(DataStore.Root, "user-scripts-test.log"), "options selected=" + (active == options) + "; visibility=" + optionsView.Control.Visibility + "; loaded=" + optionsView.Control.IsLoaded + "; suspended=" + optionsCore.IsSuspended + "; source=" + optionsCore.Source + "\n");
        await Task.Delay(300);
        check(true, "ScriptCat options document finishes its initial navigation before API calls");
        await WaitUserScriptAsync(async () => (await EvaluateUserScriptTestAsync(optionsCore, "Boolean(globalThis.__searchextraUserScriptsInstalled)"))?.GetValue<bool>() == true, "ScriptCat native extension bootstrap");
        var apiMetadata = await EvaluateUserScriptTestAsync(optionsCore, """
            (()=>{const descriptor=Object.getOwnPropertyDescriptor(chrome,'userScripts');return {
              installed:globalThis.__searchextraUserScriptsInstalled,
              namespaceType:typeof chrome.userScripts,getScriptsType:typeof chrome.userScripts?.getScripts,
              getScriptsSource:chrome.userScripts?.getScripts?.toString(),
              namespaceDescriptor:descriptor?{getType:typeof descriptor.get,valueType:typeof descriptor.value,configurable:descriptor.configurable,enumerable:descriptor.enumerable,writable:descriptor.writable}:null,
              runtimeSendType:typeof chrome.runtime.sendMessage,runtimeSendSource:chrome.runtime.sendMessage?.toString()
            }})()
            """);
        File.AppendAllText(Path.Combine(DataStore.Root, "user-scripts-test.log"), "api metadata " + apiMetadata?.ToJsonString() + "\n");
        await EvaluateUserScriptTestAsync(optionsCore, """
            (()=>{const state={started:true,callback:false};globalThis.__sxNativeIdentityDiagnostic=state;
              try{chrome.runtime.sendMessage({__sxUserScriptPageIdentity:true},value=>{state.callback=true;state.value=value;state.error=chrome.runtime.lastError?.message});}
              catch(error){state.error=String(error)}return state})()
            """);
        await Task.Delay(250);
        var identityDiagnostic = await EvaluateUserScriptTestAsync(optionsCore, "globalThis.__sxNativeIdentityDiagnostic");
        File.AppendAllText(Path.Combine(DataStore.Root, "user-scripts-test.log"), "native identity callback " + identityDiagnostic?.ToJsonString() + "\n");
        var denied = await EvaluateUserScriptTestAsync(optionsCore, "(async()=>{try{await chrome.userScripts.getScripts();return false}catch{return true}})()");
        check(denied?.GetValue<bool>() == true, "The real MV3 extension cannot register scripts before permission is granted");
        await SetUserScriptsAllowedAsync(item, true);
        await ReloadUserScriptTestAsync(optionsCore);
        var profile = optionsCore.Profile.ProfileName;
        await WaitUserScriptAsync(() => Task.FromResult(ExtensionUserScripts.Snapshots(profile).Any(state => state.ExtensionId == item.Id && state.Scripts.OfType<JsonObject>().Any(script => script["id"]?.GetValue<string>() == "scriptcat-content"))), "ScriptCat registers its real content execution environment");
        check(item.AllowUserScripts && ExtensionUserScripts.Allowed(profile, item.Id), "The production Allow user scripts switch grants access");
        var identity = await EvaluateUserScriptTestAsync(optionsCore, "({id:chrome.runtime.id,version:chrome.runtime.getManifest().version})");
        check(identity?["id"]?.GetValue<string>() == item.Id && identity["version"]?.GetValue<string>() == sourceVersion, "ScriptCat retains its original native extension identity and version");

        var code = """
            // ==UserScript==
            // @name SearcheXtra native MV3 regression
            // @namespace https://searchextra.test/
            // @version 1.0
            // @match http://127.0.0.1/*
            // @run-at document-end
            // @grant GM.getValue
            // @grant GM.setValue
            // @grant GM_xmlhttpRequest
            // @connect 127.0.0.1
            // ==/UserScript==
            (async()=>{
              document.documentElement.setAttribute('data-sx-scriptcat-started','true');
              const count=Number(await GM.getValue('searchextra-native-test-count',0))+1;
              await GM.setValue('searchextra-native-test-count',count);
              document.documentElement.setAttribute('data-sx-scriptcat-count',String(count));
              GM_xmlhttpRequest({method:'GET',url:location.origin+'/scriptcat-gm-xhr',
                onload:response=>document.documentElement.setAttribute('data-sx-scriptcat-xhr',String(response.status)+':'+String(response.responseText.includes('Local browser test'))),
                onerror:error=>document.documentElement.setAttribute('data-sx-scriptcat-error','xhr:'+String(error.error||error))});
            })().catch(error=>document.documentElement.setAttribute('data-sx-scriptcat-error',String(error)));
            """;
        var install = """
            (async()=>{
              const code=CODE;
              const now=Date.now(),uuid=crypto.randomUUID();
              const script={uuid,name:'SearcheXtra native MV3 regression',namespace:'https://searchextra.test/',origin:'',originDomain:'',
                checkUpdateUrl:'',downloadUrl:'',metadata:{name:['SearcheXtra native MV3 regression'],namespace:['https://searchextra.test/'],version:['1.0'],
                match:['http://127.0.0.1/*'],'run-at':['document-end'],grant:['GM.getValue','GM.setValue','GM_xmlhttpRequest'],connect:['127.0.0.1']},
                selfMetadata:{},sort:-1,type:1,status:1,runStatus:'complete',createtime:now,updatetime:now,checktime:now};
              const result=await chrome.runtime.sendMessage({action:'serviceWorker/script/install',data:{script,code,upsertBy:'user'}});
              if(!result||result.code)throw new Error(JSON.stringify(result));
              return {uuid,result};
            })()
            """;
        var installed = await EvaluateUserScriptTestAsync(optionsCore, install.Replace("CODE", JsonSerializer.Serialize(code), StringComparison.Ordinal));
        check(installed?["uuid"]?.GetValue<string>() is { Length: > 0 }, "The genuine ScriptCat installation service installs a user script");
        await WaitUserScriptAsync(async () => (await EvaluateUserScriptTestAsync(optionsCore,
            "(async()=>{const scripts=await chrome.userScripts.getScripts();return scripts.some(s=>s.id===" + JsonSerializer.Serialize(installed!["uuid"]!.GetValue<string>()) + ")})()"))?.GetValue<bool>() == true,
            "ScriptCat finishes registering the installed user script");
        await SelectAsync(website);
        await ReloadUserScriptTestAsync(websiteView.Control.CoreWebView2);
        async Task<JsonNode?> State() => await EvaluateUserScriptTestAsync(websiteView.Control.CoreWebView2,
            "({started:document.documentElement.getAttribute('data-sx-scriptcat-started'),count:document.documentElement.getAttribute('data-sx-scriptcat-count'),xhr:document.documentElement.getAttribute('data-sx-scriptcat-xhr'),error:document.documentElement.getAttribute('data-sx-scriptcat-error')})");
        await WaitUserScriptAsync(async () =>
        {
            var state = await State();
            if (state?["error"] is JsonValue error) throw new InvalidOperationException("ScriptCat user script failed: " + error.GetValue<string>());
            return state?["count"]?.GetValue<string>() is { Length: > 0 };
        }, "ScriptCat executes its installed script and GM storage");
        var first = await State();
        check(first?["started"]?.GetValue<string>() == "true" && first["error"] == null, "An actual ScriptCat MV3 user script modifies the webpage");
        check(int.TryParse(first?["count"]?.GetValue<string>(), out var firstCount) && firstCount >= 1, "ScriptCat GM.getValue and GM.setValue work through the production extension runtime");
        await WaitUserScriptAsync(async () => (await State())?["xhr"]?.GetValue<string>() == "200:true", "ScriptCat GM_xmlhttpRequest reaches the local HTTP fixture: " + (await State())?.ToJsonString());
        check((await State())?["xhr"]?.GetValue<string>() == "200:true", "ScriptCat GM_xmlhttpRequest returns a real HTTP response");
        GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
        await ReloadUserScriptTestAsync(websiteView.Control.CoreWebView2);
        await WaitUserScriptAsync(async () => int.TryParse((await State())?["count"]?.GetValue<string>(), out var count) && count > firstCount, "GM storage persists across navigation");
        check(true, "ScriptCat GM values and native extension transport survive collection and webpage reloads");

        var beforeRuntimeReload = int.Parse((await State())!["count"]!.GetValue<string>());
        var optionsAddress = $"chrome-extension://{item.Id}/{item.Options}";
        await SelectAsync(options); optionsView.Resume();
        await EvaluateUserScriptTestAsync(optionsCore, "(()=>{setTimeout(()=>chrome.runtime.reload(),0);return true})()");
        await WaitUserScriptAsync(() => Task.FromResult(!optionsCore.Source.StartsWith(optionsAddress, StringComparison.Ordinal)), "ScriptCat invalidates its old options document during native runtime reload");
        optionsCore.Navigate(optionsAddress);
        await WaitUserScriptAsync(() => Task.FromResult(!options.Loading && optionsCore.Source.StartsWith(optionsAddress, StringComparison.Ordinal)), "ScriptCat reopens its options after native runtime reload");
        await WaitUserScriptAsync(async () => (await EvaluateUserScriptTestAsync(optionsCore, "document.readyState"))?.GetValue<string>() == "complete", "ScriptCat reloaded options document finishes loading");
        var installedId = installed!["uuid"]!.GetValue<string>();
        await WaitUserScriptAsync(async () => (await EvaluateUserScriptTestAsync(optionsCore,
            "(async()=>{try{return (await chrome.userScripts.getScripts()).some(script=>script.id===" + JsonSerializer.Serialize(installedId) + ")}catch{return false}})()"))?.GetValue<bool>() == true,
            "The native user-script bridge reconnects after ScriptCat reloads its own runtime");
        check(true, "Original ScriptCat getScripts reconnects after chrome.runtime.reload()");
        await SelectAsync(website); await ReloadUserScriptTestAsync(websiteView.Control.CoreWebView2);
        await WaitUserScriptAsync(async () =>
        {
            var state = await State();
            if (state?["error"] is JsonValue error) throw new InvalidOperationException("Reloaded ScriptCat user script failed: " + error.GetValue<string>());
            return int.TryParse(state?["count"]?.GetValue<string>(), out var count) && count > beforeRuntimeReload && state?["xhr"]?.GetValue<string>() == "200:true";
        }, "ScriptCat keeps its installed script, GM storage and HTTP transport after native runtime reload");
        check(true, "ScriptCat native runtime reload preserves GM storage and restores real GM HTTP requests");

        await EvaluateUserScriptTestAsync(websiteView.Control.CoreWebView2, "(()=>{const f=document.createElement('iframe');f.id='sx-scriptcat-frame';f.src=location.origin+'/scriptcat-child';document.body.appendChild(f);return f.src})()");
        await WaitUserScriptAsync(async () => (await EvaluateUserScriptTestAsync(websiteView.Control.CoreWebView2, "document.querySelector('#sx-scriptcat-frame')?.contentDocument?.documentElement?.getAttribute('data-sx-scriptcat-started')"))?.GetValue<string>() == "true", "ScriptCat runs in a native child frame");
        check(true, "The actual MV3 user script executes inside matching iframes");
        var frameResults = await EvaluateUserScriptTestAsync(optionsCore, """
            (async()=>{const tabs=await chrome.tabs.query({});const tab=tabs.find(t=>t.url===URL);
              if(!tab)throw new Error('The native webpage tab was not found.');
              const js=[{code:"({href:location.href,started:document.documentElement.getAttribute('data-sx-scriptcat-started'),webview:typeof chrome.webview})"}];
              const all=await chrome.userScripts.execute({target:{tabId:tab.id,allFrames:true},js});
              const child=all.find(result=>result.frameId!==0);
              if(!child)throw new Error('The native child frame was not found.');
              const byFrame=await chrome.userScripts.execute({target:{tabId:tab.id,frameIds:[child.frameId]},js});
              const byDocument=await chrome.userScripts.execute({target:{tabId:tab.id,documentIds:[child.documentId]},js});
              const freshWorld=await chrome.userScripts.execute({target:{tabId:tab.id},worldId:'sx-fresh-world',js:[{code:"({runtime:typeof globalThis.chrome?.runtime,url:location.href})"}]});
              const multiSource=await chrome.userScripts.execute({target:{tabId:tab.id},worldId:'sx-multi-source',js:[{code:"(()=>{globalThis.__sxMultiSource='first'})()"},{code:"(()=>globalThis.__sxMultiSource+'second')()"}]});
              const main=await chrome.userScripts.execute({world:'MAIN',target:{tabId:tab.id,frameIds:[child.frameId]},js:[{code:"document.documentElement.getAttribute('data-sx-scriptcat-started')"}]});
              return {all,byFrame,byDocument,main,freshWorld,multiSource};})()
            """.Replace("URL", JsonSerializer.Serialize(websiteView.Control.CoreWebView2.Source), StringComparison.Ordinal));
        var allFrames = frameResults?["all"] as JsonArray;
        check(allFrames?.Count == 2 && allFrames.OfType<JsonObject>().All(result => result["result"]?["started"]?.GetValue<string>() == "true"), "The genuine MV3 execute API returns both native top and child frame results");
        check(allFrames!.OfType<JsonObject>().All(result => result["result"]?["webview"]?.GetValue<string>() == "undefined" && result["documentId"]?.GetValue<string>() is { Length: > 0 }), "User-script execution isolates native host APIs and reports actual document IDs");
        check(frameResults?["byFrame"] is JsonArray { Count: 1 } byFrame && byFrame[0]?["frameId"]?.GetValue<int>() is > 0
            && frameResults["byDocument"] is JsonArray { Count: 1 } byDocument && byDocument[0]?["frameId"]?.GetValue<int>() == byFrame[0]?["frameId"]?.GetValue<int>(), "The MV3 execute API selects child frames by native frame ID and document ID");
        check(frameResults?["main"] is JsonArray { Count: 1 } main && main[0]?["result"]?.GetValue<string>() == "true", "MAIN execution targets the same native child document");
        check(frameResults?["freshWorld"] is JsonArray { Count: 1 } freshWorld && freshWorld[0]?["result"]?["runtime"]?.GetValue<string>() == "undefined", "MV3 execution creates a fresh isolated world with messaging disabled by default");
        check(frameResults?["multiSource"] is JsonArray { Count: 1 } multiSource && multiSource[0]?["result"]?.GetValue<string>() == "firstsecond", "MV3 execution separates adjacent JavaScript sources safely");

        var mv2Folder = Path.Combine(DataStore.Root, "MV2-coexistence-fixture"); Directory.CreateDirectory(mv2Folder);
        await File.WriteAllTextAsync(Path.Combine(mv2Folder, "manifest.json"), """{"manifest_version":2,"name":"SearcheXtra MV2 coexistence fixture","version":"1.0","content_scripts":[{"matches":["http://127.0.0.1/*"],"js":["content.js"],"run_at":"document_end"}]}""");
        await File.WriteAllTextAsync(Path.Combine(mv2Folder, "content.js"), "document.documentElement.setAttribute('data-sx-mv2','native');");
        await InstallExtensionFolderAsync(mv2Folder);
        await SelectAsync(website); await ReloadUserScriptTestAsync(websiteView.Control.CoreWebView2);
        await WaitUserScriptAsync(async () => (await EvaluateUserScriptTestAsync(websiteView.Control.CoreWebView2, "document.documentElement.getAttribute('data-sx-mv2')"))?.GetValue<string>() == "native" && (await State())?["started"]?.GetValue<string>() == "true", "MV2 and ScriptCat MV3 execute together");
        check(Settings.Extensions.Any(extension => extension.ManifestVersion == 2 && extension.Enabled) && item.Enabled, "MV2 extensions and the original ScriptCat MV3 extension coexist in one profile");
        await SetUserScriptsAllowedAsync(item, false);
        await ReloadUserScriptTestAsync(websiteView.Control.CoreWebView2);
        await WaitUserScriptAsync(() => Task.FromResult(!website.Loading), "permission revocation reload"); await Task.Delay(1200);
        check((await State())?["started"] == null, "Revoking Allow user scripts prevents the actual ScriptCat script from running");
        check((await EvaluateUserScriptTestAsync(websiteView.Control.CoreWebView2, "document.documentElement.getAttribute('data-sx-mv2')"))?.GetValue<string>() == "native", "MV2 content scripts remain operational after MV3 user-script access is revoked");
        await SetUserScriptsAllowedAsync(item, true);
        await ReloadUserScriptTestAsync(websiteView.Control.CoreWebView2);
        await WaitUserScriptAsync(async () => int.TryParse((await State())?["count"]?.GetValue<string>(), out var count) && count > beforeRuntimeReload && (await State())?["xhr"]?.GetValue<string>() == "200:true", "Re-enabling user-script access restores the installed ScriptCat script and its GM data");
        check(true, "Re-enabling Allow user scripts restores real ScriptCat execution and preserves GM data");
    }

    private static async Task WaitUserScriptAsync(Func<Task<bool>> predicate, string label)
    {
        var started = Stopwatch.StartNew();
        while (!await predicate())
        {
            if (started.Elapsed > TimeSpan.FromSeconds(60)) throw new TimeoutException("User-script integration timed out: " + label);
            await Task.Delay(100);
        }
    }

    private static async Task ReloadUserScriptTestAsync(CoreWebView2 core)
    {
        var loaded = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        void Completed(CoreWebView2 sender, CoreWebView2NavigationCompletedEventArgs args) => loaded.TrySetResult(args.IsSuccess);
        core.NavigationCompleted += Completed;
        try { core.Reload(); if (!await loaded.Task.WaitAsync(TimeSpan.FromSeconds(30))) throw new InvalidOperationException("The integration test page could not reload."); }
        finally { core.NavigationCompleted -= Completed; }
    }

    private static async Task<JsonNode?> EvaluateUserScriptTestAsync(CoreWebView2 core, string expression)
    {
        File.AppendAllText(Path.Combine(DataStore.Root, "user-scripts-test.log"), "evaluate " + core.Source + " " + expression[..Math.Min(expression.Length, 140)] + "\n");
        // Let the extension Promise settle between short DevTools commands.
        var originalSource = core.Source;
        var key = "__sxNativeTestPromise" + Guid.NewGuid().ToString("N");
        var script = "(()=>{const value=(" + expression + ");if(!value||typeof value.then!=='function')return {done:true,value};const state={done:false};globalThis[" + JsonSerializer.Serialize(key) + "]=state;Promise.resolve(value).then(value=>{state.value=value;state.done=true},error=>{state.error=String(error?.stack||error);state.done=true});return state})()";
        try
        {
            var started = Stopwatch.StartNew();
            for (;;)
            {
                var raw = await core.CallDevToolsProtocolMethodAsync("Runtime.evaluate", JsonSerializer.Serialize(new { expression = script, awaitPromise = false, returnByValue = true }));
                var response = JsonNode.Parse(raw);
                if (response?["exceptionDetails"] is { } exception) throw new InvalidOperationException(exception["exception"]?["description"]?.GetValue<string>() ?? exception.ToJsonString());
                var state = response?["result"]?["value"];
                if (state?["done"]?.GetValue<bool>() == true)
                {
                    File.AppendAllText(Path.Combine(DataStore.Root, "user-scripts-test.log"), "result " + state.ToJsonString() + "\n");
                    if (state["error"] is JsonValue error) throw new InvalidOperationException(error.GetValue<string>());
                    return state["value"]?.DeepClone();
                }
                if (state == null)
                {
                    var replacement = "The extension document was replaced during evaluation. Original=" + originalSource + "; current=" + core.Source + "; key=" + key + "; response=" + raw;
                    File.AppendAllText(Path.Combine(DataStore.Root, "user-scripts-test.log"), replacement + "\n");
                    throw new InvalidOperationException(replacement);
                }
                if (started.Elapsed > TimeSpan.FromSeconds(30)) throw new TimeoutException("Extension JavaScript did not settle: " + expression[..Math.Min(120, expression.Length)]);
                await Task.Delay(100);
                script = "globalThis[" + JsonSerializer.Serialize(key) + "]";
            }
        }
        finally
        {
            try { await core.CallDevToolsProtocolMethodAsync("Runtime.evaluate", JsonSerializer.Serialize(new { expression = "delete globalThis[" + JsonSerializer.Serialize(key) + "]" })); }
            catch (Exception error) when (error is System.Runtime.InteropServices.COMException or InvalidOperationException) { }
        }
    }
}
