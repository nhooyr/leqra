'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {readFileSync}=require('node:fs'),vm=require('node:vm');
const {assetPath}=require('./web_assets.cjs');
const source=readFileSync(assetPath('game.js'),'utf8');
function declaration(name,code=source){const start=code.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=code.indexOf('\n',start),line=code.slice(start,end);return line.endsWith('}')?line:code.slice(start,code.indexOf('\n}',end)+2);}
function recorder(){
 let matrix={x:0,y:0,angle:0},stack=[],shape,clipped=false;
 const events=[],c={events,canvas:{},globalAlpha:1,textBaseline:'alphabetic',save(){stack.push({matrix:{...matrix},clipped,alpha:this.globalAlpha,textBaseline:this.textBaseline});},restore(){const state=stack.pop();({matrix,clipped}=state);this.globalAlpha=state.alpha;this.textBaseline=state.textBaseline;},clip(){clipped=true;},translate(x,y){matrix.x+=Math.cos(matrix.angle)*x-Math.sin(matrix.angle)*y;matrix.y+=Math.sin(matrix.angle)*x+Math.cos(matrix.angle)*y;},rotate(a){matrix.angle+=a;},beginPath(){shape=null;},rect(x,y,w,h){shape={x,y,w,h};},arc(x,y,r,start,end){shape={arc:true,x,y,r,start,end};},stroke(){if(shape?.arc)events.push({type:'arc',...shape,color:this.strokeStyle,alpha:this.globalAlpha,width:this.lineWidth,matrix:{...matrix}});},fill(){if(shape&&!shape.arc)events.push({type:'rect',...shape,alpha:this.globalAlpha,matrix:{...matrix}});},fillText(text,x,y){events.push({type:'text',text,x,y,font:this.font,alpha:this.globalAlpha,textBaseline:this.textBaseline,clipped,matrix:{...matrix}});},drawImage(image,x,y,w,h){events.push({type:'image',image,x,y,w,h,alpha:this.globalAlpha,matrix:{...matrix}});},measureText(text){return{width:text.length*6};}};
 c.strokeText=function(text,x,y){events.push({type:'text-stroke',text,x,y,font:this.font,color:this.strokeStyle,width:this.lineWidth,alpha:this.globalAlpha});};
 return new Proxy(c,{get:(t,k)=>k in t?t[k]:(()=>{})});
}
function boot(){
 const ctx=recorder(),made=[];
 const s={ctx,mode:'room',phase:'playing',pausedFrom:'playing',isSpectating:()=>false,survivalBreak:()=>false,scale:1,W:2400,H:1500,TAU:Math.PI*2,MAX_SPEED_STACKS:5,MACHINE_FIRING_ROUNDS:180,reduceMotion:true,fxTime:0,shake:0,combatPrefs:{performance:true},WEBKIT_ENGINE:false,theme:{protection:'#fff'},localPlayerID:()=>0,secondaryID:()=>1,paintColor:c=>c,clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),tankPowerBadgeCache:new Map(),tankPowerBadgeScratch:[],labelWidthCache:new Map(),drawCachedTankHull(){},roundRect:(c,...args)=>{c.beginPath();c.rect(...args);},powerIcon:(kind,c=ctx)=>c.canvas.kind=kind,document:{createElement:()=>{const c=recorder(),canvas=c.canvas;canvas.getContext=()=>c;made.push(canvas);return canvas;}}};
 vm.createContext(s);require('./identity_fixture.cjs')(s,source);s.localRoom={players:[]};vm.runInContext(source.slice(source.indexOf('const POWER='),source.indexOf('\nconst LASER_MAX_SEGMENTS=')),s);
 vm.runInContext(source.slice(source.indexOf('const tankPowerBadgeCache='),source.indexOf('function activeTankPowerBadges(')),s);
 for(const name of ['shieldCount','speedCount','measureLabel','activeTankPowerBadges','tankPowerBadgeImage','tankLabel','tankStatusLayout','tankPowerBadgePositions','powerExpiryAlpha','expiryFadeAlpha','tankPowerBadgeLife','tankPowerBadgeCount','drawTankPowerBadgeCount','drawTankPowerBadges','protectionRingAlpha','localSpawnGuideAlpha','drawLocalSpawnGuide','drawTankLabel','paintTankTurret','drawTank','drawPickup','update'])if(source.includes('function '+name+'('))vm.runInContext(declaration(name),s);
 return {s,ctx,made};
}
function tank(patch={}){return{id:3,name:'GODLIKE BOSS',human:false,alive:true,invulnerable:.75,spawnProtected:true,x:1200,y:700,angle:0,recoil:0,track:0,color:'#73cee4',power:'laser',powerTime:15,charges:3,machineRounds:180,shield:10,shieldCharges:5,speedTime:10,speedStacks:2,ghostTime:10,...patch};}
function pictures(ctx){return ctx.events.filter(e=>e.type==='image');}
function spawnGuides(ctx){return ctx.events.filter(e=>e.type==='arc'&&e.r===34&&e.width>=2.5&&e.color!=='#081015');}

test('Godlike bot warnings remain readable above names and cannot be spoofed by a human callsign',()=>{
 for(const scale of [.08,.5,1,2]){
  const {s,ctx}=boot();s.scale=scale;
  const t=tank({difficulty:'godlike',bot:true,name:'ROVER'});s.drawTank(t);
  const warning=ctx.events.find(e=>e.type==='text'&&e.text==='GODLIKE'),name=ctx.events.find(e=>e.type==='text'&&e.text==='ROVER');
  assert.ok(warning.y<name.y,'warning is above the callsign');
  assert.ok(parseFloat(warning.font.match(/[\d.]+px/)[0])*scale>=10);
  ctx.events.length=0;Object.assign(t,{human:true,bot:false,name:'Godlike fan'});s.drawTank(t);
  assert.equal(ctx.events.filter(e=>e.type==='text'&&e.text==='GODLIKE').length,0);
 }
});

function badgeOverlap(a,b){return Math.hypot(a.x+a.w/2-b.x-b.w/2,a.y+a.h/2-b.y-b.h/2)<(a.w+b.w)*28.5/64-1e-8;}
function labelRect(ctx){return ctx.events.findLast(e=>e.type==='rect');}
function nameGeometry(ctx){const text=ctx.events.findLast(e=>e.type==='text'),label=labelRect(ctx);return{x:text.x,y:text.y,font:text.font,background:{x:label.x,y:label.y,w:label.w,h:label.h}};}

test('bot and remote power icons proceed clockwise below stable names without covering the hull at desktop and mobile scales',()=>{
 for(const mode of ['room','online'])for(const scale of [2,1,.5,.2,.08])for(const charges of [0,1,5]){
  const {s,ctx}=boot();s.mode=mode;s.scale=scale;
  const t=tank({shield:charges?10:0,shieldCharges:charges,angle:1.35,human:mode==='online'});s.drawTank(t);
  const text=ctx.events.findLast(e=>e.type==='text'),label=labelRect(ctx),icons=pictures(ctx);
  assert.equal(text.text,s.tankLabel(t));assert.equal(icons.length,charges?4:3);
  for(const glyph of ctx.events.filter(event=>event.type==='text'))assert.ok(parseFloat(glyph.font.replace('bold ',''))*scale>=10-1e-8,'names and badge counts retain the 10px screen-space minimum');
  const textDescent=parseFloat(text.font.replace('bold ',''))*.25;
  for(const icon of icons){
   assert.ok(icon.y+icon.w*(.5-28.5/64)>=label.y+label.h,'name background stays above the lower icon arc');
   assert.ok(icon.y+icon.w*(.5-28.5/64)>text.y+textDescent,'scaled name descenders must stay above icons');
   assert.ok(Math.hypot(icon.x+icon.w/2-t.x,icon.y+icon.h/2-t.y)-icon.w*28.5/64>=30-1e-8,'visible badge circles stay outside the hull');
   assert.deepEqual(icon.matrix,{x:0,y:0,angle:0},'icons remain aligned with the world after the tank rotates');
   assert.ok(icon.w>=24&&icon.h>=24,'retain readable icon size');
   assert.ok(icon.w*scale>=Math.min(24*scale,17.28)-1e-8);
  }
  for(let i=0;i<icons.length;i++)for(let j=0;j<i;j++)assert.ok(!badgeOverlap(icons[i],icons[j]),'adjacent icons do not overlap');
  assert.ok(icons[0].x>t.x,'first badge starts right of the tank below its name');
  assert.ok(icons[1].x<icons[0].x&&icons[1].y>icons[0].y);
  assert.ok(Math.abs(icons[2].x+icons[2].w/2-t.x)<1e-8,'third badge is below the tank');
  assert.ok(icons[2].y>icons[1].y);
  if(charges)assert.ok(icons[3].y<icons[2].y&&icons[3].x<icons[2].x);
 }
});
test('name position and dimensions never change as weapons, shields and other effects are acquired or lost',()=>{
 for(const mode of ['room','online'])for(const scale of [1,.25,.08])for(const [x,y] of [[1200,700],[42,42],[2358,1458]]){
  const {s,ctx}=boot();s.mode=mode;s.scale=scale;
  const t=tank({x,y,powerTime:0,shield:0,shieldCharges:0,speedTime:0,ghostTime:0});
  s.drawTank(t);const before=nameGeometry(ctx);
  for(const patch of [{powerTime:15},{shield:10,shieldCharges:1},{shieldCharges:5},{speedTime:10},{ghostTime:10},{powerTime:0,shield:0,speedTime:0,ghostTime:0}]){
   Object.assign(t,patch);ctx.events.length=0;s.drawTank(t);assert.deepEqual(nameGeometry(ctx),before);
  }
 }
});
test('both local pilots, bots, remote pilots and spectated tanks receive badges',()=>{
 for(const mode of ['room','online'])for(const id of [0,1,3])for(const human of [false,true]){
  const {s,ctx}=boot();s.mode=mode;s.drawTank(tank({id,human}));
  assert.equal(pictures(ctx).length,4,`${mode} id=${id} human=${human}`);
 }
 const {s,ctx}=boot();s.mode='online';s.localPlayerID=()=>-1;s.secondaryID=()=>-1;s.drawTank(tank({id:0,human:true}));assert.equal(pictures(ctx).length,4);
});
test('badge orbits reuse cached icon sprites across movement and rotation, removing expired effects',()=>{
 const {s,ctx,made}=boot(),t=tank();s.drawTank(t);const first=pictures(ctx).map(e=>e.image);assert.equal(made.length,4);
 for(let i=0;i<20;i++){ctx.events.length=0;t.x+=1;t.y+=2;t.angle+=.1;s.drawTank(t);assert.deepEqual(pictures(ctx).map(e=>e.image),first);}
 assert.equal(made.length,4,'moving tanks do not rebuild icon sprites');
 ctx.events.length=0;Object.assign(t,{powerTime:0,shield:0,speedTime:0,ghostTime:0});s.drawTank(t);assert.equal(pictures(ctx).length,0);
 Object.assign(t,{alive:false,powerTime:10});ctx.events.length=0;s.drawTank(t);assert.equal(pictures(ctx).length,0);assert.equal(ctx.events.filter(e=>e.type==='text').length,0);
});

test('bot and remote power icons keep their tank-relative offsets through every edge and corner',()=>{
 for(const mode of ['room','online'])for(const scale of [1,.25,.08])for(const count of [1,2,3,4]){
  const {s,ctx}=boot();Object.assign(s,{mode,scale});
  const t=tank({human:mode==='online',shield:count>=2?10:0,shieldCharges:count>=2?5:0,speedTime:count>=3?10:0,ghostTime:count>=4?10:0});
  s.drawTank(t);const offsets=pictures(ctx).map(icon=>({kind:icon.image.kind,x:icon.x-t.x,y:icon.y-t.y,w:icon.w}));assert.equal(offsets.length,count);
  for(const x of [17,42,1200,2358,2383])for(const y of [17,42,700,1458,1483]){
   Object.assign(t,{x,y,angle:t.angle+.17,powerTime:9,shieldCharges:count>=2?3:0,speedStacks:4});ctx.events.length=0;s.drawTank(t);
   const label=labelRect(ctx),icons=pictures(ctx);assert.equal(icons.length,count);assert.equal(y-label.y-label.h,32,'badges never move the name');
   for(let i=0;i<icons.length;i++){
    const icon=icons[i],offset=offsets[i];assert.equal(icon.image.kind,offset.kind);assert.equal(icon.w,offset.w);
    assert.ok(Math.abs(icon.x-x-offset.x)<1e-8&&Math.abs(icon.y-y-offset.y)<1e-8,`${mode}, scale ${scale}, ${count} icons at ${x}, ${y}: slots cannot move with the maze edge`);
    for(let j=0;j<i;j++)assert.ok(!badgeOverlap(icon,icons[j]),'fixed slots remain separate');
   }
  }
 }
});

test('gaining or losing a power-up may repack badges but moving cannot create an alternate orbit',()=>{
 const {s,ctx}=boot(),t=tank({x:2383,y:1483});
 const draw=()=>{ctx.events.length=0;s.drawTank(t);return pictures(ctx).map(icon=>({kind:icon.image.kind,x:icon.x-t.x,y:icon.y-t.y}));};
 const full=draw();t.powerTime=0;const expired=draw();assert.equal(expired.length,3);assert.equal(expired[0].kind,'shield');assert.equal(expired[0].x,full[0].x);assert.equal(expired[0].y,full[0].y);
 t.powerTime=15;assert.deepEqual(draw(),full,'regaining the weapon restores the same slots even at a corner');
 const icons=pictures(ctx);assert.ok(icons.some(icon=>icon.x+icon.w>s.W||icon.y+icon.h>s.H),'near-edge icons may clip instead of moving away from the tank');
});

test('badges ease from full visibility to transparent according to their own timers',()=>{
 for(const mode of ['room','online'])for(const clock of [0,7.21]){
  const {s,ctx}=boot();Object.assign(s,{mode,fxTime:clock});const t=tank({id:0,human:true,powerTime:2.25,shield:3,speedTime:.75,ghostTime:1.5});
  s.drawTank(t);const icons=pictures(ctx),labels=ctx.events.filter(e=>e.type==='text');assert.equal(icons.length,4);assert.equal(labels.at(-1).text,s.tankLabel(t));assert.equal(labels.at(-1).alpha,1,'badge fade cannot dim the tank name');assert.equal(labels.at(-1).textBaseline,'alphabetic');
  assert.deepEqual(icons.map(icon=>icon.alpha),[.84375,1,.15625,.5]);
  assert.ok(s.expiryFadeAlpha(.001,3)<.000001);
  assert.equal(s.expiryFadeAlpha(0,3),0);
 }
});

test('Infinity and fixed tanks use the same badge positions, sprite counts and expiry fades',()=>{
 const {s,ctx}=boot(),infinite=readFileSync(assetPath('infinite.js'),'utf8');
 Object.assign(s,{COLORS:['#73cee4'],powers:vm.runInContext('POWER',s),
  art:{pilotIdentity:s.pilotIdentity,theme:s.theme,rect:s.roundRect,hull(){},turret(){},drawBadges:s.drawTankPowerBadges}});
 vm.runInContext(declaration('drawTank',infinite).replace('function drawTank','function drawInfinityTank'),s);
 for(const zoom of [.5,1,1.2])for(const mine of [false,true]){
  const t=tank({id:mine?1:3,human:mine,colorIndex:0,power:'rapid',powerTime:1,machineRounds:76,shield:3,speedTime:2,starmanTime:.5});
  s.scale=zoom;ctx.events.length=0;s.drawTank(t);
  const fixed=pictures(ctx),fixedCounts=ctx.events.filter(e=>e.type==='text').slice(0,-1);
  assert.deepEqual(fixed.map(icon=>icon.image.kind),['rapid','shield','speed','starman']);
  assert.equal(fixed[0].alpha,.5,'the weapon timer is held until Starman ends');
  assert.equal(fixed[3].alpha,.5,'Starman fades during its final second');
  ctx.events.length=0;s.drawInfinityTank(t,mine,zoom,1);
  assert.ok(parseFloat(ctx.events.find(event=>event.type==='text').font.replace('bold ',''))*zoom>=10-1e-8,'Infinity names retain the same screen-space font minimum');
  assert.deepEqual(pictures(ctx),fixed);
  assert.deepEqual(ctx.events.filter(e=>e.type==='text').slice(1),fixedCounts);
 }
});

test('shared online effect aging fades badges between snapshots without changing authority',()=>{
 const {s,ctx}=boot(),authority=tank({powerTime:.5,starmanTime:.25,ghostTime:.375,shield:.5,speedTime:1});
 const before=JSON.stringify(authority);
 vm.runInContext(declaration('applyOnlineTankEffects'),s);
 const draw=age=>{
  ctx.events.length=0;
  s.drawTankPowerBadges(s.applyOnlineTankEffects({...authority},authority,age));
  return Object.fromEntries(pictures(ctx).map(icon=>[icon.image.kind,icon.alpha]));
 };
 const first=draw(0),nearExpiry=draw(.125);
 for(const kind of Object.keys(first))assert.ok(nearExpiry[kind]<first[kind],kind);
 assert.deepEqual(Object.keys(draw(.25)),['laser','shield','speed','ghost']);
 assert.deepEqual(Object.keys(draw(.5)),['laser','speed']);
 assert.deepEqual(Object.keys(draw(.75)),['speed']);
 assert.deepEqual(draw(1),{});
 assert.equal(JSON.stringify(authority),before);
});

test('weapon corners report actual charges or machine-gun rounds and do not allocate per-count sprites',()=>{
 for(const mode of ['room','online'])for(const power of ['laser','homing','grenade','cannon','scatter','rapid']){
  const {s,ctx,made}=boot();s.mode=mode;const t=tank({human:mode==='online',power,shield:0,speedTime:0,ghostTime:0});
  const maximum=power==='rapid'?180:power==='scatter'?5:3;let sprite;
  for(let remaining=maximum;remaining>=0;remaining--){
   Object.assign(t,{charges:remaining,machineRounds:remaining,powerTime:remaining%2?2:10});s.fxTime=remaining/20;ctx.events.length=0;s.drawTankPowerBadges(t);
   const icon=pictures(ctx)[0],numbers=ctx.events.filter(e=>e.type==='text');assert.equal(numbers.length,1);assert.equal(numbers[0].text,String(remaining));assert.equal(numbers[0].alpha,icon.alpha,'number shares the badge blink');
   assert.ok(numbers[0].x>icon.x+icon.w/2&&numbers[0].x<=icon.x+icon.w);assert.ok(numbers[0].y>icon.y+icon.h/2&&numbers[0].y<icon.y+icon.h,'number occupies the lower-right corner');
   if(sprite)assert.equal(icon.image,sprite);else sprite=icon.image;
  }
  assert.equal(made.length,1,'ammo changes reuse the weapon sprite');
 }
});

test('stack counters reflect shield and speed stacks while Ghost remains unnumbered',()=>{
 for(const mode of ['room','online'])for(const stacks of [1,2,5]){
  const {s,ctx}=boot();s.mode=mode;const t=tank({human:mode==='online',power:null,shieldCharges:stacks,speedStacks:stacks});s.drawTankPowerBadges(t);
  assert.deepEqual(pictures(ctx).map(e=>e.image.kind),['shield','speed','ghost']);assert.deepEqual(ctx.events.filter(e=>e.type==='text').map(e=>e.text),[String(stacks),String(stacks)]);
  Object.assign(t,{shield:0,speedTime:0});ctx.events.length=0;s.drawTankPowerBadges(t);assert.equal(pictures(ctx).length,1);assert.equal(ctx.events.some(e=>e.type==='text'),false);
 }
});

test('fading effects and changing counts keep all four fixed slots at a maze corner',()=>{
 const {s,ctx}=boot(),t=tank({x:2383,y:1483,powerTime:2,shield:2,speedTime:2,ghostTime:2});let positions;
 for(const clock of [0,Math.PI/24,Math.PI/8,12]){
  s.fxTime=clock;t.charges=Math.ceil(clock)%3+1;t.shieldCharges=Math.ceil(clock)%5+1;ctx.events.length=0;s.drawTankPowerBadges(t);
  const current=pictures(ctx).map(e=>[e.image.kind,e.x,e.y]);if(positions)assert.deepEqual(current,positions);else positions=current;assert.equal(current.length,4);
 }
});

test('a paused local game freezes both equipment timers and their fade',()=>{
 const {s,ctx}=boot(),t=tank({powerTime:2.9,shield:3.1});s.phase='paused';s.tanks=[t];
 const before=JSON.stringify(t);for(const dt of [.03,.7,4]){
  s.update(dt);assert.equal(JSON.stringify(t),before);ctx.events.length=0;s.drawTankPowerBadges(t);const icons=pictures(ctx);
  assert.equal(icons[0].alpha,s.expiryFadeAlpha(t.powerTime,3));assert.equal(icons[1].alpha,1,'pause cannot move the shield across the three-second boundary');
 }
});


test('tank names and badge centers stay close to the hull independent of shield count',()=>{
 for(const scale of [2,1,.5,.2,.08]){
  const {s,ctx}=boot();s.scale=scale;const t=tank();s.drawTank(t);
  const label=labelRect(ctx),icons=pictures(ctx),half=icons[0].w/2;
  assert.equal(t.y-label.y-label.h,32,'name has only two units of clearance above an upward muzzle');
  const oldZ=Math.max(1,.72/scale),oldHalf=12*oldZ,oldGap=2*oldZ;
  const oldRadius=Math.hypot(Math.max(31+oldHalf*Math.SQRT2+oldGap,Math.SQRT2*(2*oldHalf+oldGap)),Math.max(0,oldGap+oldHalf-32));
  const radius=Math.hypot(icons[0].x+half-t.x,icons[0].y+half-t.y);
  assert.ok(radius<=oldRadius,'readability must not increase the former orbit');
  if(scale>=.5)assert.ok(radius<=oldRadius-7,'normal and compact views bring icons at least seven units closer');
 }
});

test('spawn circles match each local tank paint in every mode without highlighting bots, remote tanks or spectator seats',()=>{
 for(const mode of ['room','online','solo','duel'])for(const gameMode of ['elimination','deathmatch','ctf','koth','survival']){
  const {s,ctx}=boot();Object.assign(s,{mode,phase:'countdown',currentRules:()=>({mode:gameMode})});
  for(const [patch,expected] of [[{id:0,human:true},true],[{id:1,human:true},true],[{id:3,human:true},false],[{id:0,human:false},false],[{id:1,human:false},false],[{id:0,human:true,survivalEnemy:true},false],[{id:1,human:true,alive:false},false]]){
   const t=tank({...patch,color:patch.id===1?'#ff9679':'#73cee4'});ctx.events.length=0;s.drawTank(t);const guides=spawnGuides(ctx);assert.equal(guides.length,expected?1:0,`${mode}/${gameMode}: ${JSON.stringify(patch)}`);
   if(expected){assert.equal(guides[0].r,34);assert.equal(guides[0].alpha,1);assert.equal(guides[0].color,t.color);}
  }
  s.isSpectating=()=>true;assert.equal(s.localSpawnGuideAlpha(tank({id:0,human:true})),0);
  s.secondaryID=()=>undefined;assert.equal(s.localSpawnGuideAlpha(tank({id:1,human:true})),0);
 }
});

test('online spawn guide colors follow local ownership when seat IDs change or the primary pilot spectates',()=>{
 const {s,ctx}=boot();Object.assign(s,{mode:'online',localPlayerID:()=>5,secondaryID:()=>3});
 const guide=(id,color='#73cee4')=>{ctx.events.length=0;s.drawTank(tank({id,color,human:true,shield:0}));return spawnGuides(ctx);};
 assert.equal(guide(5)[0].color,'#73cee4');assert.equal(guide(3,'#ff9679')[0].color,'#ff9679');assert.equal(guide(1).length,0,'seat one is a remote pilot');
 s.isSpectating=()=>true;assert.equal(guide(5).length,0);assert.equal(guide(3,'#ff9679')[0].color,'#ff9679','local P2 keeps its selected paint while P1 spectates');
 s.secondaryID=()=>7;assert.equal(guide(3).length,0);assert.equal(guide(7,'#ffc46b')[0].color,'#ffc46b','a reassigned local P2 uses its current tank paint');
 s.secondaryID=()=>undefined;assert.equal(guide(7).length,0,'a removed local P2 cannot leave a locator on a remote body');
});

test('spawn guides use the same theme paint as each tank hull',()=>{
 const {s,ctx}=boot();s.paintColor=color=>({'#73cee4':'#32c5ff','#ff9679':'#ff758f'}[color]||color);
 for(const [id,color,paint] of [[0,'#73cee4','#32c5ff'],[1,'#ff9679','#ff758f']]){
  ctx.events.length=0;s.drawTank(tank({id,color,human:true}));assert.equal(spawnGuides(ctx)[0].color,paint);
 }
});

test('spawn guides follow remaining protection, freezing their fade through a paused countdown and long pauses',()=>{
 const {s}=boot(),t=tank({id:0,human:true});
 for(const phase of ['countdown','playing','paused']){s.phase=phase;for(const remaining of [.75,.35,.01,Number.EPSILON]){t.invulnerable=remaining;s.fxTime=1e8;assert.equal(s.localSpawnGuideAlpha(t),s.protectionRingAlpha(t));}}
 t.invulnerable=0;assert.equal(s.localSpawnGuideAlpha(t),0,'no cosmetic tail after protection expires');
 t.invulnerable=.35;t.spawnProtected=false;assert.equal(s.localSpawnGuideAlpha(t),0,'shield-hit grace does not restart the spawn ring');
 t.spawnProtected=true;for(const phase of ['menu','onlineLobby','roundOver','matchOver']){s.phase=phase;assert.equal(s.localSpawnGuideAlpha(t),0);}
 s.phase='playing';s.survivalBreak=()=>true;assert.equal(s.localSpawnGuideAlpha(t),0,'intermission is not a spawn');
});

test('online spawn tags follow authoritative life changes and never turn a shield save into a spawn',()=>{
 const {s}=boot();vm.runInContext(declaration('netTank'),s);
 let t=s.netTank(tank({id:0,bot:false,spawnSerial:0,invulnerable:.75}));assert.equal(s.localSpawnGuideAlpha(t),1);
 t=s.netTank({...t,invulnerable:.1},t);assert.ok(s.localSpawnGuideAlpha(t)>0&&s.localSpawnGuideAlpha(t)<1);
 t=s.netTank({...t,invulnerable:0},t);assert.equal(s.localSpawnGuideAlpha(t),0);
 t=s.netTank({...t,invulnerable:.35},t,true);assert.equal(s.localSpawnGuideAlpha(t),0);
 t=s.netTank({...t,spawnSerial:1,spawnProtected:true,invulnerable:1.2},t);assert.equal(s.localSpawnGuideAlpha(t),1,'objective respawns rearm protection on a new life');
 t=s.netTank({...t,invulnerable:.1},t,true);assert.equal(s.localSpawnGuideAlpha(t),0,'a shield event invalidates spawn protection even when an expired snapshot was skipped');
 t=s.netTank({...t,spawnProtected:true,invulnerable:.75},null);assert.equal(s.localSpawnGuideAlpha(t),1,'a new round generation starts with a fresh body');
});

test('a real shield save clears the local spawn tag instead of lighting the spawn ring again',()=>{
 const {s}=boot(),noop=()=>{};Object.assign(s,{canDamage:()=>true,burst:noop,addRing:noop,tone:noop,shieldSound:noop,toast:noop});vm.runInContext(declaration('hurt'),s);
 const t=tank({id:0,human:true,invulnerable:0});s.hurt(t,{owner:3,kind:'shell'});assert.equal(t.invulnerable,.35);assert.equal(t.spawnProtected,false);assert.equal(s.localSpawnGuideAlpha(t),0);
});

function onlineBoot(){
 const {s}=boot(),noop=()=>{};
 Object.assign(s,{mode:'online',phase:'onlineLobby',round:0,roundClock:0,phaseTime:0,roundWinner:-1,scores:[],gameStarted:false,tanks:[],particles:[],rings:[],traces:[],bullets:[],pickups:[],cols:12,rows:8,grid:[],walls:[],goUntil:0,shake:0,now:1000,
  performance:{now:()=>s.now},updateOnlineBounceSounds:noop,Net:require(assetPath('netcode.js')),COLORS:[],cacheMap:noop,resize:noop,clearInput:noop,sendOnlineInput:noop,closeVictory:noop,setScreen:noop,renderOnlineRoom:noop,updateHUD:noop,showStartingControls:noop,secondLocal:()=>({id:1}),moveTank:noop,onlineEffect:noop,syncRestartWaveActions:noop,
  online:{connected:true,id:0,generation:0,snapshots:[],ownedIDs:new Set(),activeIDs:new Set(),trailIDs:new Set(),trails:new Map(),localBullets:new Map(),effectQueue:[],shots:{sync:noop,prune:noop,heard:()=>false,previews:new Map()},eventsInitialized:true,lastEvent:0,buffer:{push:packet=>s.online.snapshots.push(packet),advance:()=>null,tank:id=>({...s.online.snapshots.at(-1).tankMap.get(id)})}},
  survivalState:()=>s.online.snapshots.at(-1)?.objectives?.survival,survivalBreak:()=>s.survivalState()?.status==='break',
  resetOnlineMotion:()=>{s.online.snapshots.length=0;}
 });
 s.online.predictor=new s.Net.Predictor(noop);s.online.secondary={predictor:new s.Net.Predictor(noop)};
 for(const name of ['netTank','receiveOnlineState','applyOnlineTankEffects','renderOnlineMotion'])vm.runInContext(declaration(name),s);
 let tick=0;
 s.packet=(phase,{generation=1,wave=0,status='wave',world=false,serial=0,invulnerable=.75,events=[]}={})=>({tick:++tick,generation,phase,round:wave||1,roundClock:75,phaseTime:2.6,winner:-1,scores:[],bullets:[],pickups:[],events,tanks:[tank({id:0,bot:false,spawnSerial:serial,invulnerable}),tank({id:1,bot:false,spawnSerial:serial,invulnerable}),tank({id:3,bot:true,spawnSerial:serial,invulnerable})],...(wave?{objectives:{survival:{wave,status}}}:{}),...(world?{world:{cols:12,rows:8,width:1008,height:672,walls:[]}}:{})});
 return s;
}

test('online protection presentation follows authoritative timers between packets and freezes in countdown and wave breaks',()=>{
 const s=onlineBoot(),frame=now=>{s.renderOnlineMotion(1/60,now);return s.tanks.find(t=>t.id===0);};
 s.receiveOnlineState(s.packet('countdown',{world:true}));assert.equal(s.localSpawnGuideAlpha(frame(6000)),1,'waiting before weapons are live cannot spend countdown protection');
 s.now=6000;s.receiveOnlineState(s.packet('playing'));
 assert.ok(s.localSpawnGuideAlpha(frame(6749))>0&&s.localSpawnGuideAlpha(frame(6749))<.0001);assert.equal(s.localSpawnGuideAlpha(frame(6750)),0,'ring vanishes precisely at the latest snapshot protection expiry');
 assert.equal(s.localSpawnGuideAlpha(frame(16000)),0,'stale snapshots cannot leave a stuck protected ring');
 assert.equal(s.online.snapshots.at(-1).tankMap.get(0).invulnerable,.75,'presentation never changes authority');assert.equal(s.online.predictor.state.invulnerable,.75,'prediction cannot gain or consume authoritative protection');
 s.now=16000;s.receiveOnlineState(s.packet('playing',{generation:2,wave:5,serial:1,invulnerable:1.2,world:true}));assert.ok(s.localSpawnGuideAlpha(frame(17199))>0&&s.localSpawnGuideAlpha(frame(17199))<.0001);assert.equal(s.localSpawnGuideAlpha(frame(17200)),0);
 s.now=18000;s.receiveOnlineState(s.packet('playing',{generation:2,wave:5,serial:1,status:'break',invulnerable:.1}));assert.equal(frame(25000).invulnerable,.1);assert.equal(s.localSpawnGuideAlpha(frame(25000)),0,'intermission has no golden spawn indicator');
 s.now=25000;s.receiveOnlineState(s.packet('countdown',{generation:3,wave:5,serial:2,invulnerable:1.2,world:true}));assert.equal(s.localSpawnGuideAlpha(frame(28000)),1,'retry countdown resets this wave’s protected bodies');
});

test('online shield history applies to the matching life and generation before drawing, including a dropped expiry packet',()=>{
 const s=onlineBoot();s.receiveOnlineState(s.packet('countdown',{world:true}));s.now+=1000;
 s.receiveOnlineState(s.packet('playing',{invulnerable:.1,events:[{type:'shield',id:1,player:0,spawnSerial:0,generation:1}]}));s.renderOnlineMotion(1/60,s.now);
 assert.equal(s.localSpawnGuideAlpha(s.tanks.find(t=>t.id===0)),0);assert.ok(s.localSpawnGuideAlpha(s.tanks.find(t=>t.id===1))>0);
 s.now+=1000;s.receiveOnlineState(s.packet('countdown',{generation:2,world:true,events:[{type:'shield',id:1,player:0,spawnSerial:0,generation:1}]}));s.renderOnlineMotion(1/60,s.now);assert.equal(s.localSpawnGuideAlpha(s.tanks.find(t=>t.id===0)),1,'a former round’s shield event cannot cancel fresh spawn protection');
});


test('the render pass paints edge labels above tanks after restoring the maze clip',()=>{
 const {s,ctx}=boot(),noop=()=>{};
 Object.assign(s,{accumulator:0,localTankPose:t=>t,dpr:1,cssW:2400,cssH:1500,offsetX:0,offsetY:0,shake:0,mapCanvas:null,tanks:[tank({x:1200,y:21,powerTime:0,shield:0,speedTime:0,ghostTime:0})],pickups:[],bullets:[],rings:[],particles:[],drawObjectives:noop,drawAimingGuides:noop,drawFlags:noop,drawMissileWarnings:noop,drawLasers:noop,syncCanvasSize:noop});
 vm.runInContext(declaration('drawBullets'),s);vm.runInContext(declaration('renderArena'),s);vm.runInContext(declaration('render'),s);s.render();
 const labels=ctx.events.filter(e=>e.type==='text');assert.equal(labels.length,1);assert.equal(labels[0].clipped,false,'the maze boundary must not cut off the name');
 const rect=labelRect(ctx);assert.equal(rect.y+rect.h,s.tanks[0].y-32);assert.ok(rect.y<0,'fixed above-tank position can extend into the canvas margin');
});


test('local spawn and protection rings use the same eased final 300 ms without extending protection',()=>{
 const {s,ctx}=boot();
 for(const [remaining,expected] of [[2,1],[.75,1],[.3,1],[.225,.84375],[.15,.5],[.075,.15625],[0,0],[-.1,0]]){
  for(const [id,human] of [[0,true],[1,true],[3,true],[4,false]]){
   const t=tank({id,human,shield:0,invulnerable:remaining});ctx.events.length=0;s.drawTank(t);
   const guide=spawnGuides(ctx)[0],grey=ctx.events.find(e=>e.type==='arc'&&e.r===27&&e.color===s.theme.protection);
   if(remaining<=0){assert.equal(guide,undefined);assert.equal(grey,undefined);continue;}
   assert.ok(Math.abs(grey.alpha-.35*expected)<1e-8,`grey ${remaining}`);
   if(id===0||id===1){assert.ok(Math.abs(guide.alpha-expected)<1e-8,`pilot ${id} at ${remaining}`);assert.equal(guide.color,t.color);}else assert.equal(guide,undefined);
  }
 }
 // A tiny step at either end changes opacity much less than a linear fade:
 // easing joins both full strength and zero without a visible hard corner.
 assert.ok(s.protectionRingAlpha({invulnerable:.0001})<.000001);
 assert.ok(1-s.protectionRingAlpha({invulnerable:.2999})<.000001);
});

test('shield-hit grace may fade grey but never creates a local spawn locator',()=>{
 for(const id of [0,1]){const {s,ctx}=boot(),t=tank({id,human:true,shield:0,spawnProtected:false,invulnerable:.15});s.drawTank(t);
 assert.equal(spawnGuides(ctx).length,0);assert.equal(ctx.events.find(e=>e.type==='arc'&&e.r===27).alpha,.175);}
});

test('ammo transitions keep thin black outlines and a stable top layer above every icon',()=>{
 for(const zoom of [.08,.5,1,2])for(const power of ['rapid','laser','cannon','homing','grenade','scatter']){
  const {s,ctx,made}=boot();s.scale=zoom;const t=tank({power});let anchor;
  for(const rounds of power==='rapid'?[180,179,100,99,10,9]:[3,2,1]){
   Object.assign(t,{machineRounds:rounds,charges:rounds});ctx.events.length=0;
   s.drawTankPowerBadges(t,ctx,zoom,'icons');const iconsEnd=ctx.events.length;
   s.drawTankPowerBadges(t,ctx,zoom,'counts');
   const texts=ctx.events.filter(e=>e.type==='text'),outlines=ctx.events.filter(e=>e.type==='text-stroke');
   assert.equal(texts[0].text,String(rounds));assert.equal(outlines.length,texts.length);
   for(let i=0;i<texts.length;i++){
    const text=texts[i],outline=outlines[i];assert.equal(outline.text,text.text);assert.equal(outline.x,text.x);assert.equal(outline.y,text.y);assert.equal(outline.color,'#000');
    assert.ok(outline.width*zoom>=1-1e-8&&outline.width*zoom<=2+1e-8,'one thin screen-space outline');
    assert.ok(ctx.events.indexOf(outline)>=iconsEnd);assert.ok(ctx.events.indexOf(outline)<ctx.events.indexOf(text));
   }
   const current={x:texts[0].x,y:texts[0].y,font:texts[0].font};if(anchor)assert.deepEqual(current,anchor,'100→99 and10→9 do not move the label');else anchor=current;
  }
  assert.equal(made.length,4,'all ammo values reuse icon textures');
 }
});
