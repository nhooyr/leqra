'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),{assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8');
const start=source.indexOf('function prepareUpdate(');
assert.ok(start>=0,'the public update preparation hook exists');
const declaration=source.slice(start,source.indexOf('\n}',start)+2);
function harness(){
 const elements=new Map(),$=id=>{if(!elements.has(id))elements.set(id,{hidden:false,open:false,value:''});return elements.get(id);};
 const state={mode:'room',phase:'menu',online:{},matchmaking:{},headerLoan:null,pendingRoomMode:null,rulesPending:false,presetsPending:false,rolePending:false,swapPending:null,pendingGameConfirmation:null,pendingMatchPresentation:null,bindingCapture:null,
  roomChat:{open:false,draft:'',channels:{room:{},opponent:{}}},room:{},forms:[],writes:0,stored:true,
  $,
  document:{hidden:false,activeElement:null,querySelector:()=>state.modal||null},
  roomData:()=>state.room,callsignForms:()=>state.forms,
  persistLocalRoomRules:()=>{state.writes++;if(state.storageError)throw Error('Storage failed');return state.stored;},
 };
 vm.createContext(state);vm.runInContext(declaration,state);return state;
}

test('an idle offline room saves its configuration before allowing a page update',()=>{
 const state=harness();assert.equal(state.prepareUpdate(),true);assert.equal(state.writes,1);
 state.phase='matchOver';assert.equal(state.prepareUpdate(),true);
 state.$('roomScreen').hidden=true;assert.equal(state.prepareUpdate(),false);
});

test('updates defer when configuration cannot be saved',()=>{
 for(const options of [{stored:false},{storageError:true}]){
  const state=Object.assign(harness(),options);assert.equal(state.prepareUpdate(),false);assert.equal(state.writes,1);
 }
});

test('active games, Infinity, dialogs and hidden pages never reload',()=>{
 for(const phase of ['countdown','playing','paused','roundOver','onlineLobby','starting']){
  const state=harness();state.phase=phase;assert.equal(state.prepareUpdate(),false,phase);assert.equal(state.writes,0);
 }
 for(const block of [s=>s.$('infiniteArena').open=true,s=>s.headerLoan={},s=>s.modal={},s=>s.document.hidden=true]){
  const state=harness();block(state);assert.equal(state.prepareUpdate(),false);assert.equal(state.writes,0);
 }
});

test('all online sessions and unresolved room operations defer the update',()=>{
 const onlineFields=['connected','connecting','socket','code','token','publishing','restoreInfinity','retryAt','setupPending','renamePending','roomRenamePending','unsharePending','kickPending','endMatchPending','restartWavePending'];
 for(const field of onlineFields){const state=harness();state.online[field]={};assert.equal(state.prepareUpdate(),false,field);assert.equal(state.writes,0);}
 const online=harness();online.mode='online';assert.equal(online.prepareUpdate(),false,'even an apparently idle online lobby can have an unacknowledged start');
 for(const field of ['pendingRoomMode','rulesPending','presetsPending','rolePending','swapPending','pendingGameConfirmation','pendingMatchPresentation','bindingCapture']){
  const state=harness();state[field]={};assert.equal(state.prepareUpdate(),false,field);
 }
 for(const field of ['pending','pendingKey','rematchPending']){const state=harness();state.matchmaking[field]={};assert.equal(state.prepareUpdate(),false,field);}
 for(const field of ['queue','matchmaking','awayMatch','infinityActive']){const state=harness();state.room[field]={};assert.equal(state.prepareUpdate(),false,field);}
});

test('chat drafts and unconfirmed messages survive a pending update',()=>{
 for(const change of [s=>s.roomChat.open=true,s=>s.roomChat.draft='Unsent',s=>s.$('chatInput').value='Draft',
  s=>s.roomChat.channels.room.pending={text:'Sending'},s=>s.roomChat.channels.opponent.unconfirmed={text:'Retry'}]){
  const state=harness();change(state);assert.equal(state.prepareUpdate(),false);assert.equal(state.writes,0);
 }
});

test('leaving an online room permits an idle update despite cancelled operation history',()=>{
 const state=harness();state.online={manual:true,retryAt:1000,roomRenamePending:true,setupPending:{type:'rules'}};
 assert.equal(state.prepareUpdate(),true);
 state.mode='online';assert.equal(state.prepareUpdate(),false,'a manual flag never permits an active online context to reload');
});

test('focused editors and dirty callsigns defer updates until editing finishes',()=>{
 for(const activeElement of [{isContentEditable:true},{matches:selector=>selector==='input,textarea,select'}]){
  const state=harness();state.document.activeElement=activeElement;assert.equal(state.prepareUpdate(),false);
 }
 const state=harness(),form={elements:{callsign:{value:'Changed'}},dataset:{currentName:'Saved'}};state.forms=[form];
 assert.equal(state.prepareUpdate(),false);assert.equal(state.writes,0);
 form.elements.callsign.value='Saved ';assert.equal(state.prepareUpdate(),false,'raw unsaved whitespace is also protected');
 form.elements.callsign.value='Saved';assert.equal(state.prepareUpdate(),true);assert.equal(state.writes,1);
});
