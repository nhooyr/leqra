'use strict';
const {test}=require('node:test'), assert=require('node:assert/strict'), vm=require('node:vm');
const {createHash}=require('node:crypto');
const {readFileSync}=require('node:fs');
const {assetPath}=require('./web_assets.cjs');
const fixtures=require('./fixtures/infinite-maze.json');
const sandbox={window:{}};
vm.runInNewContext(readFileSync(assetPath('infinite-maze.js'),'utf8'),sandbox);
const {create,cellSize}=sandbox.window.leqraInfiniteMaze;

test('Infinity walls match the Go geometry across signed chunk boundaries',()=>{
 for(const {seed,bounds,count,sha256} of fixtures){
  const walls=create(seed).wallsNear(...bounds);
  assert.equal(walls.length,count,`seed ${seed} and bounds ${bounds}`);
  assert.equal(createHash('sha256').update(JSON.stringify(walls)).digest('hex'),sha256,`seed ${seed} and bounds ${bounds}`);
 }
});

test('Infinity walls allow tangency and regenerate after distant exploration',()=>{
 const maze=create(32), chunkSize=8*cellSize, edge=-chunkSize, x=edge+cellSize/2;
 const radius=17, tangentY=edge-4-radius;
 assert.equal(maze.blocked(x,tangentY,radius),false);
 assert.equal(maze.blocked(x,tangentY+.01,radius),true);
 const walls=maze.wallsNear(x,edge,x,edge);
 assert.equal(walls.length,1);
 assert.equal(walls[0].line,edge);
 assert.equal(walls[0].axis,'h');
 for(let i=1;i<=256;i++)maze.wallsNear(i*chunkSize,0,i*chunkSize,0);
 assert.deepEqual(maze.wallsNear(x,edge,x,edge),walls);
});

test('Infinity wall visits include rectangles tangent to the query and can stop early',()=>{
 const maze=create(32),edge=-8*cellSize;
 const wall=maze.wallsNear(edge+cellSize/2,edge,edge+cellSize/2,edge)[0];
 assert.equal(wall.axis,'h');
 const x=wall.x+wall.w, y=wall.y+wall.h/2;
 let visits=0;
 assert.equal(maze.visitWalls(x,y,x,y,(wx,wy,w,h)=>{
  visits++;
  return wx===wall.x&&wy===wall.y&&w===wall.w&&h===wall.h;
 }),true);
 assert.ok(visits>0);
 assert.equal(maze.wallsNear(x+.001,y,x+.001,y).some(w=>w.x===wall.x&&w.y===wall.y&&w.axis===wall.axis),false);
 visits=0;
 assert.equal(maze.visitWalls(edge,edge,edge+cellSize*4,edge+cellSize*4,()=>++visits===1),true);
 assert.equal(visits,1);
});
