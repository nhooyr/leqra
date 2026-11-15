'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),vm=require('node:vm');
const {assetPath}=require('./web_assets.cjs');
const N=require(assetPath('netcode.js'));
const source=readFileSync(assetPath('game.js'),'utf8');
const firingRounds=vm.runInNewContext(source.match(/MACHINE_FIRING_ROUNDS=([^,;]+)/)[1]);
function declaration(name){
 const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);
 const end=source.indexOf('\n',start),line=source.slice(start,end);
 return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);
}
const kinds=['rapid','scatter','shield','homing','grenade','speed','laser','cannon','ghost','starman'];
function tank(id=0){return {id,x:100+id*200,y:100,angle:0,r:17,human:true,alive:true,cooldown:0,invulnerable:0,shield:0,shieldCharges:0,speedTime:0,speedStacks:0,ghostTime:0,power:null,powerTime:0,machineRounds:0,charges:0,recoil:0,track:0};}
function boot(){
 const noop=()=>{},s={Net:N,POWER_EFFECT_DURATION:10,MACHINE_FIRING_ROUNDS:firingRounds,MACHINE_CAPACITY:N.MACHINE_CAPACITY,MAX_SPEED_STACKS:5,POWER:Object.fromEntries(kinds.map(k=>[k,{name:k.toUpperCase()}])),cols:12,rows:10,time:0,localTick:0,localTankActors:Array(8),mode:'solo',phase:'playing',fxTime:0,phaseTime:0,toastTime:0,particles:[],rings:[],shake:0,roundClock:120,spawnClock:Infinity,uiClock:Infinity,bullets:[],pickups:[],bulletId:0,tanks:[tank(),tank(1)],updateTraces:noop,compactLife:noop,objectiveMode:()=>false,survivalMode:()=>false,survivalBreak:()=>false,liveLocalStats:()=>false,advanceGhost:(t,dt)=>t.ghostTime=Math.max(0,t.ghostTime-dt),humanControl:noop,botControl:noop,updateBullets:noop,finishRound:noop,updateHUD:noop,muzzleBlocked:()=>false,burst:noop,shotSound:noop,
  projectileSpec:power=>({kind:power,cooldown:0}),muzzleProjectile:(t,a)=>({owner:t.id,kind:t.power}),
  activeAmmo:t=>s.bullets.filter(b=>!b.dead&&!b.boosted&&b.owner===t.id&&N.ammoEpoch(b)===N.ammoEpoch(t)).length,shieldCount:t=>t.shield>0?t.shieldCharges||1:0,speedCount:t=>t.speedTime>0?t.speedStacks||1:0};
 vm.createContext(s);for(const name of ['choosePickup','powerEffectDuration','starmanDuration','pickupCap','pickupLifetime','grantPower','pickupMessage','powerCapacity','recycleStarmanProjectiles','fire','update'])vm.runInContext(declaration(name),s);return s;
}
test('local equipped and ground durations match each of the six map tiers',()=>{
 const s=boot();
 for(const [c,r,duration,ground,starman]of [[7,7,10,30,4],[9,8,10,30,4],[12,10,10,32,5],[14,12,15,45,6],[16,14,15,61,7],[24,14,15,90,8]]){
  s.cols=c;s.rows=r;assert.equal(s.pickupLifetime(),ground);
  for(const kind of kinds){
   const t=tank();s.grantPower(t,kind);const field={shield:'shield',speed:'speedTime',ghost:'ghostTime',starman:'starmanTime'}[kind]||'powerTime';assert.equal(t[field],kind==='starman'?starman:duration,kind+' '+c+'x'+r);
   if(kind==='starman'){assert.equal(t.ghostTime,starman);assert.equal(t.invulnerable,starman);}
  }
  s.cols=r;s.rows=c;const t=tank();s.grantPower(t,'starman');assert.equal(t.starmanTime,starman,'portrait '+r+'x'+c);
 }
 assert.equal(s.pickupLifetime(0,0),0);
});
test('Starman uses a single slot out of 27 and does not appear when disabled',()=>{
 const s=boot(),counts={};
 for(let slot=0;slot<27;slot++){
  s.Math=Object.create(Math);s.Math.random=()=>(slot+.5)/27;
  const kind=s.choosePickup(kinds);
  counts[kind]=(counts[kind]||0)+1;
  assert.notEqual(s.choosePickup(kinds.filter(k=>k!=='starman')),'starman');
 }
 assert.equal(counts.starman,1);
 for(const kind of kinds.filter(k=>k!=='starman'))assert.equal(counts[kind],['shield','speed'].includes(kind)?6:2);
});
test('Starman refreshes a short phase and immunity without replacing longer Ghost or equipped gear',()=>{
 const s=boot(),t=s.tanks[0];
 for(const kind of ['cannon','shield','speed','ghost','starman'])s.grantPower(t,kind);
 assert.equal(t.starmanTime,5);assert.equal(t.invulnerable,5);assert.equal(t.ghostTime,10);
 s.update(.5);
 assert.equal(t.starmanTime,4.5);assert.equal(t.invulnerable,4.5);
 s.grantPower(t,'starman');s.update(5);
 assert.equal(t.starmanTime,0);assert.equal(t.invulnerable,0);assert.equal(t.ghostTime,4.5);
 assert.equal(t.power,'cannon');assert.equal(t.charges,3);assert.equal(t.shieldCharges,1);assert.equal(t.speedStacks,1);
});
test('local larger-map buffs refresh independently and respect stack and charge caps',()=>{
 const s=boot();s.cols=14;s.rows=12;const t=tank();s.grantPower(t,'cannon');
 for(const kind of ['shield','speed','ghost'])for(let i=0;i<7;i++)s.grantPower(t,kind);
 assert.equal(t.power,'cannon');assert.equal(t.charges,3);assert.equal(t.powerTime,15);assert.equal(t.shieldCharges,5);assert.equal(t.speedStacks,5);
 for(const field of ['shield','speedTime','ghostTime'])assert.equal(t[field],15);
});
test('local defenses expire before attacks in either rotated seat order',()=>{
 for(const localTick of [0,1])for(const remaining of [.001,.1]){
  const s=boot(),target=s.tanks[1],dt=1/120;
  Object.assign(target,{shield:remaining,shieldCharges:1,invulnerable:remaining,starmanTime:remaining});
  s.localTick=localTick;
  s.humanControl=shooter=>{
   if(shooter.id!==0)return;
   for(const field of ['shield','invulnerable','starmanTime'])assert.equal(target[field],Math.max(0,remaining-dt),field);
   assert.equal(target.shieldCharges,remaining>dt?1:0);
   target.invulnerable=.35; // Protection just granted by a shield hit.
  };
  s.update(dt);
  assert.equal(target.invulnerable,.35);
 }
});
test('local machine gun fires exactly 180 rapid projectiles at 60 Hz on a 120 Hz simulation',()=>{
 const s=boot(),t=tank();s.grantPower(t,'rapid');let fired=0;
 for(let i=0;i<600;i++){s.time=i/120;if(t.power==='rapid'&&s.fire(t)){fired++;assert.equal(s.bullets.at(-1).kind,'rapid');}s.bullets=[];}
 assert.equal(fired,180);assert.equal(t.machineRounds,0);assert.equal(t.power,null);assert.equal(t.powerTime,0);assert.equal(t.charges,0);
});
test('local cooldown, wall, slot and same-tick blocks never spend firing budget',()=>{
 const s=boot(),t=tank();s.grantPower(t,'rapid');t.cooldown=1;assert.equal(s.fire(t),false);t.cooldown=0;
 t.ghostTime=5;s.muzzleBlocked=()=>true;assert.equal(s.fire(t),false);s.muzzleBlocked=()=>false;
 s.bullets=Array.from({length:N.MACHINE_CAPACITY},()=>({owner:0,ammoEpoch:t.ammoEpoch}));assert.equal(s.fire(t),false);assert.equal(t.machineRounds,180);
 s.bullets=[];assert.equal(s.fire(t),true);assert.equal(s.fire(t),false);assert.equal(t.machineRounds,179);
});
test('local released fire preserves budget but the regular timer still expires unused guns',()=>{
 for(const [cols,rows,duration]of [[12,10,10],[14,12,15]]){
  const s=boot();s.cols=cols;s.rows=rows;const t=s.tanks[0];s.grantPower(t,'rapid');
  for(let i=0;i<duration*120-1;i++)s.update(1/120);
  assert.equal(t.power,'rapid');assert.equal(t.machineRounds,180);
  s.phase='paused';s.update(3);assert.equal(t.machineRounds,180);assert.ok(t.powerTime>0);
  s.phase='playing';s.update(2/120);assert.equal(t.power,null);assert.equal(t.machineRounds,0);
 }
});
test('machine-gun pickup refreshes its firing budget; other buffs refill it',()=>{
 const s=boot(),t=tank();s.grantPower(t,'rapid');s.fire(t);s.grantPower(t,'shield');assert.equal(t.machineRounds,180);
 s.grantPower(t,'rapid');assert.equal(t.machineRounds,180);assert.equal(t.shieldCharges,1);
 s.grantPower(t,'cannon');assert.equal(t.machineRounds,0);assert.equal(t.charges,3);
});
const previewOptions={active:true,free:96,need:1,cooldown:0,ttl:600};
test('fixed missiles held Fire reloads after360ms with matching prediction and HUD timing',()=>{
 const s=boot(),t=s.tanks[0];Object.assign(s,{MISSILE_SPEED:235,W:1008,H:672});
 for(const name of ['projectileSpec','cooldownDuration'])vm.runInContext(declaration(name),s);
 s.grantPower(t,'homing');assert.equal(s.fire(t),true);assert.equal(t.cooldown,.36);assert.equal(t.cooldownTotal,.36);assert.equal(t.charges,2);
 assert.equal(s.cooldownDuration('homing'),.36);assert.equal(s.projectileSpec('homing').speed,235);assert.equal(s.projectileSpec('homing').r,5);
 s.humanControl=pilot=>{if(pilot===t)s.fire(pilot);};
 for(let i=0;i<21;i++)s.update(1/60);
 assert.equal(t.charges,2,'held Fire must wait for360ms');assert.equal(s.bullets.length,1);
 s.update(1/60);assert.equal(t.charges,1);assert.equal(s.bullets.length,2);
 const shots=new N.ShotPresentation();t.cooldown=0;t.shotSerial=0;t.charges=3;shots.sync(t,'playing',0);
 const options={...previewOptions,free:3,charged:true,cooldown:s.cooldownDuration('homing')};
 assert.ok(shots.tryFire(t,true,0,options));assert.equal(shots.tryFire(t,true,350,options),null);assert.ok(shots.tryFire(t,true,360,options));
});
const onlineTank=id=>({...tank(id),spawnSerial:1,shotSerial:0,power:'rapid',machineRounds:180});
test('online predicted fire reserves remaining rounds and never shows a 181st machine-gun shot',()=>{
 const p=new N.ShotPresentation(),t=onlineTank(0);p.sync(t,'playing',0);
 for(let i=0;i<180;i++){
  const now=i*N.STEP_MS+.01,v=p.tryFire(t,true,now,previewOptions);assert.ok(v,'shot '+i);v.shells=[{}];
  assert.equal(p.machineRounds(t),179-i);assert.equal(t.machineRounds,180-i,'prediction leaves server state intact');
  t.shotSerial=v.shot;t.machineRounds--;p.sync(t,'playing',now+1);p.prune(now+1,new Set([0]));assert.equal(p.machineRounds(t),179-i);
 }
 assert.equal(p.tryFire(t,true,5100,previewOptions),null);
});
test('unacknowledged previews cannot overspend the last firing rounds',()=>{
 const p=new N.ShotPresentation(),t=onlineTank(0);t.machineRounds=2;p.sync(t,'playing',0);
 assert.ok(p.tryFire(t,true,1,previewOptions));assert.ok(p.tryFire(t,true,21,previewOptions));
 assert.equal(p.machineRounds(t),0);assert.equal(p.tryFire(t,true,41,previewOptions),null);assert.equal(t.machineRounds,2);
});
test('predicted firing budget is independent for P2 and resets with a new life',()=>{
 const p=new N.ShotPresentation(),a=onlineTank(0),b=onlineTank(7);a.machineRounds=1;b.machineRounds=2;
 p.sync(a,'playing',0);p.sync(b,'playing',0);p.tryFire(a,true,1,previewOptions);
 assert.equal(p.machineRounds(a),0);assert.equal(p.machineRounds(b),2);assert.ok(p.tryFire(b,true,1,previewOptions));
 a.spawnSerial++;a.machineRounds=180;p.sync(a,'playing',100);assert.equal(p.machineRounds(a),180);
});
test('pickup feedback explains map duration, Starman, machine-gun firing time and grenade fuse',()=>{
 const s=boot();s.cols=14;s.rows=12;assert.match(s.pickupMessage('speed'),/15 SECONDS/);assert.match(s.pickupMessage('laser'),/LONG AIM GUIDE/);
 assert.match(s.pickupMessage('rapid'),/3s FIRING, 15s TO USE/);assert.match(s.pickupMessage('grenade'),/10s FUSE/);assert.match(s.pickupMessage('starman'),/6s$/);
});

const weapons=['rapid','scatter','homing','grenade','laser','cannon'];
test('every pickup refills the selected weapon and leaves older shells alive for either local pilot',()=>{
 for(const id of [0,1])for(const equipped of ['',...weapons])for(const pickup of kinds){
  const s=boot(),t=s.tanks[id];Object.assign(t,{power:equipped,machineRounds:1,charges:1,cooldown:3,cooldownTotal:3,fireBlocked:true,rapidTick:42});
  const old={owner:id,ammoEpoch:0,kind:'grenade',life:7};s.bullets=[old];s.grantPower(t,pickup);
  const label=[id,equipped,pickup].join('/'),power=weapons.includes(pickup)?pickup:equipped;
  assert.equal(t.power,power,label);assert.equal(t.ammoEpoch,1,label);assert.equal(t.cooldown,0,label);assert.equal(t.cooldownTotal,0,label);
  assert.equal(t.machineRounds,power==='rapid'?180:0,label);assert.equal(t.charges,power==='scatter'?5:weapons.includes(power)&&power!=='rapid'?3:0,label);
  assert.equal(t.fireBlocked,true,label);assert.equal(t.rapidTick,42,label);assert.equal(s.bullets[0],old,label);assert.equal(old.life,7,label);assert.ok(!old.dead,label);assert.equal(s.activeAmmo(t),0,label);
 }
});
test('each power ending and simultaneous expiries refill once before the next local firing action',()=>{
 for(const id of [0,1])for(const ending of kinds){
  const s=boot(),t=s.tanks[id];s.grantPower(t,ending);t.cooldown=t.cooldownTotal=3;t.charges=1;t.machineRounds=1;
  const field={shield:'shield',speed:'speedTime',ghost:'ghostTime',starman:'starmanTime'}[ending]||'powerTime';t[field]=.001;
  const epoch=t.ammoEpoch;s.update(1/120);assert.equal(t.ammoEpoch,epoch+1,ending);assert.equal(t.cooldown,0,ending);
  assert.equal(t.power||'',weapons.includes(ending)?'':t.power||'',ending);assert.equal(t.charges,0,ending);assert.equal(t.machineRounds,0,ending);
 }
 const s=boot(),t=s.tanks[0];Object.assign(t,{shield:.001,shieldCharges:1,speedTime:.001,speedStacks:2,ghostTime:.001,starmanTime:.001,power:'rapid',powerTime:.001,cooldown:2,machineRounds:1});
 s.update(1/120);assert.equal(t.ammoEpoch,1);assert.equal(t.cooldown,0);assert.equal(t.power,null);
});
test('a buff ending refills a surviving weapon without extending its duration',()=>{
 for(const power of weapons)for(const ending of ['shield','speedTime','ghostTime','starmanTime']){
  const s=boot(),t=s.tanks[0];Object.assign(t,{power,powerTime:7,machineRounds:1,charges:1,[ending]:.001,cooldown:3});
  s.update(1/120);assert.equal(t.power,power);assert.equal(t.powerTime,7-1/120);assert.equal(t.cooldown,0);
  assert.equal(t.machineRounds,power==='rapid'?180:0);assert.equal(t.charges,power==='scatter'?5:power==='rapid'?0:3);
 }
});
test('last charged or machine-gun shot restores ordinary ammo without deleting the final volley',()=>{
 for(const power of weapons.filter(p=>p!=='laser')){
  const s=boot(),t=s.tanks[0];s.grantPower(t,power);t.machineRounds=t.charges=1;s.time=1;
  assert.equal(s.fire(t),true,power);assert.equal(t.power,null,power);assert.equal(t.cooldown,0,power);assert.equal(t.ammoEpoch,2,power);
  assert.equal(s.bullets.length,power==='scatter'?3:1,power);assert.ok(s.bullets.every(b=>!b.dead&&b.ammoEpoch===1),power);assert.equal(s.activeAmmo(t),0,power);
  assert.equal(s.fire(t),true,power+' can immediately fire standard ammo');assert.equal(s.bullets.at(-1).ammoEpoch,2);
 }
});
test('a refill cannot bypass the rapid60Hz guard or release a held grenade trigger',()=>{
 const s=boot(),t=s.tanks[0];s.grantPower(t,'rapid');s.time=1;assert.equal(s.fire(t),true);s.grantPower(t,'speed');assert.equal(s.fire(t),false);assert.equal(t.machineRounds,180);
 const p=new N.ShotPresentation(),a=onlineTank(0);a.power='grenade';a.charges=3;p.sync(a,'playing',0);
 const options={...previewOptions,free:3,charged:true};assert.ok(p.tryFire(a,true,1,options));N.refillAmmo(a);p.sync(a,'playing',2);
 assert.equal(p.tryFire(a,true,20,options),null);p.tryFire(a,false,21,options);assert.ok(p.tryFire(a,true,22,options));
});
test('online ammo reset discards only old predicted costs and preserves already-shown flights and movement',()=>{
 const shots=new N.ShotPresentation(),a=onlineTank(0),b=onlineTank(7);a.machineRounds=1;
 for(const t of [a,b])shots.sync(t,'playing',0);
 const old=shots.tryFire(a,true,1,previewOptions);old.shells=[{life:2}];assert.equal(shots.machineRounds(a),0);
 N.refillAmmo(a);shots.sync(a,'playing',2);assert.equal(shots.machineRounds(a),180);assert.equal(shots.cooldown(a,2),0);assert.equal(shots.machineRounds(b),180);
 assert.equal(shots.previews.get(old.key),old);assert.equal(shots.tryFire(a,true,3,previewOptions),null,'same tick rapid limit survives');
 const fresh=shots.tryFire(a,true,21,previewOptions);assert.ok(fresh);assert.equal(fresh.ammoEpoch,1);assert.notEqual(fresh.key,old.key);assert.equal(shots.machineRounds(a),179);
 const predictor=new N.Predictor((t,dx,dy)=>{t.x+=dx;t.y+=dy;});predictor.reset({...a,ammoEpoch:0,ack:0});predictor.sentInput(1);predictor.advance(N.STEP*2,{...N.neutral(),forward:true});
 const x=predictor.state.x;assert.ok(x>a.x);predictor.reconcile({...a,ammoEpoch:1,ack:0});assert.equal(predictor.state.x,x);assert.equal(predictor.state.ammoEpoch,1);assert.equal(predictor.metrics.hardResets,0);assert.equal(predictor.metrics.replayed,2);
});
test('machine tuple decoding keeps the12-number format and associates optional epochs by wire index',()=>{
 const tuple=[1,0,1,1,10,20,282,0,.1,1,0,0],colors=['#fff'];
 assert.ok(!('ammoEpoch' in N.expandMachineBullets([tuple],colors)[0]));assert.equal(tuple.length,12);
 assert.equal(N.expandMachineBullets([tuple],colors,[42])[0].ammoEpoch,42);
 assert.equal(N.expandMachineBullets([[],tuple],colors,[12,43])[0].ammoEpoch,43);
 for(const invalid of [-1,Infinity,NaN,1.5,Number.MAX_SAFE_INTEGER+1])assert.equal(N.ammoEpoch(N.expandMachineBullets([tuple],colors,[invalid])[0]),0);
 const t={ammoEpoch:Number.MAX_SAFE_INTEGER,power:'rapid',rapidTick:5};N.refillAmmo(t);assert.equal(t.ammoEpoch,1);assert.equal(t.machineRounds,180);assert.equal(t.rapidTick,5);
});

test('last grenade consumes the entire hold through refills; only a new press fires standard ammo',()=>{
 for(const sampledRelease of [false,true]){
  const s=boot(),t=s.tanks[0];s.detonateOwned=()=>false;vm.runInContext(declaration('weaponControl'),s);
  s.grantPower(t,'grenade');t.charges=1;s.weaponControl(t,true,true);
  assert.equal(t.power,null);assert.equal(t.cooldown,0);assert.equal(t.fireBlocked,true);assert.equal(s.bullets.length,1);assert.equal(s.bullets[0].kind,'grenade');
  s.weaponControl(t,true,false);assert.equal(s.bullets.length,1);
  s.grantPower(t,'shield',.001);s.update(1/120);s.weaponControl(t,true,false);assert.equal(s.bullets.length,1,'pickup/expiry cannot release a consumed hold');
  if(sampledRelease)s.weaponControl(t,false,false);
  s.weaponControl(t,true,true);assert.equal(s.bullets.length,2);assert.equal(s.bullets[1].kind,null);
 }
});
test('every depleted or expired weapon consumes held Fire until a fresh press',()=>{
 for(const power of weapons)for(const expiry of [false,true])for(const sampledRelease of [false,true]){
  const s=boot(),t=s.tanks[0],noop=()=>{};Object.assign(s,{detonateOwned:()=>false,LASER_COOLDOWN:.85*2/3,laserTrace:()=>({x:0,y:0,endX:1,endY:0,target:null}),laserEffect:noop});
  vm.runInContext(declaration('weaponControl')+'\n'+declaration('fireLaser'),s);s.grantPower(t,power);
  if(expiry){t.fireHeld=true;t.powerTime=.001;s.humanControl=pilot=>{if(pilot===t)s.weaponControl(t,true,false);};s.update(1/120);}
  else{t.charges=t.machineRounds=1;s.weaponControl(t,true,true);}
  const label=[power,expiry?'timer':'ammo',sampledRelease?'sampled':'coalesced'].join('/'),fired=s.bullets.length;
  assert.equal(t.power,null,label);assert.equal(t.cooldown,0,label);assert.equal(t.fireBlocked,true,label);
  for(let i=0;i<5;i++){s.time+=(1/60);s.weaponControl(t,true,false);}assert.equal(s.bullets.length,fired,label+' no standard follow-up');
  s.grantPower(t,'shield',.001);s.update(1/120);s.weaponControl(t,true,false);assert.equal(s.bullets.length,fired,label+' passive refill preserves latch');
  if(sampledRelease)s.weaponControl(t,false,false);s.weaponControl(t,true,true);assert.equal(s.bullets.length,fired+1,label+' fresh press fires standard');
 }
});

test('fixed local empty-ammo presses play one dry cue per fresh eligible press for either pilot',()=>{
 for(const id of [0,1])for(const power of ['', 'rapid','scatter','homing','laser','cannon']){
  const s=boot(),t=s.tanks[id],sounds=[];Object.assign(s,{dryFireSound:()=>sounds.push('dry'),detonateOwned:()=>false});
  vm.runInContext(declaration('weaponControl')+'\n'+declaration('fireLaser'),s);s.grantPower(t,power||'shield');t.power=power;t.cooldown=0;t.charges=0;t.machineRounds=0;
  s.bullets=Array.from({length:s.powerCapacity(t)},()=>({owner:id,ammoEpoch:t.ammoEpoch}));const before=s.bullets.length;
  s.weaponControl(t,true,true);assert.deepEqual(sounds,['dry'],power);assert.equal(s.bullets.length,before,power);
  s.time=1;s.weaponControl(t,true,false);assert.equal(sounds.length,1,'held input is silent');s.weaponControl(t,false,false);s.weaponControl(t,true,true);assert.equal(sounds.length,2);
 }
});
