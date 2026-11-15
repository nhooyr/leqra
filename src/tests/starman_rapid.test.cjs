'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {boot:base,tank,declaration}=require('./godlike426-harness.cjs');

function fixture(boosted=false,wallList=[]){
 const s=base({cols:24,rows:14,wallList}),noop=()=>{};
 Object.assign(s,{time:0,fxTime:0,bulletId:0,reduceMotion:true,shake:0,burst:noop,addRing:noop,shotSound:noop,ricochetSound:noop,tone:noop,impactEffect:noop,
  survivalBreak:()=>false,paintColor:x=>x,projectileTankImpact:noop});
 s.tanks=[tank(0,100,100,{human:true,power:'rapid',powerTime:15,machineRounds:180,starmanTime:boosted?8:0})];
 for(const name of ['powerCapacity','activeAmmo','fire','updateBullets','compactNotDead','rapidTracerScale','drawBullet','drawBullets'])vm.runInContext(declaration(name),s);
 return s;
}
function near(actual,expected,label){assert.ok(Math.abs(actual-expected)<1e-7,`${label}: ${actual} != ${expected}`);}

test('Starman machine-gun rounds double speed and total range while retaining the straight path and radius',()=>{
 const normal=fixture(),star=fixture(true),a=normal.muzzleProjectile(normal.tanks[0],0),b=star.muzzleProjectile(star.tanks[0],0);
 near(a.vx,846,'normal speed');near(b.vx,1692,'boosted speed');assert.equal(a.vy,0);assert.equal(b.vy,0);
 near(a.r,3.5/3,'normal radius');near(b.r,a.r,'boosted radius');
 near(a.life*a.vx+28,(normal.W+normal.H)/2,'normal full range');
 near(b.life*b.vx+28,star.W+star.H,'boosted full range');near(b.life,a.life+28/1692,'full-range lifetime includes the doubled muzzle allowance');
 for(const power of [null,'scatter','homing','grenade','cannon'])assert.deepEqual(JSON.parse(JSON.stringify(normal.projectileSpec(power,true))),JSON.parse(JSON.stringify(normal.projectileSpec(power))),power||'regular');
});

test('the combo retains one shot per tick, saves ammo, and does not retune rounds already in flight',()=>{
 const s=fixture(true),pilot=s.tanks[0];
 for(let tick=1;tick<=60;tick++){s.time=tick/60;assert.equal(s.fire(pilot),true);assert.equal(s.fire(pilot),false,'duplicate render callback cannot add a volley');}
 assert.equal(s.bulletId,60);assert.equal(pilot.machineRounds,180);assert.equal(pilot.charges,0);
 const old=s.bullets[0],velocity=old.vx,life=old.life;pilot.starmanTime=0;s.time=61/60;assert.equal(s.fire(pilot),true);
 assert.equal(s.bullets.at(-1).vx,846);assert.equal(pilot.machineRounds,179);assert.equal(old.vx,velocity);assert.equal(old.life,life);
});

test('faster rapid rounds retain swept ricochets and the same spatial path budget',()=>{
 const walls=[{x:150,y:50,w:8,h:200,axis:'v'}],a=fixture(false,walls),b=fixture(true,walls);
 a.fire(a.tanks[0]);b.fire(b.tanks[0]);a.updateBullets(.1);b.updateBullets(.05);
 assert.equal(a.bullets[0].bounces,1);assert.equal(b.bullets[0].bounces,1);
 assert.ok(b.bullets[0].vx<0,'boosted shell reflects instead of tunneling');
 near(a.bullets[0].x,b.bullets[0].x,'same reflected position');near(a.bullets[0].y,b.bullets[0].y,'same reflected height');
 near(b.bullets[0].life*1692-a.bullets[0].life*846,(a.W+a.H)/2,'reflection retains the extra range budget');
});

test('individual and batched rapid tracers scale with velocity while their heads retain the collision radius',()=>{
 const s=fixture(),moves=[],radii=[],noop=()=>{},c=new Proxy({moveTo:(...p)=>moves.push(p),arc:(x,y,r)=>radii.push(r)},{get:(t,k)=>t[k]||noop,set:(t,k,v)=>(t[k]=v,true)});
 const normal={id:1,kind:'rapid',x:100,y:100,vx:846,vy:0,r:3.5/3,color:'#fff'},star={...normal,id:2,vx:1692};
 s.drawBullet(normal,c);s.drawBullet(star,c);assert.deepEqual(moves,[[92,100],[84,100]]);assert.deepEqual(radii,[3.5/3,3.5/3]);
 moves.length=radii.length=0;s.drawBullets(Array.from({length:32},(_,i)=>i%2?star:normal),c);
 assert.deepEqual(moves.slice(0,4),[[92,100],[84,100],[92,100],[84,100]]);assert.ok(radii.every(r=>r===3.5/3));
});

test('a boosted rapid tracer stops at the collision face after a ricochet',()=>{
 const s=fixture(true,[{x:100,y:50,w:8,h:200,axis:'v'}]),moves=[],noop=()=>{},c=new Proxy({moveTo:(...p)=>moves.push(p)},{get:(t,k)=>t[k]||noop,set:(t,k,v)=>(t[k]=v,true)});
 const bullet={kind:'rapid',x:98.7,y:100,vx:-1692,vy:0,r:3.5/3,color:'#fff'};
 s.drawBullet(bullet,c);assert.ok(moves[0][0]<=100-bullet.r+1e-7,'longer tail cannot appear on the far side of the wall');
 const query=()=>({fraction:.25});moves.length=0;s.drawBullet(bullet,c,0,false,query);near(moves[0][0],102.7,'Infinity uses its own maze query');
});

function soundFixture(){
 const s={time:0,lastMachineTone:-Infinity,nextMachineTone:-Infinity,machineToneClock:-Infinity,machineSourceTick:-Infinity,machinePlayedTick:-Infinity,machineSourceEpoch:null,
  SHOT_SOUNDS:{rapid:[[210,120,.06,.023,.014,'triangle']],regular:[[200,90,.09,.048,.029,'triangle']]},played:[]};
 s.tone=()=>s.played.push(s.time);vm.createContext(s);vm.runInContext(declaration('shotSound'),s);return s;
}
test('one phase-aware sound gate keeps sparse and dense rapid feedback steady under callback jitter',()=>{
 for(const hz of [60,90,120,144,165])for(const sourceHz of [15,60])for(const jitter of [0,.004]){
  const s=soundFixture();let event=0;
  for(let frame=0;frame<=Math.ceil(4*hz);frame++){
   s.time=frame/hz+(frame%2?jitter:0);
   while(event/sourceHz<=s.time&&event/sourceHz<4){s.shotSound('rapid',true,s.time,true);event++;}
  }
  assert.ok(s.played.length>=58&&s.played.length<=64,`${hz}/${sourceHz}/${jitter}: ${s.played.length} cues`);
  for(let i=1;i<s.played.length;i++){const gap=s.played[i]-s.played[i-1];assert.ok(gap>=.065-1/60-1e-8&&gap<=.101,`${hz}/${sourceHz}/${jitter}: ${gap}s gap`);}
 }
});
test('repeated-shot feedback coalesces batches, resets on clock rewind and rejects invalid clocks',()=>{
 const s=soundFixture();s.time=10;for(let i=0;i<30;i++)s.shotSound('rapid');assert.equal(s.played.length,1);
 s.shotSound('rapid',true,NaN);s.shotSound('rapid',true,Infinity);assert.equal(s.played.length,1);
 s.time=1;s.shotSound('rapid');assert.equal(s.played.length,2,'new arena clock can start immediately');
 s.time=1.001;s.shotSound('regular');assert.equal(s.played.length,3,'ordinary single shots retain their existing sound');
});

test('source-timed rapid cues retain cadence through wire batching without replay or catch-up bursts',()=>{
 for(const hz of [60,90,120,144,165])for(const wireHz of [20,30,60])for(const jitter of [0,.004]){
  const s=soundFixture(),epoch={};let event=0;
  for(let frame=0;frame<=Math.ceil(4*hz);frame++){
   s.time=frame/hz+(frame%2?jitter:0);
   while(event<60&&Math.ceil((event/15-1e-9)*wireHz)/wireHz<=s.time){s.shotSound('rapid',true,s.time,true,event*4,epoch);event++;}
  }
  assert.equal(s.played.length,60,`${hz}/${wireHz}/${jitter}: all sparse cues reach the mixer`);
  for(let i=1;i<s.played.length;i++)assert.ok(s.played[i]-s.played[i-1]>=.065/2-1e-8,'transport jitter cannot produce rapid catch-up bursts');
 }
 const s=soundFixture(),epoch={};s.time=10;s.shotSound('rapid',true,s.time,true,600,epoch);
 s.time=10.2;for(const tick of [600,599,604,608,612])s.shotSound('rapid',true,s.time,true,tick,epoch);
 assert.equal(s.played.length,2,'a replayed packet cannot generate a burst');
 s.time=1;s.shotSound('rapid',true,s.time,true,604,epoch);assert.equal(s.played.length,2,'clock rewind cannot replay an old source event');
 s.shotSound('rapid',true,s.time,true,0,{});assert.equal(s.played.length,3,'a fresh scene can begin at source tick zero');
});
