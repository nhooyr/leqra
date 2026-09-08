'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path');
const {boot,tank,bullet,declaration}=require('./godlike426-harness.cjs');
function riskFor(s,t,control,segments,horizon=1.05){return s.movementRisk(t,control.angle,control.drive,s.tune.godlike,segments,horizon).risk;}

test('Godlike is selectable everywhere and adds decision skill without extra hull speed',()=>{
 const s=boot(),html=readFileSync(path.join(__dirname,'../web/index.html'),'utf8');
 assert.equal(s.tune.godlike.speed,s.tune.hard.speed);assert.equal(s.tune.godlike.turn,s.tune.hard.turn);
 assert.ok(s.tune.godlike.think<s.tune.hard.think);assert.ok(s.tune.godlike.aim<s.tune.hard.aim);
 assert.match(html,/data-difficulty="godlike"/);
 assert.match(declaration('makeRoomPlayerRow'),/\['godlike','Godlike'\]/);
});
test('Godlike flees an enemy remote grenade before its long fuse expires',()=>{
 const s=boot(),t=tank(0,400,336),enemy=tank(1,750,336);s.tanks=[t,enemy];s.bullets=[bullet(1,250,336)];
 const base={angle:Math.PI,drive:1},segments=s.godlikeGrenadeThreats(t,s.tune.godlike,1.05,s.bullets),dodge=s.godlikeDodge(t,base,s.tune.godlike);
 assert.ok(segments.some(v=>v.remote));assert.ok(riskFor(s,t,dodge,segments)<riskFor(s,t,base,segments));
});
test('Godlike escapes its own expiring grenade without treating safe friendly grenades as threats',()=>{
 const s=boot(),t=tank(0,400,336);s.tanks=[t,tank(1,800,500,{team:1})];s.bullets=[bullet(0,250,336,'grenade',{life:.9})];
 const base={angle:Math.PI,drive:1},segments=s.godlikeGrenadeThreats(t,s.tune.godlike,1.05,s.bullets),dodge=s.godlikeDodge(t,base,s.tune.godlike);
 assert.ok(riskFor(s,t,dodge,segments)<riskFor(s,t,base,segments));
 s.bullets=[bullet(1,250,336)];assert.deepEqual(s.godlikeDodge(t,base,s.tune.godlike),base);
});
test('maze walls shelter a Godlike bot from a remote grenade blast',()=>{
 const s=boot({wallList:[{x:300,y:100,w:8,h:450,axis:'v'}]}),t=tank(0,400,336);s.tanks=[t,tank(1,220,336)];s.bullets=[bullet(1,250,336)];
 const segments=s.godlikeGrenadeThreats(t,s.tune.godlike,1.05,s.bullets);
 assert.equal(riskFor(s,t,{angle:0,drive:0},segments),0);
});
test('grenade detonation checks every owned grenade and avoids self or enabled teammate damage',()=>{
 const s=boot(),t=tank(0,100,100),enemy=tank(1,500,100),ally=tank(2,750,100,{team:1});s.tanks=[t,enemy,ally];
 s.bullets=[bullet(0,480,100),bullet(0,110,100)];assert.equal(s.godlikeDetonate(t),false);assert.equal(s.bullets[0].dead,false);
 s.bullets.pop();assert.equal(s.godlikeDetonate(t),true);
 s.bullets=[bullet(0,480,100)];ally.x=500;s.friendlyFire=true;assert.equal(s.godlikeDetonate(t),false);
 s.friendlyFire=false;assert.equal(s.godlikeDetonate(t),true);
});
test('Godlike throws safe grenades at useful range and rejects close-contact self blasts',()=>{
 const s=boot(),t=tank(0,100,336,{power:'grenade',charges:3}),enemy=tank(1,480,336);s.tanks=[t,enemy];
 assert.ok(s.evaluateBotShot(t,0,enemy,s.tune.godlike));enemy.x=195;assert.equal(s.evaluateBotShot(t,0,enemy,s.tune.godlike),null);
});
test('harmless teammates still trigger grenade contact blasts, so Godlike avoids unsafe throws',()=>{
 const s=boot(),t=tank(0,100,336,{power:'grenade',charges:3}),enemy=tank(1,480,336),ally=tank(2,190,336,{team:1});s.tanks=[t,enemy,ally];
 assert.equal(s.evaluateBotShot(t,0,enemy,s.tune.godlike),null);
});
test('Godlike seeks useful reachable pickups and avoids remote-grenade bait',()=>{
 const s=boot(),t=tank(0,126,126),enemy=tank(1,714,126);s.tanks=[t,enemy];
 const shield={x:210,y:126,type:'shield',life:30},scope={x:126,y:210,type:'scope',life:30};s.pickups=[scope,shield];
 assert.equal(s.godlikeDestination(t,enemy,null,s.tune.godlike),shield);
 s.bullets=[bullet(1,250,126)];assert.equal(s.godlikeDestination(t,enemy,null,s.tune.godlike),enemy);
 s.bullets=[];s.grid[s.cellAt(shield.x,shield.y)].neighbors=[];for(const cell of s.grid)cell.neighbors=cell.neighbors.filter(i=>i!==s.cellAt(shield.x,shield.y));
 assert.notEqual(s.godlikeDestination(t,enemy,null,s.tune.godlike),shield);
});
test('Godlike does not replace a strong healthy weapon with a weak redundant pickup',()=>{
 const s=boot(),t=tank(0,126,126,{power:'cannon',powerTime:8,charges:3});
 assert.equal(s.godlikePickupValue(t,{type:'grenade'}),0);
 assert.ok(s.godlikePickupValue(t,{type:'shield'})>s.godlikePickupValue(t,{type:'scope'}));
});
test('CTF Godlike returns its carried flag and recovers a dropped own flag first',()=>{
 const s=boot(),t=tank(0,378,294),enemy=tank(1,798,126);s.tanks=[t,enemy];
 const own={team:1,x:126,y:546,homeX:126,homeY:546,home:true,carrier:-1},other={team:2,x:t.x,y:t.y,homeX:882,homeY:126,home:false,carrier:t.id};s.localObjectives={mode:'ctf',flags:[own,other]};
 let goal=s.godlikeObjectiveGoal(t);assert.equal(goal.x,own.homeX);assert.equal(goal.y,own.homeY);
 own.home=false;own.x=210;own.y=462;goal=s.godlikeObjectiveGoal(t);assert.equal(goal.x,own.x);assert.equal(goal.y,own.y);
});
test('one-on-one CTF carriers intercept instead of waiting forever at their home bases',()=>{
 const s=boot(),t=tank(0,378,294),enemy=tank(1,798,126);s.tanks=[t,enemy];
 s.localObjectives={mode:'ctf',flags:[{team:1,x:enemy.x,y:enemy.y,homeX:126,homeY:546,home:false,carrier:1},{team:2,x:t.x,y:t.y,homeX:882,homeY:126,home:false,carrier:0}]};
 const goal=s.godlikeObjectiveGoal(t);assert.equal(goal.x,enemy.x);assert.equal(goal.y,enemy.y);
});
test('KOTH Godlike stays on a scoring hill and declines pickup distractions',()=>{
 const s=boot(),t=tank(0,378,294),enemy=tank(1,440,294);s.tanks=[t,enemy];s.localObjectives={mode:'koth',hillX:378,hillY:294,radius:32,flags:[]};
 const objective=s.godlikeObjectiveGoal(t);s.pickups=[{x:462,y:294,type:'shield',life:30}];assert.equal(s.godlikeDestination(t,enemy,objective,s.tune.godlike),objective);
 for(let i=0;i<120;i++)s.botControl(t,1/120);
 assert.ok(Math.hypot(t.x-378,t.y-294)<29,'shoots while remaining in scoring radius');
});
test('guided missile prediction follows candidate motion and never mutates live state',()=>{
 const s=boot(),t=tank(0,400,336,{angle:Math.PI/2}),enemy=tank(1,800,336);s.tanks=[t,enemy];
 const missile=bullet(1,160,336,'homing',{vx:235,vy:0,target:0}),before=JSON.stringify([s.tanks,missile]);
 const stationary=Array.from({length:9},()=>({x:t.x,y:t.y})),running=Array.from({length:9},(_,i)=>({x:t.x,y:t.y+i*1.05/8*123}));
 const a=s.godlikeMissileRisk(t,s.tune.godlike,stationary,[missile],1.05),b=s.godlikeMissileRisk(t,s.tune.godlike,running,[missile],1.05);
 assert.ok(a>0);assert.ok(b<a);assert.equal(JSON.stringify([s.tanks,missile]),before);
});
test('all moving projectile powers participate in Godlike defensive forecasts',()=>{
 const s=boot(),t=tank(0,400,336);s.tanks=[t,tank(1,800,336)];
 for(const [kind,vx,r]of[['bullet',282,3.5],['rapid',846,1.2],['scatter',282,3.5],['cannon',1128,14]]){
  s.bullets=[bullet(1,200,336,kind,{vx,vy:0,r})];const segments=s.forecastThreats(t,1.05,s.bullets);
  assert.ok(segments.length,kind);assert.ok(riskFor(s,t,{angle:0,drive:0},segments)>0,kind);
 }
});
test('Godlike anticipates a ready enemy laser lane but does not grant impossible reaction speed',()=>{
 const s=boot(),t=tank(0,400,336,{angle:Math.PI/2}),enemy=tank(1,100,336,{power:'laser',charges:3,angle:0});s.tanks=[t,enemy];
 const base={angle:Math.PI/2,drive:0},dodge=s.godlikeDodge(t,base,s.tune.godlike);
 assert.notEqual(dodge.drive,0);assert.equal(s.tune.godlike.turn,4.3);
});
test('Godlike begins clearing its own fuse with enough time to leave the complete blast radius',()=>{
 const s=boot(),t=tank(0,400,336);s.tanks=[t];s.bullets=[bullet(0,250,336,'grenade',{life:2.4})];
 const segments=s.godlikeGrenadeThreats(t,s.tune.godlike,1.05,s.bullets),base={angle:Math.PI,drive:1},dodge=s.godlikeDodge(t,base,s.tune.godlike);
 assert.ok(segments.length,'plans escape before the final one-second threat horizon');assert.ok(riskFor(s,t,dodge,segments)<riskFor(s,t,base,segments));
});
test('Godlike forecasts grenade contact with a harmless ally before a distant fuse',()=>{
 const s=boot(),t=tank(0,126,336),ally=tank(1,400,336,{team:1});s.tanks=[t,ally];
 const bomb=bullet(0,350,336,'grenade',{vx:205,life:5}),threats=s.godlikeGrenadeThreats(t,s.tune.godlike,1.05,[bomb]);
 assert.ok(threats.some(v=>v.blast&&!v.remote&&v.end<1),'friendly hull contact starts a real blast forecast');
});
test('boosted Godlike can forecast slow rounds reached by its own fast movement',()=>{
 const s=boot(),t=tank(0,100,336,{speedTime:8,speedStacks:5});s.tanks=[t,tank(1,800,336)];
 const b=bullet(1,450,336,'bullet',{vx:0,vy:0,r:3.5});s.bullets=[b];
 const d={...s.tune.godlike,speed:123*4.25},segments=s.forecastThreats(t,1.05,[b]);
 assert.ok(segments.length,'prefiltered Godlike threats are not discarded by the ordinary-speed cutoff');
 assert.ok(s.movementRisk(t,0,1,d,segments,1.05).risk>0);
});
test('cached single-cell wall sweeps exactly match exhaustive collision order and normals',()=>{
 const walls=[];for(let row=0;row<8;row++)for(let col=0;col<12;col++)if((row+col)%3===0)walls.push({x:col*84-4,y:row*84-4,w:8,h:92,axis:'v'});
 const indexed=boot({wallList:walls}),full=boot({wallList:walls});full.nearbyWalls=()=>walls;
 let seed=424242;const rand=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
 for(let i=0;i<600;i++){const args=[rand()*1008,rand()*672,(rand()-.5)*160,(rand()-.5)*160,rand()*18],a=indexed.rayWalls(...args),b=full.rayWalls(...args);assert.equal(a?.t,b?.t);assert.equal(a?.nx,b?.nx);assert.equal(a?.ny,b?.ny);assert.equal(a?.wall,b?.wall);}
});
