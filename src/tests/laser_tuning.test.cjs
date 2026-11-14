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
