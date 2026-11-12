'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),{assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8'),start=source.indexOf('function initMenuPing('),end=source.indexOf('\n}',start)+2;
assert.ok(start>=0,'menu ping initializer exists');

function boot(options={}){
 const target=()=>{const listeners=new Map();return{addEventListener(type,fn){if(!listeners.has(type))listeners.set(type,new Set());listeners.get(type).add(fn);},removeEventListener(type,fn){listeners.get(type)?.delete(fn);},emit(type){for(const fn of listeners.get(type)||[])fn({type});}};};
 const classes=new Set(options.public?['infinity-preview']:[]),arena={open:!!options.arena},observers=[],timers=new Map(),requests=[],samples=[],begins=[];
 let now=0,nextTimer=0;
 const document=Object.assign(target(),{hidden:!!options.hidden,body:{classList:{contains:name=>classes.has(name)}},documentElement:{}}),window=target();
 const s={document,window,$:()=>arena,mode:options.mode||'room',phase:options.phase||'menu',playMode:options.public?'online':options.playMode||'',online:{connected:!!options.connected},combatPrefs:{fps:options.fps!==false},settingsResetActive:!!options.reset,navigator:{onLine:options.offline?false:true},location:{protocol:options.protocol||'https:',href:'https://example.test/?room=LOCAL'},URL,AbortController,
  performance:{now:()=>now},infinityPlayMode:()=>s.playMode,beginMenuPing(){begins.push(now);s.pending=true;},setMenuPing(value){samples.push({at:now,value});s.pending=false;s.latency=value;},
  MutationObserver:class{constructor(fn){this.fn=fn;observers.push(this);}observe(){}disconnect(){this.disconnected=true;}},
  setTimeout(fn,ms){const id=++nextTimer;timers.set(id,{fn,at:now+Math.max(0,ms)});return id;},clearTimeout:id=>timers.delete(id),
  fetch(url,options){
   let resolve,reject,bodyResolve,bodyReject;const promise=new Promise((ok,fail)=>{resolve=ok;reject=fail;});
   const request={url:String(url),options,at:now,draining:false,ignoreAbort:false,
    respond(ok=true){resolve({ok,text(){request.draining=true;return new Promise((ok,fail)=>{bodyResolve=ok;bodyReject=fail;});}});},
    drain(){assert.ok(bodyResolve,'response body is being consumed');bodyResolve('ok');},fail(){reject(Error('Network unavailable'));}};
   options.signal.addEventListener('abort',()=>{if(!request.ignoreAbort){reject(Error('Aborted'));bodyReject?.(Error('Aborted'));}});requests.push(request);return promise;
  }};
 vm.createContext(s);vm.runInContext(source.slice(start,end),s);s.initMenuPing();
 const flush=async()=>{for(let i=0;i<8;i++)await Promise.resolve();};
 const advance=async ms=>{const until=now+ms;for(;;){const due=[...timers].filter(([,timer])=>timer.at<=until).sort((a,b)=>a[1].at-b[1].at||a[0]-b[0])[0];if(!due)break;now=due[1].at;timers.delete(due[0]);due[1].fn();await flush();}now=until;await flush();};
 return{s,arena,classes,requests,samples,begins,observers,flush,advance,mutate(){for(const observer of observers)if(!observer.disconnected)observer.fn();},async complete(request=requests.at(-1)){request.respond();await flush();request.drain();await flush();}};
}

test('menu health ping starts immediately and measures the full response every second',async()=>{
 const h=boot();assert.equal(h.requests.length,0,'the first probe yields until initialization finishes');
 await h.advance(0);assert.deepEqual(h.begins,[0]);assert.equal(h.requests.length,1);
 const request=h.requests[0];assert.equal(request.url,'https://example.test/healthz');assert.equal(request.options.cache,'no-store');assert.ok(request.options.signal);
 request.respond();await h.flush();assert.equal(request.draining,true);assert.equal(h.samples.length,0);
 await h.advance(37);request.drain();await h.flush();assert.deepEqual(h.samples,[{at:37,value:37}]);
 await h.advance(962);assert.equal(h.requests.length,1);await h.advance(1);assert.deepEqual(h.begins,[0,1000]);
});

test('only visible enabled online-capable menus use the health probe, avoiding existing ping sources',async()=>{
 for(const options of [{fps:false},{hidden:true},{offline:true},{reset:true},{arena:true},{phase:'playing'},{protocol:'file:'},{public:true},{mode:'online',phase:'onlineLobby',connected:true}]){
  const h=boot(options);await h.advance(12000);assert.equal(h.requests.length,0,JSON.stringify(options));
 }
 for(const options of [{phase:'onlineLobby'},{playMode:'offline'},{mode:'online',phase:'onlineLobby',connected:false},{protocol:'http:'}]){
  const h=boot(options);await h.advance(0);assert.equal(h.requests.length,1,JSON.stringify(options));
 }
});

test('failed or stalled requests clear stale ping and retry at the bounded cadence',async()=>{
 const h=boot();await h.advance(0);h.s.latency=91;h.requests[0].fail();await h.flush();assert.equal(h.s.latency,null);
 await h.advance(1000);const stalled=h.requests[1];stalled.respond();await h.flush();assert.equal(stalled.draining,true);
 await h.advance(4000);assert.equal(stalled.options.signal.aborted,true);assert.deepEqual(h.begins,[0,1000,5000]);assert.equal(h.s.latency,null);
 const third=h.requests[2];third.respond(false);await h.flush();assert.equal(h.s.latency,null);assert.equal(h.requests.length,3);
});

test('visibility, settings and match changes abort probes without rapid extra requests',async()=>{
 const h=boot();await h.advance(0);await h.advance(100);
 h.s.document.hidden=true;h.s.document.emit('visibilitychange');assert.equal(h.requests[0].options.signal.aborted,true);assert.equal(h.s.latency,null);
 h.s.document.hidden=false;h.s.document.emit('visibilitychange');h.s.document.emit('change');h.mutate();await h.advance(899);assert.equal(h.requests.length,1);
 await h.advance(1);assert.equal(h.requests.length,2);
 h.arena.open=true;h.mutate();assert.equal(h.requests[1].options.signal.aborted,true);
 h.arena.open=false;h.s.phase='playing';h.mutate();await h.advance(8000);assert.equal(h.requests.length,2);
 h.s.phase='menu';h.s.combatPrefs.fps=false;h.s.document.emit('change');await h.advance(4000);assert.equal(h.requests.length,2);
 h.s.combatPrefs.fps=true;h.s.document.emit('change');await h.advance(0);assert.equal(h.requests.length,3);
 h.s.settingsResetActive=true;h.mutate();assert.equal(h.requests[2].options.signal.aborted,true);await h.advance(8000);assert.equal(h.requests.length,3);
});

test('offline cancels immediately and a new network connection gets an immediate first probe',async()=>{
 const h=boot();await h.advance(0);await h.advance(100);h.s.navigator.onLine=false;h.s.window.emit('offline');
 assert.equal(h.requests[0].options.signal.aborted,true);assert.equal(h.s.latency,null);await h.advance(100);assert.equal(h.requests.length,1);
 h.s.navigator.onLine=true;h.s.window.emit('online');await h.advance(0);assert.deepEqual(h.begins,[0,200]);
 h.s.window.emit('pagehide');assert.equal(h.requests[1].options.signal.aborted,true);h.s.window.emit('pageshow');await h.advance(999);assert.equal(h.requests.length,2);await h.advance(1);assert.equal(h.requests.length,3);
});

test('late health responses cannot overwrite public preview ping or connected room RTT',async()=>{
 const h=boot();await h.advance(0);const health=h.requests[0];health.ignoreAbort=true;
 h.s.playMode='online';h.classes.add('infinity-preview');h.s.setMenuPing(73);h.mutate();assert.equal(health.options.signal.aborted,true);assert.equal(h.s.latency,73);
 await h.complete(health);assert.equal(h.s.latency,73);await h.advance(8000);assert.equal(h.requests.length,1);
 h.s.playMode='';h.classes.delete('infinity-preview');h.mutate();await h.advance(0);assert.equal(h.requests.length,2);
 const room=h.requests[1];room.ignoreAbort=true;h.s.mode='online';h.s.phase='onlineLobby';h.s.online.connected=true;h.mutate();assert.equal(room.options.signal.aborted,true);
 const samples=h.samples.length;await h.complete(room);assert.equal(h.samples.length,samples);await h.advance(8000);assert.equal(h.requests.length,2);
});

test('context changes invalidate responses even before a mutation callback, and stop is permanent',async()=>{
 const h=boot();await h.advance(0);h.s.phase='onlineLobby';await h.complete();assert.equal(h.samples.length,0,'the previous menu response is discarded');
 await h.advance(1000);const request=h.requests[1];h.s.window.leqraMenuPing.stop();assert.equal(request.options.signal.aborted,true);assert.ok(h.observers.every(observer=>observer.disconnected));
 h.s.window.emit('online');h.s.document.emit('change');h.mutate();await h.advance(12000);assert.equal(h.requests.length,2);
});
