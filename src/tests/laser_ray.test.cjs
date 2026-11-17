'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),vm=require('node:vm');
const {assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('infinite.js'),'utf8');
function fixture(){
 const state={window:{},CELL:84};vm.createContext(state);vm.runInContext(readFileSync(assetPath('infinite-maze.js'),'utf8'),state);
 const start=source.indexOf('function wallHit('),end=source.indexOf('\nfunction canDamage',start);
 vm.runInContext(source.slice(start,end),state);return state;
}
test('nearby laser ray spans preserve the full-ray contact and normal across generated mazes',()=>{
 const s=fixture();
 for(const seed of [1,42,12345]){
  const maze=s.window.leqraInfiniteMaze.create(seed);
  for(let i=0;i<600;i++){
   const x=Math.sin(i*17.37)*1700,y=Math.cos(i*3.72)*1700,angle=i*.618,length=[0,40,168,169,420,3024][i%6];
   const args=[maze,x,y,Math.cos(angle)*length,Math.sin(angle)*length,3],expected=s.wallHit(...args),actual=s.laserWallHit(...args);
   assert.equal(!!actual,!!expected,`seed ${seed}, ray ${i}`);
   if(expected){assert.ok(Math.abs(actual.fraction-expected.fraction)<1e-6);assert.equal(actual.nx,expected.nx);assert.equal(actual.ny,expected.ny);}
  }
 }
});
test('laser span boundaries include a wall exactly at the end of a span',()=>{
 const s=fixture(),maze={visitWalls(x0,y0,x1,y1,visit){if(x0<=171&&x1>=171)visit(171,-100,8,200);}};
 for(const length of [168,169,336,3024]){
  const hit=s.laserWallHit(maze,0,0,length,0,3);assert.ok(hit);assert.ok(Math.abs(hit.fraction-168/length)<1e-12);assert.equal(hit.nx,-1);
 }
});
test('nearby laser spans preserve complete reflected paths and the full range',()=>{
 const s=fixture();
 function trace(maze,ray,x,y,angle){
  let ux=Math.cos(angle),uy=Math.sin(angle),remaining=3024;const points=[];
  for(let step=0;step<256&&remaining>1e-7;step++){
   const hit=ray(maze,x,y,ux*remaining,uy*remaining,3),length=remaining*(hit?.fraction??1);
   x+=ux*length;y+=uy*length;points.push([x,y]);remaining-=length;
   if(!hit||remaining<=1e-7)break;
   if(hit.nx)ux=-ux;if(hit.ny)uy=-uy;
   const nudge=Math.min(.001,remaining);x+=ux*nudge;y+=uy*nudge;remaining-=nudge;
  }
  return points;
 }
 for(const seed of [1,42,12345]){
  const maze=s.window.leqraInfiniteMaze.create(seed);
  for(let i=0;i<60;i++){
   const args=[Math.sin(i*17.37)*900,Math.cos(i*3.72)*900,i*.618];
   const expected=trace(maze,s.wallHit,...args),actual=trace(maze,s.laserWallHit,...args);
   assert.equal(actual.length,expected.length);
   for(let n=0;n<actual.length;n++)assert.ok(Math.hypot(actual[n][0]-expected[n][0],actual[n][1]-expected[n][1])<1e-5,`seed ${seed}, ray ${i}, bounce ${n}`);
  }
 }
});
