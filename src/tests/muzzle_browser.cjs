'use strict';
// Real Canvas checks with deterministic RAF. All traffic stays on loopback.
// node src/tests/muzzle_browser.cjs [output-directory]
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const playwright=require('playwright'),{assetPath}=require('./web_assets.cjs');
const web=path.resolve(__dirname,'../web'),output=path.resolve(process.argv[2]||'/tmp/leqra-muzzle-browser');
fs.mkdirSync(output,{recursive:true});
const common=String.raw`
const muzzleTurret=paintTankTurret;
paintTankTurret=function(c,t){
 const fill=c.fillRect,rectangles=[];
 c.fillRect=function(x,y,w,h){rectangles.push({x,y,w,h});return fill.call(this,x,y,w,h);};
 try{return muzzleTurret(c,t);}finally{c.fillRect=fill;__muzzle.draws.push({tip:rectangles.length?rectangles.at(-1).x+rectangles.at(-1).w+1:30-(t.barrelRetraction??barrelRetraction(t)),hidden:!rectangles.length,angle:Math.atan2(c.getTransform().b,c.getTransform().a)});}
};
window.__muzzleFixed={
 setup(kind='',near=true){
  window.leqraInfinity?.close();mode='room';localRoom.rules=validateRoomRules({...defaultRoomRules(),infinity:false,pickupRate:'off'});
  localRoom.players=[0,1].map(id=>({id,member:id+1,kind:'human',name:id?'Observer':'Pilot',team:0,colorIndex:id}));
  startMatch();phase='playing';time=1;lastFrame=__muzzle.clock;accumulator=0;spawnClock=1e9;pickups=[];bullets=[];traces=[];clearInput();fire.flights=new Net.ProjectileFlights();localTankPose.presenters=new Map();
  __test.setWorld({width:504,height:420,cols:6,rows:5,walls:near?[{x:172,y:near==='corner'?212.5:110,w:8,h:200,axis:'v'}]:[]});mapCanvas=null;wallIndex=null;
  const ghost=typeof near==='string'&&near.startsWith('ghost'),gap=ghost?Number(near.slice(5)):22;
  Object.assign(tanks[1],{x:430,y:340,angle:0,invulnerable:1000,spawnProtected:false,human:true,localIndex:1});const t=tanks[0];Object.assign(t,{x:172-gap,y:210,angle:0,invulnerable:0,spawnProtected:false,cooldown:0,human:true,localIndex:0,ghostTime:ghost?600:0});
  if(kind)grantPower(t,kind);cacheMap();$('announcer').hidden=true;updateHUD(true);__muzzle.draws=[];return t;
 },
 shot(kind,near){const t=this.setup(kind,near);fire(t);render();const b=bullets[kind==='scatter'?1:0];return{draw:__muzzle.draws[0],bullet:b&&{x:b.x,y:b.y,vx:b.vx,r:b.r,startX:b.flightStartX,startY:b.flightStartY},beam:traces[0]?.points,tank:{x:t.x,y:t.y}};},
 turn(touch){const t=this.setup('',true);Object.assign(t,{invulnerable:1000});
  if(touch){const z=$('stickZone'),r=z.getBoundingClientRect(),x=r.left+r.width/2,y=r.top+r.height/2;z.dispatchEvent(new PointerEvent('pointerdown',{pointerId:77,pointerType:'touch',clientX:x,clientY:y,bubbles:true}));window.dispatchEvent(new PointerEvent('pointermove',{pointerId:77,pointerType:'touch',clientX:x,clientY:y+100,bubbles:true}));}
  else keys.add('KeyD');
  const samples=[];for(let i=0;i<45;i++){__muzzle.draws=[];update(1/120);let shot;if(i%6===0){bullets=[];t.cooldown=0;fire(t);const b=bullets[0];shot=b&&{angle:Math.atan2(b.vy,b.vx),bounces:b.bounces};}render();samples.push({angle:t.angle,draw:__muzzle.draws[0],shot});}clearInput();return samples;
 },
 online(){const t=this.setup('',true),base={...t,spawnSerial:1,shotSerial:0,alive:true};
  mode='online';online.connected=true;online.id=0;online.member=1;online.roomData=null;online.generation=-1;online.eventsInitialized=false;online.lastEvent=0;resetOnlineMotion();
  const packet=(tick,angle)=>({type:'state',tick,generation:1,world:{width:504,height:420,cols:6,rows:5,walls:[{x:172,y:110,w:8,h:200,axis:'v'}]},phase:'playing',round:1,roundClock:60,tanks:[{...base,angle}],bullets:[],pickups:[],events:[],rules:{...defaultRoomRules(),infinity:false}});
  receiveOnlineState(packet(100,0));__muzzle.clock+=34;receiveOnlineState(packet(102,.12));renderOnlineMotion(1/60,__muzzle.clock);__muzzle.draws=[];render();
  const pose={...tanks[0]};previewOnlineFire(false,{...Net.neutral(),fire:true},__muzzle.clock);
  const shell=[...online.shots.previews.values()].at(-1)?.shells[0];
  return{draw:__muzzle.draws[0],angle:pose.angle,shot:shell&&{x:shell.x,y:shell.y,angle:Math.atan2(shell.vy,shell.vx),bounces:shell.bounces}};
 }
};
`;
const infinity=String.raw`
window.__muzzleInfinity={
 setup(kind='',near=true){window.leqraInfinity.close();window.leqraInfinity.start('offline',{name:'Pilot',roomRules:{infinity:true,infinityRandomBots:false,pickupRate:'off'}});
  const w=session;w.nextBot=w.nextPickup=Infinity;w.pickups=[];w.bullets=[];w.time=1;resetControls();
  const walls=near?[{x:172,y:near==='corner'?212.5:110,w:8,h:200,axis:'v'}]:[];
  w.maze={wallsNear:()=>walls,visitWalls:(x0,y0,x1,y1,visit)=>{for(const a of walls)if(visit(a.x,a.y,a.w,a.h,a.axis,a.x+4))return true;return false;},blocked:(x,y,r)=>walls.some(a=>x+r>a.x&&x-r<a.x+a.w&&y+r>a.y&&y-r<a.y+a.h)};w.mapCache.clear();
  const ghost=typeof near==='string'&&near.startsWith('ghost'),gap=ghost?Number(near.slice(5)):22;
  const t=w.tanks[0];Object.assign(t,{x:172-gap,y:210,angle:0,invulnerable:0,spawnProtected:false,cooldown:0,power:kind,powerTime:30,charges:5,machineRounds:180,ghostTime:ghost?600:0});w.tanks=[t];w.camera.x=t.x;w.camera.y=t.y;__muzzle.draws=[];return w;
 },
 shot(kind,near){const w=this.setup(kind,near),t=w.tanks[0];fireShot(w,t);draw(w,__muzzle.clock,0);const b=w.bullets[kind==='scatter'?1:0];return{draw:__muzzle.draws[0],bullet:b&&{x:b.x,y:b.y,vx:b.vx,r:b.r,startX:b.flightStartX,startY:b.flightStartY},beam:w.visualEffects?.find(e=>e.kind==='laser')?.points,tank:{x:t.x,y:t.y}};},
 turn(touch){const w=this.setup('',true),t=w.tanks[0];t.invulnerable=1000;
  if(touch){const z=document.getElementById('infiniteStick'),r=z.getBoundingClientRect(),x=r.left+r.width/2,y=r.top+r.height/2;z.dispatchEvent(new PointerEvent('pointerdown',{pointerId:77,pointerType:'touch',clientX:x,clientY:y,bubbles:true}));window.dispatchEvent(new PointerEvent('pointermove',{pointerId:77,pointerType:'touch',clientX:x,clientY:y+100,bubbles:true}));}
  else pressed.add('KeyD');
  const samples=[];for(let i=0;i<45;i++){__muzzle.draws=[];offlineStep(w,STEP);let shot;if(i%6===0){w.bullets=[];t.cooldown=0;fireShot(w,t);const b=w.bullets[0];shot=b&&{angle:Math.atan2(b.vy,b.vx),bounces:b.bounces};}draw(w,__muzzle.clock,0);samples.push({angle:t.angle,draw:__muzzle.draws[0],shot});}resetControls();return samples;
 },
 online(){const w=this.setup('',true);w.online=true;w.joined=false;w.room={code:'PROBE',token:'synthetic'};socket={readyState:WebSocket.OPEN,send(){},close(){}};const ws=socket;
  receive(ws,{data:JSON.stringify({type:'welcome',id:1,seed:37,generation:1})});
  const packet=(tick,angle)=>({type:'state',tick,tanks:[{id:1,name:'Pilot',hp:1,x:150,y:210,angle,spawnSerial:1,colorIndex:0}],bullets:[],pickups:[],effects:[],players:1,leaderboard:[]});
  receive(ws,{data:JSON.stringify(packet(100,0))});__muzzle.clock+=34;receive(ws,{data:JSON.stringify(packet(102,.12))});__muzzle.draws=[];draw(w,__muzzle.clock,1/60);
  const result={draw:__muzzle.draws[0]};window.leqraInfinity.close();socket=null;return result;
 }
};
`;
const scripts=new Map([
 ['game.js',fs.readFileSync(assetPath('game.js'),'utf8').replace('window.leqraInfinityArt=Object.freeze({',common+'\nwindow.leqraInfinityArt=Object.freeze({')],
 ['infinite.js',fs.readFileSync(assetPath('infinite.js'),'utf8').replace('window.leqraInfinity =',infinity+'\nwindow.leqraInfinity =')],
]);
const server=http.createServer((req,res)=>{
 const url=new URL(req.url,'http://localhost'),file=path.resolve(web,'.'+(url.pathname==='/'?'/index.html':url.pathname));
 if(url.pathname.startsWith('/api/')){res.setHeader('Content-Type','application/json');res.end('{"players":0,"tankCount":0,"capacity":64,"leaders":[]}');return;}
 if(!file.startsWith(web+path.sep)||!fs.existsSync(file)){res.writeHead(404).end();return;}
 const ext=path.extname(file);res.setHeader('Content-Type',({'.js':'application/javascript','.html':'text/html','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.webmanifest':'application/manifest+json'})[ext]||'application/octet-stream');res.end(scripts.get(path.basename(file))||fs.readFileSync(file));
});
(async()=>{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const results=[],errors=[];
 try{for(const engine of ['chromium','firefox','webkit']){
  const browser=await playwright[engine].launch({headless:true});
  try{for(const profile of [{name:'desktop',mobile:false,width:1280,height:900},{name:'portrait',mobile:true,width:390,height:844},{name:'landscape',mobile:true,width:844,height:390}]){
   const mobile=profile.mobile,userAgent=mobile?(engine==='webkit'?playwright.devices['iPhone 13'].userAgent:engine==='firefox'?'Mozilla/5.0 (Android 15; Mobile; rv:128.0) Gecko/128.0 Firefox/128.0':playwright.devices['Pixel 7'].userAgent):undefined;
   const context=await browser.newContext({viewport:{width:profile.width,height:profile.height},hasTouch:mobile,userAgent,deviceScaleFactor:mobile?2:1,...(engine==='firefox'?{}:{isMobile:mobile}),serviceWorkers:'block'});
   await context.addInitScript(()=>{localStorage.setItem('leqra.introTour.v1','1');localStorage.setItem('leqra.muted','1');window.__muzzle={clock:1000,draws:[],queue:[]};window.requestAnimationFrame=fn=>{__muzzle.queue.push(fn);return __muzzle.queue.length;};Object.defineProperty(performance,'now',{value:()=>__muzzle.clock});});
   const page=await context.newPage();page.on('pageerror',e=>errors.push(engine+': '+e.message));await page.goto(`http://127.0.0.1:${server.address().port}/?test=1`);await page.waitForFunction(()=>window.__muzzleFixed&&window.__muzzleInfinity);
   for(const arena of ['Fixed','Infinity']){
    for(const kind of ['','rapid','scatter','homing','grenade','laser','cannon'])for(const near of [false,true,'corner','ghost8','ghost1']){
     const value=await page.evaluate(({arena,kind,near})=>window['__muzzle'+arena].shot(kind,near),{arena,kind,near});
     const collides=near&&(near!=='corner'||kind!=='rapid');
     assert.ok(value.draw,engine+' '+arena+' drew no turret');assert.ok(value.draw.tip<=(collides?21.500001:26.000001),JSON.stringify({engine,arena,kind,near,value}));
     if(value.bullet){if(typeof near==='string'&&near.startsWith('ghost')&&kind!=='cannon')assert.ok(Math.abs(value.bullet.x-(172-value.bullet.r-.12))<1e-6,'Ghost launch jumped away from its incoming wall face');else assert.ok(value.bullet.startX>value.tank.x+1,'hidden centre was replayed');if(collides&&kind!=='cannon')assert.ok(value.bullet.vx<0,'wall was penetrated');}
     if(near===true&&kind==='')await page.screenshot({path:path.join(output,`${engine}-${profile.name}-${arena.toLowerCase()}.png`)});
     results.push({engine,profile:profile.name,mobile,arena,kind:kind||'regular',near,value});
    }
    const samples=await page.evaluate(({arena,mobile})=>window['__muzzle'+arena].turn(mobile),{arena,mobile});
    assert.ok(samples.at(-1).angle>.5,engine+' '+arena+' did not turn');
    if(mobile)assert.ok(Math.abs(samples[0].angle-(arena==='Fixed'?9/120:9/60))<1e-6,'touch turn boost did not reach the client');
    for(const sample of samples){assert.ok(Number.isFinite(sample.angle)&&sample.draw);assert.ok(Math.abs(Math.atan2(Math.sin(sample.draw.angle-sample.angle),Math.cos(sample.draw.angle-sample.angle)))<1e-6,'barrel angle differs from displayed tank '+JSON.stringify({engine,arena,mobile,sample}));}
    assert.ok(samples.some(s=>s.shot),'turning did not fire');
    for(const sample of samples)if(sample.shot&&!sample.shot.bounces)assert.ok(Math.abs(Math.atan2(Math.sin(sample.shot.angle-sample.angle),Math.cos(sample.shot.angle-sample.angle)))<1e-6,'turning shot missed the barrel heading');
    results.push({engine,profile:profile.name,mobile,arena,turn:samples});
    const online=await page.evaluate(arena=>window['__muzzle'+arena].online(),arena);assert.ok(online.draw&&online.draw.tip<=22,JSON.stringify({engine,arena,online}));
    if(arena==='Fixed'){assert.ok(online.shot&&online.shot.bounces===1,'online shot did not reflect at the muzzle');assert.ok(Math.abs(Math.atan2(Math.sin(online.shot.angle-(Math.PI-online.angle)),Math.cos(online.shot.angle-(Math.PI-online.angle))))<1e-6,'online preview used a different turning pose');}
    results.push({engine,profile:profile.name,mobile,arena,online});
   }
   await context.close();
  }}finally{await browser.close();}
  console.log('PASS',engine);
 }}catch(e){errors.push(e.stack);process.exitCode=1;}finally{server.close();fs.writeFileSync(path.join(output,'report.json'),JSON.stringify({results,errors},null,2));console.log(JSON.stringify({cases:results.length,errors,output}));}
})();
