'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs');
const {assetPath,assetVersion}=require('./web_assets.cjs');
const source=readFileSync(assetPath('pwa.js'),'utf8');
const android='Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 Chrome/143.0.0.0 Mobile Safari/537.36';
const safari='Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Version/26.0 Mobile/15E148 Safari/604.1';

test('Home Screen uses the page theme without the deprecated translucent status bar',()=>{
 const html=readFileSync(require('node:path').join(__dirname,'../web/index.html'),'utf8');
 assert.doesNotMatch(html,/<meta\b[^>]*name=["']apple-mobile-web-app-status-bar-style["']/i);
 assert.match(html,/<meta name="theme-color" content="#[a-f0-9]{6}">/i);
 assert.match(html,/<meta name="viewport" content="[^"]*viewport-fit=cover/);
});

function target(properties={}){
 const listeners=new Map();return Object.assign(properties,{
  addEventListener(type,listener){const entries=listeners.get(type)||[];entries.push(listener);listeners.set(type,entries);},
  removeEventListener(type,listener){listeners.set(type,(listeners.get(type)||[]).filter(item=>item!==listener));},
  emit(type,properties={}){const event={type,defaultPrevented:false,preventDefault(){this.defaultPrevented=true;},...properties};for(const listener of [...listeners.get(type)||[]])listener(event);return event;},
  listeners,
 });
}
function boot({ua=android,coarse=true,secure=true,supported=true,protocol='https:',standalone=false,iosStandalone,
 platform='Linux armv8l',touchPoints=1,menu=true,storage=new Map(),storageDenied=false,missingHook=false}={}){
 class Element{
  children=[];hidden=false;attributes={};className='';textContent='';
  constructor(tag){Object.assign(this,target());this.tagName=tag.toUpperCase();}
  setAttribute(name,value){this.attributes[name]=value;}
  append(...children){for(const child of children){child.parent=this;this.children.push(child);}}
  remove(){if(this.parent)this.parent.children=this.parent.children.filter(child=>child!==this);this.parent=null;}
 }
 const body=new Element('body'),dialogs=[new Element('dialog')],observers=[],calls={prepare:0,canShow:0,prompts:0,intervals:0};
 const state={menu,throws:false};
 class Observer{
  observations=[];disconnected=false;
  constructor(callback){this.callback=callback;observers.push(this);}
  observe(node,options){this.observations.push({node,options});}
  disconnect(){this.disconnected=true;}
  notify(records=[]){if(!this.disconnected)this.callback(records);}
 }
 const mode=target({matches:standalone}),pointer=target({matches:coarse});
 const build=assetVersion+'-aaaaaaaaaaaaaaaa';
 const document=target({body,hidden:false,readyState:'loading',createElement:tag=>new Element(tag),querySelectorAll:()=>dialogs,
  querySelector:selector=>selector==='meta[name="leqra-build"]'?{content:build}:null});
 const navigator={userAgent:ua,platform,maxTouchPoints:touchPoints,onLine:true};
 if(iosStandalone!==undefined)navigator.standalone=iosStandalone;
 if(supported)navigator.serviceWorker=target({controller:null,register:async()=>({update:async()=>{}})});
 const window=target({isSecureContext:secure,matchMedia:query=>query==='(pointer: coarse)'?pointer:mode,
  leqra:{prepareUpdate(){calls.prepare++;return false;}}});
 if(!missingHook)window.leqra.canShowInstallHint=()=>{calls.canShow++;if(state.throws)throw Error('not ready');return state.menu;};
 vm.runInNewContext(source,{window,document,navigator,location:{protocol},performance:{now:()=>0},MutationObserver:Observer,
  localStorage:{getItem(key){if(storageDenied)throw Error('denied');return storage.get(key)||null;},setItem(key,value){if(storageDenied)throw Error('denied');storage.set(key,value);}},
  setInterval(){calls.intervals++;},clearInterval(){},setTimeout(){},clearTimeout(){},AbortController,
  fetch:async()=>({ok:true,json:async()=>({build})}),
 });
 const flush=async()=>{for(let n=0;n<12;n++)await Promise.resolve();};
 const notice=()=>body.children.find(node=>node.className.split(' ').includes('pwa-install-hint'));
 const install=()=>notice()?.children.find(node=>node.className.includes('pwa-install-action'));
 const dismiss=()=>notice()?.children.find(node=>node.className==='pwa-install-dismiss');
 const mutate=records=>observers.forEach(observer=>observer.notify(records));
 const offer=(properties={})=>window.emit('beforeinstallprompt',{prompt(){calls.prompts++;return Promise.resolve();},userChoice:Promise.resolve({outcome:'dismissed'}),...properties});
 return{state,calls,window,document,navigator,body,dialogs,mode,pointer,storage,observers,flush,notice,install,dismiss,mutate,offer};
}

test('mobile native installation waits for a real browser event and only prompts from Install',async()=>{
 const h=boot();assert.equal(h.notice(),undefined);assert.equal(h.calls.prompts,0);
 const event=h.offer();assert.equal(event.defaultPrevented,true);assert.equal(h.notice().hidden,false);
 assert.equal(h.calls.prompts,0);assert.equal(h.notice().attributes['aria-label'],'Install leqra');
 assert.match(h.notice().children[0].children[0].textContent,/Play leqra as an app/);
 h.install().emit('click');await h.flush();assert.equal(h.calls.prompts,1);assert.equal(h.notice(),undefined);
 assert.equal(h.storage.get('leqra.installHint.v1'),'dismissed');assert.equal(h.observers[0].disconnected,true);
 assert.equal(h.calls.prepare,0,'install suggestions use the read-only menu hook');
 assert.equal(h.calls.intervals,1,'the existing update interval is the only polling work');
});

test('unsupported, insecure, desktop and standalone environments do not get install suggestions',()=>{
 for(const options of [{supported:false},{secure:false,protocol:'http:'},{protocol:'file:'},
  {ua:'Desktop',coarse:false,touchPoints:0},{standalone:true},{ua:safari,iosStandalone:true,platform:'iPhone'}]){
  const h=boot(options);h.offer();assert.equal(h.notice(),undefined,JSON.stringify(options));
  assert.equal(h.calls.prompts,0);assert.equal(h.observers.length,0);
 }
 const h=boot();h.offer({prompt:undefined});assert.equal(h.notice(),undefined,'an unrelated event is not install capability');
});

test('known iOS browsers get accurate manual Home Screen help, excluding embedded web views',()=>{
 for(const ua of [safari,safari.replace('Version/26.0','CriOS/143.0.0.0'),safari.replace('Version/26.0','FxiOS/143.0'),safari.replace('Version/26.0','EdgiOS/143.0')]){
  const h=boot({ua,iosStandalone:false,platform:'iPhone'});assert.equal(h.notice().hidden,false);
  assert.match(h.notice().children[0].children[1].textContent,/Tap Share, then Add to Home Screen/);
  assert.equal(h.install(),undefined,'manual browsers never get a nonfunctional Install button');
 }
 for(const ua of [safari+' FBAN/FBIOS',safari+' Instagram',safari+' GSA/320',safari.replace('Version/26.0 Mobile/15E148 Safari/604.1','Mobile/15E148')]){
  const h=boot({ua,iosStandalone:false,platform:'iPhone'});h.offer();assert.equal(h.notice(),undefined);assert.equal(h.observers.length,0);
 }
 const unsupported=boot({ua:safari,platform:'iPhone'});assert.equal(unsupported.notice(),undefined,'iOS needs the standalone capability signal');
 const ipad=boot({ua:safari.replace('iPhone; CPU iPhone OS 26_0','Macintosh; Intel Mac OS X 10_15'),platform:'MacIntel',touchPoints:5,iosStandalone:false,coarse:false});
 assert.equal(ipad.notice().hidden,false);
});

test('the startup hook hides the notice during games, tours and dialogs, including late install events',()=>{
 const h=boot({menu:false});h.offer();assert.equal(h.notice(),undefined);
 h.state.menu=true;h.mutate();assert.equal(h.notice().hidden,false);
 for(const context of ['game','Infinity','tour','Controls']){
  h.state.menu=false;h.mutate([{type:'attributes'}]);assert.equal(h.notice().hidden,true,context);
  h.state.menu=true;h.mutate([{type:'attributes'}]);assert.equal(h.notice().hidden,false);
 }
 h.document.hidden=true;h.document.emit('visibilitychange');assert.equal(h.notice().hidden,true);
 h.document.hidden=false;h.document.emit('visibilitychange');assert.equal(h.notice().hidden,false);
 h.state.throws=true;h.mutate();assert.equal(h.notice().hidden,true);assert.equal(h.calls.prepare,0);
 const missing=boot({missingHook:true});missing.offer();assert.equal(missing.notice(),undefined);
 const count=h.observers[0].observations.length;h.dialogs.push({});h.mutate([{type:'childList'}]);assert.ok(h.observers[0].observations.length>count);
});

test('dismissal persists without nagging and denied storage still dismisses for the session',()=>{
 const storage=new Map(),first=boot({ua:safari,iosStandalone:false,storage});first.dismiss().emit('click');
 assert.equal(first.notice(),undefined);assert.equal(first.observers[0].disconnected,true);
 const again=boot({ua:safari,iosStandalone:false,storage});assert.equal(again.notice(),undefined);assert.equal(again.observers.length,0);
 const denied=boot({ua:safari,iosStandalone:false,storageDenied:true});denied.dismiss().emit('click');denied.mutate();denied.offer();assert.equal(denied.notice(),undefined);
 const anotherTab=boot();anotherTab.offer();anotherTab.storage.set('leqra.installHint.v1','dismissed');anotherTab.window.emit('storage',{key:'leqra.installHint.v1'});assert.equal(anotherTab.notice(),undefined);
});

test('a consumed native prompt is invoked once and failures never reject into the game',async()=>{
 for(const failure of [false,true]){
  const h=boot();let resolve;const choice=new Promise(done=>{resolve=done;});
  h.offer({prompt(){h.calls.prompts++;if(failure)throw Error('unavailable');return Promise.resolve();},userChoice:choice});
  const button=h.install();button.emit('click');button.emit('click');assert.equal(h.calls.prompts,1);
  resolve({outcome:'dismissed'});await h.flush();assert.equal(h.notice(),undefined);
  h.offer();h.mutate();assert.equal(h.notice(),undefined);assert.equal(h.calls.prompts,1);
 }
});

test('installation signals remove the hint and remember that the app is installed',async()=>{
 for(const signal of ['appinstalled','display-mode','navigator']){
  const h=boot();h.offer();assert.ok(h.notice());
  if(signal==='appinstalled')h.window.emit('appinstalled');
  else if(signal==='display-mode'){h.mode.matches=true;h.mode.emit('change');}
  else{h.navigator.standalone=true;h.window.emit('pageshow');}
  assert.equal(h.notice(),undefined);assert.equal(h.storage.get('leqra.installHint.v1'),'installed');assert.equal(h.observers[0].disconnected,true);
  await h.flush();
 }
 const h=boot({ua:safari,iosStandalone:true});assert.equal(h.storage.get('leqra.installHint.v1'),'installed');
});

test('reset suppresses install hints and a late install result cannot rewrite the cleared preference',async()=>{
 const h=boot();let resolve;const choice=new Promise(done=>{resolve=done;});h.offer({userChoice:choice});h.install().emit('click');await h.flush();
 await h.window.leqraPWA.reset();assert.equal(h.notice(),undefined);assert.equal(h.observers[0].disconnected,true);
 resolve({outcome:'dismissed'});await h.flush();assert.equal(h.storage.has('leqra.installHint.v1'),false);
 h.offer();h.mutate();assert.equal(h.notice(),undefined);
});
