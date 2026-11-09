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
