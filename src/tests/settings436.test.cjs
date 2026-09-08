'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),{readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
const clone=x=>JSON.parse(JSON.stringify(x));
function boot(storage=new Map(),touchUI=false){
 const elements=new Map(),toggles=['rapid','shield','laser'].map(weapon=>({dataset:{weaponToggle:weapon},checked:true}));
 const $=id=>{if(!elements.has(id))elements.set(id,{value:'',checked:false,disabled:false,dataset:{},style:{},classList:{toggle(){}},previousElementSibling:{style:{}},parentElement:{querySelector(){return true;}}});return elements.get(id);};
 const s={console,mode:'room',phase:'menu',touchUI,MAX_TANKS:8,POWER:{rapid:{},shield:{},laser:{}},DIFFICULTY:{easy:{},normal:{},hard:{},godlike:{}},ROOM_MODES:['elimination','ctf','koth','survival'].map(id=>({id})),localRoom:{self:0,nextMember:0,nextViewer:8,players:[]},online:{id:0,connected:true,roomData:null,snapshots:[]},pendingRoomMode:null,rulesPending:false,presetsPending:false,
 localStorage:{getItem:key=>storage.get(key)||null,setItem(key,value){if(s.storageFails)throw Error('Storage unavailable');storage.set(key,value);s.writes++;}},writes:0,
 $,document:{querySelectorAll:selector=>selector.endsWith(':checked')?toggles.filter(c=>c.checked):toggles},Theme:{colors:['a','b','c','d','e','f','g','h']},teamName:(n,r)=>r.teamNames[n-1],featureNotice(id,message){$(id).textContent=message;},updateRuleHelp(){},renderPowerLegend(){},isRoomEditable:()=>s.editable!==false,roomData:()=>({rules:s.localRoom.rules,players:s.localRoom.players.filter(p=>!p.spectating)}),roomModeEditable:()=>s.editable!==false,rejectRoomMode(message){s.rejected=message;},localPlayerID:()=>s.mode==='online'?s.online.id:s.localRoom.self,roomMembers:r=>[...r.players,...(r.spectators||[])],setLocalRules(r){s.localRoom.rules=s.validateRoomRules(r);s.persistLocalRoomRules(r);},setTimeout(){return 1;},clearTimeout(){},syncFeatureSummary(){},syncRoomModePicker(){},sendOnline(message){s.sent=message;return !s.sendFails;},closeFeature(){s.closed=true;}};
 vm.createContext(s);vm.runInContext("const LOCAL_RULES_KEY='leqra.roomRules.v1',ROOM_SETUP_KEY='leqra.roomSetup.v2';let rememberedRoomSetup=null,lastPersistedRoomSetup='';",s);
 for(const name of ['defaultRoomRules','defaultModeRules','defaultLocalRoomRules','validateTeamNames','validateRoomRules','cleanPilotName','survivalMode','roomCapacity','currentRules','activeTeamCount','nextRoomTeam','balanceLocalTeams','normalizeRoomTeams','validateSavedRoster','loadRememberedRoomSetup','loadLocalRoomRules','rememberedRulesForMode','persistLocalRoomRules','rememberRenderedRoomSetup','restoreSavedLocalRoster','rulesForRoomMode','selectRoomMode','selectRoomSetting','roomModeEditable','modeLabel','fillRulesForm','resetRuleDefaults','readRuleTeamSettings','submitRules','roomSetupRulesKey','roomSetupRosterKey','finishRoomSetupRequest','syncRoomSetupPending','sendRoomSetupRequest'])vm.runInContext(declaration(name),s);
 s.localRoom.rules=s.loadLocalRoomRules();return {s,$,storage,toggles};
}
const pilot=(options={})=>({id:0,kind:'human',name:'PILOT',team:0,...options});
const bot=(options={})=>({id:1,kind:'bot',name:'RUST',team:0,difficulty:'normal',...options});

test('each mode remembers its rules through mode changes and a fresh page load, keeping the selected map',()=>{
 const {s,storage}=boot();s.localRoom.players=[pilot(),bot()];
 const choices=[['elimination',9,90,'slow'],['ctf',7,210,'fast'],['koth',61,240,'off'],['survival',18,300,'normal']];
 for(const [mode,scoreTarget,timeLimit,pickupRate]of choices){s.localRoom.rules={...s.rulesForRoomMode(mode),scoreTarget,timeLimit,pickupRate,mapSize:'ultrawide',weapons:['shield']};assert.equal(s.persistLocalRoomRules(),true);}
 const next=boot(storage).s;assert.equal(next.localRoom.rules.mode,'survival');assert.equal(next.localRoom.rules.scoreTarget,18);next.restoreSavedLocalRoster();
 for(const [mode,scoreTarget,timeLimit,pickupRate]of choices){const rules=next.rulesForRoomMode(mode);assert.equal(rules.scoreTarget,scoreTarget);assert.equal(rules.timeLimit,timeLimit);assert.equal(rules.pickupRate,pickupRate);assert.equal(rules.mapSize,'ultrawide');assert.deepEqual(Array.from(rules.weapons),['shield']);next.localRoom.rules=rules;}
 next.localRoom.rules.mapSize='compact';assert.equal(next.rulesForRoomMode('ctf').mapSize,'compact');assert.equal(next.rulesForRoomMode('ctf').teamMode,'teams');
});

test('roster names, bot strengths, teams, local P2, spectator state and owner IDs restore across runs',()=>{
 const {s,storage}=boot();s.localRoom.rules={...s.defaultModeRules('elimination'),teamMode:'teams'};s.localRoom.self=9;
 s.localRoom.players=[bot({id:2,name:'SMART',difficulty:'godlike',team:4}),{id:3,kind:'local',name:'BUDDY',owner:9,team:2},pilot({id:9,name:'ADAM',team:3,spectating:true})];
 s.persistLocalRoomRules();const next=boot(storage).s;assert.equal(next.restoreSavedLocalRoster(),true);
 assert.deepEqual(clone(next.localRoom.players.map(({kind,name,team,difficulty,spectating})=>({kind,name,team,...(difficulty?{difficulty}:{}),spectating}))),[
 {kind:'human',name:'ADAM',team:3,spectating:true},{kind:'bot',name:'SMART',team:4,difficulty:'godlike',spectating:false},{kind:'local',name:'BUDDY',team:2,spectating:false}]);
 assert.equal(next.localRoom.self,8);assert.equal(next.localRoom.nextViewer,9);assert.equal(new Set(next.localRoom.players.map(p=>p.id)).size,3);assert.equal(next.localRoom.players.every(p=>p.owner===8),true);assert.equal(next.localRoom.players.every(p=>p.spectating?p.id>=8:p.id<8),true);
});

test('FFA tank colors survive seat reassignment and repeated restarts',()=>{
 const {s,storage}=boot();s.localRoom.self=8;s.localRoom.players=[pilot({id:8,spectating:true,colorIndex:7}),bot({id:6,difficulty:'hard'}),{id:4,kind:'local',name:'P2',team:0,colorIndex:3}];s.persistLocalRoomRules();
 for(let n=0;n<3;n++){const next=boot(storage).s;next.restoreSavedLocalRoster();assert.deepEqual(Array.from(next.localRoom.players,p=>p.colorIndex),[7,6,3]);next.persistLocalRoomRules();}
});

test('unchanged room renders write once; individual configuration changes persist immediately',()=>{
 const {s,storage}=boot();s.localRoom.players=[pilot(),bot()];for(let n=0;n<100;n++)s.rememberRenderedRoomSetup({});assert.equal(s.writes,1);
 s.localRoom.players[1].difficulty='godlike';s.rememberRenderedRoomSetup({});assert.equal(s.writes,2);
 s.localRoom.players.push({id:2,kind:'local',name:'SECOND',team:0});s.rememberRenderedRoomSetup({});assert.equal(s.writes,3);
 s.localRoom.players.splice(1,1);s.rememberRenderedRoomSetup({});assert.equal(s.writes,4);
 const next=boot(storage).s;next.restoreSavedLocalRoster();assert.deepEqual(Array.from(next.localRoom.players,p=>p.kind),['human','local']);
});

test('accepted online host settings save only the host, their local P2 and bots',()=>{
 const {s,storage}=boot();s.localRoom.players=[pilot(),bot()];s.persistLocalRoomRules();s.mode='online';s.online.id=2;
 const r={host:2,rules:{...s.defaultModeRules('ctf'),scoreTarget:8},players:[pilot({id:2,name:'HOST',team:1}),pilot({id:0,name:'REMOTE',team:2}),{id:1,kind:'local',owner:0,name:'REMOTE P2',team:2},bot({id:3,team:2,difficulty:'godlike'})],spectators:[{id:9,kind:'local',owner:2,name:'MY P2',team:1,spectating:true}]};
 s.rememberRenderedRoomSetup(r);const next=boot(storage).s;assert.equal(next.localRoom.rules.scoreTarget,8);next.restoreSavedLocalRoster();assert.deepEqual(Array.from(next.localRoom.players,p=>p.name),['HOST','RUST','MY P2']);
 const before=storage.get('leqra.roomSetup.v2');for(const changes of [{host:0},{queue:{}},{matchmaking:true},{awayMatch:true}])s.rememberRenderedRoomSetup({...r,...changes,rules:{...r.rules,scoreTarget:9}});
 s.online.connected=false;s.rememberRenderedRoomSetup({...r,rules:{...r.rules,scoreTarget:10}});assert.equal(storage.get('leqra.roomSetup.v2'),before);
});

test('legacy rules migrate including mobile map preference and omitted future defaults',()=>{
 const legacy={version:1,rules:{mode:'koth',teamMode:'ffa',scoreTarget:88,timeLimit:200,mapSize:'giant'}};
 const storage=new Map([['leqra.roomRules.v1',JSON.stringify(legacy)]]),{s}=boot(storage,true);assert.equal(s.localRoom.rules.mode,'koth');assert.equal(s.localRoom.rules.scoreTarget,88);assert.equal(s.localRoom.rules.mapSize,'giant');assert.equal(s.localRoom.rules.respawnSeconds,3);
 s.localRoom.players=[pilot(),bot()];s.persistLocalRoomRules();assert.equal(JSON.parse(storage.get('leqra.roomSetup.v2')).version,2);assert.equal(boot(new Map(),true).s.localRoom.rules.mapSize,'compact');
});

test('invalid saved rule profiles and rosters recover independently without loading unsafe seats',()=>{
 const valid=boot().s.defaultModeRules('ctf');
 for(const invalid of [null,[],[bot()],[pilot(),pilot({id:1})],[pilot(),bot({difficulty:'toString'})],[pilot(),bot({spectating:true})],[pilot({spectating:'yes'})],[pilot(),{id:1,kind:'local',name:'P2',team:1},{id:2,kind:'local',name:'P3',team:2}],[pilot(),bot({colorIndex:8})]]){
  const storage=new Map([['leqra.roomSetup.v2',JSON.stringify({version:2,selectedMode:'ctf',modes:{ctf:valid,elimination:{...valid,mode:'elimination',scoreTarget:999}},roster:invalid})]]),s=boot(storage).s;
  assert.equal(s.localRoom.rules.mode,'ctf');assert.equal(s.restoreSavedLocalRoster(),false);assert.equal(s.rememberedRulesForMode('elimination'),null);
 }
 const corrupt=boot(new Map([['leqra.roomSetup.v2','{broken']])).s;assert.equal(corrupt.localRoom.rules.mode,'elimination');
 const prototype=boot(new Map([['leqra.roomSetup.v2',JSON.stringify({version:2,selectedMode:'__proto__',modes:{}})]])).s;assert.equal(prototype.localRoom.rules.mode,'elimination');
});

test('spectating pilots do not consume survival seats; saved active overflow is rejected',()=>{
 const s=boot().s,rules=s.defaultModeRules('survival');const roster=[pilot({spectating:true,team:1}),...Array.from({length:4},(_,id)=>bot({id,name:'BOT '+id,team:1})),{kind:'local',name:'P2',team:1,spectating:true}];
 assert.equal(s.validateSavedRoster(roster,rules).length,6);assert.equal(s.validateSavedRoster([...roster,bot({name:'EXTRA',team:1})],rules),null);
});

test('storage failure does not interrupt editing and in-session mode memory remains available',()=>{
 const {s}=boot();s.localRoom.players=[pilot(),bot()];s.storageFails=true;s.localRoom.rules={...s.defaultModeRules('koth'),scoreTarget:77};assert.equal(s.persistLocalRoomRules(),false);assert.equal(s.rememberedRulesForMode('koth').scoreTarget,77);s.storageFails=false;assert.equal(s.persistLocalRoomRules(),true);
});

test('DEFAULT RULES stages mode defaults, leaves the lobby setup intact and saves only on Apply',()=>{
 for(const [mode,score,time]of [['elimination',5,75],['ctf',3,180],['koth',30,180],['survival',15,75]]){
  const {s,$,toggles}=boot();s.localRoom.players=[pilot({team:1}),bot({team:2})];s.localRoom.rules={...s.defaultModeRules(mode),teamMode:'teams',mapSize:'ultrawide',scoreTarget:19,timeLimit:500,respawnSeconds:7,friendlyFire:true,pickupRate:'off',weapons:[],teamNames:['A','B','C','D']};
  const before=JSON.stringify(s.localRoom.rules),roster=JSON.stringify(s.localRoom.players);s.resetRuleDefaults();assert.equal(JSON.stringify(s.localRoom.rules),before);assert.equal(s.writes,0);assert.equal($('rule-scoreTarget').value,score);assert.equal($('rule-timeLimit').value,time);assert.equal($('rule-friendlyFire').checked,false);assert.equal($('rule-pickupRate').value,'superfast');assert.equal(toggles.every(c=>c.checked),true);assert.match($('rulesNotice').textContent,/APPLY RULES/);
  s.submitRules({preventDefault(){}});assert.equal(s.localRoom.rules.scoreTarget,score);assert.equal(s.localRoom.rules.timeLimit,time);assert.equal(s.localRoom.rules.respawnSeconds,3);assert.deepEqual(Array.from(s.localRoom.rules.teamNames),['Team 1','Team 2','Team 3','Team 4']);assert.equal(s.localRoom.rules.mapSize,'ultrawide');assert.equal(s.localRoom.rules.teamMode,'teams');assert.equal(JSON.stringify(s.localRoom.players),roster);assert.equal(s.writes,1);assert.equal(s.closed,true);
 }
});

test('DEFAULT RULES is host-only and online Apply waits for authoritative confirmation',()=>{
 const {s,$}=boot();s.localRoom.players=[pilot(),bot()];s.mode='online';s.online.roomData={rules:{...s.defaultModeRules('koth'),scoreTarget:72}};s.editable=false;s.fillRulesForm();assert.equal($('defaultRulesBtn').disabled,true);s.resetRuleDefaults();assert.equal($('rule-scoreTarget').value,72);
 s.editable=true;s.resetRuleDefaults();s.submitRules({preventDefault(){}});assert.equal(s.sent.type,'rules');assert.equal(s.sent.rules.scoreTarget,30);assert.equal(s.online.roomData.rules.scoreTarget,72);assert.equal(s.writes,0);assert.equal(s.rulesPending,true);assert.notEqual(s.closed,true);
});


test('a rejected oversized Survival mode switch preserves the saved rules and complete roster',()=>{
 const {s,storage}=boot();s.localRoom.rules={...s.localRoom.rules,scoreTarget:11,mapSize:'huge'};s.localRoom.players=[pilot(),...Array.from({length:4},(_,id)=>bot({id:id+1,name:'BOT '+id}))];s.persistLocalRoomRules();const saved=storage.get('leqra.roomSetup.v2'),before=JSON.stringify(s.localRoom);
 assert.equal(s.selectRoomMode('survival'),false);assert.match(s.rejected,/four squad tanks/);assert.equal(JSON.stringify(s.localRoom),before);assert.equal(storage.get('leqra.roomSetup.v2'),saved);assert.equal(s.writes,1);
});

test('denied storage reads use device defaults and an invalid selected profile does not discard other profiles',()=>{
 const denied=new Map();denied.get=()=>{throw Error('Storage access denied');};assert.equal(boot(denied,true).s.localRoom.rules.mapSize,'compact');
 const rules={...boot().s.defaultModeRules('koth'),scoreTarget:66},storage=new Map([['leqra.roomSetup.v2',JSON.stringify({version:2,selectedMode:'survival',modes:{survival:{scoreTarget:-1},koth:rules},roster:null})]]),s=boot(storage).s;
 assert.equal(s.localRoom.rules.mode,'elimination');assert.equal(s.rulesForRoomMode('koth').scoreTarget,66);
});
