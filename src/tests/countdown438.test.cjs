'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),path=require('node:path');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'('),end=source.indexOf('\n',start),line=source.slice(start,end);assert.ok(start>=0,name);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
const clone=value=>JSON.parse(JSON.stringify(value));
function boot(gameMode='elimination',online=false){
 const nodes=new Map(),noop=()=>{},$=id=>{if(!nodes.has(id)){const classes=new Set();nodes.set(id,{hidden:false,textContent:'',style:{},dataset:{},classList:{toggle(key,value){value?classes.add(key):classes.delete(key);},contains:key=>classes.has(key)},classes,focus:noop,firstElementChild:{textContent:''}});}return nodes.get(id);};
 const s={$,console,mode:online?'online':'room',phase:'countdown',pausedFrom:'countdown',round:1,roundClock:75,phaseTime:3,goUntil:0,pendingMatchPresentation:null,MAX_TANKS:8,COLORS:['#fff'],localRoom:{players:[],self:0},online:{code:'ROOM',token:'SESSION',generation:1,menu:false,snapshots:[{generation:1}]},tanks:[],bullets:[],particles:[],rings:[],traces:[],pickups:[],scores:[],toastTime:0,roundWinner:-1,gameStarted:false,
  performance:{now:()=>1000},tone:noop,paintColor:value=>value,localObjectives:null,document:{body:{classList:{toggle:noop}},querySelector:()=>$('target')},teamName:n=>'Team '+n,shortTeamName:n=>'Team '+n,suddenDeath:()=>false,closeVictory:noop,clearInput:noop,makeMaze(){s.mazes=(s.mazes||0)+1;},resetTanks(){s.tanks=[];},bindLocalTankStats:noop,initObjectives(){s.localObjectives=s.rules.mode==='survival'?{mode:'survival',flags:[],survival:{wave:1,waveTarget:s.rules.scoreTarget,status:'wave'}}:{mode:s.rules.mode,flags:[],owner:0};},seedPickups:noop,pickupInterval:()=>[1,2],setScreen:noop,canvas:{focus:noop},initAudio:noop,beginLocalMatchStats:noop,roomStartError:()=>'',addLog:noop,logLines:[],lastFrame:0,accumulator:0,renderOnlineRoom:noop,localMatchResult:null};
 vm.createContext(s);vm.runInContext(source.slice(source.indexOf('const POWER_EFFECT_DURATION='),source.indexOf("let phase='menu'")),s);vm.runInContext(source.match(/const MAZE_SIZES=[^\n]+/)[0]+'\n'+source.match(/const countdownTipHistory=[^\n]+/)[0],s);
 for(const name of ['defaultRoomRules','defaultModeRules','mapDimensions','pickupCap','pickupLifetime','powerEffectDuration','countdownTipPool','getCountdownTip','setText','objectiveMode','survivalMode','survivalState','survivalBreak','survivalBossName','survivalWavePlan','survivalBossPreview','modeLabel','displayScoreTarget','modeInstructions','updateObjectiveHUD','startRound','startMatch','toggleRoomMenu'])vm.runInContext(declaration(name),s);
 s.rules=s.defaultModeRules(gameMode);s.localRoom.rules=s.rules;s.currentRules=()=>s.rules;s.objectiveState=()=>s.localObjectives;s.initObjectives();
 const hud=declaration('updateHUD'),start=hud.indexOf(" const announce=$('announcer')"),end=hud.indexOf(" if(mode==='online')onlineHUD();",start);vm.runInContext('function updateHUD(){\n'+hud.slice(start,end)+'\n}',s);
 return{s,$};
}

test('each mode has concise relevant tips, with extra Survival rules and configured targets',()=>{
 for(const mode of ['elimination','ctf','koth','survival']){
  const {s}=boot(mode);const tips=clone(s.countdownTipPool());assert.ok(tips.length>=18,mode);assert.equal(new Set(tips.map(t=>t.id)).size,tips.length);assert.equal(tips.every(t=>t.text.length<=90),true,'readable in a three-second countdown');
  assert.equal(tips.some(t=>t.id.startsWith(mode+'-')),true);assert.equal(tips.some(t=>t.id.startsWith(mode==='survival'?'ctf-':'survival-')),false);
  s.rules.scoreTarget=1;s.rules.respawnSeconds=7;const current=clone(s.countdownTipPool());if(mode!=='survival')assert.match(current.find(t=>t.id===mode+'-target').text,/\b1 (?:round|capture|hill point)\b/);
  if(mode==='ctf'||mode==='koth')assert.match(current.find(t=>t.id==='objective-respawn').text,/7 seconds/);
 }
 const {s}=boot('survival');assert.ok(s.countdownTipPool().filter(t=>t.id.startsWith('survival-')).length>=8);
});

test('power-up advice follows enabled pickups and derives durations from the actual map and constants',()=>{
 const {s}=boot('survival');const kinds=vm.runInContext('Object.keys(POWER)',s);
 for(const kind of kinds){s.rules.weapons=[kind];const power=s.countdownTipPool().filter(t=>t.id.startsWith('power-')&&t.id!=='power-duration');assert.deepEqual(Array.from(power,t=>t.id),['power-'+kind]);}
 for(const mapSize of ['compact','standard','large','huge','giant','ultrawide']){
  s.rules.mapSize=mapSize;s.rules.weapons=['rapid','grenade'];const tips=s.countdownTipPool(),[c,r]=s.mapDimensions(mapSize);
  assert.match(tips.find(t=>t.id==='power-duration').text,new RegExp(' '+s.powerEffectDuration(c,r)+' seconds'));
  assert.match(tips.find(t=>t.id==='pickup-expiry').text,new RegExp(' '+s.pickupLifetime(c,r)+' seconds'));
  assert.match(tips.find(t=>t.id==='power-rapid').text,/3 seconds of firing/);assert.match(tips.find(t=>t.id==='power-grenade').text,/10-second fuse/);
 }
 for(const setting of ['off','empty']){s.rules.pickupRate=setting==='off'?'off':'normal';s.rules.weapons=setting==='empty'?[]:['shield','laser'];const tips=s.countdownTipPool();assert.equal(tips.some(t=>t.id.startsWith('power-')||t.id==='pickup-expiry'),false);assert.equal(tips.some(t=>t.id==='survival-boss-shield'),true,'boss starting bonus is independent of pickup selection');}
});

test('team and boss advice reflects the current format, friendly fire and configured Survival length',()=>{
 const {s}=boot('koth');assert.equal(s.countdownTipPool().some(t=>t.id==='friendly-fire'||t.id==='koth-team-score'),false);
 s.rules.teamMode='teams';s.rules.friendlyFire=true;assert.match(s.countdownTipPool().find(t=>t.id==='friendly-fire').text,/is ON/);assert.ok(s.countdownTipPool().find(t=>t.id==='koth-team-score'));
 s.rules.friendlyFire=false;assert.match(s.countdownTipPool().find(t=>t.id==='friendly-fire').text,/is OFF/);
 s.rules=s.defaultModeRules('survival');for(const target of [4,5,9,10,14,15]){s.rules.scoreTarget=target;const tips=s.countdownTipPool(),tiers=tips.find(t=>t.id==='survival-boss-tiers');assert.equal(!!tiers,target>=5);assert.equal(!!tiers?.text.includes('Fierce'),target>=10);assert.equal(!!tiers?.text.includes('Godlike'),target>=15);}
});

test('actual local round starts and full rematches rotate tips while redraws and pause/resume keep one stable tip',()=>{
 for(const mode of ['elimination','ctf','koth']){
  const {s,$}=boot(mode);s.startMatch();const seen=new Set();
  for(let n=0;n<8;n++){
   const text=$('announceSub').textContent;assert.ok(text);assert.equal(seen.has(text),false,'successive countdowns vary');seen.add(text);
   for(const phaseTime of [3,2.9,2,1.1,.1]){s.phaseTime=phaseTime;s.updateHUD();s.updateObjectiveHUD();assert.equal($('announceSub').textContent,text,'objective HUD must not overwrite tips');}
   s.toggleRoomMenu();assert.equal(s.phase,'paused');s.updateHUD();assert.equal($('announcer').hidden,true);s.toggleRoomMenu();s.updateHUD();assert.equal(s.phase,'countdown');assert.equal($('announceSub').textContent,text);
   if(n%2){s.round++;s.startRound();}else s.startMatch();
  }
  assert.ok(s.localRoom.countdownSerial>=9);assert.ok(s.mazes>=9);
 }
});

test('online snapshots keep a countdown tip stable and new authoritative generations rotate it',()=>{
 for(const gameMode of ['elimination','ctf','koth','survival']){
  const {s,$}=boot(gameMode,true);s.updateHUD();const first=$('announceSub').textContent;
  for(let tick=1;tick<=60;tick++){s.online.snapshots=[{generation:1,tick}];s.phaseTime=3-tick/30;s.updateHUD();assert.equal($('announceSub').textContent,first);}
  s.phase='paused';s.updateHUD();s.phase='countdown';s.updateHUD();assert.equal($('announceSub').textContent,first);
  // A same-wave retry and a round-one rematch both receive a new generation.
  s.online.snapshots=[{generation:2}];s.updateHUD();const second=$('announceSub').textContent;assert.notEqual(second,first);
  s.online.snapshots=[{generation:3}];s.round=1;s.updateHUD();assert.notEqual($('announceSub').textContent,second);
 }
});

test('boss countdown prioritizes its existing gear preview and never leaks it into a cleared-wave hold',()=>{
 const {s,$}=boot('survival');s.rules.scoreTarget=15;s.rules.weapons=['shield','homing'];s.round=5;Object.assign(s.localObjectives.survival,{wave:5,waveTarget:15,boss:true});
 s.updateHUD();const gear=$('announceSub').textContent;assert.equal(gear,'Equipment: 1 shield charge · Homing missiles');assert.equal($('announcer').classes.has('boss-preview'),true);
 assert.equal(vm.runInContext('countdownTipHistory.current',s),null,'boss equipment does not consume or overwrite a general tip');
 s.phase='paused';s.updateHUD();assert.equal($('announcer').hidden,true);s.phase='countdown';s.phaseTime=1;s.updateHUD();assert.equal($('announceSub').textContent,gear);
 s.phase='playing';Object.assign(s.localObjectives.survival,{status:'break',breakTime:2});s.updateHUD();assert.equal($('announceSub').textContent,'New maze in 2…');assert.equal($('announcer').classes.has('boss-preview'),false);
});


test('creating a fresh local room preserves the countdown sequence for the next run',()=>{
 const {s,$}=boot();s.startMatch();const first=s.getCountdownTip(),serial=s.localRoom.countdownSerial;
 Object.assign(s,{loadLocalRoomRules:()=>s.rules,restoreSavedLocalRoster:()=>false,callsignForms:()=>[],readyRoom(){}});s.document.body.classList.remove=()=>{};s.document.documentElement={style:{removeProperty(){}}};s.localRoom.nextMember=0;
 vm.runInContext(declaration('createLocalRoom'),s);s.createLocalRoom();assert.equal(s.localRoom.countdownSerial,serial);s.startMatch();assert.equal(s.localRoom.countdownSerial,serial+1);assert.notEqual(s.getCountdownTip(),first);
});
