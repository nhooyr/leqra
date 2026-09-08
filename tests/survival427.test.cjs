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
 const s={console,mode:'room',phase:'playing',MAX_TANKS:8,RADIUS:17,CELL:84,cols:7,rows:7,W:588,H:588,POWER:Object.fromEntries(weapons.map(w=>[w,{}])),POWER_EFFECT_DURATION:10,MACHINE_FIRING_ROUNDS:180,MAX_SPEED_STACKS:5,SCOPE_DURATION:10,GHOST_DURATION:10,COLORS:['#fff','#f00'],NAMES:[],difficulty:'normal',tanks:[],bullets:[],traces:[],pickups:[],scores:Array(8).fill(0),round:1,roundClock:75,spawnClock:0,goUntil:0,localObjectives:null,firePresses:new Set(),localRoom:{rules,players,self:players[0].id},online:{snapshots:[]},$,document:{createElement:()=>new Element(),querySelectorAll:()=>[],querySelector:()=>new Element()},grid:Array.from({length:49},(_,i)=>({neighbors:[i%7?i-1:-1,i%7<6?i+1:-1,i>=7?i-7:-1,i<42?i+7:-1].filter(n=>n>=0)})),currentRules:()=>rules,center:i=>({x:(i%7+.5)*84,y:(Math.floor(i/7)+.5)*84}),cellAt:(x,y)=>Math.floor(y/84)*7+Math.floor(x/84),distance:(a,b)=>Math.hypot(a.x-b.x,a.y-b.y),rnd:(a,b)=>(a+b)/2,teamColor:(id,team)=>team===1?'#fff':'#f00',teamName:id=>rules.teamNames[id-1],teamKey:p=>'team'+p.team,shieldCount:t=>t.shieldCharges||0,speedCount:t=>t.speedStacks||0,clearInput(){s.inputClears=(s.inputClears||0)+1;},addLog(){},addRing(){},toast(){},pickupInterval:()=>[1,2],seedPickups(){s.seeds=(s.seeds||0)+1;s.pickups.push({type:'shield',life:30});},finishMatch(winner){s.winner=winner;s.finishLocalMatchStats(winner);s.phase='matchOver';},roomData:()=>({phase:s.phase,rules,players:s.localRoom.players.filter(p=>!p.spectating),spectators:s.localRoom.players.filter(p=>p.spectating)}),localPlayerID:()=>s.localRoom.self,localMatchStats:null,localMatchReport:null,localMatchResult:null,localPlayerID:()=>s.localRoom.self,secondaryMember:()=>null,roomMember:id=>s.localRoom.players.find(p=>p.id===id),syncResultActions(){},paintColor:c=>c,renderMatchStats(){},suddenDeath:()=>false};
 vm.createContext(s);
 for(const name of ['powerEffectDuration','newTank','spawnCells','respawnLocalTank','flagSafeSpawn','grantPower','setText','modeLabel','displayScoreTarget','objectiveState','objectiveMode','survivalMode','survivalState','survivalBreak','roomCapacity','survivalSeatLocked','roomStartError','survivalWavePlan','survivalSpawnPoint','initLocalSurvival','startLocalSurvivalWave','prepareLocalSurvivalBreak','endLocalSurvival','stepLocalSurvival','survivalResultState','survivalResultText','beginLocalMatchStats','bindLocalTankStats','finishLocalMatchStats','updateObjectiveHUD','fire','showVictory','matchResultEntries','resultMemberMatches'])vm.runInContext(declaration(name),s);
 s.tanks=players.map((p,i)=>s.newTank(p.id,s.spawnCells()[i]));s.beginLocalMatchStats();for(const t of s.tanks)s.bindLocalTankStats(t);s.initLocalSurvival();return s;
}
function clearWave(s){for(const t of s.tanks)if(t.survivalEnemy)t.alive=false;s.stepLocalSurvival(1/120);}
test('one to four survival squad members allow a solo human start and never become enemies',()=>{
 for(let n=1;n<=4;n++){const s=boot({count:n,ids:[7,2,4,6]});assert.equal(s.roomStartError(),'');assert.equal(s.roomCapacity(),4);assert.equal(s.objectiveMode(),false);assert.equal(s.tanks.length,n+2);assert.equal(s.localRoom.players.length,n);assert.equal(new Set(s.tanks.map(t=>t.id)).size,s.tanks.length);for(const e of s.tanks.filter(t=>t.survivalEnemy)){assert.ok(e.id>=0&&e.id<8);assert.equal(e.human,false);assert.equal(e.team,2);assert.equal(s.localRoom.players.some(p=>p.id===e.id),false);}}
 const s=boot();s.localRoom.players.forEach(p=>p.kind='bot');assert.match(s.roomStartError(),/human/);s.localRoom.players.push(...Array(3).fill({kind:'human',connected:true}));assert.match(s.roomStartError(),/four/);
});
test('wave plan scales to four enemies, alternates boss weapons and respects every enabled selection',()=>{
 const s=boot();for(let wave=1;wave<=20;wave++){const p=s.survivalWavePlan(wave);assert.equal(p.count,Math.min(4,2+Math.floor((wave-1)/2)));assert.equal(p.boss,wave%5===0);assert.equal(p.difficulty,wave<=2?'easy':wave<=4?'normal':'hard');}
 assert.deepEqual([5,10,15,20].map(w=>s.survivalWavePlan(w).weapon),['homing','cannon','laser','homing']);
 s.currentRules().weapons=['homing','laser'];assert.equal(s.survivalWavePlan(10).weapon,'laser');s.currentRules().pickupRate='off';assert.equal(s.survivalWavePlan(10).weapon,null);
});
test('wave clear awards every squad member once, keeps the maze, clears hazards and revives after four seconds',()=>{
 const s=boot(),grid=s.grid,players=s.localRoom.players;s.tanks[0].alive=false;s.tanks[1].power='cannon';s.tanks[1].powerTime=6;s.bullets=[{}];s.pickups=[{type:'shield',life:4}];clearWave(s);
 assert.equal(s.survivalState().status,'break');assert.equal(s.tanks[0].alive,false);assert.equal(s.bullets.length,0);assert.equal(s.pickups.length,0);assert.deepEqual(Array.from(s.scores.slice(0,2)),[1,1]);assert.equal(s.localRoom.players,players);s.stepLocalSurvival(3.9);assert.equal(s.survivalState().wave,1);s.stepLocalSurvival(.1);
 assert.equal(s.survivalState().wave,2);assert.equal(s.survivalState().status,'wave');assert.equal(s.grid,grid);assert.equal(s.roundClock,75);assert.equal(s.tanks.filter(t=>!t.survivalEnemy).every(t=>t.alive&&t.power===null),true);assert.equal(s.seeds,1);assert.ok(s.inputClears>=3);
});
test('fifth-wave boss has Godlike skill and only enabled gear, with no extra room participant',()=>{
 for(const [pickupRate,weapons,charges,speed,weapon]of[['superfast',['shield','speed','homing'],3,1,'homing'],['superfast',['cannon'],0,0,'cannon'],['off',['shield','speed','homing'],0,0,null]]){
  const s=boot({pickupRate,weapons});s.localObjectives.survival.wave=4;s.startLocalSurvivalWave();const boss=s.tanks.find(t=>t.survivalBoss);assert.equal(boss.name,'GODLIKE BOSS');assert.equal(boss.difficulty,'godlike');assert.equal(boss.shieldCharges,charges);assert.equal(boss.speedStacks,speed);assert.equal(boss.power,weapon);assert.equal(s.localRoom.players.length,2);assert.equal(s.tanks.filter(t=>t.survivalEnemy).length,4);
 }
});
test('squad wipes and timeout lose the run, including simultaneous final-enemy destruction',()=>{
 for(const reason of ['wipe','timeout','mutual','no-human']){const s=boot();if(reason==='timeout')s.roundClock=0;else if(reason==='no-human')s.localRoom.players[0].spectating=true;else for(const t of s.tanks)if(reason==='mutual'||!t.survivalEnemy)t.alive=false;s.stepLocalSurvival(1/120);assert.equal(s.phase,'matchOver',reason);assert.equal(s.winner,-1);assert.equal(s.survivalState().status,'lost');assert.equal(s.survivalState().wavesCleared,0);}
});
test('final wave wins without a new maze or another break and freezes squad-only statistics',()=>{
 const s=boot({target:2});clearWave(s);s.stepLocalSurvival(4);clearWave(s);assert.equal(s.phase,'matchOver');assert.equal(s.survivalState().status,'won');assert.equal(s.survivalState().wavesCleared,2);assert.equal(s.localMatchReport.players.length,2);assert.ok(s.localMatchReport.players.every(p=>p.winner&&p.score===2));assert.equal(s.localMatchReport.survival.status,'won');s.localObjectives.survival.wave=99;assert.equal(s.localMatchReport.survival.wave,2);
});
test('survival HUD explains enemies, bosses and squad returns instead of Hill or respawn timers',()=>{
 const s=boot();s.updateObjectiveHUD();assert.equal(s.$('objectiveModeLabel').textContent,'WAVE 1 / 10');assert.equal(s.$('objectiveStatus').textContent,'2 ENEMIES LEFT');s.survivalState().boss=true;s.updateObjectiveHUD();assert.match(s.$('objectiveStatus').textContent,/GODLIKE BOSS/);clearWave(s);s.updateObjectiveHUD();assert.equal(s.$('objectiveStatus').textContent,'SQUAD RETURNS IN 4s');assert.equal(s.$('clock').textContent,'4s');
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
 const s=boot();s.cols=14;s.rows=12;s.localObjectives.survival.wave=4;s.startLocalSurvivalWave();
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
