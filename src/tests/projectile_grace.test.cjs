'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),path=require('node:path');
const source=readFileSync(process.env.LEQRA_GRACE_SOURCE||path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
const specs=[['',282,3.5],['homing',235,5],['grenade',205,6],['cannon',1128,14]];
const close=(actual,expected)=>assert.ok(Math.abs(actual-expected)<1e-8,actual+' != '+expected);
function tank(id,x=200,y=200){return{id,x,y,r:17,alive:true,team:id+1,invulnerable:0};}
function boot(kind='',speed=282,radius=3.5,extra={},walls=[]){
 const owner=tank(0),shell={owner:0,x:199.7,y:200+owner.r+radius-.001,vx:speed,vy:0,r:radius,kind,age:.195,life:1,bounces:0,trail:[],seekDelay:1,rangeLeft:1000,...extra};
 const noop=()=>{},s={Math,cols:12,rows:10,CELL:84,WALL:8,W:1008,H:840,wallIndex:null,walls,tanks:[owner],bullets:[shell],hits:[],
  clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),isEnemy:(a,b)=>a.id!==b.id&&a.team!==b.team,currentRules:()=>({friendlyFire:false}),
  burst:noop,ricochetSound:noop,impactEffect:noop,detonate(b){b.dead=true;},
  projectileTankImpact(b,target){s.hits.push({id:target.id,x:b.x,y:b.y});target.alive=false;b.dead=true;}};
 vm.createContext(s);
 const constants=source.slice(source.indexOf('const DIFFICULTY='),source.indexOf("let phase='menu'"));
 vm.runInContext(constants,s);
 for(const name of ['canDamage','nearbyWalls','rayWalls','rayBounds','projectileWall','circleHit','tankHit','grenadeDragIntegral','grenadeDragFactor','steerMissile','spendMissileRange','missileWallNudge','updateBullets','compactNotDead'])vm.runInContext(declaration(name),s);
 return{s,owner,shell};
}

test('a grazing owner contact before grace expires stays harmless at local and server tick rates',()=>{
 for(const [kind,speed,radius] of specs)for(const dt of [1/120,1/60]){
  const {s,owner,shell}=boot(kind,speed,radius);s.updateBullets(dt);
  assert.equal(owner.alive,true,(kind||'regular')+' '+dt);assert.equal(s.hits.length,0);assert.equal(shell.dead,undefined);
  assert.ok(shell.x>200+Math.sqrt((owner.r+radius)**2-(shell.y-owner.y)**2),'projectile has crossed and exited the protected graze');
 }
});

test('an owner still overlapping at grace expiry is hit at the expiry point',()=>{
 for(const [age,dt,x] of [[.195,1/120,181.41],[.195,1/60,181.41],[.19,.01,182.82]]){
  const {s,owner}=boot('',282,3.5,{x:180,y:200,age});s.updateBullets(dt);
  assert.equal(owner.alive,false);assert.equal(s.hits.length,1);close(s.hits[0].x,x);close(s.hits[0].y,200);
 }
 const protectedShot=boot('',282,3.5,{x:180,y:200,age:.19});protectedShot.s.updateBullets(.005);assert.equal(protectedShot.owner.alive,true);
});

test('other tanks keep their full collision path while the owner has grace',()=>{
 for(const [kind,speed,radius] of specs){
  const {s,owner,shell}=boot(kind,speed,radius,{x:100,y:100,age:0});s.tanks.push(tank(1,100,100));s.updateBullets(1/120);
  assert.equal(owner.alive,true);assert.equal(s.hits.length,1);assert.equal(s.hits[0].id,1);close(s.hits[0].x,100);assert.equal(shell.dead,true);
 }
 for(const kind of ['scatter','rapid']){
  const {s,owner}=boot(kind,846,3.5,{x:200,y:200,age:1});s.updateBullets(1/60);assert.equal(owner.alive,true);assert.equal(s.hits.length,0,kind+' retains permanent owner immunity');
 }
});

test('ricochets use elapsed travel time for contacts before and after owner grace',()=>{
 for(const [wallX,hitOwner] of [[204,false],[205,true]]){
  const {s,owner,shell}=boot('',282,3.5,{x:200.3},[{x:wallX,y:219,w:8,h:20}]);s.updateBullets(1/60);
  assert.equal(shell.bounces,1);assert.equal(owner.alive,!hitOwner);assert.equal(s.hits.length,hitOwner?1:0);
  if(hitOwner)close(s.hits[0].x,200+Math.sqrt(20.5**2-20.499**2));
 }
 // This contact is already overlapping when grace expires on the reflected leg.
 const b=boot('',282,3.5,{x:220.6,y:200,age:.1925},[{x:225.1,y:180,w:8,h:40}]);b.s.updateBullets(1/120);
 assert.equal(b.shell.bounces,1);assert.equal(b.owner.alive,false);close(b.s.hits[0].x,220.405);
});

test('a wall reached before the unprotected owner path still wins the collision',()=>{
 const {s,owner,shell}=boot('',282,3.5,{x:176,y:200},[{x:180,y:180,w:8,h:40}]);s.updateBullets(1/120);
 assert.equal(owner.alive,true);assert.equal(s.hits.length,0);assert.equal(shell.bounces,1);assert.ok(shell.vx<0);
});
