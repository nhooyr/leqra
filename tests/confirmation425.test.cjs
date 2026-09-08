'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){
 let start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);
 if(source.slice(start-6,start)==='async ')start-=6;
 const end=source.indexOf('\n',start),line=source.slice(start,end);
 return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);
}
function boot(){
 const elements=new Map();let doc;
 class Element{
  constructor(tag='div'){this.tagName=tag.toUpperCase();this.children=[];this.listeners=new Map();this.attributes={};this.style={};this.classList={toggle(){}};this.open=false;this.disabled=false;this.value='';this.textContent='';this.isConnected=true;}
  set id(value){this._id=value;elements.set(value,this);}get id(){return this._id;}
  append(...nodes){for(const node of nodes){node.parentElement=this;this.children.push(node);}}
  setAttribute(name,value){this.attributes[name]=value;}
  addEventListener(name,handler){if(!this.listeners.has(name))this.listeners.set(name,[]);this.listeners.get(name).push(handler);}
  dispatch(name){const event={type:name,defaultPrevented:false,preventDefault(){this.defaultPrevented=true;}};for(const handler of this.listeners.get(name)||[])handler(event);return event;}
  showModal(){this.open=true;this.shows=(this.shows||0)+1;}
  close(){this.open=false;if(doc.deferCloseEvents)doc.deferred.push(()=>this.dispatch('close'));else this.dispatch('close');}
  focus(){doc.activeElement=this;}
  closest(){for(let node=this;node;node=node.parentElement)if(node.hidden)return node;return null;}
 }
 doc={body:new Element('body'),createElement:tag=>new Element(tag),activeElement:null,deferred:[]};
 const $=id=>elements.get(id)||null;
 for(const id of ['origin','unshareRoomBtn','roomStatus','presetName','presetSelect','deletePresetBtn']){const node=new Element(id==='origin'?'button':'div');node.id=id;doc.body.append(node);}
 doc.activeElement=$('origin');$('presetName').value='SETUP';$('presetSelect').value='saved:0';
 const own={id:0,member:101,name:'PILOT',hasParty:true},presets=[{name:'SETUP',rules:{scoreTarget:2},roster:[]}];
 const s={console,Promise,mode:'online',phase:'playing',pendingGameConfirmation:null,localMatchStats:{},localRoom:{self:0,players:[own]},
  online:{code:'FIRST',socket:{},member:101,generation:3,connected:true,id:0,roomData:{host:0,phase:'playing'},unsharePending:false},
  document:doc,$,watchInvite:false,watchResume:null,savedPresets:presets,
  localStorage:{getItem:()=>s.stored||null,setItem(key,value){s.stored=value;s.storageWrites=(s.storageWrites||0)+1;}},
  clearInput(){s.clears=(s.clears||0)+1;},sendOnlineInput(){s.releases=(s.releases||0)+1;},toast(message){s.notice=message;},
  roomData:()=>s.online.roomData,localPlayerID:()=>s.online.id,roomMember:()=>own,isRoomHost:()=>s.online.roomData.host===s.online.id,
  sendOnline(message){(s.sent??=[]).push(message);return true;},leaveOnline(){s.left=(s.left||0)+1;s.mode='room';},openOnline(){s.joined=(s.joined||0)+1;},readyRoom(){s.ready=(s.ready||0)+1;},
  localSnapshotFromOnline:()=>({rules:{},players:[]}),resetWatchDialog(){},closeVictory(){s.victoryClosed=true;},
  snapshotPreset:()=>({rules:{scoreTarget:5},roster:[]}),validatePreset:p=>p,renderPresets(){s.rendered=(s.rendered||0)+1;},featureNotice(id,message){s.featureMessage=message;},
  confirm(){throw Error('Native confirm must never be used');}};
 vm.createContext(s);
 for(const name of ['captureActionScope','finishGameConfirmation','confirmGameAction','leaveOnlineMatch','unshareOnlineRoom','returnToRoom','openJoinDialog','saveCurrentPreset','deleteSelectedPreset','returnToMatchParty'])vm.runInContext(declaration(name),s);
 return {s,$,own,elements};
}
function click($,id){const button=$(id);assert.ok(button,'confirmation button exists');button.onclick();}
function configureAction(s,name){if(name==='unshareOnlineRoom'){s.phase='onlineLobby';s.online.roomData.phase='lobby';}}
function mutations(s){return (s.left||0)+(s.joined||0)+(s.storageWrites||0)+(s.sent?.length||0);}

test('confirmation uses text nodes, labelled dialog, Cancel focus, and releases held inputs',async()=>{
 const {s,$}=boot(),origin=$('origin');
 const pending=s.confirmGameAction({title:'Delete <img src=x>?',message:'<script>unsafe</script>',accept:'DELETE'});
 const dialog=$('actionConfirmDialog');assert.ok(dialog.open);assert.match(dialog.className,/feature-dialog/);
 assert.equal(dialog.attributes['aria-labelledby'],'actionConfirmTitle');assert.equal(dialog.attributes['aria-describedby'],'actionConfirmMessage');
 assert.equal($('actionConfirmTitle').textContent,'Delete <img src=x>?');assert.equal($('actionConfirmMessage').textContent,'<script>unsafe</script>');
 assert.equal($('actionConfirmMessage').children.length,0);assert.equal(s.document.activeElement,$('actionConfirmCancel'));assert.ok(s.clears&&s.releases);
 click($,'actionConfirmCancel');assert.equal(await pending,false);assert.equal(dialog.open,false);assert.equal(s.document.activeElement,origin);
});
test('Escape, external close and stale acceptance cancel pending confirmations',async()=>{
 for(const action of ['escape','close','stale']){
  const {s,$}=boot();let current=true;
  const pending=s.confirmGameAction({title:'Proceed?',message:'Review',isCurrent:()=>current});
  if(action==='escape')assert.equal($('actionConfirmDialog').dispatch('cancel').defaultPrevented,true);
  else if(action==='close')$('actionConfirmDialog').close();
  else{current=false;click($,'actionConfirmAccept');}
  assert.equal(await pending,false);assert.equal(s.pendingGameConfirmation,null);
  if(action==='stale')assert.match(s.notice,/no longer available/);
 }
});
test('a duplicate request cannot replace or execute a pending confirmation',async()=>{
 const {s,$}=boot();const first=s.leaveOnlineMatch(),second=s.leaveOnlineMatch();await second;
 assert.equal($('actionConfirmDialog').shows,1);assert.equal(s.left,undefined);
 click($,'actionConfirmAccept');await first;assert.equal(s.left,1);
});
test('a delayed close event from an earlier dialog does not cancel the next confirmation',async()=>{
 const {s,$}=boot();s.document.deferCloseEvents=true;
 const first=s.confirmGameAction({title:'First',message:'First action'});click($,'actionConfirmAccept');assert.equal(await first,true);
 const second=s.confirmGameAction({title:'Second',message:'Second action'});
 for(const dispatch of s.document.deferred.splice(0))dispatch();
 assert.equal($('actionConfirmDialog').open,true);assert.ok(s.pendingGameConfirmation);
 click($,'actionConfirmAccept');assert.equal(await second,true);
});
test('online leave, host end, join, unshare and party-return act only after acceptance',async()=>{
 for(const name of ['leaveOnlineMatch','returnToRoom','openJoinDialog','unshareOnlineRoom','returnToMatchParty'])for(const accept of [false,true]){
  const {s,$}=boot();configureAction(s,name);const pending=s[name]();
  assert.equal(mutations(s),0,name+' waits for input');click($,accept?'actionConfirmAccept':'actionConfirmCancel');await pending;
  assert.equal(mutations(s)>0,accept,name);
  if(accept&&name==='returnToRoom')assert.equal(s.sent[0].type,'lobby');
  if(accept&&name==='unshareOnlineRoom')assert.equal(s.sent[0].type,'unshare');
  if(accept&&name==='returnToMatchParty')assert.equal(s.sent[0].type,'return_party');
 }
});
test('room transfer, a new generation and lost host privileges invalidate pending online actions',async()=>{
 for(const name of ['leaveOnlineMatch','returnToRoom','openJoinDialog','unshareOnlineRoom','returnToMatchParty'])for(const change of ['room','generation']){
  const {s,$}=boot();configureAction(s,name);const pending=s[name]();
  if(change==='room')s.online.code='SECOND';else s.online.generation++;
  click($,'actionConfirmAccept');await pending;assert.equal(mutations(s),0,name+' '+change);
 }
 for(const name of ['returnToRoom','unshareOnlineRoom']){
  const {s,$}=boot();configureAction(s,name);const pending=s[name]();s.online.roomData.host=1;click($,'actionConfirmAccept');await pending;assert.equal(mutations(s),0,name);
 }
});
test('preset replacement and deletion require acceptance and preserve the intended preset',async()=>{
 for(const name of ['saveCurrentPreset','deleteSelectedPreset'])for(const accept of [false,true]){
  const {s,$}=boot();const original=JSON.stringify(s.savedPresets),pending=s[name]();assert.equal(s.storageWrites,undefined);
  click($,accept?'actionConfirmAccept':'actionConfirmCancel');await pending;
  assert.equal(!!s.storageWrites,accept,name);
  if(!accept)assert.equal(JSON.stringify(s.savedPresets),original);
  else if(name==='saveCurrentPreset')assert.equal(s.savedPresets[0].rules.scoreTarget,5);
  else assert.equal(s.savedPresets.length,0);
 }
});
test('changed preset identity, selection or setup cannot be replaced or deleted by a stale dialog',async()=>{
 for(const name of ['saveCurrentPreset','deleteSelectedPreset'])for(const change of ['collection','selection']){
  const {s,$}=boot(),pending=s[name]();
  if(change==='collection')s.savedPresets=[{name:'DIFFERENT',rules:{},roster:[]}];
  else $(name==='saveCurrentPreset'?'presetName':'presetSelect').value=name==='saveCurrentPreset'?'DIFFERENT':'saved:1';
  click($,'actionConfirmAccept');await pending;assert.equal(s.storageWrites,undefined,name+' '+change);
 }
});
test('all seven native confirmations have been removed',()=>{
 assert.equal(/\bconfirm\s*\(/.test(source),false);
});
