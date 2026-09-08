'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {boot,tank,bullet}=require('./godlike426-harness.cjs');

test('Godlike keeps a safe advance and scoring hold when unrelated rounds pass nearby',()=>{
 const s=boot(),t=tank(0,400,336);s.tanks=[t,tank(1,800,336)];
 s.bullets=[bullet(1,350,440,'bullet',{vx:282,vy:0,r:3.5})];
 for(const drive of [0,.15,.65,1]){const plan={angle:0,drive};assert.equal(s.godlikeDodge(t,plan,s.tune.godlike),plan);}
});

test('Godlike co-op ally advances and fires instead of hovering at middle range',()=>{
 const s=boot(),t=tank(0,126,336),human=tank(1,90,294,{team:1,human:true}),enemy=tank(2,360,336,{team:2});s.tanks=[t,human,enemy];
 let reversals=0,lastDrive=1;
 for(let i=0;i<120;i++){s.botControl(t,1/120);if(t.ai.godControl.drive*lastDrive<0)reversals++;lastDrive=t.ai.godControl.drive;}
 assert.equal(t.ai.target,enemy.id);assert.ok(t.x>180,`advance was ${t.x-126}`);assert.ok(s.fired>0);assert.equal(reversals,0,'does not rapidly alternate forward and reverse');
});

test('Godlike retreat has separation hysteresis instead of oscillating at a single threshold',()=>{
 const s=boot(),t=tank(0,126,336),enemy=tank(1,180,336);s.tanks=[t,enemy];
 s.botControl(t,1/120);assert.ok(t.ai.godControl.drive<0);
 enemy.x=t.x+84;t.ai.think=0;s.botControl(t,1/120);assert.ok(t.ai.godControl.drive<0,'continues committed retreat after clearing trigger range');
 enemy.x=t.x+110;t.ai.think=0;s.botControl(t,1/120);assert.ok(t.ai.godControl.drive>0,'resumes pressure with enough separation');
});

test('Godlike uses a safe route when it cannot take the aimed shot',()=>{
 const s=boot(),t=tank(0,126,336),enemy=tank(1,600,336);s.tanks=[t,enemy];
 s.chooseBotAim=()=>Math.PI;s.godlikeSafeShot=()=>false;
 for(let i=0;i<120;i++)s.botControl(t,1/120);
 assert.ok(t.x>220,'unsafe aim does not pull the bot away from its route');assert.equal(s.fired||0,0);
});

test('Godlike does not rebuild its route on each think after reaching the destination cell',()=>{
 const s=boot(),t=tank(0,410,336),enemy=tank(1,420,355,{invulnerable:5});s.tanks=[t,enemy];let plans=0;
 const plan=s.planBotPath;s.planBotPath=(...args)=>{plans++;return plan(...args);};
 for(let i=0;i<120;i++)s.botControl(t,1/120);
 assert.ok(plans<=3,`performed ${plans} route rebuilds in one second`);
});

test('Godlike skips pickup distance scans when the arena has no pickups',()=>{
 const s=boot(),t=tank(0,126,126),enemy=tank(1,700,336);s.tanks=[t,enemy];
 t.ai.godPickup={x:126,y:126};s.godlikeDistances=()=>{throw Error('unnecessary maze traversal');};
 assert.equal(s.godlikeDestination(t,enemy,null,s.tune.godlike),enemy);assert.equal(t.ai.godPickup,null);
});

test('an imminent projectile overrides a recent Godlike dodge commitment',()=>{
 const s=boot(),t=tank(0,400,336,{angle:Math.PI/2});s.tanks=[t,tank(1,800,336)];
 t.ai.godDodgeTime=.25;t.ai.godDodge={angle:Math.PI/2,drive:0};
 s.bullets=[bullet(1,300,336,'bullet',{vx:282,vy:0,r:3.5})];
 const plan={angle:Math.PI/2,drive:0},segments=s.forecastThreats(t,1.05,s.bullets),next=s.godlikeDodge(t,plan,s.tune.godlike);
 const score=p=>s.movementRisk(t,p.angle,p.drive,s.tune.godlike,segments,1.05).risk;
 assert.ok(score(next)<score(plan),'new lethal path overrides commitment');
});

test('Godlike values a fresh machine gun when its active firing budget is nearly spent',()=>{
 const s=boot(),t=tank(0,126,126,{power:'rapid',powerTime:12,charges:5,machineRounds:40});
 assert.ok(s.godlikePickupValue(t,{type:'rapid'})>2);
 t.machineRounds=180;assert.ok(s.godlikePickupValue(t,{type:'rapid'})<1);
});

test('Godlike repositions after unproductive aiming but preserves a scoring hill hold',()=>{
 const s=boot(),t=tank(0,126,336),enemy=tank(1,700,336);s.tanks=[t,enemy];
 for(let i=0;i<180;i++)s.godlikeProgress(t,enemy,1/120);
 assert.ok(t.ai.godAdvance>0,'turning in place must eventually request a fresh approach');
 t.ai.godAdvance=0;t.ai.godProgressClock=0;s.localObjectives={mode:'koth',hillX:t.x,hillY:t.y,radius:32};
 for(let i=0;i<360;i++)s.godlikeProgress(t,enemy,1/120);
 assert.equal(t.ai.godAdvance,0,'scoring hold is productive');
});

test('Godlike uses spawn protection instead of fleeing harmless rounds and laser lanes',()=>{
 const s=boot(),t=tank(0,400,336,{invulnerable:2}),enemy=tank(1,100,336,{power:'laser',angle:0});s.tanks=[t,enemy];
 s.bullets=[bullet(1,300,336,'bullet',{vx:282,r:3.5}),bullet(1,180,336,'homing',{vx:235,target:0})];
 const plan={angle:0,drive:.65};assert.equal(s.godlikeDodge(t,plan,s.tune.godlike),plan);
 t.invulnerable=0;assert.notEqual(s.godlikeDodge(t,plan,s.tune.godlike),plan,'same lane becomes dangerous after protection ends');
});
