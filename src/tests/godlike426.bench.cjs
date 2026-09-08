'use strict';
const {performance}=require('node:perf_hooks');
const {boot,tank,bullet}=require('./godlike426-harness.cjs');
// Isolated Node/V8 planning workload, not browser frame time or phone FPS.
function fixture(heavy){
 const s=boot({cols:24,rows:14,lexical:true});
 for(let id=0;id<8;id++)s.tanks.push(tank(id,126+(id%4)*420,126+Math.floor(id/4)*588,{team:id%2+1,angle:id*Math.PI/4}));
 for(let row=0;row<14;row++)for(let col=0;col<24;col++){
  if(col%4===2&&row%4!==1)s.walls.push({x:(col+1)*84-4,y:row*84-4,w:8,h:92,axis:'v'});
  if(row%4===2&&col%4!==1)s.walls.push({x:col*84-4,y:(row+1)*84-4,w:92,h:8,axis:'h'});
 }
 for(let i=0;i<s.grid.length;i++){const a=s.center(i);s.grid[i].neighbors=s.grid[i].neighbors.filter(n=>{const b=s.center(n);return !s.rayWalls(a.x,a.y,b.x-a.x,b.y-a.y,18);});}
 for(let i=0;i<10;i++)s.pickups.push({x:210+(i%5)*336,y:210+Math.floor(i/5)*504,type:['shield','cannon','speed','homing','ghost'][i%5],life:30});
 if(heavy)for(let i=0;i<80;i++){const owner=i%8,origin=s.tanks[owner],kind=i%11===0?'homing':i%9===0?'grenade':i%7===0?'cannon':'rapid',speed=kind==='homing'?235:kind==='grenade'?205:kind==='cannon'?1128:846,a=i*2.399963;
  s.bullets.push(bullet(owner,s.clamp(origin.x+Math.cos(a)*150,35,s.W-35),s.clamp(origin.y+Math.sin(a)*150,35,s.H-35),kind,{vx:Math.cos(a)*speed,vy:Math.sin(a)*speed,r:kind==='cannon'?14:kind==='grenade'?6:3.5,life:3}));}
 return s;
}
const report=[];
for(const heavy of [false,true]){
 const s=fixture(heavy),samples=[];
 for(let n=0;n<45;n++){const start=performance.now();for(const t of s.tanks){t.ai.think=0;t.ai.pathClock=0;s.botControl(t,1/120);}if(n>=10)samples.push(performance.now()-start);}
 samples.sort((a,b)=>a-b);report.push({scenario:heavy?'8 Godlike bots, ultrawide maze, 80 mixed projectiles':'8 Godlike bots, ultrawide maze, no projectiles',measuredBatches:samples.length,meanMs:+(samples.reduce((a,b)=>a+b)/samples.length).toFixed(3),medianMs:+samples[Math.floor(samples.length/2)].toFixed(3),p95Ms:+samples[Math.floor(samples.length*.95)].toFixed(3)});
}
console.log(JSON.stringify({runtime:process.version,scope:'Forced full AI decisions and route rebuilds for all eight bots in Node/V8; excludes browser rendering and live physics.',results:report},null,2));
