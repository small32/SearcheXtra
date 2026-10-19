import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const handlers=new Map(),messages=[];
const selection={toString:()=>'',rangeCount:0};
const config={enabled:true,enableText:true,enableLink:true,enableImage:true,showHints:false,showTrail:false,ignoreEditable:true,distanceThreshold:20,excludedSites:[],rules:[
 {object:'text',pattern:'→',action:'search'},{object:'link',pattern:'→',action:'openTab'},{object:'image',pattern:'→',action:'openImage'}]};
// Model only the DOM surfaces used by drag feedback, keeping the gesture tests
// independent of a browser while allowing checks during a held mouse drag.
class Element {
 constructor(tag) {
  this.tagName=tag.toUpperCase();this.children=[];this.parentNode=null;this.attributes=new Map();this._text='';
  this.style={cssText:'',setProperty(name,value){this[name]=value;},getPropertyValue(name){return this[name]||'';}};
  if(this.tagName==='CANVAS'){this.width=0;this.height=0;this.drawCalls=[];}
 }
 setAttribute(name,value){this.attributes.set(name,String(value));}
 getAttribute(name){return this.attributes.get(name)??null;}
 append(...children){for(const child of children){child.remove();child.parentNode=this;this.children.push(child);}}
 remove(){if(this.parentNode){this.parentNode.children.splice(this.parentNode.children.indexOf(this),1);this.parentNode=null;}}
 set textContent(value){this._text=String(value);for(const child of this.children)child.parentNode=null;this.children=[];}
 get textContent(){return this._text+this.children.map(child=>child.textContent).join('');}
 set innerHTML(_){throw new Error('Drag preview must render content as text, not page HTML');}
 get offsetWidth(){return this.tagName==='CANVAS'?this.width:Math.max(20,Math.min(280,this.textContent.length*7),...this.children.map(child=>child.offsetWidth));}
 get offsetHeight(){return this.tagName==='CANVAS'?this.height:Math.max(18,...this.children.map(child=>child.offsetHeight));}
 getContext(kind){assert.equal(this.tagName,'CANVAS');assert.equal(kind,'2d');return {drawImage:(...args)=>this.drawCalls.push(args)};}
}
const document={documentElement:new Element('html'),createElement:tag=>new Element(tag),createElementNS:(_,tag)=>new Element(tag)};
const descendants=node=>node.children.flatMap(child=>[child,...descendants(child)]);
const previews=()=>descendants(document.documentElement).filter(node=>node.getAttribute('data-searchextra-flow-drag-preview')!==null);
const markers=()=>descendants(document.documentElement).filter(node=>node.getAttribute('data-searchextra-flow-drag-marker')!==null);
const preview=()=>{assert.equal(previews().length,1,'A held pointer drag has one content preview');return previews()[0];};
const ctx={window:{},location:{href:'https://example.com/page',hostname:'example.com',protocol:'https:'},URL,Math,Uint32Array,crypto:{getRandomValues:a=>a.fill(12)},getSelection:()=>selection,addEventListener:(name,fn)=>handlers.set(name,fn),document,innerWidth:900,innerHeight:600};
vm.createContext(ctx);vm.runInContext(readFileSync(new URL('../Sources/SearcheXtra/Resources/FlowDrag.js',import.meta.url),'utf8'),ctx);
ctx.sxInstallFlowDrag({config,labels:{}},m=>messages.push(m));
const link={tagName:'A',href:'https://target.example/',textContent:'A link',getAttribute:()=>null,matches:()=>true,closest:()=>null};
const text={tagName:'SPAN',textContent:'selected text',getAttribute:()=>null,closest:()=>null};
const img={tagName:'IMG',src:'https://example.com/img.png',alt:'Example image',complete:true,naturalWidth:480,naturalHeight:240,getAttribute:()=>null,closest:()=>null};
const blank={closest:()=>null};
function event(target,x,y,extra={}) {return {target,isTrusted:true,button:0,buttons:1,clientX:x,clientY:y,composedPath:()=>[target],defaultPrevented:false,preventDefault(){this.defaultPrevented=true},stopImmediatePropagation(){},dataTransfer:{getData:()=>''},...extra};}
function drag(target,points,extra={}) {
 messages.length=0;handlers.get('mousedown')(event(target,100,100,extra));
 handlers.get('dragstart')(event(target,100,100,extra));
 for(const [x,y] of points)handlers.get('dragover')(event(blank,x,y,extra));
 const [x,y]=points.at(-1);const drop=event(blank,x,y,extra);handlers.get('drop')(drop);handlers.get('dragend')();
 return {drop,done:messages.filter(m=>m.phase==='perform')};
}
assert.equal(drag(link,[[150,100]]).done[0].object,'link');
assert.equal(drag(img,[[150,100]]).done[0].object,'image');
selection.toString=()=> 'selected text';selection.rangeCount=1;selection.getRangeAt=()=>({getClientRects:()=>[{left:90,right:170,top:90,bottom:120}]});
assert.equal(drag(text,[[150,100]]).done[0].text,'selected text');
assert.equal(drag(link,[[150,100]]).done[0].object,'text','Selected link words retain text classification');
config.rules.push({object:'text',pattern:'↑→',action:'copy'});
assert.equal(drag(text,[[100,60],[160,60]]).done[0].pattern,'↑→');
config.rules.push({object:'text',pattern:'*',action:'search'});
assert.equal(drag(text,[[100,140]]).done[0].pattern,'↓');
config.rules.push({object:'text',pattern:'↓',action:'none'});
assert.equal(drag(text,[[100,140]]).done.length,0,'Explicit no action outranks wildcard');
assert.equal(drag(text,[[110,100]]).done.length,0,'Small movements stay native');
assert.equal(drag(text,[[150,100]],{isTrusted:false}).done.length,0);
assert.equal(drag({...text,closest:()=>({})},[[150,100]]).done.length,0);
config.enabled=false;assert.equal(drag(text,[[150,100]]).done.length,0);config.enabled=true;
config.excludedSites=['example.com'];assert.equal(drag(text,[[150,100]]).done.length,0);
ctx.location.hostname='sub.example.com';assert.equal(drag(text,[[150,100]]).done.length,0);
ctx.location.hostname='example.com.evil';assert.equal(drag(text,[[150,100]]).done.length,1);
ctx.location.hostname='example.com';config.excludedSites=[];config.enableText=false;assert.equal(drag(text,[[150,100]]).done.length,0);config.enableText=true;
for(let i=0;i<100;i++)assert.equal(drag(text,[[150,100]]).done.length,1);
messages.length=0;handlers.get('mousedown')(event(text,100,100));handlers.get('dragstart')(event(text,100,100));handlers.get('keydown')({key:'Escape'});handlers.get('drop')(event(blank,150,100));assert.equal(messages.filter(m=>m.phase==='perform').length,0);
console.log('PASS: drag classification, selected link words, direction sequences, wildcard precedence, editable fields, exclusions, Escape and 100 repeated drags');

ctx.window.__sxFlowDrag.configure({config,labels:{},pointerDrag:true});
function pointerDrag(target,points,extra={},releaseTarget=blank) {
 messages.length=0;handlers.get('mousedown')(event(target,100,100,extra));
 const start=event(target,100,100,extra);handlers.get('dragstart')(start);
 // The WinUI host may end an HTML drag immediately, without dragover or drop.
 handlers.get('dragend')();
 for(const [x,y] of points)handlers.get('mousemove')(event(blank,x,y,extra));
 const [x,y]=points.at(-1);handlers.get('mouseup')(event(releaseTarget,x,y,{buttons:0,...extra}));
 return {start,done:messages.filter(m=>m.phase==='perform')};
}
assert.equal(pointerDrag(text,[[150,100]]).done[0].text,'selected text','Mouse release searches text without a native drop event');
assert.equal(pointerDrag(text,[[100,60],[160,60]]).done[0].pattern,'↑→');
assert.equal(pointerDrag(text,[[110,100]]).done.length,0,'Pointer clicks and small movements do not run actions');
assert.equal(pointerDrag(text,[[150,100]],{isTrusted:false}).done.length,0);
assert.equal(pointerDrag(text,[[150,100]],{}, {closest:()=>({})}).done.length,0,'Dropping into editable fields does not run a gesture');
assert.equal(pointerDrag(text,[[950,100]]).done.length,0,'Release outside the page does not run an action');
assert.equal(pointerDrag(text,[[150,100]]).start.defaultPrevented,true,'Owned drags bypass the broken WinUI native drag loop');
const click=event(blank,150,100);handlers.get('click')(click);assert.equal(click.defaultPrevented,true,'Drag release cannot navigate the underlying link');
selection.toString=()=>'';selection.rangeCount=0;
assert.equal(pointerDrag(link,[[150,100]]).done[0].object,'link');
assert.equal(pointerDrag(img,[[150,100]]).done[0].object,'image');
const normalClick=event(link,100,100);handlers.get('mousedown')(normalClick);handlers.get('mouseup')(normalClick);handlers.get('click')(normalClick);assert.equal(normalClick.defaultPrevented,false,'Ordinary link clicks retain their native behavior');
config.enabled=false;assert.equal(pointerDrag(link,[[150,100]]).start.defaultPrevented,false);config.enabled=true;
messages.length=0;handlers.get('mousedown')(event(link,100,100));handlers.get('mousemove')(event(blank,150,100));handlers.get('keydown')({key:'Escape'});handlers.get('mouseup')(event(blank,150,100));assert.equal(messages.filter(m=>m.phase==='perform').length,0);
const canceled=messages.find(m=>m.phase==='cancel');assert.ok(canceled);for(const key of ['phase','id','object','pattern','text','linkUrl','imageUrl','linkText','pageUrl'])assert.equal(typeof canceled[key],'string','Cancellation includes every native Codable request field');
console.log('PASS: WinUI mouse-release text/link/image actions, native drag cancellation, direction sequences, native clicks, threshold, editable drops and Escape');

function selectWords(words) {
 selection.toString=()=>words;selection.rangeCount=words?1:0;
 selection.getRangeAt=()=>({getClientRects:()=>[{left:90,right:170,top:90,bottom:120}]});
}
function hold(target,x=150,y=100,moveTarget=blank) {
 messages.length=0;handlers.get('mousedown')(event(target,100,100));
 handlers.get('dragstart')(event(target,100,100));handlers.get('dragend')();
 handlers.get('mousemove')(event(moveTarget,x,y));
}
function release(target=blank,x=150,y=100) {
 handlers.get('mouseup')(event(target,x,y,{buttons:0}));
 assert.equal(previews().length,0,'Mouse release removes the content preview');
 assert.equal(markers().length,0,'Mouse release removes the cursor drag marker');
}
selectWords('<b>Google</b>');hold(text);
let ghost=preview();
assert.equal(markers().length,1,'A held drag shows one small cursor marker');
const marker=markers()[0];
assert.equal(marker.getAttribute('aria-hidden'),'true');
assert.ok(/pointer-events\s*:\s*none/.test(marker.style.cssText),'The cursor marker cannot intercept page input');
assert.ok(parseFloat(marker.style.top)>100&&parseFloat(marker.style.top)<130,'The marker is just below the pointer');
assert.equal(ghost.textContent,'<b>Google</b>','Dragged text is visible without interpreting HTML');
assert.equal(ghost.getAttribute('aria-hidden'),'true','A transient preview is hidden from accessibility navigation');
assert.ok(/pointer-events\s*:\s*none/.test(ghost.style.cssText)||ghost.style.pointerEvents==='none','Preview cannot intercept page input');
const opacity=Number(ghost.style.opacity||ghost.style.cssText.match(/(?:^|;)\s*opacity\s*:\s*([.\d]+)/)?.[1]);
assert.ok(opacity>0&&opacity<1,'Content preview is translucent like the native drag image');
assert.ok(/white-space\s*:\s*nowrap/.test(ghost.style.cssText)||ghost.style.whiteSpace==='nowrap','Text preview remains a single line');
assert.equal(config.showHints,false);assert.equal(config.showTrail,false);
const left=ghost.style.left,top=ghost.style.top;
handlers.get('mousemove')(event(blank,210,150));
assert.equal(preview(),ghost,'Mouse motion moves the existing preview');
assert.notEqual(ghost.style.left,left);assert.notEqual(ghost.style.top,top);
assert.equal(markers()[0],marker,'Pointer movement reuses the cursor marker');
assert.ok(parseFloat(marker.style.left)>=210&&parseFloat(marker.style.left)<230);
assert.ok(parseFloat(marker.style.top)>150&&parseFloat(marker.style.top)<180,'The marker follows below the pointer');
assert.equal(ghost.style.left,'210px','Content preview is horizontally centered on the pointer');
assert.equal(ghost.style.top,'140px','Content preview is anchored ten pixels above the pointer');
assert.ok(/transform\s*:\s*translate\(-50%,\s*-100%\)/.test(ghost.style.cssText),'The entire preview is translated above and centered on its pointer anchor');
handlers.get('mousemove')(event(blank,890,590));
assert.equal(ghost.style.left,'890px','Preview alignment is unchanged near a page edge');
assert.equal(ghost.style.top,'580px');
handlers.get('mousemove')(event(blank,100,8));
assert.equal(ghost.style.top,'-2px','Preview never moves below the pointer at the top edge');
release(blank,890,590);

selectWords('selected link words');hold(link);
assert.equal(preview().textContent,'selected link words','Selected anchor words preview the dragged text, not the link URL');release();
selectWords('A'.repeat(500));hold(text);
assert.ok(preview().textContent.startsWith('A')&&preview().textContent.length<=161,'Long selections have a bounded preview');release();
selectWords('no action content');hold(text,100,150);
assert.equal(preview().textContent,'no action content','An explicit no-action direction still shows what is being dragged');
release(blank,100,150);assert.equal(messages.filter(m=>m.phase==='perform').length,0);
const editableTarget={closest:()=>({})};selectWords('input destination');hold(text,150,100,editableTarget);
assert.equal(preview().textContent,'input destination','Entering an editable target retains the content preview');
release(editableTarget);assert.equal(messages.filter(m=>m.phase==='perform').length,0);

selectWords('');hold(link);
assert.equal(preview().textContent,'A link','Links preview their display text');release();
const emptyLink={...link,textContent:''};hold(emptyLink);
assert.equal(preview().textContent,link.href,'Links without display text preview their URL');release();
hold(link,50,100);
assert.equal(preview().textContent,'A link','Unconfigured directions retain the content preview');
release(blank,50,100);assert.equal(messages.filter(m=>m.phase==='perform').length,0);
hold(img);ghost=preview();
const canvas=descendants(ghost).find(node=>node.tagName==='CANVAS');
assert.ok(canvas,'Loaded images show a thumbnail');
assert.ok(canvas.width>0&&canvas.width<=120&&canvas.height>0&&canvas.height<=96,'Image previews fit the thumbnail bounds');
assert.equal(canvas.width/canvas.height,img.naturalWidth/img.naturalHeight,'Image previews preserve their aspect ratio');
assert.ok(canvas.drawCalls.length>0&&canvas.drawCalls.every(call=>call[0]===img),'Thumbnail uses the loaded source image without a second image request');
assert.equal(ghost.style.left,'150px','Image preview shares the centered pointer anchor');
assert.equal(ghost.style.top,'90px','Image preview shares the above-pointer anchor');
assert.ok(messages.every(message=>!Object.hasOwn(message,'previewImage')),'DOM image references stay out of native drag messages');
release();
const imageSize=[img.naturalWidth,img.naturalHeight];img.complete=false;img.naturalWidth=img.naturalHeight=0;hold(img);
assert.equal(preview().textContent,'Example image','Unloaded images preview their descriptive text');release();img.complete=true;[img.naturalWidth,img.naturalHeight]=imageSize;

selectWords('small movement');hold(text,110,100);
assert.equal(previews().length,0,'Sub-threshold mouse movement does not create a drag preview');release(blank,110,100);
selectWords('Escape cleanup');hold(text);preview();handlers.get('keydown')({key:'Escape'});
assert.equal(previews().length,0,'Escape removes the content preview');release();
selectWords('blur cleanup');hold(text);preview();handlers.get('blur')({target:ctx.window});
assert.equal(previews().length,0,'Window blur removes the content preview');release();
selectWords('settings cleanup');hold(text);preview();config.enabled=false;
ctx.window.__sxFlowDrag.configure({config,labels:{},pointerDrag:true});
assert.equal(previews().length,0,'Disabling super drag removes the content preview immediately');release();config.enabled=true;

ctx.window.__sxFlowDrag.configure({config,labels:{}});selectWords('native preview');
handlers.get('mousedown')(event(text,100,100));const nativeStart=event(text,100,100);handlers.get('dragstart')(nativeStart);
handlers.get('dragover')(event(blank,150,100));
assert.equal(previews().length,0,'Native fallback drags retain the system preview without a duplicate overlay');
assert.equal(nativeStart.defaultPrevented,false,'Native drag preview is not canceled');handlers.get('dragend')();
console.log('PASS: pointer content previews for text, selected links, link URLs and image thumbnails, independent hint settings, positioning, no-action directions and cleanup; native preview retained');

ctx.window.__sxFlowDrag.configure({config,labels:{},pointerDrag:true});
selectWords('navigating frame');hold(text);preview();
handlers.get('pagehide')({persisted:true});
assert.equal(previews().length,0,'Leaving a frame removes drag DOM before entering the back-forward cache');
assert.ok(messages.some(message=>message.phase==='cancel'),'Leaving a frame cancels its pending native action');
const gone=messages.find(message=>message.phase==='gone');assert.ok(gone?.id,'Native host can release the exact departing frame');
handlers.get('pageshow')({persisted:false});
assert.equal(messages.filter(message=>message.phase==='ready').length,0,'Initial pageshow does not duplicate document-start registration');
handlers.get('pageshow')({persisted:true});
assert.equal(messages.find(message=>message.phase==='ready')?.id,gone.id,'Restored frames register again using the same document identity');
assert.equal(ctx.window.__sxFlowDrag.isDragging(),false,'A cached document cannot resume a canceled gesture');
console.log('PASS: detached frame cleanup and back-forward cache restoration');
