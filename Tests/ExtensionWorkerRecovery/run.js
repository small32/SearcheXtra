const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const source = process.argv[2] ? fs.readFileSync(process.argv[2], 'utf8') : fs.readFileSync(path.join(__dirname, '../../Sources/SearcheXtra/ExtensionShims.swift'), 'utf8');
const script = source.split('nonisolated static let script = #"""\n')[1].split('\n    """#')[0];
const harness = fs.readFileSync(path.join(__dirname, 'shim-harness.js'), 'utf8');
const fixture = vm.runInNewContext(harness + '\nrecoveryFixture', { console });
const drain = async () => { for (let i = 0; i < 40; i++) await Promise.resolve(); };
function load(content, generation = 0, alter = () => {}) {
  const state = fixture(content, generation);
  alter(state);
  vm.runInNewContext(script.replaceAll('__SEARCH_WORKER_GENERATION__', String(generation)), state.root);
  return state;
}
let passed = 0;
async function test(name, run) { await run(); console.log('PASS ' + name); passed++; }
(async () => {
  for (const content of [true, false]) {
    const kind = content ? 'content-script' : 'extension-page';
    await test(kind + ': restart, duplicate notification, no replay/reconnect', async () => {
      const state = load(content), port = state.runtime.connect({ name: 'fixture' });
      let disconnected = 0;
      port.onDisconnect.addListener(() => disconnected++);
      port.postMessage({ question: 'hello' });
      await drain();
      assert.equal(disconnected, 0);
      // With current upstream main the notification has no subscriber and
      // the old port stays open: this assertion reproduces the real entry gap.
      state.subscriptions.forEach(s => s.resolve(1));
      await drain();
      assert.equal(disconnected, 1, kind + ' missed confirmed restart');
      port.nativeDisconnect.fire(port);
      assert.equal(disconnected, 1);
      assert.throws(() => port.postMessage({}), /disconnected port/);
      assert.equal(state.nativePorts.length, 1);
      assert.equal(port.posts.length, 1);
    });
    await test(kind + ': passive subscription, multiple ports, cancellation, native errors', async () => {
      const state = load(content), first = state.runtime.connect(), second = state.runtime.connect();
      let firstCount = 0, secondCount = 0, nativeError;
      first.onDisconnect.addListener(() => { firstCount++; nativeError = state.runtime.lastError; });
      second.onDisconnect.addListener(() => secondCount++);
      await drain();
      assert.equal(state.subscriptions.length, 2, 'each port has a passive lifetime subscription');
      const timers = state.timers.length;
      first.postMessage('one'); second.postMessage('two');
      await drain();
      assert.equal(state.timers.length, timers, 'port messages add no probing timer');
      second.disconnect(); second.disconnect();
      assert.equal(secondCount, 0, 'caller disconnect is silent');
      assert.equal(second.disconnects, 1);
      state.runtime.lastError = { message: 'native failure' };
      first.nativeDisconnect.fire(first);
      delete state.runtime.lastError;
      assert.equal(nativeError.message, 'native failure');
      state.subscriptions[0].resolve(1);
      await drain();
      assert.equal(firstCount, 1); assert.equal(secondCount, 0);
    });
    await test(kind + ': reentrant fresh connection survives, repeated restarts', async () => {
      const state = load(content), old = state.runtime.connect();
      let fresh, oldCount = 0, freshCount = 0;
      old.onDisconnect.addListener(() => {
        oldCount++;
        fresh = state.runtime.connect();
        fresh.onDisconnect.addListener(() => freshCount++);
      });
      state.subscriptions[0].resolve(1);
      await drain();
      assert.equal(oldCount, 1); assert.equal(freshCount, 0);
      assert.equal(state.subscriptions[1].expected, 1);
      fresh.postMessage({ question: 'fresh' });
      let response;
      fresh.onMessage.addListener(message => { response = message; });
      fresh.onMessage.fire({ answer: 'fresh answer' });
      // Numbering wrapper on the own-page port still delivers plain replies.
      assert.equal(response.answer, 'fresh answer');
      state.subscriptions[1].resolve(2);
      await drain();
      assert.equal(oldCount, 1); assert.equal(freshCount, 1);
    });
    await test(kind + ': no restart evidence means no disconnect', async () => {
      for (const outcome of ['pending', 'cancelled', 'rejected']) {
        const state = load(content), port = state.runtime.connect();
        let count = 0;
        port.onDisconnect.addListener(() => count++);
        if (outcome === 'cancelled') state.subscriptions[0].resolve(null);
        if (outcome === 'rejected') state.subscriptions[0].reject(new Error('closed page'));
        await drain();
        assert.equal(count, 0, outcome);
      }
    });
    await test(kind + ': incoming port listeners are preserved and tracked once', async () => {
      const state = load(content), port = state.makePort(); let count = 0, received = 0;
      const listen = given => { received++; given.onDisconnect.addListener(() => count++); };
      state.runtime.onConnect.addListener(listen);
      assert.equal(state.runtime.onConnect.hasListener(listen), true);
      state.runtime.onConnect.fire(port);
      assert.equal(received, 1);
      assert.equal(state.subscriptions.length, 1);
      state.subscriptions[0].resolve(1); await drain();
      assert.equal(count, 1);
      state.runtime.onConnect.removeListener(listen);
      assert.equal(state.runtime.onConnect.hasListener(listen), false);
      state.runtime.onConnect.fire(state.makePort()); assert.equal(received, 1);
    });
    await test(kind + ': BFCache preserves subscription and page exit cancels', async () => {
      const state = load(content); state.runtime.connect();
      const leave = persisted => state.handlers.pagehide.forEach(f => f({ persisted }));
      leave(true); await drain();
      assert.equal(state.calls.includes('background.unobserve'), false);
      state.subscriptions[0].resolve(1); await drain();
      state.runtime.connect(); leave(false); await drain();
      if (!content) assert.equal(state.calls.includes('background.unobserve'), true);
    });
    await test(kind + ': throwing connect creates no subscription', async () => {
      const failure = new Error('native connect refused');
      const state = load(content, 0, state => { state.runtime.connect = () => { throw failure; }; });
      assert.throws(() => state.runtime.connect(), error => error === failure);
      assert.equal(state.subscriptions.length, 0);
      assert.equal(state.nativePorts.length, 0);
    });
    await test(kind + ': external ports untouched', async () => {
      const state = load(content), port = state.runtime.connect('other-extension', { name: 'external' });
      assert.equal(port.onDisconnect, port.nativeDisconnect);
      port.postMessage({ plain: true });
      assert.equal(port.posts[0].plain, true);
      assert.equal(state.subscriptions.length, 0);
      let received, disconnected;
      port.onMessage.addListener((_, from) => { received = from; });
      port.onDisconnect.addListener(from => { disconnected = from; });
      port.onMessage.fire('hello', {});
      port.nativeDisconnect.fire({});
      assert.equal(received, port);
      assert.equal(disconnected, port);
    });
  }
  await test('Port listeners receive their original port for messages and disconnects', async () => {
    for (const content of [true, false]) {
      const state = load(content), port = state.runtime.connect();
      port.localState = 'kept';
      let received, disconnected;
      const onMessage = (message, from) => { received = [message, from, from.localState]; };
      const onDisconnect = from => { disconnected = [from, from.localState]; };
      port.onMessage.addListener(onMessage);
      port.onMessage.addListener(onMessage);
      port.onDisconnect.addListener(onDisconnect);
      port.onMessage.fire({ value: 1 }, { localState: 'wrong object' });
      assert.equal(received[1], port); assert.equal(received[2], 'kept');
      port.nativeDisconnect.fire({ localState: 'wrong object' });
      assert.equal(disconnected[0], port); assert.equal(disconnected[1], 'kept');
      port.onMessage.removeListener(onMessage);
      assert.equal(port.onMessage.hasListener(onMessage), false);
    }
    const state = load(false), incoming = state.makePort();
    incoming.sender = { url: 'https://example.test/' };
    let shown, messagePort, disconnectPort;
    state.runtime.onConnect.addListener(port => {
      shown = port; port.localState = 'tab state';
      port.onMessage.addListener((_, from) => { messagePort = from; });
      port.onDisconnect.addListener(from => { disconnectPort = from; });
    });
    state.runtime.onConnect.fire(incoming);
    incoming.onMessage.fire('hello', {});
    incoming.nativeDisconnect.fire({});
    assert.equal(messagePort, shown); assert.equal(messagePort.localState, 'tab state');
    assert.equal(disconnectPort, shown);
    const own = load(false), proxyTarget = own.makePort(), ownURL = own.runtime.getURL('page.html');
    proxyTarget.sender = { url: ownURL, tab: { index: -1, url: ownURL } };
    let ownView, ownMessage, ownDisconnect;
    own.runtime.onConnect.addListener(port => {
      ownView = port; port.localState = 'extension page';
      port.onMessage.addListener((_, from) => { ownMessage = from; });
      port.onDisconnect.addListener(from => { ownDisconnect = from; });
    });
    own.runtime.onConnect.fire(proxyTarget);
    assert.notEqual(ownView, proxyTarget, 'The popup sender is exposed through a proxy');
    proxyTarget.onMessage.fire('hello', {});
    proxyTarget.nativeDisconnect.fire({});
    assert.equal(ownMessage, ownView); assert.equal(ownMessage.localState, 'extension page');
    assert.equal(ownDisconnect, ownView);
  });
  await test('Multiple onConnect listeners share one port identity and retain WeakMap state', async () => {
    const state = load(false), target = state.makePort(), url = state.runtime.getURL('page.html');
    target.sender = { url, tab: { index: -1, url } };
    const seen = [], stateByPort = new WeakMap();
    let messagePort, disconnectPort;
    state.runtime.onConnect.addListener(port => { seen.push(port); });
    const second = port => {
      seen.push(port);
      stateByPort.set(port, 'connection state');
      port.onMessage.addListener((_, from) => { messagePort = from; });
      port.onDisconnect.addListener(from => { disconnectPort = from; });
    };
    state.runtime.onConnect.addListener(second);
    state.runtime.onConnect.fire(target);
    assert.equal(seen[0], seen[1]);
    assert.equal(seen[1].sender.tab, undefined, 'The shared view still removes the synthetic popup tab');
    target.onMessage.fire('hello', {});
    target.nativeDisconnect.fire({});
    assert.equal(messagePort, seen[1]);
    assert.equal(disconnectPort, seen[1]);
    assert.equal(stateByPort.get(messagePort), 'connection state');
    assert.equal(stateByPort.get(disconnectPort), 'connection state');
    state.runtime.onConnect.removeListener(second);
    assert.equal(state.runtime.onConnect.hasListener(second), false);
  });
  await test('A panel with no current tab receives undefined', async () => {
    const state = load(false, 0, state => {
      state.root.chrome.tabs = { getCurrent: async () => null };
    });
    assert.equal(await state.root.chrome.tabs.getCurrent(), undefined);
    await new Promise(resolve => state.root.chrome.tabs.getCurrent(tab => { assert.equal(tab, undefined); resolve(); }));
  });
  await test('delayed worker-only event is not lost behind a newer context event', async () => {
    for (const content of [true, false]) {
      const state = load(content), older = state.runtime.connect(), newer = state.runtime.connect();
      let oldCount = 0, newCount = 0;
      older.onDisconnect.addListener(() => oldCount++);
      newer.onDisconnect.addListener(() => newCount++);
      state.subscriptions[1].resolve(1); await drain();
      state.subscriptions[0].resolve(0); await drain();
      assert.equal(newCount, 1); assert.equal(oldCount, 1);
    }
  });
  await test('same-context worker replacement retires only native-selected old port', async () => {
    for (const content of [true, false]) {
      const state = load(content), old = state.runtime.connect(), fresh = state.runtime.connect();
      let oldCount = 0, freshCount = 0;
      old.onDisconnect.addListener(() => oldCount++);
      fresh.onDisconnect.addListener(() => freshCount++);
      // Swift binds each subscription to its actual background. The new
      // connection waiting for the replacement is deliberately not resolved.
      state.subscriptions[0].resolve(0); await drain();
      assert.equal(oldCount, 1); assert.equal(freshCount, 0);
      fresh.postMessage({ usable: true });
    }
  });
  await test('slow worker startup has no synthetic disconnect or port deadline', async () => {
    let answerPing;
    const state = load(false, 0, state => {
      Object.getPrototypeOf(state.runtime).sendMessage = () => new Promise(resolve => { answerPing = resolve; });
    });
    const port = state.runtime.connect(); let count = 0;
    port.onDisconnect.addListener(() => count++);
    await drain();
    state.now += 14000;
    assert.equal(count, 0);
    answerPing('pong'); await drain();
    assert.equal(count, 0);
    assert.equal(state.calls.includes('background.revive'), false);
    assert.deepEqual(Array.from(state.timers, t => t.delay), [15000], 'only existing checkWorker timeout');
  });
  await test('native wake and another page use the same generation fanout', async () => {
    for (const cause of ['background.wake', 'another extension page']) {
      const contexts = [load(true), load(false), load(false)];
      const counts = [0, 0, 0];
      contexts.forEach((state, i) => state.runtime.connect().onDisconnect.addListener(() => counts[i]++));
      // Models the shared Swift broadcaster, not a live WebKit restart.
      contexts.forEach(state => state.subscriptions[0].resolve(1));
      await drain(); assert.deepEqual(counts, [1, 1, 1], cause);
    }
  });
  await test('missing isolated bridge fails closed, native disconnect still works', async () => {
    const state = load(true, 0, state => { delete state.root.webkit; });
    const port = state.runtime.connect(); let count = 0;
    port.onDisconnect.addListener(() => count++);
    await drain(); assert.equal(count, 0);
    port.nativeDisconnect.fire(port); assert.equal(count, 1);
  });
  await test('newly loaded shim subscribes to its own generation', async () => {
    for (const content of [true, false]) {
      const state = load(content, 3), port = state.runtime.connect(); let count = 0;
      port.onDisconnect.addListener(() => count++);
      assert.equal(state.subscriptions[0].expected, 3);
      state.subscriptions[0].resolve(null); await drain(); assert.equal(count, 0);
    }
  });
  const requestFixture = () => {
    const calls = [];
    const state = load(false, 0, state => {
      state.root.chrome.webRequest = { onBeforeRequest: { addListener: (...args) => calls.push(args) } };
    });
    return { calls, add: state.root.chrome.webRequest.onBeforeRequest.addListener };
  };
  await test('AdBlock mixed request types preserve supported types and listener options', () => {
    const { calls, add } = requestFixture(), callback = () => {};
    const filter = { urls: ['https://*/*', 'wss://*/*'], types: ['script', 'webtransport', 'webbundle', 'xmlhttprequest'] };
    add(callback, filter, ['blocking', 'extraHeaders', 'requestHeaders']);
    assert.equal(calls.length, 1);
    assert.equal(calls[0][0], callback);
    assert.deepEqual(Array.from(calls[0][1].urls), ['https://*/*']);
    assert.deepEqual(Array.from(calls[0][1].types), ['script', 'xmlhttprequest']);
    assert.deepEqual(Array.from(calls[0][2]), ['requestHeaders']);
    assert.deepEqual(filter, { urls: ['https://*/*', 'wss://*/*'], types: ['script', 'webtransport', 'webbundle', 'xmlhttprequest'] },
      'Caller filter must stay intact');
  });
  await test('AdBlock unsupported-only request types are not broadened', () => {
    const { calls, add } = requestFixture();
    add(() => {}, { urls: ['https://*/*'], types: ['webbundle', 'webtransport'] });
    assert.equal(calls.length, 0, 'Unsupported-only listener must not become an all-types listener');
  });
  await test('AdBlock supported filters are unchanged', () => {
    const { calls, add } = requestFixture(), callback = () => {};
    const filter = { urls: ['https://example.test/*'], types: ['image'] };
    add(callback, filter, ['responseHeaders']);
    assert.equal(calls.length, 1);
    assert.equal(calls[0][0], callback);
    assert.deepEqual(Array.from(calls[0][1].urls), filter.urls);
    assert.deepEqual(Array.from(calls[0][1].types), filter.types);
    assert.deepEqual(Array.from(calls[0][2]), ['responseHeaders']);
  });
  await test('Content scripts get Chrome install reason and platform enums', () => {
    const { runtime } = load(true);
    assert.equal(runtime.OnInstalledReason.INSTALL, 'install');
    assert.equal(runtime.OnRestartRequiredReason.OS_UPDATE, 'os_update');
    assert.equal(runtime.PlatformArch.ARM64, 'arm64');
    assert.equal(runtime.PlatformOs.MAC, 'mac');
    assert.equal(runtime.RequestUpdateCheckStatus.NO_UPDATE, 'no_update');
  });
  await test('Cookie listeners ignore malformed events and keep add/remove identity', () => {
    const listeners = new Set(), seen = [];
    const state = load(false, 0, state => {
      state.root.chrome.cookies = { onChanged: {
        addListener: f => listeners.add(f), removeListener: f => listeners.delete(f), hasListener: f => listeners.has(f),
      } };
    });
    const changed = state.root.chrome.cookies.onChanged, listener = change => seen.push(change.cookie.name);
    changed.addListener(listener); changed.addListener(listener);
    for (const value of [undefined, {}, { cookie: null }, { cookie: { name: 'session' }, cause: 'explicit' }]) {
      listeners.forEach(f => f(value));
    }
    assert.deepEqual(seen, ['session']);
    assert.equal(changed.hasListener(listener), true);
    changed.removeListener(listener);
    assert.equal(changed.hasListener(listener), false);
    assert.equal(listeners.size, 0);
  });
  await test('DNR omits redirects and headers WebKit would broaden, preserving other rules', async () => {
    const changes = [];
    const state = load(false, 0, state => {
      state.root.chrome.declarativeNetRequest = {
        getSessionRules: async () => [], getDynamicRules: async () => [],
        updateSessionRules: async options => changes.push(options), updateDynamicRules: async options => changes.push(options),
      };
    });
    const condition = { regexFilter: '^https?://.*', requestDomains: ['bad.example'], resourceTypes: ['main_frame'] };
    const rules = [
      { id: 1, action: { type: 'redirect', redirect: { extensionPath: '/blocked.html' } }, condition },
      { id: 2, action: { type: 'modifyHeaders', requestHeaders: [] }, condition },
      { id: 3, action: { type: 'block' }, condition },
      { id: 4, action: { type: 'redirect', redirect: { extensionPath: '/blocked.html' } }, condition: { requestDomains: ['bad.example'] } },
      { id: 5, action: { type: 'redirect', redirect: { extensionPath: '/blocked.html' } }, condition: { regexFilter: '^https://bad.example/' } },
    ];
    const dnr = state.root.chrome.declarativeNetRequest;
    await dnr.updateSessionRules({ addRules: rules });
    await dnr.updateDynamicRules({ addRules: rules });
    assert.equal(changes.length, 2);
    for (const change of changes) assert.deepEqual(Array.from(change.addRules, rule => rule.id), [3, 4, 5]);
    assert.equal(rules.length, 5, 'Original extension rules remain intact');
  });
  await test('Tab listeners deduplicate registration and remove the original listener completely', async () => {
    const listeners = new Set(), seen = [];
    const state = load(false, 0, state => {
      state.root.chrome.tabs = { onActivated: {
        addListener: f => listeners.add(f), removeListener: f => listeners.delete(f), hasListener: f => listeners.has(f),
      } };
    });
    const activated = state.root.chrome.tabs.onActivated, listener = info => seen.push(info.tabId);
    activated.addListener(listener); activated.addListener(listener);
    assert.equal(listeners.size, 1);
    listeners.forEach(f => f({ tabId: 3, windowId: 7 }));
    await drain();
    assert.deepEqual(seen, [3]);
    activated.removeListener(listener);
    assert.equal(activated.hasListener(listener), false);
    assert.equal(listeners.size, 0);
    listeners.forEach(f => f({ tabId: 4, windowId: 7 }));
    await drain();
    assert.deepEqual(seen, [3], 'Removed listeners receive no later event');
    activated.addListener(listener);
    assert.equal(listeners.size, 1, 'A removed listener can be registered again');
  });
  await test('Tab listeners can retry after native registration throws', () => {
    const listeners = new Set(); let fail = true;
    const state = load(false, 0, state => {
      state.root.chrome.tabs = { onActivated: {
        addListener: f => { if (fail) throw new Error('registration refused'); listeners.add(f); },
        removeListener: f => listeners.delete(f), hasListener: f => listeners.has(f),
      } };
    });
    const event = state.root.chrome.tabs.onActivated, listener = () => {};
    assert.throws(() => event.addListener(listener), /registration refused/);
    assert.equal(event.hasListener(listener), false);
    fail = false; event.addListener(listener); event.addListener(listener);
    assert.equal(listeners.size, 1);
    event.removeListener(listener); assert.equal(listeners.size, 0);
  });
  await test('Per-tab side panel options and placement arrive in one completed operation', async () => {
    const messages = [];
    const state = load(false, 0, state => {
      state.root.chrome.tabs = { get: async id => ({ id, index: 2, windowId: 7 }) };
      state.root.chrome.windows = { getAll: async () => [{ id: 7, left: 10, top: 20, width: 800, height: 600 }] };
      state.runtime.sendNativeMessage = (app, message) => { messages.push(message); return Promise.resolve({ value: null }); };
    });
    await state.root.chrome.sidePanel.setOptions({ tabId: 3, enabled: true, path: 'work.html' });
    const options = messages.find(message => message.api === 'sidePanel.setOptions');
    assert(options);
    assert.equal(options.args[0].tabId, 3);
    assert.equal(options.args[1].place.i, 2);
    assert.equal(options.args[1].place.w.width, 800);
    assert(!messages.some(message => message.api === 'sidePanel.placed'), 'No separate placement can race the next operation');
  });
  await test('Side panel open and close resolve the requested tab or window and preserve callback errors', async () => {
    const messages = [], lookedUp = [];
    const state = load(false, 0, state => {
      state.root.chrome.tabs = { get: async id => { if (id === 99) throw new Error('No tab 99'); return { id, index: 2, windowId: 7 }; } };
      state.root.chrome.windows = {
        getAll: async () => [{ id: 7, left: 10, top: 20, width: 800, height: 600 }],
        get: async id => { lookedUp.push(id); return { id, left: 110, top: 120, width: 900, height: 700 }; },
      };
      state.runtime.sendNativeMessage = (app, message) => { messages.push(message); return Promise.resolve({ value: null }); };
    });
    for (const operation of ['open', 'close']) {
      messages.length = 0;
      await state.root.chrome.sidePanel[operation]({ tabId: 3 });
      const tab = messages.find(message => message.api === 'sidePanel.' + operation);
      assert.equal(tab.args[0].tabId, 3); assert.equal(tab.args[1].place.i, 2); assert.equal(tab.args[1].place.w.left, 10);
      messages.length = 0;
      await state.root.chrome.sidePanel[operation]({ windowId: 8 });
      const window = messages.find(message => message.api === 'sidePanel.' + operation);
      assert.equal(window.args[0].windowId, 8); assert.equal(window.args[1].window.left, 110);
      await new Promise(resolve => state.root.chrome.sidePanel[operation]({ tabId: 99 }, () => {
        assert.match(state.runtime.lastError.message, /No tab 99/); resolve();
      }));
    }
    assert.deepEqual(lookedUp, [8, 8]);
  });
  console.log(passed + ' full-shim regression cases passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
