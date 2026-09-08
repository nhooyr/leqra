'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
const start=source.indexOf("window.addEventListener('keydown',e=>{",source.indexOf('// All input paths'));
const keyboard=source.slice(start,source.indexOf("window.addEventListener('keyup'",start));
function boot({phase='menu',dialog}={}){
 const elements=new Map(),$=id=>{if(!elements.has(id))elements.set(id,{open:id===dialog});return elements.get(id);};
 const s={mode:'room',phase,bindingCapture:null,keys:new Set(),firePresses:new Set(),fullscreen:0,pause:0,sound:0,$,document:{querySelectorAll:()=>dialog&&['rulesDialog','presetsDialog','controlsDialog','queueDialog'].includes(dialog)?[$(dialog)]:[]},window:{addEventListener(type,fn){if(type==='keydown')s.keydown=fn;}},toggleFullscreen(){s.fullscreen++;},togglePause(){s.pause++;},toggleSound(){s.sound++;},isControlKey:code=>code==='KeyQ',isWeaponKey:code=>code==='KeyQ',primaryFireHeld:()=>false,heldAction:()=>false,primaryFireKey:()=>true,localPlayerID:()=>0,secondaryID:()=>undefined};
 vm.createContext(s);vm.runInContext(keyboard,s);
 s.press=(extra={})=>{const e={code:'KeyF',target:{tagName:'BUTTON'},preventDefault(){this.prevented=true;},...extra};s.keydown(e);return e;};return s;
}
test('F toggles fullscreen from Rules, Presets, Controls and Find Online Battle dialogs',()=>{
 for(const dialog of ['rulesDialog','presetsDialog','controlsDialog','queueDialog','swapDialog','spectatorsDialog','kickDialog','joinDialog'])for(const phase of ['menu','onlineLobby','playing','paused','matchOver']){
  const s=boot({dialog,phase});const e=s.press();assert.equal(s.fullscreen,1,dialog+' / '+phase);assert.equal(e.prevented,true);assert.equal(s.pause,0);assert.equal(s.sound,0);
 }
});
test('fullscreen keeps text entry, native select typeahead, remap capture and system shortcuts intact',()=>{
 for(const target of [{tagName:'INPUT',type:'text'},{tagName:'INPUT',type:'number'},{tagName:'INPUT',type:'search'},{tagName:'INPUT',type:'email'},{tagName:'TEXTAREA'},{tagName:'SELECT'},{tagName:'DIV',isContentEditable:true}]){const s=boot({dialog:'rulesDialog'});const e=s.press({target});assert.equal(s.fullscreen,0);assert.equal(e.prevented,undefined);}
 for(const extra of [{ctrlKey:true},{metaKey:true},{altKey:true}]){const s=boot({dialog:'presetsDialog'});s.press(extra);assert.equal(s.fullscreen,0);}
 const s=boot({dialog:'controlsDialog'});s.bindingCapture={p:0,action:'forward'};s.press();assert.equal(s.fullscreen,0);
});
test('F works while a non-text menu control is focused and does not repeat when held',()=>{
 for(const type of ['checkbox','radio','range','button','submit','reset']){const s=boot({dialog:'controlsDialog'});s.press({target:{tagName:'INPUT',type}});assert.equal(s.fullscreen,1,type);s.press({repeat:true});assert.equal(s.fullscreen,1,type);}
});
test('allowing menu fullscreen does not leak firing, pause or sound shortcuts into dialogs',()=>{
 for(const dialog of ['rulesDialog','presetsDialog','controlsDialog','queueDialog']){const s=boot({dialog,phase:'playing'});for(const code of ['KeyQ','KeyP','Escape','KeyM'])s.press({code});assert.equal(s.keys.size,0);assert.equal(s.firePresses.size,0);assert.equal(s.pause,0);assert.equal(s.sound,0);}
 const s=boot({phase:'playing'});s.press({code:'KeyQ',target:{tagName:'INPUT',type:'checkbox'}});assert.equal(s.keys.size,0);s.press({code:'KeyQ'});assert.equal(s.keys.has('KeyQ'),true);assert.equal(s.firePresses.has(0),true);s.press();assert.equal(s.fullscreen,1);
});
