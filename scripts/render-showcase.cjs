'use strict';
// Reproducible staged arena capture, using the shipped game's maze, collision
// and drawing functions unchanged. Requires @napi-rs/canvas for offscreen Canvas.
// Run: NODE_PATH=/path/to/node_modules node scripts/render-showcase.cjs
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {createCanvas}=require('@napi-rs/canvas');
const {boot,tank,declaration}=require('../src/tests/godlike426-harness.cjs');
const root=path.join(__dirname,'..'),source=fs.readFileSync(path.join(root,'src/web/game.js'),'utf8');
let seed=14383;const random=()=>{seed|=0;seed=seed+0x6d2b79f5|0;let t=Math.imul(seed^seed>>>15,1|seed);t^=t+Math.imul(t^t>>>7,61|t);return((t^t>>>14)>>>0)/4294967296;};
const canvas=createCanvas(3120,1860),ctx=canvas.getContext('2d');
const s=boot({cols:24,rows:14}),math=Object.create(Math);math.random=random;
Object.assign(s,{Math:math,rnd:(a,b)=>a+(b-a)*random(),canvas,ctx,cssW:2080,cssH:1240,dpr:1.5,scale:1,offsetX:32,offsetY:32,fxTime:8.42,time:18.42,shake:0,particles:[],rings:[],traces:[],mapCanvas:null,
 combatPrefs:{performance:false,visual:true},WEBKIT_ENGINE:false,touchUI:false,reduceMotion:false,guideEnabled:false,pausedFrom:'playing',localPlayerID:()=>0,secondaryID:()=>undefined,isSpectating:()=>false,survivalBreak:()=>false,controlledTank:()=>s.tanks[0],
 resize(){},mapDimensions:()=>[24,14],objectiveMode:()=>false,objectiveState:()=>null,survivalMode:()=>false,
 tone(){},boom(){},shotSound(){},eventShake(){},
 document:{createElement:()=>createCanvas(64,64),documentElement:{dataset:{},style:{}},querySelector:()=>null},window:{},
 currentRules:()=>({mode:'elimination',mapSize:'ultrawide',teamMode:'ffa',friendlyFire:false}),
});
vm.runInContext(fs.readFileSync(path.join(root,'src/web/theme.js'),'utf8'),s);s.theme=s.window.leqraTheme.palette;s.paintColor=s.window.leqraTheme.assetColor;s.Theme=s.window.leqraTheme;
vm.runInContext(source.split('\n').find(line=>line.startsWith('for(const [kind,def] of Object.entries(POWER))')),s);
vm.runInContext('this.powerDefs=POWER;',s);
vm.runInContext(source.slice(source.indexOf('const tankHullCache='),source.indexOf('function guideInk(')),s);
vm.runInContext(source.slice(source.indexOf('const tankPowerBadgeCache='),source.indexOf('function activeTankPowerBadges(')),s);
for(const name of ['roundRect','makeMaze','cacheMap','syncCanvasSize','measureLabel','paintTankHull','drawCachedTankHull','activeTankPowerBadges','tankPowerBadgeImage','tankStatusLayout','tankPowerBadgePositions','powerExpiryAlpha','tankPowerBadgeLife','tankPowerBadgeCount','drawTankPowerBadgeCount','drawTankPowerBadges','protectionRingAlpha','localSpawnGuideAlpha','drawLocalSpawnGuide','drawTankLabel','drawTank','powerIcon','drawPickup','drawBullet','drawLasers','drawObjectives','drawFlags','drawAimingGuides','drawMissileWarnings','missileLocks','render','burst','addRing','laserEffect','blastEffect','projectOnlineBullet'])vm.runInContext(declaration(name),s);
s.makeMaze();
const colors=['#d2f65a','#ff9679','#73cee4','#c5a2ff','#ffc46b','#ff83bd','#75f0cb','#b7c6ee'];
const names=['YOU','RUST','VAPOR','PHANTOM','EMBER','NOVA','BLITZ','ORBIT'];
const cells=[[5.5,6.5],[10.5,4.5],[16.5,7.5],[19.5,10.5],[8.5,10.5],[19.5,3.5],[3.5,3.5],[12.5,2.5]];
s.tanks=cells.map(([x,y],i)=>tank(i,x*84,y*84,{name:names[i],color:colors[i],team:0,human:i===0,track:i*7+3,recoil:0,spawnProtected:false}));
Object.assign(s.tanks[0],{power:'laser',powerTime:11.5,charges:2,shield:8.8,shieldCharges:2});
Object.assign(s.tanks[1],{power:'scatter',powerTime:10.6,charges:3,shield:8.4,shieldCharges:3});
Object.assign(s.tanks[2],{power:'cannon',powerTime:12.4,charges:2,angle:-2.65,speedTime:9.6,speedStacks:2});
Object.assign(s.tanks[3],{power:'cannon',powerTime:9.2,charges:1,angle:-2.42,ghostTime:11.4,speedTime:7.1,speedStacks:2});
Object.assign(s.tanks[4],{power:'grenade',powerTime:8.3,charges:1,angle:-.5,shield:10.5,shieldCharges:1});
Object.assign(s.tanks[5],{power:'homing',powerTime:9.7,charges:1,angle:2.6,speedTime:8.5,speedStacks:1});
Object.assign(s.tanks[6],{power:'rapid',powerTime:10.8,machineRounds:117,angle:.2,speedTime:12.3,speedStacks:3});
Object.assign(s.tanks[7],{power:'laser',powerTime:12,charges:2,angle:1.8,ghostTime:8.5});
const clear=(x,y,r=24)=>x>r&&x<s.W-r&&y>r&&y<s.H-r&&s.walls.every(w=>Math.hypot(x-Math.max(w.x,Math.min(w.x+w.w,x)),y-Math.max(w.y,Math.min(w.y+w.h,y)))>r);
// Choose a legal multi-bounce beam that ends at a shielded tank. Its path comes
// directly from laserTrace, and no wall or projectile rules are changed.
const hero=s.tanks[0],victim=s.tanks[1],all=s.tanks;s.tanks=[hero];let best=null;
for(let i=0;i<360;i++){
 const angle=i/360*Math.PI*2,beam=s.laserTrace(hero,angle);
 for(let n=4;n<Math.min(10,beam.points.length);n++){
  const a=beam.points[n-1],b=beam.points[n],x=(a.x+b.x)/2,y=(a.y+b.y)/2;
  if(!clear(x,y)||all.filter(t=>t!==victim).some(t=>Math.hypot(t.x-x,t.y-y)<140))continue;
  const p=beam.points.slice(0,n).concat({x,y}),width=Math.max(...p.map(q=>q.x))-Math.min(...p.map(q=>q.x)),height=Math.max(...p.map(q=>q.y))-Math.min(...p.map(q=>q.y));
  const score=width+height*.9-n*18;if(!best||score>best.score)best={score,angle,x,y};
 }
}
s.tanks=all;if(!best)throw Error('No showcase laser route');Object.assign(hero,{angle:best.angle,recoil:.8});Object.assign(victim,{x:best.x,y:best.y,angle:best.angle+Math.PI});
let beam=s.laserTrace(hero);s.laserEffect(beam.x,beam.y,beam.endX,beam.endY,s.powerDefs.laser.color,beam.points);s.addRing(victim.x,victim.y,s.powerDefs.shield.color,58);s.burst(victim.x,victim.y,s.powerDefs.shield.color,28,160);
// Scatter pickups through the actual maze, away from the featured tanks.
const kinds=Object.keys(s.powerDefs),slots=[];for(let y=1;y<13;y++)for(let x=1;x<23;x++)if((x*5+y*7)%11===0)slots.push({x:(x+.5)*84,y:(y+.5)*84});
for(const p of slots)if(s.tanks.every(t=>Math.hypot(t.x-p.x,t.y-p.y)>105))s.pickups.push({...p,id:s.pickups.length+1,type:kinds[(s.pickups.length*3+2)%kinds.length],life:25+s.pickups.length,age:5});
// Real projectile projection supplies wall reflections and grenade drag. The
// full launch-to-current path is sampled only for the normal trail renderer.
let nextID=0;
function shell(owner,kind,age,angle=s.tanks[owner].angle){
 const t=s.tanks[owner],copy={...t,power:kind,angle},b=s.muzzleProjectile(copy,angle);if(b.dead||b.launchHit!==undefined)return;
 b.id=++nextID;b.trail=[];const steps=10,start=Math.max(0,age-10/60);
 for(let i=0;i<=steps;i++){const q={...b};let remaining=start+(age-start)*i/steps,state=q;while(remaining>0){const dt=Math.min(.1,remaining);state=s.projectOnlineBullet(state,dt,.1);remaining-=dt;}b.trail.push({x:state.x,y:state.y});if(i===steps)Object.assign(b,state);}
 b.trail=b.trail.length?b.trail:[];s.bullets.push(b);s.burst(t.x+Math.cos(angle)*28,t.y+Math.sin(angle)*28,t.color,6,70);
}
shell(2,'cannon',.29);shell(3,'cannon',.18);shell(4,'grenade',.68);shell(4,'grenade',1.12,-1.4);shell(5,'homing',.52);shell(5,'homing',1.08,2.85);
for(const age of [.05,.1,.15,.2,.25,.3])shell(6,'rapid',age,.21);
// A second laser has a longer-range ricochet, faded slightly behind the main
// shield impact. Choose a low-complexity path so individual beams stay readable.
const second=s.tanks[7];let secondBeam=null;
for(let i=0;i<180;i++){const a=i/180*Math.PI*2,b=s.laserTrace(second,a);if(b.points.length>=4&&b.points.length<=17&&(!secondBeam||b.points.length<secondBeam.points.length)){second.angle=a;secondBeam=b;}}
if(secondBeam){s.laserEffect(secondBeam.x,secondBeam.y,secondBeam.endX,secondBeam.endY,s.powerDefs.laser.color,secondBeam.points);s.traces.at(-1).life=.13;}
// Expand genuine impact particles to capture a lively instant after contact.
for(const p of s.particles){const dt=.07+random()*.09;p.x+=p.vx*dt;p.y+=p.vy*dt;p.life=Math.max(.03,p.life-dt);}
for(const r of s.rings)r.life=.28;
s.render();
const out=path.join(root,'docs/screenshot.png');fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,canvas.toBuffer('image/png'));
console.log(JSON.stringify({output:path.relative(root,out),width:canvas.width,height:canvas.height,maze:[s.cols,s.rows],tanks:s.tanks.length,teams:s.tanks.map(t=>t.team),effects:{ghost:s.tanks.filter(t=>t.ghostTime>0).length,speed:s.tanks.filter(t=>t.speedTime>0).length,shield:s.tanks.filter(t=>t.shield>0).length},powerups:s.pickups.length,projectiles:s.bullets.map(b=>b.kind),laserSegments:s.traces.map(t=>t.points.length-1),renderer:'unmodified production Canvas functions; deliberately staged scene'},null,2));
