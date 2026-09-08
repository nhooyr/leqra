'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot(phase,breaking){
 const snapshot={generation:1,received:1000,tanks:[],bullets:[],tankMap:new Map(),bulletMap:new Map(),pickups:[{id:9,type:'laser',x:200,y:300,age:29.95,life:.05}],phaseTime:2,roundClock:60};
 const s={updateOnlineBounceSounds(){},phase,tanks:[],bullets:[],pickups:[],phaseTime:0,roundClock:0,clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),secondaryID:()=>undefined,survivalBreak:()=>breaking,Net:{STEP_MS:1000/60},moveTank(){},online:{id:0,connected:true,snapshots:[snapshot],buffer:{advance:()=>null},ownedIDs:new Set(),activeIDs:new Set(),trailIDs:new Set(),shots:{prune(){},previews:new Map()},trails:new Map(),localBullets:new Map(),effectQueue:[]}};
 vm.createContext(s);vm.runInContext(declaration('applyOnlineTankEffects')+'\n'+declaration('renderOnlineMotion'),s);return {s,snapshot};
}
test('online Survival hold snapshots keep nearly expired pickups visible without visual aging',()=>{
 const {s,snapshot}=boot('playing',true),original=JSON.stringify(snapshot.pickups);
 for(const now of [1000,1050,1250,1999,3000]){
  s.renderOnlineMotion(1/60,now);assert.equal(s.pickups.length,1);assert.equal(s.pickups[0].id,9);assert.equal(s.pickups[0].life,.05);assert.equal(s.pickups[0].age,29.95);assert.equal(s.roundClock,60);
 }
 assert.equal(JSON.stringify(snapshot.pickups),original,'rendering cannot mutate the authoritative snapshot');
});
test('online completed scenes and new-wave countdowns freeze pickups while live play still expires them',()=>{
 for(const phase of ['roundOver','matchOver','countdown']){
  const {s}=boot(phase,false);s.renderOnlineMotion(1/60,2000);assert.equal(s.pickups.length,1,phase);assert.equal(s.pickups[0].life,.05,phase);
 }
 const {s}=boot('playing',false);s.renderOnlineMotion(1/60,1200);assert.equal(s.pickups.length,0,'active pickup expiry must continue');assert.equal(s.roundClock,59.8);
});
