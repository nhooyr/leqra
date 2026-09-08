'use strict';
const {performance}=require('node:perf_hooks'),{boot}=require('./chat442-harness.cjs');
const results=[];let checksum=0;
for(const perChannel of [0,10,60]){
 const b=boot({perChannel}),samples=[],iterations=40;
 for(let sample=0;sample<10;sample++){
  const start=performance.now();for(let n=0;n<iterations;n++){b.renderActiveChat();checksum+=b.list.children.length;}
  if(sample>=3)samples.push((performance.now()-start)/iterations);
 }
 samples.sort((a,b)=>a-b);results.push({messages:perChannel*2,iterationsPerSample:iterations,samples:samples.length,medianMs:+samples[Math.floor(samples.length/2)].toFixed(4)});
}
console.log(JSON.stringify({runtime:process.version,scope:'Production chat history rendering with native Intl timestamp formatting and a lightweight DOM stand-in; excludes browser layout/paint and whole game FPS.',checksum,results},null,2));
