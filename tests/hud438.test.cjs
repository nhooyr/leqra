'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),{boot}=require('./hud438-harness.cjs');

test('combined HUD projectile state preserves ammo, grenade fuse and hostile lock rules',()=>{
 for(const mode of ['room','online'])for(const friendlyFire of [false,true]){
  const s=boot({mode,projectileCount:192});s.rules.friendlyFire=friendlyFire;
  for(const t of s.tanks)for(const power of [null,'rapid','grenade','scatter','laser']){
   t.power=power;t.charges=2;
   const grenades=s.ownedGrenades(t),expected={ammo:s.activeAmmo(t),grenades:grenades.length,grenadeLife:Math.max(0,...grenades.map(b=>b.life)),locked:s.missileLocks(t).length>0};
   assert.deepEqual(s.pilotProjectileState(t,true),expected,`${mode} ${power} pilot ${t.id} friendly fire ${friendlyFire}`);
   assert.equal(s.pilotProjectileState(t).locked,false,'loadout-only queries skip lock work');
  }
 }
});

test('local HUD follows in-place firing, deaths and grenade expiry without stale state',()=>{
 const s=boot({projectileCount:0}),t=s.tanks[0];t.power=null;
 const a={owner:0,kind:'grenade',life:4},b={owner:0,kind:'grenade',life:7},missile={owner:1,kind:'homing',target:0};s.bullets.push(a,b,missile);
 const old=s.pilotProjectileState(t,true);assert.deepEqual(old,{ammo:2,grenades:2,grenadeLife:7,locked:true});
 a.life=3.2;b.dead=true;missile.dead=true;s.bullets.push({owner:0,kind:'rapid'});
 assert.deepEqual(s.pilotProjectileState(t,true),{ammo:2,grenades:1,grenadeLife:3.2,locked:false});
 s.bullets.length=0;assert.deepEqual(s.pilotProjectileState(t,true),{ammo:0,grenades:0,grenadeLife:0,locked:false});
 assert.deepEqual(old,{ammo:2,grenades:2,grenadeLife:7,locked:true},'a later scan cannot mutate a previously returned summary');
});

test('online HUD reads each newest authoritative snapshot and excludes interpolated bullets',()=>{
 const s=boot({mode:'online',projectileCount:32}),a=s.tanks[0],b=s.tanks[7];a.power=null;b.power='laser';b.charges=1;
 s.online.snapshots[0].bullets=[];assert.equal(s.pilotProjectileState(a,true).ammo,0);
 const newest={bullets:[{owner:0,kind:'grenade',life:1.4},{owner:1,kind:'homing',target:7}],tankMap:new Map([[0,a],[7,b]]),received:1000};
 s.online.snapshots.push(newest);
 assert.deepEqual(s.pilotProjectileState(a,true),{ammo:1,grenades:1,grenadeLife:1.4,locked:false});
 assert.deepEqual(s.pilotProjectileState(b,true),{ammo:2,grenades:0,grenadeLife:0,locked:true});
 s.online.snapshots=[{...newest,bullets:[]}];assert.equal(s.pilotProjectileState(a,true).grenades,0);assert.equal(s.pilotProjectileState(b,true).locked,false);
 s.online.snapshots=[];assert.equal(s.pilotProjectileState(a,true).ammo,0,'reconnect without snapshots does not use local rendered projectiles');
});

test('team changes, friendly fire and a removed missile owner immediately update lock warnings',()=>{
 const s=boot({projectileCount:0}),t=s.tanks[0];s.bullets.push({owner:7,kind:'homing',target:0});
 assert.equal(s.pilotProjectileState(t,true).locked,false);
 s.rules.friendlyFire=true;assert.equal(s.pilotProjectileState(t,true).locked,true);
 s.rules.friendlyFire=false;s.tanks[7].team=2;assert.equal(s.pilotProjectileState(t,true).locked,true);
 s.tanks.pop();assert.equal(s.pilotProjectileState(t,true).locked,false,'an orphan projectile has no damage authority');
 s.bullets[0].owner=0;assert.equal(s.pilotProjectileState(t,true).locked,false,'self-owned missiles do not warn of an enemy lock');
});

test('two-pilot loadout and combat feedback retain detonation, ammo, pause and death behavior',()=>{
 for(const mode of ['room','online']){
  const s=boot({mode,projectileCount:0}),a=s.tanks[0],b=s.tanks[7];a.power=null;a.cooldown=0;b.power='laser';b.charges=1;b.cooldown=0;
  const grenade={owner:0,kind:'grenade',life:4.2};s.bullets.push(grenade,{owner:1,kind:'homing',target:7});s.run();
  assert.equal(s.$('weaponLabel').textContent,'DETONATE · 4.2s');assert.equal(s.$('cooldownText1').textContent,'DETONATE READY');
  assert.equal(s.$('ammoDots2').getAttribute('aria-label'),'PILOT 7: 1 of 3 laser charges available');assert.equal(s.$('missileWarning2').hidden,false);
  grenade.life=3.4;s.run();assert.equal(s.$('weaponLabel').textContent,'DETONATE · 3.4s');
  s.setPhase('paused');s.run();assert.equal(s.$('cooldownText1').textContent,'PAUSED');assert.equal(s.$('missileWarning2').hidden,true);
  s.setPhase('playing');a.alive=false;s.run();assert.equal(s.$('weaponLabel').textContent,'TANK DOWN');assert.equal(s.$('cooldownText1').textContent,'TANK DOWN');
  a.alive=true;s.bullets.length=0;s.run();assert.equal(s.$('weaponLabel').textContent,'STANDARD');assert.equal(s.$('cooldownText1').textContent,'READY');assert.equal(s.$('missileWarning2').hidden,true);
 }
});

test('a full two-pilot HUD refresh reads each projectile only once per pilot and pass',()=>{
 for(const mode of ['room','online']){
  const s=boot({mode,projectileCount:192});let reads=0;
  for(let i=0;i<s.bullets.length;i++){const b=s.bullets[i];Object.defineProperty(s.bullets,i,{get(){reads++;return b;}});}
  s.run();assert.equal(reads,192*4,'two loadout passes and two feedback passes each make one scan');
 }
});
