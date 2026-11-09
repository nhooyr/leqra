'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {boot,tank,declaration}=require('./godlike426-harness.cjs');

function simultaneousTick(tick,reverse,pickup){
 const s=boot({cols:7,rows:7}),noop=()=>{};
 Object.assign(s,{localTick:tick,time:0,round:1,bulletId:0,reduceMotion:true,mode:'room',shake:0,burst:noop,addRing:noop,shieldSound:noop,ricochetSound:noop,toast:noop,boom:noop,updateHUD:noop,shotSound:noop,addLog:noop,impactEffect:noop,recordLocalDeath:noop,
  objectiveMode:()=>false,survivalMode:()=>false,survivalBreak:()=>false,roundClock:75,phaseTime:0,fxTime:0,particles:[],rings:[],toastTime:0,uiClock:1,spawnClock:5,updateTraces:noop,liveLocalStats:()=>false,advanceGhost:noop,
  heldAction:(_,action)=>!pickup&&action==='fire',primaryFireHeld:()=>!pickup,firePresses:new Set(),mouseAimHeading:()=>null,stick:{mag:0},detonateOwned:()=>false,finishRound:winner=>s.winner=winner,
  grantPower:t=>s.claimant=t.id,pickupSound:noop,localPilotIndex:()=>-1});
 s.tanks=[tank(0,100,100,{human:true,localIndex:0,track:0}),tank(6,140,100,{human:true,angle:Math.PI,localIndex:1,track:0})];
 if(reverse)s.tanks.reverse();
 if(pickup)s.pickups.push({x:120,y:100,type:'shield',age:0,life:10});
 for(const name of ['powerCapacity','activeAmmo','fire','hurt','updateBullets','compactNotDead','compactLife','projectileTankImpact','weaponControl','humanControl','update'])vm.runInContext(declaration(name),s);
 s.update(1/120);
 return pickup?s.claimant:s.winner;
}

test('simultaneous local shots and pickup claims rotate through occupied seats independently of roster order',()=>{
 for(const pickup of [false,true])for(const reverse of [false,true])for(let tick=0;tick<4;tick++){
  assert.equal(simultaneousTick(tick,reverse,pickup),tick%2===0?6:0);
 }
});
