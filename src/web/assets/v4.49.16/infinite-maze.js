(() => {
'use strict';
const CELL=84, WALL=8, CHUNK=8, CACHE_SIZE=128, NORTH=1, WEST=2;

// Keep the hash, PRNG and chunk generation in sync with infinite_maze.go.
function chunkHash(seed,x,y,salt){
 let n=seed^Math.imul(x,0x9e3779b1)^Math.imul(y,0x85ebca77)^salt;
 n=Math.imul(n^(n>>>16),0x7feb352d);
 n=Math.imul(n^(n>>>15),0x846ca68b);
 return (n^(n>>>16))>>>0;
}

function makeChunk(seed,cx,cy){
 const walls=new Uint8Array(CHUNK*CHUNK).fill(NORTH|WEST);
 let state=chunkHash(seed,cx,cy,0x243f6a88)||1;
 function next(){
  state^=state<<13;
  state^=state>>>17;
  state^=state<<5;
  return state>>>0;
 }
 const start=next()%walls.length, stack=[start], visited=new Uint8Array(walls.length), neighbors=[];
 visited[start]=1;
 while(stack.length){
  const cell=stack[stack.length-1], x=cell%CHUNK, y=Math.floor(cell/CHUNK);
  neighbors.length=0;
  if(y>0&&!visited[cell-CHUNK])neighbors.push(cell-CHUNK);
  if(x+1<CHUNK&&!visited[cell+1])neighbors.push(cell+1);
  if(y+1<CHUNK&&!visited[cell+CHUNK])neighbors.push(cell+CHUNK);
  if(x>0&&!visited[cell-1])neighbors.push(cell-1);
  if(!neighbors.length){stack.pop();continue;}
  const neighbor=neighbors[next()%neighbors.length];
  switch(neighbor-cell){
   case -CHUNK: walls[cell]&=~NORTH; break;
   case 1: walls[neighbor]&=~WEST; break;
   case CHUNK: walls[neighbor]&=~NORTH; break;
   case -1: walls[cell]&=~WEST; break;
  }
  visited[neighbor]=1;
  stack.push(neighbor);
 }
 for(let i=0;i<walls.length;i++){
  if(i>=CHUNK&&(walls[i]&NORTH)&&next()%5===0)walls[i]&=~NORTH;
  if(i%CHUNK&&(walls[i]&WEST)&&next()%5===0)walls[i]&=~WEST;
 }
 // Each chunk owns its north and west edges, with two openings per edge.
 const north=chunkHash(seed,cx,cy,0xb7e15162), west=chunkHash(seed,cx,cy,0x8aed2a6b);
 walls[1+north%3]&=~NORTH;
 walls[4+(north>>>16)%3]&=~NORTH;
 walls[(1+west%3)*CHUNK]&=~WEST;
 walls[(4+(west>>>16)%3)*CHUNK]&=~WEST;
 return walls;
}

function create(seed){
 const cache=new Map();
 function chunk(cx,cy){
  const key=`${cx},${cy}`;
  let walls=cache.get(key);
  if(!walls){
   walls=makeChunk(seed,cx,cy);
   if(cache.size===CACHE_SIZE)cache.delete(cache.keys().next().value);
   cache.set(key,walls);
  }
  return walls;
 }
 function visitWalls(x0,y0,x1,y1,visit){
  if(!Number.isFinite(x0)||!Number.isFinite(y0)||!Number.isFinite(x1)||!Number.isFinite(y1)||x0>x1||y0>y1)return false;
  const halfWall=WALL/2;
  const firstX=Math.ceil((x0-halfWall)/CELL)-1, lastX=Math.floor((x1+halfWall)/CELL);
  const firstY=Math.ceil((y0-halfWall)/CELL)-1, lastY=Math.floor((y1+halfWall)/CELL);
  const lastChunkX=Math.floor(lastX/CHUNK), lastChunkY=Math.floor(lastY/CHUNK);
  function visitWall(x,y,w,h,axis,line){
   return x<=x1&&x+w>=x0&&y<=y1&&y+h>=y0&&visit(x,y,w,h,axis,line);
  }
  for(let cy=Math.floor(firstY/CHUNK);cy<=lastChunkY;cy++){
   const baseY=cy*CHUNK;
   for(let cx=Math.floor(firstX/CHUNK);cx<=lastChunkX;cx++){
    const baseX=cx*CHUNK, edges=chunk(cx,cy);
    for(let y=Math.max(firstY,baseY);y<=Math.min(lastY,baseY+CHUNK-1);y++){
     for(let x=Math.max(firstX,baseX);x<=Math.min(lastX,baseX+CHUNK-1);x++){
      const walls=edges[(y-baseY)*CHUNK+x-baseX], wx=x*CELL, wy=y*CELL;
      if((walls&NORTH)&&visitWall(wx-halfWall,wy-halfWall,CELL+WALL,WALL,'h',wy))return true;
      if((walls&WEST)&&visitWall(wx-halfWall,wy-halfWall,WALL,CELL+WALL,'v',wx))return true;
     }
    }
   }
  }
  return false;
 }
 function wallsNear(x0,y0,x1,y1){
  const walls=[];
  visitWalls(x0,y0,x1,y1,(x,y,w,h,axis,line)=>{walls.push({x,y,w,h,axis,line});return false;});
  return walls;
 }
 function blocked(x,y,radius){
  // A circle tangent to a wall can move along it.
  return visitWalls(x-radius,y-radius,x+radius,y+radius,(wx,wy,w,h)=>{
   const dx=x-Math.min(Math.max(x,wx),wx+w), dy=y-Math.min(Math.max(y,wy),wy+h);
   return dx*dx+dy*dy<radius*radius;
  });
 }
 return {visitWalls,wallsNear,blocked};
}

window.leqraInfiniteMaze=Object.freeze({create,cellSize:CELL});
})();
