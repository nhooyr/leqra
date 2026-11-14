'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),{readFileSync}=require('node:fs'),vm=require('node:vm');
const {assetPath}=require('./web_assets.cjs');
const source=readFileSync(process.env.LEQRA_ROSTER_SOURCE||assetPath('game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
const clone=x=>JSON.parse(JSON.stringify(x));
test('Dumb difficulty survives rules and saved-roster validation without changing defaults',()=>{
 const {s,storage}=boot();
 assert.equal(s.localRoom.rules.infinityBotDifficulty,'normal');
 const rules=s.validateRoomRules({...s.localRoom.rules,infinity:true,infinityBotDifficulty:'dumb'});
 assert.equal(rules.infinityBotDifficulty,'dumb');
 const input=[{id:0,kind:'human',name:'HOST',team:0},{id:1,kind:'bot',name:'BUDDY',team:0,difficulty:'dumb'}];
 const roster=s.validateSavedRoster(input,rules);
 assert.equal(roster[1].difficulty,'dumb');
 s.persistLocalRoomRules(rules,input);
 const restored=boot(storage).s;
 assert.equal(restored.localRoom.rules.infinityBotDifficulty,'dumb');
 assert.equal(restored.loadRememberedRoomSetup().roster[1].difficulty,'dumb');
});
function boot(storage=new Map(),touchUI=false){
 const elements=new Map(),toggles=['rapid','shield','laser'].map(weapon=>({dataset:{weaponToggle:weapon},checked:true}));
 const $=id=>{if(!elements.has(id))elements.set(id,{value:'',checked:false,disabled:false,dataset:{},style:{},classList:{toggle(){}},previousElementSibling:{style:{}},parentElement:{querySelector(){return true;}}});return elements.get(id);};
 const s={console,mode:'room',phase:'menu',touchUI,MAX_TANKS:8,POWER:Object.fromEntries(['rapid','scatter','shield','homing','grenade','speed','laser','cannon','ghost','starman'].map(kind=>[kind,{}])),DIFFICULTY:{dumb:{},easy:{},normal:{},hard:{},godlike:{}},ROOM_MODES:['elimination','ctf','koth','survival','infinity'].map(id=>({id})),localRoom:{self:0,nextMember:0,nextViewer:8,players:[]},online:{id:0,connected:true,roomData:null,snapshots:[]},pendingRoomMode:null,rulesPending:false,presetsPending:false,
 localStorage:{getItem:key=>storage.get(key)||null,setItem(key,value){if(s.storageFails)throw Error('Storage unavailable');storage.set(key,value);s.writes++;}},writes:0,
 $,document:{querySelectorAll:selector=>selector.endsWith(':checked')?toggles.filter(c=>c.checked):toggles},Theme:{colors:['a','b','c','d','e','f','g','h']},teamName:(n,r)=>r.teamNames[n-1],featureNotice(id,message){$(id).textContent=message;},updateRuleHelp(){},renderPowerLegend(){},isRoomEditable:()=>s.editable!==false,roomData:()=>({rules:s.localRoom.rules,players:s.localRoom.players.filter(p=>!p.spectating)}),roomModeEditable:()=>s.editable!==false,rejectRoomMode(message){s.rejected=message;},localPlayerID:()=>s.mode==='online'?s.online.id:s.localRoom.self,roomMembers:r=>[...r.players,...(r.spectators||[])],setLocalRules(r){s.localRoom.rules=s.validateRoomRules(r);s.persistLocalRoomRules(r);},setTimeout(){return 1;},clearTimeout(){},syncFeatureSummary(){},updateHUD(){},syncRoomModePicker(){},sendOnline(message){s.sent=message;return !s.sendFails;},closeFeature(){s.closed=true;}};
 Object.assign(s,{infinityOffline:false,infinityOnline:true,location:{protocol:'https:'},navigator:{onLine:true},renderOnlineRoom(){},resetPreviewIfLobby(){s.previewReset=true;},readyRoom(){s.persistLocalRoomRules();},callsignForms:()=>[],save(key,value){storage.set('leqra.'+key,String(value));}});
 Object.assign(s.document,{body:{classList:{remove(){}}},documentElement:{style:{removeProperty(){}}}});
 try{s.infinityOffline=storage.get('leqra.infinityOffline')==='1';s.infinityOnline=storage.get('leqra.infinityOnline')!=='0';}catch(_){}
 vm.createContext(s);if(source.includes('function orderedRoster('))vm.runInContext(declaration('orderedRoster'),s);vm.runInContext(source.match(/^const COLORS=.*$/m)[0]+'\n'+source.match(/^const colorIndex=.*$/m)[0],s);vm.runInContext("const LOCAL_RULES_KEY='leqra.roomRules.v1',ROOM_SETUP_KEY='leqra.roomSetup.v2';let rememberedRoomSetup=null,lastPersistedRoomSetup='';",s);
 for(const name of ['defaultRoomRules','defaultModeRules','defaultLocalRoomRules','validateTeamNames','validateRoomRules','cleanPilotName','survivalMode','roomCapacity','currentRules','activeTeamCount','nextRoomTeam','balanceLocalTeams','normalizeRoomTeams','validateSavedRoster','restoreRoomRules','loadRememberedRoomSetup','loadLocalRoomRules','rememberedRulesForMode','persistLocalRoomRules','rememberRenderedRoomSetup','restoreSavedLocalRoster','rulesForRoomMode','canPlayOnlineInfinity','infinityPlayMode','selectLocalInfinity','ensureDefaultLocalBots','selectPublicInfinity','selectRoomMode','selectRoomSetting','roomModeEditable','modeLabel','fillRulesForm','resetRuleDefaults','readRuleTeamSettings','submitRules','roomSetupRulesKey','roomSetupRosterKey','finishRoomSetupRequest','syncRoomSetupPending','sendRoomSetupRequest','startInfinity','createLocalRoom'])vm.runInContext(declaration(name),s);
 s.localRoom.rules=s.loadLocalRoomRules();return {s,$,storage,toggles};
}
const pilot=(options={})=>({id:0,kind:'human',name:'PILOT',team:0,...options});
const bot=(options={})=>({id:1,kind:'bot',name:'RUST',team:0,difficulty:'normal',...options});

test('new primary callsigns default to Player 1 while saved and restored choices retain their case',()=>{
 for(const saved of [undefined,'','   ','PILOT','Pilot','YOU','Snow Fox']){
  const storage=new Map(saved===undefined?[]:[['leqra.name',saved]]),{s,$}=boot(storage);s.createLocalRoom();
  const want=saved?.trim()||'Player 1';assert.equal(s.localRoom.players[0].name,want);assert.equal($('pilotName').value,want);
  const restored=boot(storage).s;restored.createLocalRoom();assert.equal(restored.localRoom.players[0].name,want);
 }
});

test('a new public Infinity setup starts with only P1 and switching it off adds three Normal bots once',()=>{
 const {s,storage}=boot();s.createLocalRoom();
 assert.deepEqual(Array.from(s.localRoom.players,p=>p.kind),['human']);
 assert.equal(s.infinityPlayMode(),'online');
 s.selectPublicInfinity(false);
 assert.deepEqual(Array.from(s.localRoom.players,p=>[p.id,p.kind,p.name,p.difficulty]),[[0,'human','Player 1',undefined],[1,'bot','Rust','normal'],[2,'bot','Vapor','normal'],[3,'bot','Ember','normal']]);
 assert.equal(new Set(s.localRoom.players.map(p=>p.member)).size,4);
 assert.equal(s.localRoom.players.every(p=>p.owner===0&&p.team===0),true);
 assert.equal(s.previewReset,true);
 assert.equal(JSON.parse(storage.get('leqra.roomSetup.v2')).roster.length,4);
 s.selectPublicInfinity(false);s.selectPublicInfinity(true);s.selectPublicInfinity(false);
 assert.equal(s.localRoom.players.length,4);
});

test('stored fixed selection fills an empty lineup while restored bots or P2 keep their exact roster',()=>{
 const fixed=new Map([['leqra.infinityOnline','0']]),first=boot(fixed).s;first.createLocalRoom();
 assert.deepEqual(Array.from(first.localRoom.players,p=>p.kind),['human','bot','bot','bot']);
 for(const companion of [bot({name:'CUSTOM',difficulty:'godlike'}),{id:2,kind:'local',name:'P2',team:0}, {id:8,kind:'local',name:'P2',team:0,spectating:true}]){
  const storage=new Map([['leqra.infinityOnline','0']]),saved=boot(storage).s;saved.localRoom.players=[pilot({name:'KEPT'}),companion];saved.persistLocalRoomRules();
  const restored=boot(storage).s;restored.createLocalRoom();
  assert.deepEqual(Array.from(restored.localRoom.players,p=>p.name),['KEPT',companion.name]);
  assert.equal(restored.localRoom.players[1].difficulty,companion.difficulty);
 }
 const offline=boot(new Map([['leqra.infinityOffline','1'],['leqra.infinityOnline','0']])).s;offline.createLocalRoom();
 assert.equal(offline.localRoom.rules.infinity,true);assert.equal(offline.localRoom.players.length,1);
});

test('selecting any fixed mode from public or room Infinity makes a solo roster playable',()=>{
 for(const from of ['public','room'])for(const mode of ['elimination','ctf','koth','survival']){
  const {s}=boot();s.localRoom.players=[pilot({member:1})];s.localRoom.nextMember=1;
  if(from==='room'){s.localRoom.rules={...s.localRoom.rules,infinity:true};s.infinityOffline=true;s.infinityOnline=false;}
  s.mapSetupChanged=()=>false;vm.runInContext(declaration('setLocalRules'),s);
  vm.runInContext(source.match(/^const teamKey=.*$/m)[0]+'\n'+declaration('roomStartError'),s);
  assert.equal(s.selectRoomMode(mode),true,from+' '+mode);
  assert.equal(s.localRoom.players.length,4);assert.equal(s.infinityPlayMode(),'');
  assert.deepEqual(Array.from(s.localRoom.players.slice(1),p=>p.difficulty),['normal','normal','normal']);
  assert.equal(s.roomStartError(),'');
  assert.equal(s.selectRoomMode(mode),true);assert.equal(s.localRoom.players.length,4);
 }
});

test('automatic default bots never change Infinity, active rounds, existing companions or online rosters',()=>{
 for(const scenario of ['public','room','open','countdown','playing','paused','roundOver','online','human','bot','local']){
  const {s,$}=boot();s.localRoom.players=[pilot()];s.infinityOnline=false;
  if(scenario==='public')s.infinityOnline=true;
  else if(scenario==='room')s.localRoom.rules={...s.localRoom.rules,infinity:true};
  else if(scenario==='open')$('infiniteArena').open=true;
  else if(['countdown','playing','paused','roundOver'].includes(scenario))s.phase=scenario;
  else if(scenario==='online')s.mode='online';
  else s.localRoom.players.push(scenario==='bot'?bot({difficulty:'hard'}):scenario==='human'?pilot({id:2,name:'REMOTE'}):{kind:'local',name:'P2'});
  const before=JSON.stringify(s.localRoom.players);assert.equal(s.ensureDefaultLocalBots(),false,scenario);assert.equal(JSON.stringify(s.localRoom.players),before);
 }
});

test('a fixed solo preset adds fallback only when it actually exits room Infinity',()=>{
 for(const exitingInfinity of [false,true]){
  const {s}=boot();s.localRoom.players=[pilot()];s.localRoom.rules={...s.localRoom.rules,infinity:exitingInfinity};s.infinityOffline=exitingInfinity;s.infinityOnline=false;
  Object.assign(s,{mapSetupChanged:()=>false,rememberCallsign(){},rememberLocalCallsign(){},clearInput(){},setScreen(){}});
  vm.runInContext(declaration('validatePreset')+'\n'+declaration('applyLocalPreset'),s);
  s.applyLocalPreset({rules:s.defaultModeRules(),roster:[{kind:'human',name:'P1',team:0}]});
  assert.equal(s.localRoom.players.length,exitingInfinity?4:1);assert.equal(!!s.localRoom.rules.infinity,false);
 }
});

test('online Infinity exit presets acknowledge the exact normalized fallback roster',()=>{
 for(const mode of ['elimination','ctf','koth','survival']){
  const {s}=boot();s.mode='online';s.phase='onlineLobby';
  Object.assign(s.online,{id:3,member:50,socket:{},token:'test',roomData:{host:3,phase:'lobby',players:[pilot({id:3,member:50})],spectators:[],rules:{...s.defaultRoomRules(),infinity:true}}});
  const preset={rules:s.defaultModeRules(mode),roster:[{kind:'human',name:'NEW HOST',team:mode==='ctf'||mode==='survival'?1:0}]};
  s.selectedPreset=()=>preset;vm.runInContext(declaration('validatePreset')+'\n'+declaration('canLoadPreset')+'\n'+declaration('applySelectedPreset'),s);
  s.applySelectedPreset();const sent=s.sent;
  assert.equal(sent.type,'preset');assert.equal(sent.roster.length,4);assert.equal(preset.roster.length,1,'saved preset stays unchanged');
  assert.deepEqual(Array.from(sent.roster.slice(1),p=>[p.name,p.kind,p.difficulty]),[['Rust','bot','normal'],['Vapor','bot','normal'],['Ember','bot','normal']]);
  assert.deepEqual(Array.from(sent.roster,p=>p.team),mode==='survival'?[1,1,1,1]:mode==='ctf'?[1,2,1,2]:[0,0,0,0]);
  assert.equal(s.presetsPending,true);assert.notEqual(s.closed,true);
  const packet={...s.online.roomData,rules:sent.rules,players:sent.roster.map((p,i)=>({...p,id:i===0?3:i-1,member:50+i,owner:3}))};
  s.online.roomData={...packet,players:packet.players.slice(0,1)};s.syncRoomSetupPending();assert.equal(s.presetsPending,true,'partial roster does not acknowledge');
  s.online.roomData={...packet,players:packet.players.map((p,i)=>i===1?{...p,difficulty:'hard'}:p)};s.syncRoomSetupPending();assert.equal(s.presetsPending,true,'wrong bot does not acknowledge');
  s.online.roomData=packet;s.syncRoomSetupPending();assert.equal(s.presetsPending,false);assert.equal(s.closed,true);
 }
 const {s}=boot();s.mode='online';s.phase='onlineLobby';s.online.roomData={host:0,phase:'lobby',players:[pilot()],spectators:[],rules:s.defaultRoomRules()};
 s.sendRoomSetupRequest('preset',{rules:s.defaultRoomRules(),roster:[{kind:'human',name:'SOLO',team:0}]});assert.equal(s.sent.roster.length,1,'ordinary fixed solo preset stays solo');
});

test('Infinity room target, teams and random bots persist separately from fixed-maze settings',()=>{
 const {s,$,storage}=boot();s.localRoom.players=[pilot(),bot()];
 s.localRoom.rules={...s.localRoom.rules,scoreTarget:9,timeLimit:300};s.persistLocalRoomRules();
 assert.equal(s.selectRoomMode('infinity'),true);
 assert.equal(s.selectRoomSetting('teamMode','teams'),true);
 s.fillRulesForm();assert.equal($('rulesDialog').dataset.mode,'infinity');
 assert.equal($('rule-infinityTarget').value,0);
 assert.equal($('rule-infinityRandomBots').checked,false);
 assert.equal($('rule-infinityBotDifficulty').value,'normal');
 assert.equal($('rule-infinityRandomDifficulty').value,'fixed');
 $('rule-infinityTarget').value='35';$('rule-teamName1').value='North';$('rule-friendlyFire').checked=true;
 $('rule-infinityRandomBots').checked=true;$('rule-infinityBotDifficulty').value='hard';$('rule-infinityRandomDifficulty').value='upTo';
 s.submitRules({preventDefault(){}});
 const {s:restored,$:restoredElement}=boot(storage);
 assert.equal(restored.localRoom.rules.infinity,true);
 assert.equal(restored.localRoom.rules.infinityTarget,35);
 assert.equal(restored.localRoom.rules.teamMode,'teams');
 assert.equal(restored.localRoom.rules.teamNames[0],'North');
 assert.equal(restored.localRoom.rules.friendlyFire,true);
 restored.fillRulesForm();
 assert.equal(restoredElement('rule-infinityRandomBots').checked,true);
 assert.equal(restoredElement('rule-infinityBotDifficulty').value,'hard');
 assert.equal(restoredElement('rule-infinityRandomDifficulty').value,'upTo');
 assert.equal(s.selectRoomMode('elimination'),true);
 assert.equal(s.localRoom.rules.infinity,false);
 assert.equal(s.localRoom.rules.scoreTarget,9);
 assert.equal(s.localRoom.rules.timeLimit,300);
 assert.equal(s.localRoom.rules.teamMode,'ffa');
 assert.equal(s.localRoom.rules.infinityRandomBots,false);
 assert.equal(s.selectRoomMode('infinity'),true);
 assert.equal(s.localRoom.rules.infinityTarget,35);
 assert.equal(s.localRoom.rules.infinityRandomBots,true);
 assert.equal(s.localRoom.rules.infinityBotDifficulty,'hard');
 assert.equal(s.localRoom.rules.infinityRandomDifficulty,true);
 s.resetRuleDefaults();
 assert.equal(s.localRoom.rules.infinityRandomBots,true,'Default Rules stages changes until Apply');
 s.submitRules({preventDefault(){}});
 assert.equal(s.localRoom.rules.infinityRandomBots,false);
 assert.equal(s.localRoom.rules.infinityBotDifficulty,'normal');
 assert.equal(s.localRoom.rules.infinityRandomDifficulty,false);
});

test('old offline Infinity selection remains endless and room rule requests include the target',()=>{
 const {s,$}=boot(new Map([['leqra.infinityOffline','1']]));
 assert.equal(s.localRoom.rules.infinity,true);
 assert.equal(s.localRoom.rules.infinityTarget,0);
 for(const target of [-1,1000,1.5,'1',null])assert.throws(()=>s.validateRoomRules({...s.localRoom.rules,infinityTarget:target}),/Infinity score target/);
 s.mode='online';s.online.roomData={rules:s.localRoom.rules};
 s.fillRulesForm();$('rule-infinityTarget').value='70';
 s.submitRules({preventDefault(){}});
 assert.equal(s.sent.rules.infinityTarget,70);
 assert.equal(s.online.roomData.rules.infinityTarget,0);
 assert.notEqual(s.roomSetupRulesKey(s.sent.rules),s.roomSetupRulesKey(s.online.roomData.rules));
});

test('random Infinity bot settings validate and each affects authoritative room confirmation',()=>{
 const {s,$}=boot(new Map([['leqra.infinityOffline','1']]));
 const {infinityRandomBots,infinityBotDifficulty,infinityRandomDifficulty,...legacy}=s.localRoom.rules;
 const normalized=s.validateRoomRules(legacy);
 assert.equal(normalized.infinityRandomBots,false);
 assert.equal(normalized.infinityBotDifficulty,'normal');
 assert.equal(normalized.infinityRandomDifficulty,false);
 assert.equal(s.roomSetupRulesKey(legacy),s.roomSetupRulesKey({...legacy,infinityBotDifficulty:''}));
 for(const [field,value,error] of [
  ['infinityRandomBots','true',/must be on or off/],
  ['infinityBotDifficulty','toString',/valid difficulty/],
  ['infinityBotDifficulty',null,/valid difficulty/],
  ['infinityRandomDifficulty',1,/must be Fixed or Up to/],
 ])assert.throws(()=>s.validateRoomRules({...legacy,[field]:value}),error);
 s.mode='online';s.online.roomData={rules:normalized};s.fillRulesForm();
 $('rule-infinityRandomBots').checked=true;$('rule-infinityBotDifficulty').value='godlike';$('rule-infinityRandomDifficulty').value='upTo';
 s.submitRules({preventDefault(){}});
 assert.equal(s.sent.rules.infinityRandomBots,true);
 assert.equal(s.sent.rules.infinityBotDifficulty,'godlike');
 assert.equal(s.sent.rules.infinityRandomDifficulty,true);
 for(const field of ['infinityRandomBots','infinityBotDifficulty','infinityRandomDifficulty']){
  assert.notEqual(s.roomSetupRulesKey({...s.sent.rules,[field]:normalized[field]}),s.online.setupPending.rulesKey);
 }
});

test('room Infinity spawn rate survives legacy defaults, form roundtrips and preset serialization',()=>{
 const {s,$}=boot(new Map([['leqra.infinityOffline','1']]));
 const {infinityBotSpawnRate,...legacy}=s.localRoom.rules;
 assert.equal(s.validateRoomRules(legacy).infinityBotSpawnRate,2);assert.equal(s.validateRoomRules({...legacy,infinityBotSpawnRate:0}).infinityBotSpawnRate,2);
 for(const rate of [.5,1,2,4]){
  const rules=s.validateRoomRules({...legacy,infinityBotSpawnRate:rate});s.fillRulesForm(rules);
  assert.equal(Number($('rule-infinityBotSpawnRate').value),rate);s.submitRules({preventDefault(){}});
  assert.equal(s.localRoom.rules.infinityBotSpawnRate,rate);
  assert.equal(s.validateRoomRules(JSON.parse(JSON.stringify(s.localRoom.rules))).infinityBotSpawnRate,rate);
  assert.notEqual(s.roomSetupRulesKey({...rules,infinityBotSpawnRate:rate===4?2:4}),s.roomSetupRulesKey(rules));
 }
 for(const invalid of [-1,.25,3,16,Infinity,'2',null])assert.throws(()=>s.validateRoomRules({...legacy,infinityBotSpawnRate:invalid}),/spawn rate/);
});

test('Infinity start passes both local pilots and reserves room rules for room runs',()=>{
 const {s}=boot(),local={id:7,kind:'local',name:'Wing',colorIndex:0};
 s.localRoom.self=4;s.localRoom.rules={...s.localRoom.rules,infinity:true,infinityTarget:12};s.localRoom.players=[local,pilot({id:4,name:'Lead',colorIndex:6})];
 Object.assign(s,{window:{leqraInfinity:{start:(kind,options)=>s.launch={kind,options}}},roomMember:id=>s.localRoom.players.find(p=>p.id===id),secondLocal:()=>local,
  bindings:[],closeVictory(){},clearInput(){},cancelPendingAudio(){}});
 s.startInfinity('offline');
 assert.equal(s.launch.options.roomRules.infinityTarget,12);
 assert.deepEqual(Array.from(s.launch.options.roster,p=>p.id),[7,4]);
 assert.equal(s.launch.options.primaryId,4);
 assert.equal(s.launch.options.localId,7);
 assert.equal(s.launch.options.localName,'Wing');
 assert.equal(s.launch.options.colorIndex,6);
 assert.equal(s.launch.options.localColorIndex,0);
 s.startInfinity('online');
 assert.equal(s.launch.options.roomRules,null);
 assert.equal(s.launch.options.roster.length,0);
 assert.equal(s.launch.options.localName,'Wing');
 assert.equal(s.launch.options.colorIndex,6);
 assert.equal(s.launch.options.localColorIndex,0);
 s.startInfinity('online',{code:'ROOM',token:'test'});
 assert.equal(s.launch.options.roomRules.infinityTarget,12);
 assert.equal(s.launch.options.token,'test');
 s.localRoom.rules={...s.localRoom.rules,teamMode:'teams',teamColors:[3,5,2,4]};
 s.localRoom.players.find(p=>p.id===4).team=1;local.team=2;
 s.startInfinity('online');
 assert.deepEqual([s.launch.options.colorIndex,s.launch.options.localColorIndex],[3,5],
  'public Infinity inherits the paints displayed by the current room, including team colors');
});

test('each mode remembers its rules through mode changes and a fresh page load, keeping the selected map',()=>{
 const {s,storage}=boot();s.localRoom.players=[pilot(),bot()];
 const choices=[['elimination',9,90,'slow'],['ctf',7,210,'fast'],['koth',61,240,'off'],['survival',18,300,'normal']];
 for(const [mode,scoreTarget,timeLimit,pickupRate]of choices){s.localRoom.rules={...s.rulesForRoomMode(mode),scoreTarget,timeLimit,pickupRate,mapSize:'ultrawide',portraitMaze:true,weapons:['shield']};assert.equal(s.persistLocalRoomRules(),true);}
 const next=boot(storage).s;assert.equal(next.localRoom.rules.mode,'survival');assert.equal(next.localRoom.rules.scoreTarget,18);next.restoreSavedLocalRoster();
 for(const [mode,scoreTarget,timeLimit,pickupRate]of choices){const rules=next.rulesForRoomMode(mode);assert.equal(rules.scoreTarget,scoreTarget);assert.equal(rules.timeLimit,timeLimit);assert.equal(rules.pickupRate,pickupRate);assert.equal(rules.mapSize,'ultrawide');assert.equal(rules.portraitMaze,true);assert.deepEqual(Array.from(rules.weapons),['shield']);next.localRoom.rules=rules;}
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
 s.online.token='inherited';
 const original=storage.get('leqra.roomSetup.v2');
 s.rememberRenderedRoomSetup({...r,host:0});s.rememberRenderedRoomSetup(r);
 assert.equal(storage.get('leqra.roomSetup.v2'),original,'host handoff preserves the personal setup');
 s.rememberRenderedRoomSetup(r,true);const next=boot(storage).s;assert.equal(next.localRoom.rules.scoreTarget,8);next.restoreSavedLocalRoster();assert.deepEqual(Array.from(next.localRoom.players,p=>p.name),['HOST','RUST','MY P2']);
 s.online.localSetupToken=s.online.token='published';
 const before=storage.get('leqra.roomSetup.v2');for(const changes of [{host:0},{queue:{}},{matchmaking:true},{awayMatch:true}])s.rememberRenderedRoomSetup({...r,...changes,rules:{...r.rules,scoreTarget:9}});
 s.online.connected=false;s.rememberRenderedRoomSetup({...r,rules:{...r.rules,scoreTarget:10}});assert.equal(storage.get('leqra.roomSetup.v2'),before);
});

test('legacy rules migrate including mobile map preference and omitted future defaults',()=>{
 const legacy={version:1,rules:{mode:'koth',teamMode:'ffa',scoreTarget:88,timeLimit:200,mapSize:'giant'}};
 const storage=new Map([['leqra.roomRules.v1',JSON.stringify(legacy)]]),{s}=boot(storage,true);assert.equal(s.localRoom.rules.mode,'koth');assert.equal(s.localRoom.rules.scoreTarget,88);assert.equal(s.localRoom.rules.mapSize,'giant');assert.equal(s.localRoom.rules.portraitMaze,false);assert.equal(s.localRoom.rules.respawnSeconds,3);
 s.localRoom.players=[pilot(),bot()];s.persistLocalRoomRules();assert.equal(JSON.parse(storage.get('leqra.roomSetup.v2')).version,2);assert.equal(boot(new Map(),true).s.localRoom.rules.mapSize,'compact');
});

test('old all-pickup rooms gain Starman while custom and current disabled choices stay disabled',()=>{
 const original=boot().s.defaultRoomRules(),weapons=Array.from(original.weapons).filter(kind=>kind!=='starman');
 const setup={version:2,selectedMode:'elimination',modes:{elimination:{...original,weapons},ctf:{...original,mode:'ctf',teamMode:'teams',weapons:['ghost']}}};
 const storage=new Map([['leqra.roomSetup.v2',JSON.stringify(setup)]]),{s}=boot(storage);
 assert.deepEqual(Array.from(s.localRoom.rules.weapons),[...weapons,'starman']);
 assert.deepEqual(Array.from(s.rememberedRulesForMode('ctf').weapons),['ghost']);
 s.localRoom.players=[pilot(),bot()];s.localRoom.rules.weapons=weapons;
 assert.equal(s.persistLocalRoomRules(),true);
 assert.deepEqual(Array.from(boot(storage).s.localRoom.rules.weapons),weapons);
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
  const {s,$,toggles}=boot();s.localRoom.players=[pilot({team:1}),bot({team:2})];s.localRoom.rules={...s.defaultModeRules(mode),teamMode:'teams',mapSize:'ultrawide',portraitMaze:true,scoreTarget:19,timeLimit:500,respawnSeconds:7,friendlyFire:true,pickupRate:'off',weapons:[],teamNames:['A','B','C','D']};
  const before=JSON.stringify(s.localRoom.rules),roster=JSON.stringify(s.localRoom.players);s.resetRuleDefaults();assert.equal(JSON.stringify(s.localRoom.rules),before);assert.equal(s.writes,0);assert.equal($('rule-scoreTarget').value,score);assert.equal($('rule-timeLimit').value,time);assert.equal($('rule-friendlyFire').checked,false);assert.equal($('rule-pickupRate').value,'superfast');assert.equal(toggles.every(c=>c.checked),true);assert.match($('rulesNotice').textContent,/APPLY RULES/);
  s.submitRules({preventDefault(){}});assert.equal(s.localRoom.rules.scoreTarget,score);assert.equal(s.localRoom.rules.timeLimit,time);assert.equal(s.localRoom.rules.respawnSeconds,3);assert.deepEqual(Array.from(s.localRoom.rules.teamNames),['Team 1','Team 2','Team 3','Team 4']);assert.equal(s.localRoom.rules.mapSize,'ultrawide');assert.equal(s.localRoom.rules.portraitMaze,true);assert.equal(s.localRoom.rules.teamMode,'teams');assert.equal(JSON.stringify(s.localRoom.players),roster);assert.equal(s.writes,1);assert.equal(s.closed,true);
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


test('saved roster and unshared/preset exports retain insertion order despite reused seat IDs',()=>{
 const {s,storage}=boot();
 const host=pilot({id:4,member:10,name:'HOST'}),older=bot({id:5,member:20,name:'OLDER'}),newer=bot({id:0,member:30,name:'NEWER',difficulty:'easy'});
 s.localRoom.self=4;s.localRoom.players=[newer,host,older];assert.equal(s.persistLocalRoomRules(),true);
 assert.deepEqual(JSON.parse(storage.get('leqra.roomSetup.v2')).roster.map(p=>p.name),['HOST','OLDER','NEWER']);
 const restored=boot(storage).s;restored.restoreSavedLocalRoster();assert.deepEqual(Array.from(restored.localRoom.players,p=>p.name),['HOST','OLDER','NEWER']);
 s.phase='menu';s.location={protocol:'https:'};s.MAX_ROOM_RUNES=128;s.$('localRoomName').value='ROOM';s.connectOnline=request=>s.published=request;
 for(const name of ['cleanRoomCode','validRoomCode','shareLocalRoom'])vm.runInContext(declaration(name),s);
 s.shareLocalRoom();assert.deepEqual(Array.from(s.published.roster,p=>p.name),['HOST','OLDER','NEWER']);
 s.mode='online';s.online.id=4;s.online.code='ROOM';
 const room={host:4,code:'ROOM',phase:'lobby',rules:s.localRoom.rules,players:[newer,host,older],spectators:[]};
 s.roomData=()=>room;s.roomMember=id=>room.players.find(p=>p.id===id);s.walls=[];s.cols=0;s.rows=0;
 for(const name of ['snapshotPreset','localSnapshotFromOnline'])vm.runInContext(declaration(name),s);
 assert.deepEqual(Array.from(s.snapshotPreset().roster,p=>p.name),['HOST','OLDER','NEWER']);
 const local=s.localSnapshotFromOnline();assert.deepEqual(Array.from(local.players,p=>p.name),['HOST','OLDER','NEWER']);assert.equal(local.nextMember,30);
 s.rememberRenderedRoomSetup(room);assert.deepEqual(JSON.parse(storage.get('leqra.roomSetup.v2')).roster.map(p=>p.name),['HOST','OLDER','NEWER']);
});

test('unsharing preserves both automatic spectator paints without overriding selected or team colors',()=>{
 const {s}=boot(),primary=pilot({id:8,member:1,name:'LEAD',color:'#c5a2ff',colorIndex:-1,spectating:true}),local={id:9,member:2,name:'WING',kind:'local',owner:8,team:0,color:'#ff83bd',spectating:true};
 const rules=s.validateRoomRules({...s.localRoom.rules,teamMode:'ffa'}),room={host:8,code:'ROOM',rules,players:[],spectators:[primary,local]};
 Object.assign(s,{mode:'online',phase:'onlineLobby',walls:[],cols:0,rows:0,roomData:()=>room});s.online.id=8;s.online.roomData=room;
 vm.runInContext(declaration('localSnapshotFromOnline'),s);
 const snapshot=s.localSnapshotFromOnline();
 assert.deepEqual(Array.from(snapshot.players,p=>[p.id,p.name,p.spectatorColor]),[[8,'LEAD','#c5a2ff'],[9,'WING','#ff83bd']]);
 Object.assign(s.localRoom,snapshot);s.localRoom.rules=snapshot.rules;s.mode='room';
 vm.runInContext(source.match(/^const teamColor=.*$/m)[0]+'\n'+source.match(/^const roomData=.*$/m)[0]+'\nthis.roomData=roomData;',s);
 assert.deepEqual(Array.from(s.roomData().spectators,p=>p.color),['#c5a2ff','#ff83bd'],'offline identities keep the authoritative colors even though viewer IDs map to other defaults');
 s.roomData=()=>room;s.mode='online';local.colorIndex=4;
 assert.equal(s.localSnapshotFromOnline().players[1].spectatorColor,undefined,'explicit selection remains the color authority');
 delete local.colorIndex;primary.team=1;room.rules={...rules,teamMode:'teams'};
 assert.equal(s.localSnapshotFromOnline().players[0].spectatorColor,undefined);assert.equal(s.localSnapshotFromOnline().players[1].spectatorColor,undefined,'team colors remain live instead of preserving old FFA paint');
});

test('saved automatic spectator paint survives reload and ignores invalid, explicit and team caches',()=>{
 const {s,storage}=boot();s.localRoom.rules={...s.localRoom.rules,teamMode:'ffa'};s.localRoom.self=9;
 s.localRoom.players=[pilot({id:9,member:1,name:'LEAD',spectating:true,spectatorColor:'#c5a2ff'}),{id:8,member:2,name:'WING',kind:'local',owner:9,team:0,spectating:true,colorIndex:-1,spectatorColor:'#ffc46b'}];
 assert.equal(s.persistLocalRoomRules(),true);
 const saved=JSON.parse(storage.get('leqra.roomSetup.v2')).roster;
 assert.deepEqual(saved.map(p=>[p.colorIndex,p.spectatorColor]),[[-1,'#c5a2ff'],[-1,'#ffc46b']]);
 const restored=boot(storage).s;assert.equal(restored.restoreSavedLocalRoster(),true);
 assert.deepEqual(Array.from(restored.localRoom.players,p=>p.spectatorColor),['#c5a2ff','#ffc46b']);
 vm.runInContext(source.match(/^const teamColor=.*$/m)[0]+'\n'+source.match(/^const roomData=.*$/m)[0]+'\nthis.roomData=roomData;',restored);
 assert.deepEqual(Array.from(restored.roomData().spectators,p=>p.color),['#c5a2ff','#ffc46b'],'viewer ID reassignment during reload does not change either paint');
 const rules=s.localRoom.rules;
 for(const patch of [{spectatorColor:'#not-a-color'},{spectatorColor:'var(--accent)'},{spectating:false},{colorIndex:4},{team:1}]){
  const roster=s.validateSavedRoster([{...s.localRoom.players[0],...patch}],rules);assert.equal(roster[0].spectatorColor,undefined,JSON.stringify(patch));
 }
 assert.equal(s.validateSavedRoster(saved,{...rules,teamMode:'teams'})[0].spectatorColor,undefined,'team mode ignores a stored FFA cache');
});

test('online public Infinity selection waits for shared metadata rather than a host-local preference',()=>{
 const {s}=boot();s.mode='online';s.online.roomData={infinityPublic:false};s.infinityOnline=true;
 assert.equal(s.infinityPlayMode(),'');
 s.selectPublicInfinity(true);
 assert.deepEqual(clone(s.sent),{type:'select_public_infinity',enabled:true});
 assert.equal(s.online.publicInfinityPending.enabled,true);
 assert.equal(s.infinityPlayMode(),'','unconfirmed selection does not launch public Infinity');
 s.online.roomData.infinityPublic=true;delete s.online.publicInfinityPending;s.infinityOnline=false;
 assert.equal(s.infinityPlayMode(),'online','all room clients use accepted shared selection');
 s.sent=null;s.editable=false;s.selectPublicInfinity(false);assert.equal(s.sent,null,'guest/read-only UI cannot change selection');
});

test('public Infinity selection expires safely and an old timeout cannot cancel a newer request',()=>{
 const {s}=boot();s.mode='online';s.online.roomData={infinityPublic:false};
 const timers=[],cancelled=[];s.setTimeout=(callback,delay)=>{timers.push({callback,delay});return timers.length;};s.clearTimeout=id=>cancelled.push(id);
 s.selectPublicInfinity(true);const first=s.online.publicInfinityPending;
 assert.equal(timers[0].delay,8000);timers[0].callback();
 assert.equal(s.online.publicInfinityPending,undefined);assert.ok(cancelled.includes(first.timer));
 s.selectPublicInfinity(true);const second=s.online.publicInfinityPending;
 assert.notEqual(first,second);timers[0].callback();assert.equal(s.online.publicInfinityPending,second);
 second.cancel();assert.equal(s.online.publicInfinityPending,undefined);assert.ok(cancelled.includes(second.timer));
 timers[1].callback();assert.equal(s.online.publicInfinityPending,undefined);
});


test('entering public Infinity clears saved bots while retaining local pilots and spectators',()=>{
 for(const spectating of [false,true]){
  const {s,storage}=boot();s.createLocalRoom();s.selectPublicInfinity(false);
  s.localRoom.players.push({id:spectating?8:6,member:20,kind:'local',name:'LOCAL TWO',owner:0,team:0,spectating});
  Object.assign(s,{closeVictory(){},clearInput(){},cancelPendingAudio(){},roomMember:id=>s.localRoom.players.find(p=>p.id===id),secondLocal:()=>s.localRoom.players.find(p=>p.kind==='local'&&!p.spectating),colorIndex:()=>0,window:{leqraInfinity:{start(kind,options){s.started={kind,options};}}}});
  s.selectPublicInfinity(true);
  assert.equal(s.localRoom.players.filter(p=>p.kind==='bot').length,3,'selection alone preserves the existing setup');
  s.startInfinity('online');
  assert.equal(s.localRoom.players.filter(p=>p.kind==='bot').length,3,'failed admission preserves the setup');
  s.started.options.onJoined();
  assert.deepEqual(Array.from(s.localRoom.players,p=>p.name),['Player 1','LOCAL TWO']);
  assert.equal(s.started.options.localName,spectating?undefined:'LOCAL TWO');
  assert.equal(JSON.parse(storage.get('leqra.roomSetup.v2')).roster.some(p=>p.kind==='bot'),false);
  const restored=boot(storage).s;restored.createLocalRoom();
  assert.equal(restored.localRoom.players.some(p=>p.kind==='bot'),false);
  assert.equal(restored.localRoom.players[1].spectating,spectating);
 }
});



test('entering offline or private Infinity retains the configured room bots',()=>{
 for(const kind of ['offline','online']){
  const {s}=boot();s.createLocalRoom();s.selectPublicInfinity(false);
  Object.assign(s,{closeVictory(){},clearInput(){},cancelPendingAudio(){},roomMember:id=>s.localRoom.players.find(p=>p.id===id),secondLocal:()=>null,colorIndex:()=>0,window:{leqraInfinity:{start(){}}}});
  s.startInfinity(kind,kind==='online'?{code:'PRIVATE'}:{});
  assert.equal(s.localRoom.players.filter(p=>p.kind==='bot').length,3);
 }
});
