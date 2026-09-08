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
function tank(id,rounds=180){return{id,alive:true,power:'rapid',machineRounds:rounds,charges:5,cooldown:0,ghostTime:0,spawnSerial:1,shotSerial:0};}
function boot(){
 const nodes=new Map(),a=tank(0),b=tank(7);
 const $=id=>{if(!nodes.has(id)){const attrs=new Map(),styles=new Map(),classes=new Set();nodes.set(id,{hidden:false,textContent:'',classList:{toggle:(c,on)=>on?classes.add(c):classes.delete(c)},style:{getPropertyValue:k=>styles.get(k),setProperty:(k,v)=>styles.set(k,v)},getAttribute:k=>attrs.get(k),setAttribute:(k,v)=>attrs.set(k,v)});}return nodes.get(id);};
 const s={$,performance:{now:()=>1000},feedbackAt:-Infinity,time:1,mode:'solo',phase:'playing',tanks:[a,b],controlledTank:()=>a,secondaryID:()=>7,survivalBreak:()=>false,survivalMode:()=>false,objectiveMode:()=>false,missileLocks:()=>[],combatPrefs:{visual:true,audio:false},lastLocks:{},lastLockTone:{},ownedGrenades:()=>[],powerCapacity:()=>96,activeAmmo:()=>0,clearTankAt:()=>true,cooldownDuration:()=>0,clamp:(v,a,b)=>Math.max(a,Math.min(b,v))};
 vm.createContext(s);for(const name of ['setText','setStyle','setAttr','liveFeedbackTank','updateCombatFeedback'])vm.runInContext(declaration(name),s);
 return s;
}
test('both ammo readouts show their own remaining productive firing time, rounded up to tenths',()=>{
 const s=boot();s.tanks[1].machineRounds=73;s.updateCombatFeedback(true);
 assert.equal(s.$('machineBudget1').textContent,'FIRE 3.0s');assert.equal(s.$('machineBudget2').textContent,'FIRE 1.3s');
 assert.equal(s.$('machineBudget1').hidden,false);assert.match(s.$('machineBudget2').getAttribute('aria-label'),/1.3 seconds/);
 s.tanks[0].machineRounds=1;s.updateCombatFeedback(true);assert.equal(s.$('machineBudget1').textContent,'FIRE 0.1s');
 s.tanks[0].machineRounds=0;s.updateCombatFeedback(true);assert.equal(s.$('machineBudget1').textContent,'FIRE 0.0s');
});
test('ammo budget survives pauses and ammo waits, and hides when dead, expired or replaced',()=>{
 const s=boot();s.tanks[0].machineRounds=60;s.activeAmmo=()=>96;s.updateCombatFeedback(true);
 assert.equal(s.$('cooldownText1').textContent,'WAITING FOR AMMO');assert.equal(s.$('machineBudget1').textContent,'FIRE 1.0s');
 s.phase='paused';s.updateCombatFeedback(true);assert.equal(s.$('cooldownText1').textContent,'PAUSED');assert.equal(s.$('machineBudget1').hidden,false);
 for(const patch of [{alive:false},{alive:true,power:null},{power:'laser'}]){Object.assign(s.tanks[0],patch);s.updateCombatFeedback(true);assert.equal(s.$('machineBudget1').hidden,true);}
 Object.assign(s.tanks[0],{power:'rapid',machineRounds:180});s.updateCombatFeedback(true);assert.equal(s.$('machineBudget1').hidden,false);assert.equal(s.$('machineBudget1').textContent,'FIRE 3.0s');
});
test('online ammo readouts include unacknowledged shots independently without mutating snapshots',()=>{
 const s=boot(),shots=new N.ShotPresentation(),a=tank(0,61),b=tank(7,121);
 s.mode='online';s.online={snapshots:[{tankMap:new Map([[0,a],[7,b]]),received:1000}],shots};
 shots.sync(a,'playing',1000);shots.sync(b,'playing',1000);
 const options={active:true,free:96,need:1,cooldown:0,ttl:600};assert.ok(shots.tryFire(a,true,1000,options));
 s.updateCombatFeedback(true);assert.equal(s.$('machineBudget1').textContent,'FIRE 1.0s');assert.equal(s.$('machineBudget2').textContent,'FIRE 2.1s');assert.equal(a.machineRounds,61);
 assert.ok(shots.tryFire(b,true,1000,options));s.updateCombatFeedback(true);assert.equal(s.$('machineBudget2').textContent,'FIRE 2.0s');assert.equal(b.machineRounds,121);
 a.machineRounds=60;a.shotSerial=1;shots.sync(a,'playing',1001);s.updateCombatFeedback(true);assert.equal(s.$('machineBudget1').textContent,'FIRE 1.0s');
});
