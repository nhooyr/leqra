'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function recorder(){
 let matrix={x:0,y:0,angle:0},stack=[],shape,clipped=false;
 const events=[],c={events,canvas:{},save(){stack.push({matrix:{...matrix},clipped});},restore(){({matrix,clipped}=stack.pop());},clip(){clipped=true;},translate(x,y){matrix.x+=Math.cos(matrix.angle)*x-Math.sin(matrix.angle)*y;matrix.y+=Math.sin(matrix.angle)*x+Math.cos(matrix.angle)*y;},rotate(a){matrix.angle+=a;},beginPath(){shape=null;},rect(x,y,w,h){shape={x,y,w,h};},arc(x,y,r,start,end){shape={arc:true,x,y,r,start,end};},stroke(){if(shape?.arc)events.push({type:'arc',...shape,color:this.strokeStyle,alpha:this.globalAlpha,width:this.lineWidth,matrix:{...matrix}});},fill(){if(shape&&!shape.arc)events.push({type:'rect',...shape,matrix:{...matrix}});},fillText(text,x,y){events.push({type:'text',text,x,y,font:this.font,clipped,matrix:{...matrix}});},drawImage(image,x,y,w,h){events.push({type:'image',image,x,y,w,h,matrix:{...matrix}});},measureText(text){return{width:text.length*6};}};
 return new Proxy(c,{get:(t,k)=>k in t?t[k]:(()=>{})});
}
function boot(){
 const ctx=recorder(),made=[];
 const s={ctx,mode:'room',phase:'playing',pausedFrom:'playing',isSpectating:()=>false,survivalBreak:()=>false,scale:1,W:2400,H:1500,TAU:Math.PI*2,MAX_SPEED_STACKS:5,reduceMotion:true,fxTime:0,theme:{protection:'#fff'},localPlayerID:()=>0,secondaryID:()=>1,paintColor:c=>c,clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),tankPowerBadgeCache:new Map(),tankPowerBadgeScratch:[],labelWidthCache:new Map(),drawCachedTankHull(){},roundRect:(c,...args)=>{c.beginPath();c.rect(...args);},powerIcon:(kind,c)=>c.canvas.kind=kind,document:{createElement:()=>{const c=recorder(),canvas=c.canvas;canvas.getContext=()=>c;made.push(canvas);return canvas;}}};
 vm.createContext(s);vm.runInContext(source.slice(source.indexOf('const POWER='),source.indexOf('\nconst LASER_MAX_SEGMENTS=')),s);
 vm.runInContext(source.slice(source.indexOf('const tankPowerBadgeCache='),source.indexOf('function activeTankPowerBadges(')),s);
 for(const name of ['shieldCount','speedCount','measureLabel','activeTankPowerBadges','tankPowerBadgeImage','tankStatusLayout','tankPowerBadgePositions','drawTankPowerBadges','protectionRingAlpha','localSpawnGuideAlpha','drawLocalSpawnGuide','drawTankLabel','drawTank'])vm.runInContext(declaration(name),s);
 return {s,ctx,made};
}
function tank(patch={}){return{id:3,name:'GODLIKE BOSS',human:false,alive:true,invulnerable:.75,spawnProtected:true,x:1200,y:700,angle:0,recoil:0,track:0,color:'#73cee4',power:'laser',powerTime:15,shield:10,shieldCharges:5,speedTime:10,speedStacks:2,scopeTime:10,ghostTime:10,...patch};}
function pictures(ctx){return ctx.events.filter(e=>e.type==='image');}

function badgeOverlap(a,b){return Math.hypot(a.x+a.w/2-b.x-b.w/2,a.y+a.h/2-b.y-b.h/2)<(a.w+b.w)*28.5/64-1e-8;}
function labelRect(ctx){return ctx.events.findLast(e=>e.type==='rect');}
function nameGeometry(ctx){const text=ctx.events.find(e=>e.type==='text'),label=labelRect(ctx);return{x:text.x,y:text.y,font:text.font,background:{x:label.x,y:label.y,w:label.w,h:label.h}};}

test('bot and remote power icons proceed clockwise below stable names without covering the hull at desktop and mobile scales',()=>{
 for(const mode of ['room','online'])for(const scale of [2,1,.5,.2,.08])for(const charges of [0,1,5]){
  const {s,ctx}=boot();s.mode=mode;s.scale=scale;
  const t=tank({shield:charges?10:0,shieldCharges:charges,angle:1.35,human:mode==='online'});s.drawTank(t);
  const text=ctx.events.find(e=>e.type==='text'),label=labelRect(ctx),icons=pictures(ctx);
  assert.equal(text.text,'GODLIKE BOSS');assert.equal(icons.length,charges?5:4);
  const textDescent=parseFloat(text.font.replace('bold ',''))*.25;
  for(const icon of icons){
   assert.ok(icon.y+icon.w*(.5-28.5/64)>=label.y+label.h,'name background stays above the lower icon arc');
   assert.ok(icon.y+icon.w*(.5-28.5/64)>text.y+textDescent,'scaled name descenders must stay above icons');
   assert.ok(Math.hypot(icon.x+icon.w/2-t.x,icon.y+icon.h/2-t.y)-icon.w*28.5/64>=30-1e-8,'visible badge circles stay outside the hull');
   assert.deepEqual(icon.matrix,{x:0,y:0,angle:0},'icons remain aligned with the world after the tank rotates');
   assert.ok(icon.w>=24&&icon.h>=24,'retain readable icon size');
   assert.ok(icon.w*scale>=Math.min(24*scale,17.28)-1e-8);
  }
  for(let i=0;i<icons.length;i++)for(let j=0;j<i;j++)assert.ok(!badgeOverlap(icons[i],icons[j]),'adjacent icons do not overlap');
  assert.ok(icons[0].x>t.x,'first badge starts right of the tank below its name');
  assert.ok(icons[1].x<icons[0].x&&icons[1].y>icons[0].y);
  assert.ok(Math.abs(icons[2].x+icons[2].w/2-t.x)<1e-8,'third badge is below the tank');
  assert.ok(icons[2].y>icons[1].y&&icons[3].y<icons[2].y&&icons[3].x<icons[2].x);
  if(icons.length===5){assert.ok(icons[4].x<icons[3].x);assert.equal(icons[4].y,icons[0].y);}
 }
});
test('name position and dimensions never change as weapons, shields and other effects are acquired or lost',()=>{
 for(const mode of ['room','online'])for(const scale of [1,.25,.08])for(const [x,y] of [[1200,700],[42,42],[2358,1458]]){
  const {s,ctx}=boot();s.mode=mode;s.scale=scale;
  const t=tank({x,y,powerTime:0,shield:0,shieldCharges:0,speedTime:0,scopeTime:0,ghostTime:0});
  s.drawTank(t);const before=nameGeometry(ctx);
  for(const patch of [{powerTime:15},{shield:10,shieldCharges:1},{shieldCharges:5},{speedTime:10},{scopeTime:10},{ghostTime:10},{powerTime:0,shield:0,speedTime:0,scopeTime:0,ghostTime:0}]){
   Object.assign(t,patch);ctx.events.length=0;s.drawTank(t);assert.deepEqual(nameGeometry(ctx),before);
  }
 }
});
test('local pilots retain HUD-only power status while bots, remote pilots and spectated tanks receive badges',()=>{
 for(const mode of ['room','online'])for(const id of [0,1,3])for(const human of [false,true]){
  const {s,ctx}=boot();s.mode=mode;s.drawTank(tank({id,human}));
  const expected=mode==='online'?id!==0&&id!==1:!human;
  assert.equal(pictures(ctx).length,expected?5:0,`${mode} id=${id} human=${human}`);
 }
 const {s,ctx}=boot();s.mode='online';s.localPlayerID=()=>-1;s.secondaryID=()=>-1;s.drawTank(tank({id:0,human:true}));assert.equal(pictures(ctx).length,5);
});
test('badge orbits reuse cached icon sprites across movement and rotation, removing expired effects',()=>{
 const {s,ctx,made}=boot(),t=tank();s.drawTank(t);const first=pictures(ctx).map(e=>e.image);assert.equal(made.length,5);
 for(let i=0;i<20;i++){ctx.events.length=0;t.x+=1;t.y+=2;t.angle+=.1;s.drawTank(t);assert.deepEqual(pictures(ctx).map(e=>e.image),first);}
 assert.equal(made.length,5,'moving tanks do not rebuild icon sprites');
 ctx.events.length=0;Object.assign(t,{powerTime:0,shield:0,speedTime:0,scopeTime:0,ghostTime:0});s.drawTank(t);assert.equal(pictures(ctx).length,0);
 Object.assign(t,{alive:false,powerTime:10});ctx.events.length=0;s.drawTank(t);assert.equal(pictures(ctx).length,0);assert.equal(ctx.events.filter(e=>e.type==='text').length,0);
});

test('all five power icons stay inside the maze at its edges, keeping names fixed above without hiding the tank',()=>{
 for(const scale of [1,.25,.08])for(const x of [42,1200,2358])for(const y of [42,700,1458]){
  const {s,ctx}=boot();s.scale=scale;s.drawTank(tank({x,y}));
  const label=labelRect(ctx),icons=pictures(ctx);assert.equal(icons.length,5,`five visible badges at ${scale}: ${x}, ${y}`);
  assert.ok(label.x>=0&&label.x+label.w<=s.W,'name stays inside horizontal maze bounds');assert.equal(y-label.y-label.h,32,'name never flips below or follows the top edge');
  for(let i=0;i<icons.length;i++){
   const icon=icons[i],r=icon.w*28.5/64,cx=icon.x+icon.w/2,cy=icon.y+icon.h/2;assert.ok(cx-r>=0&&cx+r<=s.W&&cy-r>=0&&cy+r<=s.H,'visible badge stays in the maze');
   const labelDX=Math.max(label.x-cx,0,cx-label.x-label.w),labelDY=Math.max(label.y-cy,0,cy-label.y-label.h);assert.ok(labelDX*labelDX+labelDY*labelDY>=r*r,'badge remains clear of the name');
   assert.ok(Math.hypot(cx-x,cy-y)-r>=30-1e-8,'badge stays outside the hull');
   for(let j=0;j<i;j++)assert.ok(!badgeOverlap(icon,icons[j]),'badges remain separate');
  }
 }
});


test('tank names and badge centers stay close to the hull independent of shield count',()=>{
 for(const scale of [2,1,.5,.2,.08]){
  const {s,ctx}=boot();s.scale=scale;const t=tank();s.drawTank(t);
  const label=labelRect(ctx),icons=pictures(ctx),half=icons[0].w/2;
  assert.equal(t.y-label.y-label.h,32,'name has only two units of clearance above an upward muzzle');
  const oldZ=Math.max(1,.72/scale),oldHalf=12*oldZ,oldGap=2*oldZ;
  const oldRadius=Math.hypot(Math.max(31+oldHalf*Math.SQRT2+oldGap,Math.SQRT2*(2*oldHalf+oldGap)),Math.max(0,oldGap+oldHalf-32));
  const radius=Math.hypot(icons[0].x+half-t.x,icons[0].y+half-t.y);
  assert.ok(radius<=oldRadius,'readability must not increase the former orbit');
  if(scale>=.5)assert.ok(radius<=oldRadius-7,'normal and compact views bring icons at least seven units closer');
 }
});

test('gold and neon pink spawn circles identify their actual local pilots in every mode without highlighting bots, remote tanks or spectator seats',()=>{
 for(const mode of ['room','online','solo','duel'])for(const gameMode of ['elimination','deathmatch','ctf','koth','survival']){
  const {s,ctx}=boot();Object.assign(s,{mode,phase:'countdown',currentRules:()=>({mode:gameMode})});
  for(const [patch,expected] of [[{id:0,human:true},true],[{id:1,human:true},true],[{id:3,human:true},false],[{id:0,human:false},false],[{id:1,human:false},false],[{id:0,human:true,survivalEnemy:true},false],[{id:1,human:true,alive:false},false]]){
   ctx.events.length=0;s.drawTank(tank(patch));const guides=ctx.events.filter(e=>e.type==='arc'&&['#ffd76a','#ff4fd8'].includes(e.color));assert.equal(guides.length,expected?1:0,`${mode}/${gameMode}: ${JSON.stringify(patch)}`);
   if(expected){assert.equal(guides[0].r,34);assert.equal(guides[0].alpha,1);assert.equal(guides[0].color,patch.id===1?'#ff4fd8':'#ffd76a');}
  }
  s.isSpectating=()=>true;assert.equal(s.localSpawnGuideAlpha(tank({id:0,human:true})),0);
  s.secondaryID=()=>undefined;assert.equal(s.localSpawnGuideAlpha(tank({id:1,human:true})),0);
 }
});

test('online spawn guide colors follow local ownership when seat IDs change or the primary pilot spectates',()=>{
 const {s,ctx}=boot();Object.assign(s,{mode:'online',localPlayerID:()=>5,secondaryID:()=>3});
 const guide=id=>{ctx.events.length=0;s.drawTank(tank({id,human:true,shield:0}));return ctx.events.filter(e=>e.type==='arc'&&['#ffd76a','#ff4fd8'].includes(e.color));};
 assert.equal(guide(5)[0].color,'#ffd76a');assert.equal(guide(3)[0].color,'#ff4fd8');assert.equal(guide(1).length,0,'seat one is a remote pilot');
 s.isSpectating=()=>true;assert.equal(guide(5).length,0);assert.equal(guide(3)[0].color,'#ff4fd8','local P2 keeps pink while P1 spectates');
 s.secondaryID=()=>7;assert.equal(guide(3).length,0);assert.equal(guide(7)[0].color,'#ff4fd8','a reassigned local P2 gets the same color');
 s.secondaryID=()=>undefined;assert.equal(guide(7).length,0,'a removed local P2 cannot leave a locator on a remote body');
});

test('gold follows remaining spawn protection, freezing its fade through a paused countdown and long pauses',()=>{
 const {s}=boot(),t=tank({id:0,human:true});
 for(const phase of ['countdown','playing','paused']){s.phase=phase;for(const remaining of [.75,.35,.01,Number.EPSILON]){t.invulnerable=remaining;s.fxTime=1e8;assert.equal(s.localSpawnGuideAlpha(t),s.protectionRingAlpha(t));}}
 t.invulnerable=0;assert.equal(s.localSpawnGuideAlpha(t),0,'no cosmetic tail after protection expires');
 t.invulnerable=.35;t.spawnProtected=false;assert.equal(s.localSpawnGuideAlpha(t),0,'shield-hit grace does not restart the spawn ring');
 t.spawnProtected=true;for(const phase of ['menu','onlineLobby','roundOver','matchOver']){s.phase=phase;assert.equal(s.localSpawnGuideAlpha(t),0);}
 s.phase='playing';s.survivalBreak=()=>true;assert.equal(s.localSpawnGuideAlpha(t),0,'intermission is not a spawn');
});

test('online spawn tags follow authoritative life changes and never turn a shield save into a spawn',()=>{
 const {s}=boot();vm.runInContext(declaration('netTank'),s);
 let t=s.netTank(tank({id:0,bot:false,spawnSerial:0,invulnerable:.75}));assert.equal(s.localSpawnGuideAlpha(t),1);
 t=s.netTank({...t,invulnerable:.1},t);assert.ok(s.localSpawnGuideAlpha(t)>0&&s.localSpawnGuideAlpha(t)<1);
 t=s.netTank({...t,invulnerable:0},t);assert.equal(s.localSpawnGuideAlpha(t),0);
 t=s.netTank({...t,invulnerable:.35},t,true);assert.equal(s.localSpawnGuideAlpha(t),0);
 t=s.netTank({...t,spawnSerial:1,invulnerable:1.2},t);assert.equal(s.localSpawnGuideAlpha(t),1,'objective respawns rearm protection on a new life');
 t=s.netTank({...t,invulnerable:.1},t,true);assert.equal(s.localSpawnGuideAlpha(t),0,'a shield event invalidates spawn protection even when an expired snapshot was skipped');
 t=s.netTank({...t,invulnerable:.75},null);assert.equal(s.localSpawnGuideAlpha(t),1,'a new round generation starts with a fresh body');
});

test('a real shield save clears the local spawn tag instead of lighting the golden ring again',()=>{
 const {s}=boot(),noop=()=>{};Object.assign(s,{canDamage:()=>true,burst:noop,addRing:noop,tone:noop,toast:noop});vm.runInContext(declaration('hurt'),s);
 const t=tank({id:0,human:true,invulnerable:0});s.hurt(t,{owner:3,kind:'shell'});assert.equal(t.invulnerable,.35);assert.equal(t.spawnProtected,false);assert.equal(s.localSpawnGuideAlpha(t),0);
});

function onlineBoot(){
 const {s}=boot(),noop=()=>{};
 Object.assign(s,{mode:'online',phase:'onlineLobby',round:0,roundClock:0,phaseTime:0,roundWinner:-1,scores:[],gameStarted:false,tanks:[],particles:[],rings:[],traces:[],bullets:[],pickups:[],cols:12,rows:8,grid:[],walls:[],goUntil:0,shake:0,now:1000,
  performance:{now:()=>s.now},Net:require('../web/netcode.js'),COLORS:[],cacheMap:noop,resize:noop,clearInput:noop,sendOnlineInput:noop,closeVictory:noop,setScreen:noop,renderOnlineRoom:noop,updateHUD:noop,showStartingControls:noop,secondLocal:()=>({id:1}),moveTank:noop,onlineEffect:noop,syncRestartWaveActions:noop,
  online:{connected:true,id:0,generation:0,snapshots:[],ownedIDs:new Set(),activeIDs:new Set(),trailIDs:new Set(),trails:new Map(),localBullets:new Map(),effectQueue:[],shots:{sync:noop,prune:noop,heard:()=>false,previews:new Map()},eventsInitialized:true,lastEvent:0,buffer:{push:packet=>s.online.snapshots.push(packet),advance:()=>null,tank:id=>({...s.online.snapshots.at(-1).tankMap.get(id)})}},
  survivalState:()=>s.online.snapshots.at(-1)?.objectives?.survival,survivalBreak:()=>s.survivalState()?.status==='break',
  resetOnlineMotion:()=>{s.online.snapshots.length=0;}
 });
 s.online.predictor=new s.Net.Predictor(noop);s.online.secondary={predictor:new s.Net.Predictor(noop)};
 for(const name of ['netTank','receiveOnlineState','renderOnlineMotion'])vm.runInContext(declaration(name),s);
 let tick=0;
 s.packet=(phase,{generation=1,wave=0,status='wave',world=false,serial=0,invulnerable=.75,events=[]}={})=>({tick:++tick,generation,phase,round:wave||1,roundClock:75,phaseTime:2.6,winner:-1,scores:[],bullets:[],pickups:[],events,tanks:[tank({id:0,bot:false,spawnSerial:serial,invulnerable}),tank({id:1,bot:false,spawnSerial:serial,invulnerable}),tank({id:3,bot:true,spawnSerial:serial,invulnerable})],...(wave?{objectives:{survival:{wave,status}}}:{}),...(world?{world:{cols:12,rows:8,width:1008,height:672,walls:[]}}:{})});
 return s;
}

test('online protection presentation follows authoritative timers between packets and freezes in countdown and wave breaks',()=>{
 const s=onlineBoot(),frame=now=>{s.renderOnlineMotion(1/60,now);return s.tanks.find(t=>t.id===0);};
 s.receiveOnlineState(s.packet('countdown',{world:true}));assert.equal(s.localSpawnGuideAlpha(frame(6000)),1,'waiting before weapons are live cannot spend countdown protection');
 s.now=6000;s.receiveOnlineState(s.packet('playing'));
 assert.ok(s.localSpawnGuideAlpha(frame(6749))>0&&s.localSpawnGuideAlpha(frame(6749))<.0001);assert.equal(s.localSpawnGuideAlpha(frame(6750)),0,'ring vanishes precisely at the latest snapshot protection expiry');
 assert.equal(s.localSpawnGuideAlpha(frame(16000)),0,'stale snapshots cannot leave a stuck protected ring');
 assert.equal(s.online.snapshots.at(-1).tankMap.get(0).invulnerable,.75,'presentation never changes authority');assert.equal(s.online.predictor.state.invulnerable,.75,'prediction cannot gain or consume authoritative protection');
 s.now=16000;s.receiveOnlineState(s.packet('playing',{generation:2,wave:5,serial:1,invulnerable:1.2,world:true}));assert.ok(s.localSpawnGuideAlpha(frame(17199))>0&&s.localSpawnGuideAlpha(frame(17199))<.0001);assert.equal(s.localSpawnGuideAlpha(frame(17200)),0);
 s.now=18000;s.receiveOnlineState(s.packet('playing',{generation:2,wave:5,serial:1,status:'break',invulnerable:.1}));assert.equal(frame(25000).invulnerable,.1);assert.equal(s.localSpawnGuideAlpha(frame(25000)),0,'intermission has no golden spawn indicator');
 s.now=25000;s.receiveOnlineState(s.packet('countdown',{generation:3,wave:5,serial:2,invulnerable:1.2,world:true}));assert.equal(s.localSpawnGuideAlpha(frame(28000)),1,'retry countdown resets this wave’s protected bodies');
});

test('online shield history applies to the matching life and generation before drawing, including a dropped expiry packet',()=>{
 const s=onlineBoot();s.receiveOnlineState(s.packet('countdown',{world:true}));s.now+=1000;
 s.receiveOnlineState(s.packet('playing',{invulnerable:.1,events:[{type:'shield',id:1,player:0,spawnSerial:0,generation:1}]}));s.renderOnlineMotion(1/60,s.now);
 assert.equal(s.localSpawnGuideAlpha(s.tanks.find(t=>t.id===0)),0);assert.ok(s.localSpawnGuideAlpha(s.tanks.find(t=>t.id===1))>0);
 s.now+=1000;s.receiveOnlineState(s.packet('countdown',{generation:2,world:true,events:[{type:'shield',id:1,player:0,spawnSerial:0,generation:1}]}));s.renderOnlineMotion(1/60,s.now);assert.equal(s.localSpawnGuideAlpha(s.tanks.find(t=>t.id===0)),1,'a former round’s shield event cannot cancel fresh spawn protection');
});


test('the render pass paints edge labels above tanks after restoring the maze clip',()=>{
 const {s,ctx}=boot(),noop=()=>{};
 Object.assign(s,{dpr:1,cssW:2400,cssH:1500,offsetX:0,offsetY:0,shake:0,mapCanvas:null,tanks:[tank({x:1200,y:21,powerTime:0,shield:0,speedTime:0,scopeTime:0,ghostTime:0})],pickups:[],bullets:[],rings:[],particles:[],drawObjectives:noop,drawAimingGuides:noop,drawFlags:noop,drawMissileWarnings:noop,drawLasers:noop,syncCanvasSize:noop});
 vm.runInContext(declaration('render'),s);s.render();
 const labels=ctx.events.filter(e=>e.type==='text');assert.equal(labels.length,1);assert.equal(labels[0].clipped,false,'the maze boundary must not cut off the name');
 const rect=labelRect(ctx);assert.equal(rect.y+rect.h,s.tanks[0].y-32);assert.ok(rect.y<0,'fixed above-tank position can extend into the canvas margin');
});


test('gold, pink and grey rings use the same eased final 300 ms without extending protection',()=>{
 const {s,ctx}=boot();
 for(const [remaining,expected] of [[2,1],[.75,1],[.3,1],[.225,.84375],[.15,.5],[.075,.15625],[0,0],[-.1,0]]){
  for(const [id,human] of [[0,true],[1,true],[3,true],[4,false]]){
   const t=tank({id,human,shield:0,invulnerable:remaining});ctx.events.length=0;s.drawTank(t);
   const guide=ctx.events.find(e=>e.type==='arc'&&e.r===34&&['#ffd76a','#ff4fd8'].includes(e.color)),grey=ctx.events.find(e=>e.type==='arc'&&e.r===27&&e.color===s.theme.protection);
   if(remaining<=0){assert.equal(guide,undefined);assert.equal(grey,undefined);continue;}
   assert.ok(Math.abs(grey.alpha-.35*expected)<1e-8,`grey ${remaining}`);
   if(id===0||id===1){assert.ok(Math.abs(guide.alpha-expected)<1e-8,`pilot ${id} at ${remaining}`);assert.equal(guide.color,id===1?'#ff4fd8':'#ffd76a');}else assert.equal(guide,undefined);
  }
 }
 // A tiny step at either end changes opacity much less than a linear fade:
 // easing joins both full strength and zero without a visible hard corner.
 assert.ok(s.protectionRingAlpha({invulnerable:.0001})<.000001);
 assert.ok(1-s.protectionRingAlpha({invulnerable:.2999})<.000001);
});

test('shield-hit grace may fade grey but never creates a gold or pink spawn locator',()=>{
 for(const id of [0,1]){const {s,ctx}=boot(),t=tank({id,human:true,shield:0,spawnProtected:false,invulnerable:.15});s.drawTank(t);
 assert.equal(ctx.events.some(e=>e.type==='arc'&&['#ffd76a','#ff4fd8'].includes(e.color)),false);assert.equal(ctx.events.find(e=>e.type==='arc'&&e.r===27).alpha,.175);}
});
