import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const file=readFileSync(new URL('../Windows/SearcheXtra/PageScripts.Features.cs',import.meta.url),'utf8');
const script=file.match(/public const string Features = """\s*([\s\S]*?)\s*""";/)[1];
const listeners=new Map(),frames=new Map(),moves=[];
let next=0;
const addEventListener=(name,fn)=>listeners.set(name,fn);
const context={document:{addEventListener,querySelectorAll:()=>[]},navigator:{},addEventListener,
  requestAnimationFrame:fn=>{frames.set(++next,fn);return next;},cancelAnimationFrame:id=>frames.delete(id),
  scrollBy:(...args)=>moves.push(args),chrome:{webview:{postMessage(){}}},__searchPrefs:{scroll:true}};
context.window=context.top=context;
vm.runInNewContext(script,context);
const click={button:1,clientX:10,clientY:20,target:{closest:()=>null},preventDefault(){}};
const frame=()=>{const pending=[...frames.values()];frames.clear();pending.forEach(fn=>fn());};
listeners.get('mousedown')(click);assert.equal(frames.size,1);
listeners.get('mousemove')({clientX:90,clientY:100});frame();assert.deepEqual(moves.at(-1),[10,10]);
context.__searchPrefs.scroll=false;const count=moves.length;frame();
assert.equal(frames.size,0,'Disabling automatic scroll stops its animation loop');
assert.equal(moves.length,count,'Disabled scrolling does not move the page again');
context.__searchPrefs.scroll=true;listeners.get('mousedown')(click);assert.equal(frames.size,1);
listeners.get('pagehide')();assert.equal(frames.size,0,'Navigating away cancels a live scroll frame');
listeners.get('mousedown')(click);assert.equal(frames.size,1);
listeners.get('keydown')({key:'Escape'});assert.equal(frames.size,0,'Escape cancels scrolling after re-enabling');
console.log('PASS: Windows automatic scrolling stops when disabled, navigating away or pressing Escape');
