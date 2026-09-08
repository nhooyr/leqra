'use strict';
// node --test tests/netcode.test.cjs (no npm packages required)
const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const Net=require('../web/netcode.js');
const game=fs.readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function wallMover(world){
 const context={walls:world.walls,W:world.width,H:world.height,WALL:8,CELL:84,cols:world.cols||Math.ceil(world.width/84),rows:world.rows||Math.ceil(world.height/84),clamp:Net.clamp,Math};
 vm.createContext(context);
 // Exercise the real collision functions shipped in game.js, not a test copy.
 vm.runInContext(game.slice(game.indexOf('let wallIndex=null;'),game.indexOf('function rayWalls(')),context);
 vm.runInContext(game.slice(game.indexOf('function rayBounds('),game.indexOf('function burst(')),context);
 return context.moveTank;
}
const free=(t,dx,dy)=>{t.x+=dx;t.y+=dy;};
const input=changes=>({...Net.neutral(),...changes});
const tank=changes=>({id:0,x:200,y:200,angle:0,r:17,vx:0,vy:0,alive:true,track:0,ack:0,ackSteps:0,...changes});
function snapshot(tick,x,extra={}){
 const t=tank({id:1,x,y:200,vx:128,track:x,...extra});
 return{tick,tanks:[t],tankMap:new Map([[1,t]]),bullets:[],bulletMap:new Map()};
}
function close(a,b,eps=1e-7){assert.ok(Math.abs(a-b)<eps,`${a} != ${b}`);}
test('60 Hz movement follows authoritative forward/reverse/turn rates',()=>{
 const t=tank();Net.move(t,input({forward:true}),1,free);close(t.x,328);
 Net.move(t,input({reverse:true}),1,free);close(t.x,328-128*.72);
 Net.move(t,input({right:true}),Net.STEP,free);close(t.angle,3.65/60);
});
test('stick movement and angle wrapping stay finite and bounded',()=>{
 const t=tank({angle:3.13}),start={...t};Net.move(t,input({stickX:2,stickY:-2}),Net.STEP,free);
 assert.ok(Math.hypot(t.x-start.x,t.y-start.y)<=128/60+1e-6);
 assert.ok(Math.abs(Net.delta(start.angle,t.angle))<=5.8/60+1e-6);
 assert.ok(Math.abs(t.angle)<=Math.PI);
});
test('real client wall collision never crosses a solid wall',()=>{
 const move=wallMover({width:600,height:500,walls:[{x:300,y:0,w:8,h:500}]});
 const t=tank();for(let i=0;i<240;i++)Net.move(t,input({forward:true}),Net.STEP,move);
 assert.ok(t.x<=283.01);assert.ok(t.x>=282.9);
});
test('prediction responds before receiving any authoritative acknowledgement',()=>{
 const p=new Net.Predictor(free);p.reset(tank());
 p.advance(Net.STEP,input({forward:true}));assert.ok(p.state.x>200);
});
test('held-input ackSteps replays exactly once including turns and releases',()=>{
 const p=new Net.Predictor(free);p.reset(tank());
 const authorities=[],server=tank();let seq=0,held=0;
 for(let k=1;k<=120;k++){
  const keys=input({forward:k<100,right:k>=20&&k<45,left:k>70&&k<85,reverse:k>=100});
  p.advance(Net.STEP,keys,()=>{if(k%2===1){seq++;held=0;p.sentInput(seq);}});
  Net.move(server,keys,Net.STEP,free);server.ack=seq;server.ackSteps=++held;
  authorities.push({...server});
  if(k>20&&k%3===0){
   p.reconcile(authorities[k-19]);
   close(p.state.x,server.x);close(p.state.y,server.y);close(Net.delta(p.state.angle,server.angle),0);
  }
 }
 assert.ok(p.metrics.replayed>0);assert.equal(p.metrics.hardResets,0);
});
test('two server ticks for one held command do not double-predict the second tick',()=>{
 const p=new Net.Predictor(free);p.reset(tank());
 p.advance(Net.STEP,input({forward:true}),()=>p.sentInput(1));
 p.advance(Net.STEP,input({forward:true}));
 const expected=p.state.x;p.reconcile(tank({x:expected,ack:1,ackSteps:2}));
 close(p.state.x,expected);assert.equal(p.metrics.replayed,0);
});
test('server corrections are visual offsets, not forces applied to simulation',()=>{
 const p=new Net.Predictor(free);p.reset(tank());
 p.advance(Net.STEP,input({forward:true}),()=>p.sentInput(1));
 const before=p.state.x;p.reconcile(tank({x:before-5,ack:1,ackSteps:1}));
 close(p.state.x,before-5);close(p.visual(1/60).x,before);
 for(let k=0;k<120;k++)p.visual(1/60);
 close(p.state.x,before-5);close(p.visual(1/60).x,before-5,.001);
});
test('sub-tick rendering supports refresh rates above 60 Hz',()=>{
 const p=new Net.Predictor(free);p.reset(tank());
 p.advance(1/120,input({forward:true}));
 close(p.state.x,200);close(p.visual(1/120).x,200+128/120);
 p.advance(1/120,input({forward:true}));close(p.visual(1/120).x,200+128/60);
});
test('death and generation reset discard prediction history and render offsets',()=>{
 const p=new Net.Predictor(free);p.reset(tank());
 p.advance(Net.STEP,input({right:true}),()=>p.sentInput(3));
 p.reconcile(tank({alive:false,x:80}));assert.equal(p.state.x,80);assert.equal(p.frames.length,0);
 p.reset(tank({x:400}));assert.equal(p.sent.size,0);assert.equal(p.state.x,400);
});
test('prediction history is bounded through stalled connections',()=>{
 const p=new Net.Predictor(free);p.reset(tank());
 for(let n=1;n<=800;n++)p.advance(Net.STEP,input({forward:true}),()=>p.sentInput(n));
 assert.ok(p.frames.length<=240);assert.ok(p.sent.size<=256);
 p.reconcile(tank({ack:0}));assert.ok(Number.isFinite(p.state.x));assert.equal(p.metrics.replayed,0);
});
test('snapshot buffer rejects duplicates and stale ticks',()=>{
 const b=new Net.SnapshotBuffer();assert.ok(b.push(snapshot(4,104),50));
 assert.equal(b.push(snapshot(4,104),60),false);assert.equal(b.push(snapshot(3,103),70),false);
 assert.equal(b.items.length,1);
});
test('jittered delivery never restarts or reverses remote playback',()=>{
 const b=new Net.SnapshotBuffer(),messages=[];let arrival=-1,last=0;
 for(let tick=0;tick<600;tick+=2){
  arrival=Math.max(arrival+.1,tick*1000/60+60+[0,20,3,42,10,1,38][(tick/2)%7]);
  messages.push({at:arrival,s:snapshot(tick,200+128*tick/60)});
 }
 let index=0,lastX=null,frames=0;
 for(let now=0;now<9700;now+=1000/120){
  while(index<messages.length&&messages[index].at<=now){b.push(messages[index].s,now);index++;}
  const f=b.advance(1/120);if(!f)continue;
  assert.ok(f.time>=last-1e-7||frames===0);last=f.time;
  const t=b.tank(1,f,free);
  if(lastX!==null)assert.ok(t.x>=lastX-1e-6,'remote tank moved backward');
  lastX=t.x;frames++;
 }
 assert.ok(frames>900);assert.ok(b.delay>=70&&b.delay<=180);assert.ok(b.items.length<=90);
});
test('interpolation uses the short path across the angle wrap boundary',()=>{
 const b=new Net.SnapshotBuffer();b.push(snapshot(2,210,{angle:3.12}),0);b.push(snapshot(4,220,{angle:-3.12}),33);
 b.time=50;const f=b.advance(0),t=b.tank(1,f,free);
 assert.ok(Math.abs(t.angle)>3.1);
});
test('remote extrapolation is capped and cannot tunnel through a wall',()=>{
 const b=new Net.SnapshotBuffer();b.push(snapshot(4,278),0);
 const move=wallMover({width:600,height:500,walls:[{x:300,y:0,w:8,h:500}]});
 let f;for(let i=0;i<80;i++)f=b.advance(1/60);
 assert.ok(f.extrapolate<=.0750001);
 assert.ok(b.tank(1,f,move).x<=283.01);assert.equal(b.underruns,1);
});
test('latest death is authoritative even with an older render buffer',()=>{
 const b=new Net.SnapshotBuffer();b.push(snapshot(2,220),0);b.push(snapshot(4,220,{alive:false}),33);
 const t=b.tank(1,b.advance(1/60),free);assert.equal(t.alive,false);
});
test('real client motion matches stored cross-language Go fixtures',()=>{
 const fixtures=JSON.parse(fs.readFileSync(path.join(__dirname,'movement-fixtures.json'),'utf8'));
 for(const f of fixtures){const t={...f.initial},move=wallMover(f.world);
  for(const segment of f.segments)for(let n=0;n<segment.steps;n++)Net.move(t,segment.input,Net.STEP,move);
  close(t.x,f.expected.x);close(t.y,f.expected.y);close(Net.delta(t.angle,f.expected.angle),0);
 }
});
test('speed boost matches keyboard, touch and reverse rates',()=>{
 for(const keys of [input({forward:true}),input({stickX:1}),input({reverse:true})]){
  const t=tank({speedTime:6});for(let n=0;n<30;n++)Net.move(t,keys,Net.STEP,free);
  close(t.x-200,128*1.65*.5*(keys.reverse?-.72:1));close(t.speedTime,5.5);
 }
});
test('boost steering is faster but bounded',()=>{
 const t=tank({speedTime:6});Net.move(t,input({right:true}),Net.STEP,free);close(t.angle,3.65*1.25/60);
 const u=tank({speedTime:6});Net.move(u,input({stickY:1}),Net.STEP,free);close(u.angle,5.8*1.25/60);
});
test('boost expiry uses the same pre-movement tick as Go',()=>{
 const t=tank({speedTime:.025});Net.move(t,input({forward:true}),Net.STEP,free);Net.move(t,input({forward:true}),Net.STEP,free);
 close(t.x-200,128*Net.STEP*(1.65+1));close(t.speedTime,0);
});
test('input replay crosses boost expiration without double speed or time',()=>{
 const p=new Net.Predictor(free),server=tank({speedTime:.625}),history=[];p.reset(server);let seq=0,held=0;
 for(let k=1;k<=120;k++){
  const keys=input({forward:true,right:k>45&&k<60});
  p.advance(Net.STEP,keys,()=>{if(k%2===1){seq++;held=0;p.sentInput(seq);}});
  Net.move(server,keys,Net.STEP,free);server.ack=seq;server.ackSteps=++held;history.push({...server});
  if(k>24&&k%3===0){p.reconcile(history[k-20]);close(p.state.x,server.x);close(p.state.y,server.y);close(p.state.speedTime,server.speedTime);}
 }
 assert.equal(p.metrics.hardResets,0);
});
test('boost sub-tick visuals do not consume simulation timer',()=>{
 const p=new Net.Predictor(free);p.reset(tank({speedTime:6}));p.advance(1/120,input({forward:true}));const before=p.state.speedTime;
 const visual=p.visual(1/120);close(visual.x-200,128*1.65/120);close(p.state.speedTime,before);
});
test('boosted wall contact cannot tunnel',()=>{
 const move=wallMover({width:600,height:500,walls:[{x:300,y:0,w:8,h:500}]}),t=tank({speedTime:6});
 for(let n=0;n<300;n++)Net.move(t,input({forward:true}),Net.STEP,move);
 assert.ok(t.x<=283.01&&t.x>=282.9);
});
test('five speed stacks scale movement and turning without tunneling',()=>{
 const t=tank({speedTime:6,speedStacks:5});Net.move(t,input({forward:true,right:true}),Net.STEP,free);
 close(t.x-200,Math.cos(3.65*2.25/60)*128*4.25/60);close(t.angle,3.65*2.25/60);
 const move=wallMover({width:600,height:500,walls:[{x:300,y:0,w:8,h:500}]}),u=tank({speedTime:6,speedStacks:5});
 for(let n=0;n<180;n++)Net.move(u,input({forward:true}),Net.STEP,move);
 assert.ok(u.x<=283.01&&u.x>=282.9,`max-stack tunnel ${u.x}`);
});
test('remote objective respawn never blends between different life epochs',()=>{
 const b=new Net.SnapshotBuffer();b.push(snapshot(2,220,{spawnSerial:1}),0);b.push(snapshot(4,240,{spawnSerial:2}),33);
 const t=b.tank(1,b.advance(0),free);assert.equal(t.x,240);assert.equal(t.spawnSerial,2);
});
test('newest respawn cannot render the previous life from an older buffer pair',()=>{
 const b=new Net.SnapshotBuffer();b.push(snapshot(2,220,{spawnSerial:1}),0);b.push(snapshot(4,230,{spawnSerial:1}),33);b.push(snapshot(6,250,{spawnSerial:2}),66);
 b.time=40;const t=b.tank(1,b.advance(0),free);assert.equal(t.x,250);assert.equal(t.spawnSerial,2);
});

test('Ghost movement matches Go fixtures across walls, speed stacking and expiry',()=>{
 const cases=JSON.parse(fs.readFileSync(path.join(__dirname,'fixtures/phase41.json'),'utf8'));
 for(const c of cases){const move=wallMover(c.world),t={...c.initial};
  c.inputs.forEach((keys,i)=>{Net.move(t,keys,Net.STEP,move);for(const key of ['x','y','angle','speedTime','ghostTime'])close(t[key],c.states[i][key],1e-7);});
 }
});
test('Ghost expiry solidifies only once, including high refresh subtick rendering',()=>{
 const w={width:1008,height:840,cols:12,rows:10,walls:[{x:248,y:0,w:8,h:840}]},move=wallMover(w);
 const p=new Net.Predictor(move);p.reset(tank({x:252,ghostTime:.005,speedTime:6}));p.advance(1/120,input({forward:true}));
 const v=p.visual(1/120);assert.equal(v.ghostTime,0);assert.ok(v.x<232);assert.equal(p.state.ghostTime,.005);
 p.advance(1/120,input({forward:true}));assert.equal(p.state.ghostTime,0);assert.ok(p.state.x<232);
});
test('Remote Ghost inside a wall is not pushed out by interpolation',()=>{
 const b=new Net.SnapshotBuffer(),move=wallMover({width:1008,height:840,cols:12,rows:10,walls:[{x:248,y:0,w:8,h:840}]});
 b.push(snapshot(2,249,{ghostTime:10}),0);b.push(snapshot(4,253,{ghostTime:9.966}),33);
 b.time=50;const frame=b.advance(0),t=b.tank(1,frame,move);assert.ok(t.x>=249&&t.x<=253);assert.ok(t.ghostTime>0);
});
test('Remote Ghost expiry never blends solid and phasing wall positions',()=>{
 const b=new Net.SnapshotBuffer(),move=wallMover({width:1008,height:840,cols:12,rows:10,walls:[{x:248,y:0,w:8,h:840}]});
 b.push(snapshot(2,252,{ghostTime:.02}),0);b.push(snapshot(4,230.99,{ghostTime:0}),33);
 b.time=50;const frame=b.advance(0),t=b.tank(1,frame,move);close(t.x,230.99);assert.equal(t.ghostTime,0);
});
test('Independent predictors replay Ghost and Super Speed with delayed corrections',()=>{
 const c=JSON.parse(fs.readFileSync(path.join(__dirname,'fixtures/phase41.json'),'utf8'))[0];
 for(const duration of [.45,10]){const move=wallMover(c.world),p=new Net.Predictor(move),server=tank({x:210,y:210,ghostTime:duration,speedTime:.7}),history=[];
 p.reset(server);let seq=0,held=0;
 for(let k=1;k<=120;k++){const keys=input({forward:k<100,right:k>30&&k<45});
  p.advance(Net.STEP,keys,()=>{if(k%2){seq++;held=0;p.sentInput(seq);}});Net.move(server,keys,Net.STEP,move);server.ack=seq;server.ackSteps=++held;history.push({...server});
  if(k>20&&k%3===0){p.reconcile(history[k-19]);close(p.state.x,server.x);close(p.state.y,server.y);close(p.state.ghostTime,server.ghostTime);close(p.state.speedTime,server.speedTime);}
 }
 }
});
test('Ghost reconciliation never carries a sideways visual correction through walls',()=>{
 const move=wallMover({width:1008,height:840,cols:12,rows:10,walls:[{x:248,y:0,w:8,h:840}]});
 const p=new Net.Predictor(move);p.reset(tank({x:270,y:210,ghostTime:5}));
 p.offset={x:18,y:-11,angle:.2};
 p.reconcile(tank({x:260,y:210,ghostTime:4.9,ack:0,ackSteps:0}));
 assert.equal(p.offset.x,0);assert.equal(p.offset.y,0);assert.equal(p.offset.angle,0);
});
