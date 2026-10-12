// Shared by the native Windows and macOS hosts. No network or clipboard APIs here.
function sxInstallSuperDrag(options, send) {
  if (window.__sxSuperDrag) { window.__sxSuperDrag.configure(options); return; }
  let opts = options, drag = null, hint = null, press = null, elementDrag = false;
  const blocked = el => !!el?.closest?.('input,textarea,select,[contenteditable]:not([contenteditable="false"]),canvas,[role="textbox"],[role="application"],.monaco-editor,.CodeMirror,.leaflet-container,.mapboxgl-map');
  const excepted = () => opts.config.exceptions.some(h => location.hostname.toLowerCase() === h.toLowerCase() || location.hostname.toLowerCase().endsWith('.' + h.toLowerCase()));
  const enabled = () => opts.config.enabled && /^https?:$/.test(location.protocol) && !excepted() && !/^(chromewebstore\.google\.com|microsoftedge\.microsoft\.com)$/.test(location.hostname);
  const modifier = e => ['ctrl','alt','shift','meta'].filter(k => e[k + 'Key']).join('+') || 'none';
  function direction(dx, dy) {
    if (opts.config.directionMode === '4-way') return Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 'right' : 'left') : (dy > 0 ? 'down' : 'up');
    return ['right','downRight','down','downLeft','left','upLeft','up','upRight'][(Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) + 8) % 8];
  }
  function rule(payload) {
    let found = opts.config.rules.find(r => r.object === payload.object && r.direction === payload.direction && r.modifier === payload.modifier && (r.region || 'page') === payload.region);
    if (!found && /[A-Z]/.test(payload.direction)) {
      const cardinal = Math.abs(payload.dx) > Math.abs(payload.dy) ? (payload.dx > 0 ? 'right' : 'left') : (payload.dy > 0 ? 'down' : 'up');
      found = opts.config.rules.find(r => r.object === payload.object && r.direction === cardinal && r.modifier === payload.modifier && (r.region || 'page') === payload.region);
    }
    return found?.action === 'none' ? null : found;
  }
  function removeHint() { hint?.remove(); hint = null; }
  function reset() { drag = null; press = null; elementDrag = false; removeHint(); }
  function payload(e) {
    const dx = e.clientX - drag.clientX, dy = e.clientY - drag.clientY;
    return {object:drag.object,value:drag.value,dx,dy,direction:direction(dx,dy),modifier:modifier(e),region:'page',screenX:e.screenX,screenY:e.screenY};
  }
  function indicate(p, e) {
    if (!opts.config.showHints) return;
    const match = rule(p);
    if (!match) { removeHint(); return; }
    if (!hint) {
      hint = document.createElement('div');
      hint.style.cssText = 'position:fixed;z-index:2147483647;pointer-events:none;padding:6px 10px;border-radius:8px;background:#202020e8;color:white;font:12px system-ui;max-width:260px;box-shadow:0 2px 8px #0005';
      document.documentElement.append(hint);
    }
    hint.textContent = (opts.labels[p.direction] || p.direction) + ' · ' + (opts.labels[match.action] || match.action);
    hint.style.left = Math.max(8, Math.min(innerWidth - 260, e.clientX + 18)) + 'px';
    hint.style.top = Math.max(8, Math.min(innerHeight - 40, e.clientY + 18)) + 'px';
  }
  addEventListener('mousedown', e => {
    press = e.isTrusted && e.button === 0 ? {x:e.screenX,y:e.screenY,clientX:e.clientX,clientY:e.clientY,target:e.target}:null;
    if (!press || !enabled() || blocked(e.target) || !opts.config.rules.some(r=>r.object==='element') || e.target.closest?.('a,img,[draggable="true"]') || getSelection()?.toString().trim()) return;
    const value=e.target.textContent?.trim();
    if (!value || value.length>32768) return;
    press.value=value;
    // Only a user-configured element rule replaces text selection on ordinary elements.
    e.preventDefault();
  });
  addEventListener('mousemove', e => {
    if (!e.isTrusted || !press?.value || !(e.buttons&1) || !enabled()) return;
    if (!drag && Math.hypot(e.screenX-press.x,e.screenY-press.y)>=opts.config.minDistance) {
      drag={object:'element',value:press.value,x:press.x,y:press.y,clientX:press.clientX,clientY:press.clientY};elementDrag=true;send({...payload(e),phase:'start',screenX:drag.x,screenY:drag.y});
    }
    if (elementDrag) indicate(payload(e),e);
  });
  addEventListener('mouseup', e => {
    if (!e.isTrusted || e.button!==0 || !elementDrag || !drag) return;
    const p=payload(e);
    if(enabled()&&!blocked(e.target)&&!e.defaultPrevented&&Math.hypot(p.dx,p.dy)>=opts.config.minDistance&&rule(p)){e.preventDefault();send({phase:'finish',...p});}else send({phase:'cancel'});
    reset();
  });
  addEventListener('dragstart', e => {
    if (!e.isTrusted || !enabled() || blocked(e.target) || e.defaultPrevented) return;
    const path = e.composedPath(), image = path.find(el => el.tagName === 'IMG'), link = path.find(el => el.matches?.('a[href],area[href]'));
    // Custom draggable widgets keep their own interaction.
    if (path.some(el => el !== image && el !== link && el.getAttribute?.('draggable') === 'true')) return;
    const selection = getSelection();
    let object, value;
    if (image) { object = 'image'; value = image.currentSrc || image.src; }
    else if (link) { object = 'link'; value = typeof link.href === 'string' ? link.href : new URL(link.getAttribute('href'),link.baseURI).href; }
    else if (selection?.toString().trim() && selection.containsNode(e.target, true)) { object = 'text'; value = selection.toString(); }
    else { object = 'element'; value = e.target.textContent?.trim(); }
    if (!value || value.length > 32768 || (object !== 'text' && object !== 'element' && !/^https?:\/\//i.test(value))) return;
    drag = {object,value,x:press?.x ?? e.screenX,y:press?.y ?? e.screenY,clientX:press?.clientX ?? e.clientX,clientY:press?.clientY ?? e.clientY};
    send({...payload(e),phase:'start',screenX:drag.x,screenY:drag.y});
    queueMicrotask(() => { if (e.defaultPrevented) { reset(); send({phase:'cancel'}); } });
  }, true);
  addEventListener('dragover', e => {
    if (!e.isTrusted || !drag || !enabled() || blocked(e.target)) { removeHint(); return; }
    const p = payload(e);
    if (Math.hypot(p.dx,p.dy) < opts.config.minDistance) { removeHint(); return; }
    if (rule(p)) {
      e.preventDefault();
      if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
      indicate(p,e);
    }
  }, true);
  addEventListener('drop', e => {
    if (!e.isTrusted || !drag) return;
    const p = payload(e);
    const valid = enabled() && !blocked(e.target) && !e.defaultPrevented && Math.hypot(p.dx,p.dy) >= opts.config.minDistance && rule(p);
    // Let site drop handlers veto before performing a native browser action.
    const allowed = !!valid;
    if (allowed) e.preventDefault();
    if (allowed) send({phase:'finish',...p}); else send({phase:'cancel'});
    reset();
  });
  addEventListener('dragend', () => { if (drag) send({phase:'cancel'}); reset(); });
  addEventListener('keydown', e => { if (e.key === 'Escape' && drag) { reset(); send({phase:'cancel'}); } },true);
  window.__sxSuperDrag = { configure(value) { opts = value; if (!enabled()) reset(); }, direction, rule,
    feedback(text) { if (!opts.config.showHints) return; removeHint(); hint = document.createElement('div'); hint.style.cssText='position:fixed;right:16px;bottom:16px;z-index:2147483647;pointer-events:none;background:#202020e8;color:white;padding:8px 12px;border-radius:8px;font:12px system-ui'; hint.textContent=text; document.documentElement.append(hint); const shown=hint; setTimeout(()=>{shown.remove();if(hint===shown)hint=null;},2200); } };
}
