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
const scoreboardButton = byID('infiniteScoreboardBtn');
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
const PING_INTERVAL = 1000, PING_TIMEOUT = 6000;
const ROOM_RESUME_KEY = 'leqra.infinityResume.v1';
const BOT_LEVELS = ['dumb','easy','normal','hard','godlike'];
const BOT_TUNING = {
 dumb:{range:.35,roam:.4,aim:3},
 easy:{range:.7,roam:.75,aim:1.65}, normal:{range:1,roam:1,aim:1},
 hard:{range:1.15,roam:1.15,aim:.7}, godlike:{range:1.3,roam:1.3,aim:.45},
};
const PRIMARY_KEYS = {KeyW:'forward', KeyS:'reverse', KeyA:'left', KeyD:'right', KeyQ:'fire', KeyC:'fire'};
const LOCAL_KEYS = {ArrowUp:'forward', ArrowDown:'reverse', ArrowLeft:'left', ArrowRight:'right', Space:'fire', Enter:'fire'};
const pressed = new Set();
const touchAim = {x: 0, y: 0, cx: 0, cy: 0, reach: 0, assisted: false};
let session = null, frame = 0, socket = null, mouseAim = null, sessionSerial = 0, renameSerial = 0;
let stickPointer = null, firePointer = null, mousePointer = null, mouseTap = false;
let lastTime = 0, accumulator = 0, connectTimer = 0;
let pausedLeaderboard = null;

const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
const angleOf = n => Math.atan2(Math.sin(n), Math.cos(n));
const between = (a, b) => a + Math.random() * (b - a);
const cellCenter = n => (Math.floor(n / CELL) + .5) * CELL;

function pilotName() {
 try {
  return localStorage.getItem('leqra.name')?.trim() || 'Player 1';
 } catch {
  return 'Player 1';
 }
}

function setStatus(text) {
 if(!text&&session?.leaderboardNoticeUntil>performance.now())text=session.leaderboardNotice;
 status.hidden = !text;
 if (status.textContent !== text) status.textContent = text;
 renderOnlineCount(session);
}
function arenaName(world=session) {return world?.online&&(!world.room||world.public)?'Public Infinity':'Infinity';}
function acceptGodlikeSpawns(world,message,now){
 if(!world.online||world.room&&!world.public||!Array.isArray(message.godlikeSpawns))return;
 world.godlikeSeen ||= new Map();
 const names=[];
 for(const notice of message.godlikeSpawns.slice(0,24)){
  if(!Number.isSafeInteger(notice.id)||!Number.isSafeInteger(notice.spawnSerial)||typeof notice.name!=='string')continue;
  const tank=world.tanks.find(t=>t.id===notice.id&&t.spawnSerial===notice.spawnSerial&&t.bot&&t.difficulty==='godlike'&&t.hp>0);
  if(!tank)continue;
  const key=notice.id+':'+notice.spawnSerial;if(world.godlikeSeen.has(key))continue;
  world.godlikeSeen.set(key,true);if(world.godlikeSeen.size>128)world.godlikeSeen.delete(world.godlikeSeen.keys().next().value);
  names.push(tank.name);
 }
 if(names.length){const node=byID('godlikeSpawnNotice');node.textContent=names.slice(0,3).join(', ')+' spawned nearby. Watch out!';node.hidden=false;world.godlikeWarningUntil=now+6000;}
}

function localPilots(world=session) {
 if (!world) return [];
 return world.controllers.map((seat,index)=>{
  const tank=world.tanks.find(tank=>tank.id===seat.id);
  return {id:seat.id,member:'infinity-'+world.serial+'-'+index,name:tank?.name||(index?world.localName:world.name)||(index?'CO-PILOT':'Player 1'),
   color:COLORS[tank?.colorIndex??(index?world.localColorIndex:world.colorIndex)]||COLORS[index]};
 });
}

function pilotIdentity(world,index,tank) {
 return art.pilotIdentity(index,tank?{id:tank.id,name:tank.name||(index?world.localName:world.name),
  color:COLORS[tank.colorIndex]||COLORS[index]}:localPilots(world)[index],!!world.local);
}

function finishRename(world,index,error,name) {
 const pending=world.renames.get(index);if(!pending)return;
 world.renames.delete(index);clearTimeout(pending.timer);
 if(error)pending.reject(Error(error));
 else{applyPilotName(world,index,name);pending.resolve(name);}
}

function cancelRenames(world,message) {
 for(const index of [...world.renames.keys()])finishRename(world,index,message);
}

function applyPilotName(world,index,name) {
 const id=index?world.local?.id:world.id;
 if(index)world.localName=name;else world.name=name;
 for(const collection of [world.tanks,world.leaderboard,world.party])for(const tank of collection)if(tank.id===id)tank.name=name;
 const previous=world.previousTanks.get(id);if(previous)previous.name=name;
 if(world.result?.id===id&&!world.result.team)world.result.name=name;
 try{art.persistPilotName?.(index,name);}catch(_){}
 world.nextHUD=0;
 refreshBindings(world);
 renderScores(world,world.tanks.find(tank=>tank.id===world.id),world.tanks.find(tank=>tank.id===world.local?.id));
 if(pauseMenu.open)art.syncSidebarContext?.();
 if(resultDialog.open&&world.result){const winner=resultIdentity(world);byID('infiniteResultTitle').textContent=winner.label+' wins';byID('infiniteResultTitle').style.color=winner.color;}
}

function renamePilot(index,value) {
 const world=session;
 if(!world||![0,1].includes(index)||index===1&&!world.local)return Promise.reject(Error('That local tank is no longer available.'));
 const name=art.cleanPilotName(value);
 if(!name)return Promise.reject(Error('Enter letters or numbers for the callsign.'));
 if(world.renames.has(index))return Promise.reject(Error('A callsign change is already waiting for confirmation.'));
 if(!world.online){applyPilotName(world,index,name);return Promise.resolve(name);}
 if(!world.joined||world.failed||socket?.readyState!==WebSocket.OPEN||socket.bufferedAmount>4096)return Promise.reject(Error('Reconnect before changing the callsign.'));
 const requestId=++renameSerial;
 return new Promise((resolve,reject)=>{
  const pending={requestId,resolve,reject,timer:setTimeout(()=>finishRename(world,index,'Not confirmed yet. Check the connection and try again.'),6000)};
  world.renames.set(index,pending);
  try{socket.send(JSON.stringify({type:'rename',seat:index,name,requestId}));}
  catch(_){finishRename(world,index,'Could not send. Please try again.');}
 });
}

function acceptRename(message) {
 const world=session,index=message.seat,pending=world.renames.get(index);
 if(!pending||pending.requestId!==message.requestId)return;
 if(message.type==='rename_error'){finishRename(world,index,typeof message.message==='string'?message.message:'Could not change the callsign.');return;}
 const name=typeof message.name==='string'?art.cleanPilotName(message.name):'';
 if(!name){finishRename(world,index,'Unexpected callsign confirmation. Please try again.');return;}
 world.confirmedNames.set(index,name);
 finishRename(world,index,null,name);
}

function preserveConfirmedNames(world,message) {
 for(const [index,name] of world.confirmedNames){
  const id=index?world.local?.id:world.id;
  const echoed=message.tanks.some(tank=>tank.id===id&&tank.name===name);
  for(const collection of [message.tanks,message.leaderboard,Array.isArray(message.party)?message.party:[]])for(const tank of collection)if(tank.id===id)tank.name=name;
  if(message.result?.id===id&&!message.result.team)message.result.name=name;
  if(echoed)world.confirmedNames.delete(index);
 }
}

function resultIdentity(world) {
 const result=world.result,tank=world.tanks.find(tank=>tank.id===result.id);
 if (!result.team&&result.id===world.id) return pilotIdentity(world,0,tank);
 if (!result.team&&result.id===world.local?.id) return pilotIdentity(world,1,tank);
 return {label:result.name,color:result.team?COLORS[world.rules?.teamColors?.[result.team-1]]||COLORS[result.team-1]:COLORS[tank?.colorIndex]||COLORS[0]};
}

function renderOnlineCount(world) {
 const count=byID('infiniteOnlineCount');
 count.hidden=!world?.online;
 if(count.hidden)return;
 const known=world.joined&&!world.failed&&Number.isSafeInteger(world.players)&&world.players>=0,text=(known?world.players:'?')+' online';
 if(count.textContent!==text)count.textContent=text;
 count.title=known?'Human tanks in this arena':'Online player count is unavailable.';
}

function makeTank(id, x, y, bot = false) {
 return {
  id, x, y, bot, angle: between(-Math.PI, Math.PI), hp: 1, alive: true, score: 0,
  colorIndex: bot ? 1 + Math.floor(Math.random() * (COLORS.length - 1)) : 0,
  name: bot ? 'Bot ' + id.slice(4) : pilotName(), cooldown: 0, invulnerable: 1, spawnProtected: true, respawn: 0,
  track: 0, recoil: 0, speedStacks: 0, spawnSerial: 1,
  course: null, nextDecision: 0, nextDumbShot: null, dumbTarget: null, dumbAim: null, dumbAttack: false,
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

function mouseAimEnabled(){return art.mouseAimEnabled?.()!==false;}
function mouseFireEnabled(){return art.mouseFireEnabled?.()!==false;}
function mouseEnabled(){return mouseAimEnabled()||mouseFireEnabled();}

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
  input.fire ||= mouseFireEnabled()&&(mousePointer !== null||mouseTap)||firePointer !== null;
  if (mouseAimEnabled()&&stickPointer === null && mouseAim && !input.left && !input.right) {
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

function hurt(world, target, ownerID, ownerTeam, ownerName, starmanContact = false,ownerColor='') {
 if (world.result || !target.hp || target.invulnerable > 0 && !(starmanContact && target.spawnProtected) || !canDamage(world, ownerID, ownerTeam, target)) return;
 if (target.shield > 0 && !starmanContact) {
  target.shieldCharges = Math.max(0, (target.shieldCharges || 1) - 1);
  if (!target.shieldCharges) target.shield = 0;
  target.invulnerable = .35;
  target.spawnProtected = false;
  effect(world, 'shield', target.x, target.y, ownerID);
  return;
 }
 target.hp = 0;
 target.alive = false;
 target.respawn = RESPAWN_DELAY;
 target.score--;
 const owner = world.tanks.find(tank => tank.id === ownerID) || world.botPool?.find(tank => tank.id === ownerID);
 target.killedBy = owner?.name || ownerName || 'an unknown tank';
 target.killedByColor=owner?(art.canonicalColor?.(owner.colorIndex)||COLORS[owner.colorIndex]||''):ownerColor;
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
      !wallHit(world.maze, bullet.x, bullet.y, dx, dy, 0)) hurt(world, tank, bullet.owner, bullet.team, bullet.ownerName,false,bullet.color||'');
 }
}

function weaponControl(world, tank, held, pressed) {
 tank.fireHeld = held;
 if (!held) tank.fireBlocked = false;
 if (tank.spawnProtected && tank.invulnerable > 1e-9) return;
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
 const launch=projectileLaunch(world,tank,tank.angle,3,28);
 if(!launch.valid)return{points:[{x:tank.x,y:tank.y},{x:tank.x,y:tank.y}],target:null};
 let {x,y,ux,uy}=launch,length=SHOT_RANGE-launch.distance;
 const points = [];
 for (let i = 0; i < 128 && length > 1e-7; i++) {
  const dx = ux * length, dy = uy * length;
  const wall = wallHit(world.maze, x, y, dx, dy, 3);
  const limit = wall?.fraction ?? 1;
  const hit = preview ? {fraction:limit} : tankHit(world, {x, y, owner:tank.id, team:tank.team, r:3}, dx, dy, limit);
  const distance = length * hit.fraction;
  if (!i) {const crop=launch.bounced?0:Math.min(distance,28);points.push({x:x+ux*crop,y:y+uy*crop});}
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
 return false; // Wall contacts ricochet at launch instead of blocking readiness.
}

function projectileLaunch(world,tank,angle,radius,muzzle){
 const ux=Math.cos(angle),uy=Math.sin(angle),{x,y}=tank;
 if(tank.power==='cannon'||!(tank.ghostTime>0))return{x,y,ux,uy,distance:0,muzzle,bounced:false,valid:true};
 return net.wallLaunch(x,y,ux,uy,radius,muzzle,world.maze.wallsNear(x-radius-32,y-radius-32,x+radius+32,y+radius+32));
}

function fireShot(world, tank) {
 const boosted = tank.starmanTime > 0;
 if (!tank.hp || tank.spawnProtected && tank.invulnerable > 1e-9) return;
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
  const angle = tank.angle + offset,launch=projectileLaunch(world,tank,angle,spec.r,kind==='cannon'?RADIUS+spec.r+1:28),ux=launch.ux,uy=launch.uy;
  if(!launch.valid){effect(world,'impact',tank.x,tank.y,tank.id);continue;}
  const bullet = {
   ...spec, id: ++world.lastBullet, owner: tank.id, ownerName: tank.name, team:tank.team, kind, boosted, x: launch.x, y: launch.y, color: COLORS[tank.colorIndex] || COLORS[0],
   vx: ux * spec.speed, vy: uy * spec.speed, age: 0, bounces: launch.bounced?1:0, seekDelay: launch.bounced?.04:0, target: null, trail: [],
  };
  if (advanceBullet(world, bullet, launch.muzzle / spec.speed)) world.bullets.push(bullet);
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
    hurt(world, hit.tank, bullet.owner, bullet.team, bullet.ownerName,false,bullet.color||'');
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
 if (tank.difficulty === 'dumb' && world.time < tank.nextDecision && tank.dumbTarget != null) {
  pilot = targets.find(target => target.id === tank.dumbTarget && target.hp && target !== tank && !(tank.team && target.team === tank.team));
 }
 if (!pilot) return net.neutral();
 const tune = BOT_TUNING[tank.difficulty] || BOT_TUNING.normal;
 const dx = pilot.x - tank.x, dy = pilot.y - tank.y, distance = Math.hypot(dx, dy);
 const seesPilot = distance < CELL * (tank.difficulty === 'dumb' ? 8 : 6) * tune.range && !wallHit(world.maze, tank.x, tank.y, dx, dy, BULLET_RADIUS);
 if (tank.difficulty === 'dumb') {
  if (!Number.isFinite(tank.nextDumbShot)) tank.nextDumbShot = world.time + 1.8;
  if (world.time >= tank.nextDecision) {
   tank.nextDecision = world.time + .9;
   tank.dumbTarget = pilot.id;
   tank.dumbAim = Math.atan2(dy, dx) + between(-.6,.6);
   tank.dumbAttack = Math.random() >= .35;
   if (!seesPilot) tank.course = botCourse(world.maze, tank, pilot);
  }
  const tx = seesPilot ? Math.cos(tank.dumbAim) : (tank.course?.x ?? tank.x) - tank.x;
  const ty = seesPilot ? Math.sin(tank.dumbAim) : (tank.course?.y ?? tank.y) - tank.y;
  const aim = Math.atan2(ty,tx);
  const fire = seesPilot && tank.dumbAttack && !(pilot.invulnerable > 0) && world.time >= tank.nextDumbShot && Math.abs(angleOf(aim-tank.angle)) < .36;
  if (fire) tank.nextDumbShot = world.time + 1.8;
  return {stickX:Math.cos(aim)*.72*tune.roam,stickY:Math.sin(aim)*.72*tune.roam,aimOnly:seesPilot||Math.hypot(tx,ty)<5,fire};
 }
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
 if (nearby >= 3 || world.pickups.length >= locals.length * 6) return;
 const cx = cellCenter(pilot.x), cy = cellCenter(pilot.y);
 for (let i = 0; i < 90 && nearby < 3 && world.pickups.length < locals.length * 6; i++) {
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
  spawnSerial: tank.spawnSerial + 1, killedBy: '', killedByColor:'',power: '', powerTime: 0, charges: 0, shield: 0, shieldCharges: 0,
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
  if (!tank.invulnerable) tank.spawnProtected = false;
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
  (world.movementInputs ||= new Map()).set(tank.id,controls);
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
   if (!target.hp || target.invulnerable > 0 && !target.spawnProtected || target.starmanTime > 0 ||
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

function alignControlHints(hint) {
 const rows = [...hint.querySelectorAll('.control-groups')].map(row=>[...row.children].slice(0,5));
 if (rows.length!==2 || rows.some(row=>row.length!==5)) return;
 const saved = rows.flat().map(group=>({group,width:group.style.width,maxWidth:group.style.maxWidth}));
 for (const {group} of saved) {group.style.width='max-content';group.style.maxWidth='none';}
 const widths = rows[0].map((_,index)=>Math.ceil(Math.max(...rows.map(row=>row[index].getBoundingClientRect().width))));
 for (const {group,width,maxWidth} of saved) {group.style.width=width;group.style.maxWidth=maxWidth;}
 for (const row of rows) row.forEach((group,index)=>{group.style.width=widths[index]+'px';});
}

function refreshBindings(world) {
 const bindings = world.readBindings();
 const layout = Array.isArray(bindings) ? bindings : [bindings];
 world.keys = world.local ? setupBindings(layout[0],PRIMARY_KEYS) : setupBindings(layout,{...PRIMARY_KEYS,...LOCAL_KEYS});
 if (world.local) world.local.keys = setupBindings(layout[1],LOCAL_KEYS);
 const hint = byID('infiniteControlsHint');
 if (!hint) return;
 const pilot=pilotIdentity(world,0),second=world.local&&pilotIdentity(world,1);
 const content=art.controlHintHTML(world.keys,second?pilot.label:'',art.isTouchUI()?'touch':mouseEnabled()?'mouse':'',pilot.color)+
  (second?art.controlHintHTML(world.local.keys,second.label,'',second.color):'');
 if(hint.innerHTML!==content){
  hint.innerHTML=content;
  const revision=world.controlHintRevision=(world.controlHintRevision||0)+1;
  const align=()=>{if(session===world&&arena.open&&world.controlHintRevision===revision&&!art.isTouchUI())alignControlHints(hint);};
  Promise.resolve().then(align);
  document.fonts?.ready.then(align);
 }
 canvas.setAttribute('aria-label',arenaName(world)+' maze. '+pilot.label+(second?' and '+second.label:'')+'. Controls are listed below the arena.');
 fire.setAttribute('aria-label','Fire for '+pilot.label);
 stick.setAttribute('aria-label','Move and aim '+pilot.label);
 world.controlPilots=JSON.stringify(localPilots(world));
 art.syncCallsignEditors?.();
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

function offlineTankPose(world,tank,remaining) {
 const seat=world.controllers.find(seat=>seat.id===tank.id);
 const input=seat?inputState(seat):world.movementInputs?.get(tank.id)||net.neutral();
 if(seat){
  seat.motion ||= new net.MotionPresenter();
  return seat.motion.render(tank,input,remaining,Math.round(world.time/STEP),world.moveTank);
 }
 return net.visualMove(tank,input,remaining,world.moveTank);
}

function offlineBulletPose(world,bullet,remaining) {
 if(!(remaining>0))return bullet;
 const value={...bullet},span=Math.min(remaining,bullet.life);
 value.life-=span;value.age=(value.age||0)+span;
 if(!world.online&&(value.kind==='homing'||value.kind==='grenade'))guide(world,value,span);
 if(value.kind==='grenade'){
  const drag=art.grenadeDragFactor(bullet.life,value.life);value.vx*=drag;value.vy*=drag;
 }
 let rest=span;
 for(let i=0;i<4&&rest>1e-8;i++){
  const dx=value.vx*rest,dy=value.vy*rest;
  const wall=value.kind==='cannon'?null:wallHit(world.maze,value.x,value.y,dx,dy,value.r);
  const hit=world.online?null:tankHit(world,value,dx,dy,wall?.fraction??1.00000001);
  if(hit?.tank){value.x+=dx*hit.fraction;value.y+=dy*hit.fraction;break;}
  if(!wall){value.x+=dx;value.y+=dy;break;}
  value.x+=dx*wall.fraction+wall.nx*.12;value.y+=dy*wall.fraction+wall.ny*.12;value.bounces++;
  if(wall.nx)value.vx=-value.vx;if(wall.ny)value.vy=-value.vy;
  rest*=1-wall.fraction;
 }
 return value;
}

function onlineBulletPose(world,bullet,frame){
 if(!frame?.a.bulletMap||!frame.b.bulletMap)return undefined;
 if(frame.time<frame.a.netTime)return null;
 const a=frame.a.bulletMap.get(bullet.id),b=frame.b.bulletMap.get(bullet.id);
 if(frame.alpha===1)return b?offlineBulletPose(world,b,Math.min(.075,frame.extrapolate)):null;
 if(!a)return null;
 const span=(frame.b.netTime-frame.a.netTime)/1000,elapsed=Math.max(0,frame.time-frame.a.netTime)/1000;
 if(!b)return offlineBulletPose(world,a,Math.min(.075,elapsed));
 if(a.bounces!==b.bounces){
  const cache=world.ricochetPaths||=new Map(),key=frame.a.tick+':'+frame.b.tick+':'+bullet.id;
  let saved=cache.get(key);
  if(!saved||saved.a!==a||saved.b!==b){saved={a,b,path:net.RicochetPath.between(a,b,span,(kind,x,y,dx,dy,r)=>kind==='cannon'?null:wallHit(world.maze,x,y,dx,dy,r))};if(cache.size>=256)cache.delete(cache.keys().next().value);cache.set(key,saved);}
  return saved.path?saved.path.sample(frame.alpha):offlineBulletPose(world,a,Math.min(.075,elapsed));
 }
 const f=frame.alpha;
 return {...b,x:a.x+(b.x-a.x)*f,y:a.y+(b.y-a.y)*f,vx:a.vx+(b.vx-a.vx)*f,vy:a.vy+(b.vy-a.vy)*f,life:a.life+(b.life-a.life)*f,trail:b.kind==='rapid'?null:b.trail||[a,b]};
}

function drawTank(tank, highlight, zoom, ratio, label=tank.name||'Tank', viewLeft=-Infinity, viewTop=-Infinity, viewRight=Infinity) {
 const color = COLORS[tank.colorIndex] || COLORS[0];
 ctx.save();
 ctx.translate(tank.x, tank.y);
 const shields = tank.shield > 0 ? tank.shieldCharges || 1 : 0;
 if (shields || tank.invulnerable > 0 || highlight) {
  ctx.strokeStyle = shields ? powers.shield.color : highlight ? color : art.theme.protection;
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
 const labelFont=Math.max(11,10/zoom);
 ctx.font = 'bold '+labelFont+'px ui-monospace,SFMono-Regular,Consolas,monospace';
 ctx.textAlign = 'center';
 const width = (ctx.measureText(label)?.width || 30) + 10,height=Math.max(16,labelFont*1.25+3);
 ctx.fillStyle = '#0e171ddb';
 art.rect(ctx, -width / 2, -32-height, width, height, 3);
 ctx.fill();
 ctx.fillStyle = color;
 ctx.fillText(label, 0, -32-height+(height-3)/1.25);
 if (tank.bot && tank.difficulty === 'godlike') {
  const warningWidth = (ctx.measureText('GODLIKE')?.width || 50) + 12;
  const warningX = clamp(0,viewLeft-tank.x+warningWidth/2+2/zoom,viewRight-tank.x-warningWidth/2-2/zoom);
  const warningY = Math.max(viewTop-tank.y+2/zoom,-32-height*2-Math.max(3,3/zoom));
  ctx.fillStyle = '#302217f2';
  ctx.strokeStyle = '#ffc46b';ctx.lineWidth = Math.max(1,1/zoom);
  art.rect(ctx,warningX-warningWidth/2,warningY,warningWidth,height,3);ctx.fill();ctx.stroke();
  ctx.fillStyle = '#ffc46b';ctx.fillText('GODLIKE',warningX,warningY+(height-3)/1.25);
 }
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
 const score = tank => String(tank?.score ?? 0);
 if (personalScore) {
  const rows = [pilot,...(world.local?[second]:[])].map((tank,index)=>{
   const identity=pilotIdentity(world,index,tank),rank=world.online?tank?.rank:standings.findIndex(entry=>entry.id===tank?.id)+1;
   return [identity.label,score(tank),rank,identity.color];
  });
  const signature = JSON.stringify(rows);
  if (signature !== world.personalScoreRows) {
   world.personalScoreRows = signature;
   const children = [];
   for (const [label,score,rank,color] of rows) {
    const counter = document.createElement('span');
    counter.className = 'infinite-personal-score';
    counter.style.color = color;
    const total='score: '+score+', rank: #'+(rank>0?rank:0);
    counter.setAttribute('aria-label',label+': '+total);
    const name=document.createElement('span');name.className='infinite-score-name';name.textContent=label;
    const separator=document.createElement('span');separator.className='infinite-score-separator';separator.textContent=': ';
    const value=document.createElement('span');value.className='infinite-score-value';value.textContent=total;
    counter.append(name,separator,value);
    children.push(counter);
   }
   personalScore.replaceChildren(...children);
  }
 }
 if (!leaderboard) return;
 const entries = standings.slice(0, 10);
 const publicArena = world.online && (!world.room || world.public);
 const party = world.public ? world.party || [] : [];
 const partyIDs = new Set(party.map(tank=>tank.id));
 const title = 'LEADERBOARD';
 const standingRow = (tank,rank,extra=false) => {
  const local = tank.id===world.id ? 1 : tank.id===world.local?.id ? 2 : 0;
  const name = local ? pilotIdentity(world,local-1,tank).label : art.botName?.(tank.name||'Tank',tank.bot) || tank.name || 'Tank';
  return [name, tank.score, local, COLORS[tank.colorIndex] || COLORS[0],rank,extra,partyIDs.has(tank.id)];
 };
 const rows = entries.map((tank,i) => standingRow(tank,i+1));
 const seen = new Set(entries.map(tank=>tank.id)), extraRows = [];
 for (const id of new Set([world.id,world.local?.id,...partyIDs])) {
  if (id==null || seen.has(id)) continue;
  const tank = party.find(tank=>tank.id===id) || world.tanks.find(tank=>tank.id===id);
  const rank = world.online ? tank?.rank : standings.indexOf(tank)+1;
  if (!tank || !Number.isSafeInteger(rank) || rank<=10) continue;
  extraRows.push(standingRow(tank,rank,true));
  seen.add(id);
 }
 extraRows.sort((a,b)=>a[4]-b[4]);
 rows.push(...extraRows);
 const teams = !publicArena && world.rules?.teamMode==='teams' ? world.teamScores.flatMap((score,i)=>
  i<2||score||entries.some(tank=>tank.team===i+1)?[[teamName(world,i+1),score,0,COLORS[world.rules.teamColors?.[i]] || COLORS[i]]]:[]) : [];
 const signature = JSON.stringify([title,rows,teams]);
 if (signature === world.scoreRows) return;
 world.scoreRows = signature;
 leaderboardTitle.textContent = title;
 scoreboardButton.textContent = title;
 const makeRow = ([name, score, local, color,rank,extra,partyMember]) => {
  const row = document.createElement('li');
  if (rank) row.value = rank;
  if (extra) row.className = 'off-board-local';
  if (partyMember) row.dataset.party = 'true';
  row.style.setProperty('--tank-color',color);
  if (local) {
   row.dataset.local = 'p' + local;
   row.style.setProperty('--local-highlight',color);
  }
  const callsign = document.createElement('span');
  const total = document.createElement('strong');
  callsign.textContent = name + (!local&&partyMember?' (room)':'');
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
 if(!(world.godlikeWarningUntil>now))byID('godlikeSpawnNotice').hidden=true;
 if (!pilot || world.failed || world.online && !world.joined || now < world.nextHUD) return;
 world.nextHUD = now + 1000 / 30;
 if(world.controlPilots!==JSON.stringify(localPilots(world)))refreshBindings(world);
 renderScores(world,pilot,second);
 setStatus('');
 renderOnlineCount(world);
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
 world.remoteFrame=world.online&&!world.result?world.motionBuffer?.advance(dt):null;
 const remaining=!world.online&&!world.result&&!pauseMenu.open?accumulator:0;
 world.displayTanks ||= new Map();world.displayTanks.clear();
 if(!world.online)for(const tank of world.tanks)world.displayTanks.set(tank.id,!world.result&&!pauseMenu.open?offlineTankPose(world,tank,remaining):tank);
 for (const seat of world.controllers) {
  const authority = world.tanks.find(tank=>tank.id===seat.id);
  const pilot = world.online&&!world.result ? seat.predictor.visual(dt)||authority : world.displayTanks.get(seat.id)||authority;
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
  const remote=!owner&&world.online&&world.remoteFrame?world.motionBuffer.tank(tank.id,world.remoteFrame,world.moveTank):null;
  const displayed = owner?.display || (world.online ?
   art.ageTank({... (remote||interpolate(world.previousTanks.get(tank.id),tank,alpha))},tank,age) : world.displayTanks.get(tank.id)||tank);
  if (!visible(displayed)) continue;
  if (owner&&now<owner.previewRecoilUntil) displayed.recoil = Math.max(displayed.recoil || 0,(owner.previewRecoilUntil-now)/100);
  drawTank(displayed, !!owner, zoom, ratio,
   owner?pilotIdentity(world,owner===world?0:1,tank).label:art.botName?.(tank.name||'Tank',tank.bot)||tank.name||'Tank',x0,y0,x1);
 }
 const bullets = world.visibleBullets;
 bullets.length = 0;
 for (const bullet of world.bullets) {
  if (!visible(bullet)) continue;
  if(world.online){const displayed=onlineBulletPose(world,bullet,world.remoteFrame);if(displayed!==undefined){if(displayed)bullets.push({...displayed,trail:displayed.kind==='rapid'?noTrail:displayed.trail||null});continue;}}
  const previous = world.online && world.previousBullets.get(bullet.id);
  if (previous && previous.bounces === bullet.bounces) {
   const {kind, color, r, life, vx, vy} = bullet;
   bullets.push({kind, color, r, life, vx, vy,
    x: previous.x + (bullet.x - previous.x) * alpha, y: previous.y + (bullet.y - previous.y) * alpha,
    trail: kind === 'rapid' ? noTrail : bullet.trail || [previous, bullet]});
  } else bullets.push(!world.online&&!world.result&&!pauseMenu.open?offlineBulletPose(world,bullet,accumulator):bullet);
 }
 art.bullets(bullets, ctx, now / 1000);
 if (!world.result && !world.failed && !pauseMenu.open) {
  art.drawHomingWarnings(ctx,pilot,world.bullets,(b,target)=>canDamage(world,b.owner,b.team,target));
 }
 drawEffects(world, now);
 ctx.restore();
 if (world.local) {
  ctx.save();
  const identity=pilotIdentity(world,seat===world?0:1,pilot);
  ctx.font = 'bold 12px ui-monospace,monospace';
  const badgeWidth=Math.max(36,Math.min(width-18,(ctx.measureText(identity.label)?.width||identity.label.length*7)+18));
  ctx.fillStyle = art.theme.arena;
  art.rect(ctx,left+9,top+9,badgeWidth,24,5);
  ctx.fill();
  ctx.strokeStyle = identity.color;
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.fillStyle = identity.color;
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  ctx.fillText(identity.label,left+18,top+21,badgeWidth-18);
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
 if(seat===world)mouseTap=false;
}

function measureLatency(world, now) {
 if (!world.online || !world.joined || world.result || world.failed || socket?.readyState !== WebSocket.OPEN) return;
 if (world.latency !== null && now-world.latencyAt > PING_TIMEOUT) world.latency = null;
 if (world.pendingPing !== null && now-world.pendingPing > PING_TIMEOUT) world.pendingPing = null;
 if (now < world.nextPing || world.pendingPing !== null || socket.bufferedAmount > 4096) return;
 world.pendingPing = now;
 world.nextPing = now+PING_INTERVAL;
 socket.send(JSON.stringify({type:'ping',t:now}));
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
 const winner=resultIdentity(world);
 byID('infiniteResultTitle').textContent = winner.label + ' wins';
 byID('infiniteResultTitle').style.color=winner.color;
 byID('infiniteResultScore').textContent = 'Final score ' + world.result.score;
 resultDialog.showModal();
}

function loop(now) {
 if (!arena.open || !session) return;
 const workStart = performance.now();
 const dt = clamp((now - lastTime) / 1000, 0, .1);
 measureLatency(session,now);
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
   mouseTap=false;
   accumulator = Math.max(0, accumulator - STEP);
  }
 }
 lastTime = now;
 const audioAge=session.online?Math.max(0,(now-session.arrived)/1000):0;
 art.starmanAudio?.(!pauseMenu.open&&!session.result&&(!session.online||session.joined&&audioAge<2)&&session.controllers.some(seat=>{const tank=session.tanks.find(tank=>tank.id===seat.id);return tank?.hp>0&&tank.starmanTime>audioAge;}));
 showResult(session, now);
 if (session.online ? session.joined || session.retryAt === undefined : !pauseMenu.open) draw(session, now, dt);
 art.sampleFrame(now,performance.now()-workStart,session.online?(session.latency??NaN):null);
 frame = requestAnimationFrame(loop);
}

function connectionFailed(message) {
 if (!session?.online) return;
 cancelRenames(session,'The connection was interrupted. Try again after reconnecting.');
 clearTimeout(connectTimer);
 if (session.room) clearRoomResume();
 session.failed = true;
 session.joined = false;
 session.latency = session.pendingPing = null;
 resetControls();
 art.renderLoadout(null,1);
 art.renderLoadout(null,2);
 setStatus(message + (session.room ? ' Use Exit '+arenaName(session)+' in the pause menu to return to your room.' :
  ' Choose Infinity in Room settings to play offline.'));
 if (retry) retry.hidden = false;
 socket?.close();
}

function retryConnection(message) {
 if (!session.room&&!session.publicToken&&!session.publicFallback) {connectionFailed(message);return;}
 const world = session, now = performance.now(), durable=(!session.room||session.public)&&(!!session.publicToken||!!session.publicFallback);
 if(durable&&world.public){world.room=null;world.party=[];clearRoomResume();}
 cancelRenames(world,'The connection was interrupted. Try again after reconnecting.');
 world.retryAt ??= now;
 const remaining = durable?Infinity:world.retryAt + RECONNECT_WINDOW - now;
 if (remaining <= 0) {connectionFailed(message);return;}
 clearTimeout(connectTimer);
 const old = socket;
 socket = null;
 world.joined = false;
 world.latency = world.pendingPing = null;
 resetControls();
 old?.close();
 setStatus('Connection interrupted, Reconnecting to '+(world.room&&!world.public?'room Infinity':arenaName(world))+'…');
 const delay = Math.min(remaining, 3000, 450 * 2 ** Math.min(world.retries++,3));
 connectTimer = setTimeout(() => {
  if (session === world) {
   if (!durable&&performance.now() >= world.retryAt + RECONNECT_WINDOW) connectionFailed(message);
   else connect();
  }
 },delay);
}

function watchSnapshots(ws) {
 const delay = document.hidden ? SNAPSHOT_TIMEOUT : Math.max(1,SNAPSHOT_TIMEOUT + session.arrived - performance.now());
 connectTimer = setTimeout(() => {
  if (ws !== socket || !session?.joined || session.result) return;
  if (!document.hidden && performance.now() - session.arrived >= SNAPSHOT_TIMEOUT) retryConnection('Disconnected from '+arenaName(session)+'.');
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
  connectionFailed('Unexpected response from the '+arenaName(session)+' server.');
  return;
 }
 if(message.type==='renamed'||message.type==='rename_error'){acceptRename(message);return;}
 if(message.type==='leaderboard_reset'){
  session.leaderboardNotice=message.selected===true?'Selected Public Infinity scores were reset.':'The Public Infinity leaderboard was reset.';
  session.leaderboardNoticeUntil=performance.now()+5000;setStatus(session.leaderboardNotice);return;
 }
 if (message.type === 'pong') {
  const now=performance.now(), elapsed=now-message.t;
  if (session.joined && session.pendingPing !== null && Number.isFinite(message.t) && message.t===session.pendingPing && elapsed>=0 && elapsed<=PING_TIMEOUT) {
   session.pendingPing = null;
   session.latency = Math.round(elapsed);
   session.latencyAt = now;
  }
  return;
 }
 if (message.type === 'error') {
  if(message.code==='session_replaced'){art.exposeAccountError?.();connectionFailed((message.seat===1?'P2’s tank':'Your tank')+' was taken over by another device using this account.');return;}
  if(message.code==='account_key_revoked'){art.exposeAccountError?.();const seat=message.seat===1?1:0;art.forgetRevokedAccount?.(seat?session.localPublicToken:session.publicToken,seat);connectionFailed((seat?'P2’s':'P1’s')+' account key was reset. Import the latest key in Account to continue.');return;}
  if(message.code==='callsign_taken'&&session.onConflict){session.onConflict(message);return;}
  if(message.code==='public_resume_invalid'&&!session.publicFallback){session.publicFallback=true;const previous=session.publicToken;session.publicToken='';art.rememberPublicIdentity?.('',previous||'');retryConnection('Rejoining Public Infinity…');return;}
  if(message.code==='server_shutdown'||message.code==='public_store_busy'){retryConnection(message.message||'Reconnecting…');return;}
  const error = message.message || 'Unable to join '+arenaName(session)+'.';
  if (message.code === 'session_active' && session.resumeGeneration) retryConnection(error);
  else connectionFailed(error);
  return;
 }
 if (message.type === 'welcome') {
  if(session.independentAccounts&&message.localId!=null&&message.localPublicToken!==session.localPublicToken){connectionFailed('The server did not confirm the separate P2 account key. Update the server before using P2 online.');return;}
  session.welcomed=true;
  if(message.publicToken){art.rememberPublicIdentity?.(message.publicToken,session.publicToken||'');session.publicToken=message.publicToken;}
  if(message.localPublicToken){art.rememberPublicIdentity?.(message.localPublicToken,session.localPublicToken||'',1);session.localPublicToken=message.localPublicToken;session.localNewAccount=undefined;}
  if(message.localId==null){session.localPublicToken='';session.localNewAccount=undefined;}
  session.resumed = !!message.resumed;
  if (Array.isArray(message.party)) session.party = message.party;
  session.id = message.id;
  if (message.localId != null) {
   if (!session.local) {
    session.local = addController(session,{});
    refreshBindings(session);
   }
   session.local.id = message.localId;
  } else if (session.local) {
   finishRename(session,1,'That local tank is no longer available.');session.confirmedNames.delete(1);
   session.controllers.pop();
   session.local = null;
   refreshBindings(session);
  }
  syncLocalLoadout(session.local);
  if (!session.maze || session.seed !== message.seed) {
   session.maze = geometry.create(message.seed);
   session.seed = message.seed;
   session.mapCache.clear();
   session.motionBuffer?.reset();
  }
  if (session.room && Number.isSafeInteger(message.generation) && message.generation > 0) {
   session.resumeGeneration = message.generation;
   saveRoomResume(session.room.token,message.generation);
  }
  return;
 }
 if (message.type !== 'state' || !session.maze) return;
 if (!Array.isArray(message.tanks) || !Array.isArray(message.bullets) || !Array.isArray(message.leaderboard)) {
  connectionFailed('Unexpected state from the '+arenaName(session)+' server.');
  return;
 }
 preserveConfirmedNames(session,message);
 const now = performance.now(), joined = session.joined, resumed = !joined && session.resumed;
 session.previousTanks = new Map(session.tanks.map(tank => [tank.id, tank]));
 session.previousBullets = new Map(session.bullets.map(bullet => [bullet.id, bullet]));
 session.interval = session.arrived ? clamp(now - session.arrived, 20, 90) : 1000 / 30;
 session.arrived = now;
 session.tanks = message.tanks.map(tank => ({...tank, alive: tank.hp > 0}));
 acceptGodlikeSpawns(session,message,now);
 session.bullets = message.bullets.map(bullet => ({...bullet, trail: bullet.trail || null,
  color: COLORS[bullet.colorIndex] || COLORS[0], r: (PROJECTILES[bullet.kind || 'regular'] || PROJECTILES.regular).r}));
 if(Number.isSafeInteger(message.tick)){
  session.motionBuffer ||= new net.SnapshotBuffer({delay:1000/30,minimumDelay:1000/30,maximumDelay:90,intervals:1});
  if(!joined)session.motionBuffer.reset();
  session.motionBuffer.push({tick:message.tick,tanks:session.tanks,tankMap:new Map(session.tanks.map(tank=>[tank.id,tank])),bullets:session.bullets,bulletMap:new Map(session.bullets.map(bullet=>[bullet.id,bullet]))},now);
 }
 session.pickups = Array.isArray(message.pickups) ? message.pickups : [];
 session.players = message.players;
 session.tankCount = message.tankCount ?? message.leaderboard.length;
 session.leaderboard = message.leaderboard;
 if (Array.isArray(message.party)) session.party = message.party;
 if (message.rules && !session.public) session.rules = message.rules;
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
 setStatus('');
 renderOnlineCount(session);
 if (message.result) session.result = message.result;
 if (!joined) {
  const onJoined = session.onJoined;session.onJoined = null;
  onJoined?.();
  session.retryAt = undefined;
  session.retries = 0;
  session.nextHUD = 0;
  if (resumed || pauseMenu.open) for (const seat of session.controllers) sendInput(seat,now,true);
  clearTimeout(connectTimer);
  if (session.room && !session.result) watchSnapshots(ws);
  measureLatency(session,now);
 }
}

function connect() {
 if (!session?.online) return;
 const world = session;
 cancelRenames(world,'The connection was interrupted. Try again after reconnecting.');
 clearTimeout(connectTimer);
 const oldSocket = socket;
 socket = null;
 oldSocket?.close();
 world.failed = false;
 world.joined = false;
 world.latency = world.pendingPing = null;
 world.nextPing = performance.now();
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
  connectionFailed(arenaName(world)+' requires the leqra server.');
  if (retry) retry.hidden = true;
  return;
 }
 const destination=world.room&&!world.public?'room Infinity':arenaName(world);
 setStatus((world.resumeGeneration || world.retryAt !== undefined ? 'Reconnecting to ' : 'Connecting to ')+destination+'…');
 const url = new URL('/ws/infinite', location.href);
 url.protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
 let ws;
 try {
  ws = socket = new WebSocket(url);
 } catch {
  retryConnection('Could not connect to '+arenaName(world)+'.');
  return;
 }
 ws.addEventListener('open', () => {
  if (ws === socket && session === world) {
   ws.send(JSON.stringify({type:'join',version:window.leqra.version,name:world.name,
    localName:world.room?undefined:world.localName,
    colorIndex:world.room?undefined:world.colorIndex,
    localColorIndex:world.room||!world.localName?undefined:world.localColorIndex,...world.room,
    independentAccounts:world.independentAccounts||undefined,localPublicToken:world.localPublicToken||undefined,localNewAccount:world.localNewAccount,updateNames:!world.welcomed?true:undefined,publicToken:world.publicToken||undefined,resume:world.resumeGeneration||world.publicToken?true:undefined,generation:world.resumeGeneration}));
  }
 });
 ws.addEventListener('message', event => receive(ws, event));
 ws.addEventListener('close', () => {
  if (ws === socket && session === world && !world.failed && !world.result) {
   retryConnection((world.joined ? 'Disconnected from ' : 'Could not join ')+arenaName(world)+'.');
  }
 });
 connectTimer = setTimeout(() => {
  if (ws === socket && session === world && !world.joined) retryConnection('Could not connect to '+arenaName(world)+'.');
 }, (!world.room||world.public)&&(world.publicToken||world.publicFallback)?6500:Math.min(6500,(world.retryAt ?? performance.now()) + RECONNECT_WINDOW - performance.now()));
}

function resetControls() {
 pressed.clear();
 mouseAim = null;
 mouseTap=false;canvas.style.cursor=mouseEnabled()?'':'auto';
 stickPointer = firePointer = mousePointer = null;
 fire.classList.remove('held');
 touchAim.x = touchAim.y = 0;
 touchAim.assisted = false;
 knob.style.removeProperty('--stick-x');
 knob.style.removeProperty('--stick-y');
 if (session) for (const seat of session.controllers) {
  seat.fireTap = false;
  seat.predictor.neutralize();
  sendInput(seat,performance.now(),true);
 }
}

function resetMouseControls(kind) {
 if(kind!=='fire')mouseAim=null;
 if(kind!=='aim'){mousePointer=null;mouseTap=false;}
 canvas.style.cursor=mouseEnabled()?'':'auto';
 if(session){refreshBindings(session);sendInput(session,performance.now(),true);}
}

function syncScoreboardButton() {
 scoreboardButton.setAttribute('aria-expanded',String(leaderboardPanel.open));
 if(!leaderboardPanel.open&&document.activeElement===leaderboardTitle)scoreboardButton.focus({preventScroll:true});
}

function restorePauseSidebar() {
 if (pausedLeaderboard && leaderboardPanel.parentElement === byID('gameSidebar')) {
  const {parent,next,open} = pausedLeaderboard;
  parent.insertBefore(leaderboardPanel,next?.parentElement === parent ? next : null);
  leaderboardPanel.open = open;
 }
 pausedLeaderboard = null;
 syncScoreboardButton();
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
 art.starmanAudio?.(false);
 byID('godlikeSpawnNotice').hidden=true;
 if (!session) return;
 cancelRenames(session,'Infinity was closed before the callsign change was confirmed.');
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
 const selectedColor = value => Number.isInteger(value)&&value>=0&&value<COLORS.length?value:undefined;
 session = {
  online, name, localName:options.localName, serial:++sessionSerial,renames:new Map(),confirmedNames:new Map(),readBindings, launcher:options.launcher, onJoined:options.onJoined, id:'pilot', tanks:[], bullets:[], pickups:[], leaderboard:[], controllers:[],
  public:!!options.public,party:[],publicToken:art.publicIdentityToken?.()||'',localPublicToken:options.localName?art.publicIdentityToken?.(1)||'':'',independentAccounts:typeof art.prepareLocalAccount==='function',onConflict:options.onConflict,
  colorIndex:selectedColor(options.colorIndex),localColorIndex:selectedColor(options.localColorIndex),
  room: online && options.code && options.token ? {code: options.code, token: options.token} : null,
  resumeGeneration:options.resumeGeneration,retries:0,latency:null,pendingPing:null,nextPing:0,latencyAt:0,
  rules:options.public?null:options.roomRules,teamScores:[0,0,0,0],previousTanks:new Map(),previousBullets:new Map(),
  time:0,nextBot:between(.4,1.2),nextPickup:0,pickupPilot:0,lastBot:0,lastBullet:0,nextHUD:0,lastEffect:0,botPool:[],botBudget:0,
  mapCache: new Map(), visibleBullets: [], visualEffects: [], interval: 1000 / 30, arrived: 0,
 };
 const world = session;
 if(online&&world.localName&&world.independentAccounts){try{Object.assign(world,art.prepareLocalAccount());}catch(error){setStatus(error.message);session=null;options.onError?.(error);return;}}
 byID('infiniteArenaTitle').textContent=arenaName(world);
 byID('infiniteExit').textContent='Exit '+arenaName(world);
 canvas.style.cursor=mouseEnabled()?'':'auto';
 setStatus('');
 renderOnlineCount(world);
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
  player.colorIndex = world.colorIndex ?? player.colorIndex;
  const roster = options.roster || [];
  applyTankAppearance(world,player,roster.find(member=>member.id===options.primaryId));
  session.tanks.push(player);
  if (world.local) {
   const point = clearCell(world,player,2*CELL,4*CELL,2*CELL) || {x:player.x+2*CELL,y:player.y};
   const second = makeTank(world.local.id,point.x,point.y);
   second.name = world.localName;
   second.colorIndex = world.localColorIndex ?? 1;
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
  refreshBindings(world);
  renderScores(session,player,world.local?world.tanks[1]:null);
 }
 lastTime = performance.now();
 accumulator = 0;
 frame = requestAnimationFrame(loop);
}

function mousePosition(event) {
 if(!session||art.chatOpen())return null;
 const rect = canvas.getBoundingClientRect();
 const [width,height] = primaryView(rect.width,rect.height,!!session?.local);
 const px=event.clientX-rect.left,py=event.clientY-rect.top;
 if(px<0||py<0||px>=width||py>=height)return null;
 return{x:px-width/2,y:py-height/2};
}

function updateMouse(event,position) {
 if(!mouseAimEnabled()){mouseAim=null;return false;}
 position ||= mousePosition(event);
 if(!position){mouseAim=null;return false;}
 const {x,y}=position;
 const distance = Math.hypot(x, y);
 if (distance > 3) mouseAim = {x: x / distance, y: y / distance};
 return true;
}

function pressFire(event,seat=session,mouse=false) {
 if (!session || session.result || pauseMenu.open || art.chatOpen() || session.online && !session.joined || mouse&&!mouseFireEnabled()) return;
 art.primeAudioUnlock(event);
 if(mouse)mouseTap=true;else seat.fireTap = true;
 const now = performance.now(), world = session;
 const pilot = seat.predictor.state;
 const age = now - world.arrived, boosted = pilot?.starmanTime > age / 1000;
 const canDetonate = pilot?.grenades > 0;
 if (world.online && pilot?.alive && !(pilot.spawnProtected && pilot.invulnerable > age / 1000) && now - seat.previewShotAt >= (boosted ? .065 : PROJECTILES[pilot.power || 'regular']?.cooldown || .15) * 1000 &&
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
 if (event.code === 'KeyM') {
  event.preventDefault();
  if (!event.repeat) art.toggleSound();
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
 if (event.pointerType !== 'mouse' || event.button !== 0 || mousePointer !== null || !mouseEnabled()) return;
 const position=mousePosition(event);if(!position)return;
 updateMouse(event,position);
 canvas.focus({preventScroll: true});
 if(!mouseFireEnabled())return;
 capturePointer(canvas, event);
 mousePointer = event.pointerId;
 pressFire(event,session,true);
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
 syncScoreboardButton();
 pauseMenu.scrollTop = 0;
 art.syncCallsignEditors?.();
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
scoreboardButton.addEventListener('click', () => {
 leaderboardPanel.open = !leaderboardPanel.open;
 syncScoreboardButton();
});
leaderboardPanel.addEventListener('toggle',syncScoreboardButton);
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

const pickupHelp = `Power-ups spawn near active pilots. Most last ${POWER_DURATION} seconds once collected. Starman lasts ${STAR_DURATION} seconds. Machine gun allows 3 seconds of firing. Uncollected power-ups expire after ${PICKUP_LIFETIME} seconds.`;
function sidebarHelp() {
 if (!session || !pauseMenu.open) return null;
 const target = session.rules?.infinityTarget;
 return {title:arenaName(session),twoPilots:!!session.local,pilots:localPilots(),pickupHelp,starDuration:STAR_DURATION,weaponRange:SHOT_RANGE/CELL,
  instructions:'Gain a point per kill and lose a point per death. Respawn after '+RESPAWN_DELAY+' second. '+
   (target?'Reach '+target+' points to win.':'Keep growing the score without a time limit.')+
   (session.public&&session.room?' Everyone competes individually, including pilots from your room.':'')};
}
window.leqraInfinity = Object.freeze({start, close: stop, resetControls, resetMouseControls, syncRoom, closeRoom, savedRoomGeneration, pickupHelp, sidebarHelp, localPilots, renamePilot, togglePause});
art.roomSessionReady?.();
})();
