import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const listeners=new Map(), messages=[];
const config={enabled:true,minDistance:10,directionMode:'8-way',showHints:false,exceptions:['docs.example.com'],rules:[
  {object:'link',direction:'down',modifier:'none',action:'openBackgroundTab',region:'page'},
  {object:'text',direction:'up',modifier:'none',action:'search',region:'page'},
  {object:'image',direction:'down',modifier:'none',action:'saveImage',region:'page'}]};
const selection={toString:()=>'',containsNode:()=>false};
const context={window:{},location:{hostname:'example.com',protocol:'https:'},URL,Math,setTimeout,queueMicrotask,getSelection:()=>selection,
  addEventListener:(key,fn)=>listeners.set(key,fn), document:{},innerWidth:1000,innerHeight:700};
vm.createContext(context);vm.runInContext(readFileSync(new URL('../Sources/SearcheXtra/Resources/SuperDrag.js',import.meta.url),'utf8'),context);
context.sxInstallSuperDrag({config,labels:{}},p=>messages.push(p));
const link={tagName:'A',href:'https://target.example/path',matches:q=>q.includes('a['),closest:()=>null,getAttribute:()=>null};
const blank={closest:()=>null};
function event(target,x,y,extra={}) {return {target,isTrusted:true,screenX:x,screenY:y,clientX:x,clientY:y,defaultPrevented:false,composedPath:()=>[target],preventDefault(){this.defaultPrevented=true;},...extra};}
function drag(target,dx,dy,extra={}) {messages.length=0;listeners.get('dragstart')(event(target,100,100,extra));listeners.get('drop')(event(blank,100+dx,100+dy,extra));return messages.filter(p=>p.phase==='finish');}
assert.equal(drag(link,0,40)[0]?.object,'link');
assert.equal(drag(link,0,9).length,0);
assert.equal(drag(link,0,40,{shiftKey:true}).length,0);
assert.equal(drag(link,0,40,{isTrusted:false}).length,0);
selection.toString=()=> 'selected text';selection.containsNode=()=>true;
assert.equal(drag({tagName:'SPAN',closest:()=>null,getAttribute:()=>null},0,-40)[0]?.object,'text');
selection.toString=()=>'';
const image={tagName:'IMG',currentSrc:'https://example.com/photo.png',closest:()=>null,getAttribute:()=>null};
assert.equal(drag(image,0,40)[0]?.object,'image');
assert.equal(drag({...link,closest:()=>({})},0,40).length,0);
assert.equal(drag({...link,getAttribute:()=> 'true',tagName:'DIV',matches:()=>false},0,40).length,0);
messages.length=0;listeners.get('dragstart')(event(link,100,100));listeners.get('drop')(event({closest:()=>({})},100,140));assert.equal(messages.filter(p=>p.phase==='finish').length,0);
context.location.hostname='sub.docs.example.com';assert.equal(drag(link,0,40).length,0);
context.location.hostname='docs.example.com.evil';assert.equal(drag(link,0,40).length,1);
context.location.hostname='example.com';config.enabled=false;assert.equal(drag(link,0,40).length,0);
config.enabled=true;config.rules[0].action='copy';assert.equal(context.window.__sxSuperDrag.rule({object:'link',direction:'down',modifier:'none',region:'page',dx:0,dy:40}).action,'copy');
config.directionMode='4-way';assert.equal(context.window.__sxSuperDrag.direction(20,-40),'up');
config.directionMode='8-way';assert.equal(context.window.__sxSuperDrag.direction(20,-20),'upRight');
for(let i=0;i<100;i++)assert.equal(drag(link,0,40).length,1);
config.rules.push({object:'element',direction:'up',modifier:'none',action:'copy',region:'page'});
messages.length=0;
const ordinary={textContent:'ordinary element',closest:()=>null};
listeners.get('mousedown')(event(ordinary,100,100,{button:0}));
listeners.get('mousemove')(event(ordinary,100,70,{buttons:1}));
listeners.get('mouseup')(event(blank,100,70,{button:0}));
assert.equal(messages.filter(p=>p.phase==='finish')[0]?.object,'element');
console.log('PASS: 17 super drag scenarios and 100 repeated drags');
