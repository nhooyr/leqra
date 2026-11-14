'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {assetPath}=require('./web_assets.cjs'),Net=require(assetPath('netcode.js'));
const {boot,tank,declaration}=require('./godlike426-harness.cjs');
const free=(t,x,y)=>{t.x+=x;t.y+=y;},input={...Net.neutral(),forward:true,right:true};
const pilot=patch=>({x:500,y:500,angle:0,alive:true,hp:1,track:0,speedTime:0,speedStacks:0,ghostTime:0,starmanTime:0,...patch});
test('Starman matches two speed pickups for translation and turning, without adding pickup stacks',()=>{
 for(const stacks of [0,1,2,3,5]){
  const star=pilot({starmanTime:8,speedTime:stacks?10:0,speedStacks:stacks});
  const speed=pilot({speedTime:10,speedStacks:Math.max(2,stacks)});
  for(let i=0;i<60;i++){Net.move(star,input,Net.STEP,free);Net.move(speed,input,Net.STEP,free);}
  for(const key of ['x','y','angle'])assert.ok(Math.abs(star[key]-speed[key])<1e-8,key+' stack '+stacks);
  assert.equal(star.speedStacks,stacks);assert.ok(Math.abs(star.starmanTime-7)<1e-8);
 }
});
test('prediction and fractional presentation expire Starman while the real offline step can age it once',()=>{
 const star=pilot({starmanTime:Net.STEP/2}),before=JSON.stringify(star);
 const pose=Net.visualMove(star,input,Net.STEP*.75,free);
 assert.equal(JSON.stringify(star),before);assert.ok(Number.isFinite(pose.x));
 const predicted=new Net.Predictor(free);predicted.reset(star);predicted.advance(Net.STEP,input);
 assert.equal(predicted.state.starmanTime,0);assert.equal(Net.movementStacks(predicted.state),0);
 const actual=pilot({starmanTime:2});Net.move(actual,input,Net.STEP,free,false);assert.equal(actual.starmanTime,2);
 const stronger=pilot({speedTime:3,speedStacks:5,starmanTime:Net.STEP/2});Net.move(stronger,input,Net.STEP,free);
 assert.equal(Net.movementStacks(stronger),5);assert.equal(stronger.speedStacks,5);
});
test('fixed local controls and bot tunings use the same Starman speed floor',()=>{
 for(const control of ['humanControl','botControl','godlikeBotControl']){
  const make=patch=>{const h=boot();Object.assign(h,{stick:{mag:0},heldAction:(_,key)=>input[key],mouseAimHeading:()=>null});
   vm.runInContext(declaration('humanControl'),h);const p=tank(0,126,126,{human:control==='humanControl',difficulty:control==='godlikeBotControl'?'godlike':'normal',...patch});
   h.tanks=[p,tank(1,546,126,{human:true})];return {h,p};};
  const a=make({starmanTime:8}),b=make({speedTime:10,speedStacks:2});
  if(control==='humanControl'){a.h[control](a.p,Net.STEP,true,input);b.h[control](b.p,Net.STEP,true,input);}
  else {a.h[control](a.p,Net.STEP);b.h[control](b.p,Net.STEP);}
  for(const key of ['x','y','angle'])assert.ok(Math.abs(a.p[key]-b.p[key])<1e-8,control+' '+key);
 }
});
