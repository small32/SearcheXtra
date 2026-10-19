import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { randomUUID } from 'node:crypto';

const source = fs.readFileSync(new URL('../Windows/SearcheXtra/Assets/extension-user-scripts.js', import.meta.url), 'utf8');
const makeEvent = () => ({ listeners: new Set(), addListener(f) { this.listeners.add(f); }, removeListener(f) { this.listeners.delete(f); }, hasListener(f) { return this.listeners.has(f); }, emit(...args) { return [...this.listeners].map(f => f(...args)); } });
function fixture({ nativeWorks = false, allowed = false, manifest = { manifest_version: 3, permissions: ['userScripts'] }, transportErrors = {}, timer = setTimeout } = {}) {
  const calls = [], scripts = new Map(), worlds = new Map();
  const native = { async getScripts() { calls.push('native.getScripts'); if (!nativeWorks) throw Error('User scripts are unavailable'); return []; }, async register() { calls.push('native.register'); } };
  const runtime = { id: 'abcdefghijklmnopabcdefghijklmnop', getManifest: () => manifest, onMessage: makeEvent(), onConnect: makeEvent(), sendMessage(packet, callback) {
    calls.push(packet.api);
    const transportError = transportErrors[packet.api]?.shift();
    if (transportError) {
      runtime.lastError = { message: transportError };
      try { callback(); } finally { delete runtime.lastError; }
      return;
    }
    if (packet.api === 'isAllowed') { callback({ __searchextraUserScripts: 1, result: allowed }); return; }
    if (!allowed) { callback({ __searchextraUserScripts: 1, error: 'User scripts are disabled.' }); return; }
    const [arg] = packet.args;
    let result;
    switch (packet.api) {
      case 'getScripts': result = [...scripts.values()].filter(s => !arg?.ids || arg.ids.includes(s.id)); break;
      case 'register': arg.forEach(s => scripts.set(s.id, s)); break;
      case 'update': arg.forEach(s => scripts.set(s.id, { ...scripts.get(s.id), ...s })); break;
      case 'unregister': if (arg?.ids) arg.ids.forEach(id => scripts.delete(id)); else scripts.clear(); break;
      case 'configureWorld': worlds.set(arg.worldId || '', arg); break;
      case 'getWorldConfigurations': result = [...worlds.values()]; break;
      case 'resetWorldConfiguration': worlds.delete(arg?.worldId || ''); break;
      case 'execute': result = [{ frameId: 0, result: 'executed' }]; break;
      default: throw Error(packet.api);
    }
    callback({ __searchextraUserScripts: 1, result });
  } };
  const chrome = { runtime, userScripts: native };
  vm.runInNewContext(source, { chrome, setTimeout: timer, Promise });
  return { chrome, runtime, calls, scripts, worlds, setAllowed(value) { allowed = value; } };
}

// The real ScriptCat gate registers and unregisters a temporary script.
const disabled = fixture();
await assert.rejects(disabled.chrome.userScripts.getScripts(), /disabled/);
await new Promise(resolve => disabled.chrome.userScripts.getScripts(() => { assert.match(disabled.runtime.lastError.message, /disabled/); resolve(); }));
assert.equal(disabled.runtime.lastError, undefined);
disabled.setAllowed(true);
await disabled.chrome.userScripts.register([{ id: 'scriptcat-probe', matches: ['https://not-found.scriptcat.org/*'], js: [{ code: 'void 0;' }] }]);
assert.equal((await disabled.chrome.userScripts.getScripts({ ids: ['scriptcat-probe'] }))[0].id, 'scriptcat-probe');
await disabled.chrome.userScripts.update([{ id: 'scriptcat-probe', allFrames: true }]);
assert.equal((await disabled.chrome.userScripts.getScripts())[0].allFrames, true);
await disabled.chrome.userScripts.unregister({ ids: ['scriptcat-probe'] });
assert.equal((await disabled.chrome.userScripts.getScripts()).length, 0);
await disabled.chrome.userScripts.configureWorld({ messaging: true });
assert.equal((await disabled.chrome.userScripts.getWorldConfigurations())[0].messaging, true);
await disabled.chrome.userScripts.resetWorldConfiguration();
assert.equal((await disabled.chrome.userScripts.getWorldConfigurations()).length, 0);
assert.equal((await disabled.chrome.userScripts.execute({ target: { tabId: 1 }, js: [{ code: '42' }] }))[0].result, 'executed');

const native = fixture({ nativeWorks: true, allowed: true });
await native.chrome.userScripts.register([]);
assert.deepEqual(native.calls, ['register']);
native.setAllowed(false);
await assert.rejects(native.chrome.userScripts.register([]), /disabled/);
assert.equal(native.calls.filter(call => call.startsWith('native.')).length, 0);
const mv2 = fixture({ manifest: { manifest_version: 2, permissions: ['userScripts'] } });
assert.equal(mv2.runtime.onMessage.listeners.size, 0);

// ScriptCat probes availability while its worker and hidden bridge reconnect.
// A native reload can close the first read's port; mutations must never replay.
const closedPort = 'The message port closed before a response was received.';
for (const api of ['getScripts', 'getWorldConfigurations']) {
  const reconnecting = fixture({ allowed: true, transportErrors: { [api]: [closedPort] } });
  assert.equal((await reconnecting.chrome.userScripts[api]()).length, 0);
  assert.deepEqual(reconnecting.calls, [api, api]);
}
const lostMutation = fixture({ allowed: true, transportErrors: { register: [closedPort] } });
await assert.rejects(lostMutation.chrome.userScripts.register([]), /message port closed/);
assert.deepEqual(lostMutation.calls, ['register']);
const deniedRead = fixture();
await assert.rejects(deniedRead.chrome.userScripts.getScripts(), /disabled/);
assert.deepEqual(deniedRead.calls, ['getScripts']);
const neverReconnects = fixture({ allowed: true, transportErrors: { getScripts: Array(41).fill(closedPort) }, timer: callback => queueMicrotask(callback) });
await assert.rejects(neverReconnects.chrome.userScripts.getScripts(), /message port closed/);
assert.equal(neverReconnects.calls.length, 41, 'Read reconnection retries remain bounded');

// Native identity is based on Chromium's sender, never a webpage-provided tab id.
let identity;
disabled.runtime.onMessage.emit({ __sxUserScriptPageIdentity: true }, { id: disabled.runtime.id, tab: { id: 17 }, frameId: 4 }, value => { identity = value; });
assert.equal(identity.tab.id, 17);
assert.equal(identity.frameId, 4);
let spoofed = false;
disabled.runtime.onMessage.emit({ __sxUserScriptPageIdentity: true }, { id: 'other-extension' }, () => { spoofed = true; });
assert.equal(spoofed, false);

let normalMessage = false;
assert.deepEqual(disabled.runtime.onMessage.emit({ ordinary: true }, { id: disabled.runtime.id }, () => { normalMessage = true; }), [undefined]);
assert.equal(normalMessage, false);
disabled.runtime.onUserScriptMessage.addListener(async (message, sender) => ({ answer: message.value, tabId: sender.tab.id }));
const response = await new Promise(resolve => {
  const result = disabled.runtime.onMessage.emit({ __searchextraUserScripts: 1, event: 'message', message: { value: 42 }, sender: { tab: { id: 17 } } }, { id: disabled.runtime.id }, resolve);
  assert.deepEqual(result, [true]);
});
assert.equal(response.answer, 42);
assert.equal(response.tabId, 17);

const port = { name: '__searchextraUserScriptPort:test', sender: { id: disabled.runtime.id }, onMessage: makeEvent(), onDisconnect: makeEvent(), postMessage(message) { this.last = message; }, disconnect() { this.onDisconnect.emit(); } };
let connected;
disabled.runtime.onUserScriptConnect.addListener(value => { connected = value; });
disabled.runtime.onConnect.emit(port);
port.onMessage.emit({ __searchextraUserScripts: 1, event: 'connect', name: 'scriptcat', sender: { tab: { id: 17 } } });
assert.equal(connected.name, 'scriptcat');
assert.equal(connected.sender.tab.id, 17);
let message;
connected.onMessage.addListener(value => { message = value; });
port.onMessage.emit('from user script');
assert.equal(message, 'from user script');
connected.postMessage('reply'); assert.equal(port.last, 'reply');

// Run the actual generated bridge, validating sender checks and pending request ids.
const packageSource = fs.readFileSync(new URL('../Windows/SearcheXtra/ExtensionUserScriptsPackage.cs', import.meta.url), 'utf8');
const bridge = packageSource.match(/private const string BridgeScript = """\r?\n([\s\S]*?)\r?\n\s*""";/)[1].replace('__TOKEN_JSON__', '"test-secret"');
const posted = [], bridgeRuntime = { id: disabled.runtime.id, onMessage: makeEvent(), async sendMessage() { return { ok: true }; }, connect() { return port; } };
const context = { chrome: { runtime: bridgeRuntime, webview: { postMessage: packet => posted.push(packet) }, permissions: { async getAll() { return { permissions: ['userScripts'], origins: ['https://example.com/*'] }; }, onAdded: makeEvent(), onRemoved: makeEvent() }, extension: { isAllowedFileSchemeAccess(callback) { callback(false); } } }, crypto: { randomUUID }, setTimeout, clearTimeout };
vm.createContext(context); vm.runInContext(bridge, context);
await new Promise(resolve => setImmediate(resolve));
assert.equal(posted[0].kind, 'extensionUserScriptsReady');
assert.equal(posted[0].token, 'test-secret');
assert.equal(posted[0].origins[0], 'https://example.com/*');
assert.equal(posted[0].fileAccess, false);
const hostRequest = { __searchextraUserScripts: 1, api: 'getScripts', args: [] };
assert.deepEqual(bridgeRuntime.onMessage.emit(hostRequest, { id: 'other' }, () => {}), [undefined]);
let answer;
assert.deepEqual(bridgeRuntime.onMessage.emit(hostRequest, { id: bridgeRuntime.id, tab: { id: 17 } }, value => { answer = value; }), [true]);
const request = posted.at(-1);
assert.equal(request.kind, 'extensionUserScripts');
assert.equal(request.sender.tab.id, 17);
context.__searchextraUserScriptsReply({ requestId: 'wrong-request', result: ['wrong'] });
assert.equal(answer, undefined);
context.__searchextraUserScriptsReply({ requestId: request.requestId, result: ['correct'] });
assert.equal(answer.result[0], 'correct');
await context.__searchextraUserScriptsEvent({ type: 'message', eventId: 'one', message: 'hello', sender: { tab: { id: 17 } } });
assert.equal(posted.at(-1).kind, 'extensionUserScriptsEventResult');
assert.equal(posted.at(-1).eventId, 'one');
assert.equal(posted.at(-1).result.ok, true);
console.log('PASS: Windows MV3 userScripts bridge, ScriptCat probe, opt-in gating, callbacks, native API bypass, identity and messaging/ports');
