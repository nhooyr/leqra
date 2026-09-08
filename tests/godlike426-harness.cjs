'use strict';
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){
 const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);
 const end=source.indexOf('\n',start),line=source.slice(start,end);
 return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);
}
function tank(id,x,y,extra={}){
 return{id,x,y,r:17,angle:0,team:id+1,alive:true,human:false,difficulty:'godlike',vx:0,vy:0,invulnerable:0,cooldown:0,power:null,powerTime:0,charges:0,shield:0,shieldCharges:0,speedTime:0,speedStacks:0,ghostTime:0,scopeTime:0,
  ai:{think:0,path:[],pathClock:0,target:-1,aim:null,shotClock:0,bankClock:0,bankAim:null,goal:-1,dodgeClock:0,dodgeTime:0,recoverTime:0,stuck:0,lastX:x,lastY:y},...extra};
}
function bullet(owner,x,y,kind='grenade',extra={}){return{owner,x,y,vx:0,vy:0,r:kind==='grenade'?6:5,kind,age:.5,life:kind==='grenade'?5:3,bounces:0,target:-1,seekDelay:0,rangeLeft:1000,dead:false,...extra};}
function boot({cols=12,rows=8,wallList=[],lexical=false}={}){
 const s={console,Math,mode:'room',phase:'playing',difficulty:'normal',wallIndex:null,CELL:84,WALL:8,RADIUS:17,TAU:Math.PI*2,cols,rows,W:cols*84,H:rows*84,tanks:[],bullets:[],pickups:[],walls:wallList,localObjectives:null,
  currentRules:()=>({friendlyFire:s.friendlyFire||false}),clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),rnd:(a,b)=>(a+b)/2,
  angleDelta:(a,b)=>Math.atan2(Math.sin(b-a),Math.cos(b-a)),distance:(a,b)=>Math.hypot(a.x-b.x,a.y-b.y),
  cellAt:(x,y)=>s.clamp(Math.floor(y/84),0,s.rows-1)*s.cols+s.clamp(Math.floor(x/84),0,s.cols-1),
  center:i=>({x:(i%s.cols+.5)*84,y:(Math.floor(i/s.cols)+.5)*84}),isEnemy:(a,b)=>a.id!==b.id&&(a.team===0||a.team!==b.team),
  detonateOwned(t){let n=0;for(const b of s.bullets)if(b.owner===t.id&&!b.dead&&b.kind==='grenade'){b.dead=true;n++;}return n>0;},
  fire(t){s.fired=(s.fired||0)+1;return true;}
 };
 s.grid=Array.from({length:cols*rows},(_,i)=>({neighbors:[i-cols,i+cols,...(i%cols?[i-1]:[]),...(i%cols<cols-1?[i+1]:[])].filter(n=>n>=0&&n<cols*rows)}));
 const constants=source.slice(source.indexOf('const DIFFICULTY='),source.indexOf("let phase='menu'"));
 const names=['shieldCount','speedCount','canDamage','nearbyWalls','rayWalls','circleHit','rayBounds','projectileWall','movementWall','resolveWalls','moveTank',
  'pathScratch','tracePath','bfs','targetMotion','leadPoint','projectileSpec','muzzleProjectile','grenadeDragIntegral','grenadeDragFactor','grenadeForecast',
  'ownedGrenades','steerMissile','spendMissileRange','missileWallNudge','laserTrace','evaluateBotShot','findBankAim','chooseBotAim',
  'planBotPath','routeControl','botHoldingHill','ctfCoverGoal','objectiveGoal','objectiveRoute','chooseDodge','chooseGrenadeAvoid','forecastThreats','movementRisk','forecastGrenadeBodies','godlikeDistances','godlikeObjectiveGoal',
  'godlikePickupValue','godlikePointDanger','godlikeDestination','godlikeRouteDanger','godlikeBlastSafe','godlikeDetonate','godlikeGrenadeShot',
  'godlikeGrenadeThreats','godlikeMissileRisk','godlikeDodge','godlikeSafeShot','godlikeProgress','godlikeBotControl','botControl'];
 if(lexical){const make=new Function('environment','let {'+Object.keys(s).join(',')+'}=environment;\n'+constants+'\n'+names.map(declaration).join('\n')+'\nreturn Object.assign(environment,{'+names.join(',')+',tune:DIFFICULTY});');return make(s);}
 vm.createContext(s);vm.runInContext(constants+'\nglobalThis.tune=DIFFICULTY;',s);
 for(const name of names)vm.runInContext(declaration(name),s);
 return s;
}
module.exports={boot,tank,bullet,declaration};
