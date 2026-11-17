'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {assetPath}=require('./web_assets.cjs');

test('showcase laser visibly ricochets, destroys one labelled tank, and clears every survivor',()=>{
 const context={window:{}};vm.runInNewContext(fs.readFileSync(assetPath('showcase-scene.js'),'utf8'),context);
 const wide=context.window.leqraShowcaseScene;
 for(const scene of [wide,wide.portrait,wide.desktop]){
  const hero=scene.tanks.find(tank=>tank.id===scene.localID);
  const points=scene.effects.find(effect=>effect.kind==='laser'&&effect.owner===hero.id).points;
  const ux=Math.cos(hero.angle),uy=Math.sin(hero.angle),muzzle=points[0];
  assert.ok(Math.abs(muzzle.x-hero.x-28*ux)<1e-6&&Math.abs(muzzle.y-hero.y-28*uy)<1e-6,'laser starts at the forward muzzle');
  const dx=points[1].x-muzzle.x,dy=points[1].y-muzzle.y;
  assert.ok(dx*ux+dy*uy>=54,'the initial beam extends visibly ahead of the barrel');
  assert.ok(Math.abs(dx*uy-dy*ux)<1e-6,'initial beam follows the barrel');
  const distance=(tank,a,b)=>{
   const sx=b.x-a.x,sy=b.y-a.y,length=sx*sx+sy*sy;
   const t=length?Math.max(0,Math.min(1,((tank.x-a.x)*sx+(tank.y-a.y)*sy)/length)):0;
   return Math.hypot(a.x+t*sx-tank.x,a.y+t*sy-tank.y);
  };
  for(let i=2;i<points.length;i++){
   const a=points[i-1],b=points[i],sx=b.x-a.x,sy=b.y-a.y;
   const t=Math.max(0,Math.min(1,((hero.x-a.x)*sx+(hero.y-a.y)*sy)/(sx*sx+sy*sy)));
   assert.ok(Math.hypot(a.x+t*sx-hero.x,a.y+t*sy-hero.y)>=32,'reflected beam clears P1');
  }
  const victims=scene.tanks.filter(tank=>tank.hp===0);
  assert.equal(victims.length,1);
  const victim=victims[0];assert.ok(victim.name,'the destroyed tank retains its callsign');
  assert.ok(points.some((point,i)=>i>0&&distance(victim,points[i-1],point)<1),'the laser crosses the destroyed tank');
  assert.ok(scene.effects.some(effect=>effect.kind==='hit'&&effect.owner===victim.id&&effect.x===victim.x&&effect.y===victim.y),'the tank has a visible death effect');
  for(const tank of scene.tanks.filter(tank=>tank.hp>0&&tank!==hero)){
   assert.ok(points.every((point,i)=>!i||distance(tank,points[i-1],point)>=32),'beam clears surviving '+tank.name);
  }
  const visible=points.slice(1,-1).filter(point=>Math.abs(point.x-hero.x)<(scene===wide.portrait?176:540)&&Math.abs(point.y-hero.y)<264);
  assert.ok(visible.length>=3,'at least three wall bounces fit inside the showcase view');
  const cannons=scene.bullets.filter(bullet=>bullet.kind==='cannon');
  assert.ok(cannons.length>0);
  assert.ok(cannons.some(bullet=>bullet.trail.length>14),'a cannon projectile retains a long visible trail');
 }
});
