'use strict';
const assert=require('node:assert/strict'),{readFileSync}=require('node:fs'),path=require('node:path');
function declaration(source,name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function random(seed=439){return()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};}
function boot({sourcePath=process.env.LEQRA_SPATIAL_SOURCE||path.join(__dirname,'../web/game.js'),cols=24,rows=14,seed=439,exhaustive=false}={}){
 const source=readFileSync(sourcePath,'utf8'),math=Object.create(Math);math.random=random(seed);
 const env={Math:math,cols,rows,W:cols*84,H:rows*84,CELL:84,WALL:8,grid:[],walls:[],wallIndex:null,mapDimensions:()=>[cols,rows],cacheMap(){},resize(){},clamp:(v,a,b)=>Math.max(a,Math.min(b,v))};
 const declarations=['makeMaze','nearbyWalls','rayWalls','wallBetweenCenters'].map(n=>declaration(source,n));
 if(exhaustive)declarations[1]='function nearbyWalls(){return walls;}';
 const factory=new Function('env','let {'+Object.keys(env).join(',')+'}=env;\n'+declarations.join('\n')+'\nmakeMaze();return{nearbyWalls,rayWalls,wallBetweenCenters,get walls(){return walls;},get grid(){return grid;},get index(){return wallIndex;},replaceWorld(value,c=cols,r=rows){walls=value;cols=c;rows=r;W=cols*CELL;H=rows*CELL;}};');
 return factory(env);
}
function queries(kind,cols=24,rows=14,count=2048){
 const rand=random(439000+kind.length),W=cols*84,H=rows*84,out=[];
 for(let i=0;i<count;i++){
  const x=10+rand()*(W-20),y=10+rand()*(H-20);
  if(kind==='movement')out.push([x,y,(rand()-.5)*10,(rand()-.5)*10,17]);
  else if(kind==='aiming')out.push([x,y,(rand()-.5)*840,(rand()-.5)*840,3.5]);
  else{const angle=rand()*Math.PI*2;out.push([x,y,Math.cos(angle)*(W+H),Math.sin(angle)*(W+H),3]);}
 }
 return out;
}
module.exports={boot,queries,random};
