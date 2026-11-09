'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {boot,tank,declaration}=require('./godlike426-harness.cjs');

function localCombat(tick,fire,wallList=[]){
 const s=boot({cols:7,rows:7,wallList}),noop=()=>{};
 Object.assign(s,{localTick:tick,time:0,round:1,bulletId:0,reduceMotion:true,mode:'room',shake:0,burst:noop,addRing:noop,shieldSound:noop,ricochetSound:noop,toast:noop,boom:noop,updateHUD:noop,shotSound:noop,addLog:noop,impactEffect:noop,recordLocalDeath:noop,
  objectiveMode:()=>false,survivalMode:()=>false,survivalBreak:()=>false,roundClock:75,phaseTime:0,fxTime:0,particles:[],rings:[],toastTime:0,uiClock:1,spawnClock:5,updateTraces:noop,liveLocalStats:()=>false,advanceGhost:noop,
  heldAction:(_,action)=>fire&&action==='fire',primaryFireHeld:()=>fire,firePresses:new Set(),mouseAimHeading:()=>null,stick:{mag:0},detonateOwned:()=>false,finishRound:winner=>s.winner=winner,
  grantPower:t=>s.claimant=t.id,pickupSound:noop,localPilotIndex:()=>-1});
 s.tanks=[tank(0,100,100,{human:true,localIndex:0,track:0}),tank(6,140,100,{human:true,angle:Math.PI,localIndex:1,track:0})];
 for(const name of ['powerCapacity','activeAmmo','fire','hurt','updateBullets','compactNotDead','compactLife','projectileTankImpact','weaponControl','humanControl','wallBetweenCenters','update'])vm.runInContext(declaration(name),s);
 return s;
}

function simultaneousTick(tick,reverse,pickup){
 const s=localCombat(tick,!pickup);
 if(reverse)s.tanks.reverse();
 if(pickup)s.pickups.push({x:120,y:100,type:'shield',age:0,life:10});
 s.update(1/120);
 return pickup?s.claimant:s.winner;
}

test('simultaneous local shots and pickup claims rotate through occupied seats independently of roster order',()=>{
 for(const pickup of [false,true])for(const reverse of [false,true])for(let tick=0;tick<4;tick++){
  assert.equal(simultaneousTick(tick,reverse,pickup),tick%2===0?6:0);
 }
});

test('fixed-maze Starman destroys shielded tanks at contact and honors protection and team rules',()=>{
 for(const [label,targetPatch,friendlyFire,walls,killed] of [
  ['shield',{},false,[],true],
  ['spawn protection',{invulnerable:1},false,[],false],
  ['opposing Starman',{invulnerable:1,starmanTime:1,ghostTime:1},false,[],false],
  ['teammate',{team:1},false,[],false],
  ['friendly fire',{team:1},true,[],true],
  ['wall between centers',{},false,[{x:111,y:78,w:8,h:48}],false],
 ]){
  const s=localCombat(0,false,walls),[pilot,target]=s.tanks,deaths=[];
  Object.assign(pilot,{starmanTime:4,invulnerable:4,ghostTime:4});
  Object.assign(target,{x:134,shield:10,shieldCharges:3},targetPatch);
  s.friendlyFire=friendlyFire;s.recordLocalDeath=(t,owner)=>deaths.push([t.id,owner]);
  s.update(1/60);
  assert.equal(target.alive,!killed,label);
  assert.equal(pilot.alive,true,label);
  assert.deepEqual(deaths,killed?[[6,0]]:[],label);
 }
});
