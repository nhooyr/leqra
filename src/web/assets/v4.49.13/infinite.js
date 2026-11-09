(() => {
'use strict';

const byID = id => document.getElementById(id);
const arena = byID('infiniteArena');
const pauseMenu = byID('infinitePauseMenu');
const controlsDialog = byID('controlsDialog');
const canvas = byID('infiniteCanvas');
const stick = byID('infiniteStick');
const knob = byID('infiniteKnob');
const fire = byID('infiniteFire');
const status = byID('infiniteStatus');
const personalScore = byID('infiniteKills');
const weapon = byID('infiniteWeapon');
const localWeapon = byID('infiniteLocalWeapon');
const leaderboard = byID('infiniteLeaderboard');
const teamLeaderboard = byID('infiniteTeamScores');
const resultDialog = byID('infiniteResult');
const retry = byID('infiniteRetry');
const geometry = window.leqraInfiniteMaze;
const art = window.leqraInfinityArt;
const net = window.leqraNet;
const ctx = canvas?.getContext('2d', {alpha: false});
if (!arena || !geometry || !ctx || !art || !net) return;

const STEP = 1 / 60;
const CELL = geometry.cellSize;
const RADIUS = 17;
const BULLET_RADIUS = 3.5;
const COLORS = art.colors, powers = art.powers, powerTypes = Object.keys(powers);
const POWER_DURATION = 15, STAR_DURATION = 8, SHOT_RANGE = 18 * CELL, BLAST_RADIUS = 220;
const PROJECTILES = Object.freeze({
 regular: {speed: 282, r: BULLET_RADIUS, life: 5.3, cooldown: .34, ammo: 5},
 rapid: {speed: 846, r: BULLET_RADIUS / 3, life: SHOT_RANGE / 846, cooldown: 0, ammo: 115},
 scatter: {speed: 846, r: BULLET_RADIUS, life: 3.9, cooldown: .54, ammo: 12},
 homing: {speed: 235, r: 5, life: SHOT_RANGE / 235, cooldown: .72, ammo: 3},
 grenade: {speed: 205, r: 6, life: 10, cooldown: .8, ammo: 3},
 cannon: {speed: 1128, r: 14, life: 5.3, cooldown: .85, ammo: 3},
 laser: {r: 3, cooldown: .85},
});
const TAU = Math.PI * 2;
const MAX_BOTS = 7;
const PRIMARY_KEYS = {KeyW:'forward', KeyS:'reverse', KeyA:'left', KeyD:'right', KeyQ:'fire', KeyC:'fire'};
const LOCAL_KEYS = {ArrowUp:'forward', ArrowDown:'reverse', ArrowLeft:'left', ArrowRight:'right', Space:'fire', Enter:'fire'};
const pressed = new Set();
const touchAim = {x: 0, y: 0};
let session = null, frame = 0, socket = null, mouseAim = null;
let stickPointer = null, firePointer = null, mousePointer = null;
let lastTime = 0, accumulator = 0, connectTimer = 0;

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
  id, x, y, bot, angle: between(-Math.PI, Math.PI), hp: 1, alive: true, score: 0,
  colorIndex: bot ? 1 + Math.floor(Math.random() * (COLORS.length - 1)) : 0,
  name: bot ? 'Bot ' + id.slice(4) : pilotName(), cooldown: 0, invulnerable: 1, respawn: 0,
  track: 0, recoil: 0, speedStacks: 0, spawnSerial: 1,
  course: null, nextDecision: 0,
 };
}

function teamName(world, team) {
 return world.rules?.teamNames?.[team - 1] || 'Team ' + team;
}

function nextBotTeam(world) {
 const counts = [0,0,0,0];
 for (const tank of world.tanks) if (tank.team) counts[tank.team - 1]++;
 let team = 0;
 for (let i = 1; i < counts.length; i++) if ((i === 1 || counts[i]) && counts[i] < counts[team]) team = i;
 return team + 1;
}

function setTeam(world, tank, team) {
 if (world.rules?.teamMode !== 'teams') return;
 tank.team = team || nextBotTeam(world);
 tank.colorIndex = world.rules.teamColors?.[tank.team - 1] ?? tank.team - 1;
}

function inputState(seat) {
 const input = {
  type: 'input', paused: pauseMenu.open, forward: false, reverse: false, left: false, right: false,
  stickX: 0, stickY: 0, aimOnly: false, fire: false,
 };
 if (input.paused) return input;
 input.fire = seat.fireTap;
 for (const code of pressed) if (seat.keys[code]) input[seat.keys[code]] = true;
 if (seat === session) {
  input.stickX = touchAim.x;
  input.stickY = touchAim.y;
  input.fire ||= mousePointer !== null || firePointer !== null;
  if (stickPointer === null && mouseAim && !input.left && !input.right) {
   input.stickX = mouseAim.x;
   input.stickY = mouseAim.y;
   input.aimOnly = true;
  }
 }
 return input;
}

function phaseExit(tank, maze) {
 if (!maze.blocked(tank.x, tank.y, RADIUS)) return;
 const cx = Math.floor(tank.x / CELL), cy = Math.floor(tank.y / CELL), margin = 4 + RADIUS + .01;
 let nearest = Infinity, x = tank.x, y = tank.y;
 for (let row = cy - 1; row <= cy + 1; row++) for (let col = cx - 1; col <= cx + 1; col++) {
  const xx = clamp(tank.x, col * CELL + margin, (col + 1) * CELL - margin);
  const yy = clamp(tank.y, row * CELL + margin, (row + 1) * CELL - margin);
  const distance = Math.hypot(xx - tank.x, yy - tank.y);
  if (distance < nearest - 1e-8) {
   nearest = distance;
   x = xx;
   y = yy;
  }
 }
 Object.assign(tank, {x, y});
}

function mazeMove(maze, tank, dx, dy, phaseEnded) {
 if (phaseEnded) {
  phaseExit(tank, maze);
  return;
 }
 if (dx && (tank.ghostTime > 0 || !maze.blocked(tank.x + dx, tank.y, RADIUS))) tank.x += dx;
 if (dy && (tank.ghostTime > 0 || !maze.blocked(tank.x, tank.y + dy, RADIUS))) tank.y += dy;
}

function axisHit(origin, delta, min, max) {
 if (Math.abs(delta) < 1e-9) return origin < min || origin > max ? [Infinity, -Infinity] : [-Infinity, Infinity];
 const a = (min - origin) / delta, b = (max - origin) / delta;
 return [Math.min(a, b), Math.max(a, b)];
}

function wallHit(maze, x, y, dx, dy, radius, includeOrigin = false) {
 let hit = null;
 for (const wall of maze.wallsNear(Math.min(x, x + dx) - radius, Math.min(y, y + dy) - radius,
                                Math.max(x, x + dx) + radius, Math.max(y, y + dy) + radius)) {
  const [x0, x1] = axisHit(x, dx, wall.x - radius, wall.x + wall.w + radius);
  const [y0, y1] = axisHit(y, dy, wall.y - radius, wall.y + wall.h + radius);
  const entry = Math.max(x0, y0), exit = Math.min(x1, y1);
  if (entry > 1 || entry > exit || (includeOrigin ? exit < 0 : entry < -.0001)) continue;
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

function canDamage(world, owner, team, target) {
 return target.id !== owner && (!team || team !== target.team || world.rules?.friendlyFire);
}

function tankHit(world, bullet, dx, dy, limit) {
 let tank = null;
 const speed2 = dx * dx + dy * dy;
 const radius = RADIUS + bullet.r;
 for (const target of world.tanks) {
  if (!target.hp || target.id === bullet.owner ||
      bullet.kind !== 'grenade' && (target.invulnerable > 0 || !canDamage(world, bullet.owner, bullet.team, target))) continue;
  const px = bullet.x - target.x, py = bullet.y - target.y;
  const dot = px * dx + py * dy, c = px * px + py * py - radius * radius;
  const discriminant = dot * dot - speed2 * c;
  if (c > 0 && (dot >= 0 || discriminant < 0)) continue;
  const fraction = c <= 0 ? 0 : (-dot - Math.sqrt(discriminant)) / speed2;
  if (fraction >= 0 && fraction < limit) {
   limit = fraction;
   tank = target;
  }
 }
 return {tank, fraction: limit};
}

function effect(world, kind, x, y, owner, points) {
 presentEffect(world, {kind, x, y, owner, points}, performance.now());
}

function hurt(world, target, ownerID, ownerTeam, starmanContact = false) {
 if (world.result || !target.hp || target.invulnerable > 0 || !canDamage(world, ownerID, ownerTeam, target)) return;
 if (target.shield > 0 && !starmanContact) {
  target.shieldCharges = Math.max(0, (target.shieldCharges || 1) - 1);
  if (!target.shieldCharges) target.shield = 0;
  target.invulnerable = .35;
  effect(world, 'shield', target.x, target.y, ownerID);
  return;
 }
 target.hp = 0;
 target.alive = false;
 target.respawn = 2.5;
 target.score--;
 const owner = world.tanks.find(tank => tank.id === ownerID);
 if (owner) owner.score++;
 if (target.team) world.teamScores[target.team - 1]--;
 if (ownerTeam) world.teamScores[ownerTeam - 1]++;
 effect(world, 'hit', target.x, target.y, ownerID);
 const targetScore = world.rules?.infinityTarget;
 if (targetScore > 0) {
  const score = ownerTeam ? world.teamScores[ownerTeam - 1] : owner?.score;
  if (score >= targetScore) world.result = {id:ownerID, team:ownerTeam, name:ownerTeam ? teamName(world,ownerTeam) : owner.name, score};
 }
}

function detonate(world, bullet) {
 bullet.dead = true;
 effect(world, 'blast', bullet.x, bullet.y, bullet.owner);
 for (const tank of world.tanks) {
  const dx = tank.x - bullet.x, dy = tank.y - bullet.y;
  if (tank.hp && tank.id !== bullet.owner && Math.hypot(dx, dy) <= BLAST_RADIUS + RADIUS &&
      !wallHit(world.maze, bullet.x, bullet.y, dx, dy, 0)) hurt(world, tank, bullet.owner, bullet.team);
 }
}

function weaponControl(world, tank, held, pressed) {
 tank.fireHeld = held;
 if (!held) tank.fireBlocked = false;
 if (pressed) {
  let detonated = false;
  for (const bullet of world.bullets) {
   if (!bullet.dead && bullet.kind === 'grenade' && bullet.owner === tank.id) {
    detonate(world, bullet);
    detonated = true;
   }
  }
  if (detonated || tank.power === 'grenade') {
   tank.fireBlocked = held;
   if (!detonated) fireShot(world, tank);
   return;
  }
 }
 if (!tank.fireBlocked && tank.power !== 'grenade' && (held || pressed)) fireShot(world, tank);
}

function spendWeapon(tank) {
 if (!tank.power || tank.starmanTime > 0) return;
 if (tank.power === 'rapid' ? --tank.machineRounds > 0 : --tank.charges > 0) return;
 Object.assign(tank, {power: '', powerTime: 0, charges: 0});
}

function traceLaser(world, tank, preview = false) {
 let {x, y} = tank;
 let ux = Math.cos(tank.angle), uy = Math.sin(tank.angle), length = SHOT_RANGE;
 const points = [];
 for (let i = 0; i < 128 && length > 1e-7; i++) {
  const dx = ux * length, dy = uy * length;
  const wall = wallHit(world.maze, x, y, dx, dy, 3);
  const limit = wall?.fraction ?? 1;
  const hit = preview ? {fraction:limit} : tankHit(world, {x, y, owner:tank.id, team:tank.team, r:3}, dx, dy, limit);
  const distance = length * hit.fraction;
  if (!i) points.push({x: x + ux * Math.min(distance, 28), y: y + uy * Math.min(distance, 28)});
  x += ux * distance;
  y += uy * distance;
  points.push({x, y});
  length -= distance;
  if (hit.tank || !wall || length <= 1e-7) return {points, target: hit.tank};
  if (wall.nx) ux = -ux;
  if (wall.ny) uy = -uy;
  const nudge = Math.min(.001, length);
  x += ux * nudge;
  y += uy * nudge;
  length -= nudge;
 }
 return {points};
}

function muzzleBlocked(maze, tank, radius) {
 const {x, y} = tank;
 return tank.ghostTime > 0 && maze.wallsNear(x-radius, y-radius, x+radius, y+radius).some(wall =>
  x >= wall.x-radius && x <= wall.x+wall.w+radius && y >= wall.y-radius && y <= wall.y+wall.h+radius);
}

function fireShot(world, tank) {
 const boosted = tank.starmanTime > 0;
 if (!boosted && (tank.cooldown > 1e-9 || tank.power === 'rapid' && !tank.machineRounds)) return;
 const kind = tank.power || '', spec = PROJECTILES[kind || 'regular'];
 if (kind !== 'cannon' && muzzleBlocked(world.maze, tank, spec.r)) return;
 const cooldown = boosted ? 0 : spec.cooldown;
 const showShot = !boosted || kind === 'grenade' || world.time + 1e-9 >= (tank.nextBoostEffect || 0);
 if (kind === 'laser') {
  const {points, target} = traceLaser(world, tank);
  Object.assign(tank, {cooldown, recoil: 1});
  if (showShot) {
   tank.nextBoostEffect = world.time + 4 * STEP;
   effect(world, 'laser', tank.x, tank.y, tank.id, points);
  }
  if (target) hurt(world, target, tank.id, tank.team);
  spendWeapon(tank);
  return;
 }
 const offsets = kind === 'scatter' ? [-.21, 0, .21] : [0];
 if (!boosted) {
  let ammo = 0;
  for (const bullet of world.bullets) if (!bullet.dead && !bullet.boosted && bullet.owner === tank.id) ammo++;
  if (ammo + offsets.length > spec.ammo) return;
 }
 Object.assign(tank, {cooldown, recoil: 1});
 for (const offset of offsets) {
  const angle = tank.angle + offset, ux = Math.cos(angle), uy = Math.sin(angle);
  const bullet = {
   ...spec, id: ++world.lastBullet, owner: tank.id, team:tank.team, kind, boosted, x: tank.x, y: tank.y, colorIndex: tank.colorIndex,
   vx: ux * spec.speed, vy: uy * spec.speed, age: 0, bounces: 0, seekDelay: 0, target: null, trail: [],
  };
  if (advanceBullet(world, bullet, (kind === 'cannon' ? RADIUS + spec.r + 1 : 28) / spec.speed)) world.bullets.push(bullet);
 }
 art.recycleStarmanProjectiles(world.bullets, tank.id, boosted);
 if (showShot && (boosted || kind !== 'rapid' || tank.machineRounds % 4 === 0)) {
  tank.nextBoostEffect = world.time + 4 * STEP;
  effect(world, 'shot:' + kind, tank.x, tank.y, tank.id);
 }
 spendWeapon(tank);
}

function advanceBullet(world, bullet, remaining) {
 for (let i = 0; i < 4 && remaining > .000001; i++) {
  const dx = bullet.vx * remaining, dy = bullet.vy * remaining;
  const wall = bullet.kind === 'cannon' ? null : wallHit(world.maze, bullet.x, bullet.y, dx, dy, bullet.r);
  const hit = tankHit(world, bullet, dx, dy, wall?.fraction ?? 1.00000001);
  if (hit.tank) {
   bullet.x += dx * hit.fraction;
   bullet.y += dy * hit.fraction;
   if (bullet.kind === 'grenade') detonate(world, bullet);
   else {
    if (bullet.kind === 'cannon' || bullet.kind === 'homing') effect(world, 'impact', bullet.x, bullet.y, bullet.owner);
    hurt(world, hit.tank, bullet.owner, bullet.team);
   }
   return false;
  }
  if (!wall) {
   bullet.x += dx;
   bullet.y += dy;
   return true;
  }
  const bounceLimit = ['homing', 'rapid', 'grenade'].includes(bullet.kind) ? 128 : 22;
  if (++bullet.bounces > bounceLimit) {
   if (bullet.kind === 'grenade') detonate(world, bullet);
   return false;
  }
  bullet.x += dx * wall.fraction + wall.nx * .12;
  bullet.y += dy * wall.fraction + wall.ny * .12;
  if (wall.nx) bullet.vx *= -1;
  if (wall.ny) bullet.vy *= -1;
  bullet.target = null;
  bullet.seekDelay = .04;
  if (nearCamera(world,bullet.x,bullet.y,CELL*7)) art.ricochet();
  remaining *= 1 - wall.fraction;
 }
 return true;
}

function guide(world, bullet, dt) {
 bullet.seekDelay = Math.max(0, bullet.seekDelay - dt);
 if (bullet.age < .1 || bullet.seekDelay > 0) return;
 let target, best = 10 * CELL;
 const speed = Math.hypot(bullet.vx, bullet.vy);
 for (const tank of world.tanks) {
  if (tank.id === bullet.owner || bullet.team && tank.team === bullet.team || !tank.hp ||
      tank.invulnerable > 0 || bullet.target !== null && tank.id !== bullet.target) continue;
  const dx = tank.x - bullet.x, dy = tank.y - bullet.y, distance = Math.hypot(dx, dy);
  if (distance >= best || dx * bullet.vx + dy * bullet.vy < -.75 * distance * speed) continue;
  if (!wallHit(world.maze, bullet.x, bullet.y, dx, dy, bullet.r)) {
   best = distance;
   target = tank;
  }
 }
 if (!target) {
  if (bullet.target !== null) bullet.seekDelay = .06;
  bullet.target = null;
  return;
 }
 bullet.target = target.id;
 const angle = Math.atan2(bullet.vy, bullet.vx);
 const maxTurn = art.missileTurn * dt;
 const turn = clamp(angleOf(Math.atan2(target.y - bullet.y, target.x - bullet.x) - angle), -maxTurn, maxTurn);
 bullet.vx = Math.cos(angle + turn) * speed;
 bullet.vy = Math.sin(angle + turn) * speed;
}

function clearCell(world, origin, min, max, clearance) {
 const clear = (x, y) => world.tanks.every(tank => !tank.hp || Math.hypot(tank.x - x, tank.y - y) >= clearance);
 for (let i = 0; i < 30; i++) {
  const direction = between(0, TAU), distance = between(min, max);
  const x = cellCenter(origin.x + Math.cos(direction) * distance);
  const y = cellCenter(origin.y + Math.sin(direction) * distance);
  if (clear(x, y)) return {x, y};
 }
 const cx = cellCenter(origin.x), cy = cellCenter(origin.y), limit = Math.ceil(max / CELL);
 for (let row = -limit; row <= limit; row++) for (let col = -limit; col <= limit; col++) {
  const x = cx + col * CELL, y = cy + row * CELL, distance = Math.hypot(x - origin.x, y - origin.y);
  if (distance >= min && distance <= max && clear(x, y)) return {x, y};
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

function botInput(world, tank, locals) {
 let pilot, best = Infinity;
 const targets = tank.team ? world.tanks : locals;
 for (const target of targets) {
  if (!target.hp || target === tank || tank.team && target.team === tank.team) continue;
  const distance = Math.hypot(target.x - tank.x, target.y - tank.y);
  if (distance < best) { pilot = target; best = distance; }
 }
 if (!pilot) return net.neutral();
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
  fire: seesPilot && !(pilot.invulnerable > 0) && Math.abs(angleOf(aim - tank.angle)) < .16,
 };
}

function populatePickups(world, locals, dt) {
 for (const pickup of world.pickups) pickup.life -= dt;
 world.pickups = world.pickups.filter(pickup => pickup.life > 0);
 if (world.time < world.nextPickup) return;
 world.nextPickup = world.time + between(1.25, 2.5);
 const pilot = locals[world.pickupPilot++ % locals.length];
 if (!pilot.hp) return;
 world.pickups = world.pickups.filter(pickup => locals.some(tank=>Math.hypot(pickup.x-tank.x,pickup.y-tank.y)<CELL*11));
 let nearby = world.pickups.filter(pickup => Math.hypot(pickup.x - pilot.x, pickup.y - pilot.y) < CELL * 5).length;
 if (nearby >= 3 || world.pickups.length >= 6) return;
 const cx = cellCenter(pilot.x), cy = cellCenter(pilot.y);
 for (let i = 0; i < 90 && nearby < 3 && world.pickups.length < 6; i++) {
  const dx = Math.floor(between(-3, 4)), dy = Math.floor(between(-3, 4));
  if (dx * dx + dy * dy > 12) continue;
  const x = cx + dx * CELL, y = cy + dy * CELL;
  if (world.tanks.some(tank => tank.hp && Math.hypot(tank.x-x, tank.y-y) < .85*CELL) ||
      world.pickups.some(pickup => Math.hypot(pickup.x-x, pickup.y-y) < 1.1*CELL)) continue;
  world.pickups.push({x, y, life: 30, type: art.choosePickup(powerTypes)});
  nearby++;
 }
}

function offlineStep(world, dt) {
 world.time += dt;
 const locals = world.tanks.slice(0, world.controllers.length);
 world.tanks = world.tanks.filter(tank => !tank.bot || locals.some(pilot=>Math.hypot(pilot.x-tank.x,pilot.y-tank.y)<CELL*16));
 if (world.time >= world.nextBot && world.tanks.length - locals.length < MAX_BOTS) {
  const pilot = locals[world.lastBot % locals.length];
  const point = clearCell(world, pilot, 2.4 * CELL, 5.7 * CELL, 1.9 * CELL);
  if (point) {
   const bot = makeTank('bot-' + ++world.lastBot, point.x, point.y, true);
   setTeam(world,bot);
   world.tanks.push(bot);
  }
  world.nextBot = world.time + between(1.2, 3.4);
 }
 populatePickups(world, locals, dt);
 for (const tank of world.tanks) {
  if (!tank.hp) {
   tank.respawn -= dt;
   if (tank.respawn <= 1e-9) {
    const point = clearCell(world, tank, 2 * CELL, 5 * CELL, 1.9 * CELL);
    if (point) {
     const fresh = makeTank(tank.id, point.x, point.y, tank.bot);
     Object.assign(tank, fresh, {name: tank.name, colorIndex: tank.colorIndex, score: tank.score,
      spawnSerial: tank.spawnSerial + 1, power: '', powerTime: 0, charges: 0, shield: 0, shieldCharges: 0,
      ghostTime: 0, speedTime: 0, starmanTime: 0, fireHeld: false, fireBlocked: false});
    }
   }
   continue;
  }
  for (const key of ['invulnerable', 'shield', 'starmanTime', 'cooldown']) {
   const value = (tank[key] || 0) - dt;
   tank[key] = value > 1e-9 ? value : 0;
  }
  if (tank.shield === 0) tank.shieldCharges = 0;
  if (!(tank.starmanTime > 0)) {
   tank.powerTime = Math.max(0, (tank.powerTime || 0) - dt);
   if (tank.powerTime <= 1e-9) Object.assign(tank, {power: '', powerTime: 0, charges: 0, machineRounds: 0});
  }
  tank.recoil = Math.max(0, tank.recoil - 9 * dt);
 }
 const actors = world.tanks.filter(tank => tank.hp);
 const tick = Math.round(world.time / STEP);
 for (let i = 0; i < actors.length; i++) {
  const tank = actors[(tick + i) % actors.length];
  if (!tank.hp) continue;
  const controls = tank.bot ? botInput(world,tank,locals) : inputState(tank.id === world.local?.id ? world.local : world);
  if (tank.bot && tank.fireBlocked) controls.fire = false;
  net.move(tank, controls, dt, world.moveTank);
  for (const pickup of world.pickups) {
   if (pickup.life <= 0 || Math.hypot(pickup.x - tank.x, pickup.y - tank.y) >= RADIUS + 13) continue;
   pickup.life = 0;
   art.grantPower(tank, pickup.type, POWER_DURATION, STAR_DURATION);
   if (tank.bot && pickup.type === 'grenade') tank.fireHeld = false;
   effect(world, 'pickup', tank.x, tank.y, tank.id);
  }
  weaponControl(world, tank, controls.fire, controls.fire && !tank.fireHeld);
  if (world.result) return;
 }
 for (let i = 0; i < actors.length; i++) {
  const attacker = actors[(tick + i) % actors.length];
  if (!attacker.hp || !(attacker.starmanTime > 0)) continue;
  for (const target of actors) {
   if (!target.hp || target.invulnerable > 0 || target.starmanTime > 0 ||
       !canDamage(world,attacker.id,attacker.team,target)) continue;
   const dx = target.x - attacker.x, dy = target.y - attacker.y;
   if (dx * dx + dy * dy <= 4 * RADIUS * RADIUS && !wallHit(world.maze, attacker.x, attacker.y, dx, dy, 0, true)) {
    hurt(world,target,attacker.id,attacker.team,true);
    if (world.result) return;
   }
  }
 }
 world.bullets = world.bullets.filter(bullet => {
  if (bullet.dead) return false;
  if (world.result) return true;
  const span = Math.min(dt, bullet.life);
  bullet.life -= span;
  bullet.age += span;
  if (bullet.kind === 'homing' || bullet.kind === 'grenade') guide(world, bullet, span);
  if (bullet.kind === 'grenade') {
   const drag = art.grenadeDragFactor(bullet.life + span, bullet.life);
   bullet.vx *= drag;
   bullet.vy *= drag;
  }
  if (bullet.kind !== 'rapid') {
   bullet.trail.push({x: bullet.x, y: bullet.y});
   if (bullet.trail.length > 6) bullet.trail.shift();
  }
  if (!advanceBullet(world, bullet, span)) return false;
  if (bullet.life > 1e-9) return true;
  if (bullet.kind === 'grenade') detonate(world, bullet);
  return false;
 });
}

function setupBindings(bindings, fallback) {
 const layout = Array.isArray(bindings) ? bindings : [bindings];
 const keys = {};
 for (const entry of layout) {
  for (const action of ['forward', 'reverse', 'left', 'right', 'fire', 'fireAlt']) {
   if (entry?.[action]) keys[entry[action]] = action === 'fireAlt' ? 'fire' : action;
  }
 }
 return Object.keys(keys).length ? keys : fallback;
}

function refreshBindings(world) {
 const bindings = world.readBindings();
 const layout = Array.isArray(bindings) ? bindings : [bindings];
 world.keys = world.local ? setupBindings(layout[0],PRIMARY_KEYS) : setupBindings(layout,{...PRIMARY_KEYS,...LOCAL_KEYS});
 if (world.local) world.local.keys = setupBindings(layout[1],LOCAL_KEYS);
 const hint = byID('infiniteControlsHint');
 if (!hint) return;
 const arrows = {ArrowUp: '↑', ArrowDown: '↓', ArrowLeft: '←', ArrowRight: '→'};
 const label = code => arrows[code] || code.replace(/^(Key|Digit)/, '').replace(/^Numpad/, 'Num ');
 const codes = (keys,action) => Object.keys(keys).filter(code => keys[code] === action).map(label).join('/');
 const summary = keys => `Move ${codes(keys,'forward')}/${codes(keys,'reverse')} · Turn ${codes(keys,'left')}/${codes(keys,'right')} · Fire ${codes(keys,'fire')}`;
 const primary = window.matchMedia('(pointer: coarse)').matches ?
  'Drag the stick to move and aim. Tap or hold Fire.' : summary(world.keys) + ' · Mouse aim and fire';
 hint.textContent = world.local ? `P1 ${primary} · P2 ${summary(world.local.keys)}` : primary;
}

function interpolate(previous, current, alpha) {
 if (!previous || previous.hp === 0 || current.hp === 0 ||
     previous.spawnSerial !== current.spawnSerial || (previous.ghostTime > 0) !== (current.ghostTime > 0) ||
     Math.hypot(previous.x - current.x, previous.y - current.y) > CELL) return current;
 return {
  ...current,
  track: (previous.track || 0) + ((current.track || 0) - (previous.track || 0)) * alpha,
  x: previous.x + (current.x - previous.x) * alpha,
  y: previous.y + (current.y - previous.y) * alpha,
  angle: previous.angle + angleOf(current.angle - previous.angle) * alpha,
 };
}

function drawTank(tank, mine, zoom, ratio) {
 const color = COLORS[tank.colorIndex] || COLORS[0];
 ctx.save();
 ctx.translate(tank.x, tank.y);
 const shields = tank.shield > 0 ? tank.shieldCharges || 1 : 0;
 if (shields || tank.invulnerable > 0 || mine) {
  ctx.strokeStyle = shields ? powers.shield.color : mine ? '#bf5cff' : art.theme.protection;
  ctx.lineWidth = 1.6;
  ctx.globalAlpha = shields ? .78 : tank.invulnerable > 0 ? .55 : .2;
  if (!shields && !(tank.invulnerable > 0)) ctx.setLineDash([3, 6]);
  for (let i = 0; i < Math.max(1, shields); i++) {
   ctx.beginPath();
   ctx.arc(0, 0, shields ? 26 + i * 4 : mine && tank.invulnerable > 0 ? 34 : 25, 0, TAU);
   ctx.stroke();
  }
  ctx.setLineDash([]);
  ctx.globalAlpha = 1;
 }
 if (tank.starmanTime > 0) {
  const colors = ['#ff758f', '#f9ed75', '#79d878', '#62dcff', '#ba91ff'];
  ctx.lineWidth = 2.5;
  colors.forEach((color, i) => {
   ctx.strokeStyle = color;
   ctx.beginPath();
   ctx.arc(0, 0, 24, i * TAU / colors.length, (i + .85) * TAU / colors.length);
   ctx.stroke();
  });
 }
 ctx.save();
 ctx.rotate(tank.angle);
 if (tank.ghostTime > 0) ctx.globalAlpha = tank.starmanTime > 0 ? .84 : .58;
 if (tank.speedTime > 0) {
  ctx.strokeStyle = powers.speed.color;
  ctx.lineWidth = 2;
  for (let i = 0; i < (tank.speedStacks || 1); i++) for (const y of [8 + i * 2.2, -8 - i * 2.2]) {
   ctx.beginPath();
   ctx.moveTo(-22, y);
   ctx.lineTo(-34 - i * 3, y);
   ctx.stroke();
  }
 }
 const skin = {color, track: tank.track || 0, recoil: tank.recoil || 0};
 art.hull(skin, ctx, zoom, ratio);
 art.turret(ctx, skin);
 ctx.restore();
 ctx.font = 'bold 11px ui-monospace,SFMono-Regular,Consolas,monospace';
 ctx.textAlign = 'center';
 const label = mine ? 'YOU' : tank.name;
 const width = Math.min(ctx.measureText(label)?.width || 30, 120) + 10;
 ctx.fillStyle = '#0e171ddb';
 art.rect(ctx, -width / 2, -48, width, 16, 3);
 ctx.fill();
 ctx.fillStyle = color;
 ctx.fillText(label, 0, -36, 120);
 ctx.restore();
 art.drawBadges(tank, ctx, zoom);
}

function drawMaze(world, x0, y0, x1, y1) {
 const chunkSize = CELL * 8;
 for (let cy = Math.floor(y0 / chunkSize); cy <= Math.floor(y1 / chunkSize); cy++) {
  for (let cx = Math.floor(x0 / chunkSize); cx <= Math.floor(x1 / chunkSize); cx++) {
   const key = cx + ',' + cy, x = cx * chunkSize, y = cy * chunkSize;
   let image = world.mapCache.get(key);
   if (!image) {
    image = document.createElement('canvas');
    image.width = image.height = chunkSize;
    const tileCtx = image.getContext('2d', {alpha: false});
    tileCtx.fillStyle = art.theme.floor;
    tileCtx.fillRect(0, 0, chunkSize, chunkSize);
    tileCtx.translate(-x, -y);
    for (let row = cy * 8; row < cy * 8 + 8; row++) {
     for (let col = cx * 8; col < cx * 8 + 8; col++) art.tile(tileCtx, col, row);
    }
    // Include the neighbouring wall and shadow where they cross the tile seam.
    for (const wall of world.maze.wallsNear(x - 8, y - 8, x + chunkSize + 8, y + chunkSize + 8)) art.wall(tileCtx, wall);
   }
   world.mapCache.delete(key);
   world.mapCache.set(key, image);
   if (world.mapCache.size > 12) world.mapCache.delete(world.mapCache.keys().next().value);
   ctx.drawImage(image, x, y);
  }
 }
}

function drawTrace(points, color, width, alpha, dashed = false) {
 if (points.length < 2) return;
 ctx.save();
 ctx.strokeStyle = color;
 ctx.lineWidth = width;
 ctx.globalAlpha = alpha;
 if (dashed) ctx.setLineDash([3, 7]);
 ctx.beginPath();
 ctx.moveTo(points[0].x, points[0].y);
 for (let i = 1; i < points.length; i++) ctx.lineTo(points[i].x, points[i].y);
 ctx.stroke();
 ctx.restore();
}

function nearCamera(world,x,y,distance) {
 return world.controllers.some(({camera})=>Math.hypot(x-camera.x,y-camera.y)<=distance);
}

function presentEffect(world, effect, now) {
 const {kind, owner} = effect, seat = world.controllers.find(controller=>controller.id===owner);
 if (!seat && !nearCamera(world,effect.x,effect.y,CELL*6)) return;
 if (kind.startsWith('shot:') || kind === 'laser') {
  const weaponKind = kind === 'laser' ? kind : kind.slice(5);
  // Suppress the authoritative copy of a predicted local press sound.
  if (!seat || !world.online || now - seat.pendingShotAt > 300) art.shot(weaponKind, !!seat, now / 1000);
  else seat.pendingShotAt = -Infinity;
  if (kind !== 'laser') return;
 } else if (kind === 'pickup') art.collect();
 else if (kind === 'shield') art.shield();
 else if (kind === 'hit' || kind === 'blast') art.blast();
 else if (kind === 'impact') art.impact();
 else return;
 if (world.visualEffects.length >= 32) world.visualEffects.shift();
 let outline;
 if (kind === 'blast') {
  outline = Array.from({length: 24}, (_, index) => {
   const angle = index * TAU / 24, dx = Math.cos(angle) * BLAST_RADIUS, dy = Math.sin(angle) * BLAST_RADIUS;
   const wall = wallHit(world.maze, effect.x, effect.y, dx, dy, 0), fraction = wall?.fraction ?? 1;
   return {x: dx * fraction, y: dy * fraction};
  });
 }
 world.visualEffects.push({...effect, outline, end: now + (kind === 'laser' ? 180 : 430)});
}

function drawEffects(world, now) {
 for (const effect of world.visualEffects) {
  if (effect.kind === 'laser') {
   if (effect.points) {
    const alpha = clamp((effect.end - now) / 180, 0, 1);
    drawTrace(effect.points, powers.laser.color, 7, alpha * .45);
    drawTrace(effect.points, '#fff2ff', 2, alpha);
   }
   continue;
  }
  const alpha = clamp((effect.end - now) / 430, 0, 1);
  const blast = effect.kind === 'blast';
  ctx.save();
  ctx.translate(effect.x, effect.y);
  ctx.globalAlpha = alpha * .8;
  ctx.strokeStyle = effect.kind === 'hit' ? '#f7ecbb' : (blast ? powers.grenade : powers[effect.kind] || powers.speed).color;
  ctx.lineWidth = blast ? 3 : 2;
  ctx.beginPath();
  if (effect.outline) {
   effect.outline.forEach(({x, y}, i) => {
    const f = 1 - alpha * .35;
    if (i) ctx.lineTo(x * f, y * f);
    else ctx.moveTo(x * f, y * f);
   });
   ctx.closePath();
   ctx.fillStyle = ctx.strokeStyle;
   ctx.globalAlpha = alpha * .09;
   ctx.fill();
   ctx.globalAlpha = alpha * .8;
  } else ctx.arc(0, 0, 14 + (1 - alpha) * (effect.kind === 'hit' ? 56 : 35), 0, TAU);
  ctx.stroke();
  ctx.restore();
 }
}

function renderScores(world, pilot, second) {
 if (personalScore) {
  const count = world.local ? `P1 ${pilot?.score ?? 0} · P2 ${second?.score ?? 0}` : 'Score ' + (pilot?.score ?? 0);
  if (personalScore.textContent !== count) personalScore.textContent = count;
 }
 if (!leaderboard) return;
 const entries = world.online ? world.leaderboard :
  [...world.tanks].sort((a, b) => b.score - a.score || Number(a.bot) - Number(b.bot)).slice(0, 10);
 const rows = entries.map(tank => [tank.name, tank.score, tank.id===world.id?' (you)':tank.id===world.local?.id?' (P2)':'']);
 const teams = world.rules?.teamMode==='teams' ? world.teamScores.flatMap((score,i)=>
  i<2||score||entries.some(tank=>tank.team===i+1)?[[teamName(world,i+1),score,'']]:[]) : [];
 const signature = JSON.stringify([rows,teams]);
 if (signature === world.scoreRows) return;
 world.scoreRows = signature;
 const makeRow = ([name, score, local]) => {
  const row = document.createElement('li');
  const callsign = document.createElement('span');
  const total = document.createElement('strong');
  callsign.textContent = name + local;
  total.textContent = score;
  row.append(callsign, total);
  return row;
 };
 leaderboard.replaceChildren(...rows.map(makeRow));
 teamLeaderboard.hidden = !teams.length;
 teamLeaderboard.replaceChildren(...teams.map(makeRow));
}

function updateWeapon(element,pilot) {
 if(!element || !pilot)return;
 const active = pilot.power || (pilot.starmanTime > 0 ? 'starman' : pilot.shield > 0 ? 'shield' :
  pilot.ghostTime > 0 ? 'ghost' : pilot.speedTime > 0 ? 'speed' : '');
 const label = (powers[active]?.name || 'Standard shell') + (pilot.starmanTime > 0 ? ' · ∞ AMMO' : '');
 if (element.textContent !== label) element.textContent = label;
 const color = powers[active]?.color || '';
 if (element.style.color !== color) element.style.color = color;
}

function updateHUD(world, pilot, second, now) {
 if (!pilot || world.failed || world.online && !world.joined || now < world.nextHUD) return;
 world.nextHUD = now + 80;
 renderScores(world,pilot,second);
 const counts = world.online ? ` · ${world.players} online` : ` · ${world.tanks.filter(tank=>tank.bot).length} bots`;
 const target = world.rules?.infinityTarget ? ` · First to ${world.rules.infinityTarget}` : '';
 const state = tank => tank?.hp ? 'Weapons live' : pauseMenu.open ? 'Respawn held' : 'Respawning…';
 setStatus((world.result ? world.result.name + ' wins' : second ? `P1 ${state(pilot)} · P2 ${state(second)}` : state(pilot)) + counts + target);
 updateWeapon(weapon,pilot);
 updateWeapon(localWeapon,second);
 const fireLabel = byID('infiniteFireLabel');
 const canDetonate = pilot.hp && world.bullets.some(b => !b.dead && b.owner === world.id && b.kind === 'grenade');
 if (fireLabel && canDetonate !== world.canDetonate) {
  world.canDetonate = canDetonate;
  fireLabel.textContent = canDetonate ? 'DETONATE' : 'FIRE';
  fire.classList.toggle('detonate-ready', !!canDetonate);
  fire.setAttribute('aria-label', canDetonate ? 'Press to detonate your grenade' : 'Hold to fire');
 }
}

function primaryView(width,height,split) {
 if (!split) return [width,height];
 return width>=height?[Math.ceil(width/2),height]:[width,Math.ceil(height/2)];
}

function draw(world, now, dt) {
 const width = canvas.clientWidth, height = canvas.clientHeight;
 if (!width || !height) return;
 const ratio = art.renderPixelRatio(width, height);
 const pixelsX = Math.round(width * ratio), pixelsY = Math.round(height * ratio);
 if (canvas.width !== pixelsX || canvas.height !== pixelsY) {
  canvas.width = pixelsX;
  canvas.height = pixelsY;
 }
 ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
 ctx.fillStyle = art.theme.arena;
 ctx.fillRect(0, 0, width, height);
 if (!world.maze) return;
 const alpha = clamp((now - world.arrived) / world.interval, 0, 1);
 const age = world.online&&!world.result ? Math.max(0,(now-world.arrived)/1000) : 0;
 for (const seat of world.controllers) {
  const authority = world.tanks.find(tank=>tank.id===seat.id);
  const pilot = world.online&&!world.result ? seat.predictor.visual(dt)||authority : authority;
  seat.display = pilot && (world.online ? art.ageTank({...pilot},authority,age) : pilot);
  if (pilot) Object.assign(seat.camera,{x:pilot.x,y:pilot.y});
 }
 world.visualEffects = world.visualEffects.filter(effect=>effect.end>now);
 const [firstWidth,firstHeight] = primaryView(width,height,!!world.local);
 const split = !world.local ? '' : firstWidth < width ? 'side' : 'stacked';
 if (arena.dataset.split!==split) arena.dataset.split=split;
 drawView(world,world,0,0,firstWidth,firstHeight,ratio,alpha,now,age);
 if (world.local) {
  const left = firstWidth < width ? firstWidth : 0, top = firstHeight < height ? firstHeight : 0;
  drawView(world,world.local,left,top,width-left,height-top,ratio,alpha,now,age);
  ctx.fillStyle = art.theme.arena;
  if (left) ctx.fillRect(left-1,0,2,height);
  else ctx.fillRect(0,top-1,width,2);
 }
 updateHUD(world,world.display,world.local?.display,now);
}

function drawView(world,seat,left,top,width,height,ratio,alpha,now,age) {
 const {x,y} = seat.camera, pilot = seat.display;
 const zoom = clamp(Math.min(width, height) / (CELL * 5), .7, 1.2);
 const x0 = x - width / (2 * zoom), y0 = y - height / (2 * zoom);
 const x1 = x + width / (2 * zoom), y1 = y + height / (2 * zoom);
 ctx.save();
 ctx.beginPath();
 ctx.rect(left,top,width,height);
 ctx.clip();
 ctx.translate(left+width/2,top+height/2);
 ctx.scale(zoom, zoom);
 ctx.translate(-x, -y);
 drawMaze(world, x0, y0, x1, y1);
 const visible = (item, margin = CELL) => item.x >= x0 - margin && item.x <= x1 + margin && item.y >= y0 - margin && item.y <= y1 + margin;
 for (const pickup of world.pickups) if (pickup.life > 0 && visible(pickup)) art.pickup(pickup, ctx, now / 1000);
 if (pilot?.hp && pilot.power === 'laser' && !muzzleBlocked(world.maze, pilot, 3)) {
  const aim = seat.aim;
  if (!aim || aim.x !== pilot.x || aim.y !== pilot.y || aim.angle !== pilot.angle) {
   seat.aim = {x:pilot.x,y:pilot.y,angle:pilot.angle,points:traceLaser(world,pilot,true).points};
  }
  drawTrace(seat.aim.points, powers.laser.color, 2, .5, true);
 }
 for (const tank of world.tanks) {
  if (!tank.hp) continue;
  const owner = world.controllers.find(controller=>controller.id===tank.id);
  if (!owner&&!visible(tank)) continue;
  const displayed = owner?.display || (world.online ?
   art.ageTank({...interpolate(world.previousTanks.get(tank.id),tank,alpha)},tank,age) : tank);
  if (!visible(displayed)) continue;
  if (owner&&now<owner.previewRecoilUntil) displayed.recoil = Math.max(displayed.recoil || 0,(owner.previewRecoilUntil-now)/100);
  drawTank(displayed, owner===seat, zoom, ratio);
 }
 const bullets = [];
 for (const bullet of world.bullets) {
  if (!visible(bullet)) continue;
  const previous = world.previousBullets.get(bullet.id);
  const blend = previous && previous.bounces === bullet.bounces;
  bullets.push({...bullet, x: blend ? previous.x + (bullet.x - previous.x) * alpha : bullet.x,
   y: blend ? previous.y + (bullet.y - previous.y) * alpha : bullet.y,
   color: COLORS[bullet.colorIndex] || COLORS[0], trail: bullet.trail || (blend ? [previous, bullet] : [])});
 }
 art.bullets(bullets, ctx, now / 1000);
 drawEffects(world, now);
 ctx.restore();
 if (world.local) {
  ctx.fillStyle = art.theme.arena;
  ctx.fillRect(left+8,top+8,29,19);
  ctx.fillStyle = COLORS[pilot?.colorIndex] || COLORS[0];
  ctx.textAlign = 'left';
  ctx.font = 'bold 11px ui-monospace,monospace';
  ctx.fillText(seat===world?'P1':'P2',left+14,top+22);
 }
}

function sendInput(seat = session, now = performance.now(), immediate = false, input) {
 const world = session;
 if (!world?.online || !world.joined || world.result || seat.id==null ||
     socket?.readyState !== WebSocket.OPEN || socket.bufferedAmount > 4096) return;
 input ||= inputState(seat);
 const changed = input.paused !== seat.lastSent?.paused || !net.controlsEqual(input, seat.lastSent);
 if (!immediate && now + .5 < seat.nextSend || !changed && !immediate && now < seat.keepAlive) return;
 if (changed || !seat.lastSent) {
  seat.seq++;
  seat.predictor.sentInput(seat.seq);
 }
 socket.send(JSON.stringify({...input, seq:seat.seq, local:seat===world.local||undefined}));
 seat.lastSent = input;
 seat.nextSend = now + 1000 / 30;
 seat.keepAlive = now + 140;
 seat.fireTap = false;
}

function showResult(world) {
 if (!world.result || resultDialog.open) return;
 resetControls();
 dismissPause();
 byID('infiniteResultTitle').textContent = world.result.name + ' wins';
 byID('infiniteResultScore').textContent = 'Final score ' + world.result.score;
 world.nextHUD = 0;
 resultDialog.showModal();
}

function loop(now) {
 if (!arena.open || !session) return;
 const dt = clamp((now - lastTime) / 1000, 0, .1);
 if (session.online && !session.result) {
  for (const seat of session.controllers) {
   const input = inputState(seat);
   sendInput(seat,now,false,input);
   seat.predictor.advance(dt,input);
  }
 } else if (!session.online && !pauseMenu.open && !session.result) {
  accumulator += dt;
  while (!session.result && accumulator + 1e-9 >= STEP) {
   offlineStep(session,STEP);
   for (const seat of session.controllers) seat.fireTap=false;
   accumulator = Math.max(0, accumulator - STEP);
  }
 }
 lastTime = now;
 showResult(session);
 if (session.online || !pauseMenu.open) draw(session, now, dt);
 frame = requestAnimationFrame(loop);
}

function connectionFailed(message) {
 if (!session?.online) return;
 clearTimeout(connectTimer);
 session.failed = true;
 session.joined = false;
 resetControls();
 setStatus(message + (session.room ? ' Use Exit Infinity in the pause menu to return to your room.' :
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
  if (message.localId != null) {
   if (!session.local) {
    session.local = addController(session,{});
    refreshBindings(session);
   }
   session.local.id = message.localId;
  } else if (session.local) {
   session.controllers.pop();
   session.local = null;
   refreshBindings(session);
  }
  byID('infiniteLocalLoadout').hidden = !session.local;
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
 session.interval = session.arrived ? clamp(now - session.arrived, 20, 90) : 1000 / 30;
 session.arrived = now;
 session.tanks = message.tanks.map(tank => ({...tank, alive: tank.hp > 0}));
 session.bullets = message.bullets.map(bullet => ({...bullet, r: (PROJECTILES[bullet.kind || 'regular'] || PROJECTILES.regular).r}));
 session.pickups = Array.isArray(message.pickups) ? message.pickups : [];
 session.players = message.players;
 session.leaderboard = message.leaderboard;
 if (message.rules) session.rules = message.rules;
 if (message.teamScores) session.teamScores = message.teamScores;
 for (const seat of session.controllers) {
  const pilot = session.tanks.find(tank=>tank.id===seat.id);
  if (!pilot) continue;
  const old = session.previousTanks.get(pilot.id);
  const snap = !old || old.spawnSerial !== pilot.spawnSerial;
  seat.predictor.reconcile(pilot,snap);
  if (snap) seat.lastSent = null;
 }
 let bounced = false;
 for (const bullet of session.bullets) {
  const old = session.previousBullets.get(bullet.id);
  if (old && (bullet.bounces || 0) > (old.bounces || 0) && nearCamera(session,bullet.x,bullet.y,CELL*7)) bounced = true;
 }
 if (bounced) art.ricochet();
 for (const event of Array.isArray(message.effects) ? message.effects : []) {
  if (!event || typeof event.kind !== 'string' || !Number.isInteger(event.id) || event.id <= session.lastEffect) continue;
  session.lastEffect = event.id;
  presentEffect(session, event, now);
 }
 const joined = session.joined;
 session.joined = true;
 if (!joined && pauseMenu.open) for (const seat of session.controllers) sendInput(seat,now,true);
 if (message.result) session.result = message.result;
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
 session.pickups = [];
 session.leaderboard = [];
 session.visualEffects = [];
 session.lastEffect = 0;
 for (const seat of session.controllers) {
  seat.previewShotAt = seat.pendingShotAt = -Infinity;
  seat.lastSent = null;
  seat.seq = 0;
  seat.predictor.reset(null);
 }
 session.mapCache.clear();
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
   ws.send(JSON.stringify({type:'join',version:window.leqra.version,name:session.name,
    localName:session.room?undefined:session.localName,...session.room}));
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
 stickPointer = firePointer = mousePointer = null;
 fire.classList.remove('held');
 touchAim.x = touchAim.y = 0;
 knob.style.removeProperty('--stick-x');
 knob.style.removeProperty('--stick-y');
 if (session) for (const seat of session.controllers) {
  seat.fireTap = false;
  sendInput(seat,performance.now(),true);
 }
}

function dismissPause() {
 if (pauseMenu.open) {
  if (controlsDialog?.open) {
   const tour = byID('introTourDialog');
   if (tour.open) tour.close();
   controlsDialog.close();
  }
  pauseMenu.close();
 }
}

function stop() {
 if (!session) return;
 resetControls();
 cancelAnimationFrame(frame);
 clearTimeout(connectTimer);
 const ws = socket;
 socket = null;
 session = null;
 dismissPause();
 if (resultDialog.open) resultDialog.close();
 if (arena.open) arena.close();
 ws?.close();
 art.touchPolicy();
}

function addController(world,seat) {
 Object.assign(seat,{camera:{x:CELL/2,y:CELL/2},fireTap:false,nextSend:0,keepAlive:0,seq:0,
  previewShotAt:-Infinity,pendingShotAt:-Infinity,predictor:new net.Predictor(world.moveTank)});
 world.controllers.push(seat);
 return seat;
}

function start(mode, options = {}) {
 if ((mode !== 'offline' && mode !== 'online') || arena.open) return;
 stop();
 const online = mode === 'online', name = options.name?.trim() || pilotName();
 const readBindings = typeof options.bindings === 'function' ? options.bindings : () => options.bindings;
 session = {
  online, name, localName:options.localName, readBindings, id:'pilot', tanks:[], bullets:[], pickups:[], leaderboard:[], controllers:[],
  room: online && options.code && options.token ? {code: options.code, token: options.token} : null,
  rules:options.roomRules,teamScores:[0,0,0,0],previousTanks:new Map(),previousBullets:new Map(),
  time:0,nextBot:between(.4,1.2),nextPickup:0,pickupPilot:0,lastBot:0,lastBullet:0,nextHUD:0,lastEffect:0,
  mapCache: new Map(), visualEffects: [], interval: 1000 / 30, arrived: 0,
 };
 const world = session;
 world.moveTank = (tank, dx, dy, phaseEnded) => mazeMove(world.maze, tank, dx, dy, phaseEnded);
 addController(world,world);
 if (world.localName) world.local = addController(world,{id:online?null:'local'});
 if (retry) retry.hidden = true;
 arena.dataset.mode = mode;
 byID('infiniteLocalLoadout').hidden = !world.local;
 refreshBindings(world);
 arena.showModal();
 art.touchPolicy();
 canvas.focus({preventScroll: true});
 if (online) {
  connect();
 } else {
  session.maze = geometry.create(Math.floor(Math.random() * 0x100000000));
  const player = makeTank(session.id, session.camera.x, session.camera.y);
  player.name = name;
  const roster = options.roster || [];
  setTeam(world,player,roster.find(member=>member.id===options.primaryId)?.team);
  session.tanks.push(player);
  if (world.local) {
   const point = clearCell(world,player,2*CELL,4*CELL,2*CELL) || {x:player.x+2*CELL,y:player.y};
   const second = makeTank(world.local.id,point.x,point.y);
   second.name = world.localName;
   second.colorIndex = 1;
   setTeam(world,second,roster.find(member=>member.id===options.localId)?.team);
   world.tanks.push(second);
  }
  setStatus('Weapons live · 0 bots');
  renderScores(session,player,world.tanks[1]);
 }
 lastTime = performance.now();
 accumulator = 0;
 frame = requestAnimationFrame(loop);
}

function updateMouse(event) {
 const rect = canvas.getBoundingClientRect();
 const [width,height] = primaryView(rect.width,rect.height,!!session?.local);
 const px=event.clientX-rect.left,py=event.clientY-rect.top;
 if(session?.local&&(px<0||py<0||px>=width||py>=height)){
  mouseAim=null;
  return false;
 }
 const x = px-width/2, y = py-height/2;
 const distance = Math.hypot(x, y);
 if (distance > 3) mouseAim = {x: x / distance, y: y / distance};
 return true;
}

function pressFire(event,seat=session) {
 if (!session || session.result || pauseMenu.open || session.online && !session.joined) return;
 art.primeAudioUnlock(event);
 seat.fireTap = true;
 const now = performance.now(), world = session;
 const pilot = seat.predictor.state;
 const age = now - world.arrived, boosted = pilot?.starmanTime > age / 1000;
 const canDetonate = world.bullets.some(b=>!b.dead&&b.owner===seat.id&&b.kind==='grenade');
 if (world.online && pilot?.alive && now - seat.previewShotAt >= (boosted ? .065 : PROJECTILES[pilot.power || 'regular']?.cooldown || .15) * 1000 &&
     (boosted || age >= (pilot.cooldown || 0) * 1000) &&
     pilot.power !== 'grenade' && !canDetonate && !muzzleBlocked(world.maze, pilot, PROJECTILES[pilot.power || 'regular'].r)) {
  seat.previewShotAt = seat.pendingShotAt = now;
  seat.previewRecoilUntil = now + 100;
  art.shot(pilot.power || '', true, now / 1000);
 }
 sendInput(seat,now,true);
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
 try { element.setPointerCapture?.(event.pointerId); } catch (_) {}
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
 if (event.type === 'pointerup') art.primeAudioUnlock(event);
 sendInput(session,performance.now(),true);
}

arena.addEventListener('keydown', event => {
 if (!session) return;
 event.stopPropagation();
 if (session.result) return;
 if (event.ctrlKey || event.metaKey || event.altKey) return;
 if (event.code === 'Escape' || event.code === 'KeyP') {
  event.preventDefault();
  if (!event.repeat) {
   if (pauseMenu.open) resume();
   else openPause();
  }
  return;
 }
 if (event.code === 'KeyM') {
  event.preventDefault();
  if (!event.repeat) art.toggleSound();
  return;
 }
 if (pauseMenu.open) return;
 const seat = session.controllers.find(controller=>controller.keys[event.code]);
 const action = seat?.keys[event.code];
 if (!action ||
     (event.code === 'Enter' || event.code === 'Space') && event.target.closest('button, a, input, summary')) return;
 event.preventDefault();
 if (event.repeat || pressed.has(event.code)) return;
 pressed.add(event.code);
 if (seat===session&&(action==='left'||action==='right')) mouseAim = null;
 if (action === 'fire') pressFire(event,seat);
 else sendInput(seat,performance.now(),true);
});
arena.addEventListener('keyup', event => {
 if (!pressed.delete(event.code)) return;
 event.preventDefault();
 const seat=session?.controllers.find(controller=>controller.keys[event.code]);
 if (seat) sendInput(seat,performance.now(),true);
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
 if (event.pointerType !== 'mouse' || event.button !== 0 || mousePointer !== null || !updateMouse(event)) return;
 canvas.focus({preventScroll: true});
 capturePointer(canvas, event);
 mousePointer = event.pointerId;
 pressFire(event);
});
stick.addEventListener('pointerdown', event => {
 if (event.button !== 0 || stickPointer !== null) return;
 capturePointer(stick, event);
 art.primeAudioUnlock(event);
 mouseAim = null;
 stickPointer = event.pointerId;
 updateStick(event);
 sendInput(session,performance.now(),true);
});
window.addEventListener('pointermove', event => {
 if (event.pointerId !== stickPointer) return;
 event.preventDefault();
 updateStick(event);
}, true);
fire.addEventListener('pointerdown', event => {
 if (event.button !== 0 || firePointer !== null) return;
 capturePointer(fire, event);
 firePointer = event.pointerId;
 fire.classList.add('held');
 pressFire(event);
});
fire.addEventListener('click', event => {
 // Keyboard and assistive activation has no pointer press to queue the shot.
 if (event.detail === 0) pressFire(event);
});
// A second touch can make Safari lose element-level capture.
for (const event of ['pointerup', 'pointercancel', 'lostpointercapture']) {
 window.addEventListener(event, endPointer, true);
}
arena.addEventListener('contextmenu', event => event.preventDefault());
function openPause() {
 if (!session || session.result || pauseMenu.open) return;
 pauseMenu.showModal();
 resetControls();
}
function resume() {
 if (!session || !pauseMenu.open) return;
 pauseMenu.close();
 lastTime = performance.now();
 refreshBindings(session);
 resetControls();
 canvas.focus({preventScroll: true});
}
byID('infinitePauseBtn').addEventListener('click', openPause);
byID('infiniteResumeBtn').addEventListener('click', resume);
byID('infiniteControlsBtn').addEventListener('click', art.openControls);
byID('infiniteExit').addEventListener('click', stop);
byID('infiniteResultExit').addEventListener('click',stop);
resultDialog.addEventListener('cancel',event=>{event.preventDefault();stop();});
retry?.addEventListener('click', () => {
 canvas.focus({preventScroll: true});
 connect();
});
arena.addEventListener('cancel', event => {
 if (event.target !== arena) return;
 event.preventDefault();
 openPause();
});
pauseMenu.addEventListener('cancel', event => {
 event.preventDefault();
 resume();
});
arena.addEventListener('close', event => {
 if (event.target === arena && !arena.open) stop();
});
window.addEventListener('blur', resetControls);
window.addEventListener('pagehide', resetControls);
document.addEventListener('visibilitychange', () => {
 if (document.hidden) resetControls();
});

window.leqraInfinity = Object.freeze({start, close: stop, resetControls});
})();
