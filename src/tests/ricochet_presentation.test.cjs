'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),{assetPath}=require('./web_assets.cjs');
const Net=require(assetPath('netcode.js')),{boot}=require('./godlike426-harness.cjs');
const bullet=extra=>({id:7,owner:1,kind:'',x:94,y:100,vx:282,vy:0,life:5,age:1,bounces:0,...extra});
const close=(actual,expected)=>assert.ok(Math.abs(actual-expected)<1e-7,`${actual} != ${expected}`);

test('a proven fixed-wall ricochet moves at120Hz through its actual bounce, with no snapshot mutation',()=>{
 const world=boot({cols:4,rows:4,wallList:[{x:100,y:0,w:8,h:336}]}),span=1/30;
 const first=bullet(),second=bullet({x:89.52,vx:-282,life:5-span,age:1+span,bounces:1});
 const saved=JSON.stringify([first,second]);let queries=0;
 const path=Net.RicochetPath.between(first,second,span,(...args)=>{queries++;return world.projectileWall(...args);},{nudge:.08});
 assert.ok(path);const built=queries,contact=(96.5-94)/282;
 const samples=[];
 for(let frame=0;frame<=4;frame++){
  const fraction=frame/4,time=span*fraction,pose=path.sample(fraction);samples.push(pose.x);
  const expected=time<contact?94+282*time:96.5-.08-282*(time-contact);
  close(pose.x,expected);close(pose.y,100);assert.ok(pose.x<=96.5);close(pose.life,5-time);
 }
 assert.ok(samples[1]>samples[0]&&samples[2]<samples[1]&&samples[3]<samples[2],'motion must approach the face and move away instead of holding for33ms');
 for(let frame=0;frame<120;frame++)path.sample(frame/120);
 assert.equal(queries,built,'sampling a cached path must not query wall geometry each display frame');
 assert.equal(JSON.stringify([first,second]),saved,'cosmetics cannot change authoritative projectiles');
});

test('corner reflections and four-bounce intervals follow real fixed geometry',()=>{
 const corner=boot({cols:4,rows:4,wallList:[{x:100,y:0,w:8,h:336},{x:0,y:100,w:336,h:8}]}),span=1/30;
 const path=Net.RicochetPath.between(bullet({y:94,vy:282}),bullet({x:89.52,y:89.52,vx:-282,vy:-282,life:5-span,bounces:1}),span,corner.projectileWall,{nudge:.08});
 assert.ok(path);close(path.sample(.5).x,path.sample(.5).y);assert.equal(path.sample(.5).bounces,1);
 const corridor=boot({cols:4,rows:4,wallList:[{x:100,y:0,w:8,h:336},{x:134,y:0,w:8,h:336}]}),duration=.075;
 const many=Net.RicochetPath.between(bullet({x:120,vx:1000}),bullet({x:119.32,vx:1000,life:5-duration,bounces:4}),duration,corridor.projectileWall,{nudge:.08});
 assert.ok(many,'four reflections plus a final free segment fit within the bounded replay');
 for(let i=0;i<=120;i++){const pose=many.sample(i/120);assert.ok(pose.x>=111.5&&pose.x<=130.5);}
});

test('cannon interpolation ignores interior walls and reflects only at the fixed outer rim',()=>{
 const world=boot({cols:4,rows:4,wallList:[{x:300,y:0,w:8,h:336}]}),span=.1;
 const first=bullet({kind:'cannon',x:280,vx:512}),second=bullet({kind:'cannon',x:304.72,vx:-512,life:5-span,bounces:1});
 const path=Net.RicochetPath.between(first,second,span,world.projectileWall,{nudge:.08});
 assert.ok(path);assert.ok(path.sample(.5).x>300,'Cannon must pass through the interior wall');
 assert.ok(path.sample(.9).vx<0);for(let i=0;i<=120;i++)assert.ok(path.sample(i/120).x<=318);
});

test('Infinity ricochets use actual seeded geometry and its .12 outward nudge',()=>{
 const context={window:{},Math};vm.createContext(context);
 vm.runInContext(readFileSync(assetPath('infinite-maze.js'),'utf8'),context);
 const source=readFileSync(assetPath('infinite.js'),'utf8');
 vm.runInContext(source.slice(source.indexOf('function wallHit('),source.indexOf('\nfunction canDamage(')),context);
 const maze=context.window.leqraInfiniteMaze.create(37),wall=maze.wallsNear(-168,-168,168,168)[0],span=1/30,r=3.5;
 let first,second;
 if(wall.axis==='v'){
  const face=wall.x-r,y=wall.y+wall.h/2;first=bullet({x:face-2,y});second=bullet({x:face-.12-(282*span-2),y,vx:-282,life:5-span,bounces:1});
 }else{
  const face=wall.y-r,x=wall.x+wall.w/2;first=bullet({x,y:face-2,vx:0,vy:282});second=bullet({x,y:face-.12-(282*span-2),vx:0,vy:-282,life:5-span,bounces:1});
 }
 const path=Net.RicochetPath.between(first,second,span,(_kind,x,y,dx,dy,radius)=>context.wallHit(maze,x,y,dx,dy,radius));
 assert.ok(path);assert.ok(path.sample(.5).bounces>0);assert.deepEqual(path.sample(1),second);
});

test('guided, expired, malformed and unproved ricochets return a conservative fallback',()=>{
 const world=boot({cols:4,rows:4,wallList:[{x:100,y:0,w:8,h:336}]}),span=1/30;
 const first=bullet(),second=bullet({x:89.52,vx:-282,life:5-span,bounces:1});
 for(const [a,b,duration]of[
  [first,{...second,id:99},span],[first,{...second,owner:2},span],[first,{...second,x:91},span],
  [first,{...second,vx:-280},span],[first,{...second,bounces:5},span],[first,{...second,life:4},span],
  [{...first,life:.01},{...second,life:0},span],[first,second,.11],[first,second,0],[first,{...second,x:NaN},span],
  ...['homing','grenade','laser'].map(kind=>[{...first,kind},{...second,kind},span]),
 ])assert.equal(Net.RicochetPath.between(a,b,duration,world.projectileWall,{nudge:.08}),null);
 assert.equal(Net.RicochetPath.between(first,second,span,()=>({t:NaN,nx:-1,ny:0})),null);
 assert.equal(Net.RicochetPath.between(first,second,span,()=>({t:0,nx:0,ny:0})),null);
});
