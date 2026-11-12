'use strict';
const {performance}=require('node:perf_hooks'),{boot}=require('./starman-performance-harness.cjs');
const results=[];
for(const pilots of [1,8])for(const kind of ['regular','rapid','scatter','homing','laser','cannon']){
 const fixture=boot({kind,pilots,sourcePath:process.env.LEQRA_STARMAN_SOURCE}),samples=[];
 for(let i=0;i<480;i++)fixture.step();
 for(let sample=0;sample<9;sample++){
  const started=performance.now();for(let i=0;i<480;i++)fixture.step();
  if(sample>=2)samples.push((performance.now()-started)*1000/480);
 }
 samples.sort((a,b)=>a-b);results.push({kind,pilots,medianUs:+samples[3].toFixed(3),p95Us:+samples[6].toFixed(3),...fixture.stats()});
}
console.log(JSON.stringify({runtime:process.version,scope:'Seeded Ultrawide production browser projectile firing, swept collision, trails and cosmetic generation at 120 Hz in Node/V8. All tanks protected to sustain Starman load. Excludes AI, DOM, canvas paint, audio and networking; no device FPS inference.',results},null,2));
