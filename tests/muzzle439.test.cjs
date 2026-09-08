'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {boot:base,tank,declaration}=require('./godlike426-harness.cjs');
function boot(power=null,offset=[27.2,20.49],wallList=[]){
 const s=base({cols:7,rows:7,wallList}),noop=()=>{};
 Object.assign(s,{time:0,bulletId:0,lastBounceSound:0,reduceMotion:true,mode:'room',shake:0,burst:noop,addRing:noop,tone:noop,toast:noop,boom:noop,updateHUD:noop,shotSound:noop,addLog:noop,blastEffect:noop,impactEffect:noop,objectiveMode:()=>false,survivalBreak:()=>false,clearTankAt:()=>true,recordLocalDeath(t,owner){s.deaths.push([t.id,owner]);},deaths:[]});
 s.tanks=[tank(0,100,100,{human:true,power,charges:3,powerTime:10,machineRounds:180}),tank(1,100+offset[0],100+offset[1])];
 vm.createContext(s);for(const name of ['tankHit','powerCapacity','activeAmmo','fire','hurt','detonate','updateBullets','compactNotDead'])vm.runInContext(declaration(name),s);
 if(declaration('fire').includes('projectileTankImpact('))vm.runInContext(declaration('projectileTankImpact'),s);
 return s;
}

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
