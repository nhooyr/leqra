'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),{readFileSync}=require('node:fs');
const {assetPath}=require('./web_assets.cjs');
const Net=require(assetPath('netcode.js'));
function declaration(source,name){const start=source.indexOf('function '+name+'('),end=source.indexOf('\n',start),line=source.slice(start,end);assert.ok(start>=0,name);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}

test('fixed respawn permits held fire after the previous life detonated a grenade',()=>{
 const source=readFileSync(assetPath('game.js'),'utf8'),tank={id:0,alive:false,detonationHeld:true,fireHeld:true,r:17,spawnSerial:1,ammoEpoch:1};let shots=0;
 const s=vm.createContext({Net,localObjectives:null,spawnCells:()=>Array(8).fill(0),MAX_TANKS:8,grid:[{neighbors:[]}],center:()=>({x:42,y:42}),flagSafeSpawn:()=>true,distance:()=>1000,tanks:[tank],bullets:[],cols:1,rows:1,newTank:()=>({alive:true,r:17,human:true,spawnProtected:true,fireHeld:false}),firePresses:new Set(),localPlayerID:()=>0,mouseAim:{},addRing(){},fire:()=>{shots++;return true;},detonateOwned:()=>false});
 vm.runInContext(declaration(source,'hardwareUsesP2')+'\n'+declaration(source,'respawnLocalTank')+'\n'+declaration(source,'weaponControl'),s);
 s.respawnLocalTank(tank);tank.invulnerable=0;tank.spawnProtected=false;
 s.weaponControl(tank,true,false);
 assert.equal(shots,1,'a new life must not inherit the old grenade detonation latch');
 assert.equal(tank.spawnSerial,2);
});

test('Infinity respawn permits held fire after the previous life detonated a grenade',()=>{
 const source=readFileSync(assetPath('infinite.js'),'utf8'),tank={id:1,bot:false,name:'Pilot',colorIndex:0,score:5,hp:0,alive:false,detonationHeld:true,fireHeld:true,spawnSerial:1,ammoEpoch:1};let shots=0;
 const s=vm.createContext({net:Net,COLORS:['#fff'],between:()=>0,pilotName:()=> 'Pilot',inputState:()=>({fire:true}),fireShot:()=>{shots++;},art:{},RADIUS:17});
 vm.runInContext(['makeTank','respawnOfflineTank','weaponControl'].map(name=>declaration(source,name)).join('\n'),s);
 const world={tanks:[tank],bullets:[],teamScores:[],time:1};
 s.respawnOfflineTank(world,tank,{x:42,y:42});tank.invulnerable=0;tank.spawnProtected=false;
 s.weaponControl(world,tank,true,false);
 assert.equal(shots,1,'a new life must not inherit the old grenade detonation latch');
 assert.equal(tank.spawnSerial,2);assert.equal(tank.score,5);
});
