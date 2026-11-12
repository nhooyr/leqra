'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),{assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8');

test('fixed room and match RTT probes use one-second cadence without changing input updates',()=>{
 const start=source.indexOf(" setInterval(()=>{if(mode!=='online')return;"),end=source.indexOf('\n',start);
 assert.ok(start>=0,'fixed online heartbeat exists');
 for(const phase of ['playing','onlineLobby','matchOver']){
  const sent=[],stored=[],timers=[];let now=0,inputUpdates=0;
  const context={mode:'online',phase,online:{connected:true,lastPing:0},performance:{now:()=>now},
   setInterval(callback,interval){timers.push({callback,interval});},sendOnline:packet=>sent.push(packet),storeOnlineSession:()=>stored.push(now),
   sendOnlineInput:()=>inputUpdates++,secondLocal:()=>false};
  vm.runInNewContext(source.slice(start,end),context);
  assert.equal(timers.length,1);assert.equal(timers[0].interval,250,'input keepalive keeps its existing frequency');
  for(now=250;now<=3000;now+=250)timers[0].callback();
  assert.deepEqual(sent.map(packet=>packet.t),[1000,2000,3000],phase);
  assert.ok(sent.every(packet=>packet.type==='ping'));assert.deepEqual(stored,[1000,2000,3000]);
  assert.equal(inputUpdates,phase==='playing'?0:12);
  context.online.connected=false;now=4000;timers[0].callback();assert.equal(sent.length,3);
  context.online.connected=true;context.mode='room';now=5000;timers[0].callback();assert.equal(sent.length,3);
 }
});
