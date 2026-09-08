'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),{boot}=require('./hud438-harness.cjs');
const close=(a,b)=>assert.ok(Math.abs(a-b)<1e-8,`${a} != ${b}`);
const timers=['powerTime','shield','speedTime','scopeTime','ghostTime'];
function equipped(s,id,life=.1){
 const t=s.tanks[id];Object.assign(t,{power:'rapid',machineRounds:120,charges:2,cooldown:.6,shieldCharges:2,speedStacks:3,...Object.fromEntries(timers.map(k=>[k,life]))});return t;
}
function refresh(s){for(const [num,id]of [[1,0],[2,7]])s.renderPilotLoadout(s.pilotLoadoutTank(id),num);s.updateCombatFeedback(true);}

test('both online pilot HUDs expire weapons and buffs between snapshots without changing authority',()=>{
 const s=boot({mode:'online',projectileCount:0});equipped(s,0);equipped(s,7);const auth=s.online.snapshots[0],before=JSON.stringify([...auth.tankMap.values()]);
 refresh(s);assert.equal(s.$('machineBudget1').hidden,false);assert.equal(s.$('machineBudget2').hidden,false);
 s.now+=120;refresh(s);
 for(const [num,suffix]of [[1,''],[2,'2']]){
  assert.equal(s.$('weaponLabel'+suffix).textContent,'STANDARD');assert.equal(s.$('buffLabel'+suffix).hidden,true);assert.equal(s.$('machineBudget'+num).hidden,true);assert.equal(s.$('ammoDots'+suffix).hidden,false);
  const t=s.liveFeedbackTank(s.tanks[num===1?0:7]);for(const field of timers)assert.equal(t[field],0);assert.equal(t.machineRounds,0);assert.equal(t.shieldCharges,0);assert.equal(t.speedStacks,0);
 }
 assert.equal(JSON.stringify([...auth.tankMap.values()]),before,'HUD extrapolation never mutates snapshots or controlled tanks');
});

test('fresh authoritative loadouts replace stale rendered equipment and then age continuously',()=>{
 const s=boot({mode:'online',projectileCount:0});equipped(s,0);equipped(s,7);s.now+=120;refresh(s);
 const current=s.online.snapshots[0],a={...s.tanks[0],power:'laser',powerTime:2.05,charges:1,shield:2.05,speedTime:2.05,scopeTime:2.05,ghostTime:2.05},b={...a,id:7,name:'SECOND',charges:3};
 s.online.snapshots.push({...current,received:s.now,tankMap:new Map([[0,a],[7,b]])});s.now+=120;refresh(s);
 assert.equal(s.$('weaponLabel').textContent,'LASER ×1 · 2s');assert.equal(s.$('weaponLabel2').textContent,'LASER ×3 · 2s');assert.equal(s.$('ammoDots').getAttribute('aria-label'),'PILOT 0: 1 of 3 laser charges available');
 for(const id of [0,7])for(const field of timers)close(s.pilotLoadoutTank(id)[field],1.93);
 assert.equal(s.tanks[0].power,'rapid','the old rendered body remains untouched');assert.equal(a.powerTime,2.05);
});

test('Survival intermissions discard speculative firing-budget changes and freeze both pilot loadouts',()=>{
 const s=boot({mode:'online',projectileCount:0});equipped(s,0);equipped(s,7);s.survival={status:'break',breakTime:2};
 s.online.shots={machineRounds:()=>119,cooldown:()=>0,pilots:new Map()};s.now+=1200;refresh(s);
 for(const [num,id]of [[1,0],[2,7]]){
  const t=s.liveFeedbackTank(s.tanks[id]);for(const field of timers)close(t[field],.1);close(t.cooldown,.6);assert.equal(t.machineRounds,120);assert.equal(s.$('machineBudgetTime'+num).textContent,'2.0 / 3s');assert.equal(s.$('cooldownText'+num).textContent,'NEXT WAVE 2s');
 }
 // A new active wave can show local firing immediately again.
 s.survival.status='wave';s.online.snapshots[0].received=s.now;refresh(s);assert.equal(s.liveFeedbackTank(s.tanks[0]).machineRounds,119);assert.equal(s.liveFeedbackTank(s.tanks[0]).cooldown,0);
});

test('countdown, pause, completed rounds and dead tanks keep authoritative equipment timers fixed',()=>{
 for(const phase of ['countdown','paused','roundOver','matchOver','playing']){
  const s=boot({mode:'online',projectileCount:0});const t=equipped(s,0);if(phase==='playing')t.alive=false;s.setPhase(phase);s.now+=1200;
  const view=s.pilotLoadoutTank(0),feedback=s.liveFeedbackTank(t);for(const field of timers){close(view[field],.1);close(feedback[field],.1);}close(feedback.cooldown,.6);assert.equal(feedback.machineRounds,120);
 }
});
