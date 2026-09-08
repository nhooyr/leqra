'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
class Element{constructor(){this.value='';this.dataset={};this.attributes={};this.hidden=false;this.disabled=false;this.textContent='';this.style={setProperty:(k,v)=>this[k]=v};this.classList={toggle(){}};}setAttribute(k,v){this.attributes[k]=v;}getAttribute(k){return this.attributes[k];}focus(){this.focused=true;}}
function boot({online=false,count=4}={}){
 const elements=new Map(),$=id=>{if(!elements.has(id)){const el=new Element();el.parentElement=new Element();elements.set(id,el);}return elements.get(id);};
 const choices=['elimination','ctf','koth','survival'].map(id=>{const el=new Element();el.dataset.roomMode=id;return el;});
 const timers=new Map();let timer=0;
 const s={console,mode:online?'online':'room',phase:online?'onlineLobby':'menu',MAX_TANKS:8,pendingRoomMode:null,roomModeObserved:'',roomModeError:'',roomModeContext:'',rulesPending:false,presetsPending:false,escapeHTML:v=>String(v),POWER:{rapid:{},shield:{}},localRoom:{code:'LOCAL',self:0,players:Array.from({length:count},(_,id)=>({id,kind:id?'bot':'human',team:0,connected:true})),rules:null},online:{id:0,member:1,code:'ONLINE',connected:true,socket:{},roomData:null},$,document:{querySelectorAll:selector=>selector==='[data-room-mode]'?choices:[],createElement:()=>new Element()},sent:[],sendOnline(message){s.sent.push(message);return !s.sendFails;},setTimeout(fn){timers.set(++timer,fn);return timer;},clearTimeout(id){timers.delete(id);},persistLocalRoomRules(r){s.persisted=r;},resetPreviewIfLobby(options){s.preview=options;},renderOnlineRoom(){s.syncRoomModePicker();},syncFeatureSummary(){s.syncRoomModePicker();},localPlayerID:()=>s.mode==='online'?s.online.id:s.localRoom.self,roomMembers:r=>r?.players||s.localRoom.players};
 s.roomData=()=>s.mode==='online'?s.online.roomData:{host:0,players:s.localRoom.players.filter(p=>!p.spectating),rules:s.localRoom.rules};
 vm.createContext(s);vm.runInContext(source.slice(source.indexOf('const ROOM_MODES='),source.indexOf('function roomModeEditable(')),s);
 for(const name of ['defaultRoomRules','currentRules','validateTeamNames','validateRoomRules','activeTeamCount','nextRoomTeam','balanceLocalTeams','normalizeRoomTeams','setLocalRules','isRoomHost','isRoomEditable','roomModeEditable','rulesForRoomMode','clearRoomModePending','paintRoomModeChoice','syncRoomModePicker','rejectRoomMode','selectRoomMode','selectRoomSetting','roomModeKeydown','initRoomModePicker','modeLabel','updateRuleHelp','readRuleTeamSettings','submitRules'])vm.runInContext(declaration(name),s);
 s.localRoom.rules=s.defaultRoomRules();s.online.roomData={host:0,players:s.localRoom.players,rules:s.defaultRoomRules()};s.syncRoomModePicker();s.choices=choices;return {s,$,choices,timers};
}
test('home selection applies mode defaults while preserving map, power-ups and team identity',()=>{
 const {s,$}=boot();s.localRoom.rules={...s.localRoom.rules,mapSize:'huge',pickupRate:'slow',friendlyFire:true,respawnSeconds:7,teamNames:['A','B','C','D'],weapons:['shield']};
 for(const [mode,score,time,team]of[['ctf',3,180,'teams'],['koth',30,180,'teams'],['survival',10,75,'teams'],['elimination',5,75,'teams']]){
  assert.equal(s.selectRoomMode(mode),true);const r=s.currentRules();assert.equal(r.mode,mode);assert.equal(r.scoreTarget,score);assert.equal(r.timeLimit,time);assert.equal(r.teamMode,team);assert.equal(r.mapSize,'huge');assert.equal(r.pickupRate,'slow');assert.equal(r.respawnSeconds,7);assert.equal(r.friendlyFire,true);assert.deepEqual(Array.from(r.weapons),['shield']);assert.deepEqual(Array.from(r.teamNames),['A','B','C','D']);assert.equal(s.preview.regenerateMaze,false);assert.equal(s.preview.resetPickups,false);assert.equal(s.persisted.mode,mode);assert.equal(s.choices.find(b=>b.getAttribute('aria-checked')==='true').dataset.roomMode,r.mode);
 }
});
test('clicking the current mode preserves custom score and time; Hill keeps FFA when available',()=>{
 const {s}=boot();s.localRoom.rules.scoreTarget=19;s.localRoom.rules.timeLimit=320;
 assert.equal(s.selectRoomMode('elimination'),true);assert.equal(s.currentRules().scoreTarget,19);assert.equal(s.currentRules().timeLimit,320);assert.equal(s.preview,undefined);
 assert.equal(s.selectRoomMode('koth'),true);assert.equal(s.currentRules().teamMode,'ffa');
});
test('CTF and survival normalize the entire existing lineup without replacing participants',()=>{
 const {s}=boot();const players=s.localRoom.players;s.selectRoomMode('ctf');assert.deepEqual(players.map(p=>p.team),[1,2,1,2]);s.selectRoomMode('survival');assert.deepEqual(players.map(p=>p.team),[1,1,1,1]);s.selectRoomMode('elimination');assert.deepEqual(players.map(p=>p.team),[1,2,3,4]);assert.equal(s.localRoom.players,players);
});
test('oversized survival squads roll back before local mutation or any online message',()=>{
 for(const online of [false,true]){const {s,$}=boot({online,count:5}),before=JSON.stringify(s.currentRules());assert.equal(s.selectRoomMode('survival'),false);assert.equal(JSON.stringify(s.currentRules()),before);assert.equal(s.sent.length,0);assert.equal(String(s.choices.findIndex(b=>b.getAttribute('aria-checked')==='true')),'0');assert.match($('roomModeNotice').textContent,/four squad tanks/);assert.equal(s.roomData().players.length,5);}
});
test('icon buttons expose one checked mode and one tab stop without a range slider',()=>{
 const {s,choices}=boot();let markup='';s.initRoomModePicker({before(picker){markup=picker.innerHTML;}});
 assert.doesNotMatch(markup,/type="range"|roomModeSlider/);assert.match(markup,/role="radiogroup"/);assert.equal((markup.match(/role="radio"/g)||[]).length,4);
 for(const [index,choice] of choices.entries()){choice.onclick();assert.equal(s.currentRules().mode,choice.dataset.roomMode);assert.equal(choices.filter(b=>b.getAttribute('aria-checked')==='true').length,1);assert.equal(choices.filter(b=>b.tabIndex===0).length,1);assert.equal(choices[index].tabIndex,0);}
});
test('online selection waits for the matching authoritative mode and blocks duplicate requests',()=>{
 const {s,$,timers}=boot({online:true});s.selectRoomMode('ctf');assert.equal(s.sent[0].type,'rules');assert.equal(s.sent[0].rules.teamMode,'teams');assert.equal(s.currentRules().mode,'elimination');assert.equal(s.choices.every(b=>b.disabled),true);assert.match($('roomModeNotice').textContent,/Applying Capture/);assert.equal(s.selectRoomMode('koth'),false);assert.equal(s.sent.length,1);
 s.online.roomData={...s.online.roomData,players:[...s.online.roomData.players]};s.syncRoomModePicker();assert.ok(s.pendingRoomMode,'unrelated roster packet must not acknowledge mode');
 s.online.roomData.rules=s.sent[0].rules;s.syncRoomModePicker();assert.equal(s.pendingRoomMode,null);assert.equal(s.choices.every(b=>b.disabled),false);assert.equal(String(s.choices.findIndex(b=>b.getAttribute('aria-checked')==='true')),'1');assert.equal(timers.size,0);
});
test('online failure, server rejection and acknowledgement timeout restore the real selection',()=>{
 for(const failure of ['send','server','timeout']){const {s,$,timers}=boot({online:true});s.sendFails=failure==='send';s.selectRoomMode('koth');if(failure==='server')s.rejectRoomMode('The roster changed.');if(failure==='timeout')[...timers.values()][0]();assert.equal(s.currentRules().mode,'elimination');assert.equal(s.pendingRoomMode,null);assert.equal(s.choices.every(b=>b.disabled),false);assert.equal(String(s.choices.findIndex(b=>b.getAttribute('aria-checked')==='true')),'0');assert.ok($('roomModeNotice').textContent.length>0);}
 assert.match(source,/if\(msg.action==='rules'&&pendingRoomMode\)\{rejectRoomMode\(msg.message\);break;\}/);
});
test('guests, active matches, matchmaking, disconnection and other pending settings are read-only',()=>{
 for(const scenario of ['guest','playing','queue','matchmaking','awayMatch','disconnected','rules','preset']){const {s,$}=boot({online:true});if(scenario==='guest')s.online.roomData.host=1;else if(scenario==='playing')s.phase='playing';else if(scenario==='disconnected')s.online.connected=false;else if(scenario==='rules')s.rulesPending=true;else if(scenario==='preset')s.presetsPending=true;else s.online.roomData[scenario]={};s.syncRoomModePicker();assert.equal(s.choices.every(b=>b.disabled),true,scenario);assert.equal(s.selectRoomMode('ctf'),false,scenario);assert.equal(s.sent.length,0,scenario);}
});
test('preset changes, authoritative updates and reconnects refresh the selector without stale pending state',()=>{
 const local=boot();local.s.localRoom.rules=local.s.rulesForRoomMode('survival');local.s.syncRoomModePicker();assert.equal(String(local.choices.findIndex(b=>b.getAttribute('aria-checked')==='true')),'3');
 const {s,$,timers}=boot({online:true});s.selectRoomMode('ctf');s.online.socket={};s.online.roomData.rules=s.rulesForRoomMode('koth');s.syncRoomModePicker();assert.equal(s.pendingRoomMode,null);assert.equal(String(s.choices.findIndex(b=>b.getAttribute('aria-checked')==='true')),'2');assert.equal(timers.size,0);s.online.roomData.host=1;s.syncRoomModePicker();assert.equal(s.choices.every(b=>b.disabled),true);assert.match($('roomModeNotice').textContent,/host/);
});
test('Rules use the selected mode without a second mode dropdown',()=>{
 const {s,$}=boot();s.selectRoomMode('survival');Object.assign(s,{mapDimensions:()=>[12,10],pickupLimitText:()=>'',pickupLifetime:()=>30});s.updateRuleHelp();assert.equal($('roomTeamMode').value,'teams');assert.equal($('roomTeamMode').disabled,true);assert.equal($('ruleScoreLabel').textContent,'WAVES TO SURVIVE');assert.equal($('rulesModeName').textContent,'SURVIVAL');assert.equal($('rule-respawnSeconds').parentElement.hidden,true);
 assert.doesNotMatch(source,/id="rule-mode"|\$\('rule-mode'\)|RULES & MODE/);assert.doesNotMatch(source,/id="rule-(teamMode|mapSize)"|\$\('rule-(teamMode|mapSize)'\)/);assert.match(declaration('submitRules'),/const r=\{\.\.\.currentRules\(\)/);
});
test('arrow keys wrap across mode choices; Home and End reach the first and last',()=>{
 const {s,choices}=boot();let index=0;
 for(const [code,want] of [['ArrowRight',1],['ArrowDown',2],['End',3],['ArrowRight',0],['ArrowLeft',3],['Home',0],['ArrowUp',3]]){
  let prevented=false;s.roomModeKeydown({code,currentTarget:choices[index],preventDefault(){prevented=true;}});assert.equal(prevented,true);assert.equal(s.currentRules().mode,choices[want].dataset.roomMode);assert.equal(choices[want].focused,true);assert.equal(choices[want].tabIndex,0);index=want;
 }
});
test('mode keys ignore shortcuts, unrelated keys, repeats and unavailable editing',()=>{
 for(const extra of [{ctrlKey:true},{metaKey:true},{altKey:true},{repeat:true},{code:'KeyF'},{code:'Tab'}]){const {s,choices}=boot();s.roomModeKeydown({code:'ArrowRight',currentTarget:choices[0],preventDefault(){},...extra});assert.equal(s.currentRules().mode,'elimination');}
 const {s,choices}=boot({online:true});s.online.roomData.host=1;s.roomModeKeydown({code:'ArrowRight',currentTarget:choices[0],preventDefault(){}});assert.equal(s.sent.length,0);assert.equal(choices.some(b=>b.focused),false);
});
test('authoritative updates clear rejection messages and preserve the selected mode after lost edit access',()=>{
 const {s,$}=boot({online:true});s.rejectRoomMode('The squad is too large.');s.online.roomData.rules=s.rulesForRoomMode('koth');s.syncRoomModePicker();assert.equal(s.roomModeError,'');assert.equal(String(s.choices.findIndex(b=>b.getAttribute('aria-checked')==='true')),'2');assert.equal($('roomModeNotice').hidden,true);
 s.online.roomData.host=1;s.syncRoomModePicker();assert.equal(String(s.choices.findIndex(b=>b.getAttribute('aria-checked')==='true')),'2');assert.equal(s.choices.every(b=>b.disabled),true);
});
test('an open Rules form refreshes when its authoritative mode changes, preserving drafts on unrelated updates',()=>{
 const {s,$}=boot({online:true});Object.assign(s,{displayScoreTarget:()=>'',modeInstructions:()=>'',roomStartError:()=>'',controlSummary:()=>'',fieldManualHTML:()=>'',Theme:{colors:['a','b','c','d']},teamName:(i,r)=>r.teamNames[i-1],renderPowerLegend(){},updateRuleHelp(){s.helpUpdates=(s.helpUpdates||0)+1;}});
 for(let i=1;i<=4;i++){$('rule-teamName'+i).parentElement.querySelector=()=>({});$('rule-teamColor'+i).previousElementSibling={style:{}};}
 for(const name of ['featureNotice','fillRulesForm','syncFeatureSummary'])vm.runInContext(declaration(name),s);
 s.fillRulesForm();$('rulesDialog').open=true;$('rule-scoreTarget').value='19';s.syncFeatureSummary();assert.equal($('rule-scoreTarget').value,'19');assert.equal($('rulesDialog').dataset.mode,'elimination');
 s.online.roomData.rules=s.rulesForRoomMode('koth');s.syncFeatureSummary();assert.equal($('rule-scoreTarget').value,30);assert.equal($('rule-timeLimit').value,180);assert.equal($('rulesDialog').dataset.mode,'koth');
 $('rule-timeLimit').value='222';s.online.roomData.players[1].ready=true;s.syncFeatureSummary();assert.equal($('rule-timeLimit').value,'222');
});

// Lobby setting regressions exercise the shipped request and local rule paths.
test('lobby format balances teams while map changes alone regenerate the maze',()=>{
 const {s,$}=boot();s.localRoom.rules.scoreTarget=17;s.localRoom.rules.timeLimit=240;
 assert.equal(s.selectRoomSetting('teamMode','teams'),true);assert.deepEqual(s.localRoom.players.map(p=>p.team),[1,2,3,4]);assert.equal(s.preview.regenerateMaze,false);
 s.localRoom.players[1].team=1;assert.equal(s.selectRoomSetting('mapSize','huge'),true);assert.equal(s.preview.regenerateMaze,true);assert.equal(s.localRoom.players[1].team,1);assert.equal(s.currentRules().scoreTarget,17);assert.equal(s.currentRules().timeLimit,240);assert.equal($('roomMapSize').value,'huge');
 s.preview=undefined;assert.equal(s.selectRoomSetting('mapSize','huge'),true);assert.equal(s.preview,undefined);
 assert.equal(s.selectRoomSetting('teamMode','ffa'),true);assert.deepEqual(s.localRoom.players.map(p=>p.team),[0,0,0,0]);assert.equal(s.preview.regenerateMaze,false);
});
test('lobby format and map wait for matching authoritative fields and roll back failures',()=>{
 for(const [field,value,id] of [['teamMode','teams','roomTeamMode'],['mapSize','huge','roomMapSize']]){
  const {s,$}=boot({online:true}),before=s.currentRules()[field];assert.equal(s.selectRoomSetting(field,value),true);assert.equal(s.sent.length,1);assert.equal(s.currentRules()[field],before);assert.equal($(id).value,before);assert.equal($('roomTeamMode').disabled,true);assert.equal($('roomMapSize').disabled,true);assert.equal(s.selectRoomMode('ctf'),false);
  s.online.roomData={...s.online.roomData,players:[...s.online.roomData.players]};s.syncRoomModePicker();assert.ok(s.pendingRoomMode,'unchanged mode must not acknowledge a format/map request');
  s.online.roomData.rules=s.sent[0].rules;s.syncRoomModePicker();assert.equal(s.pendingRoomMode,null);assert.equal($(id).value,value);assert.equal($(id).disabled,false);
  for(const failure of ['send','server','timeout','disconnect','socket']){
   const b=boot({online:true});b.s.sendFails=failure==='send';b.$(id).value=value;b.s.selectRoomSetting(field,value);
   if(failure==='server')b.s.rejectRoomMode('Rejected');if(failure==='timeout')[...b.timers.values()][0]();if(failure==='disconnect'){b.s.online.connected=false;b.s.syncRoomModePicker();}if(failure==='socket'){b.s.online.socket={};b.s.syncRoomModePicker();}
   assert.equal(b.s.pendingRoomMode,null,failure);assert.equal(b.$(id).value,b.s.currentRules()[field],failure);
  }
 }
});
test('lobby format and map honor all host permissions and keep objective teams locked',()=>{
 for(const scenario of ['guest','playing','queue','matchmaking','awayMatch','disconnected','rules','preset']){
  const {s,$}=boot({online:true});if(scenario==='guest')s.online.roomData.host=1;else if(scenario==='playing')s.phase='playing';else if(scenario==='disconnected')s.online.connected=false;else if(scenario==='rules')s.rulesPending=true;else if(scenario==='preset')s.presetsPending=true;else s.online.roomData[scenario]={};s.syncRoomModePicker();
  assert.equal($('roomTeamMode').disabled,true,scenario);assert.equal($('roomMapSize').disabled,true,scenario);assert.equal(s.selectRoomSetting('teamMode','teams'),false,scenario);assert.equal(s.selectRoomSetting('mapSize','huge'),false,scenario);assert.equal(s.sent.length,0,scenario);
 }
 for(const mode of ['ctf','survival']){const {s,$}=boot();s.selectRoomMode(mode);assert.equal($('roomTeamMode').disabled,true);assert.equal($('roomMapSize').disabled,false);assert.equal(s.selectRoomSetting('teamMode','ffa'),false);assert.equal(s.currentRules().teamMode,'teams');assert.equal(s.selectRoomSetting('mapSize','compact'),true);}
});
test('lobby selectors follow mode in reading order and replace the Rules fields',()=>{
 const {s,$}=boot();let html='';s.initRoomModePicker({before(p){html=p.innerHTML;}});
 assert.ok(html.indexOf('id="roomModeChoices"')<html.indexOf('id="roomTeamMode"'));assert.ok(html.indexOf('id="roomTeamMode"')<html.indexOf('id="roomMapSize"'));assert.equal((html.match(/id="roomMapSize"/g)||[]).length,1);
 $('roomTeamMode').onchange({target:{value:'teams'}});assert.equal(s.currentRules().teamMode,'teams');$('roomMapSize').onchange({target:{value:'giant'}});assert.equal(s.currentRules().mapSize,'giant');
 assert.doesNotMatch(declaration('initFeatures'),/rule-(teamMode|mapSize)/);
 const index=readFileSync(path.join(__dirname,'../web/index.html'),'utf8');assert.match(index,/id="startRoomBtn"[^>]*><span>START BUTTON<\/span>/);assert.match(declaration('renderOnlineRoom'),/firstElementChild.textContent='START BUTTON'/);
});

test('Hill defaults use 30 points while saved and current custom targets survive setup edits',()=>{
 const {s}=boot();Object.assign(s,{roomMember:()=>({name:'P1'}),savedLocalCallsign:()=> 'P2'});vm.runInContext(declaration('builtinPresets'),s);
 assert.equal(s.builtinPresets().find(p=>p.rules.mode==='koth').rules.scoreTarget,30);assert.equal(s.rulesForRoomMode('koth').scoreTarget,30);
 s.localRoom.rules=s.validateRoomRules({...s.currentRules(),mode:'koth',scoreTarget:88,timeLimit:360});s.selectRoomMode('koth');s.selectRoomSetting('mapSize','huge');s.selectRoomSetting('teamMode','teams');assert.equal(s.currentRules().scoreTarget,88);assert.equal(s.currentRules().timeLimit,360);
 assert.match(source,/key:'koth-3'[^\n]+target:30,seconds:180/);assert.doesNotMatch(source,/First to 60 hill points/);
});

test('Rules submission retains current lobby format and map without reading removed fields',()=>{
 const {s,$}=boot({online:true});s.online.roomData.rules={...s.currentRules(),mode:'koth',teamMode:'ffa',mapSize:'giant',scoreTarget:44,timeLimit:222};
 Object.assign(s,{teamName:(i,r)=>r.teamNames[i-1],featureNotice(){}});$('rule-scoreTarget').value='51';$('rule-timeLimit').value='333';$('rule-respawnSeconds').value='4';$('rule-pickupRate').value='slow';$('rule-friendlyFire').checked=false;
 s.submitRules({preventDefault(){}});assert.equal(s.sent.length,1);const r=s.sent[0].rules;assert.equal(r.mode,'koth');assert.equal(r.teamMode,'ffa');assert.equal(r.mapSize,'giant');assert.equal(r.scoreTarget,51);assert.equal(r.timeLimit,333);assert.equal(r.pickupRate,'slow');assert.equal(s.rulesPending,true);
});
