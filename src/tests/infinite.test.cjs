'use strict';

const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {test} = require('node:test');
const vm = require('node:vm');
const {assetPath} = require('./web_assets.cjs');

function harness(url = 'https://example.test/', openField = false, storage = new Map()) {
 class Element {
  listeners = {};
  children = [];
  style = {removeProperty() {}, setProperty() {}};
  classes = new Set();
  classList = {remove: name => this.classes.delete(name), add: name => this.classes.add(name), toggle() {}};
  dataset = {};
  clientWidth = 390;
  clientHeight = 740;
  open = false;
  textContent = '';
  closest() { return false; }
  setAttribute() {}
  getContext() {
   let angle = 0;
   return new Proxy({
    rotate: value => {angle = value;},
    moveTo(x,y) {if (x===41 && y===-6) markers.push({angle,color:this.strokeStyle});},
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
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this.children = children; }
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
 document.getElementById = byID;
 document.createElement = () => new Element();
 const window = new Element();
 window.leqra = {version: '9.1.0'};
 window.matchMedia = () => ({matches: false});
 const sounds = [], loadouts = [], markers = [], combatPrefs = {visual:true,audio:true,fps:false};
 const powers = Object.fromEntries(['rapid','scatter','shield','homing','grenade','speed','laser','cannon','ghost','starman']
  .map(name => [name, {name, color: '#fff'}]));
 window.leqraInfinityArt = {
  colors: ['#32c5ff','#ff758f'], theme: {}, powers, renderPixelRatio: () => 1,
  tile() {}, wall() {}, pickup() {}, hull() {}, turret() {}, rect() {}, drawBadges() {}, bullets() {},
  ageTank: tank => tank,
  sampleFrame: (now,work) => context.sampleFrame(now,work,'infiniteFPSIndicator',null),
  renderLoadout: (tank, num, projectiles, blocked, phase, twoPilots) => {
   loadouts[num] = {tank, projectiles, blocked, phase};
   context.renderDeathNotice(tank,num,twoPilots,context.infinityHUDId);
  },
  primeAudioUnlock() {}, touchPolicy() {}, grenadeDragFactor: () => 1,
  missileTurn: 4.8,
  openControls: () => byID('controlsDialog').showModal(),
  isTouchUI: () => false,
  toggleFullscreen: () => sounds.push('fullscreen'),
  toggleSound: () => sounds.push('mute'),
  shot: kind => sounds.push('shot:' + kind),
  ricochet: () => sounds.push('ricochet'), collect: () => sounds.push('pickup'), shield: () => sounds.push('shield'),
  blast: () => sounds.push('blast'), impact: () => sounds.push('impact'),
 };
 let now = 0, scheduled, randomState = 1, nextTimer = 0;
 const timers = new Map();
 const math = Object.create(Math);
 math.random = openField ? () => .5 :
  () => ((randomState = Math.imul(randomState, 1664525) + 1013904223 | 0) >>> 0) / 0x100000000;
 const context = vm.createContext({
  window, document, location: new URL(url), URL, WebSocket, Math: math,
  localStorage: {getItem: () => 'Saved pilot'}, performance: {now: () => now},
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
 vm.runInContext(game.slice(game.indexOf('function infinityHUDId('),game.indexOf('function renderInfinityLoadout(')),context);
 vm.runInContext(game.slice(game.indexOf('const frameStats='),game.indexOf('function initFrameSettings(')), context);
 const keyPolicy = game.slice(game.indexOf('function arenaKeyBlocked('), game.indexOf('// All input paths'));
 const keyLabel = game.slice(game.indexOf('function keyLabel('), game.indexOf('function aliasesActive('));
 const composition = game.match(/^function composingKey\(e\).*$/m)[0];
 vm.runInContext('let bindingCapture=null;\n'+composition+'\n'+keyLabel+keyPolicy, context);
 Object.assign(window.leqraInfinityArt, {arenaKeyBlocked: context.arenaKeyBlocked, keyLabel: context.keyLabel});
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
 vm.runInContext(readFileSync(assetPath('infinite.js'), 'utf8').replace('window.leqraInfinity =', 'window.testArena = () => session; window.leqraInfinity ='), context);
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
 return {infinity: window.leqraInfinity, byID, sockets, advance, elapse, window, state:window.testArena, sounds, loadouts, markers, combatPrefs};
}

test('Infinity runs offline directly from a file and adds nearby bots to the standings', () => {
 const {infinity, byID, sockets, advance} = harness('file:///leqra/index.html');
 infinity.start('offline', {name: 'Explorer'});
 assert.equal(byID('infiniteArena').open, true);
 assert.equal(byID('infiniteKills').textContent, 'Score 0');
 assert.equal(byID('infiniteLeaderboard').children[0].children[0].textContent, 'Explorer (you)');
 advance(90);
 assert.match(byID('infiniteStatus').textContent, /[1-7] bots/);
 assert.match(byID('infiniteLeaderboard').children[1].children[0].textContent, /^Bot /);
 assert.equal(sockets.length, 0);
 infinity.close();
 assert.equal(byID('infiniteArena').open, false);
});

test('Infinity sends its render cadence to the shared optional FPS readout', () => {
 const {infinity,byID,advance,combatPrefs}=harness(undefined,true);
 infinity.start('offline');
 advance(60);
 assert.equal(byID('infiniteFPSIndicator').textContent,'');
 combatPrefs.fps=true;
 advance(60);
 assert.equal(byID('infiniteFPSIndicator').textContent,'60 FPS · 16.7 ms');
 assert.match(byID('infiniteFPSIndicator').title,/JS update\/render work/);
 assert.equal(byID('fpsIndicator').textContent,'');
 infinity.close();
});

test('offline Infinity routes two independent keyboard layouts to separate tanks', () => {
 const {infinity,byID,state,advance}=harness(undefined,true);
 infinity.start('offline',{localName:'Local wingmate'});
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
 assert.match(byID('infiniteControlsHint').textContent,/P1 .* · P2 /);
 infinity.close();
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

test('offline room Infinity passes allied tanks and freezes on the first team score target', () => {
 const {infinity,byID,state,advance}=harness(undefined,true);
 infinity.start('offline',{
  primaryId:0,localId:1,localName:'Wingmate',
  roster:[{id:0,team:1},{id:1,team:1}],
  roomRules:{teamMode:'teams',teamNames:['Blue','Red'],teamColors:[3,5],infinityTarget:1}
 });
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
 const {infinity, byID, advance} = harness(undefined, true);
 infinity.start('offline');
 const status = byID('infiniteStatus');
 for (let i = 0; i < 480 && !status.textContent.includes('Respawning'); i++) advance();
 assert.match(status.textContent, /Respawning/);
 assert.equal(byID('infiniteKills').textContent, 'Score -1');
 const rows = byID('infiniteLeaderboard').children;
 assert.deepEqual(rows[0].children.map(cell => cell.textContent), ['Bot 1', 1]);
 assert.deepEqual(rows[1].children.map(cell => cell.textContent), ['Saved pilot (you)', -1]);
 const notice = byID('infiniteDeathNotice1');
 assert.equal(notice.textContent,'Killed by Bot 1');
 assert.equal(notice.hidden,false);
 advance(64);
 assert.match(status.textContent, /Weapons live/);
 assert.equal(byID('infiniteKills').textContent, 'Score -1');
 assert.equal(notice.hidden,true);
});

test('offline Infinity respawns Player 2 in 60 ticks and clears just their death notice', () => {
 const {infinity,byID,state,advance}=harness(undefined,true);
 infinity.start('offline',{name:'PILOT ONE',localName:'PILOT TWO',roomRules:{}});
 const [first,second]=state().tanks;
 Object.assign(first,{x:100,y:100,angle:0,power:'laser',powerTime:3,charges:1});
 Object.assign(second,{x:166,y:100,invulnerable:0});
 byID('infiniteArena').emit('keydown',{code:'KeyQ'});
 advance();
 byID('infiniteArena').emit('keyup',{code:'KeyQ'});
 assert.equal(second.respawn,1);
 const notice=byID('infiniteDeathNotice2');
 assert.equal(notice.textContent,'P2 · Killed by PILOT ONE');
 assert.equal(byID('infiniteDeathNotice1').hidden,true);
 advance(59);
 assert.equal(second.hp,0);
 assert.equal(notice.hidden,false);
 advance();
 assert.equal(second.hp,1);
 assert.equal(second.killedBy,'');
 advance(2);
 assert.equal(notice.hidden,true);
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

test('Starman contact in offline Infinity kills shielded tanks, with walls and invulnerability respected', () => {
 for(const [label,protection,wall,eliminated] of [
  ['shield',0,null,true],
  ['spawn protection',1,null,false],
  ['wall between centers',0,{x:111,y:78,w:8,h:48},false],
  ['attacker inside wall',0,{x:98,y:78,w:8,h:48},false],
 ]) {
  const {infinity,state,advance,window}=harness(undefined,true);
  infinity.start('offline');
  const world=state(),pilot=world.tanks[0];
  world.nextPickup=world.nextBot=Infinity;
  if(wall)world.maze.wallsNear=()=>[wall];
  Object.assign(pilot,{x:100,y:100});
  window.leqraInfinityArt.grantPower(pilot,'starman',15,4);
  const target={...pilot,id:'target',x:134,starmanTime:0,ghostTime:0,invulnerable:protection,shield:10,shieldCharges:3};
  world.tanks.push(target);
  advance();
  assert.equal(target.hp,eliminated?0:1,label);
  assert.equal(target.score,eliminated?-1:0,label);
  assert.equal(pilot.score,eliminated?1:0,label);
  if(eliminated)assert.equal(target.respawn,1);
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

test('online Infinity sends neutral pause heartbeats and clears the respawn hold on resume', () => {
 const {infinity, byID, sockets, state, advance} = harness();
 infinity.start('online');
 const [socket] = sockets, arena = byID('infiniteArena'), menu = byID('infinitePauseMenu');
 arena.emit('keydown',{code:'Escape'});
 socket.receive({type:'welcome',id:4,seed:0});
 socket.receive({type:'state',tanks:[{id:4,x:42,y:42,angle:0,hp:0}],bullets:[],players:1,leaderboard:[]});
 assert.ok(socket.sent.at(-1).paused);
 const pauseSeq = socket.sent.at(-1).seq;
 byID('infiniteControlsBtn').emit('click');
 advance(40);
 assert.ok(menu.open && byID('controlsDialog').open);
 assert.match(byID('infiniteStatus').textContent,/Respawn held/);
 assert.ok(socket.sent.length>2);
 assert.ok(socket.sent.every(input=>input.paused&&!input.forward&&!input.fire));
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
 assert.deepEqual(sounds,Array(4).fill('tone:850'),'the visible P2 lock and offscreen P1 lock both chirp');
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
 publish([first,{...second,hp:0,respawnTime:1,killedBy:'Pilot <7>'}]);
 assert.equal(p1.hidden,true);
 assert.equal(p2.hidden,false);
 assert.equal(p2.textContent,'P2 · Killed by Pilot <7>');
 publish([{...first,hp:0,respawnTime:1,killedBy:'Pilot 8'},{...second,spawnSerial:2}]);
 assert.equal(p1.textContent,'P1 · Killed by Pilot 8');
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
 assert.deepEqual(sounds,['tone:850','tone:850']);
 infinity.close();
});

test('Infinity ignores round endings and sounds tank destruction and grenade blasts', () => {
 const {infinity, sockets, state, sounds} = harness();
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
 assert.deepEqual(sounds,['blast','blast']);
 assert.equal(state().visualEffects.map(effect=>effect.kind).join(),'hit,blast');
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
 assert.deepEqual(socket.sent[0], {type: 'join', version: '9.1.0', name: 'Explorer', code: 'forest', token: 'test-token'});
 socket.receive({type: 'welcome', id: 7, seed: 0});
 advance();
 assert.equal(socket.sent.length, 1);
 const pilot = {id: 7, name: 'Explorer', score: -1, hp: 0, x: 42, y: 42, angle: 0};
 socket.receive({
  type: 'state', tanks: [pilot], bullets: [], players: 2,
  leaderboard: [{id: 9, name: '<Distant pilot>', score: 5}, pilot],
 });
 advance();
 assert.equal(byID('infiniteKills').textContent, 'Score -1');
 assert.match(byID('infiniteStatus').textContent, /Respawning/);
 assert.equal(byID('infiniteLeaderboard').children[0].children[0].textContent, '<Distant pilot>');
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
 assert.equal(byID('infiniteKills').textContent,'P1 4 · P2 -2');
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
 assert.deepEqual(resumed.sent.slice(1).map(input=>[!!input.local,input.seq,input.paused,input.forward,input.fire]),
  [[false,1,true,false,false],[true,1,true,false,false]]);
 assert.deepEqual(sounds,[]);
 byID('infiniteResumeBtn').emit('click');
 assert.deepEqual(resumed.sent.slice(-2).map(input=>[!!input.local,input.seq,input.paused]),
  [[false,2,false],[true,2,false]]);
 advance(2);
 assert.equal(byID('infiniteKills').textContent,'P1 4 · P2 -2');
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
 const {infinity,byID,sockets,state,advance}=harness(undefined,true);
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
 infinity.start('offline',{bindings,roomRules:{}});
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
