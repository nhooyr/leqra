'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {boot,tank,declaration}=require('./godlike426-harness.cjs');
const levels=['easy','normal','hard','godlike'];
function arena(level,wallList=[]){
 const s=boot({cols:6,rows:5,wallList}),bot=tank(0,170,180,{difficulty:level,angle:Math.atan2(30,40)}),enemy=tank(1,462,378,{human:true,invulnerable:100});s.tanks=[bot,enemy];
 s.roundClock=600;s.scores=[0,0];s.addLog=()=>{};s.recordLocalObjective=()=>{};s.pickupSound=()=>{};s.toast=()=>{};s.teamName=n=>'Team '+n;
 s.addObjectivePoint=t=>s.scores[t.id]++;
 for(const name of ['resetLocalFlag','dropLocalFlags','stepLocalObjectives'])vm.runInContext(declaration(name),s);
 // The production navigation graph excludes doorways blocked for the full hull.
 for(let i=0;i<s.grid.length;i++)s.grid[i].neighbors=s.grid[i].neighbors.filter(j=>{const a=s.center(i),b=s.center(j);return !s.rayWalls(a.x,a.y,b.x-a.x,b.y-a.y,18);});
 return{s,bot,enemy};
}
function flags(){return[{team:1,x:42,y:42,homeX:42,homeY:42,home:true,carrier:-1},{team:2,x:210,y:210,homeX:210,homeY:210,home:true,carrier:-1}];}
function advance(s,bot,seconds,done=()=>false){for(let i=0;i<seconds*120&&!done();i++){s.botControl(bot,1/120);if(s.localObjectives)s.stepLocalObjectives(1/120);}}

test('all bot difficulties complete flag pickup, dropped flag return, capture and hill scoring from the destination cell',()=>{
 for(const level of levels)for(const kind of ['flag','dropped flag','base','hill']){
  const {s,bot}=arena(level),[own,other]=flags();s.localObjectives={mode:'ctf',flags:[own,other]};
  if(kind==='dropped flag')Object.assign(own,{home:false,x:239,y:215,returnIn:20});
  if(kind==='base'){Object.assign(own,{x:210,y:210,homeX:210,homeY:210});Object.assign(other,{home:false,carrier:bot.id});}
  if(kind==='hill')s.localObjectives={mode:'koth',flags:[],hillX:210,hillY:210,radius:32,hold:0};
  const done=()=>kind==='flag'?other.carrier===bot.id:kind==='dropped flag'?own.home:s.scores[bot.id]>0;
  advance(s,bot,6,done);assert.ok(done(),`${level} stalled before ${kind} at ${bot.x}, ${bot.y}`);
 }
});

test('Godlike enters pickup contact range instead of applying the combat stand-off distance',()=>{
 const {s,bot,enemy}=arena('godlike');enemy.invulnerable=0;enemy.x=360;enemy.y=210;
 const p={x:210,y:210,type:'shield',life:30};s.pickups=[p];advance(s,bot,2,()=>s.distance(bot,p)<bot.r+13);
 assert.ok(s.distance(bot,p)<bot.r+13,'final movement reaches the actual pickup contact radius despite an available shot');
});

test('precise interaction approaches work with each difficulty tuning and a nearby teammate',()=>{
 for(const level of levels){const {s,bot}=arena(level),p={x:210,y:210},d=s.tune[level];s.tanks.push(tank(2,205,185,{team:1}));
  for(let i=0;i<240&&s.distance(bot,p)>=30;i++){
   const control=s.routeControl(bot,p,true),diff=s.angleDelta(bot.angle,control.angle);bot.angle+=s.clamp(diff,-d.turn/120,d.turn/120);const drive=control.drive*Math.max(0,Math.cos(diff));s.moveTank(bot,Math.cos(bot.angle)*d.speed*drive/120,Math.sin(bot.angle)*d.speed*drive/120);
  }
  assert.ok(s.distance(bot,p)<30,level+' never completes final approach beside ally');
 }
});

test('ordinary enemy routes retain a combat stand-off distance',()=>{
 const {s,bot}=arena('hard');const control=s.routeControl(bot,{x:210,y:210});assert.equal(control.drive,0);
});

test('all bot difficulties keep scoring instead of backing off a nearby firing target',()=>{
 for(const level of levels){const {s,bot,enemy}=arena(level);bot.x=210;bot.y=210;bot.angle=0;enemy.x=270;enemy.y=210;enemy.invulnerable=0;
  s.localObjectives={mode:'koth',flags:[],hillX:210,hillY:210,radius:32,hold:0};advance(s,bot,3);
  assert.ok(s.scores[bot.id]>=2,level+' abandoned hill score');assert.ok(s.distance(bot,{x:210,y:210})<29,level+' left scoring radius');
 }
});

test('all difficulties navigate around a blocking wall and take the flag',()=>{
 for(const level of levels){const {s,bot}=arena(level,[{x:164,y:-4,w:8,h:260,axis:'v'}]);bot.x=126;bot.y=210;bot.angle=0;const [own,other]=flags();s.localObjectives={mode:'ctf',flags:[own,other]};
  advance(s,bot,15,()=>other.carrier===bot.id);assert.equal(other.carrier,bot.id,`${level} stalled at wall: ${bot.x}, ${bot.y}`);
 }
});

test('route shortcuts discard skipped prefixes and final approach cannot aim at a passed cell',()=>{
 const {s,bot}=arena('godlike');bot.x=42;bot.y=294;bot.angle=Math.PI/2;bot.ai.path=[0,6,12,18,24];
 const control=s.routeControl(bot,{x:42,y:378},true);assert.ok(Math.abs(s.angleDelta(control.angle,Math.PI/2))<.01);assert.ok(control.drive>0);assert.equal(bot.ai.path.length,0);
 bot.x=42;bot.y=42;bot.ai.path=[6,12,18,24];s.routeControl(bot,{x:462,y:378});assert.equal(bot.ai.path[0],24,'bypassed cells must not survive the shortcut');
});

test('fully speed-stacked bots complete and hold the hill approach',()=>{
 for(const level of levels){const {s,bot}=arena(level);bot.speedStacks=5;bot.speedTime=15;s.localObjectives={mode:'koth',flags:[],hillX:210,hillY:210,radius:32,hold:0};
  advance(s,bot,6,()=>s.scores[bot.id]>0);assert.ok(s.scores[bot.id]>0,level+' overshot the hill without scoring');
 }
});

test('a clear final approach does not rebuild a breadth-first route on every frame',()=>{
 const {s,bot}=arena('easy');s.localObjectives={mode:'koth',flags:[],hillX:462,hillY:210,radius:32,hold:0};let plans=0;const bfs=s.bfs;s.bfs=(...args)=>{plans++;return bfs(...args);};
 advance(s,bot,1);assert.ok(bot.x>220,'bot continues approaching');assert.ok(plans<=4,`performed ${plans} route rebuilds in one second`);
});
