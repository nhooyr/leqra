'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){
 const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);
 const lineEnd=source.indexOf('\n',start),first=source.slice(start,lineEnd);
 return first.endsWith('}')?first:source.slice(start,source.indexOf('\n}',lineEnd)+2);
}
function eventTarget(){
 const handlers=new Map(),changes=[];
 return{handlers,changes,
  addEventListener(type,fn,options){const list=handlers.get(type)||[];list.push({fn,options});handlers.set(type,list);changes.push(['add',type]);},
  removeEventListener(type,fn){handlers.set(type,(handlers.get(type)||[]).filter(h=>h.fn!==fn));changes.push(['remove',type]);},
  emit(type,values={}){const e={type,cancelable:true,defaultPrevented:false,preventDefault(){this.defaultPrevented=true;},stopPropagation(){throw Error('Game input must still propagate');},...values};for(const {fn}of handlers.get(type)||[])fn(e);return e;}
 };
}
function element(){
 const classes=new Set(),attrs=new Map();
 return{...eventTarget(),style:{},hidden:false,title:'',
  classList:{add:c=>classes.add(c),remove:c=>classes.delete(c),contains:c=>classes.has(c),toggle(c,on){if(on)classes.add(c);else classes.delete(c);}},
  getAttribute:k=>attrs.get(k),setAttribute:(k,v)=>attrs.set(k,v),
  getBoundingClientRect:()=>({left:0,top:0,width:96,height:96}),setPointerCapture(){},hasPointerCapture:()=>true
 };
}
function boot(){
 const elements=new Map(),$=id=>{if(!elements.has(id))elements.set(id,element());return elements.get(id);};
 const selection={isCollapsed:true,cleared:0,removeAllRanges(){this.isCollapsed=true;this.cleared++;}},document={...eventTarget(),documentElement:element(),body:element(),getSelection:()=>selection},window=eventTarget();
 const s={document,window,$,mode:'room',phase:'menu',matchTouchLocked:false,matchTextComposing:false,touchUI:true,pendingMatchPresentation:null,online:{connected:true,menu:false},
  stick:{id:null,x:0,y:0,mag:0,cx:0,cy:0,max:36},firePointers:new Set(),firePresses:new Set(),initAudio(){},localPlayerID:()=>0,sendOnlineInput(){},primaryFireHeld:()=>s.firePointers.size>0};
 vm.createContext(s);
 for(const name of ['syncPauseButton','preventMatchPinch','clearMatchSelection','preventMatchSelection','syncMatchTouchPolicy'])vm.runInContext(declaration(name),s);
 // The actual joystick/Fire handlers are exercised alongside document guards.
 vm.runInContext(source.slice(source.indexOf('function cacheStickGeometry('),source.indexOf("$('touchControls').addEventListener('contextmenu'")),s);
 return{s,$,document,window,selection,setPhase(phase){s.phase=phase;s.syncPauseButton();},pinch(type='gesturechange',values={}){return document.emit(type,values);}};
}

test('pinch is blocked throughout local and online active phases, including menus and disconnection',()=>{
 for(const mode of ['room','solo','duel','online']){
  const b=boot();b.s.mode=mode;
  for(const phase of ['countdown','playing','roundOver','paused'])for(const connected of [true,false]){
   b.s.online.connected=connected;b.s.online.menu=true;b.setPhase(phase);
   assert.equal(b.document.documentElement.classList.contains('match-active'),true,mode+' '+phase);
   for(const type of ['gesturestart','gesturechange','gestureend'])assert.equal(b.pinch(type).defaultPrevented,true,type);
   assert.equal(b.pinch('touchmove',{touches:[{},{}]}).defaultPrevented,true);
  }
 }
});
test('home, lobby and completed matches release zoom and every nonpassive gesture listener',()=>{
 const b=boot();
 for(const phase of ['menu','onlineLobby','lobby','matchOver']){
  b.setPhase('playing');b.setPhase(phase);
  assert.equal(b.document.documentElement.classList.contains('match-active'),false,phase);
  for(const type of ['touchmove','gesturestart','gesturechange','gestureend','selectstart','selectionchange','contextmenu','dblclick','compositionstart','compositionend']){
   assert.equal(b.document.handlers.get(type).length,0,type);
   assert.equal(b.pinch(type,{touches:[{},{}]}).defaultPrevented,false,phase);
  }
 }
});
test('single-finger scrolling and taps remain native while only cancelable pinch gestures are canceled',()=>{
 const b=boot();b.setPhase('playing');
 for(const count of [0,1])assert.equal(b.pinch('touchmove',{touches:Array(count).fill({})}).defaultPrevented,false);
 assert.equal(b.pinch('touchstart',{touches:[{}]}).defaultPrevented,false);
 assert.equal(b.pinch('touchstart',{touches:[{},{}]}).defaultPrevented,false,'do not cancel the second gameplay pointer starting');
 assert.equal(b.pinch('touchmove',{touches:[{},{}],cancelable:false}).defaultPrevented,false);
 assert.equal(b.pinch('gesturechange',{cancelable:false}).defaultPrevented,false);
 assert.equal(b.pinch('gesturechange',{scale:1.2}).defaultPrevented,true);
});
test('repeated HUD refreshes register one capture guard per event and leave no inactive scrolling overhead',()=>{
 const b=boot();for(let i=0;i<40;i++)b.setPhase('playing');
 assert.equal(b.document.changes.length,10);
 for(const list of b.document.handlers.values()){assert.equal(list.length,1);assert.equal(list[0].options.capture,true);assert.equal(list[0].options.passive,false);}
 for(const phase of ['paused','playing','roundOver','countdown'])b.setPhase(phase);
 assert.equal(b.document.changes.length,10);
 b.setPhase('matchOver');for(let i=0;i<40;i++)b.setPhase('menu');assert.equal(b.document.changes.length,20);
 b.setPhase('playing');assert.equal(b.document.changes.length,30);
 for(const list of b.document.handlers.values())assert.equal(list.length,1);
});
test('joystick plus Fire keep independent pointers through a prevented pinch and release without stuck input',()=>{
 const b=boot();b.setPhase('playing');
 b.$('stickZone').emit('pointerdown',{pointerId:1,clientX:48,clientY:48});
 b.$('fireBtn').emit('pointerdown',{pointerId:2});
 assert.equal(b.pinch('touchmove',{touches:[{},{}]}).defaultPrevented,true);
 b.$('stickZone').emit('pointermove',{pointerId:1,clientX:84,clientY:48});
 assert.equal(b.s.stick.mag,1);assert.equal(b.s.stick.x,1);assert.equal(b.s.firePointers.has(2),true);assert.equal(b.s.firePresses.has(0),true);
 b.window.emit('pointerup',{pointerId:2});assert.equal(b.s.firePointers.size,0);assert.equal(b.s.stick.id,1);
 b.window.emit('pointercancel',{pointerId:1});assert.equal(b.s.stick.id,null);assert.equal(b.s.stick.mag,0);assert.equal(b.$('fireBtn').classList.contains('held'),false);
});

function resumeConnection(b){
 Object.assign(b.s,{location:{protocol:'https:',href:'https://leqra.test/'},URL,WebSocket:class{},setTimeout(){return 1;},clearTimeout(){},netBusy(){},setNetStatus(){}});
 Object.assign(b.s.online,{connected:false,connecting:false,code:'ROOM',token:'resume-token',manual:false});
 vm.runInContext(declaration('connectOnline'),b.s);
 b.s.connectOnline({type:'join',code:'ROOM',token:'resume-token'},true);
 b.s.syncPauseButton();
}
test('actual background reconnect keeps active-match pinch protection through its temporary menu phase',()=>{
 for(const phase of ['countdown','playing','roundOver']){
  const b=boot();b.s.mode='online';b.setPhase(phase);resumeConnection(b);
  assert.equal(b.s.phase,'menu','preserve the welcome/snapshot overlay transition');
  assert.equal(b.s.online.connecting,true);
  for(let i=0;i<20;i++)b.s.syncPauseButton();
  assert.equal(b.document.documentElement.classList.contains('match-active'),true);
  assert.equal(b.pinch('gesturechange').defaultPrevented,true);
  assert.equal(b.pinch('touchmove',{touches:[{},{}]}).defaultPrevented,true);
  assert.equal(b.document.changes.length,10,'the retry never removes and reattaches the gesture listeners');
 }
});
test('cold-session and lobby reconnects do not acquire an active-match zoom lock',()=>{
 for(const phase of ['menu','onlineLobby','matchOver']){
  const b=boot();b.s.mode='online';b.setPhase(phase);resumeConnection(b);
  assert.equal(b.s.phase,'menu');assert.equal(b.s.matchTouchLocked,false);
  assert.equal(b.pinch('gesturechange').defaultPrevented,false);
  assert.equal(b.document.changes.length,0);
 }
});
test('authoritative lobby/results, abandoned retries and leaving release a retained reconnect lock',()=>{
 for(const outcome of ['onlineLobby','matchOver','timeout','missingRoom','leave']){
  const b=boot();b.s.mode='online';b.setPhase('playing');resumeConnection(b);
  if(outcome==='timeout')b.s.online.manual=true;
  else if(outcome==='missingRoom'){b.s.online.code='';b.s.online.token='';}
  else if(outcome==='leave')b.s.mode='room';
  else b.s.phase=outcome;
  b.s.syncPauseButton();assert.equal(b.s.matchTouchLocked,false,outcome);
  assert.equal(b.pinch('gesturechange').defaultPrevented,false,outcome);
  for(const list of b.document.handlers.values())assert.equal(list.length,0,outcome);
 }
});


test('mobile HUD, ammo status, sidebar and dialogs reject native selection, callouts and double clicks only during a match',()=>{
 const b=boot();b.selection.isCollapsed=false;b.setPhase('playing');assert.equal(b.selection.cleared,1,'starting clears a selection carried from the lobby');
 for(const id of ['ammoDots','weaponLabel','pilotFeedback','secondAmmoDots','roster','onlineMenuScreen','controlsDialog'])for(const type of ['selectstart','contextmenu','dblclick']){
  assert.equal(b.document.emit(type,{target:b.$(id)}).defaultPrevented,true,id+' '+type);
 }
 assert.equal(b.document.emit('click',{target:b.$('resumeBtn')}).defaultPrevented,false,'ordinary button clicks remain native');
 for(const phase of ['paused','roundOver','countdown']){b.setPhase(phase);assert.equal(b.document.emit('selectstart').defaultPrevented,true);}
 b.setPhase('matchOver');assert.equal(b.document.emit('selectstart').defaultPrevented,false);assert.equal(b.document.emit('dblclick').defaultPrevented,false);
 b.s.touchUI=false;b.setPhase('playing');assert.equal(b.document.emit('selectstart').defaultPrevented,false,'desktop text stays selectable');
});

test('selection changes clear text ranges once while retaining a typing caret and IME composition',()=>{
 const b=boot();b.setPhase('playing');const field={value:'PILOT',selectionStart:0,selectionEnd:5,calls:0,setSelectionRange(start,end){this.selectionStart=start;this.selectionEnd=end;this.calls++;}};
 b.document.activeElement=field;b.selection.isCollapsed=false;b.document.emit('selectionchange',{cancelable:false});
 assert.equal(field.selectionStart,5);assert.equal(field.selectionEnd,5);assert.equal(field.value,'PILOT');assert.equal(b.selection.cleared,1);
 for(let i=0;i<20;i++)b.document.emit('selectionchange',{cancelable:false});assert.equal(field.calls,1);assert.equal(b.selection.cleared,1,'collapsed selection does not cause recursive changes');
 assert.equal(b.document.emit('compositionstart').defaultPrevented,false);field.selectionStart=1;field.selectionEnd=3;b.selection.isCollapsed=false;
 b.document.emit('selectionchange',{cancelable:false});assert.equal(field.calls,1);assert.equal(b.selection.cleared,1,'do not interrupt active IME replacement');
 assert.equal(b.document.emit('compositionend').defaultPrevented,false);assert.equal(field.calls,2);assert.equal(field.selectionStart,3);assert.equal(field.value,'PILOT');
 b.document.emit('compositionstart');b.setPhase('menu');b.setPhase('playing');assert.equal(b.s.matchTextComposing,false,'a later match cannot inherit stale composition state');
});

function queueResult(b){
 const s=b.s;Object.assign(s,{ROUND_END_SECONDS:2,localMatchReport:{},localObjectives:{},performance:{now:()=>1000},pendingGameConfirmation:null,
  clearInput(){},setScreen(){s.syncPauseButton();},updateHUD(){s.syncPauseButton();}});
 b.document.querySelectorAll=()=>[];b.document.querySelector=()=>null;
 for(const name of ['queueMatchPresentation','flushMatchPresentation','closeVictory'])vm.runInContext(declaration(name),s);
 s.phase='matchOver';s.queueMatchPresentation(()=>{s.presented=true;s.syncPauseButton();});
}
test('the actual compact results preview retains the complete touch lock until its final overlay appears',()=>{
 for(const mode of ['room','online']){
  const b=boot();b.s.mode=mode;b.setPhase('playing');if(mode==='online')Object.assign(b.s.online,{code:'ROOM',socket:{},generation:1,roomData:{phase:'matchOver'}});
  queueResult(b);assert.equal(b.s.matchTouchLocked,true);assert.equal(b.$('pauseBtn').hidden,true,'the ended simulation stays unpausable');
  b.s.flushMatchPresentation(2999);assert.equal(b.s.presented,undefined);assert.equal(b.document.emit('selectstart').defaultPrevented,true);assert.equal(b.pinch().defaultPrevented,true);
  b.s.flushMatchPresentation(3000);assert.equal(b.s.presented,true);assert.equal(b.s.matchTouchLocked,false);for(const list of b.document.handlers.values())assert.equal(list.length,0);
 }
});

test('superseded compact results release their touch lock without waiting for another HUD refresh',()=>{
 const b=boot();b.setPhase('playing');queueResult(b);b.s.localMatchReport={};b.s.flushMatchPresentation(1500);
 assert.equal(b.s.pendingMatchPresentation,null);assert.equal(b.s.matchTouchLocked,false);assert.equal(b.s.presented,undefined);
});
