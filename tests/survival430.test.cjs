'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=readFileSync(path.join(__dirname,'../web/game.js'),'utf8');
const fixtures=JSON.parse(readFileSync(path.join(__dirname,'survival-boss-fixtures.json'),'utf8'));
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot(){
 const elements=new Map(),$=id=>{if(!elements.has(id)){const classes=new Set();elements.set(id,{hidden:false,_text:'',get textContent(){return this._text;},set textContent(value){this._text=String(value);},style:{},classes,classList:{toggle(name,on){if(on)classes.add(name);else classes.delete(name);}}});}return elements.get(id);};
 const rules={mode:'survival',pickupRate:'normal',weapons:['shield','speed','homing','cannon','laser']};
 const s={$,mode:'room',phase:'playing',round:5,phaseTime:3,goUntil:0,COLORS:['#fff'],localRoom:{rules},online:{roomData:{rules},snapshots:[]},localObjectives:{mode:'survival',survival:{wave:4,waveTarget:10,status:'break',breakTime:2}},performance:{now:()=>100},paintColor:c=>c,suddenDeath:()=>false,modeInstructions:()=>'',tone(){}};
 vm.createContext(s);
 for(const name of ['botLevelName','setText','currentRules','objectiveState','survivalState','survivalBreak','survivalMode','survivalBossName','survivalWavePlan','survivalBossPreview'])vm.runInContext(declaration(name),s);
 // Execute the production announcer section, independently of unrelated roster
 // and control widgets. This includes its phase gates and stale-preview reset.
 const hud=declaration('updateHUD'),start=hud.indexOf(" const announce=$('announcer')"),end=hud.indexOf(" if(mode==='online')onlineHUD();",start);
 assert.ok(start>=0&&end>start);vm.runInContext('function updateAnnouncer(){\n'+hud.slice(start,end)+'\n}',s);
 return s;
}
test('next-boss gear matches fixtures also checked against authoritative Go grants',()=>{
 assert.ok(fixtures.length>0);
 for(const f of fixtures){
  const s=boot();Object.assign(s.currentRules(),{pickupRate:f.pickupRate,weapons:f.weapons});Object.assign(s.survivalState(),{wave:f.wave-1,waveTarget:20});
  const plan=s.survivalWavePlan(f.wave),preview=s.survivalBossPreview();
  assert.equal(plan.bossDifficulty,f.difficulty,f.name);assert.equal(plan.bossName,f.bossName,f.name);assert.equal(preview.difficulty,f.difficulty,f.name);assert.equal(preview.name,f.bossName,f.name);assert.equal(plan.shieldCharges,f.shieldCharges,f.name);assert.equal(plan.speedStacks,f.speedStacks,f.name);assert.equal(plan.weapon||'',f.weapon,f.name);
  const gear=[];if(f.shieldCharges)gear.push(f.shieldCharges+' shield charge'+(f.shieldCharges===1?'':'s'));if(f.speedStacks)gear.push('Speed boost');gear.push({homing:'Homing missiles',cannon:'Cannon',laser:'Laser'}[f.weapon]||'Standard shells');
  assert.equal(preview.wave,f.wave,f.name);assert.equal(preview.equipment,gear.join(' · '),f.name);
 }
});
test('boss preview uses the existing two-second countdown without changing wave state',()=>{
 const s=boot(),state=s.survivalState(),before=JSON.stringify(state);s.updateAnnouncer();
 assert.equal(s.$('announcer').hidden,false);assert.equal(s.$('announcer').classes.has('boss-preview'),true);
 assert.equal(s.$('announceTop').textContent,'NEXT: WAVE 5 · NORMAL BOSS');assert.equal(s.$('announceMain').textContent,'2');
 assert.equal(s.$('announceSub').textContent,'Equipment: 1 shield charge · Homing missiles\nSquad returns together.');assert.equal(JSON.stringify(state),before);
 state.breakTime=1.2;s.updateAnnouncer();assert.equal(s.$('announceMain').textContent,'2');assert.equal(state.breakTime,1.2);
});
test('ordinary breaks retain their clear message and never show a boss equipment preview',()=>{
 const s=boot();s.updateAnnouncer();s.survivalState().wave=5;s.updateAnnouncer();
 assert.equal(s.survivalBossPreview(),null);assert.equal(s.$('announcer').classes.has('boss-preview'),false);
 assert.equal(s.$('announceTop').textContent,'WAVE 5 CLEARED');assert.equal(s.$('announceSub').textContent,'Squad returns for the next wave.');
});
test('boss preview hides during pause, resumes with the same timer, and disappears at wave start',()=>{
 const s=boot();s.updateAnnouncer();s.phase='paused';s.updateAnnouncer();assert.equal(s.$('announcer').hidden,true);assert.equal(s.$('announcer').classes.has('boss-preview'),false);assert.equal(s.survivalState().breakTime,2);
 s.phase='playing';s.updateAnnouncer();assert.equal(s.$('announcer').hidden,false);assert.equal(s.$('announceMain').textContent,'2');
 Object.assign(s.survivalState(),{wave:5,status:'wave',breakTime:0});s.updateAnnouncer();assert.equal(s.survivalBossPreview(),null);assert.equal(s.$('announcer').hidden,true);assert.equal(s.$('announcer').classes.has('boss-preview'),false);
});
test('finished targets, ended runs, and other modes cannot announce another survival boss',()=>{
 const s=boot();s.survivalState().waveTarget=4;assert.equal(s.survivalBossPreview(),null);
 s.survivalState().waveTarget=10;for(const status of ['wave','won','lost']){s.survivalState().status=status;assert.equal(s.survivalBossPreview(),null);}
 s.survivalState().status='break';for(const mode of ['elimination','ctf','koth']){s.currentRules().mode=mode;assert.equal(s.survivalBossPreview(),null);}
 s.currentRules().mode='survival';for(const phase of ['menu','matchOver']){s.phase=phase;s.updateAnnouncer();assert.equal(s.$('announcer').hidden,true);assert.equal(s.$('announcer').classes.has('boss-preview'),false);}
});
test('online previews use authoritative snapshot waves and room rules, including disabled pickups',()=>{
 const s=boot();s.mode='online';s.online.snapshots=[{objectives:{mode:'survival',survival:{wave:9,waveTarget:20,status:'break',breakTime:2.2}}}];s.online.roomData.rules={mode:'survival',pickupRate:'off',weapons:['shield','speed','homing','cannon','laser']};s.updateAnnouncer();
 assert.equal(s.$('announceTop').textContent,'NEXT: WAVE 10 · FIERCE BOSS');assert.equal(s.$('announceMain').textContent,'3');assert.equal(s.$('announceSub').textContent,'Equipment: Standard shells\nSquad returns together.');
 s.online.roomData.rules.pickupRate='normal';s.online.roomData.rules.weapons=['shield','laser'];s.updateAnnouncer();assert.equal(s.$('announceSub').textContent,'Equipment: 2 shield charges · Laser\nSquad returns together.');
});
