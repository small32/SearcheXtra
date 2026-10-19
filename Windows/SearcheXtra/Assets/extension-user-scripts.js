/* SearcheXtra: the userScripts API missing from WebView2's extension host. */
(() => {
  'use strict';
  const runtime = globalThis.chrome?.runtime;
  if (!runtime?.id || !runtime.sendMessage || globalThis.__searchextraUserScriptsInstalled) return;
  const manifest = runtime.getManifest();
  if (manifest.manifest_version !== 3 || ![...(manifest.permissions || []), ...(manifest.optional_permissions || [])].includes('userScripts')) return;
  Object.defineProperty(globalThis, '__searchextraUserScriptsInstalled', { value: true });
  const marker = '__searchextraUserScripts';
  const nativeSend = runtime.sendMessage.bind(runtime);
  let sequence = 0;
  const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
  const event = () => {
    const listeners = new Set();
    return { addListener: listener => listeners.add(listener), removeListener: listener => listeners.delete(listener), hasListener: listener => listeners.has(listener), hasListeners: () => listeners.size, listeners };
  };
  const messages = event(), connections = event();

  async function request(api, args) {
    const envelope = { [marker]: 1, id: `${Date.now().toString(36)}-${++sequence}`, api, args };
    for (let attempt = 0; ; attempt++) {
      try {
        const answer = await new Promise((resolve, reject) => {
          nativeSend(envelope, result => {
            const error = runtime.lastError?.message;
            error ? reject(new Error(error)) : resolve(result);
          });
        });
        if (!answer || answer[marker] !== 1) throw new Error('The user script host did not respond.');
        if (answer.error) throw new Error(answer.error);
        return answer.result;
      } catch (error) {
        // The native worker can start before its bridge view has finished loading.
        // A reloading extension can also invalidate its old message port. Only
        // repeat reads after that error: a lost mutation reply may have succeeded.
        const retryRead = ['getScripts', 'getWorldConfigurations', 'isAllowed'].includes(api)
          && /message port closed before a response was received/i.test(error.message);
        if (attempt >= 40 || (!retryRead && !/receiving end does not exist|could not establish connection/i.test(error.message))) throw error;
        await pause(250);
      }
    }
  }

  function withError(error, callback) {
    const previous = Object.getOwnPropertyDescriptor(runtime, 'lastError');
    try {
      Object.defineProperty(runtime, 'lastError', { configurable: true, value: { message: error.message || String(error) } });
      callback();
    } finally {
      if (previous) Object.defineProperty(runtime, 'lastError', previous); else delete runtime.lastError;
    }
  }

  const methods = ['getScripts', 'register', 'update', 'unregister', 'configureWorld', 'getWorldConfigurations', 'resetWorldConfiguration', 'execute'];
  const shim = {};
  for (const method of methods) shim[method] = (...input) => {
    const callback = typeof input.at(-1) === 'function' ? input.pop() : null;
    // The WebView2 host cannot grant native userScripts access. A namespace may
    // still exist while its calls remain pending; use the app's permissioned
    // implementation consistently in workers and extension pages.
    const task = request(method, input);
    if (!callback) return task;
    task.then(result => callback(result), error => withError(error, callback));
  };
  Object.defineProperty(globalThis.chrome, 'userScripts', { configurable: true, value: shim });
  if (globalThis.browser && globalThis.browser !== globalThis.chrome) {
    try { Object.defineProperty(globalThis.browser, 'userScripts', { configurable: true, value: shim }); } catch (_) { }
  }
  // Keep native events on runtimes that support the API. Dispatching bridge events
  // here never changes ordinary runtime.onMessage / onConnect traffic.
  const bindEvent = (name, local) => {
    const original = runtime[name];
    const combined = {
      addListener(listener) { local.addListener(listener); original?.addListener(listener); },
      removeListener(listener) { local.removeListener(listener); original?.removeListener(listener); },
      hasListener(listener) { return local.hasListener(listener) || !!original?.hasListener(listener); },
      hasListeners() { return local.hasListeners() || !!original?.hasListeners?.(); },
    };
    Object.defineProperty(runtime, name, { configurable: true, value: combined });
  };
  bindEvent('onUserScriptMessage', messages);
  bindEvent('onUserScriptConnect', connections);
  runtime.onMessage.addListener((packet, sender, sendResponse) => {
    if (sender.id === runtime.id && packet?.__sxUserScriptPageIdentity === true) {
      sendResponse({ tab: sender.tab, frameId: sender.frameId, url: sender.url, documentId: sender.documentId, origin: sender.origin });
      return;
    }
    if (sender.id !== runtime.id || packet?.[marker] !== 1 || packet.event !== 'message') return;
    let answered = false, asynchronous = false;
    const respond = result => { if (!answered) { answered = true; sendResponse(result); } };
    for (const listener of messages.listeners) {
      try {
        const value = listener(packet.message, packet.sender, respond);
        if (value === true) asynchronous = true;
        else if (value?.then) { asynchronous = true; value.then(respond, () => respond()); }
      } catch (_) { }
    }
    return asynchronous && !answered ? true : undefined;
  });
  runtime.onConnect.addListener(port => {
    if (port.sender?.id !== runtime.id || !port.name.startsWith('__searchextraUserScriptPort:')) return;
    const initialise = packet => {
      if (packet?.[marker] !== 1 || packet.event !== 'connect') return;
      port.onMessage.removeListener(initialise);
      const wrapped = {
        name: packet.name || '', sender: packet.sender,
        onMessage: event(), onDisconnect: event(),
        postMessage: message => port.postMessage(message), disconnect: () => port.disconnect(),
      };
      port.onMessage.addListener(message => { for (const listener of wrapped.onMessage.listeners) listener(message, wrapped); });
      port.onDisconnect.addListener(() => { for (const listener of wrapped.onDisconnect.listeners) listener(wrapped); });
      for (const listener of connections.listeners) listener(wrapped);
    };
    port.onMessage.addListener(initialise);
  });
})();
