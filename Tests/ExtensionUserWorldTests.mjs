import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

// Exercise the shipping WKContentWorld bootstrap, not a second implementation.
const swift = fs.readFileSync(new URL('../Sources/SearcheXtra/ExtensionUserScripts.swift', import.meta.url), 'utf8');
const functionText = swift.slice(swift.indexOf('    static func bootstrap('), swift.indexOf('    private final class FrameBridge'));
const bootstrap = functionText.match(/#"""([\s\S]*?)"""#/)[1];
function fixture(messaging = true) {
  let serial = 0;
  const calls = [], lifecycle = {};
  const code = bootstrap.replaceAll('\\#(json(channel))', '"fixtureChannel"')
    .replaceAll('\\#(json(id))', '"fixtureExtension"')
    .replaceAll('\\#(messaging ? "true" : "false")', String(messaging));
  const context = vm.createContext({ console, addEventListener: (name, listener) => { lifecycle[name] = listener; }, crypto: { randomUUID: () => String(++serial) }, webkit: { messageHandlers: {
    fixtureChannel: { async postMessage(body) {
      calls.push(structuredClone(body));
      if (body.operation === 'message') return body.message.fail ? { error: 'User-script context was revoked' } : { value: { echo: body.message } };
      return { value: true };
    } },
  } } });
  vm.runInContext(code, context);
  return { context, calls, lifecycle, run: expression => vm.runInContext(expression, context) };
}

const user = fixture();
assert.equal(user.run('new Function("return globalThis.chrome.runtime.id")()'), 'fixtureExtension');
assert.equal(user.run('new Function("return browser === chrome")()'), true);
assert.equal(user.run('typeof chrome.storage'), 'undefined');
assert.equal(user.run('typeof chrome.tabs'), 'undefined');
assert.equal(user.run('typeof chrome.runtime.sendNativeMessage'), 'undefined');
assert.equal(JSON.stringify(await user.run('chrome.runtime.sendMessage({ gm: "storage" })')), '{"echo":{"gm":"storage"}}');
assert.equal(user.calls.at(-1).documentId, user.calls[0].documentId);
assert.equal(user.calls.at(-1).operation, 'message');
user.run('globalThis.callbackResult = null; chrome.runtime.sendMessage({ fail: true }, () => { callbackResult = chrome.runtime.lastError.message; })');
await new Promise(resolve => setImmediate(resolve));
assert.equal(user.run('callbackResult'), 'User-script context was revoked');
assert.equal(user.run('chrome.runtime.lastError'), undefined);
await assert.rejects(user.run('chrome.runtime.sendMessage({ fail: true })'), /revoked/);

user.run(`globalThis.received = []; globalThis.disconnects = 0;
  globalThis.port = chrome.runtime.connect({ name: 'gm-port' });
  port.onMessage.addListener(value => received.push(value));
  port.onDisconnect.addListener(() => disconnects++);
  port.postMessage({ first: true });`);
await new Promise(resolve => setImmediate(resolve));
const connect = user.calls.find(c => c.operation === 'connect');
const post = user.calls.find(c => c.operation === 'post');
assert.equal(connect.name, 'gm-port');
assert.equal(connect.port, post.port);
assert.deepEqual(post.message, { first: true });
user.run(`__searchUserPortEvent(${JSON.stringify(connect.port)}, 'message', { reply: true })`);
assert.equal(user.run('JSON.stringify(received)'), '[{"reply":true}]');
user.run('port.disconnect(); port.disconnect()');
await new Promise(resolve => setImmediate(resolve));
assert.equal(user.run('disconnects'), 1);
assert.equal(user.calls.filter(c => c.operation === 'disconnect').length, 1);
assert.throws(() => user.run('port.postMessage("too late")'), /disconnected/);
user.run('globalThis.remotePort = chrome.runtime.connect({ name: "remote" }); remotePort.onDisconnect.addListener(() => disconnects++)');
await new Promise(resolve => setImmediate(resolve));
const remote = user.calls.filter(c => c.operation === 'connect').at(-1);
user.run(`__searchUserPortEvent(${JSON.stringify(remote.port)}, 'disconnect', null)`);
assert.equal(user.run('disconnects'), 2);
assert.throws(() => user.run('remotePort.postMessage("too late")'), /disconnected/);
user.run('globalThis.leavingPort = chrome.runtime.connect({ name: "leaving" }); leavingPort.onDisconnect.addListener(() => disconnects++)');
await new Promise(resolve => setImmediate(resolve));
user.lifecycle.pagehide();
await new Promise(resolve => setImmediate(resolve));
assert.equal(user.run('disconnects'), 3);
assert.equal(user.calls.filter(c => c.operation === 'bye').length, 1);
user.lifecycle.pageshow({ persisted: true });
await new Promise(resolve => setImmediate(resolve));
assert.equal(user.calls.filter(c => c.operation === 'hello').length, 2);

const disabled = fixture(false);
assert.equal(disabled.run('typeof chrome'), 'undefined');
assert.equal(disabled.run('typeof browser'), 'undefined');
assert.equal(disabled.calls.length, 1);
assert.equal(disabled.calls[0].operation, 'hello');
const other = fixture();
user.run('globalThis.privateToThisWorld = 12');
assert.equal(other.run('typeof privateToThisWorld'), 'undefined');

const discoveryCode = swift.slice(swift.indexOf('    static func discovery('), swift.indexOf('    private final class FrameDiscovery')).match(/#"""([\s\S]*?)"""#/)[1]
  .replaceAll('\\#(json(channel))', '"discover"');
const discoveries = [], lifecycle = {};
const discoveryWorld = vm.createContext({ crypto: { randomUUID: () => 'document-identity' }, addEventListener: (name, listener) => { lifecycle[name] = listener; },
  webkit: { messageHandlers: { discover: { async postMessage(body) { discoveries.push(body); return true; } } } } });
vm.runInContext(discoveryCode, discoveryWorld);
assert.equal(discoveries.length, 1);
assert.equal(discoveries[0].phase, 'hello');
assert.equal(discoveryWorld.__searchFrameDocument, 'document-identity');
await vm.runInContext('__searchDiscoverFrame()', discoveryWorld);
assert.equal(discoveries[1].documentId, discoveries[0].documentId);
lifecycle.pagehide();
assert.equal(discoveries.at(-1).phase, 'goodbye');
lifecycle.pageshow({ persisted: true });
assert.equal(discoveries.at(-1).phase, 'hello');

const compiledText = swift.slice(swift.indexOf('    static func compiled('), swift.indexOf('    static func bootstrap('));
const compiled = compiledText.match(/#"""([\s\S]*?)"""#/)[1];
function inject(href, overrides = {}) {
  const rules = { matches: ['*://*.example.test/path*'], excludeMatches: [], includeGlobs: [], excludeGlobs: [], granted: ['<all_urls>'], denied: [], ...overrides };
  const code = compiled.replaceAll('\\#(json(matching))', JSON.stringify(rules)).replaceAll('\\#(source)', 'globalThis.injected = (globalThis.injected || 0) + 1;')
    .replace(/\\#\(idle \? [^\n]+/, 'run();');
  const context = vm.createContext({ URL, location: { href }, injected: 0 });
  vm.runInContext(code, context);
  return context.injected;
}
assert.equal(inject('https://example.test/path?q=1'), 1);
assert.equal(inject('https://frame.example.test/path'), 1);
assert.equal(inject('https://evil-example.test/path'), 0);
assert.equal(inject('ftp://example.test/path'), 0);
assert.equal(inject('https://example.test/elsewhere'), 0);
assert.equal(inject('https://example.test/path', { granted: [] }), 0);
assert.equal(inject('https://example.test/path', { denied: ['https://example.test/*'] }), 0);
assert.equal(inject('https://example.test/path', { excludeMatches: ['*://*.example.test/path'] }), 0);
assert.equal(inject('https://example.test/path?q=1', { includeGlobs: ['*q=?'] }), 1);
assert.equal(inject('https://example.test/path?q=1', { excludeGlobs: ['*q=?'] }), 0);
assert.equal(inject('https://example.test/path?q=1', { matches: ['https://example.test/path?q=1'] }), 1);
assert.equal(inject('https://example.test/pathXq=1', { matches: ['https://example.test/path?q=1'] }), 0);
assert.equal(inject('chrome-extension://another-id/path', { matches: ['<all_urls>'] }), 0);

// The host resolves the numeric WebKit tab from a native window/index
// selector; supplied script content never chooses another tab or sender.
const hostCode = swift.slice(swift.indexOf('    nonisolated static let hostScript = #"""')).match(/#"""([\s\S]*?)"""#/)[1];
const outbound = [], events = [];
const listeners = () => { const handlers = new Set(); return { addListener: f => handlers.add(f), emit: value => [...handlers].forEach(f => f(value)) }; };
let nativePort;
const host = vm.createContext({ chrome: {
  windows: { async getAll() { return [{ id: 2, left: 20, top: 40, width: 900, height: 600, tabs: [{ id: 42, index: 1, url: 'https://fixture.test/' }] }]; } },
  scripting: { async executeScript({ target, args }) {
    assert.equal(target.tabId, 42);
    if (args.length === 1) {
      assert.equal(args[0], 'target-marker');
      const rows = [
        { frameId: 0, documentId: '11111111-1111-4111-8111-111111111111', result: { token: 'native-main', url: 'https://fixture.test/' } },
        { frameId: 7, documentId: '22222222-2222-4222-8222-222222222222', result: { token: 'native-child', url: 'https://fixture.test/frame' } },
      ];
      if (target.frameIds) return rows.filter(row => target.frameIds.includes(row.frameId));
      if (target.documentIds) return rows.filter(row => target.documentIds.includes(row.documentId));
      return target.allFrames ? rows : [rows[0]];
    }
    assert.equal(target.allFrames, true); assert.deepEqual([...args], ['native-marker', 'native-token']);
    return [{ frameId: 7, documentId: '22222222-2222-4222-8222-222222222222', result: { matched: true, url: 'https://fixture.test/frame' } }];
  } },
  runtime: {
    async sendMessage(body) { outbound.push(body); return { ok: true }; },
    connect({ name }) { nativePort = { name, onMessage: listeners(), onDisconnect: listeners(), postMessage: message => outbound.push(message), disconnect() {} }; return nativePort; },
  },
}, webkit: { messageHandlers: { userScriptHost: { postMessage: body => events.push(body) } } } });
vm.runInContext(hostCode, host);
host.selector = { left: 20, top: 40, width: 900, height: 600, index: 1, marker: 'native-marker', token: 'native-token' };
host.sender = { id: 'fixtureExtension', frameId: 3, worldId: 'named-world', url: 'https://fixture.test/frame' };
assert.equal(JSON.stringify(await vm.runInContext('__searchUserScriptHost("message", { message: { gm: true } }, selector, sender)', host)), '{"ok":true}');
assert.equal(outbound[0].__searchUserScript, true);
assert.equal(outbound[0].__searchUserSender.tab.id, 42);
assert.equal(outbound[0].__searchUserSender.frameId, 7);
assert.equal(outbound[0].__searchUserSender.documentId, '22222222-2222-4222-8222-222222222222');
assert.equal(outbound[0].__searchUserSender.worldId, 'named-world');
await vm.runInContext('__searchUserScriptHost("connect", { port: "sourcePort", name: "gm-port" }, selector, sender)', host);
assert.equal(nativePort.name, 'search-us:gm-port');
assert.equal(outbound[1].__searchUserHandshake, true);
assert.equal(outbound[1].sender.tab.id, 42);
nativePort.onMessage.emit({ result: 9 });
assert.equal(JSON.stringify(events[0]), '{"port":"sourcePort","kind":"message","value":{"result":9}}');
host.selector = { ...host.selector, left: 999 };
await assert.rejects(vm.runInContext('__searchUserScriptHost("message", { message: "wrong window" }, selector, sender)', host), /window/);
host.selector = { ...host.selector, left: 20, marker: 'target-marker' };
let targets = await vm.runInContext('__searchUserScriptHost("targets", { target: { allFrames: true } }, selector, {})', host);
assert.equal(JSON.stringify(targets.map(frame => frame.frameId)), '[0,7]');
targets = await vm.runInContext('__searchUserScriptHost("targets", { target: { frameIds: [7] } }, selector, {})', host);
assert.equal(JSON.stringify(targets.map(frame => frame.token)), '["native-child"]');
targets = await vm.runInContext('__searchUserScriptHost("targets", { target: { documentIds: ["22222222-2222-4222-8222-222222222222"] } }, selector, {})', host);
assert.equal(JSON.stringify(targets.map(frame => frame.frameId)), '[7]');
targets = await vm.runInContext('__searchUserScriptHost("targets", { target: {} }, selector, {})', host);
assert.equal(JSON.stringify(targets.map(frame => frame.frameId)), '[0]');
await assert.rejects(vm.runInContext('__searchUserScriptHost("targets", { target: { frameIds: [999] } }, selector, {})', host), /target document/);

// Include the existing own-page port numbering shim: the bridge is a real
// extension page, and both ends must unwrap that transport before ScriptCat
// sees a handshake or a GM payload.
const shims = fs.readFileSync(new URL('../Sources/SearcheXtra/ExtensionShims.swift', import.meta.url), 'utf8');
const userStart = shims.indexOf('      const scripting = chrome.scripting;');
const userEnd = shims.indexOf('      // WebKit says "install" again', userStart);
const portStart = shims.indexOf('      if (runtime && typeof runtime.connect === "function" && runtime.onConnect) {');
const portEnd = shims.indexOf('      // Members of namespaces WebKit has.', portStart);
const bridgeURL = 'chrome-extension://fixtureExtension/_search/user-script-host.html';
const portEvent = () => {
  const listeners = new Set();
  return { listeners, addListener: f => listeners.add(f), removeListener: f => listeners.delete(f), hasListener: f => listeners.has(f),
    hasListeners: () => !!listeners.size, fire: (...values) => [...listeners].forEach(f => f(...values)) };
};
const workerConnect = portEvent();
function extensionFixture(background) {
  const runtime = { id: 'fixtureExtension', getURL: path => 'chrome-extension://fixtureExtension/' + path,
    getManifest: () => ({ permissions: ['userScripts'] }), onMessage: portEvent(), onUserScriptMessage: portEvent(), onUserScriptConnect: portEvent(),
    onConnect: background ? workerConnect : portEvent(), connect({ name }) {
      const outgoing = { name, onMessage: portEvent(), onDisconnect: portEvent() };
      const incoming = { name, sender: { id: 'fixtureExtension', url: bridgeURL }, onMessage: portEvent(), onDisconnect: portEvent() };
      outgoing.postMessage = value => queueMicrotask(() => incoming.onMessage.fire(value));
      incoming.postMessage = value => queueMicrotask(() => outgoing.onMessage.fire(value));
      outgoing.disconnect = incoming.disconnect = () => { incoming.onDisconnect.fire(); outgoing.onDisconnect.fire(); };
      queueMicrotask(() => workerConnect.fire(incoming));
      return outgoing;
    },
  };
  const chrome = { runtime };
  const context = vm.createContext({ chrome, runtime, root: {}, background, inContent: false, console, setTimeout, __SEARCH_VERBOSE__: false,
    untabbed: sender => sender, put: (target, key, value) => { target[key] = value; }, put2: (key, value) => { chrome[key] = value; },
    native: async () => undefined, withLastError: () => {} });
  vm.runInContext(shims.slice(userStart, userEnd) + shims.slice(portStart, portEnd), context);
  return { context, runtime, chrome };
}
const worker = extensionFixture(true), pageHost = extensionFixture(false);
const workerMessages = [];
worker.runtime.onUserScriptConnect.addListener(port => {
  assert.equal(port.name, 'gm-storage');
  assert.equal(port.sender.tab.id, 42);
  assert.equal(port.sender.frameId, 7);
  port.onMessage.addListener(message => { workerMessages.push(message); port.postMessage({ saved: true }); });
});
pageHost.chrome.windows = host.chrome.windows;
pageHost.chrome.scripting = host.chrome.scripting;
pageHost.context.webkit = { messageHandlers: { userScriptHost: { postMessage: body => events.push(body) } } };
pageHost.context.selector = { left: 20, top: 40, width: 900, height: 600, index: 1, marker: 'native-marker', token: 'native-token' };
pageHost.context.sender = host.sender;
vm.runInContext(hostCode, pageHost.context);
await vm.runInContext('__searchUserScriptHost("connect", { port: "numbered", name: "gm-storage" }, selector, sender)', pageHost.context);
await vm.runInContext('__searchUserScriptHost("post", { port: "numbered", message: { store: 3 } }, selector, sender)', pageHost.context);
await new Promise(resolve => setImmediate(resolve));
assert.equal(JSON.stringify(workerMessages), '[{"store":3}]');
assert.equal(JSON.stringify(events.at(-1)), '{"port":"numbered","kind":"message","value":{"saved":true}}');
console.log('PASS: macOS real user-world globals, dynamic functions, messaging gate, callbacks, ports, world separation and native sender routing');
