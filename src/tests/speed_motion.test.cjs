'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),{assetPath}=require('./web_assets.cjs');
const Net=require(assetPath('netcode.js'));
const free=(t,x,y)=>{t.x+=x;t.y+=y;};
const input=changes=>({...Net.neutral(),...changes});
const tank=changes=>({id:0,x:500,y:500,angle:0,r:17,alive:true,hp:1,spawnSerial:1,track:0,speedTime:1000,speedStacks:5,ghostTime:0,...changes});
function declaration(source,name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
const game=readFileSync(assetPath('game.js'),'utf8'),infinity=readFileSync(assetPath('infinite.js'),'utf8');

test('max-Speed turning has continuous presentation velocity across 720 simulation boundaries',()=>{
 const controls=input({forward:true,right:true}),step=Net.STEP,epsilon=step/100000;
 let state=tank(),previous=null,oldSquared=0,newSquared=0;
 const partial=(t,span)=>{const copy={...t};Net.move(copy,controls,span,free);return copy;};
 for(let tick=0;tick<720;tick++){
  const next={...state};Net.move(next,controls,step,free);
  for(const [sample,key] of [[partial,'old'],[(t,span,prior)=>Net.visualMove(t,controls,span,free,step,prior),'new']]){
   const before=sample(state,step-epsilon,previous),after=sample(next,epsilon,state);
   const jump=Math.hypot((next.x-before.x-after.x+next.x)/epsilon,(next.y-before.y-after.y+next.y)/epsilon);
   if(key==='old')oldSquared+=jump*jump;else newSquared+=jump*jump;
  }
  previous=state;state=next;
 }
 assert.ok(Math.sqrt(oldSquared/720)>70,'fixture must reproduce the original tick-boundary reset');
 assert.ok(Math.sqrt(newSquared/720)<.05,'the displayed velocity must cross tick boundaries continuously');
});

test('whole display-frame motion stays smooth at 90 Hz, ProMotion, 144 Hz and mixed cadence',()=>{
 const measure=(kind,cadence)=>{
  const presenter=new Net.MotionPresenter(),state=tank(),samples=[];let time=0,remaining=0,tick=0,frame=0;
  while(time<8){
   const dt=Array.isArray(cadence)?cadence[frame++%cadence.length]:1/cadence;time+=dt;
   const controls=kind==='keyboard'?input({forward:true,right:true}):input({stickX:Math.cos(time*7+.8),stickY:Math.sin(time*7+.8),touchAim:true});
   remaining+=dt;while(remaining+1e-9>=Net.STEP){Net.move(state,controls,Net.STEP,free);remaining=Math.max(0,remaining-Net.STEP);tick++;}
   const pose=presenter.render(state,controls,remaining,tick,free);samples.push({x:pose.x,y:pose.y,time});
  }
  let values=samples;
  for(let derivative=0;derivative<3;derivative++)values=values.slice(1).map((b,i)=>{
   const a=values[i],dt=b.time-a.time;return{x:(b.x-a.x)/dt,y:(b.y-a.y)/dt,time:(a.time+b.time)/2};
  });
  const jerks=values.filter(value=>value.time>3).map(value=>Math.hypot(value.x,value.y)).sort((a,b)=>a-b);
  return jerks[Math.floor((jerks.length-1)*.95)];
 };
 const mixed=[1/120,1/144,1/95,1/160];
 for(const cadence of [90,119.9892,120,144,mixed]){
  assert.ok(measure('keyboard',cadence)<100000,'within-tick curvature must not create a high-refresh acceleration ripple');
  assert.ok(measure('touch',cadence)<(Array.isArray(cadence)?500000:200000),'rapid analog turning must retain the bounded transition smoothing');
 }
});

test('perpendicular throttle and Speed expiry cannot create a backwards Hermite excursion',()=>{
 const sideways=input({stickY:1,touchAim:true}),still=tank();
 for(let i=0;i<=32;i++){
  const pose=Net.visualMove(still,sideways,Net.STEP*i/32,free);
  assert.ok(Math.hypot(pose.x-still.x,pose.y-still.y)<1e-8);
 }
 const expiring=tank({speedTime:.01}),forward=input({forward:true});let previous=expiring.x;
 for(let i=0;i<=32;i++){
  const pose=Net.visualMove(expiring,forward,Net.STEP*i/32,free);
  assert.ok(pose.x>=previous-1e-8);assert.ok(pose.x<=expiring.x+128*Net.STEP+1e-8);previous=pose.x;
 }
 assert.equal(expiring.speedTime,.01,'presentation must not expire the simulation equipment');
});

test('a release between ticks spreads its preview correction over a short bounded interval',()=>{
 const p=new Net.Predictor(free);p.reset(tank({x:0}));
 p.advance(1/120,input({forward:true}));const lead=p.visual(1/120);
 p.advance(1/120,input());let previous=p.visual(1/120),largestBackstep=0;
 assert.ok(previous.x>=lead.x,'release must not instantly jump back from its displayed preview');
 for(let i=0;i<100;i++){
  p.advance(1/120,input());const pose=p.visual(1/120);
  largestBackstep=Math.max(largestBackstep,previous.x-pose.x);previous=pose;
  assert.ok(Math.hypot(p.presenter.offset.x,p.presenter.offset.y)<=544/60+1e-8);
 }
 assert.ok(largestBackstep<2,'the original abrupt release rewound 4.53 world pixels in one display frame');
 assert.ok(Math.abs(previous.x)<1e-6);assert.equal(p.state.x,0,'cosmetic correction cannot move authority');
});

test('frequent analog changes at mixed refresh rates keep correction bounded and reset on a new life',()=>{
 const p=new Net.Predictor(free);p.reset(tank());let clock=0;
 for(let i=0;i<1200;i++){
  const dt=[1/120,1/144,1/95,1/160][i%4];clock+=dt;
  const controls=input({stickX:Math.cos(clock*14),stickY:Math.sin(clock*14),touchAim:true});
  p.advance(dt,controls);const authority={...p.state},pose=p.visual(dt);
  assert.ok(Number.isFinite(pose.x)&&Number.isFinite(pose.angle));
  assert.ok(Math.hypot(p.presenter.offset.x,p.presenter.offset.y)<=544/60+1e-8);
  assert.ok(Math.abs(p.presenter.offset.angle)<=.3375+1e-8);
  assert.deepEqual(p.state,authority);
 }
 p.state.spawnSerial++;p.visual(0);assert.deepEqual(p.presenter.offset,{x:0,y:0,angle:0});
});

test('curved and input-corrected visual paths remain outside actual fixed-maze walls',()=>{
 const {boot,declaration:fixedDeclaration}=require('./godlike426-harness.cjs');
 const world=boot({cols:12,rows:8,wallList:[{x:300,y:0,w:8,h:672},{x:0,y:400,w:1008,h:8}]});
 vm.runInContext(fixedDeclaration('clearTankAt'),world);
 let state=tank({x:280,y:350,angle:0});
 for(let tick=0;tick<180;tick++){
  const controls=input({forward:true,right:tick%40<20,left:tick%40>=20});
  for(let i=0;i<16;i++){
   const pose=Net.visualMove(state,controls,Net.STEP*i/16,world.moveTank);
   assert.ok(world.clearTankAt(pose.x,pose.y,17),JSON.stringify(pose));
  }
  Net.move(state,controls,Net.STEP,world.moveTank);
 }
});

test('Ghost plus max Speed cannot bow outside any fixed-map edge while sliding',()=>{
 const {boot}=require('./godlike426-harness.cjs'),world=boot({cols:12,rows:8});
 const controls=input({forward:true}),width=12*84,height=8*84;
 for(const [x,y,angle] of [[24,300,3*Math.PI/4],[width-24,300,Math.PI/4],[500,24,-Math.PI/4],[500,height-24,Math.PI/4]]){
  const presenter=new Net.MotionPresenter(),state=tank({x,y,angle,ghostTime:10});
  presenter.render(state,controls,0,0,world.moveTank);
  for(let tick=1;tick<=12;tick++){
   Net.move(state,controls,Net.STEP,world.moveTank);
   const authority={...state};
   for(let frame=0;frame<32;frame++){
    const pose=presenter.render(state,controls,Net.STEP*frame/32,tick,world.moveTank);
    assert.ok(pose.x>=21-1e-9&&pose.x<=width-21+1e-9,JSON.stringify(pose));
    assert.ok(pose.y>=21-1e-9&&pose.y<=height-21+1e-9,JSON.stringify(pose));
    assert.deepEqual(state,authority);
   }
  }
 }
});

test('fixed rendering projects fractional tank and projectile poses and restores simulation state',()=>{
 const controls=input({forward:true,right:true}),state=tank({human:true,localIndex:0});let draws=0;
 const s={Net,Math,tanks:[state],bullets:[{x:0,y:0}],mode:'room',phase:'playing',localTick:0,accumulator:1/240,
  stick:{x:0,y:0,mag:0,assisted:false},BOOST_SPEED_PER_STACK:.65,BOOST_TURN_PER_STACK:.25,
  speedCount:t=>t.speedTime>0?t.speedStacks||1:0,heldAction:(_,key)=>controls[key],mouseAimHeading:()=>null,
  angleDelta:Net.delta,moveTank:free,advanceGhost(t,dt){t.ghostTime=Math.max(0,t.ghostTime-dt);},survivalBreak:()=>false,
  projectOnlineBullet:b=>({...b,x:1}),weaponControl(){throw Error('rendering fired a weapon');},
  renderArena(){draws++;assert.ok(s.tanks[0].x>state.x);assert.equal(s.bullets[0].x,1);}};
 vm.createContext(s);for(const name of ['humanControl','localMovementInput','advanceLocalRenderTank','localTankPose','render'])vm.runInContext(declaration(game,name),s);
 const before=JSON.stringify(state),actualTanks=s.tanks,actualBullets=s.bullets;s.render();
 assert.equal(draws,1);assert.equal(s.tanks,actualTanks);assert.equal(s.bullets,actualBullets);assert.equal(JSON.stringify(state),before);
 s.renderArena=()=>{throw Error('draw failure');};assert.throws(()=>s.render(),/draw failure/);assert.equal(s.tanks,actualTanks);
});

test('offline Infinity draws each sub-tick tank pose and follows the same fractional camera',()=>{
 const state=tank(),controls=input({forward:true,right:true}),world={id:0,tanks:[state],controllers:[],camera:{x:0,y:0},time:0,
  maze:{},arrived:0,interval:1000/30,visualEffects:[],online:false};world.controllers=[world];world.moveTank=free;
 const noop=()=>{},s={net:Net,Math,Map,canvas:{clientWidth:390,clientHeight:844,width:390,height:844},
  art:{renderPixelRatio:()=>1,theme:{arena:'#000'}},ctx:new Proxy({},{get:()=>noop}),pauseMenu:{open:false},arena:{dataset:{}},
  accumulator:1/120,STEP:Net.STEP,clamp:Net.clamp,inputState:()=>controls,primaryView:(w,h)=>[w,h],drawView:noop,updateHUD:noop};
 vm.createContext(s);for(const name of ['offlineTankPose','draw'])vm.runInContext(declaration(infinity,name),s);
 const before=JSON.stringify(state);s.draw(world,1000,1/120);
 assert.ok(world.display.x>state.x);assert.equal(world.camera.x,world.display.x);assert.equal(world.camera.y,world.display.y);
 assert.equal(JSON.stringify(state),before);const first=world.camera.x;s.draw(world,1000,0);assert.equal(world.camera.x,first);
});

test('remote turning carries continuous velocity between neighboring snapshot pairs',()=>{
 const buffer=new Net.SnapshotBuffer(),radius=544/8.2125,omega=8.2125;
 for(let tick=0;tick<30;tick+=2){
  const time=tick/60,t=tank({id:1,x:500+Math.cos(time*omega)*radius,y:500+Math.sin(time*omega)*radius,angle:time*omega});
  buffer.push({tick,tanks:[t],tankMap:new Map([[1,t]])},tick*1000/60);
 }
 const epsilon=1e-5,span=2/60;
 for(let i=2;i<buffer.items.length-3;i++){
  const a=buffer.items[i],b=buffer.items[i+1],c=buffer.items[i+2];
  const left=buffer.tank(1,{a,b,alpha:1-epsilon,extrapolate:0},free);
  const end=buffer.tank(1,{a,b,alpha:1,extrapolate:0},free);
  const right=buffer.tank(1,{a:b,b:c,alpha:epsilon,extrapolate:0},free);
  const jump=Math.hypot((end.x-left.x-right.x+end.x)/(span*epsilon),(end.y-left.y-right.y+end.y)/(span*epsilon));
  assert.ok(jump<.1,'remote snapshot velocity reset: '+jump);
 }
});

test('Infinity timestamp smoothing preserves its one-snapshot steady-state delay',()=>{
 const buffer=new Net.SnapshotBuffer({delay:1000/30,minimumDelay:1000/30,maximumDelay:90,intervals:1});
 for(let tick=0;tick<60;tick+=2){
  const t=tank({id:1});buffer.push({tick,tanks:[t],tankMap:new Map([[1,t]])},tick*1000/60);
 }
 assert.ok(Math.abs(buffer.delay-1000/30)<1e-8);
 buffer.reset();assert.equal(buffer.delay,1000/30);
});
