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
 const right=new Element('infinityPreviewRight'),panel=new Element('infinityPreviewScoreboard');bar.append(new Element('infinityPreviewTitle'),new Element('infinityPreviewOnlineCount'),right,panel);right.append(new Element('infinityPreviewScores'),new Element('infinityPreviewScoreboardBtn'));panel.append(new Element('infinityPreviewScoreboardTitle'),new Element('infinityPreviewLeaders'),new Element('infinityPreviewScoreboardNote'));panel.hidden=true;
 for(const id of ['rulesSummary','roster','infiniteArena','pilotName','controlsDialog'])new Element(id,id==='infiniteArena'||id==='controlsDialog'?'dialog':'div');
 function target(extra={}){return Object.assign(extra,{listeners:new Map(),addEventListener(type,fn){this.listeners.set(type,fn);},removeEventListener(type,fn){if(this.listeners.get(type)===fn)this.listeners.delete(type);},emit(type,event={}){this.listeners.get(type)?.(event);}});}
 const r={rules:{teamMode:'ffa',infinity:false},players:[{id:0,member:1,name:'SNOW <FOX>',kind:'human',color:'#123456'},{id:2,member:2,name:'WING',kind:'local',owner:0,color:'#abcdef'}]};
 s={settingsResetActive:false,now:0,menuSamples:[],beginMenuPing(){},setMenuPing(value){s.menuSamples.push(value);},performance:{now:()=>s.now},phase:'menu',mode:'room',playMode:'online',roomData:()=>r,currentRules:()=>r.rules,infinityPlayMode:()=>s.playMode,localPlayerID:()=>0,secondLocal:()=>r.players.find(p=>p.kind==='local'&&p.owner===0&&!p.spectating),localRoom:{self:0,players:r.players},tanks:[],COLORS:['#123456','#abcdef'],paintColor:c=>c,
  document:target({body,hidden:false,createElement:tag=>new Element('',tag),querySelectorAll:selector=>selector==='dialog'?[...elements.values()].filter(node=>node.tagName==='dialog'):[],querySelector:selector=>selector==='dialog[open]'?[...elements.values()].find(node=>node.tagName==='dialog'&&node.open):null}),window:target(),navigator:{onLine:true},location:{protocol:'https:',href:'https://leqra.test/?room=PRIVATE'},URL,AbortController,
  resize(){s.resizes=(s.resizes||0)+1;},$:id=>elements.get(id),MutationObserver:class{constructor(fn){this.fn=fn;this.entries=[];observers.push(this);}observe(node,options){this.entries.push([node,options]);}disconnect(){this.disconnected=true;}},
  setTimeout(fn,ms){timers.set(++serial,{fn,ms});return serial;},clearTimeout(id){timers.delete(id);},fetch(url,options){return new Promise((resolve,reject)=>{const request={url:String(url),options,resolve:data=>resolve({ok:true,json:async()=>data}),reject};requests.push(request);options.signal.addEventListener('abort',()=>reject(Error('Aborted')));});},
 };
 vm.createContext(s);require('./identity_fixture.cjs')(s,source);for(const name of ['orderedRoster','initInfinityPreview'])vm.runInContext(declaration(name),s);s.initInfinityPreview();
 const flush=()=>new Promise(setImmediate),run=ms=>{for(const [id,timer]of [...timers])if(timer.ms===ms){timers.delete(id);timer.fn();}};
 return{s,$:s.$,r,requests,timers,observers,bar,wrap,fps,next,flush,run};
}

test('Infinity preview uses real public counts, a measured FPS node and the shared local score layout',async()=>{
 const h=boot(),{s,$,requests}=h;assert.equal(h.bar.hidden,false);assert.equal(s.document.body.classList.contains('infinity-preview'),true);assert.equal(h.fps.parentElement,h.bar);assert.equal($('infinityPreviewOnlineCount').textContent,'? online');assert.equal(requests.length,1);assert.equal(requests[0].url,'https://leqra.test/api/infinity');assert.equal(requests[0].options.cache,'no-store');
 assert.equal($('infinityPreviewTitle').textContent,'Public Infinity');
 const pilots=$('infinityPreviewScores').children;assert.deepEqual(pilots.map(p=>p.children[0].textContent),['SNOW <FOX> (P1)','WING (P2)']);assert.equal(pilots[0].style.color,'#123456');assert.equal(pilots[1].children[1].textContent,': ');assert.equal(pilots[1].children[2].textContent,'score: 0, rank: #0');assert.equal(pilots[0].attributes['aria-label'],'SNOW <FOX> (P1): score: 0, rank: #0');
 requests[0].resolve({players:7,tankCount:18,leaders:Array.from({length:12},(_,i)=>({id:i+1,name:'Tank <'+i+'>',score:30-i,colorIndex:i%2,rank:i+1}))});await h.flush();
 assert.equal($('infinityPreviewOnlineCount').textContent,'7 online');assert.equal($('infinityPreviewLeaders').children.length,10);assert.equal($('infinityPreviewLeaders').children[0].children[0].textContent,'Tank <0>');assert.equal($('infinityPreviewLeaders').children[0].children[0].style.fontWeight,'400','public pilots are not local merely because the room is on this device');
 assert.equal($('infinityPreviewScoreboardBtn').textContent,'LEADERBOARD');$('infinityPreviewScoreboardBtn').onclick();assert.equal($('infinityPreviewScoreboard').hidden,false);assert.equal($('infinityPreviewScoreboardBtn').attributes['aria-expanded'],'true');
 assert.equal($('infinityPreviewScoreboardTitle').hidden,false);assert.equal($('infinityPreviewScoreboardTitle').textContent,'LEADERBOARD');
 const escape={key:'Escape',preventDefault(){this.prevented=true;},stopPropagation(){this.stopped=true;}};s.document.emit('keydown',escape);assert.equal(escape.prevented,true);assert.equal($('infinityPreviewScoreboard').hidden,true);
});

test('the populated preview title can close its panel without leaving a collapsed card or stale header state',async()=>{
 const h=boot(),{s,$}=h;h.requests[0].resolve({players:1,tankCount:1,leaders:[{id:1,name:'PILOT',score:7,colorIndex:0,rank:1}]});await h.flush();
 const button=$('infinityPreviewScoreboardBtn'),panel=$('infinityPreviewScoreboard'),title=$('infinityPreviewScoreboardTitle');
 button.onclick();title.focus();panel.open=false;panel.ontoggle();
 assert.equal(panel.hidden,true);assert.equal(button.attributes['aria-expanded'],'false');assert.equal(s.document.activeElement,button);
 button.onclick();panel.ontoggle();assert.equal(panel.hidden,false);assert.equal(button.attributes['aria-expanded'],'true');
 // A queued close event must follow the current open state after a fast reopen.
 panel.open=false;button.onclick();panel.ontoggle();assert.equal(panel.hidden,false);assert.equal(button.attributes['aria-expanded'],'true');
});

test('leaving or hiding public preview aborts requests and restores the existing fixed FPS position',async()=>{
 const h=boot(),{s,$}=h;s.playMode='';s.window.leqraInfinityPreview.sync();assert.equal(h.bar.hidden,true);assert.equal(h.requests[0].options.signal.aborted,true);assert.equal(h.fps.parentElement,h.wrap);assert.equal(h.fps.nextSibling,h.next);assert.equal(s.document.body.classList.contains('infinity-preview'),false);
 await h.flush();s.playMode='online';s.window.leqraInfinityPreview.sync();assert.equal(h.requests.length,2);assert.equal($('infinityPreviewOnlineCount').textContent,'? online');
 s.document.hidden=true;s.document.emit('visibilitychange');assert.equal(h.requests[1].options.signal.aborted,true);await h.flush();assert.equal(h.timers.size,0);
 s.document.hidden=false;s.document.emit('visibilitychange');assert.equal(h.requests.length,3);
 $('controlsDialog').open=true;h.observers[0].fn([{type:'attributes',target:$('controlsDialog')}]);assert.equal(h.requests[2].options.signal.aborted,true,'covered menus do not poll a hidden header');await h.flush();
 $('controlsDialog').open=false;h.observers[0].fn([{type:'attributes',target:$('controlsDialog')}]);assert.equal(h.requests.length,4);
 $('infiniteArena').open=true;s.window.leqraInfinityPreview.sync();assert.equal(h.bar.hidden,true);assert.equal(h.requests[3].options.signal.aborted,true);assert.equal(h.fps.parentElement,h.wrap);
});

test('private and offline Infinity previews use room pilots without querying public state',async()=>{
 const h=boot(),{s,$,r}=h;s.playMode='';r.rules.infinity=true;r.players[1].spectating=true;r.players.push({id:3,member:3,name:'REMOTE',kind:'human',color:'#fedcba'},{id:4,member:4,name:'RUST',kind:'bot',color:'#ffeeaa'});s.window.leqraInfinityPreview.sync();await h.flush();
 assert.equal(h.bar.hidden,false);assert.equal($('infinityPreviewOnlineCount').hidden,true);assert.equal($('infinityPreviewScores').children.length,1);assert.equal($('infinityPreviewLeaders').children.length,3);assert.equal(h.timers.size,0);
 assert.equal($('infinityPreviewTitle').textContent,'Infinity','room and offline mode keep their distinct name');assert.equal($('infinityPreviewScoreboardBtn').textContent,'LEADERBOARD');assert.equal($('infinityPreviewScoreboardTitle').textContent,'LEADERBOARD');
 const rows=$('infinityPreviewLeaders').children;assert.equal(rows[0].children[0].style.fontWeight,'700');assert.equal(rows[1].children[0].style.fontWeight,'400');
 s.phase='playing';s.window.leqraInfinityPreview.sync();assert.equal(h.bar.hidden,true);
});

test('startup and tour name the public switch separately from room Infinity',()=>{
 const html=readFileSync(require('node:path').join(__dirname,'../web/index.html'),'utf8');
 assert.match(html,/<label[^>]+id="infinityToggleLabel"[^>]*>[\s\S]*?<strong>Public Infinity<\/strong>[\s\S]*?<\/label>/);
 const battle=html.split('<div data-intro-page="2"')[1].split('</div>')[0];
 assert.match(battle,/<li><strong>Public Infinity<\/strong>/);assert.match(battle,/Public Infinity switch above Play/);
 assert.match(battle,/Choose Infinity in Room settings/);assert.match(battle,/turn off Public Infinity/);
});

test('public polling retries failures every four seconds and stops permanently during settings reset',async()=>{
 const h=boot(),{s,$}=h;h.requests[0].reject(Error('offline'));await h.flush();assert.equal($('infinityPreviewOnlineCount').textContent,'? online');assert.match($('infinityPreviewScoreboardNote').textContent,/unavailable/);assert.deepEqual([...h.timers.values()].map(t=>t.ms),[4000]);
 h.run(4000);assert.equal(h.requests.length,2);h.requests[1].resolve({players:2,tankCount:2,leaders:[]});await h.flush();assert.equal($('infinityPreviewOnlineCount').textContent,'2 online');
 h.run(4000);assert.equal(h.requests.length,3);s.settingsResetActive=true;s.window.leqraInfinityPreview.stop();assert.equal(h.requests[2].options.signal.aborted,true);assert.equal(h.observers[0].disconnected,true);assert.equal(h.timers.size,0);assert.equal($('infinityPreviewScoreboard').hidden,true);
 s.settingsResetActive=false;s.window.leqraInfinityPreview.sync();assert.equal(h.requests.length,3,'late callbacks cannot restart the reset page');await h.flush();assert.equal(h.timers.size,0);
});

test('the first menu request supplies ping and online count together on a four-second cadence',async()=>{
 const h=boot(),{s,$}=h;assert.equal(h.requests.length,1,'polling starts immediately');
 s.now=240;h.requests[0].resolve({players:3,tankCount:3,leaders:[]});await h.flush();
 assert.equal($('infinityPreviewOnlineCount').textContent,'3 online');assert.deepEqual(s.menuSamples,[240]);
 assert.deepEqual([...h.timers.values()].map(timer=>timer.ms),[3760],'response time counts toward the four-second interval');
 h.run(3760);assert.equal(h.requests.length,2);
 h.requests[1].reject(Error('unavailable'));await h.flush();assert.equal(s.menuSamples.at(-1),null);
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
