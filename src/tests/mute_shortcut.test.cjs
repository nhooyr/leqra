'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),vm=require('node:vm');
const {assetPath}=require('./web_assets.cjs');
const game=readFileSync(assetPath('game.js'),'utf8');
const infinity=readFileSync(assetPath('infinite.js'),'utf8');

function declaration(name){
 const start=game.indexOf('function '+name+'(');assert.ok(start>=0,name);
 const end=game.indexOf('\n',start),line=game.slice(start,end);
 return line.endsWith('}')?line:game.slice(start,game.indexOf('\n}',end)+2);
}
function boot({phase='playing',online=false,menu=false,feature=false,result=false}={}){
 const elements=new Map(),storage=new Map(),calls={prime:0,tones:0,levels:[],fullscreen:0,pause:0};
 const $=id=>{
  if(!elements.has(id)){
   const classes=new Set(),attributes={};
   elements.set(id,{open:false,classes,attributes,classList:{toggle(name,on){if(on)classes.add(name);else classes.delete(name);}},setAttribute(name,value){attributes[name]=value;}});
  }
  return elements.get(id);
 };
 const listeners={};
 const s={muted:false,audioVolume:50,bindingCapture:null,phase,mode:online?'online':'room',online:{menu},keys:new Set(),
  $,localStorage:{setItem:(key,value)=>storage.set(key,value)},
  applyAudioLevel(){calls.levels.push(s.muted);},syncVolumeControl(){},
  primeWebAudio(){calls.prime++;},playTone(){calls.tones++;},
  toggleFullscreen(){calls.fullscreen++;},togglePause(){calls.pause++;},
  document:{querySelectorAll:()=>feature?[{open:true}]:[]},
  window:{addEventListener:(type,listener)=>{listeners[type]=listener;}},
  arena:{addEventListener:(type,listener)=>{listeners['infinity-'+type]=listener;}},
  session:{result:result?{}:null,online,joined:true,controllers:[]},pauseMenu:{open:false},
  featureNotice:(id,message)=>{s.notice=message;},renderBindings(){},
  isControlKey:()=>false,sendOnlineInput(){},openPause(){s.pauseMenu.open=true;},resume(){s.pauseMenu.open=false;},
 };
 vm.createContext(s);
 for(const name of ['save','syncSound','toggleSound','composingKey','arenaKeyBlocked','validBinding','captureBinding'])vm.runInContext(declaration(name),s);
 s.art={arenaKeyBlocked:s.arenaKeyBlocked,toggleSound:s.toggleSound,toggleFullscreen:s.toggleFullscreen,chatOpen:()=>false};
 const start=game.indexOf("window.addEventListener('keydown',e=>{\n if(arenaKeyBlocked(e))return;");assert.ok(start>=0);
 vm.runInContext(game.slice(start,game.indexOf("\nwindow.addEventListener('keyup'",start)),s);
 const infiniteStart=infinity.indexOf("arena.addEventListener('keydown', event => {");assert.ok(infiniteStart>=0);
 vm.runInContext(infinity.slice(infiniteStart,infinity.indexOf("\narena.addEventListener('keyup'",infiniteStart)),s);
 s.syncSound();
 function key(surface,code='KeyM',extra={}){
  const event={code,repeat:false,defaultPrevented:false,stopped:false,immediate:false,
   target:{tagName:'CANVAS',type:'',isContentEditable:false},
   preventDefault(){this.defaultPrevented=true;},stopPropagation(){this.stopped=true;},
   stopImmediatePropagation(){this.stopped=this.immediate=true;},...extra};
  s.captureBinding(event);
  if(!event.immediate&&surface==='infinity')listeners['infinity-keydown'](event);
  if(!event.immediate&&!event.stopped)listeners.keydown(event);
  return event;
 }
 return{s,$,storage,calls,key};
}
function assertMuted(b,expected){
 assert.equal(b.s.muted,expected);
 assert.equal(b.storage.get('leqra.muted'),expected?'1':'0');
 for(const id of ['soundBtn','infiniteSoundBtn']){
  assert.equal(b.$(id).classes.has('muted'),expected);
  assert.equal(b.$(id).attributes['aria-pressed'],String(!expected));
  assert.equal(b.$(id).attributes['aria-label'],expected?'Unmute sound':'Mute sound');
 }
 assert.equal(b.calls.levels.at(-1),expected);
 assert.equal(b.s.audioVolume,50,'mute never changes the selected volume');
}

test('M toggles the shared sound state throughout fixed gameplay, menus and dialogs',()=>{
 const cases=[{}, {phase:'menu'}, {phase:'paused'}, {phase:'matchOver'}, {online:true}, {online:true,menu:true}, {phase:'onlineLobby',online:true}, {feature:true}];
 for(const options of cases)for(const target of [{tagName:'CANVAS'},{tagName:'BUTTON'},{tagName:'INPUT',type:'range'},{tagName:'INPUT',type:'checkbox'}]){
  const b=boot(options),event=b.key('fixed','KeyM',{target});assert.equal(event.defaultPrevented,true);
  assertMuted(b,true);assert.equal(b.calls.prime,0);assert.equal(b.calls.tones,0);
  b.key('fixed','KeyM',{target});assertMuted(b,false);assert.equal(b.calls.prime,1);assert.equal(b.calls.tones,1);
  assert.equal(b.calls.fullscreen,0);assert.equal(b.calls.pause,0);
 }
 for(const id of ['swapDialog','spectatorsDialog','kickDialog','joinDialog']){
  const b=boot();b.$(id).open=true;b.key('fixed');assertMuted(b,true);
 }
});
test('M works once in Infinity gameplay, result and connection states without bubbling twice',()=>{
 for(const options of [{},{online:true},{result:true}]){
  const b=boot(options);if(options.online)b.s.session.joined=false;
  const event=b.key('infinity');assert.equal(event.stopped,true);assert.equal(event.defaultPrevented,true);assertMuted(b,true);
  b.key('infinity');assertMuted(b,false);assert.equal(b.calls.prime,1);
 }
});
test('Infinity pause and Controls use the same M shortcut with buttons or volume focused',()=>{
 for(const surface of ['fixed','infinity'])for(const target of [{tagName:'BUTTON'},{tagName:'INPUT',type:'range'}]){
  const b=boot({feature:true});b.s.pauseMenu.open=true;b.$('controlsDialog').open=true;
  b.key(surface,'KeyM',{target});assertMuted(b,true);
 }
});
test('holding M toggles only on the first keydown and another press restores sound',()=>{
 for(const surface of ['fixed','infinity']){
  const b=boot({feature:true});b.key(surface);assertMuted(b,true);
  for(let n=0;n<20;n++){
   const event=b.key(surface,'KeyM',{repeat:true});assert.equal(event.defaultPrevented,true);assertMuted(b,true);
  }
  b.key(surface);assertMuted(b,false);assert.equal(b.calls.prime,1);assert.equal(b.calls.tones,1);
 }
});
test('typing, IME, modifiers and an already handled key retain M on both input paths',()=>{
 const events=[
  ...['text','search','email','number','password'].map(type=>({target:{tagName:'INPUT',type}})),
  {target:{tagName:'TEXTAREA'}},{target:{tagName:'SELECT'}},{target:{tagName:'DIV',isContentEditable:true}},
  {isComposing:true},{keyCode:229},{ctrlKey:true},{metaKey:true},{altKey:true},{defaultPrevented:true},
 ];
 for(const surface of ['fixed','infinity'])for(const extra of events){
  const b=boot({feature:true});b.key(surface,'KeyM',extra);
  assert.equal(b.s.muted,false);assert.equal(b.storage.has('leqra.muted'),false);assert.equal(b.calls.prime,0);
 }
 for(const surface of ['fixed','infinity']){const b=boot();b.key(surface,'KeyM',{shiftKey:true});assertMuted(b,true);}
});
test('M remains reserved during binding capture and cannot mute or become a combat binding',()=>{
 for(const surface of ['fixed','infinity']){
  const b=boot({feature:true}),capture={p:0,action:'fire'};b.s.bindingCapture=capture;b.$('controlsDialog').open=true;
  assert.equal(b.s.validBinding('KeyM'),false);assert.equal(b.s.validBinding('KeyN'),true);
  const event=b.key(surface,'KeyM',{target:{tagName:'BUTTON'}});
  assert.equal(event.immediate,true);assert.equal(event.defaultPrevented,true);assert.equal(b.s.bindingCapture,capture);
  assert.match(b.s.notice,/reserved/);assert.equal(b.s.muted,false);assert.equal(b.storage.has('leqra.muted'),false);
 }
});
test('focused native button and link activation keys are still left to the focused control',()=>{
 for(const surface of ['fixed','infinity'])for(const code of ['Enter','NumpadEnter','Space'])for(const target of [{tagName:'BUTTON'},{tagName:'A'},{tagName:'SUMMARY'},{tagName:'INPUT',type:'submit'}]){
  const b=boot();b.s.isControlKey=()=>true;b.s.session.controllers=[{keys:{[code]:'fire'}}];
  const event=b.key(surface,code,{target});assert.equal(event.defaultPrevented,false);
  assert.equal(b.s.muted,false);assert.equal(b.storage.has('leqra.muted'),false);
 }
});
