'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),vm=require('node:vm');
const {assetPath}=require('./web_assets.cjs');
const Net=require(assetPath('netcode.js'));
const source=readFileSync(assetPath('game.js'),'utf8');
function declaration(name){
 const start=source.indexOf('function '+name+'('),lineEnd=source.indexOf('\n',start);
 assert.ok(start>=0,name);
 const line=source.slice(start,lineEnd);
 return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',lineEnd)+2);
}
function eventTarget(){
 const handlers=new Map(),classes=new Set();
 return{
  addEventListener(type,fn){const list=handlers.get(type)||[];list.push(fn);handlers.set(type,list);},
  emit(type,values){const event={pointerType:'mouse',pointerId:4,offsetX:60,offsetY:150,button:0,buttons:0,target:{tagName:'CANVAS'},preventDefault(){this.prevented=true;},...values};for(const fn of handlers.get(type)||[])fn(event);return event;},
  classList:{add:c=>classes.add(c),remove:c=>classes.delete(c),contains:c=>classes.has(c)},style:{},
  setPointerCapture(id){this.captured=id;},focus(){this.focused=true;}
 };
}
function boot(mode='room'){
 const p1={id:3,localIndex:0,alive:true,x:100,y:100,angle:0},p2={id:5,localIndex:1,alive:true,x:100,y:100,angle:0};
 const canvas=eventTarget(),window=eventTarget(),elements=new Map(),shots=[],packets=[];
 const bindings=[{forward:'KeyW',reverse:'KeyS',left:'KeyA',right:'KeyD',fire:'KeyQ'},{forward:'ArrowUp',reverse:'ArrowDown',left:'ArrowLeft',right:'ArrowRight',fire:'Space'}];
 const s={Net,mode,phase:'playing',now:1000,intermission:false,modal:false,chat:false,bindingCapture:null,canvas,window,tanks:[p1,p2],keys:new Set(),firePresses:new Set(),firePointers:new Set(),
  online:{id:p1.id,connected:true,menu:false,snapshots:[{received:999}]},performance:{now:()=>s.now},document:{hidden:false,querySelector:()=>s.modal?{}:null,querySelectorAll:()=>s.modal?[{open:true}]:[]},
  mouseAim:{active:false,x:0,y:0},stick:{x:0,y:0,mag:0},cssW:500,cssH:500,offsetX:10,offsetY:20,scale:.5,
  BOOST_SPEED_PER_STACK:.65,BOOST_TURN_PER_STACK:.25,angleDelta:Net.delta,clamp:Net.clamp,
  $(id){if(!elements.has(id))elements.set(id,eventTarget());return elements.get(id);},
  secondLocal:()=>p2,secondaryID:()=>p2.id,localPlayerID:()=>p1.id,controlledTank:()=>p1,chatHasFocus:()=>s.chat,survivalBreak:()=>s.intermission,
  keyForAction:(player,action,code)=>bindings[player][action]===code,heldAction:(player,action)=>s.keys.has(bindings[player][action]),isControlKey:code=>bindings.some(b=>Object.values(b).includes(code)),isWeaponKey:code=>bindings.some(b=>b.fire===code),
  primaryFireHeld:()=>s.firePointers.size>0||s.keys.has('KeyQ'),primaryFireKey:code=>code==='KeyQ',initAudio(){},sendOnlineInput(){packets.push(s.onlineControls());},
  speedCount:()=>0,moveTank(t,dx,dy){t.x+=dx;t.y+=dy;},weaponControl(t,held,pressed){if(pressed)shots.push(t.id);}
 };
 vm.createContext(s);
 for(const name of ['clearInput','humanControl','onlineControls'])vm.runInContext(declaration(name),s);
 const start=source.indexOf('// All input paths');
 vm.runInContext(source.slice(start,source.indexOf('// Dialogs and the sidebar',start)),s);
 return{s,p1,p2,canvas,window,shots,packets};
}
function close(a,b){assert.ok(Math.abs(a-b)<1e-8,`${a} != ${b}`);}

test('mouse steers only P1, preserves forward and reverse controls and yields to a keyboard turn',()=>{
 const {s,p1,p2,canvas,window}=boot();
 canvas.emit('pointermove');
 assert.ok(canvas.classList.contains('mouse-aiming'));
 s.humanControl(p1,Net.STEP);s.humanControl(p2,Net.STEP);
 close(p1.angle,5.8*Net.STEP);close(p2.angle,0);close(p1.x,100);close(p1.y,100);
 window.emit('keydown',{code:'KeyW'});
 s.humanControl(p1,Net.STEP);
 close(Math.hypot(p1.x-100,p1.y-100),128*Net.STEP);
 window.emit('keyup',{code:'KeyW'});
 const angle=p1.angle;
 window.emit('keydown',{code:'ArrowRight'});s.humanControl(p2,Net.STEP);window.emit('keyup',{code:'ArrowRight'});
 close(p2.angle,3.65*Net.STEP);assert.equal(s.mouseAim.active,true);
 window.emit('keydown',{code:'KeyA'});s.humanControl(p1,Net.STEP);window.emit('keyup',{code:'KeyA'});
 close(p1.angle,angle-3.65*Net.STEP);assert.equal(s.mouseAim.active,false);
 s.humanControl(p1,Net.STEP);close(p1.angle,angle-3.65*Net.STEP);
 canvas.emit('pointermove',{offsetX:10+p1.x*.5,offsetY:20+p1.y*.5});
 assert.equal(s.mouseAimHeading(p1),null,'the tank center has a small aiming dead zone');
});

test('a quick left click latches one P1 shot and releases capture safely',()=>{
 const {s,p1,p2,canvas,window,shots}=boot();
 assert.equal(canvas.emit('pointerdown',{pointerType:'touch'}).prevented,undefined);
 assert.equal(canvas.emit('pointerdown',{button:2}).prevented,undefined);
 assert.equal(canvas.emit('pointerdown',{buttons:1}).prevented,true);
 assert.equal(canvas.captured,4);assert.equal(canvas.focused,true);
 window.emit('pointerup');
 s.humanControl(p1,Net.STEP);s.humanControl(p2,Net.STEP);s.humanControl(p1,Net.STEP);
 assert.deepEqual(shots,[p1.id]);
 canvas.emit('pointerdown',{buttons:1});canvas.emit('lostpointercapture');
 assert.equal(s.firePointers.size,0);
 s.clearInput();
 assert.equal(s.mouseAim.active,false);assert.equal(canvas.classList.contains('mouse-aiming'),false);
 for(const phase of ['menu','countdown','paused','roundOver','matchOver']){
  s.phase=phase;assert.equal(canvas.emit('pointerdown',{buttons:1}).prevented,undefined,phase);
 }
 s.phase='playing';s.intermission=true;
 assert.equal(canvas.emit('pointerdown',{buttons:1}).prevented,undefined);
});

test('online mouse direction is aim-only and the existing fire edge sends an immediate press and release',()=>{
 const {s,p1,canvas,window,packets}=boot('online');
 canvas.emit('pointermove');
 let control=s.onlineControls();
 assert.equal(control.aimOnly,true);close(control.stickX,0);close(control.stickY,1);assert.equal(control.forward,false);
 assert.deepEqual({...s.onlineControls(true)},Net.neutral());
 s.stick.x=-1;s.stick.mag=1;
 control=s.onlineControls();assert.equal(control.aimOnly,false);assert.equal(control.stickX,-1);
 s.stick.x=0;s.stick.mag=0;s.keys.add('KeyS');
 assert.equal(s.onlineControls().reverse,true);
 canvas.emit('pointerdown',{buttons:1});window.emit('pointerup');
 assert.deepEqual(packets.map(packet=>packet.fire),[true,false]);
 assert.ok(packets.every(packet=>packet.aimOnly));
 canvas.emit('pointerleave');assert.equal(s.onlineControls().aimOnly,false);
 canvas.emit('pointermove');s.modal=true;assert.deepEqual(s.onlineControls(),Net.neutral());
 s.modal=false;s.chat=true;assert.deepEqual(s.onlineControls(),Net.neutral());
 s.chat=false;s.online.menu=true;assert.equal(canvas.emit('pointerdown',{buttons:1}).prevented,undefined);
 s.online.menu=false;p1.alive=false;assert.equal(canvas.emit('pointerdown',{buttons:1}).prevented,undefined);
});
