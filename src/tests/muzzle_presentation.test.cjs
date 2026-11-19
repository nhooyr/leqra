'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {boot,tank,declaration}=require('./godlike426-harness.cjs');

test('barrel retracts to the incoming wall face at every heading without doubling recoil',()=>{
 for(const angle of [0,Math.PI/4,Math.PI/2,Math.PI,Math.PI*1.5])for(const recoil of [0,.5,1]){
  const x=100,y=100,ux=Math.cos(angle),uy=Math.sin(angle);
  const vertical=Math.abs(ux)>.7,center={x:x+ux*22,y:y+uy*22};
  const wall=vertical?{x:center.x+(ux<0?-8:0),y:center.y-80,w:8,h:160}:{x:center.x-80,y:center.y+(uy<0?-8:0),w:160,h:8};
  const s=boot({wallList:[wall]}),p=tank(0,x,y,{angle,recoil});
  const retract=s.barrelRetraction(p);
  const expected=6+3.5/Math.abs(vertical?ux:uy);
  assert.ok(Math.abs(retract-expected)<1e-7,`${angle}/${recoil}: ${retract}`);
  assert.equal(s.barrelRetraction({...p,angle:angle+Math.PI}),recoil*4,'turning away restores the full barrel');
 }
});

test('corner-grazing shots retract even when the barrel centreline clears the wall',()=>{
 const wall={x:122,y:102.5,w:8,h:40};
 for(const power of [null,'rapid','scatter','homing','grenade','laser']){
  const s=boot({wallList:[wall]}),p=tank(0,100,100,{power});s.tanks=[p];
  assert.equal(s.rayWalls(100,100,30,0,0),null,'the centreline misses the corner');
  const retract=s.barrelRetraction(p);
  if(power==='rapid')assert.equal(retract,0,'a smaller round clears this corner');
  else assert.ok(retract>0,String(power)+' still needs corner clearance');
 }
});

test('open-space muzzle and barrel follow the same current tank heading',()=>{
 const s=boot();
 for(const angle of [0,.15,.9,Math.PI/2,Math.PI,-Math.PI+.01]){
  const p=tank(0,100,100,{angle,recoil:0});s.tanks=[p];
  const b=s.muzzleProjectile(p,angle);
  assert.ok(Math.abs(Math.hypot(b.x-p.x,b.y-p.y)-28)<1e-7);
  assert.ok(Math.abs(s.Net.delta(angle,Math.atan2(b.vy,b.vx)))<1e-7);
  assert.equal(s.barrelRetraction(p),0);
 }
});

test('touch steering keeps its fast large turns and gentle fine corrections',()=>{
 const s=boot(),turn=s.Net.steeringTurn;
 assert.equal(turn(Math.PI/2,1,true,1/60),9/60);
 assert.equal(turn(Math.PI/2,1,false,1/60),5.8/60);
 assert.equal(turn(.04,1,true,1/60),.04);
 assert.equal(turn(Math.PI/2,.35,true,1/60),5.8/60);
});

test('Ghost overlapping the muzzle wall reflects at its incoming face without a backward launch jump',()=>{
 for(const power of [null,'rapid','scatter','homing','grenade'])for(const gap of [22,8,1]){
  const s=boot({wallList:[{x:122,y:50,w:8,h:100}]}),p=tank(0,122-gap,100,{power,ghostTime:600});s.tanks=[p];
  const b=s.muzzleProjectile(p,0);
  assert.ok(b.vx<0);
  assert.ok(Math.abs(b.x-(122-b.r-.12))<1e-7,`${power}/${gap}: ${b.x}`);
  assert.ok(30-s.barrelRetraction(p)<=gap+.1,`${power}/${gap} barrel crossed wall`);
 }
});
