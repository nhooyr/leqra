'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {boot:combatBoot,tank,declaration}=require('./godlike426-harness.cjs');
const Net=require('../web/netcode.js');

function boot(){
 const s=combatBoot(),noop=()=>{};
 Object.assign(s,{mode:'online',phase:'playing',now:1000,Net,traces:[],bursts:[],sounds:[],COLORS:['#fff','#f00'],POWER:{laser:{color:'#f57cff'}},
  secondLocal:()=>null,secondaryID:()=>undefined,clearTankAt:()=>true,updateCombatFeedback:noop,
  burst:(...args)=>s.bursts.push(args),shotSound:(...args)=>s.sounds.push(args),
  online:{id:0,connected:true,menu:false,latency:100,shots:new Net.ShotPresentation(),snapshots:[],effectQueue:[],presentationMetrics:{previews:0,suppressedSounds:0}}
 });
 const own=tank(0,84,168,{human:true,power:'laser',powerTime:10,charges:3,spawnSerial:1,shotSerial:0,color:'#fff'}),enemy=tank(1,300,168,{spawnSerial:1,shotSerial:0,color:'#f00'});
 s.tanks=[own,enemy];const snapshot={generation:1,received:s.now,tanks:s.tanks.map(t=>({...t})),bullets:[]};snapshot.tankMap=new Map(snapshot.tanks.map(t=>[t.id,t]));s.online.snapshots=[snapshot];s.online.predictor={state:{...own}};s.online.shots.sync(snapshot.tankMap.get(0),'playing',s.now);
 for(const name of ['powerCapacity','activeAmmo','cooldownDuration','laserEffect','compactLife','updateTraces','previewOnlineFire','onlineEffect'])vm.runInContext(declaration(name),s);
 s.preview=()=>s.previewOnlineFire(false,{fire:true},s.now);
 s.authority=(endX=500)=>({type:'laser',generation:1,player:0,spawnSerial:1,shotSerial:1,x:112,y:168,endX,endY:168,color:'#f57cff',points:[{x:112,y:168},{x:endX,y:168}]});
 return s;
}

test('late authoritative laser replaces an expired prediction even while its sound is deduplicated',()=>{
 for(const delay of [.24,.6])for(const phase of ['playing','roundOver']){
  const s=boot(),snapshot=s.online.snapshots[0],before=JSON.stringify(snapshot.tanks);s.preview();
  assert.equal(s.traces.length,1);assert.equal(s.traces[0].endX,280,'the rendered opponent stops the cosmetic prediction');
  s.updateTraces(delay);assert.equal(s.traces.length,0);s.now+=delay*1000;s.phase=phase;
  s.online.shots.sync({...snapshot.tankMap.get(0),shotSerial:1,charges:2,cooldown:.5},phase,s.now);
  const e=s.authority();s.onlineEffect(e,snapshot);
  assert.equal(s.traces.length,1,'the actual beam cannot disappear with its older prediction');
  assert.equal(s.traces[0].endX,500,'the server endpoint replaces the guessed hit position');
  assert.deepEqual(JSON.parse(JSON.stringify(s.traces[0].points)),e.points);
  s.onlineEffect({...e,type:'shot',text:'laser'},snapshot);
  assert.equal(s.sounds.length,1,'authoritative correction does not replay the local shot sound');
  assert.equal(JSON.stringify(snapshot.tanks),before,'beam presentation never damages a tank or spends charges');
 }
});

test('a live laser prediction reconciles in place without extending its lifetime or duplicating effects',()=>{
 const s=boot(),snapshot=s.online.snapshots[0];s.preview();s.updateTraces(.1);const trace=s.traces[0],remaining=trace.life,bursts=s.bursts.length;
 s.onlineEffect(s.authority(),snapshot);
 assert.equal(s.traces.length,1);assert.equal(s.traces[0],trace);assert.equal(trace.life,remaining);assert.equal(trace.endX,500);assert.equal(s.bursts.length,bursts);
});

test('remote and unpredicted lasers retain their authoritative path and stale generations stay ignored',()=>{
 const s=boot(),snapshot=s.online.snapshots[0],e=s.authority();e.player=1;s.onlineEffect(e,snapshot);
 assert.equal(s.traces.length,1);assert.equal(s.traces[0].endX,500);
 s.onlineEffect({...e,generation:0},snapshot);assert.equal(s.traces.length,1);
});

function networkBoot(){
 const s=boot(),noop=()=>{},first=s.online.snapshots[0];
 Object.assign(s,{performance:{now:()=>s.now},updateOnlineBounceSounds:noop,round:1,roundClock:75,roundWinner:-1,scores:[],goUntil:0,phaseTime:0,gameStarted:true,
  survivalState:()=>null,survivalBreak:()=>false,survivalMode:()=>false,objectiveMode:()=>false,suddenDeath:()=>false,
  closeVictory:noop,clearInput:noop,sendOnlineInput:noop,setScreen:noop,updateHUD:noop,addRing:noop,boom:noop,eventShake:noop,toast:noop,addLog:noop,tone:noop});
 Object.assign(s.online,{generation:1,eventsInitialized:true,lastEvent:0,ownedIDs:new Set([0]),activeIDs:new Set([0]),trailIDs:new Set(),trails:new Map(),localBullets:new Map(),buffer:new Net.SnapshotBuffer(),predictor:new Net.Predictor(s.moveTank)});
 Object.assign(first,{tick:60,phase:'playing',round:1,roundClock:75,phaseTime:0,scores:[],pickups:[],bulletMap:new Map()});
 s.online.buffer.push(first,s.now);s.online.snapshots=s.online.buffer.items;s.online.predictor.reset(first.tankMap.get(0));
 for(const name of ['netTank','receiveOnlineState','applyOnlineTankEffects','renderOnlineMotion'])vm.runInContext(declaration(name),s);
 s.sequence=[];const laserEffect=s.laserEffect;s.laserEffect=(...args)=>{s.sequence.push('laser:'+args[0]);return laserEffect(...args);};s.shotSound=kind=>s.sequence.push('shot:'+kind);s.boom=()=>s.sequence.push('hit');s.shieldSound=()=>s.sequence.push('shield');
 s.packet=(events,tick=62,damage='hit')=>({...first,tick,received:undefined,tanks:first.tanks.map(t=>({...t,alive:t.id===0?damage!=='hit':true,invulnerable:t.id===0&&damage==='shield'?.35:0})),events});
 return s;
}

test('an authoritative hit or shield save presents its queued laser first, once, without draining unrelated fire',()=>{
 for(const damage of ['hit','shield'])for(const [player,tick]of [[3,62],[1,61]]){
  const s=networkBoot(),unrelated={...s.authority(),id:1,tick,player,owner:player,x:412,points:[{x:412,y:168},{x:500,y:168}]},laser={...s.authority(),id:2,tick:62,player:1,owner:1},shot={...laser,id:3,type:'shot',text:'laser'},hit={id:4,tick:62,generation:1,type:damage,player:0,owner:1,x:300,y:168};
  s.now+=34;s.receiveOnlineState(s.packet([unrelated,laser,shot,hit],62,damage));
  assert.deepEqual(s.sequence,['laser:112','shot:laser',damage],'instant damage must not precede the beam that caused it');
  assert.deepEqual(Array.from(s.online.effectQueue,q=>q.e.id),[1],'an unrelated miss stays on its buffered timeline');
  const count=s.traces.length;s.receiveOnlineState(s.packet([unrelated,laser,shot,hit],64,damage));assert.equal(s.traces.length,count,'repeated event history cannot flash the same confirmed laser again');
  s.online.buffer.time=65*Net.STEP_MS;s.renderOnlineMotion(0,s.now);
  assert.deepEqual(s.sequence,['laser:112','shot:laser',damage,'laser:412']);assert.equal(s.online.effectQueue.length,0);
 }
});

test('repeated snapshot event history cannot replay a late authoritative local beam or its sound',()=>{
 const s=networkBoot();s.preview();s.updateTraces(.3);s.now+=300;s.sequence.length=0;
 const e={...s.authority(),id:1,tick:62},shot={...e,type:'shot',id:2,text:'laser'};
 for(const tick of [62,64,66]){
  const packet=s.packet([e,shot],tick,'none');Object.assign(packet.tanks[0],{shotSerial:1,charges:2,cooldown:.5});s.receiveOnlineState(packet);
  assert.equal(s.traces.length,1);assert.deepEqual(s.sequence,['laser:112']);
 }
});

test('online muzzle contacts suppress consumed previews without shifting volley pellets or awarding local damage',()=>{
 const s=networkBoot(),snapshot=s.online.snapshots[0],own=snapshot.tankMap.get(0),enemy=snapshot.tankMap.get(1);
 Object.assign(own,{power:'scatter'});Object.assign(enemy,{x:own.x+27.2,y:own.y-20.49});s.tanks=snapshot.tanks.map(t=>({...t}));s.online.predictor.reset(own);s.WEBKIT_ENGINE=false;
 for(const name of ['projectOnlineBullet','localBulletVisual','projectileOnTimeline'])vm.runInContext(declaration(name),s);
 const before=JSON.stringify(snapshot.tanks);s.preview();const volley=s.online.shots.previews.values().next().value;
 assert.deepEqual(Array.from(volley.shells,b=>b.pellet),[0,1,2]);assert.deepEqual(Array.from(volley.shells,b=>b.launchHit??null),[1,1,null]);
 assert.equal(JSON.stringify(snapshot.tanks),before,'a cosmetic contact cannot kill, shield-hit or consume authoritative ammo');
 s.now+=16;s.renderOnlineMotion(.016,s.now);assert.deepEqual(Array.from(s.bullets,b=>b.pellet),[2],'only the unconsumed pellet should travel through the arena');
 assert.equal(s.tanks.every(t=>t.alive),true);assert.equal(JSON.stringify(snapshot.tanks),before);
 const confirmed={...volley.shells[2],id:101,age:.03,preview:false},packet=s.packet([],62,'none');packet.bullets=[confirmed];Object.assign(packet.tanks[0],{shotSerial:1,charges:2,cooldown:.5});
 s.now+=17;s.receiveOnlineState(packet);s.renderOnlineMotion(.017,s.now);
 assert.deepEqual(Array.from(s.bullets,b=>[b.id,b.pellet]),[[101,2]]);assert.equal(volley.confirmed.has(2),true);assert.equal(volley.confirmed.has(0),false,'authority must reconcile by the original pellet index');
 assert.equal(packet.tanks.every(t=>t.alive),true);
});
