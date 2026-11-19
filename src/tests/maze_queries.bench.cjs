'use strict';
// node src/tests/maze_queries.bench.cjs [path/to/infinite-maze.js]
// Deterministic geometry CPU only; does not measure browser or device FPS.
const fs=require('node:fs'),vm=require('node:vm'),{performance}=require('node:perf_hooks'),{assetPath}=require('./web_assets.cjs');
const context={window:{}};vm.runInNewContext(fs.readFileSync(process.argv[2]||assetPath('infinite-maze.js'),'utf8'),context);
const results=[];
for(const cold of [false,true]){
 const samples=[];let checksum=0;
 const count=cold?1024:16384;
 for(let sample=0;sample<9;sample++){
  const maze=context.window.leqraInfiniteMaze.create(42),start=performance.now();
  for(let i=0;i<count;i++){
   const x=cold?i*672:42+(i%21)*83.25,y=cold?0:42+(i%11)*83.5;
   maze.visitWalls(x-4,y-4,x+84,y+84,(wx,wy,w,h)=>{checksum=(Math.imul(checksum,31)+wx+wy+w+h)|0;return false;});
  }
  if(sample>=2)samples.push((performance.now()-start)*1e6/count);
 }
 samples.sort((a,b)=>a-b);results.push({case:cold?'cold-chunks':'nearby-wall-queries',nsPerQuery:samples[3],p95:samples[6],checksum});
}
console.log(JSON.stringify({runtime:process.version,scope:'Seeded production Infinity maze traversal, preserving wall order. CPU only.',results},null,2));
