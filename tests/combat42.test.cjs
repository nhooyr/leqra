'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const N=require('../web/netcode.js');
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
 const p=new N.ShotPresentation(),t=tank({power:'rapid'});p.sync(t,'playing',0);let count=0;
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
test('grenade hold cannot repeatedly throw or accidentally predict a blast',()=>{
 const p=new N.ShotPresentation(),t=tank({power:'grenade',charges:3});p.sync(t,'playing',0);assert.ok(p.tryFire(t,true,0,options({charged:true,cooldown:.8})));
 assert.equal(p.tryFire(t,true,1000,options({charged:true,cooldown:.8})),null);
 p.tryFire(t,false,1100,options());assert.equal(p.tryFire(t,true,1200,options({grenade:true})),null);
 assert.equal(p.tryFire(t,true,2400,options()),null);assert.equal(p.previews.size,1);
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
