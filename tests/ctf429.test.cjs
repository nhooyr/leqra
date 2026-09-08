'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {boot,tank,declaration}=require('./godlike426-harness.cjs');
const levels=['easy','normal','hard','godlike'];
function arena(level,escorts=1,corridor=false){
 const walls=[{x:-4,y:-4,w:512,h:8,axis:'h'},{x:-4,y:416,w:512,h:8,axis:'h'},{x:-4,y:-4,w:8,h:428,axis:'v'},{x:500,y:-4,w:8,h:428,axis:'v'}];
 if(corridor)walls.push({x:80,y:164,w:8,h:92,axis:'v'},{x:80,y:164,w:344,h:8,axis:'h'},{x:80,y:248,w:344,h:8,axis:'h'});
 const s=boot({cols:6,rows:5,wallList:walls}),carrier=tank(0,378,210,{team:1,human:true,angle:Math.PI,cooldown:100});
 s.tanks=[carrier];for(let i=1;i<=escorts;i++)s.tanks.push(tank(i,corridor?126+(i-1)*40:126,corridor?210:210+(i-1)*36,{team:1,difficulty:level,cooldown:100}));s.tanks.push(tank(escorts+1,462,42,{team:2,human:true,invulnerable:100,cooldown:100}));
 Object.assign(s,{fxTime:0,time:0,phaseTime:100,toastTime:0,particles:[],rings:[],shake:0,uiClock:0,roundClock:600,spawnClock:100,scores:Array(8).fill(0),walking:true,
  updateTraces(){},compactLife(){},survivalMode:()=>false,objectiveMode:()=>true,suddenDeath:()=>false,liveLocalStats:()=>false,respawnLocalPlayers(){},advanceGhost(){},updateBullets(){},updateHUD(){},addLog(){},recordLocalObjective(){},pickupSound(){},toast(){},teamName:n=>'Team '+n,
  humanControl(t,dt){if(t.id===0&&s.walking)s.moveTank(t,-128*dt,0);},addObjectivePoint(t){for(const ally of s.tanks)if(ally.team===t.team)s.scores[ally.id]++;}
 });
 const own={team:1,x:126,y:210,homeX:126,homeY:210,home:true,carrier:-1},other={team:2,x:378,y:210,homeX:462,homeY:42,home:false,carrier:0};s.localObjectives={mode:'ctf',flags:[own,other]};
 for(const name of ['wallBetweenCenters','resetLocalFlag','dropLocalFlags','stepLocalObjectives','update'])vm.runInContext(declaration(name),s);
 for(let i=0;i<s.grid.length;i++)s.grid[i].neighbors=s.grid[i].neighbors.filter(j=>{const a=s.center(i),b=s.center(j);return !s.rayWalls(a.x,a.y,b.x-a.x,b.y-a.y,18);});
 return{s,carrier,own,other};
}
function advance(s,seconds,done=()=>false){for(let i=0;i<seconds*120&&!done();i++)s.update(1/120);}

test('all difficulties vacate the capture point and leave a returning human room to score',()=>{
 for(const level of levels){const {s,own}=arena(level);s.walking=false;advance(s,2.5);assert.ok(s.distance(s.tanks[1],own)>44,level+' is still occupying the capture point');s.walking=true;advance(s,3,()=>s.scores[0]>0);assert.ok(s.scores[0]>0,level+' moved back into the carrier');}
});

test('all difficulties allow human and bot carriers to score with one or three escorts in open and dead-end bases',()=>{
 for(const level of levels)for(const human of [true,false])for(const corridor of [false,true])for(const escorts of [1,3]){
  const {s,carrier}=arena(level,escorts,corridor);carrier.human=human;carrier.difficulty=level;advance(s,10,()=>s.scores[0]>0);
  assert.ok(s.scores[0]>0,`${level} ${human?'human':'bot'} ${corridor?'corridor':'open'} ${escorts} escorts stalled at ${carrier.x},${carrier.y}`);
 }
});

test('CTF supporters still return a dropped own flag before clearing the base',()=>{
 for(const level of levels){const {s,own}=arena(level);Object.assign(own,{home:false,x:210,y:210,returnIn:20});advance(s,10,()=>s.scores[0]>0);assert.equal(own.home,true,level);assert.ok(s.scores[0]>0,level+' failed return and capture');}
});

test('fully boosted and ghost supporters leave the carrier a usable scoring approach',()=>{
 for(const level of levels)for(const power of ['speed','ghost']){const {s}=arena(level,3,true);for(const t of s.tanks)if(!t.human)Object.assign(t,power==='speed'?{speedTime:15,speedStacks:5}:{ghostTime:15});advance(s,10,()=>s.scores[0]>0);assert.ok(s.scores[0]>0,level+' '+power);}
});

test('cover positions are cached and restricted to active friendly carrier objectives',()=>{
 const {s,carrier,own,other}=arena('godlike'),bot=s.tanks[1],point=s.ctfCoverGoal(bot,own,carrier),grid=s.grid;
 s.grid=new Proxy(grid,{get(){throw Error('cached cover scanned navigation');}});for(let i=0;i<100;i++)assert.equal(s.ctfCoverGoal(bot,own,carrier),point);s.grid=grid;
 other.carrier=-1;assert.equal(s.objectiveGoal(bot),other);s.localObjectives.suddenDeath=true;assert.equal(s.objectiveGoal(bot),null);
});

test('Godlike support does not leave its cover goal for a pickup on the capture point',()=>{
 const {s,carrier,own}=arena('godlike'),bot=s.tanks[1],point=s.ctfCoverGoal(bot,own,carrier);s.pickups=[{x:own.x,y:own.y,type:'shield',life:30}];
 assert.equal(s.godlikeDestination(bot,s.tanks[2],point,s.tune.godlike),point);assert.equal(bot.ai.godPickup,null);
});

test('Godlike cover hold still permits imminent projectile avoidance',()=>{
 const {s,carrier,own}=arena('godlike'),bot=s.tanks[1],point=s.ctfCoverGoal(bot,own,carrier);bot.x=point.x;bot.y=point.y;
 s.bullets=[{owner:2,x:bot.x+65,y:bot.y,vx:-300,vy:0,r:3.5,kind:'',age:0,life:3,dead:false}];
 for(let i=0;i<60;i++)s.botControl(bot,1/120);
 assert.ok(s.distance(bot,point)>2,'cover hold suppressed an imminent dodge');
});
