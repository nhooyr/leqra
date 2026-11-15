'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {assetPath}=require('./web_assets.cjs');
const N=require(assetPath('netcode.js'));
const tank=(extra={})=>({id:0,spawnSerial:1,shotSerial:0,alive:true,x:200,y:200,angle:0,r:17,power:'',charges:0,cooldown:0,cooldownTotal:.34,...extra});
const options=(extra={})=>({active:true,grenade:false,blocked:false,free:5,need:1,charged:false,cooldown:.34,ttl:600,...extra});
const close=(a,b)=>assert.ok(Math.abs(a-b)<1e-6,`${a} != ${b}`);
test('one accepted volley keeps a monotonic cooldown deadline despite repeated snapshots',()=>{
 const p=new N.ShotPresentation(),t=tank({shotSerial:1,cooldown:.21});p.sync(t,'playing',1000);
 let prior=Infinity;for(let n=0;n<80;n++){let now=1000+n*8;p.sync({...t,cooldown:.21},'playing',now);const current=p.cooldown(t,now);assert.ok(current<=prior);prior=current;}
 close(prior,0);
});
test('round completion clears pending effects and stops combat timing',()=>{
 const p=new N.ShotPresentation(),t=tank();p.sync(t,'playing',0);p.tryFire(t,true,0,options());
 p.sync({...t,shotSerial:1,cooldown:.21},'roundOver',100);assert.equal(p.previews.size,0);close(p.cooldown(t,200),0);
 assert.equal(p.tryFire(t,true,200,options({active:false})),null);
});
test('prediction never mutates server tank state, ammo, or score',()=>{
 const p=new N.ShotPresentation(),t=tank(),before=JSON.stringify(t);p.sync(t,'playing',0);
 const v=p.tryFire(t,true,1,options());assert.ok(v);assert.equal(JSON.stringify(t),before);assert.equal(v.shot,1);
});
test('matching authority suppresses duplicate sound and preserves predicted cooldown',()=>{
 const p=new N.ShotPresentation(),t=tank();p.sync(t,'playing',0);const v=p.tryFire(t,true,0,options());
 p.sync({...t,shotSerial:1,cooldown:.30},'playing',140);close(p.cooldown(t,140),.20);
 assert.ok(v.accepted);assert.ok(p.heard(0,1,1));assert.equal(p.heard(1,1,1),false);
});
test('P1 fire does not consume P2 prediction, cooldown, or edges',()=>{
 const p=new N.ShotPresentation(),a=tank(),b=tank({id:7});p.sync(a,'playing',0);p.sync(b,'playing',0);
 assert.ok(p.tryFire(a,true,0,options()));close(p.cooldown(b,1),0);assert.ok(p.tryFire(b,true,10,options()));assert.equal(p.previews.size,2);
});
test('dry fire, cooldown, wall-embedded ghost, and exhausted special charges have no preview',()=>{
 for(const [t,o]of[[tank({cooldown:.2}),options()],[tank(),options({free:0})],[tank(),options({blocked:true})],[tank({power:'cannon',charges:0}),options({charged:true})]]){
  const p=new N.ShotPresentation();p.sync(t,'playing',0);assert.equal(p.tryFire(t,true,0,o),null);assert.equal(p.soundKeys.size,0);
 }
});
test('machine-gun preview has zero cooldown, a 60Hz emission ceiling, and bounded pending shots',()=>{
 const p=new N.ShotPresentation(),t=tank({power:'rapid',machineRounds:180});p.sync(t,'playing',0);let count=0;
 for(let ms=0;ms<500;ms+=5){const v=p.tryFire(t,true,ms,options({free:96,cooldown:0}));if(v){v.shells=[{}];count++;}}
 assert.equal(count,30);close(p.cooldown(t,500),0);
 for(let ms=500;ms<2000;ms+=17){const v=p.tryFire(t,true,ms,options({free:96,cooldown:0}));if(v)v.shells=[{}];}
 assert.equal(p.previews.size,48);
});
test('unconfirmed charge use blocks a speculative fourth cannon shot',()=>{
 const p=new N.ShotPresentation(),t=tank({power:'cannon',charges:3});p.sync(t,'playing',0);
 for(let n=0;n<3;n++)assert.ok(p.tryFire(t,true,n*900,options({charged:true,cooldown:.85})));
 assert.equal(p.tryFire(t,true,2800,options({charged:true,cooldown:.85})),null);
});
test('Starman bypasses preview cooldown and charge limits without spending saved ammo',()=>{
 const p=new N.ShotPresentation(),t=tank({power:'laser',charges:1,cooldown:.8,starmanTime:4});
 const o=options({free:Infinity,need:0,charged:true,cooldown:.85});
 p.sync(t,'playing',0);
 for(let n=0;n<6;n++){
  const v=p.tryFire(t,true,n*20,o);
  assert.ok(v?.boosted);
  assert.equal(v.until,v.at);
  assert.equal(p.tryFire(t,true,n*20,o),null);
 }
 assert.equal(t.charges,1);
 const expired={...t,cooldown:0,starmanTime:0};
 const shot=p.tryFire(expired,true,120,o);
 assert.ok(shot&&!shot.boosted);
 assert.equal(shot.until,970);
});
test('pending Starman shells leave ordinary projectile slots available after expiry',()=>{
 const p=new N.ShotPresentation(),t=tank({starmanTime:4});
 p.sync(t,'playing',0);
 for(let n=0;n<6;n++)p.tryFire(t,true,n*20,options()).shells=[{}];
 const expired={...t,starmanTime:0};
 const shot=p.tryFire(expired,true,120,options({free:1}));
 assert.ok(shot&&!shot.boosted);
 shot.shells=[{}];
 assert.equal(p.tryFire(expired,true,500,options({free:1})),null);
});
test('grenade hold cannot repeatedly throw or accidentally predict a blast',()=>{
 const p=new N.ShotPresentation(),t=tank({power:'grenade',charges:3});p.sync(t,'playing',0);assert.ok(p.tryFire(t,true,0,options({charged:true,cooldown:.8})));
 assert.equal(p.tryFire(t,true,1000,options({charged:true,cooldown:.8})),null);
 p.tryFire(t,false,1100,options());assert.equal(p.tryFire(t,true,1200,options({grenade:true})),null);
 assert.equal(p.tryFire(t,true,2400,options()),null);assert.equal(p.previews.size,1);
});
test('last-grenade authority refill cannot turn the consumed hold into a standard preview',()=>{
 const p=new N.ShotPresentation(),t=tank({power:'grenade',charges:1});p.sync(t,'playing',0);
 assert.ok(p.tryFire(t,true,0,options({charged:true,cooldown:.8})));
 Object.assign(t,{power:'',ammoEpoch:1,charges:0,cooldown:0,shotSerial:1});p.sync(t,'playing',30);
 assert.equal(p.tryFire(t,true,31,options()),null);p.tryFire(t,false,32,options());assert.ok(p.tryFire(t,true,33,options()));
});
test('every weapon ending in authority suppresses held standard previews without suppressing a new press',()=>{
 for(const power of ['rapid','scatter','homing','grenade','laser','cannon']){
  const p=new N.ShotPresentation(),t=tank({power,charges:1,machineRounds:1});p.sync(t,'playing',0);
  assert.ok(p.tryFire(t,true,0,options({charged:power!=='rapid',cooldown:power==='rapid'?0:.5})),power);
  Object.assign(t,{power:'',ammoEpoch:1,charges:0,machineRounds:0,cooldown:0,shotSerial:1});p.sync(t,'playing',30);
  assert.equal(p.tryFire(t,true,31,options()),null,power);p.tryFire(t,false,32,options());assert.ok(p.tryFire(t,true,33,options()),power);
 }
});
test('an early real release and repress belongs to a new hold before delayed weapon-end authority arrives',()=>{
 for(const power of ['rapid','scatter','homing','grenade','laser','cannon'])for(const timer of [false,true])for(const star of timer?[0,.02]:[0]){
  const p=new N.ShotPresentation(),tanks=[0,7].map(id=>tank({id,power,powerTime:timer?.01:15,starmanTime:star,charges:timer?3:1,machineRounds:timer?180:1}));
  const finite=options({charged:power!=='rapid',cooldown:power==='rapid'?0:.5});
  for(const t of tanks){p.sync(t,'playing',0);const v=p.tryFire(t,true,0,finite);assert.ok(v,power);v.shells=[{}];}
  const [held,repressed]=tanks;
  const release=15+star*1000,arrival=30+star*1000;
  p.tryFire(repressed,false,release,options({active:false}));
  p.tryFire(repressed,true,release+5,finite);
  for(const t of tanks){Object.assign(t,{power:'',ammoEpoch:1,charges:0,machineRounds:0,starmanTime:0,cooldown:0,shotSerial:1});p.sync(t,'playing',arrival);}
  assert.equal(p.tryFire(held,true,arrival+1,options()),null,`${power} ${timer?'expiry':'depletion'} still consumes its original P1 hold`);
  const v=p.tryFire(repressed,true,arrival+1,options());
  assert.ok(v,`${power} ${timer?'expiry':'depletion'} must preserve P2's early new hold`);
  assert.equal(v.power,'');assert.equal(v.ammoEpoch,1);assert.equal(v.shot,2,'stale finite authority cannot reserve an extra volley after its known expiry');
 }
});
test('a repress before the weapon actually expires is still consumed and Starman freezes that deadline',()=>{
 for(const power of ['rapid','scatter','homing','grenade','laser','cannon'])for(const star of [0,.02]){
  const p=new N.ShotPresentation(),t=tank({power,powerTime:.03,starmanTime:star,charges:3,machineRounds:180});
  const finite=options({charged:power!=='rapid',cooldown:power==='rapid'?0:.5});
  p.sync(t,'playing',0);assert.ok(p.tryFire(t,true,0,finite));
  p.tryFire(t,false,10,options({active:false}));p.tryFire(t,true,20,finite);
  Object.assign(t,{power:'',ammoEpoch:1,charges:0,machineRounds:0,starmanTime:0,cooldown:0,shotSerial:1});p.sync(t,'playing',60);
  assert.equal(p.tryFire(t,true,61,options()),null,`${power}, Star ${star}: this hold began before expiry`);
  p.tryFire(t,false,62,options({active:false}));assert.ok(p.tryFire(t,true,63,options()));
 }
});
test('an unconfirmed final preview cannot replace the actual later expiry with speculative depletion',()=>{
 for(const power of ['rapid','scatter','homing','grenade','laser','cannon'])for(const star of [0,.02]){
  const p=new N.ShotPresentation(),t=tank({power,powerTime:.05,starmanTime:star,charges:1,machineRounds:1});
  const finite=options({charged:power!=='rapid',cooldown:power==='rapid'?0:.5});
  p.sync(t,'playing',0);const elapsed=star*1000,view={...t,starmanTime:0};
  const preview=p.tryFire(view,true,elapsed,finite);assert.ok(preview);preview.shells=[{}];
  p.tryFire(view,false,elapsed+10,options({active:false}));p.tryFire(view,true,elapsed+20,finite);
  // Authority rejected that volley. Its timer resumes after Star's frozen
  // interval and still ends after the new hold has begun.
  Object.assign(t,{powerTime:.02,starmanTime:0,cooldown:.2});p.sync(t,'playing',elapsed+30);
  Object.assign(t,{power:'',ammoEpoch:1,charges:0,machineRounds:0,powerTime:0,starmanTime:0,cooldown:0});
  const arrival=60+star*1000;p.sync(t,'playing',arrival);
  const before=p.previews.size;
  assert.equal(p.tryFire(t,true,arrival+1,options()),null,`${power}, Star ${star}: rejected final preview cannot rearm the consumed hold`);
  assert.equal(p.previews.size,before);
  p.tryFire(t,false,arrival+2,options({active:false}));assert.ok(p.tryFire(t,true,arrival+3,options()));
 }
});
test('input acknowledgements distinguish a delayed old end from the new hold consuming that same volley serial',()=>{
 for(const power of ['rapid','scatter','homing','grenade','laser','cannon'])for(const timer of [false,true])for(const acknowledgedNewHold of [false,true]){
  const p=new N.ShotPresentation(),t=tank({power,powerTime:.05,charges:timer?3:1,machineRounds:timer?180:1});
  const finite=options({charged:power!=='rapid',cooldown:power==='rapid'?0:.5});
  p.sync(t,'playing',0);const preview=p.tryFire(t,true,0,{...finite,sequence:1});assert.ok(preview);preview.shells=[{}];
  p.tryFire(t,false,10,options({active:false,sequence:2}));
  p.tryFire(t,true,20,{...finite,sequence:3});
  Object.assign(t,{power:'',ammoEpoch:1,charges:0,machineRounds:0,cooldown:0,shotSerial:1,ack:acknowledgedNewHold?3:1});
  p.sync(t,'playing',60);
  const standard=p.tryFire(t,true,61,options({sequence:3}));
  if(acknowledgedNewHold){
   assert.equal(standard,null,`${power} ${timer?'expiry':'last shot'} consumed the new acknowledged hold`);
   p.tryFire(t,false,62,options({active:false,sequence:4}));assert.ok(p.tryFire(t,true,63,options({sequence:5})));
  }else assert.ok(standard,`${power} authority predates the fresh press, which must remain usable`);
 }
});
test('an accepted standard volley proves that an early new hold was rearmed',()=>{
 const p=new N.ShotPresentation(),t=tank({power:'homing',powerTime:15,charges:1});
 p.sync(t,'playing',0);const finite=options({charged:true,cooldown:.36});p.tryFire(t,true,0,{...finite,sequence:1}).shells=[{}];
 p.tryFire(t,false,10,options({active:false,sequence:2}));p.tryFire(t,true,20,{...finite,sequence:3});
 Object.assign(t,{power:'',ammoEpoch:1,charges:0,cooldown:0,shotSerial:2,ack:3});p.sync(t,'playing',400);
 assert.ok(p.tryFire(t,true,401,options({sequence:3})));assert.equal(p.pilots.get(t.id).blocked,false);
});
test('dry feedback reserves no preview, sound-deduplication key or shot serial and never doubles a real shot',()=>{
 const p=new N.ShotPresentation(),t=tank(),dry=[];p.sync(t,'playing',0);
 const empty=options({free:0,onDryFire:()=>dry.push('dry')});assert.equal(p.tryFire(t,true,0,empty),null);assert.deepEqual(dry,['dry']);
 assert.equal(p.previews.size,0);assert.equal(p.soundKeys.size,0);assert.equal(p.pilots.get(t.id).next,0);
 p.tryFire(t,true,500,empty);assert.equal(dry.length,1);p.tryFire(t,false,501,empty);p.tryFire(t,true,502,empty);assert.equal(dry.length,2);
 p.tryFire(t,false,503,empty);const real=p.tryFire(t,true,504,options({onDryFire:()=>dry.push('dry')}));assert.ok(real);assert.equal(dry.length,2);assert.equal(real.shot,1);
});
test('rejected previews expire and cannot hide a later valid server shot forever',()=>{
 const p=new N.ShotPresentation(),t=tank();p.sync(t,'playing',0);p.tryFire(t,true,0,options());
 p.prune(901,new Set([0]));assert.equal(p.previews.size,0);assert.equal(p.pilots.get(0).next,0);
 p.prune(2100,new Set([0]));assert.equal(p.soundKeys.size,0);
});
test('respawn and replacement life cannot inherit old cosmetic bullets or cooldown',()=>{
 const p=new N.ShotPresentation(),t=tank();p.sync(t,'playing',0);p.tryFire(t,true,0,options());
 const newLife={...t,spawnSerial:2};p.sync(newLife,'playing',20);assert.equal(p.previews.size,0);close(p.cooldown(newLife,20),0);
 assert.equal(p.heard(0,2,1),false);p.prune(30,new Set());assert.equal(p.pilots.size,0);
});
test('short remote packet gap preserves bounded angular velocity',()=>{
 const b=new N.SnapshotBuffer(),free=(t,x,y)=>{t.x+=x;t.y+=y};
 const snap=(tick,angle)=>{const t=tank({id:1,angle,track:0,vx:0,vy:0});return{tick,tankMap:new Map([[1,t]])}};
 b.push(snap(2,0),0);b.push(snap(4,3.65/30),33.333);b.time=4*N.STEP_MS+40;
 const f=b.advance(0),t=b.tank(1,f,free);close(t.angle,3.65/30+3.65*.04);
 b.time=1e7;const u=b.tank(1,b.advance(1/60),free);assert.ok(u.angle<=3.65/30+7.25*.075+1e-6);
});
test('remote turn extrapolation never crosses a respawn',()=>{
 const b=new N.SnapshotBuffer(),a=tank({id:1,angle:0,track:0}),z=tank({id:1,angle:2,spawnSerial:2,track:0});
 b.push({tick:2,tankMap:new Map([[1,a]])},0);b.push({tick:4,tankMap:new Map([[1,z]])},33);b.time=4*N.STEP_MS+30;
 close(b.tank(1,b.advance(0),()=>{}).angle,2);
});
