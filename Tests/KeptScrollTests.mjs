import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const swift = readFileSync(new URL('../Sources/SearcheXtra/KeptScroll.swift', import.meta.url), 'utf8');
const script = swift.match(/static let script = """\r?\n([\s\S]*?)\r?\n    """/)[1];
function page(mode = 'manual') {
  const listeners = new Map();
  const window = { scrollX: 0, scrollY: 900, scrollTo(x, y) { this.scrollX = x; this.scrollY = y; } };
  const context = { window, history: { scrollRestoration: mode }, addEventListener(name, fn) {
    const list = listeners.get(name) ?? []; list.push(fn); listeners.set(name, list);
  } };
  vm.runInNewContext(script, context);
  return { window, context, fire(name, persisted) { for (const fn of listeners.get(name) ?? []) fn({ persisted }); } };
}

// A cached manual-restoration page comes back from WebKit at the top.
let p = page();
p.fire('pagehide', true); p.window.scrollY = 0; p.fire('pageshow', true);
assert.equal(p.window.scrollY, 900);

// Reloads and pages left out of the back/forward cache keep their own position.
for (const [hide, show] of [[false, true], [true, false]]) {
  p = page(); p.fire('pagehide', hide); p.window.scrollY = 0; p.fire('pageshow', show);
  assert.equal(p.window.scrollY, 0);
}
p = page('auto'); p.fire('pagehide', true); p.window.scrollY = 0; p.fire('pageshow', true);
assert.equal(p.window.scrollY, 0);

// WebKit's nonzero restoration and a page's own pageshow handler take priority.
p = page(); p.fire('pagehide', true); p.window.scrollY = 120; p.fire('pageshow', true);
assert.equal(p.window.scrollY, 120);
p = page(); p.context.addEventListener('pageshow', () => p.window.scrollTo(0, 250));
p.fire('pagehide', true); p.window.scrollY = 0; p.fire('pageshow', true);
assert.equal(p.window.scrollY, 250);

// A position is consumed once; stale events cannot resurrect it.
p = page(); p.fire('pagehide', true); p.window.scrollY = 0; p.fire('pageshow', true);
p.window.scrollY = 0; p.fire('pageshow', true);
assert.equal(p.window.scrollY, 0);
console.log('PASS: cached manual scroll restoration, reloads, browser/page precedence and stale events');
