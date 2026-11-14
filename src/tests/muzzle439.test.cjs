'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {boot:base,tank,declaration}=require('./godlike426-harness.cjs');
function boot(power=null,offset=[27.2,20.49],wallList=[]){
 const s=base({cols:7,rows:7,wallList}),noop=()=>{};
 Object.assign(s,{time:0,bulletId:0,reduceMotion:true,mode:'room',shake:0,burst:noop,addRing:noop,tone:noop,shieldSound:noop,ricochetSound:noop,toast:noop,boom:noop,updateHUD:noop,shotSound:noop,addLog:noop,blastEffect:noop,impactEffect:noop,objectiveMode:()=>false,survivalBreak:()=>false,laserEffect:noop,recordLocalDeath(t,owner){s.deaths.push([t.id,owner]);},deaths:[]});
 s.tanks=[tank(0,100,100,{human:true,power,charges:3,powerTime:10,machineRounds:180}),tank(1,100+offset[0],100+offset[1])];
 vm.createContext(s);for(const name of ['tankHit','powerCapacity','activeAmmo','fire','fireLaser','aimingGuide','shotPrediction','hurt','detonate','updateBullets','compactNotDead'])vm.runInContext(declaration(name),s);
 if(declaration('fire').includes('projectileTankImpact('))vm.runInContext(declaration('projectileTankImpact'),s);
 return s;
}

test('phased wall-facing weapons always fire and ricochet without tunneling forward',()=>{
 const wall={x:101,y:80,w:8,h:50,axis:'v'};
 for(const phase of ['ghost','starman'])for(const power of [null,'laser','grenade','rapid','scatter','homing'])for(const origin of ['face','embedded','corner']){
  const label=[phase,power||'regular',origin].join('/'),s=boot(power,[40,0],[wall]),[a,b]=s.tanks;
  const radius=power==='laser'?3:s.projectileSpec(power).r;
  a.ghostTime=6;if(phase==='starman')a.starmanTime=6;
  if(origin==='embedded')a.x=105;
  if(origin==='corner')Object.assign(a,{x:wall.x-.9*radius,y:wall.y-.9*radius,angle:Math.PI/4});
  const launch=s.projectileLaunch(a,a.angle,radius,28),charges=a.charges,rounds=a.machineRounds;
  assert.equal(launch.valid,true,label);assert.equal(launch.bounced,true,label);
  assert.equal(s.fire(a),true,label);
  const guide=s.aimingGuide(a);assert.ok(guide.points.length>=2,label+' aiming guide is visible');assert.ok(guide.points[1].x<guide.points[0].x||guide.points[1].y<guide.points[0].y,label+' guide reflects');
  if(phase==='starman'){assert.equal(a.charges,charges,label);assert.equal(a.machineRounds,rounds,label);}
  else if(power==='rapid')assert.equal(a.machineRounds,rounds-1,label);
  else if(power)assert.equal(a.charges,charges-1,label);
  if(origin!=='corner')assert.equal(b.alive,true,label+' may not tunnel forward');
  if(power==='laser'){
   const beam=s.laserTrace(a);assert.equal(beam.points[0].x,launch.x,label);assert.equal(beam.points[0].y,launch.y,label);
   assert.ok(beam.points[1].x<launch.x||beam.points[1].y<launch.y,label+' laser reflects from its visible anchor');
  }else{
   assert.equal(s.bullets.length,power==='scatter'?3:1,label);
   for(const bullet of s.bullets){assert.ok(bullet.bounces>=1,label);assert.ok(bullet.vx<0||bullet.vy<0,label);if(power==='homing'||power==='grenade')assert.equal(bullet.seekDelay,.04,label);}
  }
 }
 const s=boot('cannon',[40,0],[wall]);s.tanks[0].ghostTime=6;
 assert.equal(s.fire(s.tanks[0]),true);assert.equal(s.tanks[1].alive,false,'Cannon penetrates the wall');
});

test('fully solid geometry absorbs a legal phased shot without tunneling or reusing its charge',()=>{
 for(const power of [null,'laser','grenade','rapid','scatter','homing']){
  const s=boot(power,[100,0],[{x:0,y:0,w:500,h:500}]),[a,b]=s.tanks;a.ghostTime=6;
  assert.equal(s.fire(a),true,String(power));assert.equal(s.bullets.length,0,String(power));assert.equal(b.alive,true,String(power));
  if(power==='rapid')assert.equal(a.machineRounds,179);else if(power)assert.equal(a.charges,2);
  if(power==='grenade'){const forecast=s.grenadeForecast(s.muzzleProjectile(a,a.angle),3);assert.equal(forecast.life,0);assert.equal(forecast.x,a.x);assert.equal(forecast.y,a.y);}
  assert.equal(s.fire(a),false,'normal reload or same-tick rapid limiter still applies');
 }
});

test('grenades keep their full fuse through more than 22 ricochets',()=>{
 const s=boot('grenade',[200,0],[{x:54,y:80,w:8,h:50},{x:138,y:80,w:8,h:50}]);
 s.tanks.length=1;
 let blasts=0;s.blastEffect=()=>{blasts++;};
 assert.equal(s.fire(s.tanks[0]),true);
 const grenade=s.bullets[0];
 s.fire.flights.observe([grenade]);
 for(let i=0;i<1201&&!grenade.dead;i++)s.updateBullets(1/120);
 assert.ok(grenade.bounces>22);assert.ok(Math.abs(grenade.age-10)<1e-6);assert.equal(blasts,0,'fuse authority ends immediately while blast waits for the endpoint frame');s.fire.flights.sample(600,1);s.fire.flights.flush();s.fire.flights.sample(600,10);s.fire.flights.flush();assert.equal(blasts,1);
});

test('close grazing shots hit before the muzzle can skip nonoverlapping tanks',()=>{
 for(const [power,offset] of [[null,[27.2,20.49]],['homing',[26,21.99]],['grenade',[25.2,22.99]],['cannon',[17,30]]]){
  const s=boot(power,offset),[a,b]=s.tanks;assert.ok(s.distance(a,b)>a.r+b.r);
  assert.equal(s.fire(a),true);s.updateBullets(1/120);assert.equal(b.alive,false,String(power)+' must hit the swept muzzle contact');
  assert.equal(s.bullets.length,0);assert.ok(s.deaths.some(([id,owner])=>id===1&&owner===0));
 }
});

test('muzzle hits consume one shield and one charge, with no lingering projectile',()=>{
 const s=boot('homing',[26,21.99]),[a,b]=s.tanks;b.shield=10;b.shieldCharges=2;
 s.fire(a);assert.equal(b.alive,true);assert.equal(b.shieldCharges,1);assert.equal(b.invulnerable,.35);assert.equal(a.charges,2);assert.equal(s.bullets.length,0);
 s.updateBullets(1/120);assert.equal(b.shieldCharges,1,'the same launch cannot impact twice');
});

test('ordinary launch hits respect protection and friendly fire; grenades still make physical contact',()=>{
 for(const power of ['homing','grenade'])for(const reason of ['protected','friendly']){
  const s=boot(power,power==='grenade'?[25.2,22.99]:[26,21.99]),[a,b]=s.tanks;
  if(reason==='protected')b.invulnerable=1;else b.team=a.team;
  s.fire(a);assert.equal(b.alive,true,power+'/'+reason);
  assert.equal(s.bullets.length,power==='grenade'?0:1,'only a grenade impacts an immune/friendly body');
 }
 const s=boot('homing',[26,21.99]);s.tanks[1].team=s.tanks[0].team;s.friendlyFire=true;s.fire(s.tanks[0]);assert.equal(s.tanks[1].alive,false);
});

test('a nearer wall blocks launch damage while an earlier tank hit prevents a wall bounce',()=>{
 const wall={x:110,y:80,w:8,h:50,axis:'v'};
 const blocked=boot('homing',[26,21.99],[wall]);blocked.fire(blocked.tanks[0]);assert.equal(blocked.tanks[1].alive,true);assert.equal(blocked.bullets[0].bounces,1);
 const contact=boot('homing',[26,21.99],[{...wall,x:132}]);contact.fire(contact.tanks[0]);assert.equal(contact.tanks[1].alive,false);assert.equal(contact.bullets.length,0);
});

test('muzzle queries stay pure, debit actual launch travel and stop grenade forecasts at immediate impact',()=>{
 const s=boot('homing',[26,21.99]),[a,b]=s.tanks,before=JSON.stringify(s.tanks),p=s.muzzleProjectile(a,0);
 assert.equal(JSON.stringify(s.tanks),before);assert.equal(p.launchHit,b.id);assert.ok(p.x<128);assert.ok(Math.abs(p.rangeLeft-(s.W+s.H-(p.x-a.x)))<1e-6);
 assert.equal(s.deaths.length,0);assert.equal(s.bullets.length,0);
 a.power='grenade';const g=s.muzzleProjectile(a,0),pred=s.grenadeForecast(g,3);assert.equal(pred.x,g.x);assert.equal(pred.y,g.y);assert.equal(pred.life,0);assert.equal(g.life,10);assert.equal(b.alive,true);
});
