'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {assetPath}=require('./web_assets.cjs'),Net=require(assetPath('netcode.js'));
function flight(kind='cannon',patch={}){return {id:1,owner:2,colorIndex:3,kind,radius:kind==='cannon'?14:kind==='grenade'?6:3.5,
 startTick:10,endTick:11,points:[{x:100,y:100,tick:10},{x:110,y:100,tick:11}],...patch};}
for(const kind of ['regular','rapid','scatter','homing','grenade','cannon']){
 test(kind+' born and destroyed between snapshots stays visible on the authoritative path',()=>{
  const cache=new Net.ProjectileFlights(),record=flight(kind),before=JSON.stringify(record);
  cache.accept([{id:1,flight:record}],100);
  assert.deepEqual(cache.sample(9,100),[]);
  const shell=cache.sample(10.5,108)[0];assert.equal(shell.x,105);assert.equal(shell.y,100);assert.equal(shell.owner,2);
  assert.equal(cache.sample(11,116)[0].x,110,'the exact contact is drawn before removal');assert.equal(cache.sample(11.5,124).length,0);assert.equal(cache.controls(1),true,'late snapshots cannot resurrect a completed shell');
  assert.equal(JSON.stringify(record),before,'presentation does not modify authority');
 });
 test(kind+' missed sub-frame flight receives one bounded visual grace without replaying history',()=>{
  const cache=new Net.ProjectileFlights();cache.accept([{id:2,flight:flight(kind)}],100);
  assert.equal(cache.sample(12,100)[0].x,100);assert.equal(cache.sample(14,125)[0].x,105);
  assert.equal(cache.sample(20,150)[0].x,110);assert.deepEqual(cache.sample(20,158),[]);assert.equal(cache.pending(1),false);
  cache.accept([{id:2,flight:flight(kind)}],200);assert.deepEqual(cache.sample(20,200),[]);
 });
}
test('initial join and resume consume old paths silently; a previously drawn shell never replays on impact',()=>{
 const cache=new Net.ProjectileFlights();cache.accept([{id:1,flight:flight()}],100,true);assert.deepEqual(cache.sample(20,100),[]);
 cache.observe([{id:2}]);cache.accept([{id:2,flight:flight('cannon',{id:2})}],200);assert.equal(cache.sample(20,200)[0].x,110,'seen shells go directly to contact, never replay the muzzle');assert.deepEqual(cache.sample(20,208),[]);
 cache.reset();cache.accept([{id:1,flight:flight()}],300);assert.equal(cache.sample(10.5,300).length,1);
});
test('timed rim reflections follow the actual corner and stop at the tank contact',()=>{
 const cache=new Net.ProjectileFlights();cache.accept([{id:1,flight:flight('cannon',{endTick:12,points:[{x:100,y:100,tick:10},{x:110,y:100,tick:11},{x:100,y:100,tick:12}]})}],0);
 assert.equal(cache.sample(10.5,0)[0].x,105);const reflected=cache.sample(11.5,10)[0];assert.equal(reflected.x,105);assert.ok(reflected.vx<0);
 assert.equal(cache.sample(12,20)[0].x,100);assert.deepEqual(cache.sample(12,28),[]);
});

test('long cannon recovery keeps only the recent trail instead of drawing a beam back to its muzzle',()=>{
 const cache=new Net.ProjectileFlights();cache.accept([{id:1,flight:flight('cannon',{endTick:310,points:[{x:100,y:100,tick:10},{x:5740,y:100,tick:310}]})}],0);
 const shell=cache.sample(200,0)[0];assert.ok(shell.x-shell.trail[0].x<=112.8+1e-8);assert.equal(shell.trail.at(-1).x,shell.x);
});

test('local impact presentation waits for its recovered shell and is discarded on a scene reset',()=>{
 const cache=new Net.ProjectileFlights();let effects=0;const shell={id:7,owner:0,kind:'cannon',r:14,x:100,y:100};
 cache.begin(shell,10);shell.x=120;cache.terminal(shell,10,0,100);cache.defer(7,()=>effects++);
 cache.sample(10,100);cache.flush();assert.equal(effects,0);
 cache.sample(10,151);cache.flush();assert.equal(effects,0,'endpoint remains visible for a frame');cache.sample(10,159);cache.flush();assert.equal(effects,1);cache.flush();assert.equal(effects,1);
 cache.accept([{id:9,flight:flight('cannon',{id:9})}],200);cache.defer(9,()=>effects++);cache.reset();cache.flush();assert.equal(effects,1);
});
test('instantaneous muzzle contact presents a shell then expires without adding a damaging projectile',()=>{
 const cache=new Net.ProjectileFlights(),shell={id:7,owner:0,kind:'cannon',r:14,x:100,y:100};cache.begin(shell,10);shell.x=120;
 cache.terminal(shell,10,0,100);cache.terminal(shell,10,0,101);
 assert.equal(cache.items.size,1);assert.equal(cache.sample(10,100)[0].x,100);assert.equal(cache.sample(10,125)[0].x,110);
 assert.equal(cache.sample(10,150)[0].x,120);assert.equal(cache.sample(10,158).length,0);assert.equal(shell.x,120);
});
test('invalid terminal paths and unbounded histories cannot allocate unlimited render work',()=>{
 const cache=new Net.ProjectileFlights();
 for(const [i,patch]of [{points:[]},{radius:Infinity},{owner:-1},{kind:'laser'},{endTick:0},{points:[{x:NaN,y:0,tick:10},{x:0,y:0,tick:11}]}].entries())cache.accept([{id:i+1,flight:flight('cannon',patch)}],0);
 assert.equal(cache.items.size,0);
 for(let i=10;i<1500;i++)cache.accept([{id:i,flight:flight('cannon',{id:i})}],0);
 assert.equal(cache.items.size,1024);assert.ok(cache.completed.size<=2048);
 cache.reset();cache.accept([{id:1,flight:flight('cannon',{endTick:12,points:[{x:0,y:0,tick:10},{x:2,y:0,tick:12}]})}],0,false,11);
 assert.equal(cache.items.size,0,'future terminal claims cannot hold a result card open');
});
