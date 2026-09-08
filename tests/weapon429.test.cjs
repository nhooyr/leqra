'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const N=require('../web/netcode.js');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){
 const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);
 const end=source.indexOf('\n',start),line=source.slice(start,end);
 return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);
}
function tank(id,rounds=180){return{id,alive:true,power:'rapid',powerTime:10,machineRounds:rounds,charges:5,cooldown:0,ghostTime:0,spawnSerial:1,shotSerial:0};}
function boot(){
 const nodes=new Map(),a=tank(0),b=tank(7);
 const $=id=>{if(!nodes.has(id)){const attrs=new Map(),styles=new Map(),classes=new Set();nodes.set(id,{hidden:false,textContent:'',dataset:{},classList:{toggle:(c,on)=>on?classes.add(c):classes.delete(c)},style:{getPropertyValue:k=>styles.get(k),setProperty:(k,v)=>styles.set(k,v)},getAttribute:k=>attrs.get(k),setAttribute:(k,v)=>attrs.set(k,v)});}return nodes.get(id);};
 const s={$,now:1000,MACHINE_FIRING_ROUNDS:vm.runInNewContext(source.match(/MACHINE_FIRING_ROUNDS=([^,;]+)/)[1]),performance:{now:()=>s.now},feedbackAt:-Infinity,time:1,bullets:[],canDamage:()=>false,mode:'solo',phase:'playing',tanks:[a,b],controlledTank:()=>a,secondaryID:()=>7,survivalBreak:()=>false,survivalMode:()=>false,objectiveMode:()=>false,missileLocks:()=>[],combatPrefs:{visual:true,audio:false},lastLocks:{},lastLockTone:{},ownedGrenades:()=>[],powerCapacity:()=>96,activeAmmo:()=>0,clearTankAt:()=>true,cooldownDuration:()=>0,clamp:(v,a,b)=>Math.max(a,Math.min(b,v))};
 vm.createContext(s);for(const name of ['setText','setStyle','setAttr','pilotProjectileState','applyOnlineTankEffects','liveFeedbackTank','updateMachineBudget','updateCombatFeedback'])vm.runInContext(declaration(name),s);
 return s;
}
test('both ammo readouts show their own remaining productive firing time, rounded up to tenths',()=>{
 const s=boot();s.tanks[1].machineRounds=73;s.updateCombatFeedback(true);
 assert.equal(s.$('machineBudgetTime1').textContent,'3.0 / 3s');assert.equal(s.$('machineBudgetTime2').textContent,'1.3 / 3s');
 assert.equal(s.$('machineBudget1').hidden,false);assert.equal(s.$('ammoDots').hidden,true);assert.equal(s.$('ammoDots2').hidden,true);assert.match(s.$('machineBudget2').getAttribute('aria-valuetext'),/1.3 of 3 seconds/);
 s.tanks[0].machineRounds=1;s.updateCombatFeedback(true);assert.equal(s.$('machineBudgetTime1').textContent,'0.1 / 3s');
 s.tanks[0].machineRounds=0;s.updateCombatFeedback(true);assert.equal(s.$('machineBudgetTime1').textContent,'0.0 / 3s');
});
test('ammo budget survives pauses and ammo waits, and hides when dead, expired or replaced',()=>{
 const s=boot();s.tanks[0].machineRounds=60;s.bullets=Array.from({length:96},()=>({owner:0,kind:'rapid'}));s.updateCombatFeedback(true);
 assert.equal(s.$('cooldownText1').textContent,'WAITING FOR AMMO');assert.equal(s.$('machineBudgetTime1').textContent,'1.0 / 3s');
 s.phase='paused';s.updateCombatFeedback(true);assert.equal(s.$('cooldownText1').textContent,'PAUSED');assert.equal(s.$('machineBudget1').hidden,false);
 for(const patch of [{alive:false},{alive:true,power:null},{power:'laser'}]){Object.assign(s.tanks[0],patch);s.updateCombatFeedback(true);assert.equal(s.$('machineBudget1').hidden,true);assert.equal(s.$('ammoDots').hidden,false);}
 Object.assign(s.tanks[0],{power:'rapid',powerTime:10,machineRounds:180});s.updateCombatFeedback(true);assert.equal(s.$('machineBudget1').hidden,false);assert.equal(s.$('machineBudgetTime1').textContent,'3.0 / 3s');
});
test('online ammo readouts include unacknowledged shots independently without mutating snapshots',()=>{
 const s=boot(),shots=new N.ShotPresentation(),a=tank(0,61),b=tank(7,121);
 s.mode='online';s.online={snapshots:[{tankMap:new Map([[0,a],[7,b]]),received:1000}],shots};
 shots.sync(a,'playing',1000);shots.sync(b,'playing',1000);
 const options={active:true,free:96,need:1,cooldown:0,ttl:600};assert.ok(shots.tryFire(a,true,1000,options));
 s.updateCombatFeedback(true);assert.equal(s.$('machineBudgetTime1').textContent,'1.0 / 3s');assert.equal(s.$('machineBudgetTime2').textContent,'2.1 / 3s');assert.equal(a.machineRounds,61);
 assert.ok(shots.tryFire(b,true,1000,options));s.updateCombatFeedback(true);assert.equal(s.$('machineBudgetTime2').textContent,'2.0 / 3s');assert.equal(b.machineRounds,121);
 a.machineRounds=60;a.shotSerial=1;shots.sync(a,'playing',1001);s.updateCombatFeedback(true);assert.equal(s.$('machineBudgetTime1').textContent,'1.0 / 3s');
});

test('unforced live feedback follows actual shots while idle time preserves both firing budgets',()=>{
 const s=boot();Object.assign(s,{bullets:[],bulletId:0,projectileSpec:power=>({kind:power,cooldown:0}),muzzleProjectile:t=>({owner:t.id,kind:t.power}),burst(){},shotSound(){}});
 vm.runInContext(declaration('fire'),s);
 s.updateCombatFeedback();
 for(let i=0;i<72;i++){s.now+=1000/60;s.time=s.now/1000;assert.equal(s.fire(s.tanks[0]),true);if(i%2===0)assert.equal(s.fire(s.tanks[1]),true);s.updateCombatFeedback();}
 s.now+=40;s.updateCombatFeedback();
 assert.equal(s.$('machineBudgetTime1').textContent,'1.8 / 3s');assert.equal(s.$('machineBudgetTime2').textContent,'2.4 / 3s');
 assert.equal(s.$('machineBudget1').style.getPropertyValue('--firing-left'),'0.6');assert.equal(s.$('machineBudget2').style.getPropertyValue('--firing-left'),'0.8');
 assert.equal(s.$('machineBudget1').getAttribute('aria-valuenow'),'1.8');assert.equal(s.$('machineBudget1').getAttribute('aria-valuemax'),'3');
 s.now+=1000;s.updateCombatFeedback();assert.equal(s.$('machineBudgetTime1').textContent,'1.8 / 3s');assert.equal(s.$('machineBudgetTime2').textContent,'2.4 / 3s');
});
test('unforced online readout and depletion bar update before a fresh server snapshot',()=>{
 const s=boot(),shots=new N.ShotPresentation(),a=tank(0),b=tank(7);s.mode='online';s.online={snapshots:[{tankMap:new Map([[0,a],[7,b]]),received:s.now}],shots};
 shots.sync(a,'playing',s.now);shots.sync(b,'playing',s.now);s.updateCombatFeedback();
 for(let i=0;i<12;i++){s.now+=20;assert.ok(shots.tryFire(a,true,s.now,{active:true,free:96,need:1,cooldown:0,ttl:600}));s.updateCombatFeedback();}
 s.now+=40;s.updateCombatFeedback();
 assert.equal(s.$('machineBudgetTime1').textContent,'2.8 / 3s');assert.equal(s.$('machineBudget1').style.getPropertyValue('--firing-left'),String(168/180));
 assert.equal(s.$('machineBudgetTime2').textContent,'3.0 / 3s');assert.equal(a.machineRounds,180);assert.equal(b.machineRounds,180);
});

test('loadout skips hidden machine-gun slot work and restores correct slots on weapon changes',()=>{
 const s=boot(),t=s.tanks[0];Object.assign(s,{roomData:()=>null,paintColor:c=>c,POWER:{rapid:{name:'MACHINE GUN',color:'#d2f65a'},laser:{name:'LASER',color:'#fff'}},COLORS:['#fff'],pilotFeedback:[],speedCount:()=>0,shieldCount:()=>0});
 Object.assign(t,{name:'PILOT',color:'#fff',powerTime:10});vm.runInContext(declaration('renderPilotLoadout'),s);
 let writes=0,markup='';s.powerCapacity=t=>t.power==='laser'?3:5;
 const dots=s.$('ammoDots');Object.defineProperty(dots,'innerHTML',{get:()=>markup,set:v=>{writes++;markup=v;}});
 t.power='laser';t.charges=2;s.renderPilotLoadout(t,1);assert.equal(writes,1);assert.equal((markup.match(/<i /g)||[]).length,3);
 assert.equal(dots.getAttribute('aria-label'),'PILOT: 2 of 3 laser charges available');
 t.power='rapid';for(let i=0;i<5;i++){s.bullets.push({owner:0,kind:'rapid'});s.renderPilotLoadout(t,1,true);}assert.equal(writes,1);
 assert.equal(s.$('weaponLabel').textContent,'MACHINE GUN · EXPIRES 10s');
 t.power=null;s.bullets.length=2;s.renderPilotLoadout(t,1);assert.equal(writes,2);assert.equal((markup.match(/<i /g)||[]).length,5);
 assert.equal((markup.match(/empty/g)||[]).length,2);assert.equal(dots.getAttribute('aria-label'),'PILOT: 3 of 5 active projectile slots available');
 t.power='rapid';s.renderPilotLoadout(t,1);t.power=null;t.name='RENAMED';s.renderPilotLoadout(t,1);assert.equal(writes,2);assert.equal(dots.getAttribute('aria-label'),'RENAMED: 3 of 5 active projectile slots available');
});
