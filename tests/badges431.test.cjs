'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function recorder(){
 let matrix={x:0,y:0,angle:0},stack=[],shape;
 const events=[],c={events,canvas:{},save(){stack.push({...matrix});},restore(){matrix=stack.pop();},translate(x,y){matrix.x+=Math.cos(matrix.angle)*x-Math.sin(matrix.angle)*y;matrix.y+=Math.sin(matrix.angle)*x+Math.cos(matrix.angle)*y;},rotate(a){matrix.angle+=a;},beginPath(){shape=null;},rect(x,y,w,h){shape={x,y,w,h};},arc(x,y,r,start,end){shape={arc:true,x,y,r,start,end};},stroke(){if(shape?.arc)events.push({type:'arc',...shape,color:this.strokeStyle,alpha:this.globalAlpha,width:this.lineWidth,matrix:{...matrix}});},fill(){if(shape&&!shape.arc)events.push({type:'rect',...shape,matrix:{...matrix}});},fillText(text,x,y){events.push({type:'text',text,x,y,font:this.font,matrix:{...matrix}});},drawImage(image,x,y,w,h){events.push({type:'image',image,x,y,w,h,matrix:{...matrix}});},measureText(text){return{width:text.length*6};}};
 return new Proxy(c,{get:(t,k)=>k in t?t[k]:(()=>{})});
}
function boot(){
 const ctx=recorder(),made=[];
 const s={ctx,mode:'room',phase:'playing',spawnGuideUntil:0,isSpectating:()=>false,survivalBreak:()=>false,scale:1,W:2400,H:1500,TAU:Math.PI*2,MAX_SPEED_STACKS:5,reduceMotion:true,fxTime:0,theme:{protection:'#fff'},localPlayerID:()=>0,secondaryID:()=>1,paintColor:c=>c,clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),tankPowerBadgeCache:new Map(),tankPowerBadgeScratch:[],labelWidthCache:new Map(),drawCachedTankHull(){},roundRect:(c,...args)=>{c.beginPath();c.rect(...args);},powerIcon:(kind,c)=>c.canvas.kind=kind,document:{createElement:()=>{const c=recorder(),canvas=c.canvas;canvas.getContext=()=>c;made.push(canvas);return canvas;}}};
 vm.createContext(s);vm.runInContext(source.slice(source.indexOf('const POWER='),source.indexOf('\nconst LASER_MAX_SEGMENTS=')),s);
 vm.runInContext(source.slice(source.indexOf('const tankPowerBadgeCache='),source.indexOf('function activeTankPowerBadges(')),s);
 for(const name of ['shieldCount','speedCount','measureLabel','activeTankPowerBadges','tankPowerBadgeImage','tankStatusLayout','tankPowerBadgePositions','drawTankPowerBadges','showLocalSpawnGuide','localSpawnGuideAlpha','drawLocalSpawnGuide','drawTank'])vm.runInContext(declaration(name),s);
 return {s,ctx,made};
}
function tank(patch={}){return{id:3,name:'GODLIKE BOSS',human:false,alive:true,x:1200,y:700,angle:0,recoil:0,track:0,color:'#73cee4',power:'laser',powerTime:15,shield:10,shieldCharges:5,speedTime:10,speedStacks:2,scopeTime:10,ghostTime:10,...patch};}
function pictures(ctx){return ctx.events.filter(e=>e.type==='image');}

function overlaps(a,b,gap=0){return a.x<b.x+b.w+gap&&a.x+a.w+gap>b.x&&a.y<b.y+b.h+gap&&a.y+a.h+gap>b.y;}
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
   assert.ok(icon.y>=label.y+label.h,'name background stays above the lower icon arc');
   assert.ok(icon.y>text.y+textDescent,'scaled name descenders must stay above icons');
   const nearX=Math.max(icon.x-t.x,0,t.x-icon.x-icon.w),nearY=Math.max(icon.y-t.y,0,t.y-icon.y-icon.h);
   assert.ok(nearX*nearX+nearY*nearY>=31*31,'icons stay outside the hull while outer shield rings can sit behind icons');
   assert.deepEqual(icon.matrix,{x:0,y:0,angle:0},'icons remain aligned with the world after the tank rotates');
   assert.ok(icon.w>=24&&icon.h>=24,'retain readable icon size');
   assert.ok(icon.w*scale>=Math.min(24*scale,17.28)-1e-8);
  }
  for(let i=0;i<icons.length;i++)for(let j=0;j<i;j++)assert.ok(!overlaps(icons[i],icons[j]),'adjacent icons do not overlap');
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

test('names and all five power icons stay inside the maze at its edges without hiding each other or the tank',()=>{
 for(const scale of [1,.25,.08])for(const x of [42,1200,2358])for(const y of [42,700,1458]){
  const {s,ctx}=boot();s.scale=scale;s.drawTank(tank({x,y}));
  const label=labelRect(ctx),icons=pictures(ctx);assert.equal(icons.length,5,`five visible badges at ${scale}: ${x}, ${y}`);
  assert.ok(label.x>=0&&label.x+label.w<=s.W&&label.y>=0&&label.y+label.h<=s.H,'name stays in the maze');
  for(let i=0;i<icons.length;i++){
   const icon=icons[i];assert.ok(icon.x>=0&&icon.x+icon.w<=s.W&&icon.y>=0&&icon.y+icon.h<=s.H,'badge stays in the maze');
   assert.ok(!overlaps(icon,label),'badge remains clear of the name');
   const nearX=Math.max(icon.x-x,0,x-icon.x-icon.w),nearY=Math.max(icon.y-y,0,y-icon.y-icon.h);
   assert.ok(nearX*nearX+nearY*nearY>=31*31,'badge stays outside the hull');
   for(let j=0;j<i;j++)assert.ok(!overlaps(icon,icons[j]),'badges remain separate');
  }
 }
});


test('tank names and badge centers stay close to the hull independent of shield count',()=>{
 for(const scale of [2,1,.5,.2,.08]){
  const {s,ctx}=boot();s.scale=scale;const t=tank();s.drawTank(t);
  const label=labelRect(ctx),icons=pictures(ctx),half=icons[0].w/2,gap=2*Math.max(1,.72/scale);
  assert.equal(t.y-label.y-label.h,32,'name has only two units of clearance above an upward muzzle');
  const oldZ=Math.max(1,.82/scale),oldHalf=13*oldZ,oldGap=3*oldZ;
  const oldRadius=Math.hypot(Math.max(46+oldHalf*Math.SQRT2+oldGap,Math.SQRT2*(2*oldHalf+oldGap)),Math.max(0,oldGap+oldHalf-46));
  const radius=Math.hypot(icons[0].x+half-t.x,icons[0].y+half-t.y);
  assert.ok(radius<=oldRadius,'readability must not increase the former orbit');
  if(scale>=.5)assert.ok(radius<=oldRadius-14.9,'normal and compact views bring icons 15 units closer');
 }
});

test('golden spawn circles identify both actual local pilots in every mode without highlighting bots, remote tanks or spectator seats',()=>{
 for(const mode of ['room','online','solo','duel'])for(const gameMode of ['elimination','deathmatch','ctf','koth','survival']){
  const {s,ctx}=boot();Object.assign(s,{mode,phase:'countdown',currentRules:()=>({mode:gameMode})});
  for(const [patch,expected] of [[{id:0,human:true},true],[{id:1,human:true},true],[{id:3,human:true},false],[{id:0,human:false},false],[{id:1,human:false},false],[{id:0,human:true,survivalEnemy:true},false],[{id:1,human:true,alive:false},false]]){
   ctx.events.length=0;s.drawTank(tank(patch));const gold=ctx.events.filter(e=>e.type==='arc'&&e.color==='#ffd76a');assert.equal(gold.length,expected?1:0,`${mode}/${gameMode}: ${JSON.stringify(patch)}`);
   if(expected){assert.equal(gold[0].r,34);assert.equal(gold[0].alpha,1);}
  }
  s.isSpectating=()=>true;assert.equal(s.localSpawnGuideAlpha(tank({id:0,human:true})),0);
  s.secondaryID=()=>undefined;assert.equal(s.localSpawnGuideAlpha(tank({id:1,human:true})),0);
 }
});

test('spawn circles remain through countdown, briefly mark the start, and disappear during menus, intermission and results',()=>{
 const {s}=boot(),t=tank({id:0,human:true});s.fxTime=10;s.phase='countdown';assert.equal(s.localSpawnGuideAlpha(t),1);
 s.phase='playing';s.showLocalSpawnGuide();assert.equal(s.localSpawnGuideAlpha(t),1);
 s.fxTime=11.35;assert.ok(Math.abs(s.localSpawnGuideAlpha(t)-.5)<1e-8);
 s.fxTime=11.61;assert.equal(s.localSpawnGuideAlpha(t),0);
 s.showLocalSpawnGuide();for(const phase of ['menu','onlineLobby','paused','roundOver','matchOver']){s.phase=phase;assert.equal(s.localSpawnGuideAlpha(t),0);}
 s.phase='playing';s.survivalBreak=()=>true;assert.equal(s.localSpawnGuideAlpha(t),0,'an early wave clear hides the guide during intermission');
 s.phase='countdown';s.fxTime=100;assert.equal(s.localSpawnGuideAlpha(t),1,'another countdown remains visible after the prior timer expires');
});

test('authoritative online countdowns and Survival wave transitions trigger location guides once, including a restart generation',()=>{
 const {s}=boot(),noop=()=>{};
 Object.assign(s,{mode:'online',phase:'onlineLobby',round:0,roundClock:0,phaseTime:0,roundWinner:-1,scores:[],gameStarted:false,tanks:[],particles:[],rings:[],traces:[],bullets:[],pickups:[],cols:12,rows:8,grid:[],walls:[],goUntil:0,
  performance:{now:()=>s.fxTime*1000},Net:{expandMachineBullets:()=>[]},COLORS:[],cacheMap:noop,resize:noop,clearInput:noop,sendOnlineInput:noop,closeVictory:noop,setScreen:noop,renderOnlineRoom:noop,updateHUD:noop,showStartingControls:noop,secondLocal:()=>({id:1}),
  online:{connected:true,id:0,generation:0,snapshots:[],ownedIDs:new Set(),activeIDs:new Set(),localBullets:new Map(),shots:{sync:noop,prune:noop},predictor:{state:null,reconcile:noop},secondary:{predictor:{state:null,reconcile:noop}},eventsInitialized:true},
  survivalState:()=>s.online.snapshots.at(-1)?.objectives?.survival,
  resetOnlineMotion:()=>{s.online.snapshots.length=0;}
 });
 s.online.buffer={push:packet=>s.online.snapshots.push(packet)};
 for(const name of ['netTank','receiveOnlineState'])vm.runInContext(declaration(name),s);
 let tick=0;
 const packet=(phase,{generation=1,wave=0,status='wave',world=false}={})=>({tick:++tick,generation,phase,round:wave||1,roundClock:75,phaseTime:2.6,winner:-1,scores:[],bullets:[],tanks:[tank({id:0,human:undefined,bot:false}),tank({id:1,human:undefined,bot:false}),tank({id:3,human:undefined,bot:true})],...(wave?{objectives:{survival:{wave,status}}}:{}),...(world?{world:{cols:12,rows:8,width:1008,height:672,walls:[]}}:{})});
 const own=()=>s.online.snapshots.at(-1).tanks[0];
 s.receiveOnlineState(packet('countdown',{world:true}));assert.equal(s.localSpawnGuideAlpha(own()),1);
 s.fxTime=3;s.receiveOnlineState(packet('playing'));assert.equal(s.spawnGuideUntil,4.6);assert.equal(s.localSpawnGuideAlpha(own()),1);
 s.fxTime=5;s.receiveOnlineState(packet('playing'));assert.equal(s.localSpawnGuideAlpha(own()),0,'routine snapshots must not keep circles alive');
 s.receiveOnlineState(packet('playing',{generation:2,wave:4,world:true}));assert.equal(s.spawnGuideUntil,6.6,'joining the Survival generation points out the owned tank');
 s.fxTime=8;s.receiveOnlineState(packet('playing',{generation:2,wave:4,status:'break'}));assert.equal(s.spawnGuideUntil,6.6);
 s.fxTime=12;s.receiveOnlineState(packet('playing',{generation:2,wave:5}));assert.equal(s.spawnGuideUntil,13.6,'the existing maze receives a new wave guide');
 s.fxTime=20;s.receiveOnlineState(packet('countdown',{generation:3,wave:5,world:true}));assert.equal(s.localSpawnGuideAlpha(own()),1,'restarting this wave keeps countdown markers');
 s.fxTime=23;s.receiveOnlineState(packet('playing',{generation:3,wave:5}));assert.equal(s.spawnGuideUntil,24.6);
 s.fxTime=25;s.receiveOnlineState(packet('playing',{generation:3,wave:5}));assert.equal(s.localSpawnGuideAlpha(own()),0);
});

test('every offline round countdown refreshes the guide when weapons become live',()=>{
 const {s}=boot(),noop=()=>{};
 Object.assign(s,{phase:'countdown',phaseTime:.01,fxTime:100,shake:0,time:0,toastTime:0,particles:[],rings:[],round:2,uiClock:0,goUntil:0,performance:{now:()=>s.fxTime*1000},updateTraces:noop,compactLife:noop,tone:noop,showStartingControls:noop,updateHUD:noop});
 vm.runInContext(declaration('update'),s);s.update(.02);
 assert.equal(s.phase,'playing');assert.ok(Math.abs(s.spawnGuideUntil-101.62)<1e-8);assert.equal(s.localSpawnGuideAlpha(tank({id:0,human:true})),1);assert.equal(s.localSpawnGuideAlpha(tank({id:1,human:true})),1);
});
