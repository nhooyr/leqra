'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),path=require('node:path');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'('),end=source.indexOf('\n',start),line=source.slice(start,end);assert.ok(start>=0,name);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
const clone=value=>JSON.parse(JSON.stringify(value));
function boot(){
 const nodes=new Map(),timers=new Map(),noop=()=>{};let nextTimer=0;
 const $=id=>{if(!nodes.has(id))nodes.set(id,{id,value:'',open:false,disabled:false,dataset:{},classList:{add:noop,remove:noop,toggle:noop},style:{setProperty:noop},parentElement:{querySelector:()=>true},previousElementSibling:{style:{}},close(){this.open=false;}});return nodes.get(id);};
 const s={URL,$,console,mode:'room',phase:'menu',GAME_VERSION:'test',MAX_TANKS:8,POWER:{shield:{},rapid:{}},DIFFICULTY:{normal:{},hard:{},godlike:{},easy:{}},pendingRoomMode:null,rulesPending:false,presetsPending:false,
  online:{connected:false,connecting:false,code:'',token:'',id:3,member:50,snapshots:[]},localRoom:{},matchmaking:{},rolePending:false,
  location:{protocol:'https:',href:'https://leqra.test/'},document:{body:$('body'),querySelectorAll:selector=>selector==='[data-weapon-toggle]'||selector==='[data-weapon-toggle]:checked'?[{dataset:{weaponToggle:'shield'},checked:true}]:[]},
  performance:{now:()=>1000},setTimeout(fn){timers.set(++nextTimer,fn);return nextTimer;},clearTimeout(id){timers.delete(id);},sessionStorage:{removeItem:noop},
  netBusy:noop,setNetStatus:noop,roomMember:(id,r)=>r.players.find(p=>p.id===id),secondaryMember:()=>null,rememberCallsign:noop,rememberLocalCallsign:noop,storeOnlineSession:noop,syncCallsignEditors:noop,updateHUD:noop,clearRestartWavePending:noop,clearRoomModePending:noop,cancelSwap:noop,cancelKick:noop,cancelCallsignSave:noop,clearEndMatchPending:noop,clearInput:noop,syncChatStatus:noop,showReconnecting:noop,scheduleReconnect:noop,
  sendOnline(message){if(s.sendFails)return false;s.sent.push(clone(message));return true;},sent:[],WebSocket:class{constructor(){s.socket=this;this.readyState=1;}close(){this.readyState=3;this.onclose?.();}},
  localPlayerID:()=>s.online.id,roomData:()=>s.online.roomData,teamName:(n,r)=>r.teamNames[n-1],Theme:{colors:[]},updateRuleHelp:noop,renderPowerLegend:noop,
  closeFeature(dialog){dialog.close();s.closed.push(dialog.id);},closed:[],
  syncRoomModePicker(){s.syncRoomSetupPending();},syncFeatureSummary(){s.syncRoomModePicker();const editable=s.roomModeEditable();$('applyRulesBtn').disabled=!editable;$('rulesFields').disabled=!editable;},renderOnlineRoom(){s.syncFeatureSummary();},
  selectedPreset:()=>s.preset};
 vm.createContext(s);
 for(const name of ['defaultRoomRules','defaultModeRules','currentRules','cleanPilotName','validateRoomRules','validateTeamNames','survivalMode','roomCapacity','activeTeamCount','nextRoomTeam','balanceLocalTeams','normalizeRoomTeams','validatePreset','isRoomHost','isRoomEditable','roomModeEditable','roomSetupRulesKey','roomSetupRosterKey','finishRoomSetupRequest','syncRoomSetupPending','sendRoomSetupRequest','featureNotice','fillRulesForm','readRuleTeamSettings','submitRules','setDifficulty','canLoadPreset','applySelectedPreset','connectOnline'])vm.runInContext(declaration(name),s);
 s.connectOnline({type:'join',code:'TEST'},true);timers.clear();Object.assign(s.online,{connected:true,connecting:false,code:'TEST',token:'secret'});s.phase='onlineLobby';
 const players=[{id:0,member:51,kind:'bot',name:'OLD BOT',difficulty:'normal',team:0},{id:3,member:50,kind:'human',name:'HOST',team:0}];
 s.online.roomData={type:'room',code:'TEST',host:3,phase:'lobby',players,spectators:[],rules:s.defaultRoomRules()};s.localRoom.rules=s.defaultRoomRules();
 s.fillRulesForm();$('rulesDialog').open=true;$('rule-scoreTarget').value=9;
 return{s,$,timers,receive:packet=>s.socket.onmessage({data:JSON.stringify(packet)}),room:()=>clone(s.online.roomData),apply:()=>s.submitRules({preventDefault:noop})};
}

test('Rules waits through unrelated live room broadcasts and closes only after all submitted rules match',()=>{
 const b=boot(),{s,$}=b;b.apply();assert.equal(s.rulesPending,true);assert.equal($('applyRulesBtn').disabled,true);assert.equal(s.sent.length,1);
 const stale=b.room();stale.players[0].ready=true;b.receive(stale);assert.equal(s.rulesPending,true);assert.equal($('rulesDialog').open,true);assert.equal($('rule-scoreTarget').value,9);
 b.apply();assert.equal(s.sent.length,1,'duplicate Apply cannot overlap');
 const partial=b.room();partial.rules.scoreTarget=9;b.receive(partial);assert.equal(s.rulesPending,true,'matching only the score is insufficient');
 b.receive({...b.room(),rules:s.sent[0].rules});assert.equal(s.rulesPending,false);assert.equal($('rulesDialog').open,false);assert.deepEqual(s.closed,['rulesDialog']);assert.equal(b.timers.size,0);
});

test('applying identical rules still waits for a fresh room packet',()=>{
 const b=boot(),{s,$}=b;s.online.roomData.rules.weapons=['shield'];s.fillRulesForm();b.apply();assert.equal(s.rulesPending,true);assert.equal($('rulesDialog').open,true);
 s.syncFeatureSummary();assert.equal(s.rulesPending,true);b.receive(b.room());assert.equal(s.rulesPending,false);assert.equal($('rulesDialog').open,false);
});

test('Preset waits for both rules and the complete authoritative roster, with a host in a nonzero seat',()=>{
 const b=boot(),{s,$}=b;s.preset={rules:{...s.defaultRoomRules(),weapons:['shield'],scoreTarget:7},roster:[{kind:'human',name:'NEW HOST',team:0,colorIndex:4},{kind:'local',name:'P2',team:0,colorIndex:7},{kind:'bot',name:'NEW BOT',team:0,difficulty:'godlike',colorIndex:-1}]};
 $('presetsDialog').open=true;s.applySelectedPreset();assert.equal(s.presetsPending,true);s.applySelectedPreset();assert.equal(s.sent.length,1);
 b.receive({...b.room(),rules:s.sent[0].rules});assert.equal(s.presetsPending,true);assert.equal($('presetsDialog').open,true);
 const [host,p2,bot]=s.sent[0].roster;b.receive({...b.room(),players:[{...p2,id:0,owner:3},{...bot,id:1,owner:3},{...host,id:3}],rules:s.sent[0].rules});
 assert.equal(s.presetsPending,false);assert.deepEqual(s.closed,['presetsDialog']);assert.equal(b.timers.size,0);
});

test('disconnect cancels the pending edit, keeps the draft and permits local setup after leaving',()=>{
 const b=boot(),{s,$}=b;b.apply();s.socket.close();assert.equal(s.rulesPending,false);assert.equal(s.online.setupPending,null);assert.equal(b.timers.size,0);assert.equal($('rulesDialog').open,true);assert.equal($('rule-scoreTarget').value,9);assert.match($('rulesNotice').textContent,/Connection changed/);
 s.mode='room';s.phase='menu';s.online.roomData.host=3;s.syncFeatureSummary();assert.equal(s.roomModeEditable(),true);assert.equal($('applyRulesBtn').disabled,false);
});

test('send failure, server rejection and timeout retain the form and release edit locks',()=>{
 for(const failure of ['send','error','timeout']){
  const b=boot(),{s,$}=b;s.sendFails=failure==='send';b.apply();
  if(failure==='error')b.receive({type:'error',action:'rules',message:'The match has started.'});if(failure==='timeout')[...b.timers.values()][0]();
  assert.equal(s.rulesPending,false,failure);assert.equal(s.roomModeEditable(),true,failure);assert.equal($('rulesDialog').open,true);assert.equal($('rule-scoreTarget').value,9);assert.ok($('rulesNotice').textContent);assert.equal(s.closed.length,0);
 }
});

test('connection identity, host and match changes cancel old requests without accepting a different room',()=>{
 for(const change of ['socket','member','host','phase','queue']){
  const b=boot(),{s,$}=b;b.apply();const next={...b.room(),rules:s.sent[0].rules};
  if(change==='socket')s.online.socket={};else if(change==='member')s.online.member++;else if(change==='host')next.host=0;else if(change==='phase')next.phase='countdown';else next.queue={};
  s.online.roomData=next;s.syncFeatureSummary();assert.equal(s.rulesPending,false,change);assert.equal($('rulesDialog').open,true);assert.equal(s.closed.length,0);assert.equal(b.timers.size,0);
 }
});

test('a timed-out request cannot clear a newer retry and a mismatched action error cannot dismiss it',()=>{
 const b=boot(),{s,$}=b;b.apply();const oldTimer=[...b.timers.values()][0];oldTimer();b.apply();assert.equal(s.sent.length,2);const pending=s.online.setupPending;
 oldTimer();assert.equal(s.online.setupPending,pending);b.receive({type:'error',action:'preset',message:'Previous preset rejected.'});assert.equal(s.rulesPending,true);assert.equal(s.online.setupPending,pending);assert.equal($('rulesDialog').open,true);
 b.receive({...b.room(),rules:s.sent[1].rules});assert.equal(s.rulesPending,false);
});


test('saved presets reject inherited object names as bot strengths before local or online mutation',()=>{
 for(const mode of ['room','online'])for(const difficulty of ['constructor','toString','__proto__','hasOwnProperty']){
  const b=boot(),{s,$}=b;s.mode=mode;s.phase=mode==='room'?'menu':'onlineLobby';s.applyLocalPreset=()=>{s.applied=true;};
  s.preset={rules:s.defaultRoomRules(),roster:[{kind:'human',name:'HOST',team:0},{kind:'bot',name:'BOT',team:0,difficulty}]};s.applySelectedPreset();
  assert.equal(s.sent.length,0,difficulty);assert.notEqual(s.applied,true);assert.equal(s.presetsPending,false);assert.match($('presetsNotice').textContent,/Invalid preset participant/);
 }
});

test('saved rule profiles and presets reject inherited object names as power-ups',()=>{
 const {s}=boot();for(const weapon of ['constructor','toString','__proto__']){
  const rules={...s.defaultRoomRules(),weapons:[weapon]};assert.throws(()=>s.validateRoomRules(rules),/Invalid power-up selection/);
  assert.throws(()=>s.validatePreset({rules,roster:[{kind:'human',name:'HOST',team:0}]}),/Invalid power-up selection/);
 }
 for(const difficulty of ['easy','normal','hard','godlike'])assert.equal(s.validatePreset({rules:s.defaultRoomRules(),roster:[{kind:'human',name:'HOST',team:0},{kind:'bot',name:'BOT',team:0,difficulty}]}).roster[1].difficulty,difficulty);
});

test('saved and direct global difficulty selection ignore inherited names',()=>{
 for(const value of ['constructor','toString','__proto__']){
  const {s}=boot();s.difficulty='normal';s.save=()=>{s.saved=true;};s.setDifficulty(value);assert.equal(s.difficulty,'normal');assert.notEqual(s.saved,true);
  s.localStorage={getItem:key=>key==='leqra.difficulty'?value:null};
  vm.runInContext(source.split('\n').find(line=>line.startsWith("try{muted=localStorage.getItem('leqra.muted')")),s);assert.equal(s.difficulty,'normal');
 }
});
