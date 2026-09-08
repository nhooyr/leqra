'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
class Element{constructor(){this.hidden=false;this.textContent='';this.style={setProperty(){}};this.children=[];this.classList={toggle(){},add(){},remove(){}};}setAttribute(k,v){this[k]=v;}replaceChildren(...c){this.children=c;}querySelectorAll(){return this.children.map(c=>c.children[0]).filter(Boolean);}append(...c){this.children.push(...c);}showModal(){this.open=true;}focus(){}close(){this.open=false;}}
function boot({count=2,ids=[0,1,2,3],target=10,weapons=['shield','speed','homing','cannon','laser'],pickupRate='superfast'}={}){
 const rules={mode:'survival',teamMode:'teams',mapSize:'large',teamNames:['SQUAD','ENEMIES','C','D'],teamColors:[0,1,2,3],scoreTarget:target,timeLimit:75,respawnSeconds:3,pickupRate,weapons};
 const players=ids.slice(0,count).map((id,i)=>({id,member:id+100,kind:i?'bot':'human',team:1,name:'SQUAD '+i,difficulty:'hard',connected:true}));
 const elements=new Map(),$=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id);};
 const s={console,mode:'room',phase:'playing',MAX_TANKS:8,RADIUS:17,CELL:84,cols:7,rows:7,W:588,H:588,POWER:Object.fromEntries(weapons.map(w=>[w,{}])),POWER_EFFECT_DURATION:10,MACHINE_FIRING_ROUNDS:180,MAX_SPEED_STACKS:5,SCOPE_DURATION:10,GHOST_DURATION:10,COLORS:['#fff','#f00'],NAMES:[],difficulty:'normal',tanks:[],bullets:[],traces:[],pickups:[],scores:Array(8).fill(0),round:1,roundClock:75,spawnClock:0,goUntil:0,fxTime:0,spawnGuideUntil:0,localObjectives:null,localSurvivalCheckpoint:null,particles:[],rings:[],shake:0,toastTime:0,phaseTime:0,gameStarted:true,pausedFrom:'playing',lastFrame:0,accumulator:0,performance:{now:()=>1000},canvas:{focus(){}},setScreen(){},closeVictory(){},initAudio(){},updateHUD(){},firePresses:new Set(),localRoom:{rules,players,self:players[0].id},online:{snapshots:[]},$,document:{createElement:()=>new Element(),querySelectorAll:()=>[],querySelector:()=>new Element()},grid:Array.from({length:49},(_,i)=>({neighbors:[i%7?i-1:-1,i%7<6?i+1:-1,i>=7?i-7:-1,i<42?i+7:-1].filter(n=>n>=0)})),currentRules:()=>rules,center:i=>({x:(i%7+.5)*84,y:(Math.floor(i/7)+.5)*84}),cellAt:(x,y)=>Math.floor(y/84)*7+Math.floor(x/84),distance:(a,b)=>Math.hypot(a.x-b.x,a.y-b.y),rnd:(a,b)=>(a+b)/2,teamColor:(id,team)=>team===1?'#fff':'#f00',teamName:id=>rules.teamNames[id-1],teamKey:p=>'team'+p.team,shieldCount:t=>t.shieldCharges||0,speedCount:t=>t.speedStacks||0,clearInput(){s.inputClears=(s.inputClears||0)+1;},addLog(){},addRing(){},toast(){},pickupInterval:()=>[1,2],seedPickups(){s.seeds=(s.seeds||0)+1;s.pickups.push({type:'shield',life:30});},finishMatch(winner){s.winner=winner;s.finishLocalMatchStats(winner);s.phase='matchOver';},roomData:()=>({phase:s.phase,rules,players:s.localRoom.players.filter(p=>!p.spectating),spectators:s.localRoom.players.filter(p=>p.spectating)}),localPlayerID:()=>s.localRoom.self,localMatchStats:null,localMatchReport:null,localMatchResult:null,localPlayerID:()=>s.localRoom.self,secondaryMember:()=>null,roomMember:id=>s.localRoom.players.find(p=>p.id===id),syncResultActions(){},paintColor:c=>c,renderMatchStats(){},suddenDeath:()=>false};
 vm.createContext(s);
 for(const name of ['botLevelName','powerEffectDuration','newTank','spawnCells','respawnLocalTank','flagSafeSpawn','grantPower','setText','modeLabel','displayScoreTarget','objectiveState','objectiveMode','survivalMode','survivalState','survivalBreak','roomCapacity','survivalSeatLocked','roomStartError','survivalBossName','survivalWavePlan','survivalSpawnPoint','initLocalSurvival','captureLocalSurvivalCheckpoint','canRestartSurvivalWave','restartLocalSurvivalWave','startLocalSurvivalWave','showLocalSpawnGuide','prepareLocalSurvivalBreak','endLocalSurvival','stepLocalSurvival','survivalResultState','survivalResultText','beginLocalMatchStats','bindLocalTankStats','finishLocalMatchStats','updateObjectiveHUD','fire','showVictory','matchResultEntries','resultMemberMatches'])vm.runInContext(declaration(name),s);
 s.tanks=players.map((p,i)=>s.newTank(p.id,s.spawnCells()[i]));s.beginLocalMatchStats();for(const t of s.tanks)s.bindLocalTankStats(t);s.initLocalSurvival();return s;
}
function clearWave(s){for(const t of s.tanks)if(t.survivalEnemy)t.alive=false;s.stepLocalSurvival(1/120);}
test('one to four survival squad members allow a solo human start and never become enemies',()=>{
 for(let n=1;n<=4;n++){const s=boot({count:n,ids:[7,2,4,6]});assert.equal(s.roomStartError(),'');assert.equal(s.roomCapacity(),4);assert.equal(s.objectiveMode(),false);assert.equal(s.tanks.length,n+2);assert.equal(s.localRoom.players.length,n);assert.equal(new Set(s.tanks.map(t=>t.id)).size,s.tanks.length);for(const e of s.tanks.filter(t=>t.survivalEnemy)){assert.ok(e.id>=0&&e.id<8);assert.equal(e.human,false);assert.equal(e.team,2);assert.equal(s.localRoom.players.some(p=>p.id===e.id),false);}}
 const s=boot();s.localRoom.players.forEach(p=>p.kind='bot');assert.equal(s.roomStartError(),'');s.localRoom.players.push(...Array(3).fill({kind:'human',connected:true}));assert.match(s.roomStartError(),/four/);
});
test('wave plan scales to four enemies, alternates boss weapons and respects every enabled selection',()=>{
 const s=boot();for(let wave=1;wave<=20;wave++){const p=s.survivalWavePlan(wave);assert.equal(p.count,Math.min(4,2+Math.floor((wave-1)/2)));assert.equal(p.boss,wave%5===0);assert.equal(p.difficulty,wave<=5?'easy':wave<=10?'normal':wave<=15?'hard':'godlike');}
 assert.deepEqual([5,10,15,20].map(w=>s.survivalWavePlan(w).weapon),['homing','cannon','laser','homing']);
 s.currentRules().weapons=['homing','laser'];assert.equal(s.survivalWavePlan(10).weapon,'laser');s.currentRules().pickupRate='off';assert.equal(s.survivalWavePlan(10).weapon,null);
});
test('wave clear awards every squad member once, keeps the maze, clears hazards and revives after four seconds',()=>{
 const s=boot(),grid=s.grid,players=s.localRoom.players;s.tanks[0].alive=false;s.tanks[1].power='cannon';s.tanks[1].powerTime=6;s.bullets=[{}];s.pickups=[{type:'shield',life:4}];clearWave(s);
 assert.equal(s.survivalState().status,'break');assert.equal(s.tanks[0].alive,false);assert.equal(s.bullets.length,0);assert.equal(s.pickups.length,0);assert.deepEqual(Array.from(s.scores.slice(0,2)),[1,1]);assert.equal(s.localRoom.players,players);s.stepLocalSurvival(3.9);assert.equal(s.survivalState().wave,1);s.stepLocalSurvival(.1);
 assert.equal(s.survivalState().wave,2);assert.equal(s.survivalState().status,'wave');assert.equal(s.grid,grid);assert.equal(s.roundClock,75);assert.equal(s.tanks.filter(t=>!t.survivalEnemy).every(t=>t.alive&&t.power===null),true);assert.equal(s.seeds,1);assert.ok(s.inputClears>=3);
});
test('fifth-wave boss introduces Normal skill and only enabled gear, with no extra room participant',()=>{
 for(const [pickupRate,weapons,charges,speed,weapon]of[['superfast',['shield','speed','homing'],1,0,'homing'],['superfast',['cannon'],0,0,'cannon'],['off',['shield','speed','homing'],0,0,null]]){
  const s=boot({pickupRate,weapons});s.localObjectives.survival.wave=4;s.startLocalSurvivalWave();const boss=s.tanks.find(t=>t.survivalBoss);assert.equal(boss.name,'NORMAL BOSS');assert.equal(boss.difficulty,'normal');assert.equal(boss.shieldCharges,charges);assert.equal(boss.speedStacks,speed);assert.equal(boss.power,weapon);assert.equal(s.localRoom.players.length,2);assert.equal(s.tanks.filter(t=>t.survivalEnemy).length,4);
 }
});
test('squad wipes and timeout lose the run, including simultaneous final-enemy destruction',()=>{
 for(const reason of ['wipe','timeout','mutual','empty-squad']){const s=boot();if(reason==='timeout')s.roundClock=0;else if(reason==='empty-squad')s.localRoom.players.forEach(p=>p.spectating=true);else for(const t of s.tanks)if(reason==='mutual'||!t.survivalEnemy)t.alive=false;s.stepLocalSurvival(1/120);assert.equal(s.phase,'matchOver',reason);assert.equal(s.winner,-1);assert.equal(s.survivalState().status,'lost');assert.equal(s.survivalState().wavesCleared,0);}
});
test('final wave wins without a new maze or another break and freezes squad-only statistics',()=>{
 const s=boot({target:2});clearWave(s);s.stepLocalSurvival(4);clearWave(s);assert.equal(s.phase,'matchOver');assert.equal(s.survivalState().status,'won');assert.equal(s.survivalState().wavesCleared,2);assert.equal(s.localMatchReport.players.length,2);assert.ok(s.localMatchReport.players.every(p=>p.winner&&p.score===2));assert.equal(s.localMatchReport.survival.status,'won');s.localObjectives.survival.wave=99;assert.equal(s.localMatchReport.survival.wave,2);
});
test('survival HUD explains enemies, bosses and squad returns instead of Hill or respawn timers',()=>{
 const s=boot();s.updateObjectiveHUD();assert.equal(s.$('objectiveModeLabel').textContent,'WAVE 1 / 10');assert.equal(s.$('objectiveStatus').textContent,'2 ENEMIES LEFT');s.survivalState().wave=5;s.survivalState().boss=true;s.updateObjectiveHUD();assert.match(s.$('objectiveStatus').textContent,/NORMAL BOSS/);clearWave(s);s.updateObjectiveHUD();assert.equal(s.$('objectiveStatus').textContent,'SQUAD RETURNS IN 4s');assert.equal(s.$('clock').textContent,'4s');
});
test('survival loss and victory dialogs report waves, never a draw or Hill result',()=>{
 for(const win of [false,true]){const s=boot({target:1});if(win)clearWave(s);else s.endLocalSurvival(false);s.showVictory(s.winner,s.tanks,s.localMatchReport);assert.equal(s.$('victoryTitle').textContent,win?'SURVIVAL COMPLETE!':'RUN ENDED');assert.match(s.$('victoryMessage').textContent,win?/All 1 wave cleared/:/0 \/ 1 waves cleared/);assert.equal(s.$('victoryScores').getAttribute?.('aria-label')??s.$('victoryScores')['aria-label'],'Waves cleared');}
});
test('spectators cannot enter or swap midrun, and break combat is blocked for local and online inputs',()=>{
 const s=boot();for(const phase of ['countdown','playing','paused']){s.phase=phase;assert.equal(s.survivalSeatLocked(),true);}for(const phase of ['menu','lobby','matchOver']){s.phase=phase;assert.equal(s.survivalSeatLocked(),false);}
 assert.match(declaration('setPlayerSpectating'),/!value&&\(survivalSeatLocked/);assert.match(declaration('confirmSwap'),/survivalSeatLocked/);s.phase='playing';clearWave(s);assert.equal(s.fire(s.tanks[0]),false);assert.match(declaration('onlineControls'),/!survivalBreak\(\)/);assert.match(declaration('update'),/if\(survivalMode\(\)\)\{if\(roundClock<=0\)/);
});
test('the final fraction of a wave clamps physics and match duration before a timeout loss',()=>{
 const s=boot();Object.assign(s,{fxTime:0,time:0,phaseTime:0,toastTime:0,particles:[],rings:[],shake:0,uiClock:1,spawnClock:Infinity,roundClock:.001,updateTraces(){},compactLife(){},advanceGhost(){},humanControl(t,dt){s.controlStep=dt;},botControl(t,dt){s.controlStep=dt;},updateBullets(dt){s.projectileStep=dt;},updateHUD(){}});
 vm.runInContext(declaration('liveLocalStats')+'\n'+declaration('update'),s);s.update(1/120);
 assert.equal(s.controlStep,.001);assert.equal(s.projectileStep,.001);assert.equal(s.localMatchStats.duration,.001);assert.equal(s.phase,'matchOver');assert.equal(s.survivalState().status,'lost');
});
test('completed survival progress survives a later lobby preview reset',()=>{
 const s=boot({target:1});clearWave(s);s.localObjectives=null;assert.equal(s.survivalResultText(),'All 1 wave cleared. The squad survived!');
});

// Cross-feature regressions run the merged power and survival implementations.
test('wave breaks preserve machine firing budget, then revival clears it',()=>{
 const s=boot(),pilot=s.tanks[0];s.grantPower(pilot,'rapid');pilot.machineRounds=73;clearWave(s);
 assert.equal(s.fire(pilot),false);assert.equal(pilot.machineRounds,73);s.stepLocalSurvival(4);
 assert.equal(pilot.machineRounds,0);assert.equal(pilot.power,null);
});
test('Huge survival bosses receive fifteen-second buffs and dead bosses leave the HUD',()=>{
 const s=boot();s.cols=14;s.rows=12;s.localObjectives.survival.wave=9;s.startLocalSurvivalWave();
 const boss=s.tanks.find(t=>t.survivalBoss);assert.equal(boss.powerTime,15);assert.equal(boss.shield,15);assert.equal(boss.speedTime,15);
 boss.alive=false;s.stepLocalSurvival(1/120);assert.equal(s.survivalState().boss,false);assert.equal(s.survivalState().enemiesRemaining,3);assert.equal(s.phase,'playing');
});
test('the earned wave-break revival continues if the surviving pilot spectates',()=>{
 const s=boot();s.localRoom.players[1].kind='local';s.tanks[1].alive=false;clearWave(s);
 s.localRoom.players[0].spectating=true;s.tanks=s.tanks.filter(t=>t.id!==0);s.stepLocalSurvival(4);
 assert.equal(s.phase,'playing');assert.equal(s.survivalState().wave,2);assert.equal(s.tanks.find(t=>t.id===1).alive,true);
});
test('generated enemies cannot inherit old scores and finished runs clear pickups',()=>{
 const s=boot();s.scores[2]=7;s.scores[3]=7;s.startLocalSurvivalWave();
 for(const enemy of s.tanks.filter(t=>t.survivalEnemy))assert.equal(s.scores[enemy.id],0);
 s.pickups=[{life:30}];s.endLocalSurvival(false);assert.equal(s.pickups.length,0);
});

test('Survival results let the last impact shake settle without advancing the finished game',()=>{
 for(const won of [false,true]){
  const s=boot({target:1});Object.assign(s,{fxTime:0,time:7,phaseTime:1,shake:.18});
  vm.runInContext(declaration('update'),s);if(won)clearWave(s);else s.endLocalSurvival(false);
  const state=JSON.stringify(s.survivalState()),clock=s.roundClock,positions=s.tanks.map(t=>[t.x,t.y]);
  for(let i=0;i<12;i++)s.update(1/120);assert.ok(s.shake>0&&s.shake<.18,'impact fades instead of freezing');
  for(let i=0;i<60;i++)s.update(1/120);assert.equal(s.shake,0);assert.equal(s.time,7);assert.equal(s.phaseTime,1);assert.equal(s.roundClock,clock);assert.equal(JSON.stringify(s.survivalState()),state);assert.deepEqual(s.tanks.map(t=>[t.x,t.y]),positions);
 }
});
test('paused and lobby views cannot leave the maze jiggling indefinitely',()=>{
 for(const phase of ['paused','menu']){const s=boot();Object.assign(s,{phase,fxTime:0,time:7,shake:.18});vm.runInContext(declaration('update'),s);for(let i=0;i<60;i++)s.update(1/120);assert.equal(s.shake,0);assert.equal(s.time,7);assert.equal(s.phase,phase);}
});
test('defeated local enemies retain their lineup rows until the next wave replaces them',()=>{
 const s=boot(),prior=s.tanks.filter(t=>t.survivalEnemy);for(const name of ['botLevelName','lineupMember','scoreboardEntries'])vm.runInContext(declaration(name),s);
 clearWave(s);s.stepLocalSurvival(3.9);
 assert.deepEqual(s.tanks.filter(t=>t.survivalEnemy),prior);assert.equal(prior.every(t=>!t.alive),true);
 const group=s.scoreboardEntries().find(t=>t.survivalEnemy);assert.equal(group.members.length,prior.length);assert.equal(group.members.every(t=>!t.alive),true);
 s.stepLocalSurvival(.2);const next=s.tanks.filter(t=>t.survivalEnemy);assert.equal(s.survivalState().wave,2);assert.equal(next.length,2);assert.equal(next.every(t=>t.alive&&!prior.includes(t)),true);
});
test('all-bot local squads clear waves, revive and win while their human host spectates',()=>{
 const s=boot({target:2});for(const p of s.localRoom.players)p.kind='bot';for(const t of s.tanks)if(!t.survivalEnemy)t.human=false;
 s.localRoom.players.push({id:8,member:999,kind:'human',name:'SPECTATOR',spectating:true});s.localRoom.self=8;
 assert.equal(s.roomStartError(),'');s.tanks[1].alive=false;clearWave(s);assert.equal(s.survivalState().status,'break');s.stepLocalSurvival(4);assert.equal(s.survivalState().wave,2);assert.equal(s.tanks[1].alive,true);clearWave(s);
 assert.equal(s.phase,'matchOver');assert.equal(s.survivalState().status,'won');assert.equal(s.localMatchReport.players.length,2);assert.equal(s.localMatchReport.players.every(p=>p.winner&&p.score===2),true);
});

test('stronger enemy tiers first appear as bosses, with staged armor and speed',()=>{
 const s=boot({target:20}),seen=new Set(['easy']);
 for(let wave=1;wave<=20;wave++){
  if(wave>1)s.startLocalSurvivalWave();
  const enemies=s.tanks.filter(t=>t.survivalEnemy),boss=enemies.find(t=>t.survivalBoss),difficulty=wave<=5?'easy':wave<=10?'normal':wave<=15?'hard':'godlike';
  for(const e of enemies.filter(t=>!t.survivalBoss)){assert.equal(e.difficulty,difficulty,'wave '+wave);assert.ok(seen.has(e.difficulty),'unintroduced regular tier on wave '+wave);}
  if(boss){
   const stage=Math.min(3,wave/5),skill=['normal','hard','godlike'][stage-1],name=['NORMAL BOSS','FIERCE BOSS','GODLIKE BOSS'][stage-1];
   assert.equal(boss.difficulty,skill);assert.equal(boss.name,name);assert.equal(boss.shieldCharges,stage);assert.equal(boss.speedStacks,stage>=2?1:0);assert.equal(boss.power,['homing','cannon','laser','homing'][wave/5-1]);
   s.updateObjectiveHUD();assert.ok(s.$('objectiveStatus').textContent.endsWith(name));seen.add(skill);
  }
 }
 assert.deepEqual([...seen],['easy','normal','hard','godlike']);
});


test('each local Survival wave refreshes the location guide when its squad respawns',()=>{
 const s=boot();assert.equal(s.spawnGuideUntil,1.6);
 s.fxTime=20;clearWave(s);s.stepLocalSurvival(4);assert.equal(s.localObjectives.survival.wave,2);assert.equal(s.spawnGuideUntil,21.6);
});

test('a lost Survival boss wave retries on the same maze with the prior-wave score and statistics',()=>{
 const s=boot({target:15}),maze=s.grid;
 for(let wave=1;wave<5;wave++){s.localMatchStats.rows[0].eliminations+=2;s.localMatchStats.duration+=12;clearWave(s);s.stepLocalSurvival(4);}
 const earned=s.localMatchStats.rows[0].eliminations,duration=s.localMatchStats.duration,roster=s.localRoom.players,boss=s.tanks.find(t=>t.survivalBoss);
 s.localMatchStats.rows[0].eliminations+=3;s.localMatchStats.rows[0].deaths++;s.localMatchStats.duration+=23;boss.shieldCharges=0;boss.power=null;s.endLocalSurvival(false);
 const report=s.localMatchReport;assert.equal(report.survival.wave,5);s.bullets=[{}];s.particles=[{}];s.rings=[{}];s.traces=[{}];s.shake=.2;
 assert.equal(s.restartLocalSurvivalWave(),true);assert.equal(s.phase,'countdown');assert.equal(s.phaseTime,2.6);assert.equal(s.roundClock,75);assert.equal(s.grid,maze);assert.equal(s.localRoom.players,roster);
 assert.equal(s.survivalState().wave,5);assert.equal(s.survivalState().wavesCleared,4);assert.equal(s.survivalState().status,'wave');assert.deepEqual(Array.from(s.scores.slice(0,2)),[4,4]);
 assert.equal(s.localMatchReport,null);assert.equal(s.localMatchResult,null);assert.equal(s.localMatchStats.rows[0].eliminations,earned);assert.equal(s.localMatchStats.rows[0].deaths,0);assert.equal(s.localMatchStats.duration,duration);
 const fresh=s.tanks.find(t=>t.survivalBoss);assert.notEqual(fresh,boss);assert.equal(fresh.name,'NORMAL BOSS');assert.equal(fresh.difficulty,'normal');assert.equal(fresh.shieldCharges,1);assert.equal(fresh.power,'homing');
 assert.equal(s.tanks.every(t=>t.alive),true);assert.equal(s.bullets.length+s.traces.length+s.particles.length+s.rings.length,0);assert.equal(s.shake,0);assert.equal(report.players[0].eliminations,earned+3,'old result stays frozen');
});
test('repeated failed attempts cannot farm statistics or advance the Survival wave',()=>{
 const s=boot({target:2});clearWave(s);s.stepLocalSurvival(4);
 for(let attempt=0;attempt<3;attempt++){
  s.phase='playing';s.localMatchStats.rows[0].eliminations=7;s.localMatchStats.rows[0].deaths=2;s.localMatchStats.duration=18;s.endLocalSurvival(false);
  assert.equal(s.restartLocalSurvivalWave(),true);assert.equal(s.survivalState().wave,2);assert.equal(s.localMatchStats.duration,0);assert.equal(s.localMatchStats.rows[0].eliminations,0);assert.equal(s.localMatchStats.rows[0].deaths,0);
 }
 s.phase='playing';s.localMatchStats.rows[0].eliminations=2;s.localMatchStats.duration=5;clearWave(s);assert.equal(s.localMatchReport.survival.status,'won');assert.equal(s.localMatchReport.players[0].eliminations,2);assert.equal(s.localMatchReport.duration,5);assert.equal(s.restartLocalSurvivalWave(),false);
});
test('paused Survival retries reset the whole squad and exclude departed pilots',()=>{
 const s=boot();s.localRoom.players[0].spectating=true;s.localRoom.self=0;s.localRoom.players[1].kind='bot';s.tanks[1].human=false;s.tanks[1].power='rapid';s.tanks[1].powerTime=9;s.tanks[1].machineRounds=4;
 s.phase='paused';s.pausedFrom='playing';s.roundClock=8;assert.equal(s.restartLocalSurvivalWave(),true);
 assert.equal(s.phase,'countdown');assert.equal(s.roundClock,75);assert.equal(s.tanks.filter(t=>!t.survivalEnemy).length,1);assert.equal(s.tanks.find(t=>!t.survivalEnemy).power,null);assert.equal(s.tanks.find(t=>!t.survivalEnemy).machineRounds,0);
 assert.equal(s.localMatchStats.rows.length,2,'earlier participant remains in report');assert.equal(s.localMatchStats.members.get(s.localRoom.players[1]),s.tanks.find(t=>!t.survivalEnemy).statsRow);
});
test('Survival restart eligibility rejects breaks, empty squads and stale lobby or mode state',()=>{
 const s=boot();assert.equal(s.canRestartSurvivalWave(),true);clearWave(s);assert.equal(s.restartLocalSurvivalWave(),false);s.stepLocalSurvival(4);s.endLocalSurvival(false);assert.equal(s.canRestartSurvivalWave(),true);
 s.phase='menu';assert.equal(s.canRestartSurvivalWave(),false);s.phase='matchOver';s.currentRules().mode='ctf';assert.equal(s.canRestartSurvivalWave(),false);s.currentRules().mode='survival';s.localRoom.players.forEach(p=>p.spectating=true);assert.equal(s.canRestartSurvivalWave(),false);
});

test('editing a finished Survival setup invalidates retry while preserving its frozen results',()=>{
 for(const edit of ['map','mode','time','roster']){
  const s=boot();s.endLocalSurvival(false);const report=s.localMatchReport;
  Object.assign(s,{validateRoomRules:r=>r,activeTeamCount:()=>1,normalizeRoomTeams(){},persistLocalRoomRules(){},renderOnlineRoom(){},resetTanks(){},makeMaze(){s.grid=[];}});
  vm.runInContext(declaration('resetPreviewIfLobby')+'\n'+declaration('setLocalRules'),s);
  if(edit==='roster'){s.localRoom.players[0]={...s.localRoom.players[0],member:999};s.resetPreviewIfLobby();}
  else s.setLocalRules({...s.currentRules(),...(edit==='map'?{mapSize:'huge'}:edit==='mode'?{mode:'ctf'}:{timeLimit:90})});
  assert.equal(s.localObjectives,null,edit);assert.equal(s.localSurvivalCheckpoint,null,edit);assert.equal(s.restartLocalSurvivalWave(),false,edit);assert.equal(s.localMatchReport,report,edit);assert.equal(report.survival.status,'lost',edit);
 }
});
