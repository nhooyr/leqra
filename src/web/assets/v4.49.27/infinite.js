(() => {
'use strict';

const byID = id => document.getElementById(id);
const arena = byID('infiniteArena');
const pauseMenu = byID('infinitePauseMenu');
const pauseSidebar = byID('infinitePauseSidebar');
const header = byID('infiniteHeader');
const controlsDialog = byID('controlsDialog');
const canvas = byID('infiniteCanvas');
const stick = byID('infiniteStick');
const stickBase = byID('infiniteStickBase');
const knob = byID('infiniteKnob');
const fire = byID('infiniteFire');
const status = byID('infiniteStatus');
const personalScore = byID('infiniteKills');
const leaderboard = byID('infiniteLeaderboard');
const leaderboardPanel = byID('infiniteLeaderboardPanel');
const leaderboardTitle = byID('infiniteLeaderboardTitle');
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
const COLORS = art.colors, powers = art.powers, powerTypes = Object.keys(powers), noTrail = [];
const LOCAL_HIGHLIGHTS = ['#bf5cff', '#ff4fd8'];
const POWER_DURATION = 15, STAR_DURATION = 8, PICKUP_LIFETIME = 30, SHOT_RANGE = 18 * CELL, BLAST_RADIUS = 220;
const RESPAWN_DELAY = 1;
const RESULT_NOTICE_MS = 1500;
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
const MAX_BOTS = 24, BOTS_PER_PLAYER = 8;
const RECONNECT_WINDOW = 18000, SNAPSHOT_TIMEOUT = 2500;
const ROOM_RESUME_KEY = 'leqra.infinityResume.v1';
const BOT_LEVELS = ['easy','normal','hard','godlike'];
const BOT_TUNING = {
 easy:{range:.7,roam:.75,aim:1.65}, normal:{range:1,roam:1,aim:1},
 hard:{range:1.15,roam:1.15,aim:.7}, godlike:{range:1.3,roam:1.3,aim:.45},
};
const PRIMARY_KEYS = {KeyW:'forward', KeyS:'reverse', KeyA:'left', KeyD:'right', KeyQ:'fire', KeyC:'fire'};
const LOCAL_KEYS = {ArrowUp:'forward', ArrowDown:'reverse', ArrowLeft:'left', ArrowRight:'right', Space:'fire', Enter:'fire'};
const pressed = new Set();
const touchAim = {x: 0, y: 0, cx: 0, cy: 0, reach: 0, assisted: false};
let session = null, frame = 0, socket = null, mouseAim = null;
let stickPointer = null, firePointer = null, mousePointer = null;
let lastTime = 0, accumulator = 0, connectTimer = 0;
let pausedLeaderboard = null;

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

function applyTankAppearance(world, tank, member) {
 if (world.rules?.teamMode === 'teams') tank.team = member?.team || nextBotTeam(world);
 if (member || tank.team) tank.colorIndex = art.colorIndex(member?.id ?? 0,tank.team,member?.colorIndex,world.rules);
}

function roamingDifficulty(rules) {
 const ceiling = rules?.infinityBotDifficulty || 'normal';
 if (!rules?.infinityRandomDifficulty) return ceiling;
 const levels = BOT_LEVELS.indexOf(ceiling)+1;
 return BOT_LEVELS[Math.floor(Math.random()*levels)];
}

function inputState(seat) {
 const input = {
  type: 'input', paused: pauseMenu.open, forward: false, reverse: false, left: false, right: false,
  stickX: 0, stickY: 0, aimOnly: false, fire: false,
 };
 if (input.paused || art.chatOpen()) return input;
 input.fire = seat.fireTap;
 for (const code of pressed) if (seat.keys[code]) input[seat.keys[code]] = true;
 if (seat === session) {
  input.stickX = touchAim.x;
  input.stickY = touchAim.y;
  if (touchAim.assisted) input.touchAim = true;
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

function wallHit(maze, x, y, dx, dy, radius, includeOrigin = false) {
 let hit = null;
 const flatX = Math.abs(dx) < 1e-9, flatY = Math.abs(dy) < 1e-9, sx = Math.sign(dx), sy = Math.sign(dy);
 maze.visitWalls(Math.min(x, x + dx) - radius, Math.min(y, y + dy) - radius,
                 Math.max(x, x + dx) + radius, Math.max(y, y + dy) + radius, (wx, wy, w, h) => {
  const minX = wx - radius, maxX = wx + w + radius, minY = wy - radius, maxY = wy + h + radius;
  let x0 = -Infinity, x1 = Infinity, y0 = -Infinity, y1 = Infinity;
  if (flatX) { if (x < minX || x > maxX) return false; }
  else { x0 = ((sx > 0 ? minX : maxX) - x) / dx; x1 = ((sx > 0 ? maxX : minX) - x) / dx; }
  if (flatY) { if (y < minY || y > maxY) return false; }
  else { y0 = ((sy > 0 ? minY : maxY) - y) / dy; y1 = ((sy > 0 ? maxY : minY) - y) / dy; }
  const entry = Math.max(x0, y0), exit = Math.min(x1, y1);
  if (entry > 1 || entry > exit || (includeOrigin ? exit < 0 : entry < -.0001)) return false;
  const fraction = Math.max(0, entry);
  const nx = x0 >= y0 - 1e-7 ? -sx : 0;
  const ny = y0 >= x0 - 1e-7 ? -sy : 0;
  if (!hit || fraction < hit.fraction - 1e-7) hit = {fraction, nx, ny};
  else if (Math.abs(fraction - hit.fraction) < 1e-7) {
   if (nx) hit.nx = nx;
   if (ny) hit.ny = ny;
  }
  return false;
 });
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

function hurt(world, target, ownerID, ownerTeam, ownerName, starmanContact = false) {
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
 target.respawn = RESPAWN_DELAY;
 target.score--;
 const owner = world.tanks.find(tank => tank.id === ownerID) || world.botPool?.find(tank => tank.id === ownerID);
 target.killedBy = owner?.name || ownerName || 'an unknown tank';
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
      !wallHit(world.maze, bullet.x, bullet.y, dx, dy, 0)) hurt(world, tank, bullet.owner, bullet.team, bullet.ownerName);
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
 return tank.power !== 'cannon' && tank.ghostTime > 0 && maze.visitWalls(x-radius, y-radius, x+radius, y+radius, () => true);
}

function fireShot(world, tank) {
 const boosted = tank.starmanTime > 0;
 if (!boosted && (tank.cooldown > 1e-9 || tank.power === 'rapid' && !tank.machineRounds)) return;
 const kind = tank.power || '', spec = PROJECTILES[kind || 'regular'];
 if (muzzleBlocked(world.maze, tank, spec.r)) return;
 const cooldown = boosted ? 0 : spec.cooldown;
 const showShot = !boosted || kind === 'grenade' || world.time + 1e-9 >= (tank.nextBoostEffect || 0);
 if (kind === 'laser') {
  const {points, target} = traceLaser(world, tank);
  Object.assign(tank, {cooldown, cooldownTotal:cooldown, recoil:1});
  if (showShot) {
   tank.nextBoostEffect = world.time + 4 * STEP;
   effect(world, 'laser', tank.x, tank.y, tank.id, points);
  }
  if (target) hurt(world, target, tank.id, tank.team, tank.name);
  spendWeapon(tank);
  return;
 }
 const offsets = kind === 'scatter' ? [-.21, 0, .21] : [0];
 if (!boosted) {
  let ammo = 0;
  for (const bullet of world.bullets) if (!bullet.dead && !bullet.boosted && bullet.owner === tank.id) ammo++;
  if (ammo + offsets.length > spec.ammo) return;
 }
 Object.assign(tank, {cooldown, cooldownTotal:cooldown, recoil:1});
 for (const offset of offsets) {
  const angle = tank.angle + offset, ux = Math.cos(angle), uy = Math.sin(angle);
  const bullet = {
   ...spec, id: ++world.lastBullet, owner: tank.id, ownerName: tank.name, team:tank.team, kind, boosted, x: tank.x, y: tank.y, color: COLORS[tank.colorIndex] || COLORS[0],
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
    hurt(world, hit.tank, bullet.owner, bullet.team, bullet.ownerName);
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
 const tune = BOT_TUNING[tank.difficulty] || BOT_TUNING.normal;
 const dx = pilot.x - tank.x, dy = pilot.y - tank.y, distance = Math.hypot(dx, dy);
 const seesPilot = distance < CELL * 6 * tune.range && !wallHit(world.maze, tank.x, tank.y, dx, dy, BULLET_RADIUS);
 if (!seesPilot && world.time >= tank.nextDecision) {
  tank.course = botCourse(world.maze, tank, pilot);
  tank.nextDecision = world.time + between(.25,.5)/tune.roam;
 }
 const tx = seesPilot ? dx : (tank.course?.x ?? tank.x) - tank.x;
 const ty = seesPilot ? dy : (tank.course?.y ?? tank.y) - tank.y;
 const aim = Math.atan2(ty, tx);
 return {
  stickX: Math.cos(aim)*tune.roam, stickY: Math.sin(aim)*tune.roam, aimOnly: Math.hypot(tx, ty) < 5 || seesPilot && distance < 115,
  fire: seesPilot && !(pilot.invulnerable > 0) && Math.abs(angleOf(aim - tank.angle)) < .16*tune.aim,
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
  world.pickups.push({x, y, life: PICKUP_LIFETIME, type: art.choosePickup(powerTypes)});
  nearby++;
 }
}

function respawnOfflineTank(world, tank, point) {
 const fresh = makeTank(tank.id, point.x, point.y, tank.bot);
 const fireHeld = !tank.bot && inputState(tank.id === world.local?.id ? world.local : world).fire;
 Object.assign(tank, fresh, {name: tank.name, colorIndex: tank.colorIndex, score: tank.score,
  spawnSerial: tank.spawnSerial + 1, killedBy: '', power: '', powerTime: 0, charges: 0, shield: 0, shieldCharges: 0,
  ghostTime: 0, speedTime: 0, starmanTime: 0, fireHeld, fireBlocked: false});
}

function populateBots(world, locals) {
 const limit = Math.min(MAX_BOTS, locals.length * BOTS_PER_PLAYER);
 if (world.botBudget !== limit) {
  let count = 0;
  world.tanks = world.tanks.filter(tank => {
   if (!tank.ambient || ++count <= limit) return true;
   tank.pooledAt = world.time;
   world.botPool.push(tank);
   return false;
  });
  world.botBudget = limit;
 }
 if (world.time < world.nextBot) return;
 world.nextBot = world.time + between(1.2, 3.4);
 const living = locals.filter(tank => tank.hp);
 if (!living.length) return;
 const roaming = world.tanks.filter(tank => tank.ambient);
 for (const bot of roaming) {
  if (!bot.hp || locals.some(pilot => Math.abs(pilot.x-bot.x) <= CELL*16 && Math.abs(pilot.y-bot.y) <= CELL*16)) continue;
  const pilot = living[Math.floor(Math.random()*living.length)];
  const point = clearCell(world, pilot, 3 * CELL, 6 * CELL, 1.9 * CELL);
  if (point) respawnOfflineTank(world,bot,point);
 }
 if (roaming.length >= limit) return;
 const pilot = living[roaming.length % living.length];
 const point = clearCell(world, pilot, 3 * CELL, 6 * CELL, 1.9 * CELL);
 if (!point) return;
 const pooled = world.botPool.shift();
 if (pooled) {
  if (pooled.hp) respawnOfflineTank(world,pooled,point);
  else pooled.respawn = Math.max(0,pooled.respawn-(world.time-pooled.pooledAt));
  delete pooled.pooledAt;
  world.tanks.push(pooled);
  return;
 }
 let number = 1;
 while (roaming.some(bot => bot.botNumber === number)) number++;
 const bot = makeTank('bot-' + ++world.lastBot,point.x,point.y,true);
 Object.assign(bot,{ambient:true,botNumber:number,name:'Bot '+number,difficulty:roamingDifficulty(world.rules)});
 applyTankAppearance(world,bot);
 world.tanks.push(bot);
}

function offlineStep(world, dt) {
 world.time += dt;
 const locals = world.tanks.slice(0, world.controllers.length);
 if (!world.rules || world.rules.infinityRandomBots) populateBots(world,locals);
 populatePickups(world, locals, dt);
 for (const tank of world.tanks) {
  if (!tank.hp) {
   tank.respawn -= dt;
   if (tank.respawn <= 1e-9) {
    const origin = tank.ambient ? locals.filter(pilot=>pilot.hp).sort((a,b)=>
     Math.hypot(a.x-tank.x,a.y-tank.y)-Math.hypot(b.x-tank.x,b.y-tank.y))[0] : tank;
    if (!origin) continue;
    const point = clearCell(world, origin, 2 * CELL, 5 * CELL, 1.9 * CELL);
    if (point) {
     respawnOfflineTank(world,tank,point);
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
    hurt(world,target,attacker.id,attacker.team,attacker.name,true);
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
 const codes = (keys,action) => Object.keys(keys).filter(code => keys[code] === action).map(art.keyLabel).join('/');
 const summary = keys => `Move ${codes(keys,'forward')}/${codes(keys,'reverse')} · Turn ${codes(keys,'left')}/${codes(keys,'right')} · Fire ${codes(keys,'fire')}`;
 const primary = art.isTouchUI() ?
  'Drag the stick to move and aim. Tap or hold Fire.' : summary(world.keys) + ' · Mouse aim and fire';
 const firstLine = document.createElement('span');
 firstLine.textContent = world.local ? `P1 ${primary}` : primary;
 hint.replaceChildren(firstLine);
 if (world.local) {
  const secondLine = document.createElement('span');
  secondLine.textContent = `P2 ${summary(world.local.keys)}`;
  hint.append(document.createElement('br'),secondLine);
 }
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

function drawTank(tank, highlight, zoom, ratio) {
 const color = COLORS[tank.colorIndex] || COLORS[0];
 ctx.save();
 ctx.translate(tank.x, tank.y);
 const shields = tank.shield > 0 ? tank.shieldCharges || 1 : 0;
 if (shields || tank.invulnerable > 0 || highlight) {
  ctx.strokeStyle = shields ? powers.shield.color : highlight || art.theme.protection;
  ctx.lineWidth = 1.6;
  ctx.globalAlpha = shields ? .78 : tank.invulnerable > 0 ? .55 : .2;
  if (!shields && !(tank.invulnerable > 0)) ctx.setLineDash([3, 6]);
  for (let i = 0; i < Math.max(1, shields); i++) {
   ctx.beginPath();
   ctx.arc(0, 0, shields ? 26 + i * 4 : highlight && tank.invulnerable > 0 ? 34 : 25, 0, TAU);
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
 const label = highlight ? 'YOU' : tank.name;
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
 else if (kind === 'hit') art.blast();
 else if (kind === 'blast') art.grenade();
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
 const standings = world.online ? world.leaderboard :
  [...world.tanks].sort((a, b) => b.score - a.score || Number(a.bot) - Number(b.bot));
 const score = tank => {
  const rank = world.online ? tank?.rank : standings.indexOf(tank) + 1;
  return `${tank?.score ?? 0}${rank > 0 ? ` (#${rank})` : ''}`;
 };
 if (personalScore) {
  const scores = world.local ? [[`P1 ${score(pilot)}`,pilot,0],[`P2 ${score(second)}`,second,1]] : [['Score '+score(pilot),pilot,0]];
  const rows = scores.map(([label,tank,seat]) => [label,COLORS[tank?.colorIndex] || COLORS[seat]]);
  const signature = JSON.stringify(rows);
  if (signature !== world.personalScoreRows) {
   world.personalScoreRows = signature;
   const children = [];
   for (const [label,color] of rows) {
    if (children.length) {
     const separator = document.createElement('span');
     separator.textContent = ' · ';
     separator.className = 'infinite-score-separator';
     children.push(separator);
    }
    const counter = document.createElement('span');
    counter.className = 'infinite-personal-score';
    counter.style.color = color;
    counter.textContent = label;
    children.push(counter);
   }
   personalScore.replaceChildren(...children);
  }
 }
 if (!leaderboard) return;
 const entries = standings.slice(0, 10);
 const tankCount = world.online ? world.tankCount ?? entries.length : world.tanks.length;
 const title = world.online && !world.room ? 'Top 10 Tanks' : tankCount > 10 ? `Top ${entries.length} tanks` : 'Scoreboard';
 const standingRow = (tank,rank,extra=false) => {
  const local = tank.id===world.id ? 1 : tank.id===world.local?.id ? 2 : 0;
  const name = tank.name || (local===1 ? world.name : local===2 ? world.localName : 'Tank');
  return [name, tank.score, local, COLORS[tank.colorIndex] || COLORS[0],rank,extra];
 };
 const rows = entries.map((tank,i) => standingRow(tank,i+1));
 const seen = new Set(entries.map(tank=>tank.id)), extraRows = [];
 for (const id of [world.id,world.local?.id]) {
  if (id==null || seen.has(id)) continue;
  const tank = world.tanks.find(tank=>tank.id===id);
  const rank = world.online ? tank?.rank : standings.indexOf(tank)+1;
  if (!tank || !Number.isSafeInteger(rank) || rank<=10) continue;
  extraRows.push(standingRow(tank,rank,true));
  seen.add(id);
 }
 extraRows.sort((a,b)=>a[4]-b[4]);
 rows.push(...extraRows);
 const teams = world.rules?.teamMode==='teams' ? world.teamScores.flatMap((score,i)=>
  i<2||score||entries.some(tank=>tank.team===i+1)?[[teamName(world,i+1),score,0,COLORS[world.rules.teamColors?.[i]] || COLORS[i]]]:[]) : [];
 const signature = JSON.stringify([title,rows,teams]);
 if (signature === world.scoreRows) return;
 world.scoreRows = signature;
 leaderboardTitle.textContent = title;
 const makeRow = ([name, score, local, color,rank,extra]) => {
  const row = document.createElement('li');
  if (rank) row.value = rank;
  if (extra) row.className = 'off-board-local';
  row.style.setProperty('--tank-color',color);
  if (local) {
   row.dataset.local = 'p' + local;
   row.style.setProperty('--local-highlight',LOCAL_HIGHLIGHTS[local-1]);
  }
  const callsign = document.createElement('span');
  const total = document.createElement('strong');
  callsign.textContent = name + (local===1?' (you)':local===2?' (P2)':'');
  total.textContent = score;
  row.append(callsign, total);
  return row;
 };
 leaderboard.replaceChildren(...rows.map(makeRow));
 teamLeaderboard.hidden = !teams.length;
 teamLeaderboard.replaceChildren(...teams.map(makeRow));
}

function updatePilotLoadout(world, pilot, seat, num, now) {
 if (!pilot) {art.renderLoadout(null,num);return;}
 const age = world.online&&!world.result ? clamp((now-world.arrived)/1000,0,.25) : 0;
 const tank = {...pilot,color:COLORS[pilot.colorIndex]||COLORS[0],
  cooldown:Math.max(0,(pilot.cooldown||0)-age),respawnTime:Math.max(0,(pilot.respawnTime||pilot.respawn||0)-age)};
 const grenadeLife = Math.max(0,(pilot.grenadeLife||0)-age);
 const projectiles = world.online ? {
  ammo:tank.power==='laser'?Math.max(0,3-tank.charges):pilot.ammoUsed||0,
  grenades:grenadeLife>0?pilot.grenades||0:0,grenadeLife,locked:!!pilot.locked,
 } : art.projectileState(tank,true,world.bullets,(b,target)=>canDamage(world,b.owner,b.team,target));
 const spec = PROJECTILES[tank.power||'regular'];
 const state = world.result?'complete':pauseMenu.open?(world.online&&!tank.alive?'held':'paused'):'playing';
 art.updateHomingAlert(seat.homingAlert,state==='playing'&&tank.alive&&projectiles.locked,now/1000);
 art.renderLoadout(tank,num,projectiles,muzzleBlocked(world.maze,tank,spec.r),state,!!world.local);
}

function updateHUD(world, pilot, second, now) {
 if (!pilot || world.failed || world.online && !world.joined || now < world.nextHUD) return;
 world.nextHUD = now + 1000 / 30;
 renderScores(world,pilot,second);
 const counts = world.online ? ` · ${world.players} online` : ` · ${world.tanks.filter(tank=>tank.bot).length} bots`;
 const target = world.rules?.infinityTarget ? ` · First to ${world.rules.infinityTarget}` : '';
 const state = tank => tank?.hp ? 'Weapons live' : pauseMenu.open ? 'Respawn held' : 'Respawning…';
 setStatus((world.result ? world.result.name + ' wins' : second ? `P1 ${state(pilot)} · P2 ${state(second)}` : state(pilot)) + counts + target);
 updatePilotLoadout(world,pilot,world,1,now);
 updatePilotLoadout(world,second,world.local,2,now);
}

function syncLocalLoadout(local) {
 byID('infiniteLocalLoadout').hidden = !local;
 byID('infiniteLoadouts').classList.toggle('two-pilots',!!local);
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
  if (left) ctx.fillRect(left-5,0,10,height);
  else ctx.fillRect(0,top-5,width,10);
  ctx.fillStyle = art.theme.accent;
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
  drawTank(displayed, owner===seat ? LOCAL_HIGHLIGHTS[seat===world?0:1] : null, zoom, ratio);
 }
 const bullets = world.visibleBullets;
 bullets.length = 0;
 for (const bullet of world.bullets) {
  if (!visible(bullet)) continue;
  const previous = world.online && world.previousBullets.get(bullet.id);
  if (previous && previous.bounces === bullet.bounces) {
   const {kind, color, r, life, vx, vy} = bullet;
   bullets.push({kind, color, r, life, vx, vy,
    x: previous.x + (bullet.x - previous.x) * alpha, y: previous.y + (bullet.y - previous.y) * alpha,
    trail: kind === 'rapid' ? noTrail : bullet.trail || [previous, bullet]});
  } else bullets.push(bullet);
 }
 art.bullets(bullets, ctx, now / 1000);
 if (!world.result && !world.failed && !pauseMenu.open) {
  art.drawHomingWarnings(ctx,pilot,world.bullets,(b,target)=>canDamage(world,b.owner,b.team,target));
 }
 drawEffects(world, now);
 ctx.restore();
 if (world.local) {
  ctx.save();
  ctx.fillStyle = art.theme.arena;
  art.rect(ctx,left+9,top+9,36,24,5);
  ctx.fill();
  ctx.strokeStyle = COLORS[pilot?.colorIndex] || COLORS[seat===world?0:1];
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.fillStyle = '#f3f8ff';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.font = 'bold 12px ui-monospace,monospace';
  ctx.fillText(seat===world?'P1':'P2',left+27,top+21);
  ctx.restore();
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

function showResult(world, now) {
 if (!world.result || resultDialog.open) return;
 if (world.resultAt === undefined) {
  resetControls();
  dismissPause();
  const localDeath = world.controllers.some(seat=>world.tanks.some(tank=>tank.id===seat.id&&!tank.hp&&tank.killedBy));
  world.resultAt = now + (localDeath ? RESULT_NOTICE_MS : 0);
  world.nextHUD = 0;
 }
 if (now < world.resultAt) return;
 byID('infiniteResultTitle').textContent = world.result.name + ' wins';
 byID('infiniteResultScore').textContent = 'Final score ' + world.result.score;
 resultDialog.showModal();
}

function loop(now) {
 if (!arena.open || !session) return;
 const workStart = performance.now();
 const dt = clamp((now - lastTime) / 1000, 0, .1);
 if (session.online && session.joined && !session.result) {
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
 showResult(session, now);
 if (session.online ? session.joined || session.retryAt === undefined : !pauseMenu.open) draw(session, now, dt);
 art.sampleFrame(now,performance.now()-workStart);
 frame = requestAnimationFrame(loop);
}

function connectionFailed(message) {
 if (!session?.online) return;
 clearTimeout(connectTimer);
 if (session.room) clearRoomResume();
 session.failed = true;
 session.joined = false;
 resetControls();
 art.renderLoadout(null,1);
 art.renderLoadout(null,2);
 setStatus(message + (session.room ? ' Use Exit Infinity in the pause menu to return to your room.' :
  ' Choose Infinity in Room settings to play offline.'));
 if (retry) retry.hidden = false;
 socket?.close();
}

function retryConnection(message) {
 if (!session.room) {connectionFailed(message);return;}
 const world = session, now = performance.now();
 world.retryAt ??= now;
 const remaining = world.retryAt + RECONNECT_WINDOW - now;
 if (remaining <= 0) {connectionFailed(message);return;}
 clearTimeout(connectTimer);
 const old = socket;
 socket = null;
 world.joined = false;
 resetControls();
 old?.close();
 setStatus('Connection interrupted · Reconnecting to room Infinity…');
 const delay = Math.min(remaining, 3000, 450 * 2 ** Math.min(world.retries++,3));
 connectTimer = setTimeout(() => {
  if (session === world) {
   if (performance.now() >= world.retryAt + RECONNECT_WINDOW) connectionFailed(message);
   else connect();
  }
 },delay);
}

function watchSnapshots(ws) {
 const delay = document.hidden ? SNAPSHOT_TIMEOUT : Math.max(1,SNAPSHOT_TIMEOUT + session.arrived - performance.now());
 connectTimer = setTimeout(() => {
  if (ws !== socket || !session?.joined || session.result) return;
  if (!document.hidden && performance.now() - session.arrived >= SNAPSHOT_TIMEOUT) retryConnection('Disconnected from Infinity.');
  else watchSnapshots(ws);
 },delay);
}

function saveRoomResume(token,generation) {
 try {sessionStorage.setItem(ROOM_RESUME_KEY,JSON.stringify({token,generation}));} catch {}
}

function clearRoomResume() {
 try {sessionStorage.removeItem(ROOM_RESUME_KEY);} catch {}
}

function savedRoomGeneration(token) {
 try {
  const saved = JSON.parse(sessionStorage.getItem(ROOM_RESUME_KEY));
  clearRoomResume();
  if (saved?.token === token && Number.isSafeInteger(saved.generation) && saved.generation > 0) return saved.generation;
 } catch {}
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
  const error = message.message || 'Unable to join Infinity.';
  if (message.code === 'session_active' && session.resumeGeneration) retryConnection(error);
  else connectionFailed(error);
  return;
 }
 if (message.type === 'welcome') {
  session.resumed = !!message.resumed;
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
  syncLocalLoadout(session.local);
  if (!session.maze || session.seed !== message.seed) {
   session.maze = geometry.create(message.seed);
   session.seed = message.seed;
   session.mapCache.clear();
  }
  if (session.room && Number.isSafeInteger(message.generation) && message.generation > 0) {
   session.resumeGeneration = message.generation;
   saveRoomResume(session.room.token,message.generation);
  }
  return;
 }
 if (message.type !== 'state' || !session.maze) return;
 if (!Array.isArray(message.tanks) || !Array.isArray(message.bullets) || !Array.isArray(message.leaderboard)) {
  connectionFailed('Unexpected state from the Infinity server.');
  return;
 }
 const now = performance.now(), joined = session.joined, resumed = !joined && session.resumed;
 session.previousTanks = new Map(session.tanks.map(tank => [tank.id, tank]));
 session.previousBullets = new Map(session.bullets.map(bullet => [bullet.id, bullet]));
 session.interval = session.arrived ? clamp(now - session.arrived, 20, 90) : 1000 / 30;
 session.arrived = now;
 session.tanks = message.tanks.map(tank => ({...tank, alive: tank.hp > 0}));
 session.bullets = message.bullets.map(bullet => ({...bullet, trail: bullet.trail || null,
  color: COLORS[bullet.colorIndex] || COLORS[0], r: (PROJECTILES[bullet.kind || 'regular'] || PROJECTILES.regular).r}));
 session.pickups = Array.isArray(message.pickups) ? message.pickups : [];
 session.players = message.players;
 session.tankCount = message.tankCount ?? message.leaderboard.length;
 session.leaderboard = message.leaderboard;
 if (message.rules) session.rules = message.rules;
 if (message.teamScores) session.teamScores = message.teamScores;
 for (const seat of session.controllers) {
  const pilot = session.tanks.find(tank=>tank.id===seat.id);
  if (!pilot) continue;
  const old = session.previousTanks.get(pilot.id);
  const snap = !joined || !old || old.spawnSerial !== pilot.spawnSerial;
  seat.predictor.reconcile(pilot,snap);
  if (snap) seat.lastSent = null;
 }
 let bounced = false;
 for (const bullet of session.bullets) {
  const old = session.previousBullets.get(bullet.id);
  if (old && (bullet.bounces || 0) > (old.bounces || 0) && nearCamera(session,bullet.x,bullet.y,CELL*7)) bounced = true;
 }
 if (!resumed && bounced) art.ricochet();
 for (const event of Array.isArray(message.effects) ? message.effects : []) {
  if (!event || typeof event.kind !== 'string' || !Number.isInteger(event.id) || event.id <= session.lastEffect) continue;
  session.lastEffect = event.id;
  if (!resumed) presentEffect(session, event, now);
 }
 if (resumed) resetControls();
 session.joined = true;
 if (message.result) session.result = message.result;
 if (!joined) {
  session.retryAt = undefined;
  session.retries = 0;
  session.nextHUD = 0;
  if (resumed || pauseMenu.open) for (const seat of session.controllers) sendInput(seat,now,true);
  clearTimeout(connectTimer);
  if (session.room && !session.result) watchSnapshots(ws);
 }
}

function connect() {
 if (!session?.online) return;
 const world = session;
 clearTimeout(connectTimer);
 const oldSocket = socket;
 socket = null;
 oldSocket?.close();
 world.failed = false;
 world.joined = false;
 world.visualEffects = [];
 if (!world.resumeGeneration) {
  world.maze = null;
  world.tanks = [];
  world.bullets = [];
  world.pickups = [];
  world.leaderboard = [];
  world.tankCount = 0;
  world.lastEffect = 0;
  art.renderLoadout(null,1);
  art.renderLoadout(null,2);
  world.mapCache.clear();
  renderScores(world, null);
 }
 for (const seat of world.controllers) {
  seat.previewShotAt = seat.pendingShotAt = -Infinity;
  seat.homingAlert = {};
  seat.lastSent = null;
  seat.seq = 0;
  seat.nextSend = seat.keepAlive = 0;
  seat.predictor.reset(null);
 }
 if (retry) retry.hidden = true;
 if (location.protocol !== 'http:' && location.protocol !== 'https:') {
  connectionFailed('Online Infinity requires the leqra server.');
  if (retry) retry.hidden = true;
  return;
 }
 setStatus(world.resumeGeneration || world.retryAt !== undefined ? 'Reconnecting to room Infinity…' :
  world.room ? 'Connecting to room Infinity…' : 'Connecting to Infinity…');
 const url = new URL('/ws/infinite', location.href);
 url.protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
 let ws;
 try {
  ws = socket = new WebSocket(url);
 } catch {
  retryConnection('Could not connect to Infinity.');
  return;
 }
 ws.addEventListener('open', () => {
  if (ws === socket && session === world) {
   ws.send(JSON.stringify({type:'join',version:window.leqra.version,name:world.name,
    localName:world.room?undefined:world.localName,...world.room,
    resume:world.resumeGeneration?true:undefined,generation:world.resumeGeneration}));
  }
 });
 ws.addEventListener('message', event => receive(ws, event));
 ws.addEventListener('close', () => {
  if (ws === socket && session === world && !world.failed && !world.result) {
   retryConnection(world.joined ? 'Disconnected from Infinity.' : 'Could not join Infinity.');
  }
 });
 connectTimer = setTimeout(() => {
  if (ws === socket && session === world && !world.joined) retryConnection('Could not connect to Infinity.');
 }, Math.min(6500,(world.retryAt ?? performance.now()) + RECONNECT_WINDOW - performance.now()));
}

function resetControls() {
 pressed.clear();
 mouseAim = null;
 stickPointer = firePointer = mousePointer = null;
 fire.classList.remove('held');
 touchAim.x = touchAim.y = 0;
 touchAim.assisted = false;
 knob.style.removeProperty('--stick-x');
 knob.style.removeProperty('--stick-y');
 if (session) for (const seat of session.controllers) {
  seat.fireTap = false;
  sendInput(seat,performance.now(),true);
 }
}

function restorePauseSidebar() {
 if (pausedLeaderboard && leaderboardPanel.parentElement === byID('gameSidebar')) {
  const {parent,next,open} = pausedLeaderboard;
  parent.insertBefore(leaderboardPanel,next?.parentElement === parent ? next : null);
  leaderboardPanel.open = open;
 }
 pausedLeaderboard = null;
 art.restoreSidebar(pauseSidebar);
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
 restorePauseSidebar();
}

function stop() {
 if (!session) return;
 resetControls();
 cancelAnimationFrame(frame);
 clearTimeout(connectTimer);
 const ws = socket;
 if (session.room) {
  clearRoomResume();
  if (ws?.readyState === WebSocket.OPEN) ws.send(JSON.stringify({type:'leave'}));
 }
 socket = null;
 session = null;
 art.renderLoadout(null,1);
 art.renderLoadout(null,2);
 dismissPause();
 if (resultDialog.open) resultDialog.close();
 if (arena.open) arena.close();
 art.restoreHeader(header);
 ws?.close();
 art.touchPolicy();
}

function exitArena() {
 const launcher = session?.launcher?.();
 stop();
 if (launcher?.getClientRects().length && !launcher.disabled && !document.querySelector('dialog[open]')) {
  launcher.focus({preventScroll:true});
 }
}

function syncRoom(code,token,active) {
 if (!session?.room || session.room.token !== token) return;
 if (active) session.room.code = code;
 else stop();
}

function closeRoom() {
 if (session?.room) stop();
}

function addController(world,seat) {
 Object.assign(seat,{camera:{x:CELL/2,y:CELL/2},fireTap:false,nextSend:0,keepAlive:0,seq:0,
  homingAlert:{},previewShotAt:-Infinity,pendingShotAt:-Infinity,predictor:new net.Predictor(world.moveTank)});
 world.controllers.push(seat);
 return seat;
}

function start(mode, options = {}) {
 if ((mode !== 'offline' && mode !== 'online') || arena.open) return;
 stop();
 const online = mode === 'online', name = options.name?.trim() || pilotName();
 const readBindings = typeof options.bindings === 'function' ? options.bindings : () => options.bindings;
 session = {
  online, name, localName:options.localName, readBindings, launcher:options.launcher, id:'pilot', tanks:[], bullets:[], pickups:[], leaderboard:[], controllers:[],
  room: online && options.code && options.token ? {code: options.code, token: options.token} : null,
  resumeGeneration:options.resumeGeneration,retries:0,
  rules:options.roomRules,teamScores:[0,0,0,0],previousTanks:new Map(),previousBullets:new Map(),
  time:0,nextBot:between(.4,1.2),nextPickup:0,pickupPilot:0,lastBot:0,lastBullet:0,nextHUD:0,lastEffect:0,botPool:[],botBudget:0,
  mapCache: new Map(), visibleBullets: [], visualEffects: [], interval: 1000 / 30, arrived: 0,
 };
 const world = session;
 world.moveTank = (tank, dx, dy, phaseEnded) => mazeMove(world.maze, tank, dx, dy, phaseEnded);
 addController(world,world);
 if (world.localName) world.local = addController(world,{id:online?null:'local'});
 if (retry) retry.hidden = true;
 arena.dataset.mode = mode;
 syncLocalLoadout(world.local);
 refreshBindings(world);
 art.mountHeader(header);
 arena.showModal();
 art.touchPolicy();
 canvas.focus({preventScroll: true});
 if (online) {
  if (world.room && world.resumeGeneration) saveRoomResume(world.room.token,world.resumeGeneration);
  connect();
 } else {
  session.maze = geometry.create(Math.floor(Math.random() * 0x100000000));
  const player = makeTank(session.id, session.camera.x, session.camera.y);
  player.name = name;
  const roster = options.roster || [];
  applyTankAppearance(world,player,roster.find(member=>member.id===options.primaryId));
  session.tanks.push(player);
  if (world.local) {
   const point = clearCell(world,player,2*CELL,4*CELL,2*CELL) || {x:player.x+2*CELL,y:player.y};
   const second = makeTank(world.local.id,point.x,point.y);
   second.name = world.localName;
   second.colorIndex = 1;
   applyTankAppearance(world,second,roster.find(member=>member.id===options.localId));
   world.tanks.push(second);
  }
  if (world.rules) for (const member of roster) {
   if (member.kind!=='bot'||member.spectating) continue;
   const point = clearCell(world,player,2.4*CELL,5.7*CELL,1.9*CELL) ||
    {x:player.x+world.tanks.length*8*CELL,y:player.y};
   const bot = makeTank('bot-' + ++world.lastBot,point.x,point.y,true);
   bot.name = member.name || bot.name;
   bot.difficulty = member.difficulty || 'normal';
   applyTankAppearance(world,bot,member);
   world.tanks.push(bot);
  }
  setStatus('Weapons live · ' + world.lastBot + ' bots');
  renderScores(session,player,world.local?world.tanks[1]:null);
 }
 lastTime = performance.now();
 accumulator = 0;
 frame = requestAnimationFrame(loop);
}

function updateMouse(event) {
 if (art.chatOpen()) {mouseAim=null;return false;}
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
 if (!session || session.result || pauseMenu.open || art.chatOpen() || session.online && !session.joined) return;
 art.primeAudioUnlock(event);
 seat.fireTap = true;
 const now = performance.now(), world = session;
 const pilot = seat.predictor.state;
 const age = now - world.arrived, boosted = pilot?.starmanTime > age / 1000;
 const canDetonate = pilot?.grenades > 0;
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
 const {cx,cy,reach} = touchAim;
 if (!reach) return;
 const x = event.clientX - cx, y = event.clientY - cy;
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
  touchAim.assisted = false;
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
 if (art.arenaKeyBlocked(event)) return;
 if (event.code === 'KeyF') {
  event.preventDefault();
  if (!event.repeat) art.toggleFullscreen();
  return;
 }
 if (session.result) return;
 if (event.target.tagName === 'INPUT') return;
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
 if (pauseMenu.open || art.chatOpen() || session.online && !session.joined) return;
 const seat = session.controllers.find(controller=>controller.keys[event.code]);
 const action = seat?.keys[event.code];
 if (!action) return;
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
 if (event.button !== 0 || stickPointer !== null || art.chatOpen()) return;
 capturePointer(stick, event);
 art.primeAudioUnlock(event);
 mouseAim = null;
 stickPointer = event.pointerId;
 touchAim.assisted = event.pointerType === 'touch' || event.pointerType === 'pen';
 const rect = stickBase.getBoundingClientRect(), size = Math.min(rect.width,rect.height);
 touchAim.cx = rect.left + rect.width / 2;
 touchAim.cy = rect.top + rect.height / 2;
 touchAim.reach = size > 0 ? Math.max(24,size*.375) : 0;
 updateStick(event);
 sendInput(session,performance.now(),true);
});
window.addEventListener('pointermove', event => {
 if (event.pointerId !== stickPointer) return;
 event.preventDefault();
 updateStick(event);
}, true);
fire.addEventListener('pointerdown', event => {
 if (event.button !== 0 || firePointer !== null || art.chatOpen()) return;
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
 renderScores(session,session.tanks.find(tank=>tank.id===session.id),session.tanks.find(tank=>tank.id===session.local?.id));
 pauseMenu.showModal();
 art.mountSidebar(pauseSidebar);
 pausedLeaderboard = {parent:leaderboardPanel.parentElement,next:leaderboardPanel.nextSibling,open:leaderboardPanel.open};
 const sidebar = byID('gameSidebar');
 sidebar.insertBefore(leaderboardPanel,sidebar.firstChild);
 leaderboardPanel.open = true;
 pauseMenu.scrollTop = 0;
 resetControls();
}
function resume() {
 if (!session || !pauseMenu.open) return;
 dismissPause();
 lastTime = performance.now();
 refreshBindings(session);
 resetControls();
 canvas.focus({preventScroll: true});
}
function togglePause() {
 if (pauseMenu.open) resume();
 else openPause();
}
byID('infiniteResumeBtn').addEventListener('click', resume);
byID('infiniteControlsBtn').addEventListener('click', () => {
 byID('infiniteControlsBtn').focus({preventScroll:true});
 art.openControls();
});
byID('infiniteExit').addEventListener('click', exitArena);
byID('infiniteResultExit').addEventListener('click',exitArena);
resultDialog.addEventListener('cancel',event=>{event.preventDefault();exitArena();});
retry?.addEventListener('click', () => {
 if (!session?.failed) return;
 session.resumeGeneration = session.retryAt = undefined;
 session.retries = 0;
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
pauseMenu.addEventListener('close', () => {
 if (!pauseMenu.open) restorePauseSidebar();
});
arena.addEventListener('close', event => {
 if (event.target === arena && !arena.open) stop();
});
window.addEventListener('blur', resetControls);
window.addEventListener('pagehide', resetControls);
document.addEventListener('visibilitychange', () => {
 if (document.hidden) resetControls();
});

const pickupHelp = `Power-ups spawn near active pilots. Most last ${POWER_DURATION} seconds after pickup. Starman lasts ${STAR_DURATION} seconds. Machine gun allows 3 seconds of firing. Uncollected power-ups expire after ${PICKUP_LIFETIME} seconds.`;
function sidebarHelp() {
 if (!session || !pauseMenu.open) return null;
 const target = session.rules?.infinityTarget;
 return {twoPilots:!!session.local,pickupHelp,starDuration:STAR_DURATION,weaponRange:SHOT_RANGE/CELL,
  instructions:'Gain a point for each kill and lose a point when your tank is destroyed. Respawn after '+RESPAWN_DELAY+' second. '+
   (target?'Reach '+target+' points to win.':'Keep playing and growing your score without a time limit.')};
}
window.leqraInfinity = Object.freeze({start, close: stop, resetControls, syncRoom, closeRoom, savedRoomGeneration, pickupHelp, sidebarHelp, togglePause});
art.roomSessionReady?.();
})();
