(() => {
'use strict';

const byID = id => document.getElementById(id);
const arena = byID('infiniteArena');
const canvas = byID('infiniteCanvas');
const stick = byID('infiniteStick');
const knob = byID('infiniteKnob');
const fire = byID('infiniteFire');
const status = byID('infiniteStatus');
const personalScore = byID('infiniteKills');
const leaderboard = byID('infiniteLeaderboard');
const retry = byID('infiniteRetry');
const geometry = window.leqraInfiniteMaze;
const ctx = canvas?.getContext('2d', {alpha: false});
if (!arena || !geometry || !ctx) return;

const STEP = 1 / 60;
const CELL = geometry.cellSize;
const RADIUS = 17;
const BULLET_RADIUS = 3.5;
const COLORS = ['#d2f65a', '#ff9679', '#73cee4', '#c5a2ff', '#ffc46b', '#ff83bd', '#75f0cb', '#b7c6ee'];
const TAU = Math.PI * 2;
const MAX_BOTS = 7;
const KEYS = {
 ArrowUp: 'forward', KeyW: 'forward', ArrowDown: 'reverse', KeyS: 'reverse',
 ArrowLeft: 'left', KeyA: 'left', ArrowRight: 'right', KeyD: 'right',
 Space: 'fire', Enter: 'fire', KeyQ: 'fire', KeyC: 'fire',
};
const pressed = new Set();
const touchAim = {x: 0, y: 0};
let session = null, frame = 0, socket = null, mouseAim = null, fireTap = false;
let stickPointer = null, firePointer = null, mousePointer = null;
let lastTime = 0, accumulator = 0, nextSend = 0, connectTimer = 0;

const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
const angleOf = n => Math.atan2(Math.sin(n), Math.cos(n));
const between = (a, b) => a + Math.random() * (b - a);
const cellCenter = n => (Math.floor(n / CELL) + .5) * CELL;

function pilotName() {
 try {
  return localStorage.getItem('leqra.name')?.trim() || 'Pilot';
 } catch {
  return 'Pilot';
 }
}

function setStatus(text) {
 if (status.textContent !== text) status.textContent = text;
}

function makeTank(id, x, y, bot = false) {
 return {
  id, x, y, bot, angle: between(-Math.PI, Math.PI), hp: 3, score: 0,
  colorIndex: bot ? 1 + Math.floor(Math.random() * (COLORS.length - 1)) : 0,
  name: bot ? 'Bot ' + id.slice(4) : pilotName(), cooldown: 0, protection: 1, respawn: 0,
  course: null, nextDecision: 0,
 };
}

function inputState() {
 const input = {
  type: 'input', forward: false, reverse: false, left: false, right: false,
  stickX: touchAim.x, stickY: touchAim.y, aimOnly: false,
  fire: fireTap || mousePointer !== null || firePointer !== null,
 };
 for (const code of pressed) input[session.keys[code]] = true;
 if (stickPointer === null && mouseAim && !input.left && !input.right) {
  input.stickX = mouseAim.x;
  input.stickY = mouseAim.y;
  input.aimOnly = true;
 }
 return input;
}

function drive(tank, input, maze, dt) {
 let throttle = Number(!!input.forward) - .72 * Number(!!input.reverse);
 let turn = (Number(!!input.right) - Number(!!input.left)) * 3.65 * dt;
 const magnitude = Math.hypot(input.stickX, input.stickY);
 if (magnitude > .1) {
  const diff = angleOf(Math.atan2(input.stickY, input.stickX) - tank.angle);
  turn = clamp(diff, -5.8 * dt, 5.8 * dt);
  if (!input.aimOnly) throttle = Math.min(1, magnitude) * Math.max(0, Math.cos(diff));
 }
 tank.angle = angleOf(tank.angle + turn);
 const dx = Math.cos(tank.angle) * throttle * 128 * dt;
 const dy = Math.sin(tank.angle) * throttle * 128 * dt;
 if (dx && !maze.blocked(tank.x + dx, tank.y, RADIUS)) tank.x += dx;
 if (dy && !maze.blocked(tank.x, tank.y + dy, RADIUS)) tank.y += dy;
}

function axisHit(origin, delta, min, max) {
 if (Math.abs(delta) < 1e-9) return origin < min || origin > max ? [Infinity, -Infinity] : [-Infinity, Infinity];
 const a = (min - origin) / delta, b = (max - origin) / delta;
 return [Math.min(a, b), Math.max(a, b)];
}

function wallHit(maze, x, y, dx, dy, radius) {
 let hit = null;
 for (const wall of maze.wallsNear(Math.min(x, x + dx) - radius, Math.min(y, y + dy) - radius,
                                Math.max(x, x + dx) + radius, Math.max(y, y + dy) + radius)) {
  const [x0, x1] = axisHit(x, dx, wall.x - radius, wall.x + wall.w + radius);
  const [y0, y1] = axisHit(y, dy, wall.y - radius, wall.y + wall.h + radius);
  const entry = Math.max(x0, y0), exit = Math.min(x1, y1);
  if (entry < -.0001 || entry > 1 || entry > exit) continue;
  const fraction = Math.max(0, entry);
  const nx = x0 >= y0 - 1e-7 ? -Math.sign(dx) : 0;
  const ny = y0 >= x0 - 1e-7 ? -Math.sign(dy) : 0;
  if (!hit || fraction < hit.fraction - 1e-7) hit = {fraction, nx, ny};
  else if (Math.abs(fraction - hit.fraction) < 1e-7) {
   if (nx) hit.nx = nx;
   if (ny) hit.ny = ny;
  }
 }
 return hit;
}

function tankHit(tanks, bullet, dx, dy, limit) {
 let hit = null;
 const a = dx * dx + dy * dy;
 const radius = RADIUS + BULLET_RADIUS;
 for (const tank of tanks) {
  if (tank.id === bullet.owner || !tank.hp || tank.protection > 0) continue;
  const px = bullet.x - tank.x, py = bullet.y - tank.y;
  const b = px * dx + py * dy, c = px * px + py * py - radius * radius;
  const discriminant = b * b - a * c;
  if (c > 0 && (b >= 0 || discriminant < 0)) continue;
  const fraction = c <= 0 ? 0 : (-b - Math.sqrt(discriminant)) / a;
  if (fraction >= 0 && fraction < limit) {
   limit = fraction;
   hit = tank;
  }
 }
 return hit;
}

function fireShot(world, tank) {
 tank.cooldown = 21 * STEP;
 const ux = Math.cos(tank.angle), uy = Math.sin(tank.angle);
 const bullet = {
  id: ++world.lastBullet, owner: tank.id, x: tank.x, y: tank.y,
  vx: ux * 282, vy: uy * 282, life: 5.3, bounces: 0,
 };
 if (advanceBullet(world, bullet, 28 / 282)) world.bullets.push(bullet);
}

function advanceBullet(world, bullet, remaining) {
 while (remaining > 0.000001) {
  const dx = bullet.vx * remaining, dy = bullet.vy * remaining;
  const wall = wallHit(world.maze, bullet.x, bullet.y, dx, dy, BULLET_RADIUS);
  const target = tankHit(world.tanks, bullet, dx, dy, wall?.fraction ?? 1.00001);
  if (target) {
   if (--target.hp === 0) {
    target.respawn = 2.5;
    target.score--;
    const owner = world.tanks.find(tank => tank.id === bullet.owner);
    if (owner) owner.score++;
   }
   return false;
  }
  if (!wall) {
   bullet.x += dx;
   bullet.y += dy;
   return true;
  }
  if (++bullet.bounces > 3) return false;
  bullet.x += dx * wall.fraction + wall.nx * .12;
  bullet.y += dy * wall.fraction + wall.ny * .12;
  if (wall.nx) bullet.vx *= -1;
  if (wall.ny) bullet.vy *= -1;
  remaining *= 1 - wall.fraction;
 }
 return true;
}

function clearCell(world, origin, min, max, clearance) {
 for (let i = 0; i < 30; i++) {
  const direction = between(0, TAU), distance = between(min, max);
  const x = cellCenter(origin.x + Math.cos(direction) * distance);
  const y = cellCenter(origin.y + Math.sin(direction) * distance);
  if (world.tanks.every(tank => !tank.hp || Math.hypot(tank.x - x, tank.y - y) >= clearance)) return {x, y};
 }
 return null;
}

const NEIGHBORS = [[CELL, 0], [-CELL, 0], [0, CELL], [0, -CELL]];

function botCourse(maze, bot, player) {
 const origin = {x: cellCenter(bot.x), y: cellCenter(bot.y)};
 const goalX = cellCenter(player.x), goalY = cellCenter(player.y);
 const visits = new Set([origin.x + ',' + origin.y]);
 const queue = [{...origin, step: null}];
 let nearest = null, nearestDistance = Infinity;
 for (let i = 0; i < queue.length; i++) {
  const {x, y, step} = queue[i];
  if (step) {
   const distance = Math.hypot(goalX - x, goalY - y);
   if (distance < nearestDistance) {
    nearestDistance = distance;
    nearest = step;
   }
   if (distance === 0) break;
  }
  for (const [dx, dy] of NEIGHBORS) {
   const nx = x + dx, ny = y + dy, key = nx + ',' + ny;
   if (Math.abs(nx - origin.x) > 4 * CELL || Math.abs(ny - origin.y) > 4 * CELL ||
       visits.has(key) || maze.blocked(x + dx / 2, y + dy / 2, RADIUS)) continue;
   visits.add(key);
   queue.push({x: nx, y: ny, step: step || {x: nx, y: ny}});
  }
 }
 return nearest;
}

function botInput(world, tank, pilot) {
 const dx = pilot.x - tank.x, dy = pilot.y - tank.y, distance = Math.hypot(dx, dy);
 const seesPilot = pilot.hp && distance < CELL * 6 && !wallHit(world.maze, tank.x, tank.y, dx, dy, BULLET_RADIUS);
 if (!seesPilot && world.time >= tank.nextDecision) {
  tank.course = botCourse(world.maze, tank, pilot);
  tank.nextDecision = world.time + between(.25, .5);
 }
 const tx = seesPilot ? dx : (tank.course?.x ?? tank.x) - tank.x;
 const ty = seesPilot ? dy : (tank.course?.y ?? tank.y) - tank.y;
 const aim = Math.atan2(ty, tx);
 return {
  stickX: Math.cos(aim), stickY: Math.sin(aim), aimOnly: Math.hypot(tx, ty) < 5 || seesPilot && distance < 115,
  fire: seesPilot && Math.abs(angleOf(aim - tank.angle)) < .16,
 };
}

function offlineStep(world, input, dt) {
 world.time += dt;
 const pilot = world.tanks[0];
 world.tanks = world.tanks.filter(tank => !tank.bot || Math.hypot(pilot.x - tank.x, pilot.y - tank.y) < CELL * 16);
 if (world.time >= world.nextBot && world.tanks.length <= MAX_BOTS) {
  const point = clearCell(world, pilot, 2.4 * CELL, 5.7 * CELL, 1.9 * CELL);
  if (point) world.tanks.push(makeTank('bot-' + ++world.lastBot, point.x, point.y, true));
  world.nextBot = world.time + between(1.2, 3.4);
 }
 for (const tank of world.tanks) {
  if (!tank.hp) {
   tank.respawn -= dt;
   if (tank.respawn <= 0) {
    const point = clearCell(world, tank, 2 * CELL, 5 * CELL, 1.9 * CELL);
    if (point) Object.assign(tank, point, {hp: 3, protection: 1, cooldown: 0, course: null, nextDecision: 0});
   }
   continue;
  }
  tank.cooldown -= dt;
  tank.protection -= dt;
  const controls = tank.bot ? botInput(world, tank, pilot) : input;
  drive(tank, controls, world.maze, dt);
  if (controls.fire && tank.cooldown <= 0 && tank.protection <= 0) fireShot(world, tank);
 }
 world.bullets = world.bullets.filter(bullet => {
  bullet.life -= dt;
  return bullet.life > 0 && advanceBullet(world, bullet, dt);
 });
}

function setupBindings(bindings) {
 if (!bindings) return KEYS;
 const layout = Array.isArray(bindings) ? bindings : [bindings];
 const keys = {};
 for (const entry of layout) {
  for (const action of ['forward', 'reverse', 'left', 'right', 'fire', 'fireAlt']) {
   if (entry?.[action]) keys[entry[action]] = action === 'fireAlt' ? 'fire' : action;
  }
 }
 return Object.keys(keys).length ? keys : KEYS;
}

function updateHint(keys) {
 const hint = byID('infiniteControlsHint');
 if (!hint) return;
 if (window.matchMedia('(pointer: coarse)').matches) {
  hint.textContent = 'Drag the stick to move and aim. Tap or hold Fire.';
  return;
 }
 const arrows = {ArrowUp: '↑', ArrowDown: '↓', ArrowLeft: '←', ArrowRight: '→'};
 const label = code => arrows[code] || code.replace(/^(Key|Digit)/, '').replace(/^Numpad/, 'Num ');
 const codes = action => Object.keys(keys).filter(code => keys[code] === action).map(label).join('/');
 hint.textContent = `Move ${codes('forward')} or ${codes('reverse')} · Turn ${codes('left')} or ${codes('right')} · Aim with the mouse · Click or press ${codes('fire')} to fire`;
}

function interpolate(previous, current, alpha) {
 if (!previous || previous.hp === 0 || current.hp === 0 ||
     Math.hypot(previous.x - current.x, previous.y - current.y) > CELL) return current;
 return {
  ...current,
  x: previous.x + (current.x - previous.x) * alpha,
  y: previous.y + (current.y - previous.y) * alpha,
  angle: previous.angle + angleOf(current.angle - previous.angle) * alpha,
 };
}

function drawTank(tank, mine) {
 const color = mine ? COLORS[0] : COLORS[tank.colorIndex] || COLORS[1];
 ctx.save();
 ctx.translate(tank.x, tank.y);
 if (mine || tank.protected || tank.protection > 0) {
  ctx.strokeStyle = tank.protected || tank.protection > 0 ? '#f3f6e6' : color;
  ctx.lineWidth = 1.5;
  ctx.globalAlpha = .8;
  ctx.beginPath();
  ctx.arc(0, 0, 23, 0, TAU);
  ctx.stroke();
  ctx.globalAlpha = 1;
 }
 ctx.save();
 ctx.rotate(tank.angle);
 ctx.fillStyle = '#090d12';
 ctx.fillRect(-16, -15, 30, 7);
 ctx.fillRect(-16, 8, 30, 7);
 ctx.fillStyle = color;
 ctx.fillRect(-13, -11, 25, 22);
 ctx.fillRect(1, -3, 21, 6);
 ctx.fillStyle = '#20272b';
 ctx.fillRect(-6, -6, 12, 12);
 ctx.fillStyle = color;
 ctx.fillRect(-3, -3, 6, 6);
 ctx.restore();
 ctx.fillStyle = '#070b10';
 ctx.fillRect(-14, 25, 28, 3);
 ctx.fillStyle = color;
 ctx.fillRect(-14, 25, 28 * tank.hp / 3, 3);
 ctx.font = '600 12px system-ui, sans-serif';
 ctx.textAlign = 'center';
 ctx.fillStyle = '#f3f6e6';
 ctx.fillText(mine ? 'YOU' : tank.name, 0, -27, 120);
 ctx.restore();
}

function renderScores(world, pilot) {
 if (personalScore) {
  const count = 'Score ' + (pilot?.score ?? 0);
  if (personalScore.textContent !== count) personalScore.textContent = count;
 }
 if (!leaderboard) return;
 const entries = world.online ? world.leaderboard :
  [...world.tanks].sort((a, b) => b.score - a.score || Number(a.bot) - Number(b.bot)).slice(0, 10);
 const rows = entries.map(tank => [tank.name, tank.score, tank.id === world.id]);
 const signature = JSON.stringify(rows);
 if (signature === world.scoreRows) return;
 world.scoreRows = signature;
 leaderboard.replaceChildren(...rows.map(([name, score, mine]) => {
  const row = document.createElement('li');
  const callsign = document.createElement('span');
  const total = document.createElement('strong');
  callsign.textContent = mine ? name + ' (you)' : name;
  total.textContent = score;
  row.append(callsign, total);
  return row;
 }));
}

function draw(world, now) {
 const width = canvas.clientWidth, height = canvas.clientHeight;
 if (!width || !height) return;
 const ratio = Math.min(window.devicePixelRatio || 1, 2, Math.sqrt(4e6 / (width * height)));
 const pixelsX = Math.round(width * ratio), pixelsY = Math.round(height * ratio);
 if (canvas.width !== pixelsX || canvas.height !== pixelsY) {
  canvas.width = pixelsX;
  canvas.height = pixelsY;
 }
 ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
 ctx.fillStyle = '#10181d';
 ctx.fillRect(0, 0, width, height);
 if (!world.maze) return;
 const alpha = clamp((now - world.arrived) / world.interval, 0, 1);
 const tanks = world.online ? world.tanks.map(tank => interpolate(world.previousTanks.get(tank.id), tank, alpha)) : world.tanks;
 const pilot = tanks.find(tank => tank.id === world.id);
 if (pilot) world.camera = {x: pilot.x, y: pilot.y};
 const {x, y} = world.camera;
 const zoom = clamp(Math.min(width, height) / (CELL * 5), .7, 1.2);
 const x0 = x - width / (2 * zoom), y0 = y - height / (2 * zoom);
 const x1 = x + width / (2 * zoom), y1 = y + height / (2 * zoom);
 ctx.translate(width / 2, height / 2);
 ctx.scale(zoom, zoom);
 ctx.translate(-x, -y);
 ctx.strokeStyle = '#202d34';
 ctx.lineWidth = 1;
 ctx.beginPath();
 for (let gridX = Math.ceil(x0 / CELL) * CELL; gridX < x1; gridX += CELL) {
  ctx.moveTo(gridX, y0);
  ctx.lineTo(gridX, y1);
 }
 for (let gridY = Math.ceil(y0 / CELL) * CELL; gridY < y1; gridY += CELL) {
  ctx.moveTo(x0, gridY);
  ctx.lineTo(x1, gridY);
 }
 ctx.stroke();
 ctx.fillStyle = '#577174';
 for (const wall of world.maze.wallsNear(x0, y0, x1, y1)) ctx.fillRect(wall.x, wall.y, wall.w, wall.h);
 ctx.fillStyle = '#ffdb85';
 ctx.beginPath();
 for (const bullet of world.bullets) {
  const previous = world.previousBullets?.get(bullet.id);
  const bx = previous ? previous.x + (bullet.x - previous.x) * alpha : bullet.x;
  const by = previous ? previous.y + (bullet.y - previous.y) * alpha : bullet.y;
  ctx.moveTo(bx + BULLET_RADIUS, by);
  ctx.arc(bx, by, BULLET_RADIUS, 0, TAU);
 }
 ctx.fill();
 for (const tank of tanks) {
  if (tank.hp && tank.x > x0 - CELL && tank.x < x1 + CELL && tank.y > y0 - CELL && tank.y < y1 + CELL) {
   drawTank(tank, tank.id === world.id);
  }
 }
 if (!pilot || world.failed || world.online && !world.joined) return;
 renderScores(world, pilot);
 const counts = world.online ? ` · ${world.players} online` : ` · ${world.tanks.length - 1} bots`;
 setStatus((pilot.hp ? `Health ${pilot.hp}/3` : 'Respawning…') + counts);
}

function sendInput(now = performance.now(), immediate = false) {
 if (!session?.online || !session.joined || socket?.readyState !== WebSocket.OPEN ||
     socket.bufferedAmount > 4096 || (!immediate && now < nextSend)) return;
 socket.send(JSON.stringify(inputState()));
 fireTap = false;
 nextSend = now + 1000 / 30;
}

function loop(now) {
 if (!arena.open || !session) return;
 if (session.online) {
  sendInput(now);
 } else {
  accumulator += Math.min(.1, (now - lastTime) / 1000);
  while (accumulator >= STEP) {
   offlineStep(session, inputState(), STEP);
   fireTap = false;
   accumulator -= STEP;
  }
 }
 lastTime = now;
 draw(session, now);
 frame = requestAnimationFrame(loop);
}

function connectionFailed(message) {
 if (!session?.online) return;
 clearTimeout(connectTimer);
 session.failed = true;
 session.joined = false;
 setStatus(message + (session.room ? ' Leave to return to your room.' :
  ' Choose Infinity in Room settings to play offline.'));
 if (retry) retry.hidden = false;
 socket?.close();
}

function receive(ws, event) {
 if (ws !== socket || !session?.online || session.failed) return;
 let message;
 try {
  message = JSON.parse(event.data);
  if (!message || typeof message.type !== 'string') throw new Error('Invalid Infinity packet');
 } catch {
  connectionFailed('Unexpected response from the Infinity server.');
  return;
 }
 if (message.type === 'error') {
  connectionFailed(message.message || 'Unable to join Infinity.');
  return;
 }
 if (message.type === 'welcome') {
  session.id = message.id;
  session.maze = geometry.create(message.seed);
  return;
 }
 if (message.type !== 'state' || !session.maze) return;
 if (!Array.isArray(message.tanks) || !Array.isArray(message.bullets) || !Array.isArray(message.leaderboard)) {
  connectionFailed('Unexpected state from the Infinity server.');
  return;
 }
 const now = performance.now();
 session.previousTanks = new Map(session.tanks.map(tank => [tank.id, tank]));
 session.previousBullets = new Map(session.bullets.map(bullet => [bullet.id, bullet]));
 session.interval = clamp(now - session.arrived, 25, 90);
 session.arrived = now;
 session.tanks = message.tanks;
 session.bullets = message.bullets;
 session.players = message.players;
 session.leaderboard = message.leaderboard;
 session.joined = true;
 clearTimeout(connectTimer);
}

function connect() {
 if (!session?.online) return;
 clearTimeout(connectTimer);
 const oldSocket = socket;
 socket = null;
 oldSocket?.close();
 session.failed = false;
 session.joined = false;
 session.maze = null;
 session.tanks = [];
 session.bullets = [];
 session.leaderboard = [];
 renderScores(session, null);
 if (retry) retry.hidden = true;
 if (location.protocol !== 'http:' && location.protocol !== 'https:') {
  connectionFailed('Online Infinity requires the leqra server.');
  if (retry) retry.hidden = true;
  return;
 }
 setStatus(session.room ? 'Connecting to room Infinity…' : 'Connecting to Infinity…');
 const url = new URL('/ws/infinite', location.href);
 url.protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
 let ws;
 try {
  ws = socket = new WebSocket(url);
 } catch {
  connectionFailed('Could not connect to Infinity.');
  return;
 }
 ws.addEventListener('open', () => {
  if (ws === socket && session) {
   ws.send(JSON.stringify({type: 'join', version: window.leqra.version, name: session.name, ...session.room}));
  }
 });
 ws.addEventListener('message', event => receive(ws, event));
 ws.addEventListener('close', () => {
  if (ws === socket && session && !session.failed) {
   connectionFailed(session.joined ? 'Disconnected from Infinity.' : 'Could not join Infinity.');
  }
 });
 connectTimer = setTimeout(() => {
  if (ws === socket && session && !session.joined) connectionFailed('Could not connect to Infinity.');
 }, 6500);
}

function resetControls() {
 pressed.clear();
 mouseAim = null;
 fireTap = false;
 stickPointer = firePointer = mousePointer = null;
 fire.classList.remove('held');
 touchAim.x = touchAim.y = 0;
 knob.style.removeProperty('--stick-x');
 knob.style.removeProperty('--stick-y');
 sendInput(performance.now(), true);
}

function stop() {
 resetControls();
 cancelAnimationFrame(frame);
 clearTimeout(connectTimer);
 const ws = socket;
 socket = null;
 session = null;
 ws?.close();
}

function start(mode, options = {}) {
 if ((mode !== 'offline' && mode !== 'online') || arena.open) return;
 stop();
 const online = mode === 'online', name = options.name?.trim() || pilotName();
 session = {
  online, name, keys: setupBindings(options.bindings), id: 'pilot', tanks: [], bullets: [], leaderboard: [],
  room: online && options.code && options.token ? {code: options.code, token: options.token} : null,
  camera: {x: CELL / 2, y: CELL / 2}, previousTanks: new Map(), previousBullets: new Map(),
  time: 0, nextBot: between(.4, 1.2), lastBot: 0, lastBullet: 0,
 };
 if (retry) retry.hidden = true;
 arena.dataset.mode = mode;
 updateHint(session.keys);
 arena.showModal();
 canvas.focus({preventScroll: true});
 if (online) {
  connect();
 } else {
  session.maze = geometry.create(Math.floor(Math.random() * 0x100000000));
  const player = makeTank(session.id, session.camera.x, session.camera.y);
  player.name = name;
  session.tanks.push(player);
  setStatus('Health 3/3 · 0 bots');
  renderScores(session, player);
 }
 lastTime = performance.now();
 accumulator = nextSend = 0;
 frame = requestAnimationFrame(loop);
}

function updateMouse(event) {
 const rect = canvas.getBoundingClientRect();
 const x = event.clientX - rect.left - rect.width / 2, y = event.clientY - rect.top - rect.height / 2;
 const distance = Math.hypot(x, y);
 if (distance > 3) mouseAim = {x: x / distance, y: y / distance};
}

function pressFire() {
 fireTap = true;
 sendInput(performance.now(), true);
}

function updateStick(event) {
 const rect = stick.getBoundingClientRect(), reach = Math.min(rect.width, rect.height) * .34;
 if (!reach) return;
 const x = event.clientX - rect.left - rect.width / 2, y = event.clientY - rect.top - rect.height / 2;
 const magnitude = Math.max(reach, Math.hypot(x, y));
 touchAim.x = x / magnitude;
 touchAim.y = y / magnitude;
 knob.style.setProperty('--stick-x', touchAim.x * reach + 'px');
 knob.style.setProperty('--stick-y', touchAim.y * reach + 'px');
}

function capturePointer(element, event) {
 event.preventDefault();
 element.setPointerCapture(event.pointerId);
}

function endPointer(event) {
 if (event.pointerId === stickPointer) {
  stickPointer = null;
  touchAim.x = touchAim.y = 0;
  knob.style.removeProperty('--stick-x');
  knob.style.removeProperty('--stick-y');
 } else if (event.pointerId === firePointer) {
  firePointer = null;
  fire.classList.remove('held');
 } else if (event.pointerId === mousePointer) {
  mousePointer = null;
 } else {
  return;
 }
 sendInput(performance.now(), true);
}

arena.addEventListener('keydown', event => {
 if (!session) return;
 event.stopPropagation();
 const action = session.keys[event.code];
 if (!action || event.ctrlKey || event.metaKey || event.altKey ||
     (event.code === 'Enter' || event.code === 'Space') && event.target.closest('button, a, input, summary')) return;
 event.preventDefault();
 if (pressed.has(event.code)) return;
 pressed.add(event.code);
 if (action === 'left' || action === 'right') mouseAim = null;
 if (action === 'fire') pressFire();
});
arena.addEventListener('keyup', event => {
 if (!pressed.delete(event.code)) return;
 event.preventDefault();
 sendInput(performance.now(), true);
});
canvas.addEventListener('pointermove', event => {
 if (event.pointerType !== 'mouse') return;
 updateMouse(event);
 if (!(event.buttons & 1)) endPointer(event);
});
canvas.addEventListener('pointerleave', event => {
 if (event.pointerType === 'mouse' && mousePointer === null) mouseAim = null;
});
canvas.addEventListener('pointerdown', event => {
 if (event.pointerType !== 'mouse' || event.button !== 0 || mousePointer !== null) return;
 canvas.focus({preventScroll: true});
 capturePointer(canvas, event);
 updateMouse(event);
 mousePointer = event.pointerId;
 pressFire();
});
stick.addEventListener('pointerdown', event => {
 if (event.button !== 0 || stickPointer !== null) return;
 capturePointer(stick, event);
 mouseAim = null;
 stickPointer = event.pointerId;
 updateStick(event);
});
stick.addEventListener('pointermove', event => {
 if (event.pointerId === stickPointer) updateStick(event);
});
fire.addEventListener('pointerdown', event => {
 if (event.button !== 0 || firePointer !== null) return;
 capturePointer(fire, event);
 firePointer = event.pointerId;
 fire.classList.add('held');
 pressFire();
});
fire.addEventListener('click', event => {
 // Keyboard and assistive activation has no pointer press to queue the shot.
 if (event.detail === 0) pressFire();
});
// A second touch can make Safari lose element-level capture.
for (const event of ['pointerup', 'pointercancel', 'lostpointercapture']) {
 window.addEventListener(event, endPointer, true);
}
arena.addEventListener('contextmenu', event => event.preventDefault());
function close() {
 if (!arena.open) return;
 arena.close();
 stop();
}
byID('infiniteExit').addEventListener('click', close);
retry?.addEventListener('click', () => {
 canvas.focus({preventScroll: true});
 connect();
});
arena.addEventListener('close', () => {
 if (!arena.open) stop();
});
window.addEventListener('blur', resetControls);
document.addEventListener('visibilitychange', () => {
 if (document.hidden) resetControls();
});

window.leqraInfinity = Object.freeze({start, close});
})();
