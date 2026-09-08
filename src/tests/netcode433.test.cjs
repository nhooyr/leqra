'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const N=require('../web/netcode.js');
const tank=(extra={})=>({id:1,spawnSerial:1,shotSerial:0,alive:true,x:200,y:200,angle:0,track:0,vx:0,vy:0,cooldown:0,cooldownTotal:.34,...extra});
const free=(t,dx,dy)=>{t.x+=dx;t.y+=dy;};
const close=(a,b)=>assert.ok(Math.abs(a-b)<1e-7,`${a} != ${b}`);

test('remote boosted keyboard and touch rotation survives a short packet gap',()=>{
 for(const stacks of [0,1,2,5])for(const direction of [-1,1])for(const touch of [false,true]){
  const t=tank({angle:3.1,speedStacks:stacks,speedTime:stacks?3:0}),buffer=new N.SnapshotBuffer();
  const input={...N.neutral(),right:!touch&&direction>0,left:!touch&&direction<0};
  buffer.push({tick:2,tankMap:new Map([[t.id,{...t}]])},0);
  for(let step=0;step<2;step++){
   if(touch){input.stickX=Math.cos(t.angle+direction);input.stickY=Math.sin(t.angle+direction);}
   N.move(t,input,N.STEP,free);
  }
  buffer.push({tick:4,tankMap:new Map([[t.id,{...t}]])},N.STEP_MS*2);
  buffer.time=4*N.STEP_MS+40;
  const visual=buffer.tank(t.id,buffer.advance(0),free),omega=(touch?5.8:3.65)*(1+.25*stacks)*direction;
  close(N.delta(t.angle,visual.angle),omega*.04);
  close(buffer.items.at(-1).tankMap.get(t.id).angle,t.angle);
 }
});

test('remote turn extrapolation bounds abrupt corrections using the current boost',()=>{
 for(const stacks of [0,5]){
  const buffer=new N.SnapshotBuffer(),first=tank(),last=tank({angle:2.5,speedStacks:stacks,speedTime:stacks?3:0});
  buffer.push({tick:2,tankMap:new Map([[first.id,first]])},0);
  buffer.push({tick:4,tankMap:new Map([[last.id,last]])},N.STEP_MS*2);
  buffer.time=4*N.STEP_MS+1e4;
  const visual=buffer.tank(last.id,buffer.advance(0),free);
  close(N.delta(last.angle,visual.angle),5.8*(1+.25*stacks)*.075);
 }
});

test('shot cooldown tracks only its pilot’s unconfirmed previews and stops at the first match',()=>{
 const shots=new N.ShotPresentation(),a=tank({id:0}),b=tank({id:7});
 shots.sync(a,'playing',0);shots.sync(b,'playing',0);
 const own=shots.tryFire(a,true,0,{active:true,free:5,need:1,cooldown:.34});
 for(let i=0;i<60;i++)shots.previews.set('other:'+i,{owner:7,accepted:false});
 let inspected=0;const values=shots.previews.values.bind(shots.previews);
 shots.previews.values=function*(){for(const value of values()){inspected++;yield value;}};
 shots.sync(a,'playing',100);
 close(shots.cooldown(a,100),.24);
 assert.equal(inspected,1,'a pending local volley should stop the scan before unrelated previews');
 own.accepted=true;
 shots.sync(a,'playing',101);
 close(shots.cooldown(a,101),0);
 shots.prune(102,new Set([0,7]));
 assert.equal(shots.pilots.get(0).next,0,'only the other pilot has unconfirmed shots');
});
