'use strict';
// Optional rendering-layout CPU benchmark. Results are hardware dependent.
// node src/tests/tank_labels.bench.cjs [path/to/game.js]
const {readFileSync}=require('node:fs');
const {performance}=require('node:perf_hooks');
const {assetPath}=require('./web_assets.cjs');
const source=readFileSync(process.argv[2]||assetPath('game.js'),'utf8');
const start=source.indexOf('function placeTankLabels('),end=source.indexOf('\nfunction ',start+1);
if(start<0||end<0)throw Error('Missing tank-label layout function');
const place=new Function('clamp',source.slice(start,end)+';return placeTankLabels;')((value,min,max)=>Math.max(min,Math.min(max,value)));
for(const count of [8,32,128])for(const dense of [false,true]){
 const entries=Array.from({length:count},(_,id)=>({id,local:id<2,layout:{x:0,labelY:0,labelWidth:150,labelHeight:18}}));
 const run=()=>{
  for(const entry of entries){entry.layout.x=dense?600:100+(entry.id%16)*92;entry.layout.labelY=dense?2000:50+Math.floor(entry.id/16)*95;}
  place(entries,{left:0,right:1600,top:0,bottom:4000},1);
 };
 for(let i=0;i<100;i++)run();
 const samples=[];
 for(let sample=0;sample<7;sample++){const before=performance.now();for(let i=0;i<200;i++)run();samples.push((performance.now()-before)/200);}
 samples.sort((a,b)=>a-b);
 console.log(JSON.stringify({labels:count,dense,medianMs:samples[3],minMs:samples[0],maxMs:samples.at(-1)}));
}
