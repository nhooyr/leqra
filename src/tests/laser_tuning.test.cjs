'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {boot,tank,declaration}=require('./godlike426-harness.cjs');
function length(points){let total=0;for(let i=1;i<points.length;i++)total+=Math.hypot(points[i].x-points[i-1].x,points[i].y-points[i-1].y);return total;}
test('doubled Ultrawide laser keeps its full range through more than128 narrow-corridor reflections',()=>{
 const s=boot({cols:24,rows:14,wallList:[{x:-4,y:-4,w:2024,h:8},{x:-4,y:80,w:2024,h:8}]});
 const p=tank(0,126,42,{angle:Math.PI/2});s.tanks=[p];const beam=s.laserTrace(p);
 assert.ok(beam.points.length>129);assert.ok(beam.points.length<=257);assert.ok(Math.abs(length(beam.points)-(4*(s.W+s.H)-28))<1e-5);
});
test('Laser and Cannon fire and their readiness use a reload reduced by one third',()=>{
 for(const power of ['laser','cannon']){
  const s=boot(),p=tank(0,126,126,{human:true,power,powerTime:15,charges:3}),noop=()=>{};
  Object.assign(s,{time:0,bulletId:0,tanks:[p],survivalBreak:()=>false,shotSound:noop,burst:noop,laserEffect:noop,impactEffect:noop});
  for(const name of ['activeAmmo','powerCapacity','fire','fireLaser','cooldownDuration'])vm.runInContext(declaration(name),s);
  assert.equal(s.fire(p),true);assert.equal(p.charges,2);assert.ok(Math.abs(p.cooldown-.85*2/3)<1e-12);assert.ok(Math.abs(s.cooldownDuration(power)-p.cooldown)<1e-12);
 }
});

test('fixed shotgun simulation and prediction HUD use the halved270ms reload',()=>{
 const s=boot(),p=tank(0,126,126,{human:true,power:'scatter',powerTime:15,charges:5}),noop=()=>{};
 Object.assign(s,{time:0,bulletId:0,tanks:[p],survivalBreak:()=>false,shotSound:noop,burst:noop});
 for(const name of ['activeAmmo','powerCapacity','fire','cooldownDuration'])vm.runInContext(declaration(name),s);
 const spec=s.projectileSpec('scatter');assert.equal(spec.cooldown,.27);assert.equal(spec.speed,846);assert.equal(spec.life,3.9);assert.equal(spec.r,3.5);
 assert.equal(s.fire(p),true);assert.equal(p.charges,4);assert.equal(s.bullets.length,3);assert.equal(p.cooldown,.27);assert.equal(p.cooldownTotal,.27);assert.equal(s.cooldownDuration('scatter'),.27);
 p.cooldown=.001;assert.equal(s.fire(p),false);assert.equal(p.charges,4);p.cooldown=0;assert.equal(s.fire(p),true);assert.equal(p.charges,3);
});
