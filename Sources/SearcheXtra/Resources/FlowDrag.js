// SearcheXtra's native drag adapter. Independently implemented; FlowMouse is the behavior reference.
function sxInstallFlowDrag(options, send) {
  if (window.__sxFlowDrag) { window.__sxFlowDrag.configure(options); return; }
  let opts=options, press=null, drag=null, overlay=null, trail=null, hint=null, preview=null, marker=null, selectionStyle=null, suppressClick=false;
  const web=value=>{try {const u=new URL(value,location.href);return /^https?:$/.test(u.protocol)?u.href:'';}catch{return '';}};
  const editable=target=>!!target?.closest?.('input,textarea,select,[contenteditable]:not([contenteditable="false"]),[role="textbox"],canvas,[role="application"],.monaco-editor,.CodeMirror');
  const enabled=()=>opts.config.enabled && /^https?:$/.test(location.protocol) && !opts.config.excludedSites.some(host=>location.hostname===host || location.hostname.endsWith('.'+host));
  const typeEnabled=type=>opts.config['enable'+type[0].toUpperCase()+type.slice(1)];
  function selectedAt(e) {
    const s=getSelection(),text=s?.toString();
    if(!text?.trim())return '';
    for(let i=0;i<(s.rangeCount||0);i++)if([...s.getRangeAt(i).getClientRects()].some(r=>e.clientX>=r.left && e.clientX<=r.right && e.clientY>=r.top && e.clientY<=r.bottom))return text.trim();
    return '';
  }
  function reset() {drag=null;press=null;overlay?.remove();preview?.remove();marker?.remove();selectionStyle?.remove();overlay=trail=hint=preview=marker=selectionStyle=null;}
  function sendDrag(phase) {
    const {id,object,text,linkUrl,imageUrl,linkText,pageUrl,pattern}=drag;
    send({phase,id,object,text,linkUrl,imageUrl,linkText,pageUrl,pattern});
  }
  function cancel() {if(drag)sendDrag('cancel');reset();}
  function content(e,selected) {
    const path=e.composedPath(),image=path.find(n=>n.tagName==='IMG'),link=path.find(n=>n.matches?.('a[href],area[href]'));
    if(!selected && ['grab','grabbing','move'].includes(window.getComputedStyle?.(path[0])?.cursor))return null;
    if(path.some(n=>n!==image && n!==link && n.getAttribute?.('draggable')==='true'))return null;
    const object=selected?'text':image?'image':link?'link':'';
    const text=object==='text'?selected:'',linkUrl=link?web(typeof link.href==='string'?link.href:link.getAttribute('href')):'',imageUrl=image?web(image.currentSrc||image.src):'';
    if(!object || !typeEnabled(object) || (object==='text' ? !text || text.length>32768 : object==='image' ? !imageUrl : !linkUrl))return null;
    return {object,text,linkUrl,imageUrl,linkText:link?.textContent?.trim()||image?.alt?.trim()||'',pageUrl:location.href,previewImage:image};
  }
  function begin(value) {
    const {x,y}=press;
    const id=[...crypto.getRandomValues(new Uint32Array(4))].map(n=>n.toString(16)).join('-');
    drag={...value,pattern:'',anchorX:x,anchorY:y,points:[[x,y]],id};
    // Keep the selection for copying/searching, but hide its fill while dragging.
    selectionStyle=document.createElement('style');
    selectionStyle.textContent=':root::selection, :root *::selection { background-color: transparent !important; }';
    document.documentElement.append(selectionStyle);
    sendDrag('begin');
  }
  function finish(e) {
    update(e);
    const inside=e.clientX>=0 && e.clientY>=0 && e.clientX<innerWidth && e.clientY<innerHeight;
    const r=inside && enabled() && !(opts.config.ignoreEditable&&editable(e.target)) && match();
    if(r && r.action!=='none') {
      e.preventDefault();e.stopImmediatePropagation();
      sendDrag('perform');
    } else sendDrag('cancel');
    reset();
  }
  function update(e) {
    if(!drag)return;
    const dx=e.clientX-drag.anchorX,dy=e.clientY-drag.anchorY;
    if(Math.hypot(dx,dy)>=opts.config.distanceThreshold) {
      const next=Math.abs(dx)>Math.abs(dy)?dx>0?'→':'←':dy>0?'↓':'↑';
      if(!drag.pattern.endsWith(next) && drag.pattern.length<32)drag.pattern+=next;
      drag.anchorX=e.clientX;drag.anchorY=e.clientY;
    }
    if(opts.config.showTrail && drag.pattern && drag.points.length<512)drag.points.push([e.clientX,e.clientY]);
  }
  const match=()=>drag?.pattern ? opts.config.rules.find(r=>r.object===drag.object && r.pattern===drag.pattern) || opts.config.rules.find(r=>r.object===drag.object && r.pattern==='*') : null;
  function showPreview(e) {
    if(!preview) {
      preview=document.createElement('div');preview.setAttribute('data-searchextra-flow-drag-preview','');preview.setAttribute('aria-hidden','true');
      preview.style.cssText='all:initial;position:fixed;z-index:2147483647;pointer-events:none;user-select:none;opacity:.68;font:13px system-ui;color:#808080;text-shadow:0 1px 1px #ffffff70;max-width:260px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;transform:translate(-50%,-100%)';
      const image=drag.previewImage;
      if(drag.object==='image' && image?.naturalWidth>0 && image.naturalHeight>0) {
        const canvas=document.createElement('canvas'),scale=Math.min(1,120/image.naturalWidth,96/image.naturalHeight);
        canvas.width=Math.max(1,Math.round(image.naturalWidth*scale));canvas.height=Math.max(1,Math.round(image.naturalHeight*scale));
        canvas.style.cssText='display:block;border-radius:4px;pointer-events:none';
        canvas.getContext('2d').drawImage(image,0,0,canvas.width,canvas.height);preview.append(canvas);
      } else {
        const value=(drag.object==='text'?drag.text:drag.linkText || drag.linkUrl || drag.imageUrl).replace(/\s+/g,' ').trim();
        preview.textContent=value.length>160?value.slice(0,160)+'…':value;
      }
      document.documentElement.append(preview);
    }
    preview.style.left=e.clientX+'px';
    preview.style.top=(e.clientY-10)+'px';
    if(!marker) {
      marker=document.createElement('div');marker.setAttribute('data-searchextra-flow-drag-marker','');marker.setAttribute('aria-hidden','true');
      marker.style.cssText='all:initial;position:fixed;z-index:2147483647;pointer-events:none;user-select:none;width:8px;height:8px;box-sizing:border-box;border:1px dashed #d7d7d7;background:#202020b3;box-shadow:0 0 0 1px #0006';
      document.documentElement.append(marker);
    }
    marker.style.left=(e.clientX+7)+'px';
    marker.style.top=(e.clientY+14)+'px';
  }
  function show(e) {
    const r=match();
    if(!r || r.action==='none') {overlay?.remove();overlay=trail=hint=null;return;}
    if(!opts.config.showHints && !opts.config.showTrail)return;
    if(!overlay) {
      overlay=document.createElement('div');overlay.setAttribute('data-searchextra-flow-drag','');
      overlay.style.cssText='position:fixed;inset:0;z-index:2147483647;pointer-events:none';
      if(opts.config.showTrail) {
        const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.style.cssText='position:absolute;width:100%;height:100%;overflow:visible';
        trail=document.createElementNS('http://www.w3.org/2000/svg','polyline');trail.setAttribute('fill','none');trail.setAttribute('stroke','#4285f4');trail.setAttribute('stroke-width','3');trail.setAttribute('stroke-linecap','round');trail.setAttribute('stroke-linejoin','round');svg.append(trail);overlay.append(svg);
      }
      if(opts.config.showHints) {hint=document.createElement('div');hint.style.cssText='position:absolute;padding:6px 10px;border-radius:8px;background:#202020e8;color:white;font:12px system-ui;max-width:260px;box-shadow:0 2px 8px #0005';overlay.append(hint);}
      document.documentElement.append(overlay);
    }
    if(trail)trail.setAttribute('points',drag.points.map(p=>p.join(',')).join(' '));
    if(hint) {hint.textContent=drag.pattern+' · '+(opts.labels[r.action]||r.action);hint.style.left=Math.max(8,Math.min(innerWidth-260,e.clientX+18))+'px';hint.style.top=Math.max(8,Math.min(innerHeight-40,e.clientY+18))+'px';}
  }
  addEventListener('mousedown',e=>{
    cancel();suppressClick=false;
    if(!e.isTrusted || e.button!==0 || !enabled() || (opts.config.ignoreEditable&&editable(e.target)))return;
    press={x:e.clientX,y:e.clientY};
    const value=content(e,selectedAt(e));
    if(value && opts.config.rules.some(r=>r.object===value.object && r.action!=='none'))press.content=value;
  },true);
  addEventListener('dragstart',e=>{
    if(!e.isTrusted || !enabled() || (opts.config.ignoreEditable && editable(e.target)) || e.defaultPrevented || !press?.content)return;
    // Keep mouse events flowing for gestures instead of starting a native HTML drag.
    e.preventDefault();e.stopImmediatePropagation();
  },true);
  addEventListener('mousemove',e=>{
    if(!e.isTrusted || !press?.content)return;
    if(!(e.buttons&1) || !enabled()){cancel();return;}
    if(!drag && Math.hypot(e.clientX-press.x,e.clientY-press.y)<opts.config.distanceThreshold)return;
    if(!drag)begin(press.content);
    update(e);showPreview(e);
    if(opts.config.ignoreEditable&&editable(e.target)){overlay?.remove();overlay=trail=hint=null;return;}
    e.preventDefault();e.stopImmediatePropagation();show(e);
  },true);
  addEventListener('mouseup',e=>{
    if(!e.isTrusted || e.button!==0)return;
    if(drag){suppressClick=true;finish(e);}else press=null;
  },true);
  addEventListener('click',e=>{if(e.isTrusted && suppressClick){suppressClick=false;e.preventDefault();e.stopImmediatePropagation();}},true);
  addEventListener('keydown',e=>{if(e.key==='Escape')cancel();},true);
  addEventListener('blur',e=>{if(e.target===window)cancel();},true);
  const frameId=[...crypto.getRandomValues(new Uint32Array(4))].map(n=>n.toString(16)).join('-');
  const announce=phase=>send({phase,id:frameId,object:'',text:'',linkUrl:'',imageUrl:'',linkText:'',pageUrl:location.href,pattern:''});
  addEventListener('pagehide',()=>{cancel();announce('gone');},true);
  addEventListener('pageshow',e=>{if(e.persisted)announce('ready');},true);
  window.__sxFlowDrag={configure(value){opts=value;if(!enabled())cancel();},isDragging(){return !!drag;}};
  announce('ready');
}
