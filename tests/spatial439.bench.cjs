'use strict';
const {performance}=require('node:perf_hooks'),{boot,queries}=require('./spatial439-harness.cjs');
const results=[];let checksum=0;
for(const kind of ['movement','aiming','laser'])for(const operation of ['candidates','ray']){
 const s=boot(),samples=[],qs=queries(kind),run=operation==='candidates'?(q)=>s.nearbyWalls(...q).length:(q)=>{const h=s.rayWalls(...q);return h?h.t+h.nx+h.ny:0;};
 for(let sample=0;sample<12;sample++){
  const start=performance.now();for(let n=0;n<20;n++)for(const q of qs)checksum+=run(q);
  if(sample>=5)samples.push((performance.now()-start)*1000/(20*qs.length));
 }
 samples.sort((a,b)=>a-b);results.push({kind,operation,walls:s.walls.length,queriesPerSample:qs.length*20,samples:samples.length,medianUs:+samples[Math.floor(samples.length/2)].toFixed(4)});
}
console.log(JSON.stringify({runtime:process.version,scope:'Isolated production wall-candidate and exact ray queries in a seeded Ultrawide maze; excludes whole simulation, renderer, and network. No FPS claim.',checksum,results},null,2));
