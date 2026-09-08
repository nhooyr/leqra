'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),{boot,queries,random}=require('./spatial439-harness.cjs');
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
function expectedCandidates(walls,q,cols,rows){
 if(walls.length<24)return walls;
 const [x,y,dx,dy,r]=q,x0=clamp(Math.floor((Math.min(x,x+dx)-r)/84),0,cols-1),x1=clamp(Math.floor((Math.max(x,x+dx)+r)/84),0,cols-1),y0=clamp(Math.floor((Math.min(y,y+dy)-r)/84),0,rows-1),y1=clamp(Math.floor((Math.max(y,y+dy)+r)/84),0,rows-1);
 if((x1-x0+1)*(y1-y0+1)>cols*rows/3)return walls;
 // Independent interval-overlap oracle: filter the original wall order without
 // gathering bins, stamps, sorting candidates, or using bit operations.
 return walls.filter(w=>clamp(Math.floor(w.x/84),0,cols-1)<=x1&&clamp(Math.floor((w.x+w.w)/84),0,cols-1)>=x0&&clamp(Math.floor(w.y/84),0,rows-1)<=y1&&clamp(Math.floor((w.y+w.h)/84),0,rows-1)>=y0);
}
function equalOrder(actual,expected){assert.equal(actual.length,expected.length);for(let i=0;i<actual.length;i++)assert.equal(actual[i],expected[i],`wall order/identity at ${i}`);}

test('wall candidates preserve exhaustive ordered membership on all six maze sizes',()=>{
 for(const [cols,rows] of [[7,7],[9,8],[12,10],[14,12],[16,14],[24,14]]){
  const s=boot({cols,rows});for(const kind of ['movement','aiming','laser'])for(const q of queries(kind,cols,rows,400))equalOrder(s.nearbyWalls(...q),expectedCandidates(s.walls,q,cols,rows));
 }
});

test('ray hit time, corner normals and winning wall identity exactly match exhaustive sweeps',()=>{
 for(const [cols,rows] of [[7,7],[12,10],[24,14]]){
  const indexed=boot({cols,rows}),full=boot({cols,rows,exhaustive:true});full.replaceWorld(indexed.walls);
  for(const kind of ['movement','aiming','laser'])for(const q of queries(kind,cols,rows,450)){
   assert.deepEqual(indexed.rayWalls(...q),full.rayWalls(...q),`${cols}x${rows} ${kind} ${q}`);
   assert.equal(indexed.wallBetweenCenters(...q.slice(0,4)),full.wallBetweenCenters(...q.slice(0,4)));
  }
 }
});

test('bit 31 and later words retain ordered duplicate-free candidates and exact corner ties',()=>{
 const s=boot({cols:24,rows:14}),walls=[];
 for(let i=0;i<130;i++)walls.push({x:84+(i%3)*84,y:84+Math.floor(i/20)*84,w:i%2?8:92,h:i%2?92:8,axis:i%2?'v':'h'});
 s.replaceWorld(walls);
 for(const q of [[80,80,280,570,3],[80,80,100,100,17],[90,90,-120,-120,0],[164,164,168,168,3.5]])equalOrder(s.nearbyWalls(...q),expectedCandidates(walls,q,24,14));
 // Walls spanning several bins appear once, even across the signed high bit.
 const all=s.nearbyWalls(80,80,280,570,3);assert.ok(all.includes(walls[31])&&all.includes(walls[32])&&all.includes(walls[63])&&all.includes(walls[127]));assert.equal(new Set(all).size,all.length);
 const full=boot({exhaustive:true});full.replaceWorld(walls);assert.deepEqual(s.rayWalls(40,40,200,200,3),full.rayWalls(40,40,200,200,3));
});

test('successive multi-cell queries clear previous candidates and preserve one-cell fast paths',()=>{
 const s=boot(),walls=Array.from({length:80},(_,i)=>({x:80+(i%4)*84,y:80+Math.floor(i/4)*8,w:8,h:92}));s.replaceWorld(walls);
 const fullQuery=[70,70,360,250,3],emptyQuery=[1000,700,100,100,3];
 for(let n=0;n<20;n++){
  equalOrder(s.nearbyWalls(...fullQuery),expectedCandidates(walls,fullQuery,24,14));assert.deepEqual(s.nearbyWalls(...emptyQuery),[]);
  const a=s.nearbyWalls(42,42,1,1,0),b=s.nearbyWalls(43,43,1,1,0);assert.equal(a,b,'the immutable one-cell cache remains reusable');
 }
});

test('maze replacement, count changes and dimension changes invalidate candidate masks',()=>{
 const s=boot(),q=[80,80,120,120,17];s.nearbyWalls(...q);
 const replacement=s.walls.map(w=>({...w,x:w.x+10}));s.replaceWorld(replacement);equalOrder(s.nearbyWalls(...q),expectedCandidates(replacement,q,24,14));
 replacement.push({x:84,y:84,w:8,h:92});equalOrder(s.nearbyWalls(...q),expectedCandidates(replacement,q,24,14));assert.ok(s.nearbyWalls(...q).includes(replacement.at(-1)));
 s.replaceWorld(replacement,12,10);equalOrder(s.nearbyWalls(...q),expectedCandidates(replacement,q,12,10));
 s.replaceWorld(replacement.slice(0,12),7,7);assert.equal(s.nearbyWalls(...q),s.walls,'small wall lists keep their direct path');
});


test('wall sweeps include endpoint contacts and preserve corner normals',()=>{
 const s=boot(),wall={x:100,y:100,w:8,h:8};s.replaceWorld([wall]);
 const cases=[
  {q:[90,104,10,0,0],nx:-1,ny:0},
  {q:[118,104,-10,0,0],nx:1,ny:0},
  {q:[104,90,0,10,0],nx:0,ny:-1},
  {q:[104,118,0,-10,0],nx:0,ny:1},
  {q:[90,90,10,10,0],nx:-1,ny:-1},
  {q:[118,118,-10,-10,0],nx:1,ny:1},
  {q:[90,104,6.5,0,3.5],nx:-1,ny:0},
  {q:[118,104,-6.5,0,3.5],nx:1,ny:0},
  {q:[104,90,0,6.5,3.5],nx:0,ny:-1},
  {q:[104,118,0,-6.5,3.5],nx:0,ny:1},
  {q:[90,90,6.5,6.5,3.5],nx:-1,ny:-1}
 ];
 for(const {q,nx,ny} of cases){
  const hit=s.rayWalls(...q);assert.ok(hit,JSON.stringify(q));assert.equal(hit.t,1);assert.equal(hit.nx,nx);assert.equal(hit.ny,ny);assert.equal(hit.wall,wall);
 }
 const near=s.rayWalls(90,104,10/(1-5e-8),0);assert.ok(near);assert.ok(Math.abs(near.t-(1-5e-8))<1e-12);
 assert.equal(s.rayWalls(90,104,10/(1+5e-8),0),null,'a wall beyond the segment remains out of reach');
 const vertical={x:100,y:80,w:8,h:40},horizontal={x:80,y:100,w:40,h:8};
 for(const walls of [[vertical,horizontal],[horizontal,vertical]]){
  s.replaceWorld(walls);const hit=s.rayWalls(90,90,10,10);assert.ok(hit);assert.equal(hit.t,1);assert.equal(hit.nx,-1);assert.equal(hit.ny,-1);assert.equal(hit.wall,walls[0]);
 }
});
