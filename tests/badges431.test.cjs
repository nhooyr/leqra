'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function recorder(){
 let matrix={x:0,y:0,angle:0},stack=[],shape;
 const events=[],c={events,canvas:{},save(){stack.push({...matrix});},restore(){matrix=stack.pop();},translate(x,y){matrix.x+=Math.cos(matrix.angle)*x-Math.sin(matrix.angle)*y;matrix.y+=Math.sin(matrix.angle)*x+Math.cos(matrix.angle)*y;},rotate(a){matrix.angle+=a;},beginPath(){shape=null;},rect(x,y,w,h){shape={x,y,w,h};},fill(){if(shape)events.push({type:'rect',...shape,matrix:{...matrix}});},fillText(text,x,y){events.push({type:'text',text,x,y,font:this.font,matrix:{...matrix}});},drawImage(image,x,y,w,h){events.push({type:'image',image,x,y,w,h,matrix:{...matrix}});},measureText(text){return{width:text.length*6};}};
 return new Proxy(c,{get:(t,k)=>k in t?t[k]:(()=>{})});
}
function boot(){
 const ctx=recorder(),made=[];
 const s={ctx,mode:'room',scale:1,W:2400,H:1500,TAU:Math.PI*2,MAX_SPEED_STACKS:5,reduceMotion:true,fxTime:0,theme:{protection:'#fff'},localPlayerID:()=>0,secondaryID:()=>1,paintColor:c=>c,clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),tankPowerBadgeCache:new Map(),tankPowerBadgeScratch:[],labelWidthCache:new Map(),drawCachedTankHull(){},roundRect:(c,...args)=>{c.beginPath();c.rect(...args);},powerIcon:(kind,c)=>c.canvas.kind=kind,document:{createElement:()=>{const c=recorder(),canvas=c.canvas;canvas.getContext=()=>c;made.push(canvas);return canvas;}}};
 vm.createContext(s);vm.runInContext(source.slice(source.indexOf('const POWER='),source.indexOf('\nconst LASER_MAX_SEGMENTS=')),s);
 vm.runInContext(source.slice(source.indexOf('const tankPowerBadgeCache='),source.indexOf('function activeTankPowerBadges(')),s);
 for(const name of ['shieldCount','speedCount','measureLabel','activeTankPowerBadges','tankPowerBadgeImage','tankStatusLayout','tankPowerBadgePositions','drawTankPowerBadges','drawTank'])vm.runInContext(declaration(name),s);
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
   assert.ok(nearX*nearX+nearY*nearY>=46*46,'icons stay outside both the hull and all five shield rings');
   assert.deepEqual(icon.matrix,{x:0,y:0,angle:0},'icons remain aligned with the world after the tank rotates');
   assert.ok(icon.w>=26&&icon.h>=26,'retain readable icon size');
   assert.ok(icon.w*scale>=Math.min(26*scale,21.32)-1e-8);
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
   assert.ok(nearX*nearX+nearY*nearY>=46*46,'badge stays outside the hull and maximum shield rings');
   for(let j=0;j<i;j++)assert.ok(!overlaps(icon,icons[j]),'badges remain separate');
  }
 }
});
