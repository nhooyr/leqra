'use strict';
const {performance}=require('node:perf_hooks'),{boot}=require('./hud438-harness.cjs');
const results=[],fixtures=[];
for(const mode of ['room','online'])for(const projectileCount of [32,192,768]){
 const s=boot({mode,projectileCount}),samples=[],iterations=5000;
 for(let run=0;run<12;run++){
  const start=performance.now();for(let n=0;n<iterations;n++)s.run();
  if(run>=5)samples.push((performance.now()-start)*1000/iterations);
 }
 samples.sort((a,b)=>a-b);
 results.push({mode,projectiles:projectileCount,medianUs:+samples[Math.floor(samples.length/2)].toFixed(3),samples:7});fixtures.push(s);
}
// Instrument only after every timing sample: indexed accessors otherwise
// deoptimize V8's shared array-read feedback for later benchmark cases.
for(let i=0;i<fixtures.length;i++){const s=fixtures[i];let reads=0;for(let n=0;n<s.bullets.length;n++){const b=s.bullets[n];Object.defineProperty(s.bullets,n,{get(){reads++;return b;}});}s.run();results[i].projectileReads=reads;}
console.log(JSON.stringify({runtime:process.version,scope:'Production two-pilot loadout and combat-feedback refresh functions in Node/V8 with a lightweight DOM stand-in. Excludes browser layout, paint, and simulation; no FPS inference.',results},null,2));
