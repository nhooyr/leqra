'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),path=require('node:path');
const source=readFileSync(process.env.LEQRA_GRACE_SOURCE||path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
const specs=[['',282,3.5],['homing',235,5],['grenade',205,6],['cannon',1128,14],['rapid',846,3.5/3],['scatter',846,3.5]];
function tank(id,x=200,y=200){return{id,x,y,r:17,alive:true,team:id+1,invulnerable:0};}
function boot(kind='',speed=282,radius=3.5,extra={},walls=[]){
 const owner=tank(0),shell={owner:0,x:199.7,y:200+owner.r+radius-.001,vx:speed,vy:0,r:radius,kind,age:.195,life:1,bounces:0,trail:[],seekDelay:1,rangeLeft:1000,...extra};
 const noop=()=>{},s={Math,distance:(a,b)=>Math.hypot(a.x-b.x,a.y-b.y),blastEffect:noop,cols:12,rows:10,CELL:84,WALL:8,W:1008,H:840,wallIndex:null,walls,tanks:[owner],bullets:[shell],hits:[],
  clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),isEnemy:(a,b)=>a.id!==b.id&&a.team!==b.team,currentRules:()=>({friendlyFire:false}),
  burst:noop,ricochetSound:noop,impactEffect:noop,
  hurt(target,b){s.hits.push(target.id);target.alive=false;}};
 vm.createContext(s);
 const constants=source.slice(source.indexOf('const DIFFICULTY='),source.indexOf("let phase='menu'"));
 vm.runInContext(constants,s);
 for(const name of ['canDamage','nearbyWalls','rayWalls','rayBounds','projectileWall','circleHit','tankHit','grenadeDragIntegral','grenadeDragFactor','steerMissile','spendMissileRange','missileWallNudge','updateBullets','compactNotDead','detonate','projectileTankImpact'])vm.runInContext(declaration(name),s);
 return{s,owner,shell};
}

test('all projectiles pass through the shooter and can still hit an enemy',()=>{
 for(const [kind,speed,radius] of specs)for(const age of [0,1]){
  const {s,owner,shell}=boot(kind,speed,radius,{x:173,y:200,age,life:10-age});s.tanks.push(tank(1,247,200));
  for(let i=0;i<60&&!shell.dead;i++)s.updateBullets(1/120);
  assert.equal(owner.alive,true,kind+' at age '+age);assert.deepEqual(s.hits,[1]);assert.equal(shell.dead,true);
 }
});

test('a ricochet passes through the shooter and still hits an enemy',()=>{
 const {s,owner,shell}=boot('',282,3.5,{x:220,y:200,age:1},[{x:230,y:180,w:8,h:80}]);s.tanks.push(tank(1,140,200));
 for(let i=0;i<60&&!shell.dead;i++)s.updateBullets(1/120);
 assert.equal(owner.alive,true);assert.deepEqual(s.hits,[1]);assert.equal(shell.bounces,1);assert.equal(shell.dead,true);
});

test('owner immunity applies to grenade fuse and remote blasts even with friendly fire',()=>{
 for(const cause of ['fuse','remote']){
  const {s,owner,shell}=boot('grenade',205,6,{x:200,y:200,vx:0,age:9.99,life:.01});
  s.tanks.push(tank(1,255,200));s.tanks[1].team=owner.team;s.currentRules=()=>({friendlyFire:true});
  if(cause==='fuse')s.updateBullets(1/60);else s.detonate(shell);
  assert.equal(owner.alive,true,cause);assert.deepEqual(s.hits,[1]);assert.equal(shell.dead,true);
 }
});
