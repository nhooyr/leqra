'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){let start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);if(source.slice(start-6,start)==='async ')start-=6;const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot(){
 const elements=new Map(),timers=new Map();let doc,timerID=0;
 class Element{
  constructor(){this.children=[];this.listeners=new Map();this.style={};this.classList={toggle(){}};this.hidden=false;this.disabled=false;this.open=false;this.textContent='';this.isConnected=true;this.firstChild={textContent:''};}
  set id(id){this._id=id;elements.set(id,this);}get id(){return this._id;}
  append(...children){for(const child of children){this.children.push(child);child.parentElement=this;}}
  setAttribute(name,value){this[name]=value;}addEventListener(name,handler){this.listeners.set(name,handler);}focus(){doc.activeElement=this;}closest(){return null;}
  showModal(){this.open=true;this.shows=(this.shows||0)+1;}close(){this.open=false;this.listeners.get('close')?.();}
 }
 const $=id=>elements.get(id)||null;doc={body:new Element(),createElement:()=>new Element(),activeElement:null,querySelectorAll:()=>[]};
 for(const id of ['announcer','origin','restartWaveBtn','victoryRestartWaveBtn','victoryAgainBtn','victoryCloseBtn']){const e=new Element();e.id=id;doc.body.append(e);}doc.activeElement=$('origin');
 const rules={mode:'survival'},own={id:8,member:108,spectating:true,name:'HOST'},room={host:8,canStart:true,canRestartWave:true,phase:'playing',rules,players:[{id:0,member:100,kind:'bot',connected:true}],spectators:[own]};
 const snapshot={tick:10,generation:1,phase:'playing',objectives:{survival:{wave:5,wavesCleared:4,waveTarget:15,status:'wave'}},tanks:[]};
 const s={console,Promise,ROUND_END_SECONDS:2,mode:'online',phase:'playing',pausedFrom:'playing',localMatchStats:{},localRoom:{self:8,players:[]},localSurvivalCheckpoint:null,pendingGameConfirmation:null,pendingMatchPresentation:null,localMatchReport:null,localObjectives:null,
  online:{code:'ARENA',socket:{},member:108,generation:1,id:8,connected:true,menu:true,roomData:room,snapshots:[snapshot],restartWavePending:null,lastMatch:1,ownedIDs:new Set(),activeIDs:new Set(),localBullets:new Map(),shots:{sync(){},prune(){}},buffer:{push(state){s.online.snapshots.push(state);}}},
  $ ,document:doc,currentRules:()=>rules,roomData:()=>room,localPlayerID:()=>s.online.id,roomMember:()=>own,secondaryMember:()=>null,secondaryID:()=>undefined,secondLocal:()=>null,
  clearInput(){s.clears=(s.clears||0)+1;},sendOnlineInput(){s.releases=(s.releases||0)+1;},toast(message){s.notice=message;},
  sendOnline(message){s.sent.push(message);return s.sendSucceeds;},sent:[],sendSucceeds:true,setTimeout(fn){const id=++timerID;timers.set(id,fn);return id;},clearTimeout(id){timers.delete(id);},
  performance:{now:()=>1000},COLORS:['#fff'],particles:[{}],rings:[{}],traces:[{}],bullets:[{}],pickups:[{}],tanks:[],goUntil:99,bestWins:0,
  Net:{STEP_MS:1000/60,expandMachineBullets:()=>[]},cacheMap(){},resize(){},resetOnlineMotion(){s.online.snapshots=[];},closeVictory(){s.pendingMatchPresentation=null;s.closed=(s.closed||0)+1;},
  setScreen(screen){s.screen=screen;},showStartingControls(){},showLocalSpawnGuide(){},renderOnlineRoom(){},updateHUD(){},onlineEffect(){},showVictory(){s.results=(s.results||0)+1;},save(){},teamKey:t=>t.team,
  startMatch(){s.newRun=true;},matchmaking:{rematchPending:false},requestQueueRematch(){},confirm(){throw Error('Native confirmation is forbidden');}};
 vm.createContext(s);
 for(const name of ['objectiveState','survivalState','survivalMode','canRestartSurvivalWave','syncRestartWaveActions','clearRestartWavePending','captureActionScope','finishGameConfirmation','confirmGameAction','requestRestartSurvivalWave','syncResultActions','quickReplay','netTank','receiveOnlineState','queueMatchPresentation','flushMatchPresentation','onlineMatchResultDelay'])vm.runInContext(declaration(name),s);
 return{s,$,room,own,snapshot,timers};
}
function statePacket({generation=2,tick=11,phase='countdown',status='wave'}={}){return{generation,tick,phase,round:5,roundClock:75,phaseTime:2.6,winner:-1,scores:Array(8).fill(0),tanks:[],bullets:[],events:[],objectives:{survival:{wave:5,wavesCleared:4,waveTarget:15,status}},world:{cols:7,rows:7,width:588,height:588,walls:[]}};}
async function accept(b){const action=b.s.requestRestartSurvivalWave();b.$('actionConfirmAccept').onclick();await action;}

test('online restart uses the game confirmation and sends one host-scoped wave command',async()=>{
 const b=boot(),{s,$}=b,first=s.requestRestartSurvivalWave();assert.equal(s.sent.length,0);assert.equal($('actionConfirmDialog').open,true);assert.equal(docFocus(b),'actionConfirmCancel');
 await s.requestRestartSurvivalWave();assert.equal($('actionConfirmDialog').shows,1);$('actionConfirmAccept').onclick();await first;
 assert.deepEqual(JSON.parse(JSON.stringify(s.sent)),[{type:'restart_wave',generation:1,wave:5}]);assert.equal($('restartWaveBtn').disabled,true);assert.equal($('victoryAgainBtn').disabled,true);assert.ok(s.releases);
 await s.requestRestartSurvivalWave();s.quickReplay();assert.equal(s.sent.length,1);assert.equal(b.timers.size,1);
});
function docFocus(b){return b.s.document.activeElement.id;}
test('cancel and authoritative state changes invalidate online restart confirmation',async()=>{
 for(const change of ['cancel','wave','break','host','connection','generation','phase']){
  const b=boot(),{s,$}=b,action=s.requestRestartSurvivalWave();
  if(change==='cancel')$('actionConfirmCancel').onclick();else{if(change==='wave')b.snapshot.objectives.survival.wave=6;if(change==='break')b.snapshot.objectives.survival.status='break';if(change==='host')b.room.host=0;if(change==='connection')s.online.connected=false;if(change==='generation')s.online.generation++;if(change==='phase')s.phase='matchOver';$('actionConfirmAccept').onclick();}
  await action;assert.equal(s.sent.length,0,change);assert.equal(s.online.restartWavePending,null,change);
 }
});
test('fresh authoritative restart state closes the menu after wave one and allows another loss result',async()=>{
 const b=boot(),{s,$}=b;await accept(b);s.receiveOnlineState(statePacket());
 assert.equal(s.phase,'countdown');assert.equal(s.online.generation,2);assert.equal(s.online.menu,false);assert.equal(s.screen,null);assert.equal(s.online.restartWavePending,null);assert.equal(b.timers.size,0);assert.equal($('restartWaveBtn').disabled,false);assert.equal(s.particles.length+s.rings.length+s.traces.length+s.bullets.length+s.pickups.length,0);
 b.room.phase='matchOver';s.receiveOnlineState(statePacket({generation:2,tick:12,phase:'matchOver',status:'lost'}));assert.equal(s.results,undefined);s.flushMatchPresentation(3000);assert.equal(s.results,1);assert.equal(s.online.lastMatch,2);
});
test('loss results offer wave retry and full replay for spectating hosts of bot squads',async()=>{
 const b=boot(),{s,$}=b;s.phase='matchOver';b.snapshot.objectives.survival.status='lost';s.syncResultActions();
 assert.equal($('victoryRestartWaveBtn').hidden,false);assert.equal($('victoryRestartWaveBtn').textContent,'RESTART WAVE');assert.equal($('victoryAgainBtn').hidden,false);assert.equal($('restartWaveBtn').hidden,true);
 await s.requestRestartSurvivalWave();assert.equal($('actionConfirmDialog'),null);assert.equal(s.sent[0].type,'restart_wave');assert.equal($('victoryRestartWaveBtn').disabled,true);
 s.clearRestartWavePending('Rejected');assert.equal($('victoryAgainBtn').disabled,false);s.quickReplay();assert.equal(s.sent.at(-1).type,'start');
});
test('guests, disconnected hosts, non-Survival games and won runs never get wave retry controls',async()=>{
 for(const change of ['guest','disconnected','queue','matchmaking','away','won','break','lobby','mode','empty','checkpoint']){
  const b=boot(),{s,$}=b;if(change==='guest')b.room.host=0;if(change==='disconnected')s.online.connected=false;if(['queue','matchmaking','away'].includes(change))b.room[change==='away'?'awayMatch':change]={};if(change==='won'){s.phase='matchOver';b.snapshot.objectives.survival.status='won';}if(change==='break')b.snapshot.objectives.survival.status='break';if(change==='lobby')s.phase='onlineLobby';if(change==='mode')b.room.rules.mode='ctf';if(change==='empty')b.room.players=[];if(change==='checkpoint')b.room.canRestartWave=false;
  s.syncRestartWaveActions();assert.equal($('restartWaveBtn').hidden,true,change);assert.equal($('victoryRestartWaveBtn').hidden,true,change);await s.requestRestartSurvivalWave();assert.equal(s.sent.length,0,change);
 }
});
test('send failure, rejection and timeout reenable retry without applying a local online restart',async()=>{
 for(const cause of ['send','reject','timeout']){
  const b=boot(),{s,$}=b;if(cause==='send')s.sendSucceeds=false;await accept(b);if(cause==='reject')s.clearRestartWavePending('The wave has changed.');if(cause==='timeout')for(const fn of [...b.timers.values()])fn();
  assert.equal(s.online.restartWavePending,null,cause);assert.equal($('restartWaveBtn').disabled,false,cause);assert.equal(s.online.generation,1,cause);assert.equal(s.phase,'playing',cause);assert.ok(s.notice,cause);
 }
 assert.match(source,/msg\.action==='restart_wave'\)\{clearRestartWavePending\(msg\.message\)/);
 assert.match(source,/online\.socket===ws\)clearRestartWavePending\(\)/);
});

test('online final state delays results once while duplicate snapshots keep the original deadline',()=>{
 for(const gameMode of ['survival','ctf','koth','elimination']){
  const b=boot(),{s}=b;s.online.lastMatch=-1;b.room.phase='matchOver';b.room.rules.mode=gameMode;
  s.receiveOnlineState(statePacket({generation:1,tick:11,phase:'matchOver',status:'lost'}));assert.equal(s.phase,'matchOver');assert.equal(s.results,undefined);assert.equal(s.screen,null);const pending=s.pendingMatchPresentation;assert.equal(pending.at,3000);
  s.receiveOnlineState(statePacket({generation:1,tick:12,phase:'matchOver',status:'lost'}));assert.equal(s.pendingMatchPresentation,pending,'normal snapshots never extend or duplicate the result reveal');s.flushMatchPresentation(2999);assert.equal(s.results,undefined);s.flushMatchPresentation(3000);assert.equal(s.results,1);s.flushMatchPresentation(4000);assert.equal(s.results,1);
 }
});
test('online round-result delay and joining an already completed match reveal results immediately',()=>{
 for(const previousPhase of ['roundOver','onlineLobby']){
  const b=boot(),{s}=b;s.online.lastMatch=-1;s.phase=previousPhase;s.receiveOnlineState(statePacket({generation:1,tick:11,phase:'matchOver',status:'lost'}));assert.equal(s.results,1,previousPhase);assert.equal(s.pendingMatchPresentation,null);
 }
});
test('online result reveal cannot survive a disconnect, room transfer, new generation or lobby state',()=>{
 for(const action of ['disconnect','room','socket','generation','lobby','restart','room lobby','room countdown']){
  const b=boot(),{s}=b;s.online.lastMatch=-1;b.room.phase='matchOver';s.receiveOnlineState(statePacket({generation:1,tick:11,phase:'matchOver',status:'lost'}));assert.ok(s.pendingMatchPresentation);
  if(action==='disconnect')s.online.connected=false;if(action==='room')s.online.code='ANOTHER';if(action==='socket')s.online.socket={};if(action==='generation')s.online.generation=99;if(action==='room lobby')b.room.phase='lobby';if(action==='room countdown')b.room.phase='countdown';
  if(action==='lobby')s.receiveOnlineState(statePacket({generation:1,tick:12,phase:'lobby',status:'lost'}));if(action==='restart')s.receiveOnlineState(statePacket({generation:2,tick:12,phase:'countdown',status:'wave'}));
  s.flushMatchPresentation(4000);assert.equal(s.results,undefined,action);assert.equal(s.pendingMatchPresentation,null,action);
 }
});

test('a final snapshot arriving before room metadata retains its delayed result',()=>{
 const b=boot(),{s}=b;s.online.lastMatch=-1;
 s.receiveOnlineState(statePacket({generation:1,tick:11,phase:'matchOver',status:'lost'}));const pending=s.pendingMatchPresentation;assert.ok(pending);assert.equal(b.room.phase,'playing');
 s.flushMatchPresentation(3000);assert.equal(s.results,undefined);assert.equal(s.pendingMatchPresentation,pending,'older playing metadata cannot discard the result');s.online.roomData={...b.room,phase:'matchOver'};s.flushMatchPresentation(3001);assert.equal(s.results,1);assert.equal(s.pendingMatchPresentation,null);
});

test('online end timing subtracts the authoritative hold even if roundOver snapshots were skipped',()=>{
 const {s}=boot(),packet={generation:7,tick:220,events:[{generation:6,tick:50,type:'roundEnd'},{generation:7,tick:100,type:'roundEnd'},{generation:7,tick:220,type:'matchEnd'}]};
 assert.equal(s.onlineMatchResultDelay(packet,'playing',false),0);assert.equal(s.onlineMatchResultDelay(packet,'roundOver',false),0);
 packet.tick=160;packet.events.pop();assert.ok(Math.abs(s.onlineMatchResultDelay(packet,'roundOver',false)-1000)<1e-9,'only the remaining part of a partial hold is presented');
 packet.events=[{generation:6,tick:10,type:'roundEnd'},{generation:7,tick:160,type:'matchEnd'}];assert.equal(s.onlineMatchResultDelay(packet,'playing',false),2000,'direct objective, Survival and forfeit finishes start a two-second hold');
 packet.tick=190;assert.equal(s.onlineMatchResultDelay(packet,'playing',false),1500,'late final snapshots do not restart the full timer');assert.equal(s.onlineMatchResultDelay(packet,'onlineLobby',true),0,'joining an already-finished match does not replay its hold');
});

test('online win and loss previews remain visible for exactly the existing two-second result interval',()=>{
 for(const gameMode of ['survival','ctf','koth'])for(const won of [false,true]){
  const b=boot(),{s,$}=b;b.room.rules.mode=gameMode;b.room.phase='matchOver';s.online.lastMatch=-1;
  for(const id of ['announceTop','announceMain','announceSub']){const e=s.document.createElement('div');e.id=id;s.document.body.append(e);}
  s.roundWinner=-1;s.survivalBreak=()=>false;s.survivalBossPreview=()=>null;s.modeLabel=()=>gameMode.toUpperCase();s.winnerName=id=>id===0?'SQUAD':'RIVAL';s.paintColor=c=>c;s.suddenDeath=()=>false;
  for(const name of ['setText','survivalResultText','matchResultPreview'])vm.runInContext(declaration(name),s);
  const hud=declaration('updateHUD'),start=hud.indexOf(" const announce=$('announcer')"),end=hud.indexOf(" if(mode==='online')onlineHUD();",start);
  vm.runInContext('function updateHUD(){\n'+hud.slice(start,end)+'\n}',s);
  const packet=statePacket({generation:1,tick:11,phase:'matchOver',status:won?'won':'lost'});packet.winner=won?0:gameMode==='survival'?-1:1;
  s.receiveOnlineState(packet);assert.equal($('announcer').hidden,false);assert.equal($('announceMain').textContent,gameMode==='survival'?(won?'SURVIVAL COMPLETE':'RUN ENDED'):(won?'SQUAD WINS':'RIVAL WINS'));
  const pending=s.pendingMatchPresentation;s.receiveOnlineState({...packet,tick:12});assert.equal(s.pendingMatchPresentation,pending);s.flushMatchPresentation(2999);assert.equal(s.results,undefined);assert.equal($('announcer').hidden,false);
  s.flushMatchPresentation(3000);assert.equal(s.results,1);assert.equal($('announcer').hidden,true);
 }
});
