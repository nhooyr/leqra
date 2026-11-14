'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm');
const {readFileSync}=require('node:fs'),{assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8');
function declaration(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\n',start),line=source.slice(start,end);return line.endsWith('}')?line:source.slice(start,source.indexOf('\n}',end)+2);}
function boot(){
 const noop=()=>{},s={Net:require(assetPath('netcode.js')),mode:'room',time:0,bulletId:0,bullets:[],tanks:[],traces:[],MACHINE_CAPACITY:96,LASER_COOLDOWN:.85,POWER:{laser:{color:'#fff'}},survivalBreak:()=>false,muzzleBlocked:()=>false,burst:noop,shotSound:noop,
  projectileSpec:power=>({kind:power||'regular',cooldown:.34}),muzzleProjectile:(t,a)=>({owner:t.id,kind:t.power||'regular'}),activeAmmo:()=>0,
  laserTrace:()=>({x:100,y:100,endX:200,endY:100,points:[{x:100,y:100},{x:200,y:100}],target:null}),laserEffect:noop,detonate:b=>b.dead=true,
  canDamage:(id,t)=>t.id!==id,recordLocalDeath:noop,objectiveMode:()=>false,reduceMotion:true,addRing:noop,boom:noop,addLog:noop,updateHUD:noop};
 vm.createContext(s);for(const name of ['powerCapacity','recycleStarmanProjectiles','fire','fireLaser','ownedGrenades','detonateOwned','weaponControl','hurt','netTank'])vm.runInContext(declaration(name),s);return s;
}
function tank(power=null){return{id:0,name:'PILOT',x:100,y:100,angle:0,alive:true,human:true,power,powerTime:10,charges:3,machineRounds:180,cooldown:0,recoil:0,spawnProtected:true,invulnerable:.75};}

test('fixed-maze spawn protection blocks every weapon without ammo, recoil or cooldown changes',()=>{
 for(const power of [null,'rapid','scatter','homing','grenade','laser','cannon']){
  const s=boot(),t=tank(power);s.tanks=[t];const before=JSON.stringify(t);
  assert.equal(s.fire(t),false,power);if(power==='laser')assert.equal(s.fireLaser(t),false);
  s.weaponControl(t,true,true);assert.equal(JSON.stringify(t),before,power);assert.equal(s.bullets.length,0);
  t.invulnerable=0;assert.equal(s.fire(t),true,power+' can fire after protection expires');
 }
});

test('protected fixed-maze pilots cannot detonate old grenades or predict online attacks',()=>{
 const s=boot(),t=tank();s.bullets=[{owner:0,kind:'grenade'}];
 assert.equal(s.detonateOwned(t),false);s.weaponControl(t,true,true);assert.equal(s.bullets[0].dead,undefined);
 t.spawnProtected=false;assert.equal(s.detonateOwned(t),true);
 const calls=[];s.online={id:0,connected:true,shots:{tryFire:(...args)=>calls.push(args)},snapshots:[{received:1000,tankMap:new Map([[0,tank()]])}],predictor:{state:{}}};s.phase='playing';
 vm.runInContext(declaration('previewOnlineFire'),s);s.previewOnlineFire(false,{fire:true},1100);
 assert.equal(calls.length,1);assert.equal(calls[0][3].active,false,'no locally predicted shot or firing sound during protection');
});

test('fixed-maze Starman contact defeats spawn protection and shields while other defenses still apply',()=>{
 for(const [spawnProtected,kind,invulnerable,shield,alive]of [[true,'starman',1,10,false],[true,'regular',1,0,true],[false,'starman',.35,0,true]]){
  const s=boot(),target={...tank(),id:1,spawnProtected,invulnerable,shield};s.tanks=[tank(),target];
  s.hurt(target,{owner:0,kind});assert.equal(target.alive,alive);
 }
 const s=boot(),target={...tank(),id:1,shield:10};s.canDamage=()=>false;s.hurt(target,{owner:0,kind:'starman'});assert.equal(target.alive,true,'friendly-fire rules still protect allies');
});

test('authoritative spawn flags keep shield-hit immunity distinct on the fixed-maze client',()=>{
 const s=boot();assert.equal(s.netTank({...tank(),spawnProtected:false}).spawnProtected,false);
 assert.equal(s.netTank(tank()).spawnProtected,true);
});

test('spawn protection readiness is shared by fixed-maze and Infinity HUDs',()=>{
 const s=boot(),nodes=new Map(),$=id=>{if(!nodes.has(id))nodes.set(id,{hidden:false,attributes:{},style:{},classList:{toggle(){}},textContent:''});return nodes.get(id);};
 Object.assign(s,{$,combatPrefs:{visual:true},updateMachineBudget(){},setText:(id,v)=>$(id).textContent=v,setStyle:(e,k,v)=>e.style[k]=v,setAttr:(e,k,v)=>e.attributes[k]=v,clamp:(v,lo,hi)=>Math.max(lo,Math.min(v,hi)),cooldownDuration:()=>.34});
 vm.runInContext(declaration('renderPilotReadiness'),s);
 for(const prefix of ['', 'infinite']){
  s.renderPilotReadiness(tank(),1,{locked:false,grenades:1,ammo:0},false,null,id=>prefix+id);
  assert.equal($(prefix+'cooldownText1').textContent,'SPAWN PROTECTION');assert.equal($(prefix+'fireLabel').textContent,'WAIT');assert.equal($(prefix+'fireBtn').style['--ready'],'0.000');
  s.renderPilotReadiness({...tank(),invulnerable:0},1,{locked:false,grenades:0,ammo:0},false,null,id=>prefix+id);
  assert.equal($(prefix+'cooldownText1').textContent,'READY');
 }
});
