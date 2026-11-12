'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs');
const {assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'('),end=source.indexOf('\n',start),line=source.slice(start,end);assert.ok(start>=0,name);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot(){
 const elements=new Map(),timers=new Map(),requests=[],observers=[];let serial=0,s;
 class Element{
  constructor(id='',tag='div'){this.id=id;this.tagName=tag;this.children=[];this.hidden=false;this.open=false;this.attributes={};this.textContent='';this.style={setProperty(key,value){this[key]=value;}};this.classes=new Set();this.classList={contains:key=>this.classes.has(key),toggle:(key,on)=>on?this.classes.add(key):this.classes.delete(key)};if(id)elements.set(id,this);}
  get nextSibling(){return this.parentElement?.children[this.parentElement.children.indexOf(this)+1]||null;}
  append(...children){for(const child of children)this.insertBefore(child,null);}
  insertBefore(child,next){if(child.parentElement){const siblings=child.parentElement.children;siblings.splice(siblings.indexOf(child),1);}child.parentElement=this;this.children.splice(next?this.children.indexOf(next):this.children.length,0,child);}
  replaceChildren(...children){this.children=[];this.append(...children);}
  setAttribute(key,value){this.attributes[key]=String(value);}
  contains(node){while(node){if(node===this)return true;node=node.parentElement;}return false;}
  focus(){s.document.activeElement=this;}
 }
 const body=new Element('body'),shell=new Element('shell'),bar=new Element('infinityPreviewBar'),wrap=new Element('arenaWrap'),fps=new Element('fpsIndicator'),next=new Element('fpsNext');body.append(shell);shell.append(bar,wrap);wrap.append(fps,next);
 const right=new Element('infinityPreviewRight'),panel=new Element('infinityPreviewScoreboard');bar.append(new Element('infinityPreviewOnlineCount'),right,panel);right.append(new Element('infinityPreviewScores'),new Element('infinityPreviewScoreboardBtn'));panel.append(new Element('infinityPreviewScoreboardTitle'),new Element('infinityPreviewLeaders'),new Element('infinityPreviewScoreboardNote'));panel.hidden=true;
 for(const id of ['rulesSummary','roster','infiniteArena','pilotName','controlsDialog'])new Element(id,id==='infiniteArena'||id==='controlsDialog'?'dialog':'div');
 function target(extra={}){return Object.assign(extra,{listeners:new Map(),addEventListener(type,fn){this.listeners.set(type,fn);},removeEventListener(type,fn){if(this.listeners.get(type)===fn)this.listeners.delete(type);},emit(type,event={}){this.listeners.get(type)?.(event);}});}
 const r={rules:{teamMode:'ffa',infinity:false},players:[{id:0,member:1,name:'SNOW <FOX>',kind:'human',color:'#123456'},{id:2,member:2,name:'WING',kind:'local',owner:0,color:'#abcdef'}]};
 s={settingsResetActive:false,phase:'menu',mode:'room',playMode:'online',roomData:()=>r,currentRules:()=>r.rules,infinityPlayMode:()=>s.playMode,localPlayerID:()=>0,secondLocal:()=>r.players.find(p=>p.kind==='local'&&p.owner===0&&!p.spectating),localRoom:{self:0,players:r.players},tanks:[],COLORS:['#123456','#abcdef'],paintColor:c=>c,
  document:target({body,hidden:false,createElement:tag=>new Element('',tag),querySelectorAll:selector=>selector==='dialog'?[...elements.values()].filter(node=>node.tagName==='dialog'):[],querySelector:selector=>selector==='dialog[open]'?[...elements.values()].find(node=>node.tagName==='dialog'&&node.open):null}),window:target(),navigator:{onLine:true},location:{protocol:'https:',href:'https://leqra.test/?room=PRIVATE'},URL,AbortController,
  resize(){s.resizes=(s.resizes||0)+1;},$:id=>elements.get(id),MutationObserver:class{constructor(fn){this.fn=fn;this.entries=[];observers.push(this);}observe(node,options){this.entries.push([node,options]);}disconnect(){this.disconnected=true;}},
  setTimeout(fn,ms){timers.set(++serial,{fn,ms});return serial;},clearTimeout(id){timers.delete(id);},fetch(url,options){return new Promise((resolve,reject)=>{const request={url:String(url),options,resolve:data=>resolve({ok:true,json:async()=>data}),reject};requests.push(request);options.signal.addEventListener('abort',()=>reject(Error('Aborted')));});},
 };
 vm.createContext(s);require('./identity_fixture.cjs')(s,source);for(const name of ['orderedRoster','initInfinityPreview'])vm.runInContext(declaration(name),s);s.initInfinityPreview();
 const flush=()=>new Promise(setImmediate),run=ms=>{for(const [id,timer]of [...timers])if(timer.ms===ms){timers.delete(id);timer.fn();}};
 return{s,$:s.$,r,requests,timers,observers,bar,wrap,fps,next,flush,run};
}

test('Infinity preview uses real public counts, a measured FPS node and the shared local score layout',async()=>{
 const h=boot(),{s,$,requests}=h;assert.equal(h.bar.hidden,false);assert.equal(s.document.body.classList.contains('infinity-preview'),true);assert.equal(h.fps.parentElement,h.bar);assert.equal($('infinityPreviewOnlineCount').textContent,'— online');assert.equal(requests.length,1);assert.equal(requests[0].url,'https://leqra.test/api/infinity');assert.equal(requests[0].options.cache,'no-store');
 const pilots=$('infinityPreviewScores').children;assert.deepEqual(pilots.map(p=>p.children[0].textContent),['SNOW <FOX> (P1)','WING (P2)']);assert.equal(pilots[0].style.color,'#123456');assert.equal(pilots[1].children[1].textContent,': (0, #0)');
 requests[0].resolve({players:7,tankCount:18,leaders:Array.from({length:12},(_,i)=>({id:i+1,name:'Tank <'+i+'>',score:30-i,colorIndex:i%2,rank:i+1}))});await h.flush();
 assert.equal($('infinityPreviewOnlineCount').textContent,'7 online');assert.equal($('infinityPreviewLeaders').children.length,10);assert.equal($('infinityPreviewLeaders').children[0].children[0].textContent,'Tank <0>');assert.equal($('infinityPreviewLeaders').children[0].children[0].style.fontWeight,'400','public pilots are not local merely because the room is on this device');
 assert.equal($('infinityPreviewScoreboardBtn').textContent,'Top 10 Tanks');$('infinityPreviewScoreboardBtn').onclick();assert.equal($('infinityPreviewScoreboard').hidden,false);assert.equal($('infinityPreviewScoreboardBtn').attributes['aria-expanded'],'true');
 const escape={key:'Escape',preventDefault(){this.prevented=true;},stopPropagation(){this.stopped=true;}};s.document.emit('keydown',escape);assert.equal(escape.prevented,true);assert.equal($('infinityPreviewScoreboard').hidden,true);
});

test('leaving or hiding public preview aborts requests and restores the existing fixed FPS position',async()=>{
 const h=boot(),{s,$}=h;s.playMode='';s.window.leqraInfinityPreview.sync();assert.equal(h.bar.hidden,true);assert.equal(h.requests[0].options.signal.aborted,true);assert.equal(h.fps.parentElement,h.wrap);assert.equal(h.fps.nextSibling,h.next);assert.equal(s.document.body.classList.contains('infinity-preview'),false);
 await h.flush();s.playMode='online';s.window.leqraInfinityPreview.sync();assert.equal(h.requests.length,2);assert.equal($('infinityPreviewOnlineCount').textContent,'— online');
 s.document.hidden=true;s.document.emit('visibilitychange');assert.equal(h.requests[1].options.signal.aborted,true);await h.flush();assert.equal(h.timers.size,0);
 s.document.hidden=false;s.document.emit('visibilitychange');assert.equal(h.requests.length,3);
 $('controlsDialog').open=true;h.observers[0].fn([{type:'attributes',target:$('controlsDialog')}]);assert.equal(h.requests[2].options.signal.aborted,true,'covered menus do not poll a hidden header');await h.flush();
 $('controlsDialog').open=false;h.observers[0].fn([{type:'attributes',target:$('controlsDialog')}]);assert.equal(h.requests.length,4);
 $('infiniteArena').open=true;s.window.leqraInfinityPreview.sync();assert.equal(h.bar.hidden,true);assert.equal(h.requests[3].options.signal.aborted,true);assert.equal(h.fps.parentElement,h.wrap);
});

test('private and offline Infinity previews use room pilots without querying public state',async()=>{
 const h=boot(),{s,$,r}=h;s.playMode='';r.rules.infinity=true;r.players[1].spectating=true;r.players.push({id:3,member:3,name:'REMOTE',kind:'human',color:'#fedcba'},{id:4,member:4,name:'RUST',kind:'bot',color:'#ffeeaa'});s.window.leqraInfinityPreview.sync();await h.flush();
 assert.equal(h.bar.hidden,false);assert.equal($('infinityPreviewOnlineCount').hidden,true);assert.equal($('infinityPreviewScores').children.length,1);assert.equal($('infinityPreviewLeaders').children.length,3);assert.equal(h.timers.size,0);
 const rows=$('infinityPreviewLeaders').children;assert.equal(rows[0].children[0].style.fontWeight,'700');assert.equal(rows[1].children[0].style.fontWeight,'400');
 s.phase='playing';s.window.leqraInfinityPreview.sync();assert.equal(h.bar.hidden,true);
});

test('public polling retries failures every ten seconds and stops permanently during settings reset',async()=>{
 const h=boot(),{s,$}=h;h.requests[0].reject(Error('offline'));await h.flush();assert.equal($('infinityPreviewOnlineCount').textContent,'— online');assert.match($('infinityPreviewScoreboardNote').textContent,/unavailable/);assert.deepEqual([...h.timers.values()].map(t=>t.ms),[10000]);
 h.run(10000);assert.equal(h.requests.length,2);h.requests[1].resolve({players:2,tankCount:2,leaders:[]});await h.flush();assert.equal($('infinityPreviewOnlineCount').textContent,'2 online');
 h.run(10000);assert.equal(h.requests.length,3);s.settingsResetActive=true;s.window.leqraInfinityPreview.stop();assert.equal(h.requests[2].options.signal.aborted,true);assert.equal(h.observers[0].disconnected,true);assert.equal(h.timers.size,0);assert.equal($('infinityPreviewScoreboard').hidden,true);
 s.settingsResetActive=false;s.window.leqraInfinityPreview.sync();assert.equal(h.requests.length,3,'late callbacks cannot restart the reset page');await h.flush();assert.equal(h.timers.size,0);
});

test('an empty public or private preview shows one centered message without a title or dividing line',async()=>{
 const h=boot(),{s,$}=h;h.requests[0].resolve({players:0,tankCount:0,leaders:[]});await h.flush();
 const check=()=>{assert.equal($('infinityPreviewScoreboard').classList.contains('is-empty'),true);assert.equal($('infinityPreviewScoreboardTitle').hidden,true);assert.equal($('infinityPreviewLeaders').hidden,true);assert.equal($('infinityPreviewLeaders').children.length,0);assert.equal($('infinityPreviewScoreboardNote').textContent,'No tanks are playing yet.');};check();
 s.playMode='';h.r.rules.infinity=true;h.r.players=[];s.window.leqraInfinityPreview.sync();check();
 const css=readFileSync(assetPath('style.css'),'utf8');assert.match(css,/\.infinity-preview-scoreboard\.is-empty>p\{[^}]*align-items:center;justify-content:center;[^}]*border-top:0;text-align:center/);assert.match(css,/\.infinity-preview-scoreboard\.is-empty>ol\{display:none\}/);
 const previewSelector='body.touch-ui .infinity-preview-header>.infinity-preview-scoreboard[open]',activeSelector='body.touch-ui .infinite-leaderboard[open]';
 assert.ok(css.indexOf(activeSelector)>css.indexOf(previewSelector),'fixture exercises the later active-arena height cap');
 assert.match(css,/body\.touch-ui \.infinity-preview-header>\.infinity-preview-scoreboard\[open\]\{max-height:50dvh\}/,'the preview parent adds specificity so the active touch arena height cap cannot clip an empty preview');
});
