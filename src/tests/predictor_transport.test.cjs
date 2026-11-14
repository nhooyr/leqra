'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {assetPath}=require('./web_assets.cjs'),Net=require(assetPath('netcode.js'));
const {measure}=require('./predictor_transport_harness.cjs');

for(const rtt of [1,10,25,50,150,250,400])for(const control of ['keyboard','touch']){
 test(`actual Speed5 Predictor stays smooth at120Hz with ${rtt}ms RTT ±12ms jitter, ${control} turns`,()=>{
  const result=measure(Net,{rtt,control});
  assert.ok(result.frames>=1200,'the profile includes ten steady-state seconds');
  // At25ms this clock/jitter phase acknowledges three held-input ticks before
  // the next packet acknowledges one. Replay must immediately accept the
  // resulting two-tick (~18px) correction. A20rad/s spring settles that larger
  // error with more acceleration; compare ripple per correction pixel without
  // slowing the spring or relaxing the one-tick profiles' original bounds.
  assert.ok(result.maxReconciliationError<20,'transport correction remains within two Speed5 steps');
  const multiTick=result.maxReconciliationError>1.5*544/60;
  const p95Limit=multiTick?2*result.maxReconciliationError:30;
  const peakLimit=multiTick?4*result.maxReconciliationError:35;
  assert.ok(result.p95SpeedChange<p95Limit,`p95 frame-speed ripple ${result.p95SpeedChange.toFixed(3)}px/s`);
  assert.ok(result.p99SpeedChange<(multiTick?peakLimit:30),`p99 frame-speed ripple ${result.p99SpeedChange.toFixed(3)}px/s`);
  assert.ok(result.maxSpeedChange<peakLimit,'a correction cannot create an isolated frame-speed spike');
  assert.ok(result.maxOffset<18&&result.maxViewError<20,'render smoothing remains spatially bounded');
  assert.equal(result.stalls,0,'a moving pilot must not stall on snapshot arrival');
  assert.equal(result.hardResets,0,'ordinary transport jitter must preserve prediction history');
 });
}

test('a new life and collision-policy change discard correction velocity as well as position',()=>{
 const free=(pose,dx,dy)=>{pose.x+=dx;pose.y+=dy;},pose={id:0,x:0,y:0,angle:0,alive:true,spawnSerial:1,ghostTime:0};
 const predictor=new Net.Predictor(free);predictor.reset(pose);
 predictor.offset={x:3,y:5,angle:.2};predictor.correctionVelocity={x:20,y:-30,angle:2};
 predictor.reconcile({...pose,x:100});
 assert.deepEqual(predictor.offset,{x:0,y:0,angle:0});assert.deepEqual(predictor.correctionVelocity,{x:0,y:0,angle:0});
 predictor.offset={x:3,y:5,angle:.2};predictor.correctionVelocity={x:20,y:-30,angle:2};
 predictor.reconcile({...pose,x:100,ghostTime:3});
 assert.deepEqual(predictor.offset,{x:0,y:0,angle:0});assert.deepEqual(predictor.correctionVelocity,{x:0,y:0,angle:0});
});
