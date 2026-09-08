'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const N=require('../web/netcode.js');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
const firingRounds=vm.runInNewContext(source.match(/MACHINE_FIRING_ROUNDS=([^,;]+)/)[1]);
function declaration(name){
 const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);
 const end=source.indexOf('\n',start),line=source.slice(start,end);
 return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);
}
const kinds=['rapid','scatter','shield','homing','grenade','speed','laser','scope','cannon','ghost'];
function tank(id=0){return {id,x:100+id*200,y:100,angle:0,r:17,human:true,alive:true,cooldown:0,invulnerable:0,shield:0,shieldCharges:0,speedTime:0,speedStacks:0,scopeTime:0,ghostTime:0,power:null,powerTime:0,machineRounds:0,charges:0,recoil:0,track:0};}
function boot(){
 const noop=()=>{},s={POWER_EFFECT_DURATION:10,MACHINE_FIRING_ROUNDS:firingRounds,MACHINE_CAPACITY:96,MAX_SPEED_STACKS:5,POWER:Object.fromEntries(kinds.map(k=>[k,{name:k.toUpperCase()}])),cols:12,rows:10,time:0,mode:'solo',phase:'playing',fxTime:0,phaseTime:0,toastTime:0,particles:[],rings:[],shake:0,roundClock:120,spawnClock:Infinity,uiClock:Infinity,bullets:[],pickups:[],bulletId:0,tanks:[tank(),tank(1)],updateTraces:noop,compactLife:noop,objectiveMode:()=>false,survivalMode:()=>false,survivalBreak:()=>false,liveLocalStats:()=>false,advanceGhost:(t,dt)=>t.ghostTime=Math.max(0,t.ghostTime-dt),humanControl:noop,botControl:noop,updateBullets:noop,finishRound:noop,updateHUD:noop,clearTankAt:()=>true,burst:noop,shotSound:noop,
  projectileSpec:power=>({kind:power,cooldown:0}),muzzleProjectile:(t,a)=>({owner:t.id,kind:t.power}),
  activeAmmo:t=>s.bullets.filter(b=>!b.dead&&b.owner===t.id).length,shieldCount:t=>t.shield>0?t.shieldCharges||1:0,speedCount:t=>t.speedTime>0?t.speedStacks||1:0};
 vm.createContext(s);for(const name of ['powerEffectDuration','pickupCap','pickupLifetime','grantPower','pickupMessage','powerCapacity','fire','update'])vm.runInContext(declaration(name),s);return s;
}
test('local equipped and ground durations match each of the six map tiers',()=>{
 const s=boot();
 for(const [c,r,duration,ground]of [[7,7,10,30],[9,8,10,30],[12,10,10,32],[14,12,15,45],[16,14,15,61],[24,14,15,90]]){
  s.cols=c;s.rows=r;assert.equal(s.pickupLifetime(),ground);
  for(const kind of kinds){const t=tank();s.grantPower(t,kind);const field={shield:'shield',speed:'speedTime',scope:'scopeTime',ghost:'ghostTime'}[kind]||'powerTime';assert.equal(t[field],duration,kind+' '+c+'x'+r);}
 }
 assert.equal(s.pickupLifetime(0,0),0);
});
test('local larger-map buffs refresh independently and respect stack and charge caps',()=>{
 const s=boot();s.cols=14;s.rows=12;const t=tank();s.grantPower(t,'cannon');
 for(const kind of ['shield','speed','scope','ghost'])for(let i=0;i<7;i++)s.grantPower(t,kind);
 assert.equal(t.power,'cannon');assert.equal(t.charges,3);assert.equal(t.powerTime,15);assert.equal(t.shieldCharges,5);assert.equal(t.speedStacks,5);
 for(const field of ['shield','speedTime','scopeTime','ghostTime'])assert.equal(t[field],15);
});
test('local machine gun fires exactly 180 rapid projectiles at 60 Hz on a 120 Hz simulation',()=>{
 const s=boot(),t=tank();s.grantPower(t,'rapid');let fired=0;
 for(let i=0;i<600;i++){s.time=i/120;if(t.power==='rapid'&&s.fire(t)){fired++;assert.equal(s.bullets.at(-1).kind,'rapid');}s.bullets=[];}
 assert.equal(fired,180);assert.equal(t.machineRounds,0);assert.equal(t.power,null);assert.equal(t.powerTime,0);assert.equal(t.charges,0);
});
test('local cooldown, wall, slot and same-tick blocks never spend firing budget',()=>{
 const s=boot(),t=tank();s.grantPower(t,'rapid');t.cooldown=1;assert.equal(s.fire(t),false);t.cooldown=0;
 t.ghostTime=5;s.clearTankAt=()=>false;assert.equal(s.fire(t),false);s.clearTankAt=()=>true;
 s.bullets=Array.from({length:96},()=>({owner:0}));assert.equal(s.fire(t),false);assert.equal(t.machineRounds,180);
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
test('machine-gun pickup refreshes its firing budget; other buffs preserve it',()=>{
 const s=boot(),t=tank();s.grantPower(t,'rapid');s.fire(t);s.grantPower(t,'shield');assert.equal(t.machineRounds,179);
 s.grantPower(t,'rapid');assert.equal(t.machineRounds,180);assert.equal(t.shieldCharges,1);
 s.grantPower(t,'cannon');assert.equal(t.machineRounds,0);assert.equal(t.charges,3);
});
const previewOptions={active:true,free:96,need:1,cooldown:0,ttl:600};
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
test('pickup feedback explains map duration separately from machine-gun firing time and grenade fuse',()=>{
 const s=boot();s.cols=14;s.rows=12;assert.match(s.pickupMessage('speed'),/15 SECONDS/);assert.match(s.pickupMessage('scope'),/15 SECONDS/);
 assert.match(s.pickupMessage('rapid'),/3s FIRING · 15s TO USE/);assert.match(s.pickupMessage('grenade'),/10s FUSE/);
});
