'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {assetPath}=require('./web_assets.cjs'),Net=require(assetPath('netcode.js'));
const move=(t,dx,dy)=>{t.x+=dx;t.y+=dy;};
function fixture(kind,shield=false){
 const r=kind==='cannon'?14:kind==='grenade'?6:kind==='rapid'?3.5/3:3.5;
 const before={x:140,y:100,angle:0,vx:0,vy:0,hp:1,shield:shield?10:0,shieldCharges:shield?2:0,invulnerable:0,spawnProtected:false};
 const contact={projectileId:7,kind,tick:12,target:3,spawnSerial:4,before};
 const flight={id:7,owner:2,colorIndex:1,kind,radius:r,startTick:10,endTick:12,points:[{x:90,y:100,tick:10},{x:140-17-r,y:100,tick:12}]};
 const authority={id:3,spawnSerial:4,alive:shield,hp:shield?1:0,x:160,y:100,angle:0,shield:shield?10:0,shieldCharges:shield?1:0,invulnerable:shield?.35:0,ghostTime:10,speedTime:10,speedStacks:5,score:123};
 return {contact,flight,authority,event:{id:1,owner:2,contact,flight},r};
}
for(const kind of ['regular','rapid','scatter','homing','grenade','cannon'])test(kind+' presents shell/body contact before damage and audio at every latency and refresh rate',()=>{
 for(const ping of [1,50,200,400])for(const fps of [60,120])for(const shield of [false,true])for(const published of [false,true])for(const view of ['attacker','victim','spectator']){
  const {contact,flight,authority,event,r}=fixture(kind,shield),cache=new Net.ProjectileFlights(),original=JSON.stringify(authority);
  if(published)cache.observe([{id:7,x:90,y:100}],10);
  cache.accept([event],ping,false,12);let audio=0;cache.deferContact(1,()=>audio++);
  const own=new Set(view==='attacker'?[2]:view==='victim'?[3]:[]),interval=1000/fps;
  let touching=false,released=false;
  for(let frame=0;frame<30;frame++){
   const now=ping+frame*interval,items=cache.sample(10+frame*interval/Net.STEP_MS,now,{own,localTick:12}),tank=cache.visualTank(authority,{...authority},null,now,move);cache.flush();
   if(cache.contactCount){
    assert.equal(tank.hp,1);assert.equal(tank.shieldCharges,contact.before.shieldCharges);assert.equal(tank.score,123);assert.equal(audio,0);
    for(const b of items)if(Math.abs(Math.hypot(b.x-tank.x,b.y-tank.y)-17-r)<1e-7)touching=true;
   }else{
    assert.ok(touching,`${kind} ${ping}ms ${fps}Hz ${view} published=${published} shield=${shield}: exact contact precedes damage`);
    assert.equal(tank.hp,authority.hp);assert.equal(tank.shieldCharges,authority.shieldCharges);assert.equal(audio,1);released=true;break;
   }
  }
  assert.ok(released);assert.equal(JSON.stringify(authority),original,'presentation never changes authoritative health, score or movement');
 }
});

test('terminal segments do not hide a previously published projectile before their start tick',()=>{
 const {event}=fixture('rapid'),cache=new Net.ProjectileFlights();cache.accept([event],0);
 assert.equal(cache.controls(7,9),false);assert.equal(cache.controls(7,10),true);
 assert.deepEqual(cache.sample(9,0),[]);assert.equal(cache.pendingPresentation,true);
});

test('offline published shell draws its exact terminal edge without rewinding an old muzzle path',()=>{
 for(const kind of ['regular','rapid','scatter','homing','grenade','cannon']){
  const {flight,authority}=fixture(kind),cache=new Net.ProjectileFlights(),b={id:7,owner:2,kind:kind==='regular'?'':kind,r:flight.radius,x:30,y:100};
  cache.begin(b,0);cache.observe([{...b,x:90}],10);b.x=flight.points.at(-1).x;
  const contact=cache.recordContact(b,{...authority,alive:true,hp:1,x:140},12,100);
  cache.terminal(b,12,1,100);assert.equal(cache.items.get(7).flight.startTick,10);
  assert.equal(cache.items.get(7).flight.points[0].x,90);
  const shell=cache.sample(12,100)[0],tank=cache.visualTank(authority,authority,null,100,move);
  assert.ok(Math.abs(Math.hypot(shell.x-tank.x,shell.y-tank.y)-17-shell.r)<1e-7);assert.equal(tank.hp,1);
  cache.sample(12,109);assert.equal(cache.contacts.get(contact).released,true);assert.equal(cache.visualTank(authority,authority,null,109,move).hp,0);
 }
});

test('Laser and Starman preserve one contact frame; own Starman is not delayed by the remote clock',()=>{
 for(const kind of ['laser','starman']){
  const {event,authority}=fixture(kind);delete event.flight;event.contact.projectileId=0;
  const cache=new Net.ProjectileFlights();cache.accept([event],0);let sounds=0;cache.deferContact(1,()=>sounds++);
  const options={own:new Set([2]),localTick:12},clock=kind==='starman'?1:12;
  cache.sample(clock,100,options);assert.equal(cache.visualTank(authority,authority,null,100,move).hp,1);cache.flush();assert.equal(sounds,0);
  cache.sample(clock,109,options);assert.equal(cache.visualTank(authority,authority,null,109,move).hp,0);cache.flush();assert.equal(sounds,1);
 }
});

test('stale victim lives and reconnects cannot replay deferred damage or apply it to a new tank',()=>{
 const {event,authority}=fixture('cannon'),cache=new Net.ProjectileFlights();cache.accept([event],0);let sounds=0;cache.deferContact(1,()=>sounds++);
 const respawn={...authority,alive:true,hp:1,spawnSerial:5};
 assert.equal(cache.status(event,new Map([[3,respawn]])),'drop');cache.flush();assert.equal(sounds,0);
 assert.equal(cache.visualTank(respawn,respawn,null,100,move),respawn);
 cache.reset();cache.accept([event],0,true);assert.equal(cache.pendingPresentation,false);assert.equal(cache.contacts.size,0);
});

test('shield survivors ease back to their current pose without moving through walls or mutating health',()=>{
 const {event,authority}=fixture('rapid',true),cache=new Net.ProjectileFlights();cache.observe([{id:7}]);cache.accept([event],0);
 cache.sample(12,0);const before=cache.visualTank(authority,authority,null,0,move);assert.equal(before.x,140);
 cache.sample(12,9);const first=cache.visualTank(authority,authority,null,9,move);assert.equal(first.x,140);assert.equal(first.shieldCharges,1);
 const later=cache.visualTank(authority,authority,null,49,move);assert.ok(later.x>140&&later.x<160);assert.equal(authority.x,160);
});

test('the retained Starman Shotgun burst cannot evict a contact before its endpoint frame',()=>{
 const cache=new Net.ProjectileFlights();cache.rememberTanks(Array.from({length:8},(_,id)=>({id,spawnSerial:1})),0);
 const records=Array.from({length:864},(_,i)=>{const f=fixture('scatter');f.event.id=i+1;f.event.flight.id=f.event.contact.projectileId=i+1;f.event.contact.target=i+32;return f.event;});
 cache.accept(records,0);assert.equal(cache.items.size,864);assert.equal(cache.contactCount,864);
 assert.equal(cache.sample(20,0).length,864);assert.equal(cache.sample(20,50).length,864);assert.equal(cache.contactCount,864,'contact frame holds every target before any damage cue');
 assert.equal(cache.sample(20,59).length,0);assert.equal(cache.contactCount,0);cache.sample(20,1060);assert.equal(cache.contacts.size,0,'released histories stop adding per-frame work');
});

test('known retired victims remain present through contact without resurrecting a changed life',()=>{
 const {event,authority}=fixture('cannon'),cache=new Net.ProjectileFlights();cache.rememberTanks([{...authority,alive:true,hp:1}],0);cache.accept([event],0);
 const missing=cache.missingTanks(new Map());assert.equal(missing.length,1);
 assert.equal(cache.visualTank(missing[0],missing[0],null,0,move).hp,1);
 assert.equal(cache.missingTanks(new Map([[3,{...authority,spawnSerial:5}]] )).length,0);
 cache.sample(12,0);cache.sample(12,50);cache.sample(12,59);assert.equal(cache.missingTanks(new Map()).length,0);
 cache.reset();assert.equal(cache.bodies.size,0);
});

test('the finite round cue waits until the exact contact and damage have been painted',()=>{
 const {event}=fixture('rapid'),cache=new Net.ProjectileFlights();cache.observe([{id:7}]);cache.accept([event],0);const sequence=[];
 cache.deferContact(1,()=>sequence.push('hit'));cache.deferScene(()=>sequence.push('round'));
 cache.sample(12,0);cache.flush();assert.deepEqual(sequence,[]);
 cache.sample(12,9);cache.flush();assert.deepEqual(sequence,['hit','round']);
});

test('a fast-forwarded same-tick reflected muzzle path uses its last contact point',()=>{
 const {event,flight,authority}=fixture('rapid'),cache=new Net.ProjectileFlights();
 flight.startTick=flight.endTick=12;flight.points=[{x:90,y:100,tick:12},{x:70,y:100,tick:12},{x:flight.points.at(-1).x,y:100,tick:12}];
 cache.accept([event],0);cache.expedite(7);
 const shell=cache.sample(12,0)[0],tank=cache.visualTank(authority,authority,null,0,move);
 assert.equal(shell.x,flight.points.at(-1).x);assert.ok(Math.abs(Math.hypot(shell.x-tank.x,shell.y-tank.y)-17-shell.r)<1e-7);
 cache.sample(12,9);assert.equal(cache.visualTank(authority,authority,null,9,move).hp,0);
});

test('coalesced shield and lethal hits each touch their moving victim before their own damage cue',()=>{
 const a=fixture('rapid',true),b=fixture('cannon'),cache=new Net.ProjectileFlights();
 b.event.id=2;b.contact.projectileId=b.flight.id=8;b.contact.tick=b.flight.startTick=b.flight.endTick=33;
 b.contact.before.x=180;b.flight.points=[{x:140,y:100,tick:33},{x:149,y:100,tick:33}];
 cache.accept([a.event,b.event],0);const sounds=[];cache.deferContact(1,()=>sounds.push('shield'));cache.deferContact(2,()=>sounds.push('death'));
 cache.sample(40,0);cache.sample(40,50);assert.equal(cache.visualTank(b.authority,b.authority,null,50,move).x,140);cache.flush();assert.deepEqual(sounds,[]);
 const shells=cache.sample(40,59),second=cache.visualTank(b.authority,b.authority,null,59,move);cache.flush();
 assert.equal(second.hp,1);assert.equal(second.x,180);assert.equal(shells.find(s=>s.id===8).x,149);assert.deepEqual(sounds,['shield']);
 cache.sample(40,68);const dead=cache.visualTank(b.authority,b.authority,null,68,move);cache.flush();assert.equal(dead.hp,0);assert.deepEqual(sounds,['shield','death']);
});
