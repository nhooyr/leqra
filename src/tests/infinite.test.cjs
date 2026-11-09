'use strict';

const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {test} = require('node:test');
const vm = require('node:vm');
const {assetPath} = require('./web_assets.cjs');

function harness(url = 'https://example.test/', openField = false) {
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
  getContext() { return new Proxy({}, {get: () => () => {}}); }
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
 const sounds = [];
 const powers = Object.fromEntries(['rapid','scatter','shield','homing','grenade','speed','laser','cannon','ghost','starman']
  .map(name => [name, {name, color: '#fff'}]));
 window.leqraInfinityArt = {
  colors: ['#32c5ff','#ff758f'], theme: {}, powers, renderPixelRatio: () => 1,
  tile() {}, wall() {}, pickup() {}, hull() {}, turret() {}, rect() {}, badge() {}, bullets() {},
  primeAudioUnlock() {}, touchPolicy() {}, grenadeDragFactor: () => 1,
  missileTurn: 4.8, grenadeTurn: 2.4,
  openControls: () => byID('controlsDialog').showModal(),
  toggleSound: () => sounds.push('mute'),
  shot: kind => sounds.push('shot:' + kind),
  ricochet: () => sounds.push('ricochet'), collect: () => sounds.push('pickup'), shield: () => sounds.push('shield'),
  blast: () => sounds.push('blast'), impact: () => sounds.push('impact'),
 };
 let now = 0, scheduled, randomState = 1;
 const math = Object.create(Math);
 math.random = openField ? () => .5 :
  () => ((randomState = Math.imul(randomState, 1664525) + 1013904223 | 0) >>> 0) / 0x100000000;
 const context = vm.createContext({
  window, document, location: new URL(url), URL, WebSocket, Math: math,
  localStorage: {getItem: () => 'Saved pilot'}, performance: {now: () => now},
  requestAnimationFrame: callback => { scheduled = callback; return 1; },
  cancelAnimationFrame: () => { scheduled = undefined; },
  setTimeout: () => 1, clearTimeout() {},
 });
 vm.runInContext(readFileSync(assetPath('infinite-maze.js'), 'utf8'), context);
 vm.runInContext(readFileSync(assetPath('netcode.js'), 'utf8'), context);
 window.leqraNet = context.leqraNet;
 const game = readFileSync(assetPath('game.js'), 'utf8');
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
  window.leqraInfiniteMaze = {cellSize: 84, create: () => ({wallsNear: () => [], blocked: () => false})};
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
 return {infinity: window.leqraInfinity, byID, sockets, advance, window, state:window.testArena, sounds};
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
 advance(156);
 assert.match(status.textContent, /Weapons live/);
 assert.equal(byID('infiniteKills').textContent, 'Score -1');
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

test('offline Infinity grenades steer at half the missile rate', () => {
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
 assert.ok(Math.abs(Math.atan2(grenade.vy, grenade.vx) - missileTurn/2) < 1e-12);
 infinity.close();
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

test('offline Infinity equips maze pickups and sounds a weapon before another frame arrives online', () => {
 const {infinity, byID, sockets, advance, state, sounds} = harness(undefined, true);
 infinity.start('offline');
 const tank = state().tanks[0];
 state().pickups.push({x:tank.x,y:tank.y,type:'shield',life:30});
 advance();
 assert.equal(tank.shieldCharges, 1);
 assert.equal(byID('infiniteWeapon').textContent, 'shield');
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
 assert.equal(socket.sent.at(-1).forward, false);
 assert.equal(socket.readyState, 3);
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
 const stick=byID('infiniteStick'),fire=byID('infiniteFire');
 stick.setPointerCapture=fire.setPointerCapture=()=>{throw new Error('Pointer capture unavailable');};
 stick.emit('pointerdown',{button:0,pointerId:1,clientX:80,clientY:48});
 window.emit('pointermove',{pointerId:1,clientX:48,clientY:145});
 fire.emit('pointerdown',{button:0,pointerId:2});
 assert.equal(fire.classes.has('held'),true);
 assert.equal(socket.sent.at(-1).stickY,1);
 assert.equal(socket.sent.at(-1).fire,true);
 window.emit('pointercancel',{pointerId:2});
 assert.equal(socket.sent.at(-1).stickY,1);
 assert.equal(socket.sent.at(-1).fire,false);
 window.emit('pagehide');
 assert.equal(socket.sent.at(-1).stickY,0);
 assert.equal(socket.sent.at(-1).fire,false);
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
