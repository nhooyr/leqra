'use strict';
const {readFileSync}=require('node:fs'),{assetPath}=require('./web_assets.cjs');
const {random}=require('./spatial439-harness.cjs');
function declaration(source,name){const start=source.indexOf('function '+name+'(');if(start<0)throw Error(name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}

function boot({kind='regular',pilots=8,sourcePath=assetPath('game.js')}={}){
 const source=readFileSync(sourcePath,'utf8'),math=Object.create(Math);math.random=random(44937);
 const noop=()=>{},rules={teamMode:'ffa',friendlyFire:false},env={Math:math,Net:require(assetPath('netcode.js')),COLORS:['#d2f65a','#ff9679','#73cee4','#c5a2ff','#ffc46b','#ff83bd','#75f0cb','#b7c6ee'],cols:24,rows:14,CELL:84,WALL:8,MAX_TANKS:8,RADIUS:17,TAU:Math.PI*2,W:2016,H:1176,grid:[],walls:[],wallIndex:null,
  tanks:[],bullets:[],particles:[],rings:[],traces:[],time:0,bulletId:0,mode:'room',WEBKIT_ENGINE:false,combatPrefs:{performance:false},MACHINE_CAPACITY:115,
  mapDimensions:()=>[24,14],cacheMap:noop,resize:noop,currentRules:()=>rules,survivalBreak:()=>false,
  shotSound:noop,ricochetSound:noop,tone:noop,hurt:noop,impactEffect:noop,projectileTankImpact:noop,detonate:noop,
  clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),rnd:(a,b)=>a+math.random()*(b-a),distance:(a,b)=>Math.hypot(a.x-b.x,a.y-b.y),
  isEnemy:(a,b)=>a.id!==b.id&&(a.team===0||a.team!==b.team),angleDelta:(a,b)=>Math.atan2(Math.sin(b-a),Math.cos(b-a))};
 const constants=source.slice(source.indexOf('const POWER_EFFECT_DURATION='),source.indexOf("let phase='menu'"));
 const names=['canDamage','makeMaze','nearbyWalls','rayWalls','circleHit','tankHit','rayBounds','projectileWall','projectileSpec','muzzleBlocked','muzzleProjectile','activeAmmo','powerCapacity','recycleStarmanProjectiles',
  'fire','fireLaser','laserTrace','laserEffect','steerMissile','guideGrenade','grenadeDragIntegral','grenadeDragFactor','spendMissileRange','missileWallNudge','updateBullets','compactLife','compactNotDead','updateTraces','burst','addRing'];
 if(source.includes('function projectileLaunch('))names.push('projectileLaunch');
 const factory=new Function('env','let {'+Object.keys(env).join(',')+'}=env;\n'+constants+'\n'+names.map(name=>declaration(source,name)).join('\n')+`
 makeMaze();
 for(let id=0;id<8;id++)tanks.push({id,team:0,x:(1+id%4*5+.5)*CELL,y:(1+Math.floor(id/4)*8+.5)*CELL,r:17,angle:id*Math.PI/4,alive:true,human:true,color:'#d2f65a',invulnerable:1e9,ghostTime:1e9,spawnProtected:false,starmanTime:1e9,power:null,cooldown:0,charges:3,machineRounds:180});
 return{tanks,step(){time+=1/120;for(let id=0;id<env.pilots;id++)fire(tanks[id]);updateBullets(1/120);updateTraces(1/120);for(const p of particles)p.life-=1/120;compactLife(particles);if(Math.round(time*120)%2===0)fire.flights?.observe(bullets);},stats(){return{projectiles:bullets.length,particles:particles.length,traces:traces.length,shots:bulletId};}};
 `);
 env.pilots=pilots;const fixture=factory(env);
 for(const tank of fixture.tanks.slice(0,pilots))tank.power=kind==='regular'?null:kind;
 return fixture;
}
module.exports={boot};
