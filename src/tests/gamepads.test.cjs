'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {assetPath}=require('./web_assets.cjs');
const {Gamepads,merge}=require(assetPath('gamepads.js'));

function controller(index,id='Test controller'){
 return {connected:true,mapping:'standard',index,id,axes:[0,0,0,0],
  buttons:Array.from({length:17},()=>({pressed:false,value:0}))};
}
function button(pad,index,pressed=true){pad.buttons[index].pressed=pressed;}

test('standard gamepad maps both sticks, D-pad, fire aliases, and dead zone',()=>{
 const gamepads=new Gamepads(),pad=controller(4);
 const sample=()=>gamepads.sample([null,pad],'match',true,false,true);
 pad.axes=[.05,.07,0,0];sample();assert.equal(gamepads.inputs[0],null);
 pad.axes=[0,-.8,0,0];sample();assert.equal(gamepads.inputs[0].stickY,-.8);
 assert.equal(gamepads.inputs[0].aimOnly,false);
 pad.axes=[0,-.8,1,1];button(pad,13);button(pad,15);sample();
 const {forward,reverse,right,stickX,stickY,aimOnly}=gamepads.inputs[0];
 assert.equal(forward,false);assert.equal(reverse,true);assert.equal(right,true);
 assert.ok(Math.abs(Math.hypot(stickX,stickY)-1)<1e-9);assert.equal(stickX,stickY);assert.ok(stickX>0);
 assert.equal(aimOnly,true);
 for(const key of [0,5,7]){
  pad.buttons[key].value=.8;sample();assert.equal(gamepads.inputs[0].fire,true);
  pad.buttons[key].value=0;sample();assert.equal(gamepads.inputs[0].fire,false);
 }
});

test('two controller slots keep their identity and require neutral before assigning another seat',()=>{
 const gamepads=new Gamepads(),first=controller(2),second=controller(6),extra=controller(8);
 const sample=(devices,primary=true,secondary=true)=>gamepads.sample(devices,'match',primary,secondary,true);
 sample([first,second,extra]);first.axes[0]=.5;second.axes[1]=.7;extra.axes[0]=-1;
 sample([first,second,extra]);assert.equal(gamepads.inputs[0].stickX,.5);assert.equal(gamepads.inputs[1].stickY,.7);
 sample([second,extra]);assert.equal(gamepads.inputs[0],null);assert.equal(gamepads.inputs[1].stickY,.7);
 extra.axes[0]=0;sample([second,extra]);extra.axes[0]=-1;sample([second,extra]);
 assert.equal(gamepads.inputs[0].stickX,-1);assert.equal(gamepads.inputs[1].stickY,.7);
 sample([second],true,false);assert.equal(gamepads.inputs[0],null,'a held stick cannot take over a solo seat');
 second.axes[1]=0;sample([second],true,false);second.axes[1]=.7;sample([second],true,false);
 assert.equal(gamepads.inputs[0].stickY,.7);assert.equal(gamepads.inputs[1],null);
});

test('Menu fires once per press and held input is released under a modal or after reset',()=>{
 const gamepads=new Gamepads(),pad=controller(0);
 const sample=(context='match',canPause=true)=>gamepads.sample([pad],context,true,false,canPause);
 assert.equal(sample(),false);
 button(pad,9);button(pad,0);assert.equal(sample(),true);
 assert.equal(sample('',false),false);assert.deepEqual(gamepads.inputs,[null,null]);
 assert.equal(sample(),false);assert.equal(gamepads.inputs[0],null);
 button(pad,0,false);button(pad,9,false);sample();
 button(pad,9);button(pad,0);assert.equal(sample(),true);assert.equal(gamepads.inputs[0].fire,true);
 gamepads.clear();assert.deepEqual(gamepads.inputs,[null,null]);assert.equal(sample(),false);
 assert.equal(gamepads.inputs[0],null);
 assert.equal(gamepads.sample([], 'match', true, false, true),false);
 assert.deepEqual(gamepads.inputs,[null,null]);
});

test('merging controller controls retains other fire sources and explicit touch aim',()=>{
 const neutral={forward:false,reverse:false,left:false,right:false,fire:false,stickX:1,stickY:0,aimOnly:true,snapAim:true,touchAim:false};
 const pad={...neutral,forward:true,fire:true,stickX:0,stickY:-1,aimOnly:false};
 assert.deepEqual(merge({...neutral},pad,true),{...neutral,forward:true,fire:true});
 assert.deepEqual(merge({...neutral,fire:true},{...pad,fire:false}),{...neutral,forward:true,fire:true,stickX:0,stickY:-1,aimOnly:false,snapAim:false});
 assert.deepEqual(merge({...neutral},{...pad,stickX:0,stickY:0,left:true}),{...neutral,forward:true,left:true,fire:true,stickX:0,stickY:0,aimOnly:false,snapAim:false});
});
