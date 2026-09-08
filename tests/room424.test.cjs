'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
// Execute the shipped functions with small UI/network fixtures; no copied
// assignment algorithm or browser dependency is used by these regressions.
function declaration(name){
 const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);
 const lineEnd=source.indexOf('\n',start),first=source.slice(start,lineEnd);
 return first.endsWith('}')?first:source.slice(start,source.indexOf('\n}',lineEnd)+2);
}
class Element {
 constructor(tag='div'){this.tagName=tag.toUpperCase();this.children=[];this.dataset={};this.attributes={};this.style={setProperty(){}};this.classList={toggle(){},remove(){},add(){}};this.hidden=false;this.disabled=false;this.value='';this.textContent='';this.htmlWrites=0;}
 set innerHTML(value){this.html=value;this.htmlWrites++;}
 get innerHTML(){return this.html;}
 append(...children){for(const c of children){c.parentElement=this;this.children.push(c);}}
 setAttribute(k,v){this.attributes[k]=v;}
 getAttribute(k){return this.attributes[k];}
 addEventListener(){}
}
function boot(extra={}){
 const elements=new Map();const $=id=>{if(!elements.has(id)){const el=new Element();el.parentElement=new Element();elements.set(id,el);}return elements.get(id);};
 const rules={mode:'elimination',teamMode:'teams',teamNames:['A','B','C','D'],teamColors:[0,1,2,3],mapSize:'large',weapons:[],scoreTarget:5,timeLimit:75};
 const sandbox={console,mode:'room',phase:'menu',MAX_TANKS:8,localRoom:{rules,players:[],self:0,nextMember:10,nextViewer:8},online:{connected:true},rolePending:false,$,document:{createElement:tag=>new Element(tag)},DIFFICULTY:{easy:{},normal:{},hard:{}},toast(message){sandbox.notice=message;},sendOnline(message){sandbox.sent=message;return true;},paintColor:c=>c,teamName:(n,r=rules)=>r.teamNames[n-1],isRoomHost:()=>true,isRoomEditable:()=>sandbox.phase==='menu',currentRules:()=>sandbox.localRoom.rules,localPlayerID:()=>0,roomMembers:r=>r?r.players:sandbox.localRoom.players,roomData:()=>({host:0,players:sandbox.localRoom.players.filter(p=>!p.spectating)}),validateRoomRules:r=>({...r}),defaultRoomRules:()=>({...rules}),persistLocalRoomRules(){},resetPreviewIfLobby(options){sandbox.preview=options||{};},renderOnlineRoom(){},savedLocalCallsign:()=> 'P2',canEditTankPaint:()=>false,makeKickButton:()=>new Element('button'),moveLocalMember(p,id,spectating,team){p.id=id;p.spectating=spectating;p.team=team;},refreshLocalRoles(){},...extra};
 vm.createContext(sandbox);
 for(const name of ['survivalMode','roomCapacity','survivalSeatLocked','activeTeamCount','nextRoomTeam','balanceLocalTeams','normalizeRoomTeams','setLocalRules','syncPauseButton','roomPlayerStatus','makeRoomPlayerRow','changeSeat','addRoomSeat','cleanPilotName','validatePreset','setPlayerSpectating','roomStartError','updateRuleHelp','readRuleTeamSettings','syncFeatureSummary'])vm.runInContext(declaration(name),sandbox);
 return {...sandbox,s:sandbox,$,elements};
}
const players=n=>Array.from({length:n},(_,id)=>({id,member:id+1,name:'P'+id,kind:id?'bot':'human',team:0,difficulty:'normal'}));
const teams=b=>b.s.localRoom.players.filter(p=>!p.spectating).map(p=>p.team);

test('enabling Teams distributes 1–8 tanks across every eligible team, skipping spectators',()=>{
 for(const mode of ['elimination','koth','ctf'])for(let n=1;n<=8;n++){
  const b=boot();b.s.localRoom.players=players(n);b.s.localRoom.players.push({id:8,spectating:true,team:0});
  b.s.localRoom.rules={...b.s.localRoom.rules,mode,teamMode:'ffa'};
  b.s.setLocalRules({...b.s.localRoom.rules,teamMode:'teams'});
  assert.deepEqual(teams(b),Array.from({length:n},(_,i)=>1+i%(mode==='ctf'?2:4)));
  assert.equal(b.s.preview.regenerateMaze,false);
 }
});
test('new bot and local P2 fill the least-populated team and preserve manual choices',()=>{
 for(const mode of ['elimination','koth','ctf']){
  const b=boot();b.s.localRoom.rules.mode=mode;b.s.localRoom.players=players(1);b.s.localRoom.players[0].team=1;
  for(let i=1;i<8;i++){b.s.addRoomSeat(i===1?'local':'bot');assert.equal(b.s.localRoom.players[i].team,1+i%(mode==='ctf'?2:4));}
  const before=teams(b);b.s.addRoomSeat('bot');assert.deepEqual(teams(b),before);
 }
 const b=boot();b.s.localRoom.players=players(3);b.s.localRoom.players.forEach(p=>p.team=3);b.s.addRoomSeat('bot');assert.deepEqual(teams(b),[3,3,3,1]);
});
test('online add leaves the team decision to the server; active matches reject local adds',()=>{
 const b=boot({mode:'online'});b.s.addRoomSeat('bot');assert.equal(b.s.sent.type,'add');assert.equal('team' in b.s.sent,false);
 b.s.mode='room';b.s.phase='playing';b.s.addRoomSeat('bot');assert.equal(b.s.localRoom.players.length,0);
});
test('changing to and from CTF rebalances, while other rule edits preserve host assignments',()=>{
 const b=boot();b.s.localRoom.players=players(8);b.s.balanceLocalTeams();
 b.s.setLocalRules({...b.s.localRoom.rules,mode:'ctf'});assert.deepEqual(teams(b),[1,2,1,2,1,2,1,2]);
 b.s.localRoom.players[1].team=1;b.s.setLocalRules({...b.s.localRoom.rules,timeLimit:100});assert.equal(teams(b)[1],1);
 b.s.setLocalRules({...b.s.localRoom.rules,mode:'elimination'});assert.deepEqual(teams(b),[1,2,3,4,1,2,3,4]);
});
test('CTF roster menus contain only first two teams; FFA has no team menu',()=>{
 for(const [mode,format,want] of [['ctf','teams',[1,2]],['elimination','teams',[1,2,3,4]],['koth','teams',[1,2,3,4]],['elimination','ffa',[]]]){
  const b=boot();b.s.localRoom.rules.mode=mode;b.s.localRoom.rules.teamMode=format;
  const r={host:0,phase:'lobby',rules:b.s.localRoom.rules},p={id:0,name:'PILOT',team:1,color:'#fff',kind:'human'};
  const row=b.s.makeRoomPlayerRow(p,r),controls=row.children[1],select=controls.children.find(c=>c.dataset.team===0);
  assert.deepEqual(select?select.children.map(c=>c.value):[],want);
 }
});
test('CTF rejects manual Teams 3/4 locally and before sending an online edit',()=>{
 for(const mode of ['room','online']){const b=boot({mode});b.s.localRoom.rules.mode='ctf';b.s.localRoom.players=players(2);b.s.balanceLocalTeams();b.s.changeSeat(b.s.localRoom.players[1],{team:4});assert.equal(teams(b)[1],2);assert.equal(b.s.sent,undefined);assert.match(b.s.notice,/Team 1 and Team 2/);}
});
test('legacy CTF presets migrate to two teams; valid manual presets retain their teams',()=>{
 const b=boot();const rules={...b.s.localRoom.rules,mode:'ctf'};
 const roster=players(4).map((p,i)=>({...p,team:i<2?3:4}));const before=JSON.stringify(roster);
 const migrated=b.s.validatePreset({rules,roster});assert.deepEqual(Array.from(migrated.roster,p=>p.team),[1,2,1,2]);assert.equal(JSON.stringify(roster),before);
 const valid=b.s.validatePreset({rules,roster:roster.map((p,i)=>({...p,team:i<3?1:2}))});assert.deepEqual(Array.from(valid.roster,p=>p.team),[1,1,1,2]);
});
test('spectators entering play fill an empty side, including after a CTF transition',()=>{
 const b=boot();b.s.localRoom.players=[...players(2).map((p,i)=>({...p,team:i+1})),{id:8,member:9,kind:'human',spectating:true,team:1}];
 b.s.setPlayerSpectating(b.s.localRoom.players[2],false);assert.deepEqual(teams(b),[1,2,3]);
});
test('pause visibility and labels track lobby, match, results, local pause and online connection',()=>{
 const b=boot();
 for(const phase of ['menu','onlineLobby','lobby','matchOver']){b.s.phase=phase;b.s.syncPauseButton();assert.equal(b.$('pauseBtn').hidden,true,phase);}
 for(const phase of ['countdown','playing','roundOver','paused']){b.s.phase=phase;b.s.syncPauseButton();assert.equal(b.$('pauseBtn').hidden,false,phase);}
 assert.equal(b.$('pauseBtn').getAttribute('aria-label'),'Resume game');
 b.s.mode='online';b.s.phase='playing';b.s.syncPauseButton();assert.equal(b.$('pauseBtn').getAttribute('aria-label'),'Match menu');
 b.s.online.connected=false;b.s.syncPauseButton();assert.equal(b.$('pauseBtn').hidden,true);
 assert.match(readFileSync(path.join(__dirname,'../web/index.html'),'utf8'),/id="pauseBtn"[^>]*\bhidden\b/);
});
test('rules hide inactive team fields and respawn settings without losing saved team names',()=>{
 const b=boot({mapDimensions:()=>[12,10],pickupLimitText:()=>'',pickupLifetime:()=>32});
 b.$('rule-mode').value='ctf';b.$('rule-teamMode').value='teams';b.$('rule-teamName3').value='Saved team';b.s.updateRuleHelp();
 for(let i=1;i<=4;i++){assert.equal(b.$('rule-teamName'+i).parentElement.hidden,i>2);assert.equal(b.$('rule-teamName'+i).disabled,i>2);}
 b.$('rule-mode').value='elimination';b.$('rule-teamMode').value='ffa';b.s.updateRuleHelp();assert.equal(b.$('teamNamesEditor').hidden,true);assert.equal(b.$('rule-friendlyFire').parentElement.hidden,true);assert.equal(b.$('rule-respawnSeconds').parentElement.hidden,true);
 b.$('rule-teamMode').value='teams';b.s.updateRuleHelp();assert.equal(b.$('rule-teamName3').value,'Saved team');assert.equal(b.$('rule-teamName3').parentElement.hidden,false);
});
test('unchanged room metadata does not rebuild the field manual DOM',()=>{
 const b=boot({modeLabel:()=> 'ELIMINATION',displayScoreTarget:()=> 'FIRST TO 5',modeInstructions:()=> 'Play',roomStartError:()=> '',controlSummary:()=> 'KEYS',fieldManualHTML:()=> '<p>Controls</p>'});
 b.s.roomStartError=()=>'';
 for(let i=0;i<20;i++)b.s.syncFeatureSummary();
 assert.equal(b.$('manualContent').htmlWrites,1);
 b.s.fieldManualHTML=()=>'<p>Updated controls</p>';b.s.syncFeatureSummary();assert.equal(b.$('manualContent').htmlWrites,2);
});

test('inactive team fields cannot block applying FFA or CTF with unfinished hidden names',()=>{
 const b=boot();for(let i=1;i<=4;i++){b.$('rule-teamName'+i).value=i<=2?'New '+i:'';b.$('rule-teamColor'+i).value=String(i-1);}
 const ctf=b.s.readRuleTeamSettings({mode:'ctf',teamMode:'teams'});
 assert.deepEqual(Array.from(ctf.teamNames),['New 1','New 2','C','D']);
 const ffa=b.s.readRuleTeamSettings({mode:'elimination',teamMode:'ffa'});assert.deepEqual(Array.from(ffa.teamNames),['A','B','C','D']);
});

test('survival rules reject oversized squads without losing their roster or changing the old rules',()=>{
 const b=boot();b.s.localRoom.players=players(5);const rules=b.s.localRoom.rules,roster=JSON.stringify(b.s.localRoom.players);
 assert.throws(()=>b.s.setLocalRules({...rules,mode:'survival',teamMode:'teams'}),/four squad tanks/);
 assert.equal(b.s.localRoom.rules,rules);assert.equal(JSON.stringify(b.s.localRoom.players),roster);
 b.s.localRoom.players[4].spectating=true;b.s.setLocalRules({...rules,mode:'survival',teamMode:'teams'});assert.deepEqual(teams(b),[1,1,1,1]);const length=b.s.localRoom.players.length;b.s.addRoomSeat('bot');assert.equal(b.s.localRoom.players.length,length);assert.match(b.s.notice,/four squad seats/);
});
test('survival roster hides team assignments and presets normalize one cooperative squad',()=>{
 const b=boot();b.s.localRoom.rules.mode='survival';const p={id:0,name:'PILOT',team:1,color:'#fff',kind:'human'},r={host:0,phase:'lobby',rules:b.s.localRoom.rules};
 assert.equal(b.s.makeRoomPlayerRow(p,r).children[1].children.some(c=>c.dataset.team===0),false);
 const preset=b.s.validatePreset({rules:b.s.localRoom.rules,roster:players(4).map((p,i)=>({...p,team:i+1}))});assert.deepEqual(Array.from(preset.roster,p=>p.team),[1,1,1,1]);assert.throws(()=>b.s.validatePreset({rules:b.s.localRoom.rules,roster:players(5)}),/four squad tanks/);
});
