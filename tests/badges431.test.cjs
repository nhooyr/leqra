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
 for(const name of ['shieldCount','speedCount','measureLabel','activeTankPowerBadges','tankPowerBadgeImage','tankStatusLayout','drawTankPowerBadges','drawTank'])vm.runInContext(declaration(name),s);
 return {s,ctx,made};
}
function tank(patch={}){return{id:3,name:'GODLIKE BOSS',human:false,alive:true,x:1200,y:700,angle:0,recoil:0,track:0,color:'#73cee4',power:'laser',powerTime:15,shield:10,shieldCharges:5,speedTime:10,speedStacks:2,scopeTime:10,ghostTime:10,...patch};}
function pictures(ctx){return ctx.events.filter(e=>e.type==='image');}

test('all bot and remote power icons sit below the actual name background and text at desktop and mobile scales',()=>{
 for(const mode of ['room','online'])for(const scale of [2,1,.5,.2,.08])for(const charges of [0,1,5]){
  const {s,ctx}=boot();s.mode=mode;s.scale=scale;
  s.drawTank(tank({shield:charges?10:0,shieldCharges:charges,angle:1.35,human:mode==='online'}));
  const text=ctx.events.find(e=>e.type==='text'),label=ctx.events.findLast(e=>e.type==='rect'),icons=pictures(ctx);
  assert.equal(text.text,'GODLIKE BOSS');assert.equal(icons.length,charges?5:4);
  const textDescent=parseFloat(text.font.replace('bold ',''))*.25;
  for(const icon of icons){
   assert.ok(icon.y>label.y+label.h,'label background must not cover any icon');
   assert.ok(icon.y>text.y+textDescent,'scaled name descenders must stay above icons');
   assert.ok(icon.y+icon.h<700-26||icon.y>700+26,'icons do not cover the tank hull');
   assert.deepEqual(icon.matrix,{x:0,y:0,angle:0},'icons remain aligned with the world after the tank rotates');
   assert.ok(icon.w>=26&&icon.h>=26,'retain the existing readable icon size');
   assert.ok(icon.w*scale>=Math.min(26*scale,21.32)-1e-8);
  }
  for(let i=1;i<icons.length;i++){assert.ok(icons[i].x>icons[i-1].x+icons[i-1].w,'adjacent icons do not overlap');assert.equal(icons[i].y,icons[0].y);}
  const left=icons[0].x,right=icons.at(-1).x+icons.at(-1).w;assert.ok(Math.abs((left+right)/2-text.x)<1e-8,'row remains centered on its tank');
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
test('badge rows reuse cached icon sprites across movement and rotation, removing expired effects',()=>{
 const {s,ctx,made}=boot(),t=tank();s.drawTank(t);const first=pictures(ctx).map(e=>e.image);assert.equal(made.length,5);
 for(let i=0;i<20;i++){ctx.events.length=0;t.x+=1;t.y+=2;t.angle+=.1;s.drawTank(t);assert.deepEqual(pictures(ctx).map(e=>e.image),first);}
 assert.equal(made.length,5,'moving tanks do not rebuild icon sprites');
 ctx.events.length=0;Object.assign(t,{powerTime:0,shield:0,speedTime:0,scopeTime:0,ghostTime:0});s.drawTank(t);assert.equal(pictures(ctx).length,0);
 Object.assign(t,{alive:false,powerTime:10});ctx.events.length=0;s.drawTank(t);assert.equal(pictures(ctx).length,0);assert.equal(ctx.events.filter(e=>e.type==='text').length,0);
});

test('name and power row stay inside the maze near its top and side walls',()=>{
 for(const scale of [1,.25])for(const x of [42,2358]){
  const {s,ctx}=boot();s.scale=scale;s.drawTank(tank({x,y:42}));
  const label=ctx.events.findLast(e=>e.type==='rect'),icons=pictures(ctx);
  assert.ok(label.y>42+34,'top-edge stack moves below the shielded hull');
  assert.ok(icons[0].x>=0&&icons.at(-1).x+icons.at(-1).w<=s.W,'badge row stays within side walls');
  assert.ok(icons.every(icon=>icon.y>label.y+label.h));
 }
});
