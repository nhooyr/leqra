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
 const canvas=eventTarget(),window=eventTarget(),elements=new Map(),shots=[],packets=[],saved=new Map();
 const bindings=[{forward:'KeyW',reverse:'KeyS',left:'KeyA',right:'KeyD',fire:'KeyQ'},{forward:'ArrowUp',reverse:'ArrowDown',left:'ArrowLeft',right:'ArrowRight',fire:'Space'}];
 const s={Net,mode,phase:'playing',now:1000,intermission:false,modal:false,chat:false,bindingCapture:null,canvas,window,tanks:[p1,p2],keys:new Set(),firePresses:new Set(),firePointers:new Set(),
  online:{id:p1.id,connected:true,menu:false,snapshots:[{received:999}]},performance:{now:()=>s.now},document:{hidden:false,querySelector:()=>s.modal?{}:null,querySelectorAll:()=>s.modal?[{open:true}]:[]},
  mouseAim:{active:false,x:0,y:0},stick:{x:0,y:0,mag:0},combatPrefs:{visual:false,audio:false,fps:true,performance:true},localStorage:{getItem:key=>saved.get(key)||null,setItem:(key,value)=>saved.set(key,value)},cssW:500,cssH:500,offsetX:10,offsetY:20,scale:.5,
  BOOST_SPEED_PER_STACK:.65,BOOST_TURN_PER_STACK:.25,angleDelta:Net.delta,clamp:Net.clamp,
  $(id){if(!elements.has(id))elements.set(id,eventTarget());return elements.get(id);},
  secondLocal:()=>p2,secondaryID:()=>p2.id,localPlayerID:()=>p1.id,controlledTank:()=>p1,chatHasFocus:()=>s.chat,survivalBreak:()=>s.intermission,
  keyForAction:(player,action,code)=>bindings[player][action]===code,heldAction:(player,action)=>s.keys.has(bindings[player][action]),isControlKey:code=>bindings.some(b=>Object.values(b).includes(code)),isWeaponKey:code=>bindings.some(b=>b.fire===code),
  primaryFireHeld:()=>s.firePointers.size>0||s.keys.has('KeyQ'),primaryFireKey:code=>code==='KeyQ',initAudio(){},sendOnlineInput(){packets.push(s.onlineControls());},
  speedCount:()=>0,moveTank(t,dx,dy){t.x+=dx;t.y+=dy;},weaponControl(t,held,pressed){if(pressed)shots.push(t.id);},featureNotice(id,text,error){s.preferenceNotice={id,text,error};},syncFeatureSummary(){s.summaryRefreshes=(s.summaryRefreshes||0)+1;},syncSidebarContext(){s.sidebarRefreshes=(s.sidebarRefreshes||0)+1;}
 };
 vm.createContext(s);
 for(const name of ['clearInput','humanControl','onlineControls','composingKey','arenaKeyBlocked','readCombatPrefs','setMouseControlEnabled','storePerformancePrefs'])vm.runInContext(declaration(name),s);
 const start=source.indexOf('// All input paths');
 vm.runInContext(source.slice(start,source.indexOf('// Dialogs and the sidebar',start)),s);
 return{s,p1,p2,canvas,window,shots,packets,saved};
}
function close(a,b){assert.ok(Math.abs(a-b)<1e-8,`${a} != ${b}`);}

test('all four mouse aim and fire combinations are independent offline and online',()=>{
 for(const mode of ['room','online'])for(const aim of [false,true])for(const fire of [false,true]){
  const {s,p1,canvas,shots}=boot(mode);s.setMouseControlEnabled('aim',aim);s.setMouseControlEnabled('fire',fire);
  canvas.emit('pointermove');assert.equal(s.mouseAim.active,aim);
  const event=canvas.emit('pointerdown',{buttons:1});assert.equal(event.prevented,fire?true:undefined);assert.equal(s.primaryFireHeld(),fire);
  const controls=s.onlineControls();assert.equal(controls.aimOnly,aim);assert.equal(controls.fire,fire);
  if(mode==='room'){s.humanControl(p1,Net.STEP);assert.deepEqual(shots,fire?[p1.id]:[]);if(!aim)assert.equal(p1.angle,0,'mouse firing keeps the keyboard/current heading when aim is disabled');else assert.ok(p1.angle>0);}
  assert.equal(s.$('p1MouseAimEnabled').checked,aim);assert.equal(s.$('p1MouseFireEnabled').checked,fire);
 }
});

test('changing one mouse setting clears only that capability, with no synthesized fire when re-enabled',()=>{
 for(const mode of ['room','online']){
  const {s,p1,canvas,window,shots,packets,saved}=boot(mode),resets=[];window.leqraInfinity={resetMouseControls(kind){resets.push(kind);}};
  canvas.emit('pointermove');canvas.emit('pointerdown',{buttons:1});assert.equal(s.primaryFireHeld(),true);
  s.setMouseControlEnabled('aim',false);assert.equal(s.mouseAim.active,false);assert.equal(s.primaryFireHeld(),true,'turning off aim keeps the mouse fire press');assert.equal(s.mouseAimHeading(p1),null);
  if(mode==='online'){assert.equal(packets.at(-1).aimOnly,false);assert.equal(packets.at(-1).fire,true);}
  s.setMouseControlEnabled('aim',true);assert.equal(s.mouseAim.active,false);canvas.emit('pointermove',{buttons:1});assert.equal(s.mouseAim.active,true);
  s.setMouseControlEnabled('fire',false);assert.equal(s.mouseAim.active,true,'turning off fire keeps mouse aim');assert.equal(s.firePointers.size,0);assert.equal(s.mouseAim.firePressed,false);
  if(mode==='room'){s.humanControl(p1,Net.STEP);assert.deepEqual(shots,[]);}else assert.equal(packets.at(-1).fire,false,'an immediate release is sent to the server');
  assert.deepEqual(JSON.parse(saved.get('leqra.feedback.v1')),{visual:false,audio:false,fps:true,performance:true,mouseAim:true,mouseFire:false});
  s.setMouseControlEnabled('fire',true);canvas.emit('pointermove',{buttons:1});assert.equal(s.primaryFireHeld(),false);assert.equal(s.mouseAim.firePressed,false,'an already-held button cannot synthesize a click');
  window.emit('pointerup');canvas.emit('pointerdown',{buttons:1});assert.equal(s.primaryFireHeld(),true);assert.equal(s.mouseAim.firePressed,true);
  assert.deepEqual(resets,['aim','aim','fire','fire']);assert.equal(s.summaryRefreshes,4);assert.equal(s.sidebarRefreshes,4);
 }
});

test('mouse preference changes preserve keyboard, P2 and touch controls including a queued nonmouse fire press',()=>{
 const {s,p1,p2,canvas,window,shots}=boot();canvas.emit('pointerdown',{buttons:1});window.emit('pointerup');
 window.emit('keydown',{code:'KeyQ'});window.emit('keyup',{code:'KeyQ'});window.emit('keydown',{code:'Space'});window.emit('keydown',{code:'KeyW'});
 s.stick={id:99,x:0,y:1,mag:1,assisted:true};s.$('fireBtn').emit('pointerdown',{pointerType:'touch',pointerId:88,buttons:1});
 s.setMouseControlEnabled('aim',false);s.setMouseControlEnabled('fire',false);assert.equal(s.keys.has('KeyW'),true);assert.equal(s.keys.has('Space'),true);assert.equal(s.firePointers.has(88),true);assert.equal(s.stick.id,99);assert.equal(s.stick.mag,1);
 assert.equal(s.onlineControls().touchAim,true);assert.equal(s.onlineControls().fire,true);
 s.humanControl(p1,Net.STEP);s.humanControl(p2,Net.STEP);assert.deepEqual(shots,[p1.id,p2.id]);
 s.$('fireBtn').emit('pointerup',{pointerType:'touch',pointerId:88});assert.equal(s.firePointers.size,0);
 s.$('fireBtn').emit('pointerdown',{pointerType:'touch',pointerId:89,buttons:1});s.$('fireBtn').emit('pointerup',{pointerType:'touch',pointerId:89});
 s.setMouseControlEnabled('fire',true);s.humanControl(p1,Net.STEP);assert.deepEqual(shots,[p1.id,p2.id,p1.id],'touch taps remain queued through the setting change');
});

test('independent mouse preferences migrate default-on and legacy choices without dropping other settings',()=>{
 const {s,saved}=boot();assert.equal(s.readCombatPrefs().mouseAim,true);assert.equal(s.readCombatPrefs().mouseFire,true);
 for(const [extra,aim,fire]of [[{},true,true],[{mouse:false},false,false],[{mouse:false,mouseAim:true},true,false],[{mouse:false,mouseFire:true},false,true],[{mouse:true,mouseAim:false,mouseFire:false},false,false]]){
  saved.set('leqra.feedback.v1',JSON.stringify({visual:false,audio:true,fps:true,performance:false,...extra}));
  assert.deepEqual({...s.readCombatPrefs()},{visual:false,audio:true,fps:true,performance:false,mouseAim:aim,mouseFire:fire});
 }
 s.combatPrefs={visual:false,audio:true,fps:true,performance:false,mouse:false};s.setMouseControlEnabled('aim',true);
 assert.deepEqual(JSON.parse(saved.get('leqra.feedback.v1')),{visual:false,audio:true,fps:true,performance:false,mouseAim:true,mouseFire:false});assert.equal('mouse' in s.combatPrefs,false);
 s.setMouseControlEnabled('fire',true);assert.equal(s.readCombatPrefs().mouseFire,true);assert.equal(s.readCombatPrefs().mouseAim,true);
 s.localStorage={getItem(){throw Error('denied');},setItem(){throw Error('denied');}};
 assert.equal(s.readCombatPrefs().mouseAim,true);assert.equal(s.readCombatPrefs().mouseFire,true);assert.doesNotThrow(()=>s.setMouseControlEnabled('fire',false));assert.equal(s.combatPrefs.mouseFire,false);assert.equal(s.preferenceNotice.error,true);
});

test('fixed offline steering and online controls both use touch assist for P1 only',()=>{
 const {s,p1,p2}=boot();
 Object.assign(s.stick,{x:0,y:1,mag:1,assisted:true});
 s.humanControl(p1,Net.STEP);
 s.humanControl(p2,Net.STEP);
 close(p1.angle,9*Net.STEP);
 close(p2.angle,0);
 assert.equal(s.onlineControls().touchAim,true);
 assert.equal(s.onlineControls(true).touchAim,undefined);
 s.clearInput();
 assert.equal(s.stick.assisted,false);
 assert.equal(s.onlineControls().touchAim,undefined);
});

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

test('a fixed-maze respawn while Fire is held does not synthesize a fresh press',()=>{
 const {s,p1,window,shots}=boot();
 window.emit('keydown',{code:'KeyQ'});
 s.humanControl(p1,Net.STEP);
 // The same held key survives the respawn, but a fresh tank has no fire state.
 p1.fireHeld=false;
 s.humanControl(p1,Net.STEP);
 assert.deepEqual(shots,[p1.id]);
 window.emit('keyup',{code:'KeyQ'});
 window.emit('keydown',{code:'KeyQ'});
 s.humanControl(p1,Net.STEP);
 assert.deepEqual(shots,[p1.id,p1.id]);
});

test('respawning cancels a queued mouse tap from the previous tank without cancelling P2',()=>{
 const {s,p1,p2,canvas,window,shots}=boot();
 Object.assign(s,{MAX_TANKS:8,localObjectives:null,spawnCells:()=>Array(8).fill(0),grid:[{neighbors:[]}],center:()=>({x:100,y:100}),flagSafeSpawn:()=>true,distance:(a,b)=>Math.hypot(a.x-b.x,a.y-b.y),bullets:[],cols:1,rows:1,newTank:id=>({...s.tanks.find(t=>t.id===id),alive:true}),addRing(){}});
 p1.r=p2.r=17;vm.runInContext(declaration('respawnLocalTank'),s);
 canvas.emit('pointerdown',{buttons:1});window.emit('pointerup');assert.equal(s.mouseAim.firePressed,true);s.firePresses.add(p2.id);
 p1.alive=false;s.respawnLocalTank(p1);s.humanControl(p1,Net.STEP);s.humanControl(p2,Net.STEP);
 assert.equal(s.mouseAim.firePressed,false);assert.deepEqual(shots,[p2.id]);
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
