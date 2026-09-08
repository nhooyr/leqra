'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {boot:base,tank,declaration}=require('./godlike426-harness.cjs'),Net=require('../web/netcode.js');
const close=(a,b)=>assert.ok(Math.abs(a-b)<1e-8,`${a} != ${b}`);
function boot(){
 const s=base(),noop=()=>{},buffer=new Net.SnapshotBuffer();
 Object.assign(s,{mode:'online',phase:'playing',now:1000,round:1,roundClock:75,phaseTime:0,roundWinner:-1,scores:[],gameStarted:true,particles:[],rings:[],traces:[],goUntil:0,shake:0,WEBKIT_ENGINE:false,Net,COLORS:['#fff'],
  performance:{now:()=>s.now},updateOnlineBounceSounds:noop,cacheMap:noop,resize:noop,clearInput:noop,sendOnlineInput:noop,closeVictory:noop,setScreen:noop,renderOnlineRoom:noop,updateHUD:noop,showStartingControls:noop,onlineEffect:noop,syncRestartWaveActions:noop,
  secondaryID:()=>1,secondLocal:()=>({id:1}),onlineControls:()=>({forward:true,reverse:false,left:false,right:false,fire:false,stickX:0,stickY:0}),
  survivalState:()=>s.online.snapshots.at(-1)?.objectives?.survival,survivalBreak:()=>s.survivalState()?.status==='break',
  online:{id:0,connected:true,menu:false,generation:1,lastMatch:1,snapshots:buffer.items,buffer,ownedIDs:new Set(),activeIDs:new Set(),trailIDs:new Set(),trails:new Map(),localBullets:new Map(),effectQueue:[],shots:new Net.ShotPresentation(),eventsInitialized:true,lastEvent:0}
 });
 s.online.predictor=new Net.Predictor(s.moveTank);s.online.secondary={predictor:new Net.Predictor(s.moveTank)};
 for(const name of ['netTank','receiveOnlineState','predictOnlineTank','applyOnlineTankEffects','renderOnlineMotion','activeTankPowerBadges'])vm.runInContext(declaration(name),s);
 let tick=58;s.packet=(patch={},status='wave',phase='playing')=>({tick:tick+=2,generation:1,phase,round:1,roundClock:75,phaseTime:2,winner:-1,scores:[],bullets:[],pickups:[],events:[],objectives:{survival:{wave:1,status}},tanks:[0,1,3].map(id=>tank(id,126+id*100,126,{bot:id===3,spawnSerial:1,ack:0,ackSteps:0,power:'laser',powerTime:10,charges:3,machineRounds:0,shield:10,shieldCharges:1,speedTime:10,speedStacks:1,scopeTime:10,ghostTime:10,...patch}))});
 s.receive=(patch,status,phase)=>{const p=s.packet(patch,status,phase);s.receiveOnlineState(p);return p;};
 return s;
}

test('buffered tank positions use newest authoritative equipment and ammo without mutating either snapshot',()=>{
 const s=boot();s.receive();s.now+=34;s.receive({charges:2});s.now+=34;const newest=s.receive({x:650,power:'homing',charges:1,shieldCharges:4,speedStacks:3});
 const before=s.online.snapshots.map(p=>JSON.stringify(p.tanks));s.online.buffer.time=s.online.snapshots[0].netTime;s.renderOnlineMotion(0,s.now);
 const remote=s.tanks.find(t=>t.id===3);assert.notEqual(remote.x,newest.tankMap.get(3).x,'movement keeps its buffered position');assert.equal(remote.power,'homing');assert.equal(remote.charges,1);assert.equal(remote.shieldCharges,4);assert.equal(remote.speedStacks,3);
 assert.deepEqual(s.online.snapshots.map(p=>JSON.stringify(p.tanks)),before);
});

test('all visual power-up timers progress between snapshots, refresh immediately and expire without stale icons',()=>{
 const s=boot(),fields=['powerTime','shield','speedTime','scopeTime','ghostTime'],values=Object.fromEntries(fields.map(k=>[k,3.02]));
 const snapshot=s.receive(values),original=JSON.stringify(snapshot.tanks);s.renderOnlineMotion(0,1120);
 for(const t of s.tanks)for(const field of fields)close(t[field],2.9);
 assert.equal(JSON.stringify(snapshot.tanks),original);assert.equal(s.online.predictor.state.powerTime,3.02,'drawing does not change prediction state');
 s.now=1200;const fresh=s.receive({...values,power:'rapid',machineRounds:87});s.renderOnlineMotion(0,1250);
 for(const t of s.tanks){assert.equal(t.power,'rapid');assert.equal(t.machineRounds,87);for(const field of fields)close(t[field],2.97);}
 s.renderOnlineMotion(0,5000);for(const t of s.tanks){assert.equal(t.power,null);assert.equal(t.machineRounds,0);assert.equal(t.shieldCharges,0);assert.equal(t.speedStacks,0);assert.deepEqual(Array.from(s.activeTankPowerBadges(t)),[]);}
 assert.equal(fresh.tankMap.get(3).power,'rapid');assert.equal(fresh.tankMap.get(3).machineRounds,87);
});

test('Survival breaks discard prior-wave prediction and freeze both local pilots, remote positions and every buff timer',()=>{
 const s=boot();s.receive({ghostTime:.1,scopeTime:.1});s.predictOnlineTank(.05);
 assert.ok(s.online.predictor.stepID>0);assert.ok(s.online.secondary.predictor.stepID>0);
 s.now+=34;const held=s.receive({ghostTime:.1,scopeTime:.1},'break'),before=JSON.stringify(held.tanks);
 for(const [id,channel] of [[0,s.online],[1,s.online.secondary]]){assert.equal(channel.predictor.stepID,0,'break must discard unprocessed old-wave controls');close(channel.predictor.state.x,held.tankMap.get(id).x);}
 for(let i=0;i<20;i++)s.predictOnlineTank(.1);
 s.renderOnlineMotion(.05,7000);
 for(const t of s.tanks){const authoritative=held.tankMap.get(t.id);for(const field of ['x','y','powerTime','shield','speedTime','scopeTime','ghostTime'])close(t[field],authoritative[field]);}
 assert.equal(JSON.stringify(held.tanks),before);assert.equal(s.online.predictor.stepID,0);assert.equal(s.online.secondary.predictor.stepID,0);
 s.now=7100;s.receive({},'wave');s.predictOnlineTank(Net.STEP);assert.ok(s.online.predictor.stepID>0,'live prediction resumes for the next active wave');
});

test('countdowns and completed scenes keep timer values fixed',()=>{
 for(const phase of ['countdown','roundOver','matchOver','paused']){
  const s=boot(),p=s.receive({scopeTime:.1,ghostTime:.1},'wave',phase);s.renderOnlineMotion(0,9000);
  for(const t of s.tanks)for(const field of ['powerTime','shield','speedTime','scopeTime','ghostTime'])close(t[field],p.tankMap.get(t.id)[field]);
 }
});

test('online rendering plays new ricochets once, stays silent during a wave break and clears history on reconnect',()=>{
 const s=boot();let cues=0;
 Object.assign(s,{onlineBounceCounts:new Map(),onlineBounceGeneration:null,ricochetSound:()=>cues++,localBulletVisual:n=>({...n})});
 for(const name of ['updateOnlineBounceSounds','resetOnlineMotion'])vm.runInContext(declaration(name),s);
 const shell={id:9,owner:0,kind:'rapid',x:200,y:200,vx:280,vy:0,bounces:0};
 const show=(count,status='wave')=>{s.now+=34;const p=s.receive({},status);p.bullets=[{...shell,bounces:count}];p.bulletMap=new Map([[9,p.bullets[0]]]);s.renderOnlineMotion(.034,s.now);};
 show(0);assert.equal(cues,0);show(1);assert.equal(cues,1);show(1);assert.equal(cues,1);
 show(2,'break');assert.equal(cues,1,'intermission cannot play a cosmetic bounce');
 s.resetOnlineMotion();assert.equal(s.onlineBounceCounts.size,0);
 show(2);assert.equal(cues,1,'a reused projectile ID establishes a fresh baseline after reconnect');show(3);assert.equal(cues,2);
});
