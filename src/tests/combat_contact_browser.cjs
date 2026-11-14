'use strict';
// Optional real Chromium/Canvas regression. Never point this at a live service.
// node src/tests/combat_contact_browser.cjs http://127.0.0.1:18109 --disposable
// --quick limits the matrix while developing; omit it for the complete run.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict');
const {chromium}=require('playwright'),{assetPath}=require('./web_assets.cjs');
const args=process.argv.slice(2),address=args.find(arg=>/^https?:/.test(arg));
assert.ok(address&&args.includes('--disposable'),'Supply a disposable loopback backend and --disposable.');
const target=new URL(address);assert.ok(['127.0.0.1','localhost','[::1]'].includes(target.hostname)&&target.pathname==='/'&&!target.search&&!target.hash&&!target.username&&!target.password,'Only an uncredentialed loopback origin is allowed.');
const root=path.resolve(__dirname,'../..'),web=path.join(root,'src/web'),origin=target.origin;
const output=process.env.LEQRA_BROWSER_OUTPUT?path.resolve(process.env.LEQRA_BROWSER_OUTPUT):fs.mkdtempSync(path.join(os.tmpdir(),'leqra-combat-contact-'));
fs.mkdirSync(output,{recursive:true});
const quick=args.includes('--quick'),uiOnly=args.includes('--ui-only'),profileFilter=args.find(arg=>arg.startsWith('--profile='))?.slice(10),arenaFilter=args.find(arg=>arg.startsWith('--arena='))?.slice(8);
const profiles=[{name:'desktop',width:1280,height:900,mobile:false},{name:'portrait',width:390,height:844,mobile:true},{name:'landscape',width:844,height:390,mobile:true}].filter(p=>!profileFilter||p.name===profileFilter);
const ballistics=['regular','rapid','scatter','homing','grenade','cannon'],weapons=[...ballistics,'laser','starman'];
const records=[],errors=[],checks=[];const check=(ok,label)=>{assert.ok(ok,label);checks.push(label);};
const commonHooks=String.raw`
const contactTank=drawTank;drawTank=function(t,...args){const p=__combatProbe,c=ctx,m=c.getTransform(),at=p.pixel(c,m,t.x,t.y);const result=contactTank(t,...args);if(p.frame){p.frame.tanks.push({id:t.id,x:t.x,y:t.y,r:t.r||17,alive:!!t.alive,hp:t.hp??(t.alive?1:0),shield:t.shield||0,shieldCharges:t.shieldCharges||0,life:t.spawnSerial||0,painted:at!==p.pixel(c,m,t.x,t.y)});}return result;};
const contactBullets=drawBullets;drawBullets=function(items,c=ctx,...args){const p=__combatProbe,m=c.getTransform(),before=items.map(b=>p.pixel(c,m,b.x,b.y));const result=contactBullets(items,c,...args);if(p.frame)for(let i=0;i<items.length;i++){const b=items[i];p.frame.bullets.push({id:b.id,x:b.x,y:b.y,r:b.r,kind:b.kind||'regular',flight:!!b.flight,painted:before[i]!==p.pixel(c,m,b.x,b.y)});}return result;};
const contactLasers=drawLasers;drawLasers=function(...args){if(__combatProbe.frame)__combatProbe.frame.beams.push(...traces.map(t=>({points:t.points.map(p=>({x:p.x,y:p.y}))})));return contactLasers(...args);};
const contactOnlineEffect=onlineEffect;onlineEffect=function(e,...args){if(__combatProbe.frame)__combatProbe.frame.effects.push({id:e.id,kind:e.type,target:e.contact?.target??e.player});return contactOnlineEffect(e,...args);};
const contactBoom=boom;boom=function(...args){__combatProbe.frame?.sounds.push('hit');return contactBoom(...args);};
const contactShieldSound=shieldSound;shieldSound=function(...args){__combatProbe.frame?.sounds.push('shield');return contactShieldSound(...args);};
const contactGrenadeBoom=grenadeBoom;grenadeBoom=function(...args){__combatProbe.frame?.sounds.push('blast');return contactGrenadeBoom(...args);};
const contactTankImpact=projectileTankImpact;projectileTankImpact=function(b,target,...args){if(target)__combatProbe.terminal={x:b.x,y:b.y,r:b.r,id:b.id};return contactTankImpact(b,target,...args);};
__combatProbe.fixedSetup=function(){
 window.leqraInfinity?.close();mode='room';localRoom.rules=validateRoomRules({...defaultRoomRules(),infinity:false,mode:'elimination',teamMode:'ffa',timeLimit:600,scoreTarget:20});
 localRoom.players=[0,1].map(id=>({id,member:id+1,kind:'human',name:id?'Target':'Probe',team:0,colorIndex:id}));startMatch();
 phase='playing';time=1;spawnClock=1e9;accumulator=0;pickups=[];bullets=[];traces=[];particles=[];rings=[];shake=0;fire.flights=new Net.ProjectileFlights();
 __test.setWorld({width:504,height:420,cols:6,rows:5,walls:[]});mapCanvas=null;wallIndex=null;
 for(const t of tanks)Object.assign(t,{x:t.id?250:100,y:210,angle:0,human:true,invulnerable:0,spawnProtected:false,power:null,cooldown:0,spawnSerial:7,shield:0,shieldCharges:0,speedTime:9,speedStacks:5,ghostTime:9});
 this.surface=canvas;this.terminal=null;return tanks;
};
__combatProbe.fixedNetwork=function(spec){
 const initial=this.fixedSetup(),owner=spec.role==='remote'?1:0,victim=1-owner;
 const base=initial.map(t=>({...t,x:t.id===owner?100:250,alive:true,shotSerial:1,spawnSerial:7,vx:0,vy:0,shield:spec.shield&&t.id===victim?9:0,shieldCharges:spec.shield&&t.id===victim?2:0}));
 if(spec.kind==='starman')base.find(t=>t.id===owner).x=216;
 mode='online';online.connected=true;online.id=spec.role==='spectator'?7:0;online.member=1;online.roomData=null;online.spectating=spec.role==='spectator';online.generation=-1;online.eventsInitialized=false;online.lastEvent=0;online.latency=spec.ping;resetOnlineMotion();
 const world={width:504,height:420,cols:6,rows:5,walls:[]},rules={...defaultRoomRules(),infinity:false,mode:'elimination'};
 const packet=(tick,bs,events=[],dead=false,life=7)=>({type:'state',tick,generation:1,world,phase:spec.winning&&dead?'matchOver':'playing',phaseTime:0,round:1,roundClock:75,winner:owner,scores:Array(8).fill(0),tanks:base.filter(t=>!(spec.missing&&dead&&t.id===victim)).map(t=>({...t,spawnSerial:t.id===victim?life:7,x:t.id===victim&&life!==7?360:t.x,alive:t.id!==victim||!dead||spec.shield,shieldCharges:t.id===victim&&dead&&spec.shield?1:t.shieldCharges,invulnerable:t.id===victim&&dead&&spec.shield?.35:0})),bullets:bs,pickups:[],events,rules});
 const r=this.radius(spec.kind),end={x:250-17-r,y:210},start={x:128,y:210},before={x:250,y:210,angle:0,vx:0,vy:0,hp:1,shield:spec.shield?9:0,shieldCharges:spec.shield?2:0,invulnerable:0,spawnProtected:false};
 const flight={id:77,owner,colorIndex:owner,kind:spec.kind,radius:r,startTick:spec.published?102:103,endTick:103.8,points:[{...start,tick:spec.published?102:103},{...end,tick:103.8}]};
 if(spec.equalTick){flight.startTick=flight.endTick=103;for(const point of flight.points)point.tick=103;}
 const contact={projectileId:['laser','starman'].includes(spec.kind)?0:77,kind:spec.kind,tick:spec.equalTick?103:['laser','starman'].includes(spec.kind)?104:103.8,target:victim,spawnSerial:7,before};
 let id=1;const events=[];
 if(spec.kind==='laser')events.push({id:id++,type:'laser',owner,player:owner,tick:104,generation:1,x:128,y:210,endX:end.x,endY:210,color:'#f57cff',points:[start,end]});
 else if(spec.kind!=='starman')events.push({id:id++,type:spec.kind==='grenade'?'blast':['cannon','homing'].includes(spec.kind)?'impact':'projectileFlight',owner,player:-1,tick:104,generation:1,x:end.x,y:210,color:COLORS[owner],flight,shotSerial:1,spawnSerial:7});
 events.push({id:id++,type:spec.shield?'shield':'hit',owner,player:victim,tick:104,generation:1,x:250,y:210,color:COLORS[victim],contact});
 if(spec.baseline){receiveOnlineState(packet(104,[],events,true));}
 else{
  receiveOnlineState(packet(100,[]));this.clock+=1000/30;
  receiveOnlineState(packet(102,spec.published&&contact.projectileId?[{id:77,owner,kind:spec.kind==='regular'?'':spec.kind,r,x:start.x,y:210,vx:100,vy:0,life:2,age:.01,bounces:0,color:COLORS[owner],shotSerial:1,spawnSerial:7}]:[]));
  if(spec.published)this.take(()=>{renderOnlineMotion(1/120,this.clock);render();},false);
  this.clock+=1000/30+spec.ping/2;receiveOnlineState(packet(104,[],events,true));
  if(spec.lifeGuard){this.clock+=1;receiveOnlineState(packet(106,[],events,false,8));}
 }
 const frames=[];for(let i=0;i<42;i++){this.clock+=1000/120;frames.push(this.take(()=>{renderOnlineMotion(1/120,this.clock);render();flushMatchPresentation(this.clock);},spec.capture));}
 return{frames,victim,owner,end,r,authorityDead:!online.snapshots.at(-1).tankMap.get(victim)?.alive,baseline:!!spec.baseline,lifeGuard:!!spec.lifeGuard};
};
__combatProbe.fixedOffline=function(spec){
 const ts=this.fixedSetup(),p=ts[0],target=ts[1];target.x=spec.published?250:134;if(spec.shield){target.shield=9;target.shieldCharges=2;}
 const victim=target.id,r=this.radius(spec.kind);if(spec.kind!=='regular'&&spec.kind!=='starman')grantPower(p,spec.kind);
 const frames=[];this.begin();
 if(spec.kind==='starman'){p.x=target.x-34;p.starmanTime=9;hurt(target,{owner:p.id,kind:'starman'});}else fire(p);
 frames.push(this.take(()=>render(),spec.capture));
 for(let i=0;i<180;i++){this.clock+=1000/120;time+=1/120;updateBullets(1/120);frames.push(this.take(()=>render(),spec.capture));if((!target.alive||spec.shield&&target.shieldCharges===1)&&i>10&&!fire.flights.pendingPresentation)break;}
 return{frames,victim,owner:0,end:this.terminal||{x:target.x-17-r,y:target.y},r:this.terminal?.r??r,authorityDead:!target.alive};
};
__combatProbe.fixedBatch=function(){
 const initial=this.fixedSetup(),base=initial.map(t=>({...t,alive:true,spawnSerial:7,shield:t.id===1?9:0,shieldCharges:t.id===1?1:0}));mode='online';online.connected=true;online.id=0;online.member=1;online.roomData=null;online.spectating=false;online.generation=-1;online.eventsInitialized=false;online.lastEvent=0;resetOnlineMotion();
 const world={width:504,height:420,cols:6,rows:5,walls:[]},packet=(tick,events=[],dead=false)=>({type:'state',tick,generation:1,world,phase:'playing',phaseTime:0,round:1,roundClock:75,winner:-1,scores:Array(8).fill(0),tanks:base.map(t=>({...t,x:dead&&t.id===1?290:t.x,alive:!dead||t.id!==1,shield:dead?0:t.shield,shieldCharges:dead?0:t.shieldCharges})),bullets:[],pickups:[],events,rules:{...defaultRoomRules(),infinity:false}});
 receiveOnlineState(packet(100));this.clock+=1000/30;receiveOnlineState(packet(102));this.clock+=400;
 const before=(x,shield)=>({x,y:210,angle:0,vx:0,vy:0,hp:1,shield:shield?9:0,shieldCharges:shield?1:0,invulnerable:0,spawnProtected:false});
 const flight=(id,x,start,end)=>({id,owner:0,colorIndex:0,kind:'cannon',radius:14,startTick:start,endTick:end,points:[{x:128,y:210,tick:start},{x,y:210,tick:end}]});
 const events=[{id:1,type:'impact',tick:104,generation:1,owner:0,player:-1,x:219,y:210,color:COLORS[0],flight:flight(77,219,99,103.8)},{id:2,type:'shield',tick:104,generation:1,owner:0,player:1,x:250,y:210,color:COLORS[1],contact:{projectileId:77,kind:'cannon',tick:103.8,target:1,spawnSerial:7,before:before(250,true)}},{id:3,type:'impact',tick:126,generation:1,owner:0,player:-1,x:259,y:210,color:COLORS[0],flight:flight(78,259,118.8,125.8)},{id:4,type:'hit',tick:126,generation:1,owner:0,player:1,x:290,y:210,color:COLORS[1],contact:{projectileId:78,kind:'cannon',tick:125.8,target:1,spawnSerial:7,before:before(290,false)}}];
 receiveOnlineState(packet(126,events,true));const frames=[];for(let i=0;i<90;i++){this.clock+=1000/120;frames.push(this.take(()=>{renderOnlineMotion(1/120,this.clock);render();},false));}return frames;
};
__combatProbe.fixedBadges=function(count){
 this.fixedSetup();tanks.length=1;const t=tanks[0];Object.assign(t,{x:250,y:210,power:'rapid',powerTime:9,machineRounds:count,shield:9,shieldCharges:5,speedTime:9,speedStacks:5,ghostTime:9});
 particles=[{x:288,y:240,size:24,color:'#ff00ff',life:1,max:1}];rings=[{x:250,y:210,life:1,maxLife:1,max:40,color:'#f00'}];
 const frame=this.take(()=>render(),true,true);return{frame,icons:frame.ops.filter(o=>o.method==='drawImage'),numbers:frame.ops.filter(o=>['strokeText','fillText'].includes(o.method)&&/^\d+$/.test(o.text))};
};
__combatProbe.fixedTuning=function(){
 this.fixedSetup();tanks.length=1;const t=tanks[0];grantPower(t,'laser');const guide=aimingGuide(t),length=guide.points.slice(1).reduce((v,p,i)=>v+Math.hypot(p.x-guide.points[i].x,p.y-guide.points[i].y),0),frame=this.take(()=>render(),false,true);fire(t);updateHUD(true);updateCombatFeedback(true);const laser={cooldown:t.cooldown,total:t.cooldownTotal,guide:length,expected:4*(W+H)-28,readiness:$('cooldownText1').textContent,guidePainted:frame.ops.some(o=>o.method==='stroke'&&o.dash.join(',')==='3,7')};
 grantPower(t,'cannon');t.cooldown=0;fire(t);updateHUD(true);updateCombatFeedback(true);return{laser,cannon:{cooldown:t.cooldown,total:t.cooldownTotal,life:bullets[0]?.life,readiness:$('cooldownText1').textContent}};
};
`;
const infinityHooks=String.raw`
const contactInfinityTank=drawTank;drawTank=function(t,...args){const p=__combatProbe,m=ctx.getTransform(),before=p.pixel(ctx,m,t.x,t.y),result=contactInfinityTank(t,...args);if(p.frame)p.frame.tanks.push({id:t.id,x:t.x,y:t.y,r:17,alive:t.hp>0,hp:t.hp,shield:t.shield||0,shieldCharges:t.shieldCharges||0,life:t.spawnSerial||0,painted:before!==p.pixel(ctx,m,t.x,t.y)});return result;};
const contactInfinityTrace=drawTrace;drawTrace=function(points,color,width,...args){if(__combatProbe.frame&&width===7)__combatProbe.frame.beams.push({points:points.map(p=>({x:p.x,y:p.y}))});return contactInfinityTrace(points,color,width,...args);};
const contactInfinityEffect=presentEffect;presentEffect=function(w,e,...args){if(__combatProbe.frame)__combatProbe.frame.effects.push({id:e.id,kind:e.kind,target:e.contact?.target});return contactInfinityEffect(w,e,...args);};
const contactInfinityHurt=hurt;hurt=function(w,t,owner,team,name,star=false,color='',projectile=null){if(projectile&&t.hp&&!(t.invulnerable>0))__combatProbe.terminal={x:projectile.x,y:projectile.y,r:projectile.r,id:projectile.id};return contactInfinityHurt(w,t,owner,team,name,star,color,projectile);};
__combatProbe.infinitySetup=function(){
 window.leqraInfinity.close();window.leqraInfinity.start('offline',{name:'Probe',roomRules:{...__test.defaultRoomRules(),infinity:true,infinityRandomBots:false,infinityTarget:0}});
 const w=session;w.maze={wallsNear:()=>[],visitWalls:()=>false,blocked:()=>false};w.mapCache.clear();w.nextBot=w.nextPickup=1e9;w.bullets=[];w.pickups=[];w.time=1;w.flights=new net.ProjectileFlights();w.visualEffects=[];
 const p=w.tanks[0];Object.assign(p,{x:100,y:210,angle:0,spawnSerial:7,spawnProtected:false,invulnerable:0,power:'',powerTime:9,cooldown:0,charges:3,machineRounds:180,speedTime:9,speedStacks:5,ghostTime:9});
 w.tanks=[p,{...p,id:2,name:'Target',bot:false,x:250,power:'',charges:0,score:0,team:0,colorIndex:1}];w.camera.x=175;w.camera.y=210;this.surface=canvas;this.terminal=null;return w;
};
__combatProbe.infinityNetwork=function(spec){
 const w=this.infinitySetup(),owner=spec.role==='remote'?2:1,victim=owner===1?2:1;w.online=true;w.joined=false;w.room={code:'PROBE',token:'synthetic'};socket={readyState:WebSocket.OPEN,bufferedAmount:0,send(){},close(){}};const ws=socket;
 const recv=packet=>receive(ws,{data:JSON.stringify(packet)});recv({type:'welcome',id:spec.role==='spectator'?9:1,seed:37,generation:1,spectating:spec.role==='spectator',following:spec.role==='spectator'?victim:0});w.maze={wallsNear:()=>[],visitWalls:()=>false,blocked:()=>false};
 const base=[1,2].map(id=>({id,name:id===1?'Probe':'Target',hp:1,alive:true,x:id===owner?100:250,y:210,angle:0,vx:0,vy:0,spawnSerial:7,colorIndex:id-1,invulnerable:0,spawnProtected:false,power:'',powerTime:9,speedTime:9,speedStacks:5,ghostTime:9,shield:spec.shield&&id===victim?9:0,shieldCharges:spec.shield&&id===victim?2:0}));if(spec.kind==='starman')base.find(t=>t.id===owner).x=216;
 const packet=(tick,bullets,effects=[],dead=false,life=7)=>({type:'state',tick,tanks:base.filter(t=>!(spec.missing&&dead&&t.id===victim)).map(t=>({...t,spawnSerial:t.id===victim?life:7,x:t.id===victim&&life!==7?360:t.x,hp:t.id!==victim||!dead||spec.shield?1:0,shieldCharges:t.id===victim&&dead&&spec.shield?1:t.shieldCharges,invulnerable:t.id===victim&&dead&&spec.shield?.35:0})),bullets,pickups:[],effects,players:2,leaderboard:[],following:spec.role==='spectator'?victim:0,...(spec.winning&&dead?{result:{id:owner,name:'Winner',score:5}}:{})});
 const r=this.radius(spec.kind),end={x:250-17-r,y:210},start={x:128,y:210},before={x:250,y:210,angle:0,vx:0,vy:0,hp:1,shield:spec.shield?9:0,shieldCharges:spec.shield?2:0,invulnerable:0,spawnProtected:false};
 const flight={id:77,owner,colorIndex:owner-1,kind:spec.kind,radius:r,startTick:spec.published?102:103,endTick:103.8,points:[{...start,tick:spec.published?102:103},{...end,tick:103.8}]};if(spec.equalTick){flight.startTick=flight.endTick=103;for(const point of flight.points)point.tick=103;}const contact={projectileId:['laser','starman'].includes(spec.kind)?0:77,kind:spec.kind,tick:spec.equalTick?103:['laser','starman'].includes(spec.kind)?104:103.8,target:victim,spawnSerial:7,before};
 let id=1;const effects=[];
 if(spec.kind==='laser')effects.push({id:id++,kind:'laser',owner,tick:104,x:128,y:210,points:[start,end]});
 else if(spec.kind!=='starman')effects.push({id:id++,kind:spec.kind==='grenade'?'blast':['cannon','homing'].includes(spec.kind)?'impact':'projectileFlight',owner,tick:104,x:end.x,y:210,flight});
 effects.push({id:id++,kind:spec.shield?'shield':'hit',owner,tick:104,x:250,y:210,contact});
 if(spec.baseline)recv(packet(104,[],effects,true));
 else{recv(packet(100,[]));this.clock+=1000/30;recv(packet(102,spec.published&&contact.projectileId?[{id:77,owner,kind:spec.kind==='regular'?'':spec.kind,colorIndex:owner-1,x:start.x,y:210,vx:100,vy:0,life:2,bounces:0}]:[]));if(spec.published)this.take(()=>draw(w,this.clock,1/120),false);this.clock+=1000/30+spec.ping/2;recv(packet(104,[],effects,true));if(spec.lifeGuard){this.clock+=1;recv(packet(106,[],effects,false,8));}}
 const frames=[];for(let i=0;i<42;i++){this.clock+=1000/120;frames.push(this.take(()=>{draw(w,this.clock,1/120);showResult(w,this.clock);},spec.capture));}
 const value={frames,victim,owner,end,r,authorityDead:!w.tanks.find(t=>t.id===victim)?.hp,baseline:!!spec.baseline,lifeGuard:!!spec.lifeGuard};window.leqraInfinity.close();socket=null;return value;
};
__combatProbe.infinityOffline=function(spec){
 const w=this.infinitySetup(),p=w.tanks[0],target=w.tanks[1];target.x=spec.published?250:134;if(spec.shield){target.shield=9;target.shieldCharges=2;}if(spec.kind!=='regular'&&spec.kind!=='starman')art.grantPower(p,spec.kind,15,8);
 this.begin();if(spec.kind==='starman'){p.x=target.x-34;p.starmanTime=9;hurt(w,target,p.id,p.team,p.name,true);}else fireShot(w,p);
 const frames=[this.take(()=>draw(w,this.clock,0),spec.capture)];
 for(let i=0;i<180;i++){this.clock+=1000/120;offlineStep(w,1/120);frames.push(this.take(()=>draw(w,this.clock,1/120),spec.capture));if((!target.hp||spec.shield&&target.shieldCharges===1)&&i>10&&!w.flights.pendingPresentation)break;}
 const value={frames,victim:target.id,owner:p.id,end:this.terminal||{x:target.x-17-this.radius(spec.kind),y:target.y},r:this.terminal?.r??this.radius(spec.kind),authorityDead:!target.hp};window.leqraInfinity.close();return value;
};
__combatProbe.infinityBadges=function(count){const w=count===180||!this.badgeWorld?this.infinitySetup():this.badgeWorld;this.badgeWorld=w;const t=w.tanks[0];w.tanks=[t];Object.assign(t,{x:175,y:210,power:'rapid',powerTime:9,machineRounds:count,shield:9,shieldCharges:5,speedTime:9,speedStacks:5,ghostTime:9});w.camera.x=175;w.camera.y=210;w.visualEffects=[{kind:'hit',x:200,y:240,end:this.clock+430}];if(count===180)draw(w,this.clock,0);const frame=this.take(()=>draw(w,this.clock,0),true,true);return{frame,icons:frame.ops.filter(o=>o.method==='drawImage'),numbers:frame.ops.filter(o=>['strokeText','fillText'].includes(o.method)&&/^\d+$/.test(o.text))};};
__combatProbe.infinityTuning=function(){const w=this.infinitySetup(),t=w.tanks[0];w.tanks=[t];art.grantPower(t,'laser',15,8);const guide=traceLaser(w,t,true).points,length=guide.slice(1).reduce((v,p,i)=>v+Math.hypot(p.x-guide[i].x,p.y-guide[i].y),0),frame=this.take(()=>draw(w,this.clock,0),false,true);fireShot(w,t);updatePilotLoadout(w,t,w,1,this.clock);const laser={cooldown:t.cooldown,total:t.cooldownTotal,guide:length,expected:36*CELL-28,readiness:byID('infiniteCooldownText1').textContent,guidePainted:frame.ops.some(o=>o.method==='stroke'&&o.dash.join(',')==='3,7')};art.grantPower(t,'cannon',15,8);t.cooldown=0;fireShot(w,t);updatePilotLoadout(w,t,w,1,this.clock);const value={laser,cannon:{cooldown:t.cooldown,total:t.cooldownTotal,life:w.bullets[0]?.life,readiness:byID('infiniteCooldownText1').textContent}};window.leqraInfinity.close();return value;};
`;
function initialize(){
 for(const [key,value]of Object.entries({'introTour.v1':'1',name:'FrameProbe',local2Name:'FrameWing',infinityOnline:'0',infinityOffline:'0',muted:'1'}))localStorage.setItem('leqra.'+key,value);
 window.__combatProbe={clock:1000,frame:null,surface:null,captureOps:false,queue:[],frameIndex:0,
  radius(kind){return kind==='cannon'?14:kind==='grenade'?6:kind==='homing'?5:kind==='rapid'?3.5/3:kind==='laser'?3:kind==='starman'?0:3.5;},
  pixel(c,m,x,y){const px=Math.round(m.a*x+m.c*y+m.e),py=Math.round(m.b*x+m.d*y+m.f);if(px<0||py<0||px>=c.canvas.width||py>=c.canvas.height)return'offscreen';return [...c.getImageData(px,py,1,1).data].join(',');},
  begin(){this.frame={index:this.frameIndex++,at:this.clock,tanks:[],bullets:[],beams:[],effects:[],sounds:[],ops:[]};return this.frame;},
  take(draw,capture=false,ops=false){const frame=this.frame||this.begin();this.captureOps=ops;draw();frame.covered=!!document.querySelector('#infiniteResult[open],#victoryDialog[open]')||document.getElementById('matchScreen')?.hidden===false;if(capture)frame.png=this.surface.toDataURL('image/png');this.frame=null;this.captureOps=false;return frame;}
 };
 window.requestAnimationFrame=callback=>{__combatProbe.queue.push(callback);return __combatProbe.queue.length;};Object.defineProperty(performance,'now',{value:()=>__combatProbe.clock});
 for(const method of ['drawImage','fillText','strokeText','fill','stroke','fillRect']){const original=CanvasRenderingContext2D.prototype[method];CanvasRenderingContext2D.prototype[method]=function(...a){const p=__combatProbe;if(p.frame&&p.captureOps&&this.canvas===p.surface){const m=this.getTransform(),x=method==='drawImage'?a[1]:a[1]??0,y=method==='drawImage'?a[2]:a[2]??0;p.frame.ops.push({method,text:method.endsWith('Text')?String(a[0]):undefined,x,y,a:m.a,d:m.d,e:m.e,f:m.f,stroke:this.strokeStyle,fill:this.fillStyle,lineWidth:this.lineWidth,alpha:this.globalAlpha,dash:this.getLineDash()});}return original.apply(this,a);};}
}
const mime={'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.webmanifest':'application/manifest+json'};
async function createPage(browser,profile){
 const context=await browser.newContext({viewport:{width:profile.width,height:profile.height},isMobile:profile.mobile,hasTouch:profile.mobile,deviceScaleFactor:profile.mobile?2:1,serviceWorkers:'block'});await context.addInitScript(initialize);
 const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{const request=route.request(),u=new URL(request.url());if(request.method()!=='GET')return route.continue();const file=u.pathname==='/'?path.join(web,'index.html'):path.resolve(web,'.'+u.pathname);if(!file.startsWith(web+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile())return route.continue();let body=fs.readFileSync(file);
  if(file===assetPath('game.js')){body=body.toString();const marker='window.leqraInfinityArt=Object.freeze({';assert.ok(body.includes(marker));body=body.replace(marker,commonHooks+'\n'+marker);}
  if(file===assetPath('infinite.js')){body=body.toString();const at=body.lastIndexOf('})();');assert.ok(at>0);body=body.slice(0,at)+infinityHooks+body.slice(at);}
  await route.fulfill({status:200,contentType:mime[path.extname(file)]||'application/octet-stream',body});
 });await page.goto(origin+'/?test=1');await page.waitForFunction(()=>window.__test&&__combatProbe.infinityNetwork,null,{polling:20});return page;
}
function analyze(spec,result,label){
 const frames=result.frames,targetFrames=frames.map(f=>({f,t:f.tanks.find(t=>t.id===result.victim)}));
 if(spec.baseline){check(!frames.some(f=>f.bullets.length||f.effects.some(e=>['hit','shield','blast'].includes(e.kind))||f.sounds.length),label+' baseline does not replay old contacts');check(!targetFrames.some(({t})=>t?.alive),label+' baseline does not resurrect victim');return;}
 if(spec.lifeGuard){check(targetFrames.every(({t})=>!t||t.life===8&&t.alive),label+' new life is not replaced by old pre-hit state');check(!frames.some(f=>f.effects.some(e=>e.kind==='hit'||e.kind==='shield')),label+' stale-life damage effect is dropped');return;}
 const endpoint=frames.find(f=>spec.kind==='laser'?f.beams.some(b=>Math.hypot(b.points.at(-1).x-result.end.x,b.points.at(-1).y-result.end.y)<.05):spec.kind==='starman'?f.tanks.some(t=>{const target=f.tanks.find(t=>t.id===result.victim);return target&&t.id===result.owner&&Math.hypot(t.x-target.x,t.y-target.y)<=34.01;}):f.bullets.some(b=>Math.hypot(b.x-result.end.x,b.y-result.end.y)<.05));
 assert.ok(endpoint,label+' actual Canvas draws exact contact endpoint');
 const touched=endpoint.tanks.find(t=>t.id===result.victim);check(touched?.alive,label+' victim remains alive on endpoint frame');check(!spec.shield||touched.shieldCharges===2,label+' pre-hit Shield count survives endpoint frame');
 if(spec.winning)check(!endpoint.covered,label+' winning shot remains visible before result screen');
 if(!['laser','starman'].includes(spec.kind)){const shell=endpoint.bullets.find(b=>Math.hypot(b.x-result.end.x,b.y-result.end.y)<.05);check(shell.painted,label+' exact shell endpoint changes actual Canvas pixels');check(Math.hypot(shell.x-touched.x,shell.y-touched.y)<=shell.r+touched.r+.1,label+' shell visibly reaches victim body');}
 const changed=targetFrames.find(({t})=>spec.shield?t?.shieldCharges===1:!t||!t.alive);check(changed&&changed.f.index>endpoint.index,label+' damage presentation starts after endpoint frame');
 const effectFrames=frames.filter(f=>f.effects.some(e=>[spec.shield?'shield':'hit','blast'].includes(e.kind))||f.sounds.includes(spec.shield?'shield':'hit')||f.sounds.includes('blast'));
 check(effectFrames.length&&effectFrames.every(f=>f.index>endpoint.index),label+' hit/Shield/blast visuals and audio start after contact');
 for(const {f,t}of targetFrames)if(f.index<=endpoint.index)check(t?.alive&&(!spec.shield||t.shieldCharges===2),label+' pre-contact frame '+f.index+' keeps victim/protection');
 return{endpoint:endpoint.index,changed:changed.f.index,effects:effectFrames.map(f=>f.index)};
}
function saveFrames(label,result,indices){for(const frame of result.frames)if(frame.png&&indices.includes(frame.index)){fs.writeFileSync(path.join(output,label+'-frame-'+frame.index+'.png'),Buffer.from(frame.png.split(',')[1],'base64'));}for(const f of result.frames)delete f.png;}
async function run(){
 const browser=await chromium.launch({headless:true,args:['--disable-features=LocalNetworkAccessChecks']});
 try{for(const profile of profiles){const page=await createPage(browser,profile);try{
  for(const arena of ['fixed','infinity'].filter(a=>!arenaFilter||a===arenaFilter)){
   const matrix=[];
   for(const ping of quick?[150]:[50,150,400])for(const role of quick?['remote']:['own','remote','spectator'])for(const published of [false,true])for(const shield of [false,true])for(const kind of quick?['regular','cannon','grenade','laser','starman']:weapons){if(['laser','starman'].includes(kind)&&published||kind==='starman'&&shield)continue;matrix.push({kind,ping,role,published,shield});}
   for(const kind of weapons)matrix.push({kind,ping:400,role:'own',published:ballistics.includes(kind),shield:false,winning:true});
   matrix.push({kind:'cannon',ping:400,role:'remote',published:true,shield:false,baseline:true},{kind:'cannon',ping:400,role:'remote',published:true,shield:false,lifeGuard:true},{kind:'cannon',ping:400,role:'own',published:true,shield:false,equalTick:true},{kind:'cannon',ping:400,role:'remote',published:true,shield:false,missing:true});
   for(const spec of uiOnly?[]:matrix){const capture=spec.kind==='cannon'&&spec.ping===400&&spec.role==='own'&&spec.published&&!spec.shield;spec.capture=capture;const label=[profile.name,arena,'online',spec.kind,spec.ping,spec.role,spec.published?'published':'short',spec.shield?'shield':'kill',spec.winning?'win':spec.baseline?'baseline':spec.lifeGuard?'new-life':spec.equalTick?'equal-tick':spec.missing?'retired-target':''].filter(Boolean).join('-');
    const result=await page.evaluate(({arena,spec})=>__combatProbe[arena+'Network'](spec),{arena,spec});const record={label,spec,frames:result.frames};records.push(record);const timeline=analyze(spec,result,label);record.timeline=timeline;if(timeline)saveFrames(label,result,[timeline.endpoint,timeline.changed]);
   }
   for(const published of [false,true])for(const shield of [false,true])for(const kind of uiOnly?[]:quick?['regular','cannon']:weapons){if(['laser','starman'].includes(kind)&&published||kind==='starman'&&shield)continue;const spec={kind,published,shield},label=[profile.name,arena,'offline',kind,published?'published':'short',shield?'shield':'kill'].join('-');const result=await page.evaluate(({arena,spec})=>__combatProbe[arena+'Offline'](spec),{arena,spec});const record={label,spec,frames:result.frames};records.push(record);record.timeline=analyze(spec,result,label);}
   if(!uiOnly&&arena==='fixed'){const frames=await page.evaluate(()=>__combatProbe.fixedBatch()),label=profile.name+' fixed coalesced Shield then lethal contact',first=frames.find(f=>f.bullets.some(b=>b.id===77&&Math.abs(b.x-219)<.05)),second=frames.find(f=>f.bullets.some(b=>b.id===78&&Math.abs(b.x-259)<.05)),shield=frames.find(f=>f.effects.some(e=>e.kind==='shield')),hit=frames.find(f=>f.effects.some(e=>e.kind==='hit'));check(first&&second&&shield&&hit&&first.index<shield.index&&shield.index<=second.index&&second.index<hit.index,label+' each endpoint precedes its own damage');check(first.tanks.some(t=>t.id===1&&t.alive&&t.shieldCharges===1&&t.x===250)&&second.tanks.some(t=>t.id===1&&t.alive&&t.shieldCharges===0&&t.x===290),label+' each endpoint touches the correct live pre-hit pose');records.push({label,frames});}
   let previousIcons;
   for(const count of [180,179,100,99,10,9]){const result=await page.evaluate(({arena,count})=>__combatProbe[arena+'Badges'](count),{arena,count}),label=profile.name+' '+arena+' badge '+count;
    const filled=result.numbers.filter(n=>n.method==='fillText'),strokes=result.numbers.filter(n=>n.method==='strokeText');check(filled.some(n=>n.text===String(count)),label+' visible round count');check(strokes.length===filled.length&&strokes.every((n,i)=>n.text===filled[i].text&&n.stroke==='#000000'&&n.lineWidth>0),label+' every count has black outline');
    const ops=result.frame.ops,lastIcon=ops.findLastIndex(o=>o.method==='drawImage'),firstCount=ops.findIndex(o=>o.method==='strokeText'&&/^\d+$/.test(o.text));check(firstCount>lastIcon,label+' all icons precede count layer');check(ops.slice(firstCount).every(o=>['fillText','strokeText','fill'].includes(o.method)),label+' no later effects cover numbers');
    const icons=result.icons.map(o=>[o.x,o.y,o.a,o.d,o.e,o.f].map(v=>Math.round(v*1e5)/1e5));if(previousIcons)check(JSON.stringify(icons)===JSON.stringify(previousIcons),label+' count transition preserves icon positions '+JSON.stringify({icons,previousIcons}));previousIcons=icons;
    fs.writeFileSync(path.join(output,[profile.name,arena,'badge',count].join('-')+'.png'),Buffer.from(result.frame.png.split(',')[1],'base64'));delete result.frame.png;records.push({label,count,frame:result.frame});
   }
   const tuning=await page.evaluate(arena=>__combatProbe[arena+'Tuning'](),arena);for(const kind of ['laser','cannon']){check(Math.abs(tuning[kind].cooldown-.85*2/3)<1e-10&&Math.abs(tuning[kind].total-.85*2/3)<1e-10,profile.name+' '+arena+' '+kind+' actual reload is one third shorter');check(tuning[kind].readiness==='COOLDOWN 0.6s',profile.name+' '+arena+' '+kind+' readiness UI uses reduced reload');}check(Math.abs(tuning.laser.guide-tuning.laser.expected)<1e-5&&tuning.laser.guidePainted,profile.name+' '+arena+' actual painted guide uses doubled Laser range');check(tuning.cannon.life===5.3,profile.name+' '+arena+' Cannon retains lifetime');records.push({label:profile.name+' '+arena+' tuning',tuning});
  }
 }finally{await page.context().close();}}
 check(errors.length===0,'No browser runtime errors');
 }catch(error){errors.push(error.stack||error.message);process.exitCode=1;}
 finally{await browser.close();fs.writeFileSync(path.join(output,'report.json'),JSON.stringify({scope:'Actual headless Chromium Canvas draws, transformed projectile/body contacts and pixel changes; synthetic controlled packet arrival/120Hz timestamps. Not a physical display FPS or real-network RTT claim.',checks,records,errors},null,2));console.log(JSON.stringify({checks:checks.length,cases:records.length,errors,output}));}
}
run().catch(error=>{console.error(error);process.exitCode=1;});
