'use strict';
const assert=require('node:assert/strict'),{readFileSync}=require('node:fs'),path=require('node:path');
function declaration(source,name){
 const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);
 const end=source.indexOf('\n',start),line=source.slice(start,end);
 return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);
}
function boot({sourcePath=process.env.LEQRA_HUD_SOURCE||path.join(__dirname,'../web/game.js'),mode='room',projectileCount=192}={}){
 const source=readFileSync(sourcePath,'utf8'),nodes=new Map();
 const $=id=>{if(!nodes.has(id)){
  const attrs=new Map(),styles=new Map(),classes=new Set();
  nodes.set(id,{hidden:false,textContent:'',innerHTML:'',dataset:{},title:'',classList:{toggle:(k,on)=>on?classes.add(k):classes.delete(k),contains:k=>classes.has(k)},style:{getPropertyValue:k=>styles.get(k),setProperty:(k,v)=>styles.set(k,String(v))},getAttribute:k=>attrs.get(k),setAttribute:(k,v)=>attrs.set(k,String(v))});
 }return nodes.get(id);};
 const tanks=Array.from({length:8},(_,id)=>({id,name:'PILOT '+id,color:'#73cee4',team:id===0||id===7?1:2,alive:true,power:id===0?'grenade':'scatter',charges:3,powerTime:8,machineRounds:180,cooldown:.2,cooldownTotal:.54,ghostTime:0,shield:0,speedTime:0,scopeTime:0}));
 const bullets=Array.from({length:projectileCount},(_,n)=>({owner:n%8,kind:n%17===0?'homing':n%29===0?'grenade':'rapid',life:2.2+n%8/10,dead:n%31===0,target:n%2?7:0}));
 const rules={friendlyFire:false},online={snapshots:[{bullets,tankMap:new Map(tanks.map(t=>[t.id,t])),received:1000}]};
 const env={mode,phase:'playing',bullets,tanks,online,rules,$,nodes,now:1000,performance:{now:()=>1000},feedbackAt:-Infinity,time:1,
  controlledTank:()=>tanks[0],secondaryID:()=>7,roomData:()=>({players:tanks}),currentRules:()=>rules,isEnemy:(a,b)=>a.id!==b.id&&(a.team===0||a.team!==b.team),
  survivalBreak:()=>false,survivalMode:()=>false,objectiveMode:()=>false,combatPrefs:{visual:true,audio:false},lastLocks:{},lastLockTone:{},clearTankAt:()=>true,
  clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),paintColor:c=>c,pilotFeedback:[],shieldCount:t=>t.shieldCharges||0,speedCount:t=>t.speedStacks||0,COLORS:['#fff'],MACHINE_CAPACITY:96,MACHINE_FIRING_ROUNDS:180,CANNON_COOLDOWN:.85};
 const names=['canDamage','activeAmmo','ownedGrenades','missileLocks','setText','setStyle','setAttr','powerCapacity','cooldownDuration','liveFeedbackTank','updateMachineBudget','renderPilotLoadout','updateCombatFeedback'];
 if(source.includes('function pilotProjectileState('))names.push('pilotProjectileState');
 const constants=source.slice(source.indexOf('const POWER='),source.indexOf('\nconst LASER_MAX_SEGMENTS='));
 const factory=new Function('env','let {'+Object.keys(env).join(',')+'}=env;\n'+constants+'\n'+names.map(n=>declaration(source,n)).join('\n')+'\nreturn {'+names.join(',')+',setPhase(value){phase=value;},run(){renderPilotLoadout(tanks[0],1);renderPilotLoadout(tanks[7],2);updateCombatFeedback(true);}};');
 return Object.assign(env,factory(env));
}
module.exports={boot};
