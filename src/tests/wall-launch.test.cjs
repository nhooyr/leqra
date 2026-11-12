'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {assetPath}=require('./web_assets.cjs'),net=require(assetPath('netcode.js'));
const fixtures=require('./fixtures/wall_launch.json');
for(const fixture of fixtures)test('launch geometry: '+fixture.name,()=>{
 const f=fixture,bounds=f.bounds?((x,y)=>x>=f.bounds[0]&&y>=f.bounds[1]&&x<=f.bounds[2]&&y<=f.bounds[3]):null;
 for(const walls of [f.walls,[...f.walls].reverse()]){
  const actual=net.wallLaunch(f.x,f.y,f.ux,f.uy,f.radius,f.muzzle,walls,bounds);
  for(const [key,want]of Object.entries(f.expected)){
   if(typeof want==='number')assert.ok(Math.abs(actual[key]-want)<1e-7,key+': '+actual[key]+' != '+want);
   else assert.equal(actual[key],want,key);
  }
  if(actual.valid&&actual.bounced){assert.ok(actual.distance<=32);assert.ok((actual.x-f.x)*f.ux+(actual.y-f.y)*f.uy<=1e-7);}
 }
});
