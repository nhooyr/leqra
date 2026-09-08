'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(process.env.LEQRA_LAYOUT_SOURCE||path.join(__dirname,'../web/game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function element(){const classes=new Set(),styles=new Map();return{hidden:false,textContent:'',innerHTML:'',dataset:{},attributes:{},style:{getPropertyValue:k=>styles.get(k),setProperty:(k,v)=>styles.set(k,v)},setAttribute(k,v){this.attributes[k]=v;},classList:{toggle(k,v){if(v)classes.add(k);else classes.delete(k);},contains:k=>classes.has(k)}};}
function boot({p2=false,spectating=false}={}){
 const nodes=new Map(),$=id=>{if(!nodes.has(id))nodes.set(id,element());return nodes.get(id);},body=element(),noop=()=>{};
 const primary={id:0,name:'PILOT',kind:'human',color:'#f80',team:0},secondary={id:3,name:'LOCAL P2',kind:'local',owner:0,color:'#08f',team:0};
 const room={players:[...(!spectating?[primary]:[]),...(p2?[secondary]:[])],spectators:spectating?[primary]:[],rules:{mode:'elimination'},phase:'lobby'};
 const s={mode:'online',phase:'onlineLobby',round:1,phaseTime:2.6,goUntil:0,bullets:[],tanks:[],COLORS:['#f80','#08f'],online:{roomData:room,snapshots:[{generation:0,tanks:[],tankMap:new Map()}]},$: $,document:{body},performance:{now:()=>1000},POWER:{shield:{color:'#0ff'}},pilotFeedback:[{},{}],
  roomData:()=>room,localPlayerID:()=>0,secondaryID:()=>room.players.find(p=>p.kind==='local')?.id,secondaryMember:()=>[...room.players,...room.spectators].find(p=>p.kind==='local'),paintColor:c=>c,powerCapacity:()=>5,activeAmmo:()=>0,ownedGrenades:()=>[],shieldCount:t=>t.shieldCharges||0,speedCount:t=>t.speedStacks||0,
  syncPauseButton:noop,renderLineup:noop,survivalBreak:()=>false,survivalMode:()=>false,survivalBossPreview:()=>null,suddenDeath:()=>false,modeInstructions:()=>'',getCountdownTip:()=> 'Get ready.',tone:noop,onlineHUD:noop,updateObjectiveHUD:noop,updateCombatFeedback:noop,syncSpectatingHUD:noop};
 vm.createContext(s);for(const name of ['setText','setStyle','pilotProjectileState','applyOnlineTankEffects','liveFeedbackTank','pilotLoadoutTank','renderPilotLoadout','updateHUD'])vm.runInContext(declaration(name),s);
 function snapshot(phase,bodies){s.phase=phase;room.phase=phase==='onlineLobby'?'lobby':phase;s.online.snapshots=[{generation:1,received:1000,tanks:bodies,tankMap:new Map(bodies.map(t=>[t.id,t]))}];s.updateHUD(true);}
 return{s,$,room,primary,secondary,body,snapshot};
}
test('assigned online ammo panels retain their layout through empty lobby, GO, live play and END MATCH snapshots',()=>{
 for(const p2 of [false,true]){
  const b=boot({p2}),{s,$,primary,secondary}=b,signature=()=>[$('pilotLoadout1').hidden,$('pilotLoadout2').hidden,b.body.classList.contains('two-local-pilots')];
  s.updateHUD(true);const lobby=signature();assert.deepEqual(lobby,[false,!p2,p2]);assert.equal(s.tanks.length,0,'lobby contains no simulated bodies');
  const bodies=[{...primary,alive:true,power:null},...(p2?[{...secondary,alive:true,power:null}]:[])];
  b.snapshot('countdown',bodies);assert.deepEqual(signature(),lobby,'GO does not reveal a new-sized ammo area');
  b.snapshot('playing',bodies.map(t=>({...t,power:'laser',powerTime:9,charges:2})));assert.deepEqual(signature(),lobby);
  s.tanks=bodies;b.snapshot('onlineLobby',[]);assert.deepEqual(signature(),lobby,'ending the match does not collapse assigned panels');
  assert.equal($('weaponLabel').textContent,'TANK DOWN','old rendered equipment cannot leak into the empty lobby snapshot');
 }
});
test('online HUD uses the arriving authoritative tank before rendered bodies catch up',()=>{
 const b=boot({p2:true}),{s,$,primary,secondary}=b;s.tanks=[{...primary,alive:false,power:null},{...secondary,alive:false,power:null}];
 s.POWER.laser={short:'LASER',color:'#f0f'};b.snapshot('countdown',[{...primary,alive:true,power:'laser',powerTime:10,charges:3},{...secondary,alive:true,power:null}]);
 assert.equal($('weaponLabel').textContent,'LASER ×3 · 10s');assert.equal($('weaponLabel2').textContent,'STANDARD');assert.equal($('pilotLoadout2').hidden,false);
});
test('spectator and local P2 assignments define HUD presence without inventing controlled tanks',()=>{
 const b=boot({p2:true,spectating:true}),{s,$}=b;s.updateHUD(true);assert.equal($('pilotLoadout1').hidden,true);assert.equal($('pilotLoadout2').hidden,false);assert.equal(b.body.classList.contains('two-local-pilots'),true);
 b.room.players=[];s.updateHUD(true);assert.equal($('pilotLoadout1').hidden,true);assert.equal($('pilotLoadout2').hidden,true);assert.equal(b.body.classList.contains('two-local-pilots'),false);
 s.mode='room';const local={id:0,alive:true};s.tanks=[local];assert.equal(s.pilotLoadoutTank(0),local,'offline tanks retain their live simulation source');
});

// A spectator keeps their configured cockpit slot; only their content disappears.
test('P2 spectating preserves the two-pilot cockpit through lobby, countdown, play, pause and results',()=>{
 for(const mode of ['room','online'])for(const phase of ['menu','onlineLobby','countdown','playing','paused','roundOver','matchOver']){
  const b=boot({p2:true}),{s,secondary}=b;s.mode=mode;s.phase=phase;
  s.pendingMatchPresentation=null;s.roundWinner=-1;s.roundClock=75;s.scores=[];
  for(const primaryWatching of [false,true]){
   b.room.players=primaryWatching?[secondary]:[b.primary,secondary];b.room.spectators=primaryWatching?[{...b.primary,spectating:true}]:[];
   s.tanks=b.room.players.map(p=>({...p,alive:true,power:null}));s.updateHUD(true);
   assert.equal(b.body.classList.contains('two-local-pilots'),true);
   b.room.players=b.room.players.filter(p=>p!==secondary);b.room.spectators.push({...secondary,spectating:true});s.tanks=s.tanks.filter(t=>t.id!==secondary.id);s.updateHUD(true);
   assert.equal(b.$('pilotLoadout2').hidden,true);assert.equal(b.body.classList.contains('two-local-pilots'),true,mode+' '+phase+' must retain P2 layout when spectating');
   assert.equal(b.$('localLoadouts').classList.contains('two-pilots'),true);
  }
 }
});
