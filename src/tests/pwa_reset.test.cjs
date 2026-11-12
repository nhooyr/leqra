'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs');
const {assetPath,assetVersion}=require('./web_assets.cjs');
const source=readFileSync(assetPath('pwa.js'),'utf8'),origin='https://leqra.test';
const buildA=assetVersion+'-1111111111111111',buildB=assetVersion+'-2222222222222222';
function deferred(){let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return{promise,resolve,reject};}
function target(properties={}){const listeners=new Map();return Object.assign(properties,{addEventListener(type,listener){const all=listeners.get(type)||[];all.push(listener);listeners.set(type,all);},removeEventListener(type,listener){listeners.set(type,(listeners.get(type)||[]).filter(value=>value!==listener));},emit(type,properties={}){for(const listener of [...listeners.get(type)||[]])listener({type,...properties});}});}
function boot({protocol='https:',supported=true,cacheSupport=true,controllerBuild=buildA,legacyWorker=false}={}){
 let now=0,nextTimer=0;const timers=new Map(),ports=[],calls={fetch:[],register:0,update:0,unregister:[],reset:[],deleted:[],keys:0,discovery:0,reload:0,prepare:0};
 const state={latestBuild:buildA,fetchGate:null,registerGate:null,updateGate:null,unregisterError:false,cacheError:'',discoveryError:false,silentBuild:false};
 const schedule=(callback,delay,interval=0)=>{const id=++nextTimer;timers.set(id,{callback,at:now+delay,interval});return id;};
 class Channel{constructor(){this.port1={closed:false,onmessage:null,close(){this.closed=true;}};this.port2={closed:false,close(){this.closed=true;},postMessage:data=>{if(!this.port1.closed)this.port1.onmessage?.({data});}};ports.push(this.port1,this.port2);}}
 const worker=scriptURL=>({scriptURL,postMessage(message,reply){if(message.type==='LEQRA_BUILD_INFO'){if(!state.silentBuild)queueMicrotask(()=>reply[0].postMessage({build:controllerBuild}));}else if(message.type==='LEQRA_RESET'){calls.reset.push(scriptURL);if(!legacyWorker)queueMicrotask(()=>reply[0].postMessage({type:'LEQRA_RESET_DONE'}));}}});
 const makeRegistration=(scope=origin+'/',scriptURL=origin+'/sw.js')=>({scope,active:worker(scriptURL),async unregister(){calls.unregister.push(this.scope+' '+this.active.scriptURL);if(state.unregisterError&&this.scope===origin+'/')throw Error('unregister failed');return true;},async update(){calls.update++;if(state.updateGate)await state.updateGate.promise;}});
 const own=makeRegistration(),registrations=[own],cacheNames=new Set(['leqra-app-'+assetVersion,'leqra-app-old-build','blog-v1','leqra-appx-other']);
 const sw=target({controller:own.active,async getRegistrations(){calls.discovery++;if(state.discoveryError)throw Error('denied');return registrations;},async register(){calls.register++;if(state.registerGate)await state.registerGate.promise;return own;}});
 const storage={async keys(){calls.keys++;if(state.cacheError==='keys')throw Error('denied');return[...cacheNames];},delete(name){calls.deleted.push(name);if(state.cacheError===name)throw Error('denied');cacheNames.delete(name);return Promise.resolve(true);}};
 const navigator={onLine:true,userAgent:'Desktop'};if(supported)navigator.serviceWorker=sw;
 const window=target({isSecureContext:true,leqra:{prepareUpdate(){calls.prepare++;return false;}}});if(cacheSupport)window.caches=storage;
 const document=target({hidden:false,readyState:'loading',querySelector:()=>({content:buildA})});
 vm.runInNewContext(source,{window,document,navigator,location:{protocol,href:protocol==='file:'?'file:///game/index.html':origin+'/',reload(){calls.reload++;}},URL,MessageChannel:Channel,AbortController,
  performance:{now:()=>now},setTimeout:(callback,delay)=>schedule(callback,delay),clearTimeout:id=>timers.delete(id),setInterval:(callback,delay)=>schedule(callback,delay,delay),clearInterval:id=>timers.delete(id),
  fetch:async(_url,options)=>{calls.fetch.push(options);if(state.fetchGate)await state.fetchGate.promise;return{ok:true,json:async()=>({build:state.latestBuild})};},
 });
 const flush=async()=>{for(let n=0;n<40;n++)await Promise.resolve();};
 async function advance(ms){const until=now+ms;for(let n=0;n<1000;n++){const next=[...timers].filter(([,timer])=>timer.at<=until).sort((a,b)=>a[1].at-b[1].at)[0];if(!next)break;const[id,timer]=next;now=timer.at;if(timer.interval)timer.at+=timer.interval;else timers.delete(id);timer.callback();await flush();}now=until;await flush();}
 return{state,calls,window,document,sw,own,registrations,makeRegistration,cacheNames,timers,ports,flush,advance,load:async()=>{window.emit('load');await flush();}};
}

test('PWA reset unregisters only leqra root workers and removes only leqra offline caches',async()=>{
 const h=boot();h.registrations.push(h.makeRegistration(origin+'/blog/',origin+'/sw.js'),h.makeRegistration(origin+'/',origin+'/blog-worker.js'),h.makeRegistration('https://other.test/','https://other.test/sw.js'));
 await h.window.leqraPWA.reset();assert.deepEqual(h.calls.unregister,[origin+'/ '+origin+'/sw.js']);assert.deepEqual(h.calls.reset,[origin+'/sw.js']);
 assert.deepEqual([...h.cacheNames].sort(),['blog-v1','leqra-appx-other']);assert.equal(h.timers.size,0);
 const fetched=h.calls.fetch.length;h.window.emit('load');h.window.emit('online');h.window.emit('pageshow');h.document.emit('visibilitychange');h.sw.emit('controllerchange');await h.advance(120000);
 assert.equal(h.calls.fetch.length,fetched);assert.equal(h.calls.register,0);assert.equal(h.calls.reload,0);
});

test('PWA reset exists before the file protocol guard and handles absent capabilities',async()=>{
 for(const options of [{protocol:'file:'},{supported:false,cacheSupport:false},{protocol:'http:',supported:false,cacheSupport:false}]){
  const h=boot(options);assert.equal(typeof h.window.leqraPWA.reset,'function');await h.window.leqraPWA.reset();assert.equal(h.calls.unregister.length,0);assert.equal(h.calls.deleted.length,0);assert.equal(h.calls.fetch.length,0);
 }
 const h=boot({supported:false});await h.window.leqraPWA.reset();assert.deepEqual([...h.cacheNames].sort(),['blog-v1','leqra-appx-other']);
});

test('concurrent resets share their work and failed worker or cache cleanup remains visible and retryable',async()=>{
 const h=boot();h.state.unregisterError=true;h.state.cacheError='leqra-app-'+assetVersion;
 const first=h.window.leqraPWA.reset(),second=h.window.leqraPWA.reset();assert.equal(first,second);
 await assert.rejects(first,/unregister.*offline cache/);assert.equal(h.calls.deleted.length,2,'one failing cache cannot skip another deletion');
 assert.deepEqual([...h.cacheNames].sort(),['blog-v1','leqra-app-'+assetVersion,'leqra-appx-other']);
 h.state.unregisterError=false;h.state.cacheError='';await h.window.leqraPWA.reset();assert.deepEqual([...h.cacheNames].sort(),['blog-v1','leqra-appx-other']);
 const denied=boot();denied.state.discoveryError=true;await assert.rejects(denied.window.leqraPWA.reset(),/unregister/);assert.equal(denied.calls.deleted.length,2,'discovery failure still clears known app caches');
 const unreadable=boot();unreadable.state.cacheError='keys';await assert.rejects(unreadable.window.leqraPWA.reset(),/read leqra offline caches/);assert.equal(unreadable.calls.unregister.length,1);
});

test('reset aborts a build fetch and its late response cannot register a worker or reload',async()=>{
 const h=boot();h.state.fetchGate=deferred();h.state.latestBuild=buildB;await h.load();assert.equal(h.calls.fetch.length,1);
 await h.window.leqraPWA.reset();assert.equal(h.calls.fetch[0].signal.aborted,true);assert.equal(h.timers.size,0);
 h.state.fetchGate.resolve();await h.flush();assert.equal(h.calls.register,0);assert.equal(h.calls.reload,0);assert.equal(h.timers.size,0);
});

test('reset includes a registration already in flight and blocks its later update continuation',async()=>{
 const h=boot();h.state.registerGate=deferred();await h.load();assert.equal(h.calls.register,1);
 const reset=h.window.leqraPWA.reset();h.state.registerGate.resolve();await reset;await h.flush();
 assert.ok(h.calls.unregister.length>=1);assert.equal(h.calls.update,0);assert.equal(h.calls.reload,0);assert.equal(h.timers.size,0);
 const updating=boot();updating.state.updateGate=deferred();await updating.load();assert.equal(updating.calls.update,1);await updating.window.leqraPWA.reset();updating.state.updateGate.resolve();await updating.flush();assert.equal(updating.calls.reload,0);assert.equal(updating.timers.size,0);
});

test('reset cancels controller probes and pending reload retries without leaving timers behind',async()=>{
 const probe=boot();probe.state.latestBuild=buildB;probe.state.silentBuild=true;await probe.load();assert.ok(probe.ports.length>0);await probe.window.leqraPWA.reset();assert.equal(probe.timers.size,0);assert.ok(probe.ports.every(port=>port.closed));assert.equal(probe.calls.reload,0);
 const retry=boot({controllerBuild:buildB});retry.state.latestBuild=buildB;await retry.load();assert.ok(retry.calls.prepare>0);await retry.window.leqraPWA.reset();await retry.advance(120000);assert.equal(retry.calls.reload,0);assert.equal(retry.timers.size,0);
});

test('legacy worker reset acknowledgements have a bounded wait while cleanup still completes',async()=>{
 const h=boot({legacyWorker:true}),reset=h.window.leqraPWA.reset();await h.flush();assert.equal(h.calls.unregister.length,0);await h.advance(1000);await reset;assert.equal(h.calls.unregister.length,1);assert.equal(h.calls.deleted.length,2);assert.equal(h.timers.size,0);
});
