'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=process.env.LEQRA_HUD_SOURCE?readFileSync(process.env.LEQRA_HUD_SOURCE,'utf8'):readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot(mode='room',gameMode='survival'){
 const writes=[],elements=new Map(),headerIDs=new Set(['arenaStatus','roundLabel','clock','objectiveModeLabel','objectiveStatus','target']);
 const element=id=>{if(!elements.has(id)){const classes=new Set();elements.set(id,{hidden:false,value:'',style:{},classList:{toggle(name,on){if(on)classes.add(name);else classes.delete(name);},contains:name=>classes.has(name)},get textContent(){return this.value;},set textContent(value){this.value=String(value);if(headerIDs.has(id))writes.push([id,this.value]);}});}return elements.get(id);};
 const rules={mode:gameMode,scoreTarget:15},noop=()=>{};
 const s={mode,phase:'playing',round:1,roundClock:75,phaseTime:2,goUntil:0,COLORS:['#fff'],tanks:[],performance:{now:()=>1000},$:element,document:{body:{classList:{toggle:noop}},querySelector:()=>element('target')},online:{connected:true,code:'TEST',latency:35,snapshots:[{received:1000}],buffer:{delay:80}},POWER:{},rules,objective:{mode:gameMode,flags:[],owner:0,survival:gameMode==='survival'?{wave:1,waveTarget:15,enemiesRemaining:2,status:'wave',breakTime:0}:null},currentRules:()=>rules,objectiveMode:()=>['ctf','koth'].includes(rules.mode),survivalMode:()=>rules.mode==='survival',objectiveState:()=>s.objective,survivalState:()=>s.objective.survival,survivalBreak:()=>s.objective.survival?.status==='break',suddenDeath:()=>!!s.objective.suddenDeath,survivalBossPreview:()=>null,displayScoreTarget:()=>rules.scoreTarget,modeInstructions:()=>rules.mode,teamName:id=>'Team '+id,shortTeamName:id=>'Team '+id,paintColor:c=>c,syncPauseButton:noop,renderLineup:noop,controlledTank:()=>null,pilotLoadoutTank:()=>null,localPlayerID:()=>0,secondaryID:()=>null,renderPilotLoadout:()=>null,updateCombatFeedback:noop,syncSpectatingHUD:noop,tone:noop,writes};
 vm.createContext(s);for(const name of ['setText','survivalBossName','onlineHUD','updateObjectiveHUD','updateHUD'])vm.runInContext(declaration(name),s);return s;
}
test('unchanged offline and online HUDs do not replace their status text each refresh',()=>{
 for(const mode of ['room','online'])for(const gameMode of ['elimination','ctf','koth','survival']){
  const s=boot(mode,gameMode);s.updateHUD();s.writes.length=0;
  for(let n=0;n<30;n++)s.updateHUD(n%2===0);
  assert.deepEqual(s.writes,[],mode+' '+gameMode+' should not rewrite stable labels');
 }
});
test('Survival wave, break, boss and result transitions keep the final labels without intermediate generic text',()=>{
 for(const mode of ['room','online']){
  const s=boot(mode);s.round=4;s.objective.survival.wave=4;s.updateHUD();s.writes.length=0;
  Object.assign(s.objective.survival,{status:'break',breakTime:4,enemiesRemaining:0});s.updateHUD();
  assert.equal(s.$('arenaStatus').textContent,'BETWEEN WAVES');assert.equal(s.$('roundLabel').textContent,'WAVE 04');assert.equal(s.$('clock').textContent,'4s');assert.equal(s.$('clock').classList.contains('urgent'),false);
  assert.equal(s.writes.filter(([id])=>id==='clock').length,1);assert.equal(s.writes.filter(([id])=>id==='arenaStatus').length,1);
  s.writes.length=0;for(let n=0;n<10;n++){s.objective.survival.breakTime-=.08;s.updateHUD();}assert.deepEqual(s.writes,[]);
  s.round=5;Object.assign(s.objective.survival,{wave:5,status:'wave',breakTime:0,enemiesRemaining:4,boss:true});s.updateHUD();
  assert.equal(s.$('arenaStatus').textContent,'SURVIVAL');assert.equal(s.$('roundLabel').textContent,'WAVE 05');assert.equal(s.$('clock').textContent,'01:15');assert.equal(s.$('objectiveStatus').textContent,'4 ENEMIES LEFT · NORMAL BOSS');
  s.phase='matchOver';s.updateHUD();assert.equal(s.$('arenaStatus').textContent,'MATCH COMPLETE');assert.equal(s.$('objectiveBar').hidden,true);
  s.phase=mode==='online'?'onlineLobby':'menu';s.updateHUD();assert.equal(s.$('arenaStatus').textContent,mode==='online'?'ROOM LOBBY':'READY ROOM');
 }
});
test('objective clock updates once per displayed second and sudden death stays stable',()=>{
 const s=boot('online','koth');s.updateHUD();s.writes.length=0;s.roundClock=74.92;s.updateHUD();assert.deepEqual(s.writes,[]);
 s.roundClock=74;s.updateHUD();assert.deepEqual(s.writes,[['clock','01:14']]);
 s.objective.suddenDeath=true;s.updateHUD();assert.equal(s.$('clock').textContent,'SD');assert.equal(s.$('clock').classList.contains('urgent'),true);assert.equal(s.$('objectiveModeLabel').textContent,'SUDDEN DEATH');assert.equal(s.$('roundLabel').textContent,'HILL');
 s.writes.length=0;for(let n=0;n<30;n++)s.updateHUD();assert.deepEqual(s.writes,[]);
});

test('pausing Survival keeps PAUSED visible during both waves and the intermission',()=>{
 const s=boot();for(const status of ['wave','break']){
  Object.assign(s.objective.survival,{status,breakTime:4});s.phase='playing';s.updateHUD();s.phase='paused';s.updateHUD();
  assert.equal(s.$('arenaStatus').textContent,'PAUSED');assert.equal(s.$('roundLabel').textContent,'WAVE 01');assert.equal(s.$('objectiveBar').hidden,false);assert.equal(s.$('clock').textContent,status==='break'?'4s':'01:15');
  s.writes.length=0;for(let n=0;n<10;n++)s.updateHUD();assert.deepEqual(s.writes,[]);
  s.phase='playing';s.updateHUD();assert.equal(s.$('arenaStatus').textContent,status==='break'?'BETWEEN WAVES':'SURVIVAL');
 }
});
