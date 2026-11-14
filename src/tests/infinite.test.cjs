'use strict';

const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {test} = require('node:test');
const vm = require('node:vm');
const {assetPath} = require('./web_assets.cjs');

function harness(url = 'https://example.test/', openField = false, storage = new Map(), savedName = 'Saved pilot') {
 class Element {
  listeners = {};
  children = [];
  style = {
   removeProperty(name) { delete this[name]; },
   setProperty(name,value) { this[name] = value; },
   getPropertyValue(name) { return this[name] || ''; },
  };
  classes = new Set();
  classList = {remove: name => this.classes.delete(name), add: name => this.classes.add(name), toggle() {}};
  dataset = {};
  attributes = {};
  clientWidth = 390;
  clientHeight = 740;
  open = false;
  parentElement = null;
  _textContent = '';
  get innerHTML() {return this._html || '';}
  set innerHTML(value) {this._html=value;this.textContent=value.replace(/<[^>]+>/g,' ').replace(/\s+/g,' ').trim();}
  get textContent() { return this.children.length ? this._textContent + this.children.map(child=>child.textContent).join('') : this._textContent; }
  set textContent(value) { this.replaceChildren(); this._textContent = value; }
  closest() { return false; }
  querySelectorAll() { return []; }
  setAttribute(name,value) {this.attributes[name]=String(value);}
  getContext() {
   let angle = 0, radius = null;
   return new Proxy({
    beginPath() {radius=null;},
    arc(x,y,r) {radius=r;},
    rotate: value => {angle = value;},
    moveTo(x,y) {if (x===41 && y===-6) markers.push({angle,color:this.strokeStyle});},
    fillText(text,x,y) {labels.push({text,x,y,color:this.fillStyle});},
    stroke() {strokes.push(this.strokeStyle);if(radius!==null)rings.push({r:radius,color:this.strokeStyle});},
   }, {get: (target,key) => target[key] ?? (()=>{})});
  }
  getBoundingClientRect() { return {left:0,top:0,width:96,height:96}; }
  addEventListener(type, listener) { (this.listeners[type] ||= []).push(listener); }
  emit(type, event = {}) {
   for (const listener of this.listeners[type] || []) {
   listener({type,target: this, stopPropagation() {}, preventDefault() {}, ...event});
   }
  }
  showModal() { this.open = true; }
  close() { this.open = false; this.emit('close'); }
  focus() {}
  get firstChild() {return this.children[0] || null;}
  get nextSibling() {return this.parentElement?.children[this.parentElement.children.indexOf(this)+1] || null;}
  remove() {
   if(this.parentElement){const nodes=this.parentElement.children;nodes.splice(nodes.indexOf(this),1);this.parentElement=null;}
  }
  insertBefore(child,next) {
   child.remove();const index=next?this.children.indexOf(next):this.children.length;
   this.children.splice(index,0,child);child.parentElement=this;
  }
  append(...children) {for(const child of children)this.insertBefore(child,null);}
  replaceChildren(...children) {this._textContent='';for(const child of [...this.children])child.remove();this.append(...children);}
 }
 const sockets = [];
 class WebSocket extends Element {
  static OPEN = 1;
  readyState = WebSocket.OPEN;
  bufferedAmount = 0;
  sent = [];
  constructor(url) { super(); this.url = String(url); sockets.push(this); }
  send(data) { this.sent.push(JSON.parse(data)); }
  receive(message) { this.emit('message', {data: JSON.stringify(message)}); }
  close() { this.readyState = 3; this.emit('close'); }
 }
 const elements = new Map();
 const byID = id => {
  if (!elements.has(id)) elements.set(id, new Element());
  return elements.get(id);
 };
 const document = new Element();
 byID('infiniteStage').append(byID('infiniteLeaderboardPanel'),byID('infiniteTouchControls'));
 byID('infiniteLeaderboardPanel').append(byID('infiniteLeaderboardTitle'),byID('infiniteTeamScores'),byID('infiniteLeaderboard'));
 document.getElementById = byID;
 document.createElement = tag => Object.assign(new Element(),{tagName:tag.toUpperCase()});
 document.querySelector = selector => selector === 'dialog[open]' && [...elements.values()].find(element => element.open);
 const window = new Element();
 window.leqra = {version: '9.1.0'};
 window.matchMedia = () => ({matches: false});
 const sounds = [], loadouts = [], markers = [], labels = [], strokes = [], rings = [], frameSamples = [], bulletDraws = [], combatPrefs = {visual:true,audio:true,fps:false};
 let chatOpen = false;
 const sidebarHome = {}, sidebarMoves = [], headerHome = {}, headerMoves = [];
 let sidebarParent = sidebarHome;
 let headerParent = headerHome;
 const powers = Object.fromEntries(['rapid','scatter','shield','homing','grenade','speed','laser','cannon','ghost','starman']
  .map(name => [name, {name, color: '#fff'}]));
 window.leqraInfinityArt = {
  colors: ['#32c5ff','#ff758f','#73cee4','#c5a2ff','#ffc46b','#ff83bd','#75f0cb','#b7c6ee'], theme: {}, powers, renderPixelRatio: () => 1,
  tile() {}, wall() {}, pickup() {}, hull() {}, turret() {}, rect: ctx=>ctx.beginPath(), drawBadges() {}, bullets(items) {bulletDraws.push(items.map(b=>({...b})));if(bulletDraws.length>8)bulletDraws.shift();},
  ageTank: tank => tank,
  sampleFrame: (now,work,latency=null) => {frameSamples.push({now,work,latency});context.sampleFrame(now,work,'infiniteFPSIndicator',latency);},
  renderLoadout: (tank, num, projectiles, blocked, phase, twoPilots) => {
   loadouts[num] = {tank, projectiles, blocked, phase};
   context.renderDeathNotice(tank,num,twoPilots,context.infinityHUDId);
  },
  primeAudioUnlock() {}, touchPolicy() {}, grenadeDragFactor: () => 1,
  missileTurn: 4.8,
  openControls: () => byID('controlsDialog').showModal(),
  chatOpen: () => chatOpen,
  mountSidebar: container => {sidebarParent = container;sidebarMoves.push('mount');},
  restoreSidebar: container => {if(sidebarParent===container){sidebarParent=sidebarHome;sidebarMoves.push('restore');}},
  mountHeader: container => {headerParent=container;headerMoves.push('mount');},
  restoreHeader: container => {if(headerParent===container){headerParent=headerHome;headerMoves.push('restore');}},
  isTouchUI: () => false,
  toggleFullscreen: () => sounds.push('fullscreen'),
  toggleSound: () => sounds.push('mute'),
  shot: kind => sounds.push('shot:' + kind),
  ricochet: () => sounds.push('ricochet'), collect: () => sounds.push('pickup'), shield: () => sounds.push('shield'),
  blast: () => sounds.push('blast'), grenade: () => sounds.push('grenadeblast'), impact: () => sounds.push('impact'),
 };
 let now = 0, scheduled, randomState = 1, nextTimer = 0;
 const timers = new Map();
 const math = Object.create(Math);
 math.random = openField ? () => .5 :
  () => ((randomState = Math.imul(randomState, 1664525) + 1013904223 | 0) >>> 0) / 0x100000000;
 const context = vm.createContext({
  window, document, location: new URL(url), URL, WebSocket, Math: math,
  localStorage: {getItem: () => savedName}, performance: {now: () => now},
  sessionStorage: {
   getItem: key => storage.get(key) ?? null,
   setItem: (key,value) => storage.set(key,value),
   removeItem: key => storage.delete(key),
  },
  requestAnimationFrame: callback => { scheduled = callback; return 1; },
  cancelAnimationFrame: () => { scheduled = undefined; },
  setTimeout: (callback,delay) => {timers.set(++nextTimer,{callback,at:now+delay});return nextTimer;},
  clearTimeout: id => timers.delete(id),
 });
 vm.runInContext(readFileSync(assetPath('infinite-maze.js'), 'utf8'), context);
 vm.runInContext(readFileSync(assetPath('netcode.js'), 'utf8'), context);
 window.leqraNet = context.leqraNet;
 const game = readFileSync(assetPath('game.js'), 'utf8');
 Object.assign(context, {$:byID,combatPrefs});
 vm.runInContext('const MAX_TANKS=8;'+game.match(/^const COLORS=.*$/m)[0]+game.match(/^const colorIndex=.*$/m)[0]+';this.colorIndex=colorIndex;this.canonicalColor=index=>COLORS[index]||"";',context);
 window.leqraInfinityArt.colorIndex = context.colorIndex;
 window.leqraInfinityArt.canonicalColor=context.canonicalColor;
 vm.runInContext(game.slice(game.indexOf('function infinityHUDId('),game.indexOf('function renderInfinityLoadout(')),context);
 vm.runInContext(game.slice(game.indexOf('const frameStats='),game.indexOf('function initFrameSettings(')), context);
 const keyPolicy = game.slice(game.indexOf('function arenaKeyBlocked('), game.indexOf('// All input paths'));
 const keyLabel = game.slice(game.indexOf('function keyLabel('), game.indexOf('function aliasesActive('));
 const composition = game.match(/^function composingKey\(e\).*$/m)[0];
 vm.runInContext('let bindingCapture=null;\n'+composition+'\n'+keyLabel+keyPolicy, context);
 const hintFunctions=['controlKeycapsHTML','controlMouseKeyHTML','controlKeyHTML','controlHintHTML'].map(name=>{
  const start=game.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=game.indexOf('\n',start),line=game.slice(start,end);return line.endsWith('}')?line:game.slice(start,game.indexOf('\n}',end)+2);
 });
 vm.runInContext(game.match(/^const escapeHTML=.*$/m)[0]+'\n'+hintFunctions.join('\n'),context);
 vm.runInContext(game.match(/^function pilotIdentity\(.*$/m)[0]+'\n'+game.match(/^function cleanPilotName\(.*$/m)[0],context);
 Object.assign(window.leqraInfinityArt, {arenaKeyBlocked: context.arenaKeyBlocked, keyLabel: context.keyLabel,controlHintHTML:context.controlHintHTML,pilotIdentity:context.pilotIdentity,cleanPilotName:context.cleanPilotName});
 const projectileState = game.slice(game.indexOf('function pilotProjectileState('), game.indexOf('function liveFeedbackTank('));
 vm.runInContext(projectileState, context);
 window.leqraInfinityArt.projectileState = context.pilotProjectileState;
 Object.assign(context,{combatPrefs,POWER:powers,paintColor:color=>color,tone:frequency=>sounds.push('tone:'+frequency)});
 for (const name of ['missileLocks','updateHomingAlert','drawHomingWarnings']) {
  const start = game.indexOf('function '+name+'(');
  vm.runInContext(game.slice(start,game.indexOf('\n}',start)+2),context);
  window.leqraInfinityArt[name] = context[name];
 }
 vm.runInContext(game.slice(game.indexOf('function choosePickup('), game.indexOf('// Power-up colors')), context);
 window.leqraInfinityArt.choosePickup = context.choosePickup;
 const recycle = game.indexOf('function recycleStarmanProjectiles(');
 context.MACHINE_CAPACITY = window.leqraNet.MACHINE_CAPACITY;
 vm.runInContext(game.slice(recycle,game.indexOf('\n}',recycle)+2), context);
 window.leqraInfinityArt.recycleStarmanProjectiles = context.recycleStarmanProjectiles;
 const grant = game.slice(game.indexOf('function grantPower('), game.indexOf('function pickupMessage('));
 Object.assign(context, {POWER:powers, MAX_SPEED_STACKS:5, MACHINE_FIRING_ROUNDS:180, shieldCount:t=>t.shieldCharges||0, speedCount:t=>t.speedStacks||0});
 vm.runInContext(grant, context);
 window.leqraInfinityArt.grantPower = context.grantPower;
 if (openField) {
  window.leqraInfiniteMaze = {cellSize: 84, create: () => ({
   wallsNear: () => [], blocked: () => false,
   visitWalls(x0,y0,x1,y1,visit) {
    return this.wallsNear(x0,y0,x1,y1).some(({x,y,w,h})=>
     x<=x1&&x+w>=x0&&y<=y1&&y+h>=y0&&visit(x,y,w,h));
   },
  })};
 }
 vm.runInContext(readFileSync(assetPath('infinite.js'), 'utf8').replace('window.leqraInfinity =', 'window.testArena = () => session; window.testDraw = draw; window.testFire = fireShot; window.testBotInput = botInput; window.leqraInfinity ='), context);
 byID('pauseBtn').addEventListener('click',()=>window.leqraInfinity.togglePause());
 const advance = (frames = 1) => {
  for (let i = 0; i < frames; i++) {
   now += 1000 / 60;
   const frame = scheduled;
   scheduled = undefined;
   frame?.(now);
  }
 };
 const elapse = ms => {
  const until = now+ms;
  for (;;) {
   const next = [...timers].sort(([,a],[,b])=>a.at-b.at)[0];
   if (!next || next[1].at > until) break;
   now = Math.max(now,next[1].at);
   timers.delete(next[0]);
   next[1].callback();
  }
  now = until;
 };
 return {infinity: window.leqraInfinity, byID, sockets, advance, elapse, window, state:window.testArena, botInput:window.testBotInput,setRandom(fn){math.random=fn;},sounds, loadouts, markers, labels, strokes, rings, frameSamples, bulletDraws, combatPrefs,sidebarMoves,sidebarHome,get sidebarParent(){return sidebarParent;},headerMoves,headerHome,get headerParent(){return headerParent;},setChatOpen(value){chatOpen=value;if(value)window.leqraInfinity.resetControls();}};
}

test('all online Infinity projectile kinds survive newest removal until playback reaches the terminal frame',()=>{
 const h=harness(undefined,true);h.infinity.start('online');const ws=h.sockets[0];ws.receive({type:'welcome',id:1,seed:0});
 const tank={id:1,hp:1,x:42,y:42,angle:0,spawnSerial:1};
 const kinds=['regular','rapid','scatter','homing','grenade','cannon'];
 const packet=(tick,bullets)=>({type:'state',tick,tanks:[tank],bullets,players:1,leaderboard:[]});
 ws.receive(packet(2,[]));ws.receive(packet(4,kinds.map((kind,i)=>({id:i+1,owner:2,kind,colorIndex:1,x:100,y:100+i*5,vx:100,vy:0,life:1,age:.01,bounces:0}))));ws.receive(packet(6,[]));
 const w=h.state(),a=w.motionBuffer.items.find(s=>s.tick===4),b=w.motionBuffer.items.find(s=>s.tick===6);
 w.motionBuffer.time=(a.netTime+b.netTime)/2;h.window.testDraw(w,w.arrived,0);
 assert.deepEqual(Array.from(h.bulletDraws.at(-1),b=>b.id),[1,2,3,4,5,6]);
 w.motionBuffer.time=b.netTime;h.window.testDraw(w,w.arrived,0);assert.equal(h.bulletDraws.at(-1).length,0);h.infinity.close();
});

test('all offline Infinity ballistic muzzle kills present a shell without leaving a damaging projectile',()=>{
 for(const kind of ['regular','rapid','scatter','homing','grenade','cannon']){
  const h=harness(undefined,true);h.infinity.start('offline',{roomRules:{infinityRandomBots:false}});const w=h.state(),p=w.tanks[0];
  Object.assign(p,{x:100,y:100,angle:0,hp:1,spawnProtected:false,invulnerable:0,power:kind==='regular'?'':kind,powerTime:10,charges:3,machineRounds:180});
  const target={...p,id:'target',name:'Target',bot:true,x:134,y:100,power:'',charges:0,team:0,score:0};w.tanks.push(target);
  h.window.testFire(w,p);assert.equal(target.hp,0,kind);h.window.testDraw(w,100,0);
  assert.ok(h.bulletDraws.at(-1).some(b=>(b.kind||'regular')===kind),kind+' remains visible');
  h.window.testDraw(w,151,0);assert.ok(h.bulletDraws.at(-1).some(b=>b.flight));h.window.testDraw(w,159,0);assert.ok(!h.bulletDraws.at(-1).some(b=>b.flight),kind+' visual grace is bounded');h.infinity.close();
 }
});

test('room Infinity shows a between-snapshot terminal cannon even when that shot ends the run',()=>{
 const h=harness(undefined,true);h.infinity.start('online',{code:'ROOM',token:'proof'});const ws=h.sockets[0];ws.receive({type:'welcome',id:1,seed:0});
 const packet={type:'state',tick:10,tanks:[{id:1,hp:1,x:42,y:42,angle:0}],bullets:[],players:1,leaderboard:[]};ws.receive(packet);
 ws.receive({...packet,tick:12,result:{id:1,name:'Winner',score:5},effects:[{id:1,kind:'impact',x:100,y:42,owner:1,flight:{id:7,owner:1,colorIndex:0,kind:'cannon',radius:14,startTick:10,endTick:11,points:[{x:70,y:42,tick:10},{x:100,y:42,tick:11}]}}]});
 const w=h.state();h.window.testDraw(w,100,0);assert.equal(h.bulletDraws.at(-1)[0]?.id,7);
 h.window.testDraw(w,151,0);assert.equal(h.bulletDraws.at(-1)[0]?.x,100);h.window.testDraw(w,159,0);assert.equal(h.bulletDraws.at(-1).length,0);assert.ok(h.sounds.includes('impact'));h.infinity.close();
});

test('Dumb Infinity bots retain stale aim, hesitate and space trigger pulses',()=>{
 const h=harness(undefined,true);h.infinity.start('offline');h.setRandom(()=>.5);
 const world=h.state(),pilot=world.tanks[0];pilot.invulnerable=0;
 const bot={id:'bot-test',bot:true,hp:1,x:pilot.x+100,y:pilot.y,angle:Math.PI,difficulty:'dumb',nextDecision:0,nextDumbShot:null};
 world.tanks.push(bot);
 const input=()=>h.botInput(world,bot,[pilot]);
 assert.equal(input().fire,false);
 const old=input();pilot.y+=60;world.time=.3;
 assert.equal(input().stickY,old.stickY,'aim must not track between slow decisions');
 world.time=1.81;let controls=input();bot.angle=Math.atan2(controls.stickY,controls.stickX);
 assert.equal(input().fire,true);
 world.time=1.82;assert.equal(input().fire,false,'a trigger pulse cannot become held rapid fire');
 world.time=3.62;assert.equal(input().fire,true);
 h.setRandom(()=>.1);world.time=5.5;assert.equal(input().fire,false,'Dumb bots sometimes forget to attack');
 h.setRandom(()=>.5);world.time=6.5;pilot.invulnerable=1;controls=input();bot.angle=Math.atan2(controls.stickY,controls.stickX);
 assert.equal(input().fire,false,'spawn protection remains respected');
 pilot.invulnerable=0;assert.equal(input().fire,true);
 h.infinity.close();
});

test('online Godlike warnings use authoritative bot difficulty rather than callsigns',()=>{
 const h=harness(undefined,true);h.infinity.start('online');const socket=h.sockets[0];
 socket.receive({type:'welcome',id:1,seed:0});
 const tanks=[{id:1,name:'Godlike fan',bot:false,difficulty:'godlike',hp:1,x:42,y:42,colorIndex:0},
  {id:2,name:'Bot 2',bot:true,difficulty:'dumb',hp:1,x:126,y:42,colorIndex:1},
  {id:3,name:'Bot 3 - Godlike',bot:true,difficulty:'godlike',hp:1,x:210,y:42,colorIndex:2}];
 socket.receive({type:'state',tick:1,tanks,bullets:[],players:1,leaderboard:[]});
 h.labels.length=0;h.advance();
 assert.equal(h.state().tanks.find(t=>t.id===3).difficulty,'godlike');
 const warnings=h.labels.filter(label=>label.text==='GODLIKE');assert.equal(warnings.length,1);
 assert.equal(warnings[0].color,'#ffc46b');
 h.infinity.close();
});

test('Infinity Starman loop follows either local pilot and stops on pause, expiry, death, disconnect and closure',()=>{
 const h=harness(undefined,true),wanted=[];h.window.leqraInfinityArt.starmanAudio=active=>wanted.push(active);
 h.infinity.start('offline',{localName:'Wing'});const world=h.state(),pilot=world.tanks.find(t=>t.id===world.local.id);
 pilot.starmanTime=4;h.advance();assert.equal(wanted.at(-1),true,'P2 starts the shared loop');
 h.infinity.togglePause();h.advance();assert.equal(wanted.at(-1),false);h.infinity.togglePause();h.advance();assert.equal(wanted.at(-1),true);
 pilot.hp=0;h.advance();assert.equal(wanted.at(-1),false);pilot.hp=1;pilot.starmanTime=0;
 world.tanks.find(t=>t.id===world.id).starmanTime=3;h.advance();assert.equal(wanted.at(-1),true);
 world.tanks.find(t=>t.id===world.id).starmanTime=0;h.advance();assert.equal(wanted.at(-1),false);
 h.infinity.close();assert.equal(wanted.at(-1),false);
 h.infinity.start('online');const socket=h.sockets.at(-1);socket.receive({type:'welcome',id:1,seed:0});socket.receive({type:'state',tick:1,tanks:[{id:1,name:'Pilot',hp:1,starmanTime:5,x:42,y:42}],bullets:[],players:1,leaderboard:[]});
 h.advance();assert.equal(wanted.at(-1),true);h.advance(125);assert.equal(wanted.at(-1),false,'a stale socket cannot sustain the loop');h.infinity.close();
});

test('a cached public account key never turns a first private join into a nonexistent body resume',()=>{
 for(const [options,resume]of [[{code:'ROOM',token:'proof'},undefined],[{code:'ROOM',token:'proof',resumeGeneration:7},true],[{},true],[{code:'ROOM',token:'proof',public:true},true],[{code:'ROOM',token:'proof',spectating:true},undefined]]){
  const h=harness(undefined,true);h.window.leqraInfinityArt.publicIdentityToken=()=> 'p_'+'a'.repeat(43);
  h.infinity.start('online',options);const ws=h.sockets[0];ws.emit('open');assert.equal(ws.sent[0].resume,resume,JSON.stringify(options));h.infinity.close();
 }
});

test('room spectators can follow every ranked tank without owning or controlling a body',async()=>{
 const h=harness(undefined,true),audio=[];h.window.leqraInfinityArt.starmanAudio=value=>audio.push(value);
 h.infinity.start('online',{code:'WATCH',token:'viewer-proof',spectating:true,localName:'Unused P2'});const ws=h.sockets[0];ws.emit('open');
 const join=ws.sent[0];assert.equal(join.spectating,true);assert.equal(join.localName,undefined);assert.equal(join.publicToken,undefined);
 ws.receive({type:'welcome',id:0,spectating:true,following:1,seed:0,generation:1});
 const leaders=Array.from({length:24},(_,i)=>({id:i+1,name:'Tank '+(i+1),score:24-i,bot:i>1,colorIndex:i%8}));
 const state={type:'state',spectating:true,following:1,tick:1,tanks:[{id:1,name:'Tank 1',hp:1,starmanTime:8,x:42,y:42,spawnSerial:1}],bullets:[],players:2,leaderboard:leaders};
 ws.receive(state);h.advance();assert.equal(h.byID('infiniteLeaderboard').children.length,24);assert.equal(h.infinity.localPilots().length,0);assert.equal(h.state().local,null);
 assert.match(h.byID('infiniteKills').textContent,/Following Tank 1/);assert.equal(audio.at(-1),false);
 const button=h.byID('infiniteLeaderboard').children[22].children[0];button.emit('click');assert.equal(ws.sent.at(-1).type,'follow');assert.equal(ws.sent.at(-1).target,23);
 ws.receive({type:'followed',following:23});ws.receive({...state,tick:2,following:23,tanks:[{id:23,name:'Tank 23',hp:0,x:8400,y:4200,spawnSerial:2}]});h.advance(3);
 assert.equal(h.state().camera.x,8400);assert.match(h.byID('infiniteKills').textContent,/respawning/);
 h.byID('infiniteArena').emit('keydown',{code:'KeyW',target:{tagName:'CANVAS'}});h.infinity.resetControls();assert.equal(ws.sent.filter(packet=>packet.type==='input').length,0);
 await assert.rejects(h.infinity.renamePilot(0,'Forged'),/Spectators/);
 ws.receive({type:'error',action:'follow',code:'follow_invalid',message:'Tank removed'});h.advance(3);assert.notEqual(h.state().failed,true);assert.match(h.byID('infiniteStatus').textContent,/Tank removed/);
 ws.receive({...state,tick:3,following:0,tanks:[],leaderboard:[]});h.advance(3);assert.equal(h.state().camera.x,42);assert.match(h.byID('infiniteKills').textContent,/waiting for tanks/);h.infinity.close();
});

test('nearby Godlike spawn notices precede encounters, deduplicate by life and never shift gameplay',()=>{
 const h=harness(undefined,true);h.infinity.start('online');const socket=h.sockets[0];
 socket.receive({type:'welcome',id:1,seed:0});
 const tanks=[{id:1,name:'Pilot',bot:false,hp:1,x:42,y:42,colorIndex:0,spawnSerial:1},
  {id:3,name:'Bot 3 - Godlike',bot:true,difficulty:'godlike',hp:1,x:462,y:42,colorIndex:2,spawnSerial:2}];
 const packet={type:'state',tick:1,tanks,bullets:[],players:1,leaderboard:[],godlikeSpawns:[{id:3,spawnSerial:2,name:'Bot 3 - Godlike'}]};
 socket.receive(packet);const notice=h.byID('godlikeSpawnNotice');
 assert.equal(notice.hidden,false);assert.match(notice.textContent,/Bot 3 - Godlike spawned nearby/);
 h.advance(180);socket.receive({...packet,tick:3});h.advance(190);
 assert.equal(notice.hidden,true,'repeated snapshots must not extend the six-second notice');
 tanks[1].spawnSerial=3;socket.receive({...packet,tick:5,godlikeSpawns:[{id:3,spawnSerial:3,name:'Bot 3 - Godlike'}]});assert.equal(notice.hidden,false);
 h.infinity.close();assert.equal(notice.hidden,true);
});

test('spawn notices cannot turn human callsigns into Godlike bot alerts',()=>{
 const h=harness(undefined,true);h.infinity.start('online');const socket=h.sockets[0];
 socket.receive({type:'welcome',id:1,seed:0});
 socket.receive({type:'state',tick:1,tanks:[{id:1,name:'Godlike Bot 7',bot:false,difficulty:'godlike',spawnSerial:1,hp:1,x:42,y:42}],bullets:[],players:1,leaderboard:[],godlikeSpawns:[{id:1,spawnSerial:1,name:'Godlike Bot 7'}]});
 h.advance();assert.equal(h.byID('godlikeSpawnNotice').hidden,true);h.infinity.close();
});

test('Infinity primary defaults use Player 1 without replacing saved or explicit callsigns',()=>{
 for(const saved of [undefined,'','   ','PILOT','Pilot','YOU']){
  const storage=new Map(),h=harness(undefined,true,storage,saved??null),want=saved?.trim()||'Player 1';
  h.infinity.start('offline');assert.equal(h.state().name,want);assert.equal(h.state().tanks.find(t=>t.id===h.state().id).name,want);assert.equal(h.infinity.localPilots()[0].name,want);h.infinity.close();
  h.infinity.start('online');h.sockets[0].emit('open');assert.equal(h.sockets[0].sent[0].name,want);h.infinity.close();
  h.infinity.start('offline',{name:'CUSTOM',localName:'CO-PILOT'});assert.deepEqual(Array.from(h.infinity.localPilots(),p=>p.name),['CUSTOM','CO-PILOT']);h.infinity.close();
 }
});

test('public standalone and room-party Infinity use Public Infinity while offline and private keep Infinity',()=>{
 for(const [mode,options,label,destination]of [
  ['offline',{},'Infinity',null],
  ['online',{},'Public Infinity','Public Infinity'],
  ['online',{code:'ROOM',token:'own'},'Infinity','room Infinity'],
  ['online',{code:'ROOM',token:'own',public:true},'Public Infinity','Public Infinity'],
 ]){
  const {infinity,byID}=harness(undefined,true);infinity.start(mode,{name:'Lead',...options});
  assert.equal(byID('infiniteArenaTitle').textContent,label);
  assert.equal(byID('infiniteExit').textContent,'Exit '+label);
  assert.ok(byID('infiniteCanvas').attributes['aria-label'].startsWith(label+' maze.'));
  if(destination)assert.equal(byID('infiniteStatus').textContent,'Connecting to '+destination+'…');
  infinity.togglePause();assert.equal(infinity.sidebarHelp().title,label);infinity.close();
 }
});

test('Public Infinity disconnect and retry messages retain the public name for standalone and party entry',()=>{
 for(const options of [{},{code:'ROOM',token:'own',public:true}]){
  const {infinity,byID,sockets,elapse}=harness();infinity.start('online',options);
  sockets[0].receive({type:'welcome',id:1,seed:0});sockets[0].close();
  assert.ok(byID('infiniteStatus').textContent.includes('Public Infinity'));
  assert.ok(!byID('infiniteStatus').textContent.includes('room Infinity'));
  if(options.code){elapse(450);assert.equal(byID('infiniteStatus').textContent,'Reconnecting to Public Infinity…');}
  else{byID('infiniteRetry').emit('click');assert.equal(byID('infiniteStatus').textContent,'Connecting to Public Infinity…');}
  infinity.close();
 }
});

test('Infinity reconnect discards unfinished flights and consumes the first effect history silently',()=>{
 const h=harness(undefined,true);h.infinity.start('online');const ws=h.sockets[0],packet={type:'state',tick:2,tanks:[{id:1,hp:1,x:42,y:42}],bullets:[],players:1,leaderboard:[]};
 ws.receive({type:'welcome',id:1,seed:0});ws.receive(packet);const w=h.state();
 const event={id:1,kind:'impact',owner:1,x:80,y:42,flight:{id:7,owner:1,colorIndex:0,kind:'cannon',radius:14,startTick:2,endTick:3,points:[{x:70,y:42,tick:2},{x:80,y:42,tick:3}]}};
 w.flights.accept([event],0);w.pendingImpacts=[event];ws.close();h.byID('infiniteRetry').emit('click');
 assert.equal(w.flights.items.size,0);assert.equal(w.pendingImpacts.length,0);
 const retry=h.sockets.at(-1);retry.receive({type:'welcome',id:1,seed:0});const sounds=h.sounds.length;
 retry.receive({...packet,tick:9,effects:[{id:2,kind:'laser',owner:1,x:42,y:42,points:[{x:42,y:42},{x:100,y:42}]}]});
 assert.equal(h.sounds.length,sounds);assert.equal(w.visualEffects.length,0);h.infinity.close();
});

test('explicit Infinity exits restore launcher focus while forced closure keeps the current focus', () => {
 const {infinity,byID} = harness();
 let focused = 0;
 const launcher = {getClientRects:() => [1],focus:() => focused++};
 const start = () => infinity.start('offline',{launcher:() => launcher});
 start();infinity.close();assert.equal(focused,0);
 start();byID('joinDialog').showModal();byID('infiniteExit').emit('click');assert.equal(focused,0);
 byID('joinDialog').close();
 start();launcher.disabled = true;byID('infiniteExit').emit('click');assert.equal(focused,0);
 start();launcher.disabled = false;byID('infiniteExit').emit('click');assert.equal(focused,1);
 start();byID('infiniteResultExit').emit('click');assert.equal(focused,2);
});

test('Infinity borrows the shared header and restores it after every exit path',()=>{
 const h=harness();
 for(const exit of [()=>h.infinity.close(),()=>h.byID('infiniteExit').emit('click'),()=>h.byID('infiniteArena').close()]){
  h.infinity.start('offline');
  assert.equal(h.headerParent,h.byID('infiniteHeader'));
  h.byID('pauseBtn').emit('click');
  assert.equal(h.byID('infinitePauseMenu').open,true);
  h.infinity.togglePause();
  assert.equal(h.byID('infinitePauseMenu').open,false);
  exit();
  assert.equal(h.headerParent,h.headerHome);
 }
 assert.deepEqual(h.headerMoves,['mount','restore','mount','restore','mount','restore']);
});

test('Infinity chat clears held controls and blocks keyboard and touch firing until closed',()=>{
 const {infinity,byID,sockets,advance,setChatOpen}=harness();
 infinity.start('online');
 const [socket]=sockets,arena=byID('infiniteArena');
 socket.receive({type:'welcome',id:1,seed:0});
 socket.receive({type:'state',tanks:[{id:1,hp:1,x:42,y:42,angle:0}],bullets:[],players:1,leaderboard:[]});
 arena.emit('keydown',{code:'KeyW'});
 assert.equal(socket.sent.at(-1).forward,true);
 setChatOpen(true);
 assert.equal(socket.sent.at(-1).forward,false);
 assert.equal(socket.sent.at(-1).paused,false);
 arena.emit('keydown',{code:'KeyW'});
 arena.emit('keydown',{code:'KeyQ'});
 byID('infiniteFire').emit('pointerdown',{button:0,pointerId:3,pointerType:'touch'});
 byID('infiniteStick').emit('pointerdown',{button:0,pointerId:4,pointerType:'touch'});
 advance(4);
 assert.equal(socket.sent.at(-1).forward,false);
 assert.equal(socket.sent.at(-1).fire,false);
 setChatOpen(false);
 arena.emit('keydown',{code:'KeyW'});
 assert.equal(socket.sent.at(-1).forward,true);
 assert.equal(socket.sent.at(-1).fire,false);
 infinity.close();
});

test('Infinity runs offline directly from a file and adds nearby bots to the standings', () => {
 const {infinity, byID, sockets, advance} = harness('file:///leqra/index.html');
 infinity.start('offline', {name: 'Explorer'});
 assert.equal(byID('infiniteArena').open, true);
 assert.equal(byID('infiniteKills').textContent, 'Explorer (P1): score: 0, rank: #1');
 assert.equal(byID('infiniteLeaderboardTitle').textContent, 'LEADERBOARD');
 assert.equal(byID('infiniteLeaderboard').children[0].children[0].textContent, 'Explorer (P1)');
 advance(90);
 assert.equal(byID('infiniteStatus').hidden,true);assert.equal(byID('infiniteOnlineCount').hidden,true);
 assert.match(byID('infiniteLeaderboard').children[1].children[0].textContent, /^Bot /);
 assert.equal(byID('infiniteLeaderboardTitle').textContent, 'LEADERBOARD');
 assert.equal(sockets.length, 0);
 infinity.close();
 assert.equal(byID('infiniteArena').open, false);
});

test('Infinity shows human count by the title and reserves footer status for connections and errors',()=>{
 const h=harness();h.infinity.start('online',{name:'Lead',localName:'Wing'});
 const status=h.byID('infiniteStatus'),count=h.byID('infiniteOnlineCount'),socket=h.sockets[0];
 assert.equal(status.hidden,false);assert.match(status.textContent,/Connecting/);assert.equal(count.hidden,false);assert.equal(count.textContent,'? online');
 socket.receive({type:'welcome',id:1,localId:2,seed:0});
 const packet={type:'state',players:7,tankCount:12,tanks:[{id:1,name:'Lead',x:42,y:42,hp:1},{id:2,name:'Wing',x:126,y:42,hp:0}],bullets:[],leaderboard:[]};
 socket.receive(packet);h.advance(4);
 assert.equal(count.textContent,'7 online');assert.equal(count.hidden,false);
 assert.equal(status.textContent,'');assert.equal(status.hidden,true);
 h.infinity.togglePause();h.advance(4);
 assert.equal(status.hidden,true,'respawn holds are not repeated beside the controls');
 socket.receive({...packet,players:3});
 assert.equal(count.textContent,'3 online');
 for(const players of [undefined,-1,'3']){socket.receive({...packet,players});assert.equal(count.hidden,false);assert.equal(count.textContent,'? online','missing or invalid counts must not fall back to local controller count');}
 socket.receive({...packet,players:0});assert.equal(count.textContent,'0 online','a retrieved zero remains a valid count');
 socket.receive({type:'error',message:'Arena unavailable.'});
 assert.equal(status.hidden,false);assert.match(status.textContent,/Arena unavailable/);assert.equal(count.hidden,false);assert.equal(count.textContent,'? online');
 h.infinity.close();h.infinity.start('offline');
 assert.equal(status.hidden,true);assert.equal(status.textContent,'');assert.equal(count.hidden,true);
 h.infinity.close();
});

test('Infinity sends its render cadence to the shared optional FPS readout', () => {
 const {infinity,byID,advance,combatPrefs}=harness(undefined,true);
 infinity.start('offline');
 advance(60);
 assert.equal(byID('infiniteFPSIndicator').textContent,'');
 combatPrefs.fps=true;
 advance(60);
 assert.equal(byID('infiniteFPSIndicator').textContent,'fps: 60');
 assert.match(byID('infiniteFPSIndicator').title,/JS update\/render work/);
 assert.equal(byID('fpsIndicator').textContent,'');
 infinity.close();
});

test('Infinity measures matching WebSocket pongs and clears stale, disconnected, and offline ping values',()=>{
 const h=harness(undefined,true);h.infinity.start('online',{code:'ROOM',token:'secret'});
 h.combatPrefs.fps=true;
 const socket=h.sockets[0],packet={type:'state',tick:1,tanks:[{id:1,hp:1,x:42,y:42,angle:0}],bullets:[],players:1,leaderboard:[]};
 socket.receive({type:'welcome',id:1,seed:0,generation:3});socket.receive(packet);
 const pings=socket.sent.filter(message=>message.type==='ping');
 assert.equal(pings.length,1,'first server state starts a ping immediately, before the first render frame');
 const ping=pings[0];assert.equal(ping.t,0);
 h.advance(2);
 assert.ok(Number.isNaN(h.frameSamples.at(-1).latency),'online ping remains unknown until a reply');
 h.elapse(47-(h.frameSamples.at(-1).now-ping.t));socket.receive({type:'pong',t:ping.t+1});socket.receive({type:'pong',t:String(ping.t)});
 assert.equal(h.state().latency,null,'unsolicited or malformed echoes cannot update latency');
 socket.receive({type:'pong',t:ping.t});assert.equal(h.state().latency,47);
 h.advance();assert.equal(h.frameSamples.at(-1).latency,47,'readout receives actual round-trip time');
 h.advance(45);assert.match(h.byID('infiniteFPSIndicator').textContent,/^fps: \d+, ping: 47 ms$/);
 socket.receive({...packet,tick:2});
 h.elapse(20);socket.receive({type:'pong',t:ping.t});assert.equal(h.state().latency,47,'duplicate replies cannot replace the accepted sample');
 h.advance(361);assert.equal(h.state().latency,null,'an unanswered connection cannot keep an old ping forever');
 assert.ok(Number.isNaN(h.frameSamples.at(-1).latency));
 socket.close();assert.equal(h.state().latency,null);assert.equal(h.state().pendingPing,null);
 h.elapse(450);const resumed=h.sockets.at(-1);assert.notEqual(resumed,socket);
 resumed.receive({type:'welcome',id:1,seed:0,generation:3,resumed:true});resumed.receive(packet);
 socket.receive({type:'pong',t:ping.t});assert.equal(h.state().latency,null,'the old socket cannot supply a new connection’s ping');
 h.infinity.close();h.infinity.start('offline',{roomRules:{}});h.advance(180);
 assert.equal(h.frameSamples.at(-1).latency,null,'offline play has no network ping');h.infinity.close();
});

test('Infinity samples ping immediately and then every second',()=>{
 const h=harness(undefined,true);h.infinity.start('online');const socket=h.sockets[0];
 socket.receive({type:'welcome',id:1,seed:0});
 socket.receive({type:'state',tick:1,tanks:[{id:1,hp:1,x:42,y:42,angle:0}],bullets:[],players:1,leaderboard:[]});
 const pings=()=>socket.sent.filter(message=>message.type==='ping');
 assert.equal(pings().length,1);assert.equal(pings()[0].t,0);
 h.elapse(20);socket.receive({type:'pong',t:0});h.advance(58);
 assert.equal(pings().length,1,'no polling before the one-second cadence');
 h.advance();assert.equal(pings().length,2);assert.ok(pings()[1].t>=1000&&pings()[1].t<1020);
 h.infinity.close();
});

test('Infinity scores retain labels and accessible pilot identities in desktop and touch layouts',()=>{
 for(const mobile of [false,true]){
  const h=harness(undefined,true);h.window.leqraInfinityArt.isTouchUI=()=>mobile;
  h.infinity.start('offline',{name:'Snow Fox',roomRules:{}});const scores=h.byID('infiniteKills');
  assert.equal(scores.children[0].children[0].textContent,'Snow Fox (P1)');
  assert.equal(scores.children[0].children[2].textContent,'score: 0, rank: #1');
  assert.equal(scores.children[0].attributes['aria-label'],'Snow Fox (P1): score: 0, rank: #1');h.infinity.close();
 }
});

test('offline Infinity routes two independent keyboard layouts to separate tanks', () => {
 const {infinity,byID,state,advance}=harness(undefined,true);
 infinity.start('offline',{localName:'Local wingmate'});state().tanks.forEach(tank=>{tank.invulnerable=0;tank.spawnProtected=false;});
 const world=state(),[pilot,local]=world.tanks,arena=byID('infiniteArena');
 world.nextBot=world.nextPickup=Infinity;
 Object.assign(pilot,{x:100,y:100,angle:0});
 Object.assign(local,{x:280,y:300,angle:0});
 for(const code of ['KeyW','ArrowDown','KeyQ','Space'])arena.emit('keydown',{code});
 advance();
 assert.ok(pilot.x>100 && local.x<280);
 assert.deepEqual(Array.from(world.bullets,b=>b.owner).sort(),[local.id,pilot.id].sort());
 assert.equal(byID('infiniteLocalLoadout').hidden,false);
 assert.equal(arena.dataset.split,'stacked');
 const hint=byID('infiniteControlsHint');
 assert.equal((hint.innerHTML.match(/class="control-player"/g)||[]).length,2);
 assert.match(hint.textContent,/Saved pilot \(P1\) Forward W Reverse S Left A Right D Fire Q \/ C Mouse Aim Mouse Fire/);
 assert.match(hint.textContent,/Local wingmate \(P2\) Forward ↑ Reverse ↓ Left ← Right → Fire SPACE \/ ENTER/);
 infinity.close();
});

test('solo Infinity omits the repeated controls identity while retaining the loadout, score and accessible callsign',()=>{
 const h=harness(undefined,true);
 h.infinity.start('offline',{name:'Solo pilot',roomRules:{infinityRandomBots:false}});h.advance(4);
 const hint=h.byID('infiniteControlsHint');
 assert.ok(!hint.innerHTML.includes('control-pilot'));
 assert.ok(!hint.textContent.includes('Solo pilot'));
 assert.match(hint.textContent,/Forward W \/ ↑/);
 assert.equal(h.loadouts[1].tank.name,'Solo pilot');
 assert.match(h.byID('infiniteKills').textContent,/Solo pilot \(P1\)/);
 assert.match(h.byID('infiniteCanvas').attributes['aria-label'],/Solo pilot \(P1\)/);
 h.infinity.close();h.infinity.start('offline',{name:'Solo pilot',localName:'Wingmate',roomRules:{infinityRandomBots:false}});
 assert.equal((hint.innerHTML.match(/class="control-pilot"/g)||[]).length,2);
 assert.match(hint.textContent,/Solo pilot \(P1\)/);assert.match(hint.textContent,/Wingmate \(P2\)/);
 h.infinity.close();
});

test('Infinity control groups preserve aliases through remapping and touch layouts',()=>{
 const h=harness(undefined,true);
 const bindings=[
  {forward:'KeyI',reverse:'KeyK',left:'KeyJ',right:'KeyL',fire:'KeyZ',fireAlt:'KeyX'},
  {forward:'ArrowUp',reverse:'ArrowDown',left:'ArrowLeft',right:'ArrowRight',fire:'Space',fireAlt:'Enter'},
 ];
 h.infinity.start('offline',{bindings:()=>bindings});
 assert.match(h.byID('infiniteControlsHint').textContent,/Forward I \/ ↑ Reverse K \/ ↓ Left J \/ ← Right L \/ → Fire Z \/ X \/ SPACE \/ ENTER Mouse Aim Mouse Fire/);
 h.infinity.close();
 h.window.leqraInfinityArt.isTouchUI=()=>true;
 h.infinity.start('offline',{localName:'Wingmate',bindings:()=>bindings});
 const hint=h.byID('infiniteControlsHint');
 assert.equal((hint.innerHTML.match(/class="control-player"/g)||[]).length,2);
 assert.match(hint.textContent,/Saved pilot \(P1\) Drag the stick to move and aim. Tap or hold Fire./);
 assert.match(hint.textContent,/Wingmate \(P2\) Forward ↑ Reverse ↓ Left ← Right → Fire SPACE \/ ENTER/);
 bindings[1].fireAlt='KeyV';
 h.byID('infiniteArena').emit('keydown',{code:'Escape'});
 h.byID('infiniteResumeBtn').emit('click');
 assert.match(hint.textContent,/Wingmate \(P2\) Forward ↑ Reverse ↓ Left ← Right → Fire SPACE \/ V/);
 h.infinity.close();
});

test('offline room Infinity spawns only its listed bots and preserves their team', () => {
 const {infinity,state,advance}=harness(undefined,true);
 const roomRules={teamMode:'teams',teamColors:[3,5],infinityTarget:0};
 infinity.start('offline',{roomRules});
 advance(400);
 assert.equal(state().tanks.length,1);
 infinity.close();
 infinity.start('offline',{roomRules,roster:[{id:3,kind:'bot',name:'ROOM BOT',team:2,difficulty:'hard'}]});
 const [pilot,bot]=state().tanks;
 pilot.x+=5000;
 advance(400);
 assert.equal(state().tanks.length,2);
 assert.equal(state().tanks[1],bot);
 assert.deepEqual([bot.name,bot.team,bot.colorIndex,bot.difficulty],['ROOM BOT',2,5,'hard']);
 infinity.close();
});

test('offline Infinity uses room paint for both local pilots and roster bots', () => {
 const {infinity,state,byID,window}=harness(undefined,true);
 infinity.start('offline',{primaryId:3,localId:5,localName:'Wingmate',roomRules:{teamMode:'ffa'},roster:[
  {id:3,kind:'human',colorIndex:4},
  {id:5,kind:'local',colorIndex:7},
  {id:2,kind:'bot',name:'DEFAULT BOT',colorIndex:-1},
 ]});
 assert.deepEqual(Array.from(state().tanks,t=>t.colorIndex),[4,7,2]);
 const rows = byID('infiniteLeaderboard').children, colors = window.leqraInfinityArt.colors;
 assert.equal(byID('infiniteLeaderboardTitle').textContent,'LEADERBOARD');
 assert.deepEqual(rows.map(row=>row.style.getPropertyValue('--tank-color')),[colors[4],colors[7],colors[2]]);
 assert.equal(rows[0].dataset.local,'p1');
 assert.equal(rows[0].style.getPropertyValue('--local-highlight'),colors[4]);
 assert.equal(rows[1].dataset.local,'p2');
 assert.equal(rows[1].style.getPropertyValue('--local-highlight'),colors[7]);
 assert.equal(rows[2].dataset.local,undefined);
 assert.deepEqual(byID('infiniteKills').children.map(node=>node.style.color),[colors[4],colors[7]]);
 infinity.close();
});

test('Infinity local tank labels use both callsigns and retain their own halos and selected paint',()=>{
 const {infinity,state,advance,labels,rings,window}=harness(undefined,true);
 infinity.start('offline',{name:'Lead',localName:'Wing',colorIndex:4,localColorIndex:7});
 assert.deepEqual(Array.from(state().tanks,t=>[t.name,t.colorIndex]),[['Lead',4],['Wing',7]]);
 Object.assign(state().tanks[0],{x:42,y:42});Object.assign(state().tanks[1],{x:126,y:42});
 rings.length=0;advance(1);
 const names=labels.filter(label=>label.x===0&&label.text.includes('(P')).map(label=>label.text);
 assert.ok(names.includes('Lead (P1)'));
 assert.ok(names.includes('Wing (P2)'));
 assert.ok(!names.includes('YOU'));
 const colors=window.leqraInfinityArt.colors;
 assert.deepEqual(rings.filter(ring=>ring.r===34).map(ring=>ring.color),[colors[4],colors[7],colors[4],colors[7]],'both local tanks use their own paint in both viewports');
 state().tanks.forEach(tank=>tank.invulnerable=0);rings.length=0;advance(1);
 assert.deepEqual(rings.filter(ring=>ring.r===25).map(ring=>ring.color),[colors[4],colors[7],colors[4],colors[7]],'persistent local halos retain the selected colors after spawn protection');
 infinity.close();
});

test('Infinity header toggles the actual scoreboard and restores its disclosure state after pause',()=>{
 const {infinity,byID,state,advance}=harness(undefined,true);
 infinity.start('offline',{name:'Lead',localName:'Wing',roomRules:{infinityRandomBots:false}});
 const button=byID('infiniteScoreboardBtn'),panel=byID('infiniteLeaderboardPanel');
 assert.equal(button.textContent,'LEADERBOARD');
 button.emit('click');assert.equal(panel.open,true);assert.equal(button.attributes['aria-expanded'],'true');
 infinity.togglePause();assert.equal(panel.parentElement,byID('gameSidebar'));
 infinity.togglePause();assert.equal(panel.parentElement,byID('infiniteStage'));assert.equal(panel.open,true);
 button.emit('click');assert.equal(panel.open,false);assert.equal(button.attributes['aria-expanded'],'false');
 infinity.togglePause();assert.equal(panel.open,true);assert.equal(button.attributes['aria-expanded'],'true');
 infinity.togglePause();assert.equal(panel.open,false);assert.equal(button.attributes['aria-expanded'],'false');
 panel.open=true;panel.emit('toggle');assert.equal(button.attributes['aria-expanded'],'true');
 state().tanks.push(...Array.from({length:10},(_,i)=>({id:i+100,name:'Bot '+i,bot:true,score:0,hp:0,respawn:10000})));
 advance(4);assert.equal(button.textContent,'LEADERBOARD');
 const counters=byID('infiniteKills').children;
 assert.deepEqual(counters.map(node=>node.children.map(child=>child.textContent)),[['Lead (P1)',': ','score: 0, rank: #1'],['Wing (P2)',': ','score: 0, rank: #2']]);
 assert.equal(counters[0].attributes['aria-label'],'Lead (P1): score: 0, rank: #1');
 infinity.close();
});

test('Infinity uses safe colored callsigns for both controls, scores, status, views and pause help',()=>{
 const {infinity,state,byID,advance,labels,window}=harness(undefined,true);
 const name='<LEAD & "A">'+'X'.repeat(20),localName='W'.repeat(32),colors=window.leqraInfinityArt.colors;
 infinity.start('offline',{name,localName,colorIndex:4,localColorIndex:7,roomRules:{infinityRandomBots:false}});
 const expected=[name+' (P1)',localName+' (P2)'];
 assert.deepEqual(Array.from(infinity.localPilots(),pilot=>[pilot.name,pilot.color]),[[name,colors[4]],[localName,colors[7]]]);
 const counters=byID('infiniteKills').children.filter(node=>node.className==='infinite-personal-score');
 assert.deepEqual(counters.map(node=>[node.children[0].textContent,node.style.color]),[[name+' (P1)',colors[4]],[localName+' (P2)',colors[7]]]);
 assert.deepEqual(counters.map(node=>node.children[2].className),['infinite-score-value','infinite-score-value']);
 assert.match(byID('infiniteControlsHint').innerHTML,/&lt;LEAD &amp; &quot;A&quot;&gt;/);
 assert.ok(!byID('infiniteControlsHint').innerHTML.includes('<LEAD'));
 for(const color of [colors[4],colors[7]])assert.ok(byID('infiniteControlsHint').innerHTML.includes('color:'+color));
 assert.match(byID('infiniteCanvas').attributes['aria-label'],/\(P1\).*\(P2\)/);
 assert.equal(byID('infiniteFire').attributes['aria-label'],'Fire for '+expected[0]);
 advance(4);
 assert.equal(byID('infiniteStatus').hidden,true);assert.equal(byID('infiniteStatus').textContent,'');
 for(const [index,color] of [[0,colors[4]],[1,colors[7]]])assert.ok(labels.some(label=>label.text===expected[index]&&label.color===color));
 infinity.togglePause();
 assert.deepEqual(Array.from(infinity.sidebarHelp().pilots,pilot=>[pilot.name,pilot.color]),[[name,colors[4]],[localName,colors[7]]]);
 assert.deepEqual(Array.from(state().tanks,tank=>tank.name),[name,localName],'presentation suffixes never change simulation callsigns');
 infinity.close();assert.deepEqual(Array.from(infinity.localPilots()),[]);
});

test('Infinity refreshes names and paint while paused without rebuilding unchanged identity rows',()=>{
 const {infinity,byID,sockets,advance,window}=harness();
 infinity.start('online',{name:'Lead',localName:'Wing'});
 const socket=sockets[0],colors=window.leqraInfinityArt.colors;
 socket.receive({type:'welcome',id:1,localId:2,seed:0});
 const tanks=[{id:1,name:'Lead',colorIndex:4,score:1,rank:1,hp:1,x:42,y:42,angle:0},
  {id:2,name:'Wing',colorIndex:7,score:0,rank:2,hp:1,x:210,y:42,angle:0}];
 const snapshot=()=>{socket.receive({type:'state',tanks,leaderboard:tanks,bullets:[],players:tanks.length});advance(4);};
 snapshot();infinity.togglePause();
 const oldRow=byID('infiniteLeaderboard').children[0],oldCounter=byID('infiniteKills').children[0];
 snapshot();assert.equal(byID('infiniteLeaderboard').children[0],oldRow);assert.equal(byID('infiniteKills').children[0],oldCounter);
 Object.assign(tanks[0],{name:'New lead',colorIndex:2});Object.assign(tanks[1],{name:'New wing',colorIndex:5});snapshot();
 assert.deepEqual(byID('infiniteLeaderboard').children.map(row=>[row.children[0].textContent,row.style['--tank-color']]),
  [['New lead (P1)',colors[2]],['New wing (P2)',colors[5]]]);
 assert.deepEqual(byID('infiniteLeaderboard').children.map(row=>row.style['--local-highlight']),[colors[2],colors[5]],'paused local highlights refresh with tank paint even without a score change');
 assert.match(byID('infiniteControlsHint').innerHTML,/New lead \(P1\)/);assert.ok(byID('infiniteControlsHint').innerHTML.includes('color:'+colors[5]));
 assert.deepEqual(Array.from(infinity.localPilots(),pilot=>pilot.name),['New lead','New wing']);
 socket.receive({type:'welcome',id:1,seed:0});tanks.pop();snapshot();
 assert.equal(byID('infiniteKills').textContent,'New lead (P1): score: 1, rank: #1');
 assert.equal(byID('infiniteLeaderboard').children[0].children[0].textContent,'New lead (P1)');
 assert.ok(!byID('infiniteControlsHint').textContent.includes('(P2)'));
 assert.equal(infinity.localPilots().length,1);
 infinity.close();
});

test('public Infinity sends selected paint for both pilots and preserves valid palette zero',()=>{
 const {infinity,sockets}=harness();
 infinity.start('online',{name:'Lead',localName:'Wing',colorIndex:0,localColorIndex:7});
 sockets[0].emit('open');
 assert.deepEqual([sockets[0].sent[0].name,sockets[0].sent[0].localName,
  sockets[0].sent[0].colorIndex,sockets[0].sent[0].localColorIndex],['Lead','Wing',0,7]);
 infinity.close();
 infinity.start('online',{colorIndex:-1,localColorIndex:99});
 sockets[1].emit('open');
 assert.equal(sockets[1].sent[0].colorIndex,undefined);
 assert.equal(sockets[1].sent[0].localColorIndex,undefined);
 infinity.close();
 infinity.start('online',{code:'PRIVATE',token:'secret',localName:'Wing',colorIndex:4,localColorIndex:7});
 sockets[2].emit('open');
 assert.equal(sockets[2].sent[0].colorIndex,undefined,'authenticated private roster owns P1 paint');
 assert.equal(sockets[2].sent[0].localColorIndex,undefined,'authenticated private roster owns P2 paint');
});

test('online Infinity score and rank colors track both tanks even when scores stay the same',()=>{
 const {infinity,byID,sockets,advance,window}=harness();
 infinity.start('online',{localName:'Wingmate'});
 const [socket]=sockets;
 socket.receive({type:'welcome',id:1,localId:2,seed:0});
 const tanks=[{id:1,colorIndex:4,score:7,rank:12,hp:1,x:42,y:42,angle:0},
  {id:2,colorIndex:7,score:4,rank:18,hp:1,x:126,y:42,angle:0}];
 const snapshot=()=>socket.receive({type:'state',tanks,bullets:[],players:2,leaderboard:[]});
 snapshot();advance(4);
 const read=()=>byID('infiniteKills').children.filter(node=>node.className==='infinite-personal-score');
 assert.deepEqual(read().map(node=>[node.textContent,node.style.color]),[
  ['Saved pilot (P1): score: 7, rank: #12',window.leqraInfinityArt.colors[4]],['Wingmate (P2): score: 4, rank: #18',window.leqraInfinityArt.colors[7]],
 ]);
 tanks[0].colorIndex=2;tanks[1].colorIndex=5;
 snapshot();advance(4);
 assert.deepEqual(read().map(node=>node.style.color),[window.leqraInfinityArt.colors[2],window.leqraInfinityArt.colors[5]]);
 infinity.close();
});

test('the offline Infinity leaderboard caps at ten and updates when tanks leave', () => {
 const {infinity,state,byID,advance}=harness(undefined,true);
 infinity.start('offline',{roomRules:{teamMode:'ffa'},roster:Array.from({length:11},(_,id)=>({id,kind:'bot',name:'Bot '+id}))});
 const world=state();
 world.nextPickup=world.nextBot=Infinity;
 assert.equal(byID('infiniteLeaderboard').children.length,10);
 assert.equal(byID('infiniteLeaderboardTitle').textContent,'LEADERBOARD');
 const tanks=world.tanks;
 world.tanks=tanks.slice(0,10);
 advance(4);
 assert.equal(byID('infiniteLeaderboard').children.length,10);
 assert.equal(byID('infiniteLeaderboardTitle').textContent,'LEADERBOARD');
 world.tanks=tanks.slice(0,11);
 advance(4);
 assert.equal(byID('infiniteLeaderboardTitle').textContent,'LEADERBOARD');
 world.tanks=world.tanks.slice(0,8);
 advance(4);
 assert.equal(byID('infiniteLeaderboard').children.length,8);
 assert.equal(byID('infiniteLeaderboardTitle').textContent,'LEADERBOARD');
 infinity.close();
});

test('the private Infinity leaderboard keeps its name as the arena count changes', () => {
 const {infinity,byID,sockets,advance}=harness();
 infinity.start('online',{code:'PRIVATE',token:'secret'});
 const [socket]=sockets;
 socket.receive({type:'welcome',id:1,seed:0});
 const leaders=Array.from({length:10},(_,i)=>({id:i+1,name:'Tank '+i,score:10-i,colorIndex:i%8}));
 const pilot={...leaders[0],hp:1,x:42,y:42,angle:0};
 for(const count of [11,10,11]) {
  socket.receive({type:'state',tanks:[pilot],bullets:[],players:1,tankCount:count,leaderboard:leaders});
  advance(4);
  assert.equal(byID('infiniteLeaderboard').children.length,10);
  assert.equal(byID('infiniteLeaderboardTitle').textContent,'LEADERBOARD');
 }
 infinity.close();
});

test('public Infinity keeps the top ten and appends local standings with their real ranks', () => {
 const {infinity,byID,sockets,advance}=harness();
 infinity.start('online',{localName:'Wingmate'});
 const [socket]=sockets;
 socket.receive({type:'welcome',id:1,localId:2,seed:0});
 const local=[1,2].map(id=>({id,name:'Local '+id,score:-1,rank:13-id,hp:1,x:42*id,y:42,angle:0}));
 const leaders=Array.from({length:10},(_,i)=>({id:i+100,name:'Leader '+i,score:100-i,colorIndex:i%8}));
 for(const count of [12,20,30]){
  socket.receive({type:'state',tanks:local,bullets:[],players:2,tankCount:count,leaderboard:[...leaders,...local]});
  advance(4);
  assert.equal(byID('infiniteLeaderboardTitle').textContent,'LEADERBOARD');
  const rows=byID('infiniteLeaderboard').children;
  assert.equal(rows.length,12);
  assert.ok(rows.slice(0,10).every(row=>row.dataset.local===undefined));
  assert.deepEqual(rows.slice(0,10).map(row=>row.children[0].textContent),leaders.map(tank=>tank.name));
  assert.deepEqual(rows.slice(10).map(row=>[row.value,row.dataset.local,row.children[0].textContent,row.children[1].textContent]),
   [[11,'p2','Local 2 (P2)',-1],[12,'p1','Local 1 (P1)',-1]]);
  assert.ok(rows.slice(10).every(row=>row.className==='off-board-local'));
 }
 local.forEach((tank,i)=>tank.rank=i+1);
 socket.receive({type:'state',tanks:local,bullets:[],players:2,tankCount:2,leaderboard:local});
 advance(4);
 assert.equal(byID('infiniteLeaderboardTitle').textContent,'LEADERBOARD');
 assert.deepEqual(byID('infiniteLeaderboard').children.map(row=>row.dataset.local),['p1','p2']);
 assert.ok(byID('infiniteLeaderboard').children.every(row=>row.className!=='off-board-local'));
 infinity.close();
});

test('online Infinity shows each local score and global rank outside the top ten',()=>{
 for(const room of [false,true]){
  const {infinity,byID,sockets,advance}=harness();
  infinity.start('online',{localName:'Wingmate',...(room?{code:'PRIVATE',token:'secret'}:{})});
  const [socket]=sockets;
  socket.receive({type:'welcome',id:1,localId:2,seed:0});
  const tanks=[1,2].map((id,i)=>({id,name:'Local '+id,score:-2+i,rank:12-i,hp:1,x:42*id,y:42,angle:0}));
  const leaders=Array.from({length:10},(_,i)=>({id:i+100,name:'Leader '+i,score:100-i}));
  socket.receive({type:'state',tanks,bullets:[],players:2,tankCount:12,leaderboard:leaders});
  advance(4);
  assert.equal(byID('infiniteKills').textContent,'Local 1 (P1): score: -2, rank: #12Local 2 (P2): score: -1, rank: #11');
  const board=byID('infiniteLeaderboard');
  assert.deepEqual(board.children.slice(10).map(row=>[row.dataset.local,row.value]),[['p2',11],['p1',12]]);
  infinity.togglePause();
  assert.equal(board.parentElement,byID('infiniteLeaderboardPanel'));
  assert.equal(byID('infiniteLeaderboardPanel').parentElement,byID('gameSidebar'));
  tanks[0].score=200;tanks[0].rank=1;tanks[1].rank=12;
  socket.receive({type:'state',tanks,bullets:[],players:2,tankCount:12,leaderboard:[tanks[0],...leaders.slice(0,9)]});
  advance(4);
  assert.equal(byID('infiniteKills').textContent,'Local 1 (P1): score: 200, rank: #1Local 2 (P2): score: -1, rank: #12');
  assert.equal(byID('infiniteLeaderboard').children[0].dataset.local,'p1');
  assert.equal(board.children.length,11);
  assert.deepEqual(board.children.slice(10).map(row=>[row.dataset.local,row.value]),[['p2',12]]);
  tanks[1].rank=17;
  socket.receive({type:'state',tanks,bullets:[],players:2,tankCount:20,leaderboard:[tanks[0],...leaders.slice(0,9)]});
  advance(4);
  assert.equal(board.children[10].value,17,'rank-only changes refresh the appended marker while paused');
  socket.receive({type:'welcome',id:1,seed:0});
  socket.receive({type:'state',tanks:[tanks[0]],bullets:[],players:1,tankCount:19,leaderboard:[tanks[0],...leaders.slice(0,9)]});
  advance(4);
  assert.equal(board.children.length,10,'a removed second controller leaves no stale personal row');
  infinity.close();
 }
 const {infinity,byID,sockets,advance}=harness();
 infinity.start('online');
 const [socket]=sockets;
 socket.receive({type:'welcome',id:1,seed:0});
 socket.receive({type:'state',tanks:[{id:1,score:7,rank:23,hp:1,x:42,y:42,angle:0}],bullets:[],players:1,leaderboard:[]});
 advance(4);
 assert.equal(byID('infiniteKills').textContent,'Saved pilot (P1): score: 7, rank: #23');
 assert.deepEqual(byID('infiniteLeaderboard').children.map(row=>[row.value,row.dataset.local]),[[23,'p1']]);
 infinity.close();
});

test('offline Infinity local ranks follow the full scoreboard including ties and deaths',()=>{
 const {infinity,state,byID,advance}=harness(undefined,true);
 infinity.start('offline',{localName:'Wingmate',roomRules:{teamMode:'ffa'},roster:
  Array.from({length:11},(_,id)=>({id,kind:'bot',name:'Bot '+id}))});
 const world=state(),[first,second,...bots]=world.tanks;
 world.nextPickup=world.nextBot=Infinity;
 first.invulnerable=second.invulnerable=1000;
 first.score=-2;second.score=-1;
 bots.forEach(bot=>{bot.score=10;bot.hp=0;bot.respawn=1000;});
 advance(4);
 assert.equal(byID('infiniteKills').textContent,'Saved pilot (P1): score: -2, rank: #13Wingmate (P2): score: -1, rank: #12');
 assert.deepEqual(byID('infiniteLeaderboard').children.slice(10).map(row=>[row.value,row.dataset.local]),[[12,'p2'],[13,'p1']]);
 first.score=second.score=10;
 advance(4);
 assert.equal(byID('infiniteKills').textContent,'Saved pilot (P1): score: 10, rank: #1Wingmate (P2): score: 10, rank: #2');
 assert.equal(byID('infiniteLeaderboard').children.length,10,'local leaders are not duplicated below the top ten');
 first.score=-1;first.hp=0;first.respawn=1000;
 advance(4);
 assert.equal(byID('infiniteKills').textContent,'Saved pilot (P1): score: -1, rank: #13Wingmate (P2): score: 10, rank: #1');
 assert.deepEqual(byID('infiniteLeaderboard').children.slice(10).map(row=>[row.value,row.dataset.local]),[[13,'p1']]);
 infinity.close();
});

test('opening offline Infinity pause refreshes local rows before the next HUD frame',()=>{
 const {infinity,state,byID}=harness(undefined,true);
 infinity.start('offline',{localName:'Twin',name:'Twin',roomRules:{teamMode:'ffa'},roster:
  Array.from({length:11},(_,id)=>({id,kind:'bot',name:'Bot '+id}))});
 const [first,second,...bots]=state().tanks;
 first.score=-2;second.score=-1;
 bots.forEach(bot=>bot.score=1);
 infinity.togglePause();
 const rows=byID('infiniteLeaderboard').children;
 assert.equal(byID('infiniteLeaderboardPanel').parentElement,byID('gameSidebar'));
 assert.equal(rows.length,12);
 assert.deepEqual(rows.slice(10).map(row=>[row.value,row.children[0].textContent]),[[12,'Twin (P2)'],[13,'Twin (P1)']]);
 infinity.close();
});

test('roaming room bots use the fixed difficulty or roll up to it',()=>{
 for (const [randomDifficulty,expected] of [[false,'hard'],[true,'normal']]) {
  const {infinity,state,advance}=harness(undefined,true);
  infinity.start('offline',{roomRules:{
   teamMode:'ffa',infinityRandomBots:true,infinityBotDifficulty:'hard',infinityRandomDifficulty:randomDifficulty
  }});
  advance(90);
  const bots=state().tanks.filter(tank=>tank.bot);
  assert.ok(bots.length>0 && bots.every(bot=>bot.ambient&&bot.difficulty===expected));
  infinity.close();
 }
});

test('offline Infinity ends distant roaming lives without awarding kills and starts fresh near humans',()=>{
 const {infinity,state,advance}=harness(undefined,true);
 infinity.start('offline');
 const world=state(),pilot=world.tanks[0];world.nextPickup=Infinity;pilot.invulnerable=10000;
 for(let i=0;i<24;i++){world.nextBot=0;advance();}
 const bots=world.tanks.filter(t=>t.ambient);assert.equal(bots.length,16);
 const recycled=bots.at(-1),serial=recycled.spawnSerial;recycled.score=7;
 pilot.x=pilot.y=10000;world.nextBot=Infinity;const score=pilot.score;advance();
 assert.equal(world.tanks.filter(t=>t.ambient).length,0);assert.equal(pilot.score,score);
 assert.equal(recycled.score,7,'retirement itself is not a death penalty');
 world.nextBot=0;advance();const reborn=world.tanks.find(t=>t.ambient);
 assert.equal(reborn,recycled);assert.equal(reborn.spawnSerial,serial+1);assert.equal(reborn.score,7,'retirement never fabricates a death or score penalty');
 assert.ok(Math.hypot(reborn.x-pilot.x,reborn.y-pilot.y)<7*84);
 const life=reborn.spawnSerial;Object.assign(pilot,{hp:0,respawn:100});world.nextBot=0;advance();
 assert.ok(world.tanks.includes(reborn));assert.equal(reborn.spawnSerial,life,'a nearby connected human still anchors the existing life while respawning');
 infinity.close();
});

test('offline Infinity pools surplus bots without losing identity, death timers, or late kill credit',()=>{
 const {infinity,state,advance}=harness(undefined,true);
 infinity.start('offline',{localName:'Wingmate'});
 const world=state(),[pilot,second]=world.tanks,secondSeat=world.local;
 world.nextPickup=Infinity;
 pilot.invulnerable=second.invulnerable=10000;
 for(let i=0;i<32;i++){world.nextBot=0;advance();}
 const bots=world.tanks.filter(tank=>tank.ambient),serial=world.lastBot;
 assert.ok(bots.length>24&&bots.length<=32);
 const pooledDead=bots[16];
 Object.assign(pooledDead,{hp:0,respawn:1,score:3});
 world.tanks=world.tanks.filter(tank=>tank!==second);
 world.controllers.pop();world.local=null;
 world.nextBot=Infinity;
 advance();
 assert.equal(world.tanks.filter(tank=>tank.ambient).length,16);
 assert.equal(world.botPool.length,bots.length-16);
 assert.ok(world.botPool.includes(pooledDead));
 const target=bots[0];
 Object.assign(target,{x:pilot.x+8*84,y:pilot.y,invulnerable:0});
 world.bullets.push({id:999,kind:'cannon',owner:pooledDead.id,ownerName:pooledDead.name,team:0,
  x:target.x-40,y:target.y,vx:1128,vy:0,r:14,life:1,age:.2,bounces:0,trail:[]});
 advance();
 assert.equal(target.hp,0);
 assert.equal(pooledDead.score,4);
 advance(65);
 world.local=secondSeat;world.controllers.push(secondSeat);world.tanks.splice(1,0,second);
 for(let i=0;i<20;i++){world.nextBot=0;advance();}
 assert.ok(world.tanks.filter(tank=>tank.ambient).length>=bots.length);
 assert.equal(world.botPool.length,0);
 assert.ok(world.lastBot<=serial+1);
 assert.ok(world.tanks.includes(pooledDead));
 assert.equal(pooledDead.hp,1,'pooled death time elapses before reactivation');
 assert.equal(pooledDead.score,4);
 assert.equal(pooledDead.name,'Bot 17');
 infinity.close();
});

test('offline room Infinity passes allied tanks and freezes on the first team score target', () => {
 const {infinity,byID,state,advance}=harness(undefined,true);
 infinity.start('offline',{
  primaryId:0,localId:1,localName:'Wingmate',
  roster:[{id:0,team:1},{id:1,team:1}],
  roomRules:{teamMode:'teams',teamNames:['Blue','Red'],teamColors:[3,5],infinityTarget:1}
 });state().tanks.forEach(tank=>{tank.invulnerable=0;tank.spawnProtected=false;});
 const world=state(),[pilot,local]=world.tanks,arena=byID('infiniteArena');
 world.nextBot=world.nextPickup=Infinity;
 Object.assign(pilot,{x:100,y:100,angle:0,power:'laser',charges:3,powerTime:4});
 Object.assign(local,{x:160,y:100,invulnerable:0});
 world.tanks.push({...local,id:'opponent',name:'Opponent',x:220,team:2,score:0});
 arena.emit('keydown',{code:'KeyQ'});
 advance();
 assert.equal(local.hp,1,'friendly fire is disabled');
 assert.equal(pilot.colorIndex,3);
 assert.deepEqual(Array.from(world.teamScores),[1,-1,0,0]);
 assert.equal(world.result.name,'Blue');
 advance(); // The beam/contact frame must precede the result overlay.
 assert.equal(byID('infiniteResultTitle').textContent,'Blue wins');
 assert.equal(byID('infiniteResult').open,true);
 const finish=world.time;
 advance(180);
 assert.equal(world.time,finish);
 byID('infiniteResultExit').emit('click');
 assert.equal(arena.open,false);
});

test('offline Infinity spawns every pickup and equips a collected grenade', () => {
 const {infinity, state, advance, window} = harness('file:///leqra/index.html');
 infinity.start('offline');
 const world = state(), tank = world.tanks[0], seen = new Set();
 world.nextBot = Infinity;
 for (let i = 0; i < 90; i++) {
  world.pickups.length = 0;
  world.nextPickup = 0;
  advance();
  for (const pickup of world.pickups) {
   seen.add(pickup.type);
   if (pickup.type !== 'grenade' || tank.power === 'grenade') continue;
   const {x, y} = tank;
   Object.assign(tank, {x: pickup.x, y: pickup.y});
   advance();
   assert.equal(tank.power, 'grenade');
   assert.equal(tank.charges, 3);
   Object.assign(tank, {x, y});
  }
 }
 assert.deepEqual([...seen].sort(), Object.keys(window.leqraInfinityArt.powers).sort());
});

test('offline Infinity awards the kill and keeps the death penalty after respawn', () => {
 const {infinity, byID, state, advance} = harness(undefined, true);
 infinity.start('offline');
 while(state().tanks.length===1)advance();
 state().nextBot=Infinity;
 const status = byID('infiniteStatus');
 for (let i = 0; i < 480 && state().tanks[0].hp; i++) advance();
 assert.equal(state().tanks[0].hp,0);assert.equal(status.hidden,true);
 advance(4);
 assert.equal(byID('infiniteKills').textContent, 'Saved pilot (P1): score: -1, rank: #2');
 const rows = byID('infiniteLeaderboard').children;
 assert.deepEqual(rows[0].children.map(cell => cell.textContent), ['Bot 1', 1]);
 assert.deepEqual(rows[1].children.map(cell => cell.textContent), ['Saved pilot (P1)', -1]);
 const notice = byID('infiniteDeathNotice1');
 assert.equal(notice.textContent,'Killed by Bot 1');
 assert.equal(notice.hidden,false);
 advance(64);
 assert.equal(status.hidden,true);assert.equal(state().tanks[0].hp,1);
 assert.equal(byID('infiniteKills').textContent, 'Saved pilot (P1): score: -1, rank: #2');
 assert.equal(notice.hidden,true);
});

test('offline Infinity respawns Player 2 in 60 ticks and clears just their death notice', () => {
 const {infinity,byID,state,advance}=harness(undefined,true);
 infinity.start('offline',{name:'PILOT ONE',localName:'PILOT TWO',roomRules:{}});state().tanks.forEach(tank=>{tank.invulnerable=0;tank.spawnProtected=false;});
 const [first,second]=state().tanks;
 Object.assign(first,{x:100,y:100,angle:0,power:'laser',powerTime:3,charges:1});
 Object.assign(second,{x:166,y:100,invulnerable:0});
 byID('infiniteArena').emit('keydown',{code:'KeyQ'});
 advance();
 byID('infiniteArena').emit('keyup',{code:'KeyQ'});
 assert.equal(second.respawn,1);
 const notice=byID('infiniteDeathNotice2');
 assert.equal(notice.textContent,'Killed by PILOT ONE');
 assert.equal(byID('infiniteDeathNotice1').hidden,true);
 advance(59);
 assert.equal(second.hp,0);
 assert.equal(notice.hidden,false);
 advance();
 assert.equal(second.hp,1);
 assert.equal(second.killedBy,'');
 assert.equal(second.killedByColor,'');
 advance(2);
 assert.equal(notice.hidden,true);
});

test('offline Infinity keeps an old grenade armed through a held-fire respawn', () => {
 const {infinity,byID,state,advance}=harness(undefined,true);
 infinity.start('offline',{roomRules:{}});state().tanks.forEach(tank=>{tank.invulnerable=0;tank.spawnProtected=false;});
 const world=state(),pilot=world.tanks[0],arena=byID('infiniteArena');
 Object.assign(pilot,{power:'grenade',powerTime:3,charges:1});
 arena.emit('keydown',{code:'KeyQ'});
 advance();
 const grenade=world.bullets.find(b=>b.kind==='grenade');
 assert.ok(grenade);
 Object.assign(pilot,{alive:false,hp:0,respawn:1});
 advance(60);
 assert.equal(pilot.hp,1);
 assert.ok(world.bullets.includes(grenade),'held Fire must not detonate the previous life’s grenade');
 arena.emit('keyup',{code:'KeyQ'});
 advance(60);
 arena.emit('keydown',{code:'KeyQ'});
 advance();
 assert.ok(!world.bullets.includes(grenade),'a fresh press can still detonate it');
});

test('Infinity prediction keeps render corrections on the authoritative side of a wall', () => {
 const {infinity,state}=harness();
 infinity.start('offline',{roomRules:{}});
 const world=state(),pilot=world.tanks[0];
 const wall=world.maze.wallsNear(-84,-84,168,168).find(w=>w.axis==='v');
 assert.ok(wall);
 const y=wall.y+wall.h/2;
 world.predictor.reset({...pilot,x:wall.x+31,y});
 world.predictor.reconcile({...pilot,x:wall.x-17,y});
 assert.equal(world.predictor.offset.x,48);
 assert.ok(world.predictor.visual(0).x<=wall.x-17);
});

test('simultaneous Infinity laser hits rotate priority between live actors', () => {
 for (const winner of [0, 1]) {
  const {infinity, byID, state, advance} = harness(undefined, true);
  infinity.start('offline');
  const world = state();
  world.nextPickup = world.nextBot = Infinity;
  world.time = (1 - winner) / 60;
  const pilot = world.tanks[0];
  Object.assign(pilot, {x: 42, y: 42, angle: 0, power: 'laser', powerTime: 3, charges: 1, invulnerable: 0});
  const bot = {...pilot, id: 'bot-1', name: 'Bot', bot: true, x: 126, angle: Math.PI};
  world.tanks.push(bot);
  byID('infiniteArena').emit('keydown', {code: 'KeyQ'});
  advance();
  assert.equal(world.tanks[winner].score, 1);
  assert.equal(world.tanks[1 - winner].score, -1);
  infinity.close();
 }
});

test('offline Infinity grenades steer at the full missile rate', () => {
 const {infinity, state, advance} = harness(undefined, true);
 infinity.start('offline');
 const world = state(), pilot = world.tanks[0];
 world.nextPickup = world.nextBot = Infinity;
 const target = {...pilot, id:'target', x:175, y:240, invulnerable:0};
 world.tanks.push(target);
 const shots = ['homing','grenade'].map((kind,id)=>({
  id, kind, owner:pilot.id, x:100, y:100, vx:kind==='grenade'?205:235, vy:0,
  r:kind==='grenade'?6:5, age:.2, life:1, bounces:0, seekDelay:0, target:null, trail:[]
 }));
 world.bullets.push(...shots);
 advance();
 const [missile, grenade] = shots;
 assert.equal(missile.target, target.id);
 assert.equal(grenade.target, target.id);
 const missileTurn = Math.atan2(missile.vy, missile.vx);
 assert.ok(Math.abs(missileTurn - 4.8/60) < 1e-12);
 assert.ok(Math.abs(Math.atan2(grenade.vy, grenade.vx) - missileTurn) < 1e-12);
 infinity.close();
});

test('offline Infinity Cannon passes through walls and expires after 5.3 seconds', () => {
 const flightTime = 5.3, speed = 1128, flightTicks = Math.round(flightTime*60);
 for (const offset of [-4, 4]) {
  const {infinity, byID, state, advance, loadouts} = harness(undefined,true);
  infinity.start('offline',{localName:'Wingmate'});state().tanks.forEach(tank=>{tank.invulnerable=0;tank.spawnProtected=false;});
  const world = state(), [pilot,target] = world.tanks;
  world.nextPickup = world.nextBot = Infinity;
  Object.assign(pilot, {x:100,y:100,angle:0,power:'cannon',powerTime:3,charges:3,ghostTime:2});
  world.maze.wallsNear = () => [{x:96,y:78,w:8,h:48},{x:151,y:78,w:8,h:48}];
  Object.assign(target,{x:100+32+flightTime*speed+17+14+offset,y:100,invulnerable:0});
  const arena = byID('infiniteArena');
  arena.emit('keydown',{code:'KeyQ'});
  advance();
  arena.emit('keyup',{code:'KeyQ'});
  advance(flightTicks-2);
  assert.equal(world.bullets.length,1);
  assert.equal(world.bullets[0].bounces,0);
  assert.equal(loadouts[1].projectiles.ammo,1);
  assert.equal(target.hp,1);
  advance();
  assert.equal(world.bullets.length,0);
  assert.equal(target.hp,offset<0?0:1);
  assert.equal(pilot.hp,1);
  advance(2);
  assert.equal(loadouts[1].projectiles.ammo,0);
  infinity.close();
 }
});

test('offline Infinity reflects every phased wall-facing weapon and preserves shot accounting',()=>{
 for(const phase of ['ghost','starman'])for(const power of ['', 'rapid','scatter','homing','grenade','laser','cannon'])for(const embedded of [false,true]){
  const label=[phase,power||'regular',embedded?'embedded':'face'].join('/'),h=harness(undefined,true);
  h.infinity.start('offline',{localName:'Target'});
  const world=h.state(),[pilot,target]=world.tanks,arena=h.byID('infiniteArena');world.nextPickup=world.nextBot=Infinity;
  for(const t of world.tanks)Object.assign(t,{invulnerable:0,spawnProtected:false});
  Object.assign(pilot,{x:embedded?105:100,y:100,angle:0});Object.assign(target,{x:141,y:100});
  world.maze.wallsNear=()=>[{x:101,y:80,w:8,h:50}];
  h.window.leqraInfinityArt.grantPower(pilot,phase,15,8);if(power)h.window.leqraInfinityArt.grantPower(pilot,power,15,8);
  const charges=pilot.charges,rounds=pilot.machineRounds;
  arena.emit('keydown',{code:'KeyQ'});h.advance();arena.emit('keyup',{code:'KeyQ'});
  if(phase==='starman'){assert.equal(pilot.charges,charges,label);assert.equal(pilot.machineRounds,rounds,label);}
  else if(power==='rapid')assert.equal(pilot.machineRounds,rounds-1,label);else if(power)assert.equal(pilot.charges,charges-1,label);
  if(power==='cannon'){assert.equal(target.hp,0,label+' penetrates');h.infinity.close();continue;}
  assert.equal(target.hp,1,label+' does not tunnel forward');
  if(power==='laser'){
   const beam=world.visualEffects.find(e=>e.kind==='laser');assert.ok(beam,label+' fires');assert.ok(beam.points[1].x<beam.points[0].x,label+' reflects');
  }else{
   assert.equal(world.lastBullet,power==='scatter'?3:1,label+' fires');assert.equal(world.bullets.length,power==='scatter'?3:1,label);
   for(const bullet of world.bullets){assert.equal(bullet.bounces,1,label);assert.ok(bullet.vx<0,label);}
  }
  h.infinity.close();
 }
});

test('online Infinity previews Cannon shots from inside a wall', () => {
 const {infinity, byID, state, sockets, sounds} = harness(undefined,true);
 infinity.start('online');
 const [socket] = sockets;
 socket.receive({type:'welcome',id:4,seed:0});
 socket.receive({type:'state',tick:2,tanks:[{id:4,x:100,y:100,angle:0,hp:1,power:'cannon',ghostTime:2}],bullets:[],players:1,leaderboard:[]});
 state().maze.wallsNear = () => [{x:96,y:78,w:8,h:48}];
 byID('infiniteArena').emit('keydown',{code:'KeyQ'});
 assert.ok(sounds.includes('shot:cannon'));
 assert.ok(socket.sent.at(-1).fire);
 infinity.close();
});

test('offline Infinity spawn protection blocks all weapons without spending ammunition',()=>{
 for(const power of ['', 'rapid', 'scatter', 'homing', 'grenade', 'laser', 'cannon']){
  const h=harness(undefined,true);h.infinity.start('offline',{roomRules:{}});
  const world=h.state(),tank=world.tanks[0],arena=h.byID('infiniteArena');
  world.nextPickup=world.nextBot=Infinity;
  if(power)h.window.leqraInfinityArt.grantPower(tank,power,15,8);
  const before={charges:tank.charges||0,rounds:tank.machineRounds||0};
  arena.emit('keydown',{code:'KeyQ'});h.advance(10);
  assert.equal(world.lastBullet,0,power);assert.equal(tank.cooldown,0,power);assert.equal(tank.recoil,0,power);
  assert.deepEqual({charges:tank.charges,rounds:tank.machineRounds},before,power);
  assert.ok(!h.sounds.some(sound=>sound.startsWith('shot:')),power);
  arena.emit('keyup',{code:'KeyQ'});tank.invulnerable=1/60;h.advance();
  assert.equal(tank.spawnProtected,false,power);
  arena.emit('keydown',{code:'KeyQ'});h.advance();
  assert.ok(power==='laser'?h.sounds.includes('shot:laser'):world.lastBullet>0,power+' fires after protection expires');
  h.infinity.close();
 }
});

test('online Infinity waits to preview fire until spawn protection ends, while shield-hit protection permits firing',()=>{
 const h=harness(undefined,true);h.infinity.start('online');const socket=h.sockets[0],arena=h.byID('infiniteArena');
 socket.receive({type:'welcome',id:4,seed:0});
 const packet={type:'state',tick:1,tanks:[{id:4,x:100,y:100,angle:0,hp:1,invulnerable:1,spawnProtected:true}],bullets:[],players:1,leaderboard:[]};
 socket.receive(packet);arena.emit('keydown',{code:'KeyQ'});
 assert.ok(!h.sounds.includes('shot:'));assert.equal(socket.sent.at(-1).fire,true,'authority receives held input');
 arena.emit('keyup',{code:'KeyQ'});packet.tick++;packet.tanks[0].spawnProtected=false;packet.tanks[0].invulnerable=.35;
 socket.receive(packet);arena.emit('keydown',{code:'KeyQ'});
 assert.ok(h.sounds.includes('shot:'));h.infinity.close();
});

test('Starman contact in offline Infinity bypasses shields and spawn protection while respecting walls and hit protection', () => {
 for(const [label,protection,wall,eliminated] of [
  ['shield',0,null,true],
  ['spawn protection',1,null,true],
  ['shield-hit protection',.35,null,false],
  ['wall between centers',0,{x:111,y:78,w:8,h:48},false],
  ['attacker inside wall',0,{x:98,y:78,w:8,h:48},false],
 ]) {
  const {infinity,state,advance,window,sounds}=harness(undefined,true);
  infinity.start('offline');
  const world=state(),pilot=world.tanks[0];
  world.nextPickup=world.nextBot=Infinity;
  if(wall)world.maze.wallsNear=()=>[wall];
  Object.assign(pilot,{x:100,y:100});
  window.leqraInfinityArt.grantPower(pilot,'starman',15,4);
  const target={...pilot,id:'target',x:134,starmanTime:0,ghostTime:0,invulnerable:protection,spawnProtected:label==='spawn protection',shield:10,shieldCharges:3};
  world.tanks.push(target);
  advance();
  assert.equal(target.hp,eliminated?0:1,label);
  assert.equal(target.score,eliminated?-1:0,label);
  assert.equal(pilot.score,eliminated?1:0,label);
  if(eliminated){assert.equal(target.respawn,1);assert.ok(!sounds.includes('blast'),'contact frame precedes hit audio');advance();assert.ok(sounds.includes('blast'));assert.ok(!sounds.includes('grenadeblast'));}
  infinity.close();
 }
});

test('the Infinity pause menu freezes the offline simulation until Resume', () => {
 const {infinity, byID, state, advance} = harness();
 infinity.start('offline');
 const world = state(), before = world.time;
 const arena = byID('infiniteArena'), pauseMenu = byID('infinitePauseMenu');
 arena.emit('keydown',{code:'Escape'});
 assert.ok(arena.open && pauseMenu.open);
 arena.emit('keydown',{code:'KeyQ'});
 advance(180);
 assert.equal(world.time,before);
 assert.equal(world.bullets.length,0);
 byID('infiniteResumeBtn').emit('click');
 advance();
 assert.ok(!pauseMenu.open && world.time>before);
 assert.equal(world.bullets.length,0);
 infinity.close();
});

test('Infinity pause owns the shared sidebar until resume, direct close, or exit', () => {
 const h=harness(),{infinity,byID}=h;
 infinity.start('offline',{localName:'Wingmate'});
 const arena=byID('infiniteArena'),pause=byID('infinitePauseMenu');
 arena.emit('keydown',{code:'Escape'});
 assert.equal(h.sidebarParent,byID('infinitePauseSidebar'));
 assert.equal(infinity.sidebarHelp().twoPilots,true);
 assert.match(infinity.sidebarHelp().instructions,/Respawn after 1 second/);
 byID('infiniteControlsBtn').emit('click');byID('introTourDialog').showModal();
 byID('infiniteResumeBtn').emit('click');
 assert.equal(h.sidebarParent,h.sidebarHome);
 assert.ok(!pause.open&&!byID('controlsDialog').open&&!byID('introTourDialog').open);
 assert.equal(infinity.sidebarHelp(),null);
 arena.emit('keydown',{code:'Escape'});pause.close();
 assert.equal(h.sidebarParent,h.sidebarHome);
 arena.emit('keydown',{code:'Escape'});infinity.close();
 assert.equal(h.sidebarParent,h.sidebarHome);
 assert.deepEqual(h.sidebarMoves,['mount','restore','mount','restore','mount','restore']);
});

test('Infinity pause borrows the actual scoreboard and restores its position and disclosure state', () => {
 const {infinity,byID}=harness();
 const panel=byID('infiniteLeaderboardPanel'),home=panel.parentElement,next=panel.nextSibling;
 infinity.start('offline');
 for(const open of [false,true]){
  panel.open=open;byID('pauseBtn').emit('click');
  assert.equal(panel.parentElement,byID('gameSidebar'));assert.equal(panel.open,true);
  panel.open=false;byID('infiniteResumeBtn').emit('click');
  assert.equal(panel.parentElement,home);assert.equal(panel.nextSibling,next);assert.equal(panel.open,open);
 }
 byID('pauseBtn').emit('click');infinity.close();
 assert.equal(panel.parentElement,home);assert.equal(panel.nextSibling,next);
});

test('online Infinity sends neutral pause heartbeats and clears the respawn hold on resume', () => {
 const {infinity, byID, sockets, state, advance} = harness();
 infinity.start('online');
 const [socket] = sockets, arena = byID('infiniteArena'), menu = byID('infinitePauseMenu');
 arena.emit('keydown',{code:'Escape'});
 socket.receive({type:'welcome',id:4,seed:0});
 socket.receive({type:'state',tanks:[{id:4,x:42,y:42,angle:0,hp:0}],bullets:[],players:1,leaderboard:[]});
 const inputs=()=>socket.sent.filter(message=>message.type==='input');
 assert.ok(inputs().at(-1).paused);
 const pauseSeq = inputs().at(-1).seq;
 byID('infiniteControlsBtn').emit('click');
 advance(40);
 assert.ok(menu.open && byID('controlsDialog').open);
 assert.equal(byID('infiniteStatus').hidden,true);
 assert.ok(inputs().length>2);
 assert.ok(inputs().every(input=>input.paused&&!input.forward&&!input.fire));
 byID('controlsDialog').close();
 menu.emit('cancel');
 assert.ok(!menu.open);
 assert.equal(socket.sent.at(-1).paused,false);
 assert.ok(socket.sent.at(-1).seq>pauseSeq);
 assert.ok(state().joined);
 infinity.close();
});

test('Starman keeps an equipped Infinity machine gun firing beyond its usual budget', () => {
 const {infinity, byID, state, advance, window} = harness(undefined,true);
 infinity.start('offline');
 const world = state(), tank = world.tanks[0], arena = byID('infiniteArena');
 world.nextPickup = world.nextBot = Infinity;
 Object.assign(tank,{angle:0,power:'rapid',powerTime:.3,machineRounds:1,charges:5,cooldown:2});
 window.leqraInfinityArt.grantPower(tank,'starman',15,4);
 arena.emit('keydown',{code:'KeyQ'});
 advance(200);
 assert.equal(world.lastBullet,200);
 assert.equal(tank.power,'rapid');
 assert.equal(tank.powerTime,.3);
 assert.equal(tank.machineRounds,1);
 assert.equal(tank.cooldown,0);
 assert.ok(world.bullets.length<=window.leqraNet.MACHINE_CAPACITY);
 arena.emit('keyup',{code:'KeyQ'});
 advance(41);
 assert.equal(tank.starmanTime,0);
 assert.ok(tank.powerTime<.3 && tank.powerTime>0);
 arena.emit('keydown',{code:'KeyQ'});
 advance();
 assert.equal(world.lastBullet,201);
 assert.equal(tank.power,'');
 infinity.close();
});

test('ordinary Infinity shells can fire immediately after Starman with boosted shells still in flight', () => {
 const {infinity, byID, state, advance, window} = harness(undefined,true);
 infinity.start('offline');
 const world = state(), tank = world.tanks[0];
 world.nextPickup = world.nextBot = Infinity;
 tank.angle = 0;
 window.leqraInfinityArt.grantPower(tank,'starman',15,4);
 byID('infiniteArena').emit('keydown',{code:'KeyQ'});
 advance(140);
 const cap = window.leqraNet.MACHINE_CAPACITY, oldest = world.bullets[0], recent = world.bullets.at(-1);
 assert.equal(world.bullets.length,cap);
 assert.ok(oldest.boosted && recent.boosted);
 tank.starmanTime = 1/60;
 for(let i=0;i<6;i++){tank.cooldown=0;advance();}
 assert.equal(tank.starmanTime,0);
 assert.equal(world.lastBullet,145);
 assert.equal(world.bullets.length,cap);
 assert.equal(world.bullets.filter(b=>!b.boosted).length,5);
 assert.ok(oldest.dead && world.bullets.includes(recent));
 infinity.close();
});

test('offline Infinity equips maze pickups and sounds a weapon before another frame arrives online', () => {
 const {infinity, byID, sockets, advance, state, sounds, loadouts} = harness(undefined, true);
 infinity.start('offline');
 const tank = state().tanks[0];
 state().pickups.push({x:tank.x,y:tank.y,type:'shield',life:30});
 advance();
 assert.equal(tank.shieldCharges, 1);
 assert.equal(loadouts[1].tank.shieldCharges, 1);
 assert.ok(sounds.includes('pickup'));
 infinity.close();
 infinity.start('online');
 const [socket] = sockets;
 socket.receive({type:'welcome',id:4,seed:0});
 socket.receive({type:'state',tanks:[{id:4,x:42,y:42,angle:0,hp:1}],bullets:[],players:1,leaderboard:[]});
 byID('infiniteArena').emit('keydown',{code:'KeyW'});
 advance();
 assert.ok(state().predictor.state.x > 42, 'local movement must precede any server acknowledgement');
 byID('infiniteArena').emit('keydown',{code:'KeyQ'});
 assert.equal(sounds.at(-1), 'shot:', 'local fire has immediate sound');
 assert.ok(socket.sent.at(-1).fire);
 socket.receive({type:'state',tanks:[{id:4,x:42,y:42,angle:0,hp:1}],bullets:[],players:1,leaderboard:[],
  effects:[{id:1,kind:'shot:',x:42,y:42,owner:4}]});
 assert.equal(sounds.filter(sound=>sound==='shot:').length, 1, 'authoritative copy must not echo the preview');
 infinity.close();
});

test('online Infinity reads per-pilot combat status even when their ordnance is off-screen', () => {
 const {infinity, sockets, advance, loadouts, sounds, byID} = harness(undefined, true);
 infinity.start('online',{code:'TEAM',token:'secret',localName:'Wingmate'});
 const [socket] = sockets;
 socket.receive({type:'welcome',id:4,localId:9,seed:0});
 socket.receive({type:'state',tanks:[
  {id:4,x:42,y:42,angle:0,hp:1,ammoUsed:5,grenades:1,grenadeLife:7,cooldown:.4,cooldownTotal:.8,locked:true},
  {id:9,x:210,y:210,angle:0,hp:1,power:'laser',charges:2,powerTime:7},
 ],bullets:[],players:2,leaderboard:[]});
 advance();
 assert.equal(loadouts[1].projectiles.ammo,5);
 assert.equal(loadouts[1].projectiles.grenades,1);
 assert.equal(loadouts[1].projectiles.locked,true);
 assert.ok(loadouts[1].projectiles.grenadeLife<7);
 assert.equal(loadouts[1].tank.cooldownTotal,.8);
 assert.ok(loadouts[1].tank.cooldown>0&&loadouts[1].tank.cooldown<.4);
 assert.equal(loadouts[2].projectiles.ammo,1);
 assert.equal(loadouts[2].projectiles.grenades,0);
 assert.equal(loadouts[2].projectiles.locked,false);
 advance(30);
 byID('infiniteArena').emit('keydown',{code:'KeyQ'});
 assert.ok(!sounds.includes('shot:'),'detonating the off-screen grenade cannot preview a regular shot');
 infinity.close();
});

test('online Infinity follows shared homing visual and audio preferences for both pilots', () => {
 const {infinity, sockets, advance, markers, sounds, combatPrefs} = harness(undefined,true);
 infinity.start('online',{localName:'Wingmate'});
 const [socket] = sockets;
 socket.receive({type:'welcome',id:4,localId:9,seed:0});
 const first={id:4,x:42,y:42,angle:0,hp:1},second={id:9,x:210,y:210,angle:0,hp:1};
 const grenade={id:1,kind:'grenade',owner:99,target:9,x:210,y:126,vx:0,vy:205,life:7};
 const snapshot=(locked1,locked2,bullets=[])=>socket.receive({type:'state',
  tanks:[{...first,locked:locked1},{...second,locked:locked2}],bullets,players:2,leaderboard:[]});
 snapshot(true,true,[grenade]);
 advance();
 assert.deepEqual(markers.map(marker=>marker.angle),[-Math.PI/2]);
 assert.equal(sounds.length,4,'the visible P2 lock and offscreen P1 lock both chirp');assert.deepEqual(sounds.slice(0,2),sounds.slice(2),'both local pilots use the same lock cue');assert.ok(sounds.every(sound=>sound.startsWith('tone:')));
 advance(4);
 assert.equal(sounds.length,4,'a sustained lock does not retrigger');
 snapshot(false,false);
 advance(100);
 markers.length=0;
 combatPrefs.visual=false;
 snapshot(false,true,[grenade]);
 advance(3);
 assert.equal(markers.length,0);
 assert.equal(sounds.length,6,'disabling visuals does not silence the next lock');
 snapshot(false,false);
 advance(100);
 combatPrefs.visual=true;
 combatPrefs.audio=false;
 snapshot(false,true,[grenade]);
 advance(3);
 assert.ok(markers.length>0);
 assert.equal(sounds.length,6,'disabling audio preserves the directional marker');
 infinity.close();
});

test('online Infinity displays only the killed local pilot’s authoritative notice', () => {
 const {infinity,sockets,byID,advance}=harness(undefined,true);
 infinity.start('online',{localName:'Wingmate'});
 const [socket]=sockets;
 socket.receive({type:'welcome',id:4,localId:9,seed:0});
 const first={id:4,x:42,y:42,angle:0,hp:1,spawnSerial:1};
 const second={id:9,x:210,y:210,angle:0,hp:1,spawnSerial:1};
 const publish = tanks => {
  socket.receive({type:'state',tanks,bullets:[],players:2,leaderboard:[]});
  advance(3);
 };
 const p1=byID('infiniteDeathNotice1'),p2=byID('infiniteDeathNotice2');
 publish([first,{...second,hp:0,respawnTime:1,killedBy:'Pilot <7>',killedByColor:'#ff83bd'}]);
 assert.equal(p1.hidden,true);
 assert.equal(p2.hidden,false);
 assert.equal(p2.textContent,'Killed by Pilot <7>');
 assert.equal(p2.children[1].style.color,'#ff83bd');
 publish([{...first,hp:0,respawnTime:1,killedBy:'Pilot 8',killedByColor:'#75f0cb'},{...second,spawnSerial:2}]);
 assert.equal(p1.textContent,'Killed by Pilot 8');
 assert.equal(p1.children[1].style.color,'#75f0cb');
 assert.equal(p2.hidden,true);
 infinity.close();
 assert.equal(p1.hidden,true);
});

test('a match-ending Infinity kill leaves time to read the victim’s notice',()=>{
 const {infinity,sockets,byID,advance}=harness(undefined,true);
 infinity.start('online');
 const [socket]=sockets;
 socket.receive({type:'welcome',id:4,seed:0});
 socket.receive({type:'state',players:2,bullets:[],leaderboard:[],
  tanks:[{id:4,x:42,y:42,angle:0,hp:0,spawnSerial:1,killedBy:'Winner'}],
  result:{id:8,name:'Winner',score:3}});
 advance();
 const result=byID('infiniteResult');
 assert.equal(result.open,false);
 assert.equal(byID('infiniteDeathNotice1').textContent,'Killed by Winner');
 advance(91);
 assert.equal(result.open,true);
 assert.equal(byID('infiniteResultTitle').textContent,'Winner wins');
});

test('offline Infinity draws a warning and chirps when a missile locks Player 2', () => {
 const {infinity, advance, state, loadouts, markers, sounds} = harness(undefined,true);
 infinity.start('offline',{localName:'Wingmate'});
 const world=state(),[,second]=world.tanks;
 world.nextBot=world.nextPickup=Infinity;
 second.invulnerable=0;
 world.bullets.push({id:1,owner:'enemy',kind:'homing',x:second.x+100,y:second.y,vx:-235,vy:0,
  r:5,age:.2,life:4,bounces:0,seekDelay:0,target:null,trail:[]});
 advance(3);
 assert.equal(loadouts[1].projectiles.locked,false);
 assert.equal(loadouts[2].projectiles.locked,true);
 assert.ok(markers.length>0&&markers.every(marker=>Math.abs(marker.angle)<1e-6));
 assert.equal(sounds.length,2);assert.ok(sounds.every(sound=>sound.startsWith('tone:')));
 infinity.close();
});

test('Infinity ignores round endings and separates tank destruction from grenade blasts', () => {
 const {infinity, sockets, state, sounds, elapse} = harness();
 infinity.start('online');
 const [socket] = sockets;
 socket.receive({type:'welcome',id:4,seed:0});
 const update = effects => socket.receive({
  type:'state',tanks:[{id:4,x:42,y:42,angle:0,hp:1}],bullets:[],players:1,leaderboard:[],
  effects:effects.map((kind,index)=>({id:index+1,kind,x:42,y:42,owner:4}))
 });
 update(['roundEnd','matchEnd']);
 assert.deepEqual(sounds,[]);
 assert.equal(state().visualEffects.length,0);
 update(['roundEnd','matchEnd','hit','blast']);
 assert.deepEqual(sounds,['blast','grenadeblast']);
 assert.equal(state().visualEffects.map(effect=>effect.kind).join(),'hit,blast');
 elapse(500);update(['roundEnd','matchEnd','hit','blast','hit']);
 assert.deepEqual(sounds,['blast','grenadeblast','blast'],'late deaths remain the soft tank cue and do not repeat the grenade blast');
 infinity.close();
});

test('private Infinity sends room credentials, honors keyboard remaps, and uses the authoritative leaderboard', () => {
 const {infinity, byID, sockets, advance} = harness();
 infinity.start('online', {
  name: 'Explorer', code: 'forest', token: 'test-token',
  bindings: {forward: 'KeyI', reverse: 'KeyK', left: 'KeyJ', right: 'KeyL', fire: 'KeyZ', fireAlt: 'KeyX'},
 });
 const [socket] = sockets;
 const arena = byID('infiniteArena');
 assert.equal(socket.url, 'wss://example.test/ws/infinite');
 socket.emit('open');
 assert.deepEqual(socket.sent[0], {type: 'join', version: '9.1.0', name: 'Explorer', code: 'forest', token: 'test-token', updateNames:true});
 socket.receive({type: 'welcome', id: 7, seed: 0});
 advance();
 assert.equal(socket.sent.length, 1);
 const pilot = {id: 7, name: 'Explorer', score: -1, hp: 0, x: 42, y: 42, angle: 0, colorIndex:0};
 socket.receive({
  type: 'state', tanks: [pilot], bullets: [], players: 2,
  leaderboard: [{id: 9, name: '<Distant pilot>', score: 5, colorIndex:1}, pilot],
 });
 advance();
 assert.equal(byID('infiniteKills').textContent, 'Explorer (P1): score: -1, rank: #0');
 assert.equal(byID('infiniteStatus').hidden,true);
 assert.equal(byID('infiniteLeaderboard').children[0].children[0].textContent, '<Distant pilot>');
 assert.equal(byID('infiniteLeaderboardTitle').textContent,'LEADERBOARD');
 const distantRow=byID('infiniteLeaderboard').children[0];
 assert.equal(distantRow.style.getPropertyValue('--tank-color'),'#ff758f');
 assert.equal(distantRow.dataset.local,undefined);
 assert.equal(byID('infiniteLeaderboard').children[1].dataset.local,'p1');
 socket.receive({type:'state',tanks:[pilot],bullets:[],players:1,
  leaderboard:[{id:9,name:'<Distant pilot>',score:5,colorIndex:4},pilot]});
 advance(4);
 assert.equal(byID('infiniteLeaderboardTitle').textContent,'LEADERBOARD');
 assert.equal(byID('infiniteLeaderboard').children[0].style.getPropertyValue('--tank-color'),'#ffc46b');
 arena.emit('keydown', {code: 'KeyI'});
 arena.emit('keydown', {code: 'KeyZ'});
 assert.equal(socket.sent.at(-1).forward, true);
 assert.equal(socket.sent.at(-1).fire, true);
 arena.emit('keyup', {code: 'KeyZ'});
 assert.equal(socket.sent.at(-1).fire, false);
 infinity.close();
 assert.equal(socket.sent.at(-2).forward, false);
 assert.deepEqual(socket.sent.at(-1),{type:'leave'});
 assert.equal(socket.readyState, 3);
});

test('private Infinity automatically resumes both paused seats and ignores old inputs and effects', () => {
 const {infinity,byID,sockets,state,advance,elapse,sounds}=harness(undefined,true);
 infinity.start('online',{code:'forest',token:'secret',localName:'Wingmate'});
 const [first]=sockets, arena=byID('infiniteArena');
 const welcome={type:'welcome',id:4,localId:9,seed:0,generation:3};
 const pilots=[
  {id:4,name:'First',score:4,x:42,y:42,angle:0,hp:1},
  {id:9,name:'Second',score:-2,x:210,y:210,angle:0,hp:0},
 ];
 const snapshot={type:'state',tanks:pilots,players:2,leaderboard:pilots,bullets:[]};
 first.emit('open');
 first.receive(welcome);
 first.receive(snapshot);
 advance();
 arena.emit('keydown',{code:'KeyW'});
 arena.emit('keydown',{code:'Escape'});
 first.close();
 assert.equal(arena.open,true);
 assert.equal(byID('infinitePauseMenu').open,true);
 assert.equal(byID('infiniteKills').textContent,'First (P1): score: 4, rank: #0Second (P2): score: -2, rank: #0');
 assert.match(byID('infiniteStatus').textContent,/Reconnecting to room Infinity/);
 assert.equal(byID('infiniteRetry').hidden,true);
 elapse(450);
 const [,duplicate]=sockets;
 duplicate.emit('open');
 assert.deepEqual(duplicate.sent[0],{
  type:'join',version:'9.1.0',name:'Saved pilot',code:'forest',token:'secret',resume:true,generation:3,
 });
 duplicate.receive({type:'error',code:'session_active',message:'Duplicate connection'});
 elapse(900);
 const resumed=sockets.at(-1);
 assert.notEqual(resumed,duplicate);
 resumed.emit('open');
 resumed.receive({...welcome,resumed:true});
 resumed.receive({...snapshot,effects:[{id:1,kind:'hit',owner:4,x:210,y:210}]});
 assert.deepEqual([state().id,state().local.id],[4,9]);
 assert.deepEqual(resumed.sent.filter(input=>input.type==='input').map(input=>[!!input.local,input.seq,input.paused,input.forward,input.fire]),
  [[false,1,true,false,false],[true,1,true,false,false]]);
 assert.deepEqual(sounds,[]);
 byID('infiniteResumeBtn').emit('click');
 assert.deepEqual(resumed.sent.slice(-2).map(input=>[!!input.local,input.seq,input.paused]),
  [[false,2,false],[true,2,false]]);
 advance(2);
 assert.equal(byID('infiniteKills').textContent,'First (P1): score: 4, rank: #0Second (P2): score: -2, rank: #0');
});

test('private Infinity recovers a stalled socket but stops when its room ends', () => {
 const {infinity,byID,sockets,elapse}=harness();
 infinity.start('online',{code:'forest',token:'secret'});
 sockets[0].receive({type:'welcome',id:4,seed:0,generation:3});
 sockets[0].receive({type:'state',tanks:[],players:1,leaderboard:[],bullets:[]});
 elapse(2500);
 assert.equal(sockets[0].readyState,3);
 assert.match(byID('infiniteStatus').textContent,/Reconnecting to room Infinity/);
 infinity.syncRoom('forest','secret',false);
 elapse(6000);
 assert.equal(sockets.length,1);
 assert.equal(byID('infiniteArena').open,false);
 assert.equal(infinity.savedRoomGeneration('secret'),undefined);
});

test('private Infinity reload can only resume a saved generation and stops on expiry', () => {
 const storage=new Map();
 const first=harness(undefined,true,storage);
 first.infinity.start('online',{code:'forest',token:'secret'});
 first.sockets[0].receive({type:'welcome',id:4,seed:0,generation:3});
 const reloaded=harness(undefined,true,storage);
 const resumeGeneration=reloaded.infinity.savedRoomGeneration('secret');
 assert.equal(resumeGeneration,3);
 assert.equal(reloaded.infinity.savedRoomGeneration('secret'),undefined);
 reloaded.infinity.start('online',{code:'forest',token:'secret',resumeGeneration});
 const [socket]=reloaded.sockets;
 socket.emit('open');
 assert.equal(socket.sent[0].generation,3);
 assert.equal(socket.sent[0].resume,true);
 socket.receive({type:'error',code:'resume_expired',message:'Infinity seat expired.'});
 reloaded.elapse(18000);
 assert.equal(reloaded.sockets.length,1);
 assert.equal(reloaded.byID('infiniteRetry').hidden,false);
 assert.equal(reloaded.infinity.savedRoomGeneration('secret'),undefined);
});

test('online room Infinity routes Player 2 separately and displays the authoritative team result', () => {
 const h=harness(undefined,true),{infinity,byID,sockets,state,advance}=h;
 infinity.start('online',{code:'TEAM',token:'secret',localName:'Local wingmate'});
 const [socket]=sockets,arena=byID('infiniteArena');
 socket.emit('open');
 assert.equal(socket.sent[0].localName,undefined,'private Player 2 comes from the authenticated room roster');
 socket.receive({type:'welcome',id:4,localId:9,seed:0});
 const packet={
  type:'state',tanks:[{id:4,x:42,y:42,angle:0,hp:1,team:1},{id:9,x:210,y:210,angle:0,hp:1,team:1}],
  bullets:[],players:2,leaderboard:[],rules:{infinityTarget:3,teamMode:'teams',teamNames:['Blue','Red']},teamScores:[0,0,0,0]
 };
 socket.receive(packet);
 arena.emit('keydown',{code:'KeyW'});
 arena.emit('keydown',{code:'ArrowDown'});
 arena.emit('keydown',{code:'Space'});
 assert.ok(socket.sent.some(input=>!input.local&&input.forward&&!input.reverse&&!input.fire));
 assert.ok(socket.sent.some(input=>input.local&&input.reverse&&input.fire&&!input.forward));
 advance();
 assert.ok(state().predictor.state.x>42 && state().local.predictor.state.x<210);
 arena.emit('keydown',{code:'Escape'});
 assert.deepEqual(socket.sent.slice(-2).map(input=>[!!input.local,input.paused,input.fire]),[[false,true,false],[true,true,false]]);
 socket.receive({...packet,teamScores:[3,-3,0,0],result:{name:'Blue',team:1,score:3}});
 advance();
 assert.equal(byID('infinitePauseMenu').open,false);
 assert.equal(h.sidebarParent,h.sidebarHome);
 assert.equal(byID('infiniteLeaderboardPanel').parentElement,byID('infiniteStage'));
 assert.equal(byID('infiniteResultTitle').textContent,'Blue wins');
 assert.equal(byID('infiniteResult').open,true);
 const sent=socket.sent.length;
 advance(120);
 assert.equal(socket.sent.length,sent);
 infinity.close();
});

test('failed public Infinity connection points to offline mode', () => {
 const {infinity, byID, sockets} = harness();
 infinity.start('online');
 sockets[0].receive({type: 'error', message: 'Arena is full.'});
 assert.match(byID('infiniteStatus').textContent, /Arena is full.*Room settings.*offline/);
 assert.equal(sockets[0].readyState, 3);
});

test('Infinity steers and fires together without capture and clears both controls on page hide', () => {
 const {infinity, byID, sockets, window} = harness(undefined, true);
 infinity.start('online');
 const [socket] = sockets;
 socket.receive({type:'welcome',id:4,seed:0});
 socket.receive({type:'state',tanks:[{id:4,x:42,y:42,angle:0,hp:1}],bullets:[],players:1,leaderboard:[]});
 const stick=byID('infiniteStick'),base=byID('infiniteStickBase'),fire=byID('infiniteFire');
 stick.setPointerCapture=fire.setPointerCapture=()=>{throw new Error('Pointer capture unavailable');};
 let measurements=0;
 base.getBoundingClientRect=()=>{measurements++;return {left:20,top:30,width:96,height:96};};
 stick.emit('pointerdown',{button:0,pointerId:1,pointerType:'touch',clientX:68,clientY:78});
 assert.equal(socket.sent.at(-1).stickX,0);
 assert.equal(socket.sent.at(-1).stickY,0);
 window.emit('pointermove',{pointerId:1,clientX:68,clientY:150});
 fire.emit('pointerdown',{button:0,pointerId:2});
 assert.equal(measurements,1);
 assert.equal(fire.classes.has('held'),true);
 assert.equal(socket.sent.at(-1).stickY,1);
 assert.equal(socket.sent.at(-1).touchAim,true);
 assert.equal(socket.sent.at(-1).fire,true);
 window.emit('pointercancel',{pointerId:2});
 assert.equal(socket.sent.at(-1).stickY,1);
 assert.equal(socket.sent.at(-1).fire,false);
 window.emit('pagehide');
 assert.equal(socket.sent.at(-1).stickY,0);
 assert.equal(socket.sent.at(-1).fire,false);
 assert.equal(socket.sent.at(-1).touchAim,undefined);
 stick.emit('pointerdown',{button:0,pointerId:3,pointerType:'mouse',clientX:68,clientY:150});
 assert.equal(measurements,2);
 assert.equal(socket.sent.at(-1).stickY,1);
 assert.equal(socket.sent.at(-1).touchAim,undefined);
});

test('a tap completed while Infinity connects does not fire after joining', () => {
 const {infinity, byID, sockets, window, advance} = harness();
 infinity.start('online');
 byID('infiniteFire').emit('pointerdown',{button:0,pointerId:2});
 window.emit('pointerup',{pointerId:2});
 const [socket] = sockets;
 socket.receive({type:'welcome',id:4,seed:0});
 socket.receive({type:'state',tanks:[{id:4,x:42,y:42,angle:0,hp:1}],bullets:[],players:1,leaderboard:[]});
 advance();
 assert.equal(socket.sent.at(-1).type,'input');
 assert.equal(socket.sent.at(-1).fire,false);
});

test('the shared M sound shortcut works inside the Infinity dialog', () => {
 const {infinity, byID, sounds} = harness();
 infinity.start('offline');
 const arena=byID('infiniteArena');
 arena.emit('keydown',{code:'KeyM'});
 arena.emit('keydown',{code:'KeyM',repeat:true});
 arena.emit('keydown',{code:'KeyM',metaKey:true});
 assert.deepEqual(sounds,['mute']);
});

test('Infinity shares fullscreen and protects native keyboard activation and text entry', () => {
 const {infinity, byID, sounds, state, advance} = harness(undefined,true);
 const bindings = {fire:'NumpadEnter'};
 infinity.start('offline',{bindings,roomRules:{}});state().tanks.forEach(tank=>{tank.invulnerable=0;tank.spawnProtected=false;});
 const arena = byID('infiniteArena'), pauseMenu = byID('infinitePauseMenu');
 arena.emit('keydown',{code:'KeyF'});
 arena.emit('keydown',{code:'KeyF',repeat:true});
 arena.emit('keydown',{code:'KeyF',target:{tagName:'INPUT',type:'text'}});
 arena.emit('keydown',{code:'KeyM',isComposing:true});
 arena.emit('keydown',{code:'Escape',defaultPrevented:true});
 arena.emit('keydown',{code:'NumpadEnter',target:{tagName:'SUMMARY'}});
 advance();
 assert.deepEqual(sounds,['fullscreen']);
 assert.equal(pauseMenu.open,false);
 assert.equal(state().bullets.length,0);
 assert.match(byID('infiniteControlsHint').textContent,/Fire NUM ENTER/);
 arena.emit('keydown',{code:'NumpadEnter',target:{tagName:'CANVAS'}});
 advance();
 assert.equal(state().bullets.length,1);
});


test('split-screen offline Infinity budgets pickups per local pilot', () => {
 const h = harness();
 h.infinity.start('offline', {name:'P1',localName:'P2',roomRules:{teamMode:'ffa',infinityRandomBots:false}});
 const world = h.state(), [first,second] = world.tanks;
 Object.assign(first,{x:42,y:42});
 Object.assign(second,{x:1722,y:42});
 // Old pickups remain within the retention radius but are not near either pilot.
 world.pickups = Array.from({length:6},(_,i)=>({x:546+i%3*168,y:-126+Math.floor(i/3)*336,life:30,type:'shield'}));
 world.pickupPilot = 1;
 world.nextPickup = 0;
 h.advance(2);
 assert.equal(world.pickups.filter(p=>Math.hypot(p.x-second.x,p.y-second.y)<5*84).length,3);
 assert.equal(world.pickups.length,9);
});


test('public Infinity parties track all room pilots beyond the top ten without duplicate or team rows',()=>{
 const {infinity,sockets,state,byID,advance}=harness();
 infinity.start('online',{code:'ROOM',token:'secret',public:true,localName:'Wing',roomRules:{teamMode:'teams',infinityTarget:9}});
 assert.equal(state().rules,null,'source-room team and target rules never carry into public Infinity');
 const socket=sockets[0];socket.emit('open');
 assert.equal(socket.sent[0].code,'ROOM');assert.equal(socket.sent[0].token,'secret');
 assert.equal(socket.sent[0].localName,undefined,'the authenticated room roster controls local seats');
 const party=[{id:1,name:'Lead',score:30,rank:12,colorIndex:4},{id:2,name:'Wing',score:20,rank:20,colorIndex:7},
  {id:3,name:'Distant',score:10,rank:30,colorIndex:6},{id:4,name:'Already top',score:96,rank:5,colorIndex:2},
  {id:5,name:'Farther',score:2,rank:40,colorIndex:3}];
 socket.receive({type:'welcome',id:1,localId:2,seed:0,party});
 const leaders=Array.from({length:10},(_,i)=>({id:i===4?4:100+i,name:i===4?'Already top':'Leader '+i,score:100-i,colorIndex:i===4?2:i%8}));
 const packet={type:'state',tanks:party.slice(0,2).map(t=>({...t,hp:1,x:t.id*84,y:42,angle:0})),bullets:[],leaderboard:leaders,party,tankCount:40,
  rules:{teamMode:'teams',infinityTarget:9},teamScores:[5,4]};
 socket.receive(packet);advance(2);
 const rows=byID('infiniteLeaderboard').children;
 assert.equal(byID('infiniteLeaderboardTitle').textContent,'LEADERBOARD');
 assert.equal(byID('infiniteTeamScores').hidden,true);
 assert.deepEqual(rows.map(row=>row.value),[1,2,3,4,5,6,7,8,9,10,12,20,30,40]);
 assert.equal(rows.filter(row=>row.textContent.includes('Already top')).length,1);
 assert.equal(rows[4].dataset.party,'true');
 assert.equal(rows[10].dataset.local,'p1');assert.equal(rows[11].dataset.local,'p2');
 assert.equal(rows[12].textContent,'Distant (room)10');
 assert.equal(rows[12].style.getPropertyValue('--tank-color'),'#75f0cb');
 assert.equal(state().rules,null);
 const changed=party.map(t=>t.id===3?{...t,score:22,rank:18,colorIndex:5}:t);
 socket.receive({...packet,party:changed});advance(3);
 const distant=byID('infiniteLeaderboard').children.find(row=>row.textContent.includes('Distant'));
 assert.equal(distant.value,18);assert.equal(distant.style.getPropertyValue('--tank-color'),'#ff83bd');
 assert.ok(distant.textContent.endsWith('22'));
 socket.receive({...packet,party:[]});advance(3);
 assert.equal(byID('infiniteLeaderboard').children.length,12,'departed remote party rows disappear while both local counters stay');
});


test('public entry runs source-room cleanup once only after a valid first state',()=>{
 const h=harness();let joined=0;
 h.infinity.start('online',{name:'P1',onJoined(){joined++;}});
 const socket=h.sockets[0];socket.emit('open');
 assert.equal(joined,0);socket.receive({type:'welcome',id:1,seed:0});assert.equal(joined,0);
 const packet={type:'state',tanks:[{id:1,hp:1,x:42,y:42,angle:0}],bullets:[],leaderboard:[]};
 socket.receive(packet);assert.equal(joined,1);socket.receive(packet);assert.equal(joined,1);
});

test('offline Infinity callsign changes preserve both tanks, scores and equipment while refreshing pause identities',async()=>{
 const h=harness(undefined,true),persisted=[],sidebarSyncs=[];let editorSyncs=0;
 h.window.leqraInfinityArt.persistPilotName=(index,name)=>persisted.push([index,name]);
 h.window.leqraInfinityArt.syncCallsignEditors=()=>editorSyncs++;
 h.window.leqraInfinityArt.syncSidebarContext=()=>sidebarSyncs.push(Array.from(h.infinity.localPilots(),pilot=>pilot.name));
 h.infinity.start('offline',{name:'First',localName:'Second',colorIndex:4,localColorIndex:7,roomRules:{infinityRandomBots:false}});
 const world=h.state(),[first,second]=world.tanks,member=h.infinity.localPilots()[0].member;
 Object.assign(first,{score:12,hp:0,respawn:.7,x:420,y:126,power:'laser',powerTime:4,charges:2});
 Object.assign(second,{score:-3,shield:5,shieldCharges:2,x:210,y:126});
 const before=world.tanks.map(tank=>({...tank}));h.infinity.togglePause();assert.ok(editorSyncs>0);
 assert.equal(await h.infinity.renamePilot(0,'  Rémo_te-7! '),'Rémo_te-7');
 assert.equal(await h.infinity.renamePilot(1,'New Wing'),'New Wing');
 assert.deepEqual(persisted,[[0,'Rémo_te-7'],[1,'New Wing']]);
 assert.deepEqual(sidebarSyncs,[['Rémo_te-7','Second'],['Rémo_te-7','New Wing']]);
 assert.equal(world.tanks[0],first);assert.equal(world.tanks[1],second);
 world.tanks.forEach((tank,index)=>assert.deepEqual({...tank,name:before[index].name},before[index]));
 assert.equal(h.infinity.localPilots()[0].member,member,'renaming does not replace the editor seat');
 assert.deepEqual(Array.from(h.infinity.sidebarHelp().pilots,pilot=>pilot.name),['Rémo_te-7','New Wing']);
 assert.match(h.byID('infiniteKills').textContent,/Rémo_te-7 \(P1\): score: 12, rank: #1/);assert.match(h.byID('infiniteKills').textContent,/New Wing \(P2\): score: -3, rank: #2/);
 assert.match(h.byID('infiniteControlsHint').innerHTML,/Rémo_te-7 \(P1\)/);
 assert.equal(h.byID('infinitePauseMenu').open,true);
 h.infinity.close();h.infinity.start('offline',{name:'Fresh'});assert.notEqual(h.infinity.localPilots()[0].member,member);
 await assert.rejects(h.infinity.renamePilot(1,'Missing'),/no longer available/);
});

test('public, private and party Infinity renames wait for matching acknowledgements and protect confirmed names from queued snapshots',async()=>{
 for(const room of [{},{code:'PRIVATE',token:'secret'},{code:'PARTY',token:'secret',public:true}]){
  const h=harness(),persisted=[],sidebarSyncs=[];h.window.leqraInfinityArt.persistPilotName=(index,name)=>persisted.push([index,name]);
  h.window.leqraInfinityArt.syncSidebarContext=()=>sidebarSyncs.push(Array.from(h.infinity.localPilots(),pilot=>pilot.name));
  h.infinity.start('online',{name:'First',localName:'Second',...room});const socket=h.sockets[0];
  socket.receive({type:'welcome',id:1,localId:2,seed:0,generation:3});
  const tanks=[{id:1,name:'First',score:9,rank:1,colorIndex:4,hp:1,x:42,y:42,angle:0},
   {id:2,name:'Second',score:4,rank:2,colorIndex:7,hp:0,x:210,y:42,angle:0,power:'laser',powerTime:5,charges:2}];
  const packet={type:'state',tanks,leaderboard:tanks,party:tanks,bullets:[],players:2};socket.receive(packet);h.advance(4);h.infinity.togglePause();
  const first=h.infinity.renamePilot(0,'New First'),second=h.infinity.renamePilot(1,'New Second');
  const requests=socket.sent.filter(message=>message.type==='rename');
  assert.equal(requests.length,2);assert.deepEqual(requests.map(message=>message.seat),[0,1]);assert.ok(requests.every(message=>Number.isSafeInteger(message.requestId)&&message.requestId>0));
  assert.notEqual(requests[0].requestId,requests[1].requestId);assert.deepEqual(persisted,[]);
  assert.equal(h.state().tanks[0].name,'First','unconfirmed drafts do not replace the live callsign');
  socket.receive({type:'renamed',seat:1,name:'WRONG',requestId:requests[0].requestId});assert.deepEqual(persisted,[]);
  socket.receive({type:'renamed',seat:1,name:'New Second',requestId:requests[1].requestId});assert.equal(await second,'New Second');
  socket.receive({type:'renamed',seat:0,name:'New First',requestId:requests[0].requestId});assert.equal(await first,'New First');
  assert.deepEqual(persisted,[[1,'New Second'],[0,'New First']]);
  assert.deepEqual(sidebarSyncs,[['First','New Second'],['New First','New Second']]);
  socket.receive(packet);h.advance(4);
  assert.deepEqual(Array.from(h.state().tanks,tank=>tank.name),['New First','New Second'],'an older queued snapshot cannot undo confirmation');
  assert.equal(h.state().tanks[0].score,9);assert.equal(h.state().tanks[1].power,'laser');assert.equal(h.state().tanks[1].hp,0);
  assert.deepEqual(h.byID('infiniteLeaderboard').children.map(row=>row.children[0].textContent),['New First (P1)','New Second (P2)']);
  tanks[0].name='New First';tanks[1].name='New Second';socket.receive(packet);h.advance(4);assert.equal(h.state().confirmedNames.size,0);
  tanks[0].name='Authoritative';socket.receive(packet);h.advance(4);assert.equal(h.infinity.localPilots()[0].name,'Authoritative');
  assert.equal(h.byID('infinitePauseMenu').open,true);h.infinity.close();
 }
});

test('Infinity rename errors, timeouts, send failures and disconnected transports never silently save drafts',async()=>{
 const boot=()=>{const h=harness();h.infinity.start('online',{name:'First'});const socket=h.sockets[0];socket.receive({type:'welcome',id:1,seed:0});socket.receive({type:'state',tanks:[{id:1,name:'First',score:7,hp:1,x:42,y:42,angle:0}],leaderboard:[],bullets:[]});return{...h,socket};};
 const rejected=boot(),pending=rejected.infinity.renamePilot(0,'Draft'),request=rejected.socket.sent.at(-1);
 rejected.socket.receive({type:'rename_error',seat:0,requestId:request.requestId,message:'Try another callsign.'});await assert.rejects(pending,/Try another callsign/);
 assert.equal(rejected.state().failed,false);assert.equal(rejected.state().tanks[0].name,'First');
 const timed=rejected.infinity.renamePilot(0,'Timed');rejected.elapse(6000);await assert.rejects(timed,/Not confirmed yet/);assert.equal(rejected.state().renames.size,0);
 const retry=rejected.infinity.renamePilot(0,'Retried');const retryRequest=rejected.socket.sent.at(-1);
 rejected.socket.receive({type:'rename_error',seat:0,requestId:request.requestId,message:'OLD'});assert.equal(rejected.state().renames.size,1);
 rejected.socket.receive({type:'renamed',seat:0,requestId:retryRequest.requestId,name:'Retried'});assert.equal(await retry,'Retried');rejected.infinity.close();
 const failed=boot(),send=failed.socket.send;failed.socket.send=()=>{throw Error('closed');};await assert.rejects(failed.infinity.renamePilot(0,'Failed'),/Could not send/);assert.equal(failed.state().renames.size,0);failed.socket.send=send;failed.infinity.close();
 const full=boot();full.socket.bufferedAmount=5000;await assert.rejects(full.infinity.renamePilot(0,'Blocked'),/Reconnect/);assert.equal(full.state().renames.size,0);full.infinity.close();
 const gone=boot(),disconnected=gone.infinity.renamePilot(0,'Gone');gone.socket.close();await assert.rejects(disconnected,/connection was interrupted/);assert.equal(gone.state().tanks[0].name,'First');gone.infinity.close();
 const invalid=boot();await assert.rejects(invalid.infinity.renamePilot(0,' ! 🦊 '),/Enter letters or numbers/);assert.equal(invalid.socket.sent.filter(message=>message.type==='rename').length,0);invalid.infinity.close();
});

test('Infinity stops pending renames at closure or co-pilot removal and ignores stale confirmations after a new session',async()=>{
 const h=harness(),persisted=[];h.window.leqraInfinityArt.persistPilotName=(index,name)=>persisted.push([index,name]);
 h.infinity.start('online',{name:'Old',localName:'Wing'});const old=h.sockets[0];
 old.receive({type:'welcome',id:1,localId:2,seed:0});old.receive({type:'state',tanks:[{id:1,name:'Old',hp:1,x:42,y:42,angle:0},{id:2,name:'Wing',hp:1,x:210,y:42,angle:0}],bullets:[],leaderboard:[]});
 const primary=h.infinity.renamePilot(0,'New'),secondary=h.infinity.renamePilot(1,'Missing');
 await assert.rejects(h.infinity.renamePilot(0,'Duplicate'),/already waiting/);
 const requests=old.sent.filter(message=>message.type==='rename');old.receive({type:'welcome',id:1,seed:0});await assert.rejects(secondary,/no longer available/);
 h.infinity.close();await assert.rejects(primary,/closed before/);h.infinity.start('offline',{name:'Fresh'});
 for(const request of requests)old.receive({type:'renamed',seat:request.seat,requestId:request.requestId,name:'STALE'});
 assert.equal(h.state().tanks[0].name,'Fresh');assert.deepEqual(persisted,[]);
 await assert.rejects(h.infinity.renamePilot(3,'Invalid'),/no longer available/);h.infinity.close();await assert.rejects(h.infinity.renamePilot(0,'Closed'),/no longer available/);
});

test('stored mouse OFF blocks Infinity canvas aiming and firing while both keyboard pilots still work',()=>{
 const h=harness(undefined,true);Object.assign(h.window.leqraInfinityArt,{mouseAimEnabled:()=>false,mouseFireEnabled:()=>false});
 h.infinity.start('offline',{localName:'Wing',roomRules:{infinityRandomBots:false}});h.state().tanks.forEach(tank=>{tank.invulnerable=0;tank.spawnProtected=false;});
 const world=h.state(),[first,second]=world.tanks,canvas=h.byID('infiniteCanvas'),arena=h.byID('infiniteArena');
 world.nextBot=world.nextPickup=Infinity;canvas.getBoundingClientRect=()=>({left:0,top:0,width:390,height:740});
 Object.assign(first,{x:100,y:100,angle:0});Object.assign(second,{x:500,y:500,angle:0});
 canvas.emit('pointermove',{pointerType:'mouse',pointerId:1,clientX:300,clientY:60,buttons:0});
 canvas.emit('pointerdown',{pointerType:'mouse',button:0,pointerId:1,clientX:300,clientY:60});
 h.advance(20);assert.equal(first.angle,0);assert.equal(world.bullets.length,0);assert.equal(canvas.style.cursor,'auto');
 assert.ok(!h.byID('infiniteControlsHint').innerHTML.includes('control-mouse-key'));
 for(const code of ['KeyW','KeyQ','ArrowDown','Space'])arena.emit('keydown',{code});h.advance();
 assert.ok(first.x>100);assert.ok(second.x<500);assert.deepEqual(Array.from(world.bullets,bullet=>bullet.owner).sort(),[first.id,second.id].sort());
 h.infinity.close();
});

test('disabling Infinity mouse controls cancels only mouse taps and reenable needs a fresh click',()=>{
 const h=harness(undefined,true);let enabled=true;Object.assign(h.window.leqraInfinityArt,{mouseAimEnabled:()=>enabled,mouseFireEnabled:()=>enabled});
 h.infinity.start('offline',{roomRules:{infinityRandomBots:false}});h.state().tanks.forEach(tank=>{tank.invulnerable=0;tank.spawnProtected=false;});const world=h.state(),canvas=h.byID('infiniteCanvas');
 world.nextBot=world.nextPickup=Infinity;Object.assign(world.tanks[0],{x:100,y:100,angle:0});
 canvas.getBoundingClientRect=()=>({left:0,top:0,width:390,height:740});
 const click=pointerId=>canvas.emit('pointerdown',{pointerType:'mouse',button:0,pointerId,clientX:300,clientY:100});
 click(1);enabled=false;h.infinity.resetMouseControls();h.advance();assert.equal(world.bullets.length,0);assert.equal(world.tanks[0].angle,0);
 assert.ok(!h.byID('infiniteControlsHint').innerHTML.includes('control-mouse-key'));
 enabled=true;h.infinity.resetMouseControls();canvas.emit('pointermove',{pointerType:'mouse',pointerId:1,clientX:300,clientY:100,buttons:1});
 h.advance(30);assert.equal(world.bullets.length,0,'a held old mouse button cannot start firing after reenable');assert.equal(canvas.style.cursor,'');
 assert.ok(h.byID('infiniteControlsHint').innerHTML.includes('control-mouse-key'));
 click(2);h.advance();assert.equal(world.bullets.length,1);h.infinity.close();
 for(const source of ['keyboard','touch']){
  const b=harness(undefined,true);let mouse=true;Object.assign(b.window.leqraInfinityArt,{mouseAimEnabled:()=>mouse,mouseFireEnabled:()=>mouse});
  b.infinity.start('offline',{roomRules:{infinityRandomBots:false}});b.state().tanks.forEach(tank=>{tank.invulnerable=0;tank.spawnProtected=false;});b.state().nextBot=b.state().nextPickup=Infinity;
  b.byID('infiniteCanvas').emit('pointerdown',{pointerType:'mouse',button:0,pointerId:5,clientX:70,clientY:30});
  if(source==='keyboard'){b.byID('infiniteArena').emit('keydown',{code:'KeyQ'});b.byID('infiniteArena').emit('keyup',{code:'KeyQ'});}
  else{b.byID('infiniteFire').emit('pointerdown',{button:0,pointerType:'touch',pointerId:6});b.window.emit('pointerup',{pointerId:6});}
  mouse=false;b.infinity.resetMouseControls();b.advance();assert.equal(b.state().bullets.length,1,source+' fire tap survives mouse-only cleanup');b.infinity.close();
 }
});

test('Infinity mouse toggle immediately releases only P1 mouse input online and preserves P2 and keyboard motion',()=>{
 const h=harness(undefined,true);let enabled=true;Object.assign(h.window.leqraInfinityArt,{mouseAimEnabled:()=>enabled,mouseFireEnabled:()=>enabled});
 h.infinity.start('online',{localName:'Wing'});const socket=h.sockets[0];socket.receive({type:'welcome',id:1,localId:2,seed:0});
 socket.receive({type:'state',tanks:[{id:1,x:42,y:42,angle:0,hp:1},{id:2,x:210,y:210,angle:0,hp:1}],bullets:[],leaderboard:[],players:2});
 const canvas=h.byID('infiniteCanvas'),arena=h.byID('infiniteArena');canvas.getBoundingClientRect=()=>({left:0,top:0,width:390,height:740});
 for(const code of ['KeyW','ArrowDown','Space'])arena.emit('keydown',{code});
 canvas.emit('pointerdown',{pointerType:'mouse',button:0,pointerId:1,clientX:300,clientY:100});
 assert.equal(socket.sent.at(-1).fire,true);assert.equal(socket.sent.at(-1).aimOnly,true);
 const before=socket.sent.length;enabled=false;h.infinity.resetMouseControls();
 assert.equal(socket.sent.length,before+1);assert.equal(socket.sent.at(-1).local,undefined);assert.equal(socket.sent.at(-1).fire,false);
 assert.equal(socket.sent.at(-1).forward,true);assert.equal(socket.sent.at(-1).aimOnly,false);assert.equal(socket.sent.at(-1).stickX,0);
 assert.equal(h.state().local.lastSent.fire,true);assert.equal(h.state().local.lastSent.reverse,true);
 enabled=true;h.infinity.resetMouseControls();assert.equal(socket.sent.at(-1).fire,false);
 canvas.emit('pointermove',{pointerType:'mouse',pointerId:1,clientX:300,clientY:100,buttons:1});h.advance(4);
 assert.equal(h.state().lastSent.fire,false);canvas.emit('pointerdown',{pointerType:'mouse',button:0,pointerId:2,clientX:300,clientY:100});assert.equal(socket.sent.at(-1).fire,true);
 arena.emit('keydown',{code:'Escape'});enabled=false;h.infinity.resetMouseControls();assert.equal(socket.sent.at(-1).paused,true);assert.equal(socket.sent.at(-1).fire,false);h.infinity.close();
});

test('Infinity mouse cleanup preserves held touch steering and fire, with missing preference hooks enabled by default',()=>{
 const h=harness(undefined,true);h.infinity.start('online');const socket=h.sockets[0];socket.receive({type:'welcome',id:1,seed:0});
 socket.receive({type:'state',tanks:[{id:1,x:42,y:42,angle:0,hp:1}],bullets:[],leaderboard:[],players:1});
 h.byID('infiniteCanvas').emit('pointerdown',{pointerType:'mouse',button:0,pointerId:3,clientX:70,clientY:30});assert.equal(socket.sent.at(-1).fire,true,'legacy fixtures and saved defaults keep mouse controls enabled');
 h.byID('infiniteStick').emit('pointerdown',{pointerType:'touch',button:0,pointerId:1,clientX:48,clientY:96});
 h.byID('infiniteFire').emit('pointerdown',{pointerType:'touch',button:0,pointerId:2});
 Object.assign(h.window.leqraInfinityArt,{mouseAimEnabled:()=>false,mouseFireEnabled:()=>false});h.infinity.resetMouseControls();
 assert.equal(socket.sent.at(-1).fire,true);assert.equal(socket.sent.at(-1).stickY,1);assert.equal(socket.sent.at(-1).touchAim,true);
 h.window.emit('pointerup',{pointerId:2});assert.equal(socket.sent.at(-1).fire,false);assert.equal(socket.sent.at(-1).stickY,1);
 h.infinity.close();
});

test('Infinity mouse aim and mouse fire operate independently in all four preference combinations',()=>{
 for(const aim of [false,true])for(const fire of [false,true]){
  const h=harness(undefined,true);Object.assign(h.combatPrefs,{mouseAim:aim,mouseFire:fire});
  Object.assign(h.window.leqraInfinityArt,{mouseAimEnabled:()=>aim,mouseFireEnabled:()=>fire});
  h.infinity.start('offline',{localName:'Wing',roomRules:{infinityRandomBots:false}});h.state().tanks.forEach(tank=>{tank.invulnerable=0;tank.spawnProtected=false;});
  const world=h.state(),canvas=h.byID('infiniteCanvas'),[first,second]=world.tanks;
  world.nextPickup=world.nextBot=Infinity;Object.assign(first,{x:100,y:100,angle:0});Object.assign(second,{x:900,y:900,angle:0});
  canvas.getBoundingClientRect=()=>({left:0,top:0,width:390,height:740});
  canvas.emit('pointerdown',{pointerType:'mouse',button:0,pointerId:1,clientX:300,clientY:70});h.advance(20);
  assert.equal(first.angle!==0,aim,'aim '+aim+', fire '+fire);assert.equal(world.bullets.length>0,fire,'aim '+aim+', fire '+fire);
  assert.equal(canvas.style.cursor,aim||fire?'':'auto');
  const hint=h.byID('infiniteControlsHint').textContent;
  assert.equal(hint.includes('Mouse Aim'),aim);assert.equal(hint.includes('Mouse Fire'),fire);
  h.infinity.close();
 }
});

test('changing Infinity aim does not release mouse fire and changing fire does not erase mouse aim',()=>{
 const h=harness(undefined,true);let aim=true,fire=true;
 Object.assign(h.window.leqraInfinityArt,{mouseAimEnabled:()=>aim,mouseFireEnabled:()=>fire});
 h.infinity.start('online',{localName:'Wing'});const socket=h.sockets[0];socket.receive({type:'welcome',id:1,localId:2,seed:0});
 socket.receive({type:'state',tanks:[{id:1,x:42,y:42,angle:0,hp:1},{id:2,x:210,y:210,angle:0,hp:1}],bullets:[],leaderboard:[],players:2});
 const canvas=h.byID('infiniteCanvas');canvas.getBoundingClientRect=()=>({left:0,top:0,width:390,height:740});
 canvas.emit('pointerdown',{pointerType:'mouse',button:0,pointerId:1,clientX:300,clientY:70});assert.equal(socket.sent.at(-1).fire,true);assert.equal(socket.sent.at(-1).aimOnly,true);
 aim=false;h.infinity.resetMouseControls('aim');assert.equal(socket.sent.at(-1).fire,true);assert.equal(socket.sent.at(-1).aimOnly,false);
 aim=true;h.infinity.resetMouseControls('aim');assert.equal(socket.sent.at(-1).fire,true);assert.equal(socket.sent.at(-1).aimOnly,false);
 canvas.emit('pointermove',{pointerType:'mouse',pointerId:1,clientX:300,clientY:70,buttons:1});h.advance(3);assert.equal(h.state().lastSent.aimOnly,true);
 fire=false;h.infinity.resetMouseControls('fire');assert.equal(socket.sent.at(-1).fire,false);assert.equal(socket.sent.at(-1).aimOnly,true);
 fire=true;h.infinity.resetMouseControls('fire');assert.equal(socket.sent.at(-1).fire,false);assert.equal(socket.sent.at(-1).aimOnly,true);
 canvas.emit('pointermove',{pointerType:'mouse',pointerId:1,clientX:300,clientY:70,buttons:1});h.advance(3);assert.equal(h.state().lastSent.fire,false);
 canvas.emit('pointerdown',{pointerType:'mouse',button:0,pointerId:2,clientX:300,clientY:70});assert.equal(socket.sent.at(-1).fire,true);
 fire=false;h.infinity.resetMouseControls('fire');aim=false;h.infinity.resetMouseControls('aim');assert.equal(canvas.style.cursor,'auto');
 h.infinity.close();
});

test('mouse-fire-only Infinity clicks use the keyboard heading and cannot control the co-pilot viewport',()=>{
 const h=harness(undefined,true);Object.assign(h.window.leqraInfinityArt,{mouseAimEnabled:()=>false,mouseFireEnabled:()=>true});
 h.infinity.start('online',{localName:'Wing'});const socket=h.sockets[0];socket.receive({type:'welcome',id:1,localId:2,seed:0});
 socket.receive({type:'state',tanks:[{id:1,x:42,y:42,angle:0,hp:1},{id:2,x:210,y:210,angle:0,hp:1}],bullets:[],leaderboard:[],players:2});
 const canvas=h.byID('infiniteCanvas');canvas.getBoundingClientRect=()=>({left:0,top:0,width:390,height:740});
 const count=socket.sent.length;canvas.emit('pointerdown',{pointerType:'mouse',button:0,pointerId:1,clientX:300,clientY:600});assert.equal(socket.sent.length,count,'the second viewport never fires the primary tank');
 canvas.emit('pointerdown',{pointerType:'mouse',button:0,pointerId:2,clientX:300,clientY:70});
 assert.equal(socket.sent.at(-1).fire,true);assert.equal(socket.sent.at(-1).aimOnly,false);assert.equal(socket.sent.at(-1).stickX,0);assert.equal(socket.sent.at(-1).stickY,0);assert.equal(socket.sent.at(-1).local,undefined);
 h.infinity.close();
});


test('leaderboard reset notices keep public Infinity connected and survive the next score snapshot',()=>{
 for(const selected of [false,true]){
  const h=harness(undefined,true);h.infinity.start('online');const socket=h.sockets[0];
  socket.receive({type:'welcome',id:4,seed:0});
  const packet={type:'state',tick:1,tanks:[{id:4,x:100,y:100,angle:0,hp:1,score:7}],bullets:[],players:1,leaderboard:[]};
  socket.receive(packet);const world=h.state();
  socket.receive({type:'leaderboard_reset',selected});
  const notice=selected?'Selected Public Infinity scores were reset.':'The Public Infinity leaderboard was reset.';
  assert.equal(h.byID('infiniteStatus').textContent,notice);assert.equal(world.failed,false);assert.equal(world.joined,true);assert.equal(h.sockets.length,1);assert.equal(world.tanks[0].score,7,'the authoritative snapshot chooses affected scores');
  packet.tick++;packet.tanks[0].score=0;socket.receive(packet);
  assert.equal(world.tanks[0].score,0);assert.equal(h.byID('infiniteStatus').textContent,notice);assert.equal(h.byID('infiniteStatus').hidden,false);
  h.elapse(5100);packet.tick++;socket.receive(packet);assert.equal(h.byID('infiniteStatus').hidden,true);assert.equal(world.joined,true);assert.equal(h.sockets.length,1);h.infinity.close();
 }
});

test('public ownership handover preserves score and stops superseded browsers from retrying',()=>{
 const h=harness(undefined,true),remembered=[];
 h.window.leqraInfinityArt.publicIdentityToken=()=> 'p_original';
 h.window.leqraInfinityArt.rememberPublicIdentity=token=>remembered.push(token);
 h.infinity.start('online',{name:'Chosen'});
 const [socket]=h.sockets;socket.emit('open');
 assert.equal(socket.sent[0].publicToken,'p_original');assert.equal(socket.sent[0].updateNames,true);
 socket.receive({type:'welcome',id:14,seed:0,publicToken:'p_replacement',resumed:true});
 socket.receive({type:'state',tick:1,tanks:[{id:14,name:'Chosen',x:100,y:100,angle:0,hp:1,score:27}],bullets:[],players:1,leaderboard:[]});
 const world=h.state();assert.equal(world.publicToken,'p_replacement');assert.deepEqual(remembered,['p_replacement']);assert.equal(world.tanks[0].score,27);
 socket.receive({type:'error',code:'session_replaced',message:'This online identity continued in another window.'});
 h.elapse(60000);
 assert.equal(world.failed,true);assert.equal(world.joined,false);assert.equal(h.sockets.length,1);assert.equal(socket.readyState,3);assert.equal(world.publicToken,'p_replacement','a superseded transport cannot discard ownership');
 assert.match(h.byID('infiniteStatus').textContent,/taken over by another device/);h.infinity.close();
});

test('a revoked account key is terminal and clears only the credential used by that arena',()=>{
 const h=harness(undefined,true),revoked=[];
 h.window.leqraInfinityArt.publicIdentityToken=()=> 'p_old_owner';
 h.window.leqraInfinityArt.forgetRevokedAccount=token=>revoked.push(token);
 h.infinity.start('online',{name:'Chosen'});const [socket]=h.sockets;socket.emit('open');
 socket.receive({type:'welcome',id:14,seed:0,publicToken:'p_old_owner',resumed:true});
 socket.receive({type:'state',tick:1,tanks:[{id:14,name:'Chosen',x:100,y:100,angle:0,hp:1,score:27}],bullets:[],players:1,leaderboard:[]});
 socket.receive({type:'error',code:'account_key_revoked'});h.elapse(60000);
 assert.deepEqual(revoked,['p_old_owner']);assert.equal(h.state().failed,true);assert.equal(h.sockets.length,1);assert.match(h.byID('infiniteStatus').textContent,/key was reset.*Import the latest key/);h.infinity.close();
});

test('a stored or revoked unselected P2 key never joins or returns during a solo reconnect',()=>{
 const h=harness(undefined,true),keys=['p_primary','p_old_p2'];
 h.window.leqraInfinityArt.publicIdentityToken=seat=>keys[seat||0];
 h.window.leqraInfinityArt.prepareLocalAccount=()=>({localPublicToken:keys[1]});
 h.infinity.start('online',{name:'Solo'});let socket=h.sockets[0];socket.emit('open');assert.equal(socket.sent[0].localPublicToken,undefined,'unused stored P2 proof is omitted');
 socket.receive({type:'welcome',id:14,seed:0,publicToken:keys[0],resumed:true});socket.receive({type:'state',tick:1,tanks:[{id:14,name:'Solo',x:100,y:100,angle:0,hp:1,score:27}],bullets:[],players:1,leaderboard:[]});
 assert.equal(h.state().localPublicToken,'');keys[1]='';socket.close();h.elapse(500);socket=h.sockets.at(-1);socket.emit('open');assert.equal(socket.sent[0].localPublicToken,undefined);assert.equal(socket.sent[0].localName,undefined);assert.equal(socket.sent[0].publicToken,keys[0]);h.infinity.close();
});

test('manual public entry updates chosen names but reconnects omit stale drafts and recover after 20 seconds',()=>{
 const h=harness(undefined,true);h.window.leqraInfinityArt.publicIdentityToken=()=> 'p_owner';
 h.infinity.start('online',{name:'Chosen',localName:'Wing'});
 const [first]=h.sockets;first.emit('open');
 assert.equal(first.sent[0].name,'Chosen');assert.equal(first.sent[0].localName,'Wing');assert.equal(first.sent[0].updateNames,true);assert.equal(first.sent[0].resume,true);
 const packet={type:'state',tick:1,tanks:[{id:4,name:'Saved Lead',x:100,y:100,angle:0,hp:1,score:13},{id:9,name:'Saved Wing',x:220,y:100,angle:0,hp:1,score:-3}],bullets:[],players:2,leaderboard:[]};
 first.receive({type:'welcome',id:4,localId:9,seed:0,publicToken:'p_owner',resumed:true});first.receive(packet);first.close();
 h.elapse(26000);const resumed=h.sockets.at(-1);
 assert.equal(resumed.readyState,1,'public attempts retain a full handshake window after a long outage');resumed.emit('open');
 assert.equal(resumed.sent[0].publicToken,'p_owner');assert.equal(resumed.sent[0].resume,true);assert.equal(resumed.sent[0].updateNames,undefined,'transport retries must not rename persisted pilots from stale drafts');
 resumed.receive({type:'welcome',id:4,localId:9,seed:0,publicToken:'p_owner',resumed:true});resumed.receive({...packet,tick:2});
 assert.equal(h.state().failed,false);assert.equal(h.state().joined,true);assert.deepEqual(Array.from(h.state().tanks,t=>t.score),[13,-3]);h.infinity.close();
});

test('public room reconnect drops stale membership while private rooms retain their 20-second window',()=>{
 for(const isPublic of [false,true]){
  const h=harness(undefined,true),storage=h.window.leqraInfinityArt;storage.publicIdentityToken=()=> 'p_owner';
  h.infinity.start('online',{code:'old room',token:'room-secret',public:isPublic,resumeGeneration:3});
  const [first]=h.sockets;first.emit('open');first.receive({type:'welcome',id:4,seed:0,generation:3,publicToken:isPublic?'p_owner':undefined});
  first.receive({type:'state',tick:1,tanks:[],bullets:[],players:1,leaderboard:[]});first.close();h.elapse(450);
  const next=h.sockets.at(-1);next.emit('open');const join=next.sent[0];
  assert.equal(join.publicToken,'p_owner');assert.equal(join.updateNames,undefined);
  if(isPublic){assert.equal(join.code,undefined);assert.equal(join.token,undefined);assert.equal(h.state().room,null);h.elapse(26000);assert.equal(h.state().failed,false);}
  else{assert.equal(join.code,'old room');assert.equal(join.token,'room-secret');assert.equal(join.generation,3);h.elapse(21000);assert.equal(h.state().failed,true);const attempts=h.sockets.length;h.elapse(20000);assert.equal(h.sockets.length,attempts);}
  h.infinity.close();
 }
});

test('a manual public name conflict returns to its editor without clearing or replacing ownership',()=>{
 const h=harness(undefined,true),remembered=[],conflicts=[];h.window.leqraInfinityArt.publicIdentityToken=()=> 'p_owner';h.window.leqraInfinityArt.rememberPublicIdentity=token=>remembered.push(token);
 h.infinity.start('online',{name:'Taken',onConflict:packet=>{conflicts.push(packet);h.infinity.close();}});
 const [socket]=h.sockets;socket.emit('open');assert.equal(socket.sent[0].updateNames,true);
 const rejection={type:'error',code:'callsign_taken',conflicts:[{seat:0,name:'Taken'}],message:'Choose an unused online callsign.'};socket.receive(rejection);h.elapse(30000);
 assert.deepEqual(JSON.parse(JSON.stringify(conflicts)),[rejection]);assert.deepEqual(remembered,[]);assert.equal(h.sockets.length,1);assert.equal(h.byID('infiniteArena').open,false);
});
