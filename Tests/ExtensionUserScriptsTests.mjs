import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

// Run the shipping macOS shim, including ScriptCat's real availability probe.
const swift = fs.readFileSync(new URL('../Sources/SearcheXtra/ExtensionShims.swift', import.meta.url), 'utf8');
const start = swift.indexOf('      const scripting = chrome.scripting;');
const end = swift.indexOf('      // WebKit says "install" again', start);
assert(start >= 0 && end > start);
const shim = swift.slice(start, end);
const event = () => ({ listeners: new Set(), addListener(f) { this.listeners.add(f); }, removeListener(f) { this.listeners.delete(f); } });

function fixture({ allowed = false, optional = false, background = false, saved = [] } = {}) {
  const state = { allowed, saved: structuredClone(saved), calls: [], worlds: [], registered: new Map() };
  const runtime = {
    id: 'userscript-fixture', getManifest: () => optional ? { optional_permissions: ['userScripts'] } : { permissions: ['userScripts'] },
    onUserScriptMessage: event(), onUserScriptConnect: event(), onConnect: event(), onMessage: event(),
  };
  const chrome = { runtime, scripting: {
    async registerContentScripts(scripts) { for (const s of scripts) { if (state.registered.has(s.id)) throw Error('Duplicate script id'); state.registered.set(s.id, s); } },
    async unregisterContentScripts({ ids } = {}) { if (!ids) state.registered.clear(); else ids.forEach(id => state.registered.delete(id)); },
    async getRegisteredContentScripts() { return [...state.registered.values()]; },
  } };
  const root = { chrome };
  const native = async (api, args) => {
    state.calls.push(api);
    if (api === 'permissions.userScriptsAllowed') return state.allowed;
    if (api.startsWith('userScripts.') && !state.allowed) throw Error('User scripts are disabled');
    switch (api) {
      case 'runtime.reload': return;
      case 'userScripts.list': return structuredClone(state.saved);
      case 'userScripts.register': state.saved.push(...structuredClone(args[0])); return;
      case 'userScripts.update': state.saved = state.saved.map(s => ({ ...s, ...structuredClone(args[0].find(update => update.id === s.id)) })); return;
      case 'userScripts.unregister': state.saved = args[0].ids ? state.saved.filter(s => !args[0].ids.includes(s.id)) : []; return;
      case 'userScripts.world':
        state.worlds = state.worlds.filter(w => (w.worldId || '') !== (args[0].worldId || ''));
        if (!args[0].reset) state.worlds.push(structuredClone(args[0]));
        return;
      case 'userScripts.worlds': return structuredClone(state.worlds);
      default: throw Error(api);
    }
  };
  vm.runInNewContext(`(() => {${shim}\n})()`, {
    chrome, runtime, root, background, native,
    put: (o, k, v) => { o[k] = v; },
    put2: (k, v) => { chrome[k] = v; },
    withLastError: (e, callback) => { runtime.lastError = { message: e.message }; try { callback(); } finally { delete runtime.lastError; } },
  });
  return { state, chrome };
}

async function scriptCatProbe(chrome) {
  if (typeof chrome.userScripts?.getScripts !== 'function') return false;
  const scripts = await chrome.userScripts.getScripts({ ids: ['scriptcat-content', 'scriptcat-inject'] });
  if (!scripts || typeof scripts.length !== 'number') return false;
  if (scripts[0]?.id) return true;
  const id = 'undefined-id-1234';
  await chrome.userScripts.register([{ id, js: [{ code: 'void 0;' }], matches: ['https://not-found.scriptcat.org/'], world: 'USER_SCRIPT' }]);
  await chrome.userScripts.unregister({ ids: [id] });
  return true;
}

for (const optional of [false, true]) {
  const { state, chrome } = fixture({ optional });
  await assert.rejects(scriptCatProbe(chrome), /disabled/);
  assert.equal(state.registered.size, 0);
  state.allowed = true;
  assert.equal(await scriptCatProbe(chrome), true);
  assert.equal(state.registered.size, 0);
  assert.equal(state.saved.length, 0);
  state.allowed = false;
  await new Promise(resolve => chrome.userScripts.getScripts(() => {
    assert.match(chrome.runtime.lastError.message, /disabled/);
    resolve();
  }));
}

const saved = [{ id: 'scriptcat-content', js: [{ code: 'void 0;' }], matches: ['<all_urls>'], world: 'USER_SCRIPT' }];
const disabled = fixture({ background: true, saved });
disabled.chrome.runtime.reload();
await Promise.resolve();
assert(disabled.state.calls.includes('runtime.reload'), 'Extension self-reload must replace browser-owned user-script worlds and transport');
await assert.rejects(disabled.chrome.userScripts.getScripts(), /disabled/);
assert.deepEqual(disabled.state.saved, saved);
disabled.state.allowed = true;
assert.equal(JSON.stringify(await disabled.chrome.userScripts.getScripts()), JSON.stringify(saved));
await disabled.chrome.userScripts.update([{ id: 'scriptcat-content', runAt: 'document_start' }]);
assert.equal(disabled.state.saved[0].runAt, 'document_start');
await disabled.chrome.userScripts.configureWorld({ messaging: true });
assert.equal((await disabled.chrome.userScripts.getWorldConfigurations())[0].messaging, true);
await disabled.chrome.userScripts.resetWorldConfiguration();
assert.equal((await disabled.chrome.userScripts.getWorldConfigurations()).length, 0);
assert.equal(disabled.state.registered.size, 0, 'User scripts are not exposed as privileged native extension content scripts');
assert(disabled.state.calls.includes('userScripts.register') === false);
assert(disabled.state.calls.includes('userScripts.update'));

// macOS 15 WebKit's alarm binding does not accept the Chrome callback overload
// used during ScriptCat startup. The real scheduler must receive only its args.
const alarmStart = swift.indexOf('      if (chrome.alarms && typeof chrome.alarms.create === "function") {');
const alarmEnd = swift.indexOf('      // The popup Search shows', alarmStart);
assert(alarmStart >= 0 && alarmEnd > alarmStart);
const alarmCalls = [];
const alarmRuntime = {};
const alarms = { create(...args) {
  assert.equal(this, alarms);
  assert(args.every(value => typeof value !== 'function'));
  alarmCalls.push(args);
  if (args[0] === 'bad') throw new Error('Invalid alarm');
  return Promise.resolve();
} };
vm.runInNewContext(swift.slice(alarmStart, alarmEnd), {
  chrome: { alarms }, put: (target, key, value) => { target[key] = value; },
  withLastError(error, callback) { alarmRuntime.lastError = error; try { callback(); } finally { delete alarmRuntime.lastError; } },
});
await new Promise(resolve => alarms.create('cloudSync', { periodInMinutes: 60 }, resolve));
await alarms.create('cleanup', { delayInMinutes: 1 });
await new Promise(resolve => alarms.create('bad', {}, () => { assert.match(alarmRuntime.lastError.message, /Invalid alarm/); resolve(); }));
await assert.rejects(alarms.create('bad', {}), /Invalid alarm/);
assert.deepEqual(alarmCalls[0], ['cloudSync', { periodInMinutes: 60 }]);
assert.equal(alarmRuntime.lastError, undefined);
console.log('PASS: macOS user-script opt-in, ScriptCat probe, optional permission, callback errors, native-world forwarding and alarm callback compatibility');
