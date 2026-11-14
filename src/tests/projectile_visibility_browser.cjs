'use strict';
// Optional real Canvas/browser check. Use an isolated loopback backend only.
// node src/tests/projectile_visibility_browser.cjs http://127.0.0.1:18108 --disposable
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto'),{chromium}=require('playwright');
const {assetPath}=require('./web_assets.cjs'),args=process.argv.slice(2),address=args.find(value=>/^https?:/.test(value));
if(!address||!args.includes('--disposable'))throw Error('Supply an isolated loopback backend and --disposable.');
const url=new URL(address);if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.username||url.password||url.pathname!=='/'||url.search||url.hash)throw Error('Only an uncredentialed loopback origin is allowed.');
const origin=url.origin,root=path.resolve(__dirname,'../..'),web=path.join(root,'src/web'),prefix='/'+path.relative(web,path.dirname(assetPath('game.js'))).split(path.sep).join('/')+'/';
const out=process.env.LEQRA_BROWSER_OUTPUT?path.resolve(process.env.LEQRA_BROWSER_OUTPUT):fs.mkdtempSync(path.join(os.tmpdir(),'leqra-projectile-visibility-'));fs.mkdirSync(out,{recursive:true});
const profiles=[{name:'desktop',width:1280,height:900,mobile:false},{name:'portrait',width:390,height:844,mobile:true},{name:'landscape',width:844,height:390,mobile:true}],kinds=['regular','rapid','scatter','homing','grenade','cannon'];
const checks=[],errors=[],measurements=[],run=crypto.randomBytes(3).toString('hex');const check=(ok,label)=>{if(!ok)throw Error(label);checks.push(label);};
const commonHooks=String.raw`
const probeDrawBullets=drawBullets;drawBullets=function(items,...args){__projectileProbe.draws.push(...items.map(b=>({id:b.id,kind:b.kind||'regular',x:b.x,y:b.y,flight:!!b.flight})));return probeDrawBullets(items,...args);};
const probeDrawLasers=drawLasers;drawLasers=function(...args){__projectileProbe.lasers+=traces.length;return probeDrawLasers(...args);};
__projectileProbe.fixedSetup=function(kind){
 window.leqraInfinity?.close();mode='room';localRoom.rules=validateRoomRules({...defaultRoomRules(),infinity:false,teamMode:'ffa'});
 localRoom.players=[{id:0,member:1,kind:'human',name:'Probe',team:0,colorIndex:0},{id:1,member:2,kind:'human',name:'Target',team:0,colorIndex:1}];
 startMatch();phase='playing';time=1;spawnClock=1e9;accumulator=0;pickups=[];bullets=[];traces=[];
 __test.setWorld({width:504,height:420,cols:6,rows:5,walls:[]});mapCanvas=null;wallIndex=null;
 for(const t of tanks)Object.assign(t,{x:t.id?134:100,y:100,angle:0,human:true,invulnerable:0,spawnProtected:false,power:null,cooldown:0});
 if(kind!=='regular')grantPower(tanks[0],kind);this.draws=[];this.lasers=0;return tanks[0];
};
__projectileProbe.fixedOffline=function(kind,ending=false){
 const p=this.fixedSetup(kind),a=this.realNow();const fired=fire(p),fireMs=this.realNow()-a;if(ending)finishRound(0);
 const b=this.realNow();render();const renderMs=this.realNow()-b;
 const result={fired,dead:!tanks[1].alive,draws:[...this.draws],lasers:this.lasers,fireMs,renderMs};
 this.draws=[];this.clock+=70;render();result.expired=!this.draws.some(b=>b.flight);return result;
};
__projectileProbe.fixedNetwork=function(kind,ping,ending=false,published=false){
 this.fixedSetup('regular');const base=tanks.map(t=>({...t,alive:true,shotSerial:0,spawnSerial:1}));
 mode='online';online.connected=true;online.id=0;online.member=1;online.roomData=null;online.generation=-1;online.eventsInitialized=false;online.lastEvent=0;resetOnlineMotion();
 const world={width:504,height:420,cols:6,rows:5,walls:[]},rules={...defaultRoomRules(),infinity:false};
 const packet=(tick,bs,events=[],end=false)=>({type:'state',tick,generation:1,world,phase:end?'roundOver':'playing',phaseTime:end?2:0,round:1,roundClock:75,winner:end?1:-1,scores:Array(8).fill(0),tanks:base.map(t=>({...t,alive:!end||t.id===1})),bullets:bs,pickups:[],events,rules});
 this.clock+=ping/2;receiveOnlineState(packet(100,[]));this.clock+=33+ping/2;
 const radius=kind==='cannon'?14:kind==='grenade'?6:kind==='homing'?5:kind==='rapid'?1.4:3.5;
 if(published){
  const bullet={id:77,owner:1,kind:kind==='regular'?'':kind,r:radius,x:140,y:100,vx:100,vy:0,life:1,age:.01,bounces:0,color:COLORS[1],shotSerial:1,spawnSerial:1};
  receiveOnlineState(packet(102,[bullet]));this.clock+=33;receiveOnlineState(packet(104,[]));online.buffer.time=103*Net.STEP_MS;
 }else{
  const flight={id:77,owner:1,colorIndex:1,kind,radius,startTick:100,endTick:100.8,points:[{x:128,y:100,tick:100},{x:143,y:100,tick:100.8}]};
  const event=kind==='laser'?{id:1,type:'laser',owner:1,player:1,tick:100,generation:1,x:128,y:100,endX:143,endY:100,color:'#f57cff',points:[{x:128,y:100},{x:143,y:100}]}:
   {id:1,type:kind==='grenade'?'blast':['cannon','homing'].includes(kind)?'impact':'projectileFlight',tick:101,generation:1,owner:1,player:-1,x:143,y:100,color:COLORS[1],flight,shotSerial:1,spawnSerial:1};
  receiveOnlineState(packet(102,[],[event],ending));
 }
 this.draws=[];this.lasers=0;const captures=[];
 for(let frame=0;frame<30;frame++){this.clock+=1000/120;renderOnlineMotion(published?0:1/120,this.clock);render();captures.push(...this.draws);this.draws=[];if(published)break;}
 return{draws:captures,lasers:this.lasers,mode,phase};
};
`;
const infinityHooks=String.raw`
const probeDrawTrace=drawTrace;drawTrace=function(points,color,width,...args){if(width===7)__projectileProbe.lasers++;return probeDrawTrace(points,color,width,...args);};
__projectileProbe.infinitySetup=function(kind){
 window.leqraInfinity.close();window.leqraInfinity.start('offline',{name:'Probe',roomRules:{...__test.defaultRoomRules(),infinity:true,infinityRandomBots:false}});
 const w=session;w.maze={wallsNear:()=>[],visitWalls:()=>false,blocked:()=>false};w.mapCache.clear();w.nextBot=w.nextPickup=1e9;w.bullets=[];w.pickups=[];w.time=1;
 const p=w.tanks[0];Object.assign(p,{x:100,y:100,angle:0,spawnProtected:false,invulnerable:0,power:kind==='regular'?'':kind,powerTime:10,cooldown:0,charges:3,machineRounds:180});
 w.tanks=[p,{...p,id:'target',name:'Target',bot:true,x:134,power:'',charges:0,score:0,team:0}];this.draws=[];this.lasers=0;return w;
};
__projectileProbe.infinityOffline=function(kind,ending=false){
 const w=this.infinitySetup(kind);if(ending)w.rules.infinityTarget=1;
 const a=this.realNow();fireShot(w,w.tanks[0]);const fireMs=this.realNow()-a,b=this.realNow();draw(w,this.clock,0);const renderMs=this.realNow()-b;
 const result={dead:w.tanks[1].hp===0,draws:[...this.draws],lasers:this.lasers,fireMs,renderMs};this.draws=[];this.clock+=70;draw(w,this.clock,.07);result.expired=!this.draws.some(b=>b.flight);window.leqraInfinity.close();return result;
};
__projectileProbe.infinityNetwork=function(kind,ping,ending=false,published=false){
 const w=this.infinitySetup('regular');w.online=true;w.joined=false;w.room={code:'PROBE',token:'synthetic'};socket={readyState:WebSocket.OPEN,send(){},close(){}};const ws=socket;
 const receivePacket=packet=>receive(ws,{data:JSON.stringify(packet)});receivePacket({type:'welcome',id:1,seed:37,generation:1});w.maze={wallsNear:()=>[],visitWalls:()=>false,blocked:()=>false};
 const tanks=[{id:1,name:'Probe',hp:1,x:134,y:100,angle:0,spawnSerial:1,colorIndex:0},{id:2,name:'Target',hp:1,x:100,y:100,angle:0,spawnSerial:1,colorIndex:1}];
 const packet=(tick,bullets,effects=[],end=false)=>({type:'state',tick,tanks:tanks.map(t=>({...t,hp:end&&t.id===1?0:1})),bullets,pickups:[],effects,players:2,leaderboard:[],...(end?{result:{id:2,name:'Target',score:5}}:{})});
 this.clock+=ping/2;receivePacket(packet(100,[]));this.clock+=33+ping/2;
 const radius=kind==='cannon'?14:kind==='grenade'?6:kind==='homing'?5:kind==='rapid'?1.4:3.5;
 if(published){receivePacket(packet(102,[{id:77,owner:2,kind:kind==='regular'?'':kind,colorIndex:1,x:140,y:100,vx:100,vy:0,life:1,bounces:0}]));this.clock+=33;receivePacket(packet(104,[]));w.motionBuffer.time=103*net.STEP_MS;}
 else{
  const flight={id:77,owner:2,colorIndex:1,kind,radius,startTick:100,endTick:100.8,points:[{x:128,y:100,tick:100},{x:143,y:100,tick:100.8}]};
  const effect=kind==='laser'?{id:1,kind:'laser',owner:2,x:128,y:100,points:[{x:128,y:100},{x:143,y:100}]}:{id:1,kind:kind==='grenade'?'blast':['cannon','homing'].includes(kind)?'impact':'projectileFlight',owner:2,x:143,y:100,flight};
  receivePacket(packet(102,[],[effect],ending));
 }
 this.draws=[];this.lasers=0;const captures=[];let covered=false;
 for(let frame=0;frame<30;frame++){this.clock+=1000/120;draw(w,this.clock,published?0:1/120);showResult(w,this.clock);if(!captures.length&&resultDialog.open)covered=true;captures.push(...this.draws);this.draws=[];if(published)break;}
 const result={draws:captures,lasers:this.lasers,covered,result:!!w.result};window.leqraInfinity.close();socket=null;return result;
};
`;
const mime={'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.webmanifest':'application/manifest+json'};
(async()=>{const browser=await chromium.launch({headless:true,args:['--disable-features=LocalNetworkAccessChecks']});const contexts=[];
 async function make(profile,suffix){
  const context=await browser.newContext({viewport:{width:profile.width,height:profile.height},isMobile:profile.mobile,hasTouch:profile.mobile,deviceScaleFactor:profile.mobile?2:1,serviceWorkers:'block'});contexts.push(context);
  await context.addInitScript(name=>{for(const [key,value]of Object.entries({'introTour.v1':'1',name,local2Name:name+'W',infinityOnline:'0',infinityOffline:'0',muted:'1'}))localStorage.setItem('leqra.'+key,value);
   window.__projectileProbe={clock:1000,draws:[],lasers:0,queue:[],realNow:performance.now.bind(performance)};window.requestAnimationFrame=fn=>{__projectileProbe.queue.push(fn);return __projectileProbe.queue.length;};Object.defineProperty(performance,'now',{value:()=>__projectileProbe.clock});
  },'P'+run+suffix);
  const page=await context.newPage();page.on('pageerror',error=>errors.push(error.message));
  await page.route('**/*',async route=>{const request=route.request(),u=new URL(request.url());if(request.method()!=='GET')return route.continue();const file=u.pathname==='/'?path.join(web,'index.html'):u.pathname.startsWith(prefix)?path.join(web,u.pathname):'';if(!file||!fs.existsSync(file))return route.continue();let text=fs.readFileSync(file);
   if(file.endsWith('/game.js')){text=text.toString();const marker='window.leqraInfinityArt=Object.freeze({';if(!text.includes(marker))throw Error('Missing Canvas hook anchor');text=text.replace(marker,commonHooks+'\n'+marker);}
   if(file.endsWith('/infinite.js')){text=text.toString();const at=text.lastIndexOf('})();');text=text.slice(0,at)+infinityHooks+text.slice(at);}
   return route.fulfill({status:200,contentType:mime[path.extname(file)]||'application/octet-stream',body:text});
  });await page.goto(origin+'/?test=1');await page.waitForFunction(()=>window.__test&&window.__projectileProbe.infinityNetwork,null,{polling:20});return page;
 }
 try{
  for(const profile of profiles){
   if(!args.includes('--ui-only')){
   const page=await make(profile,profile.name[0]);
   const cold=await page.evaluate(()=>__projectileProbe.fixedOffline('regular')),warm=await page.evaluate(()=>Array.from({length:25},()=>__projectileProbe.fixedOffline('regular')).map(({fireMs,renderMs})=>({fireMs,renderMs})));
   measurements.push({profile:profile.name,scope:'Muted real Chromium JS fire and Canvas submission CPU only; deterministic playback clock, not display FPS',cold:{fireMs:cold.fireMs,renderMs:cold.renderMs},warm});
   for(const arena of ['fixed','infinity']){
    for(const kind of [...kinds,'laser']){
     const result=await page.evaluate(({arena,kind})=>__projectileProbe[arena+'Offline'](kind),{arena,kind});
     check(result.dead&&(kind==='laser'?result.lasers>0:result.draws.some(b=>b.kind===kind)),profile.name+' '+arena+' offline '+kind+' muzzle kill is actually drawn');
     check(result.expired,profile.name+' '+arena+' '+kind+' minimum visibility expires');measurements.push({profile:profile.name,arena,kind,scope:'cold-or-warmed-in-this-page JS fire and Canvas submission CPU; no physical FPS claim',fireMs:result.fireMs,renderMs:result.renderMs});
    }
    for(const ping of [50,150,400])for(const kind of [...kinds,'laser']){
     const result=await page.evaluate(({arena,kind,ping})=>__projectileProbe[arena+'Network'](kind,ping),{arena,kind,ping});
     check(kind==='laser'?result.lasers>0:result.draws.some(b=>b.id===77&&b.kind===kind),profile.name+' '+arena+' '+ping+'ms synthetic arrival '+kind+' between-snapshot hit is drawn');
    }
    for(const kind of kinds){const result=await page.evaluate(({arena,kind})=>__projectileProbe[arena+'Network'](kind,150,false,true),{arena,kind});check(result.draws.some(b=>b.id===77&&b.kind===kind),profile.name+' '+arena+' '+kind+' published shell survives newest removal until playback');}
    const final=await page.evaluate(arena=>__projectileProbe[arena+'Network']('cannon',400,true),arena);check(final.draws.some(b=>b.id===77)&&!final.covered,profile.name+' '+arena+' round-ending cannon remains visible before result modal');
   }
   await page.screenshot({path:path.join(out,profile.name+'-projectiles.png')});await page.context().close();
   }
   const ui=await make(profile,profile.name[0]+'U');await ui.evaluate(()=>__test.setLocalRules({...__test.defaultRoomRules(),infinity:true,infinityRandomBots:true}));
   let rectangle;
   for(const rate of [.5,1,2,4]){
    await ui.evaluate(()=>document.getElementById('roomRulesBtn').click());await ui.locator('#rule-infinityBotSpawnRate').selectOption(String(rate));
    const rect=await ui.locator('#rule-infinityBotSpawnRate').boundingBox();if(rectangle)check(Math.abs(rect.height-rectangle.height)<.2&&Math.abs(rect.width-rectangle.width)<.2,profile.name+' '+rate+'x rate retains field size');rectangle=rect;
    await ui.locator('#applyRulesBtn').click();check(await ui.evaluate(rate=>__test.currentRules().infinityBotSpawnRate===rate&&__test.snapshotPreset().rules.infinityBotSpawnRate===rate,rate),profile.name+' '+rate+'x rate saves to room and preset');
   }
   await ui.reload();await ui.waitForFunction(()=>window.__test,null,{polling:20});check(await ui.evaluate(()=>__test.currentRules().infinityBotSpawnRate===4),profile.name+' local spawn rate survives reload');
   await ui.locator('#copyInviteBtn').click();await ui.waitForFunction(()=>__test.online.connected&&__test.phase==='onlineLobby',null,{polling:20});
   for(const rate of [.5,1,2,4]){await ui.evaluate(()=>document.getElementById('roomRulesBtn').click());await ui.locator('#rule-infinityBotSpawnRate').selectOption(String(rate));await ui.locator('#applyRulesBtn').click();await ui.waitForFunction(rate=>__test.online.roomData?.rules.infinityBotSpawnRate===rate,rate,{polling:20});check(true,profile.name+' '+rate+'x rate roundtrips through Go host-owned rules');}
   await ui.evaluate(()=>{document.getElementById('roomRulesBtn').click();document.getElementById('rule-infinityBotSpawnRate').scrollIntoView({block:'center'});});
   const visibleRate=await ui.locator('#rule-infinityBotSpawnRate').evaluate(node=>{const c=document.createElement('canvas').getContext('2d'),s=getComputedStyle(node),r=node.getBoundingClientRect();c.font=s.font;return{fits:c.measureText(node.selectedOptions[0].textContent).width+parseFloat(s.paddingLeft)+parseFloat(s.paddingRight)<=r.width,y:r.y,bottom:r.bottom};});
   check(visibleRate.fits&&visibleRate.y>=0&&visibleRate.bottom<=profile.height,profile.name+' full selected rate and interval fit visibly');
   await ui.screenshot({path:path.join(out,profile.name+'-spawn-rate.png'),fullPage:true});await ui.locator('#defaultRulesBtn').click();check(await ui.locator('#rule-infinityBotSpawnRate').inputValue()==='2',profile.name+' Defaults restores doubled cadence');await ui.screenshot({path:path.join(out,profile.name+'-spawn-defaults.png'),fullPage:true});await ui.locator('#applyRulesBtn').click();await ui.waitForFunction(()=>__test.online.roomData?.rules.infinityBotSpawnRate===2,null,{polling:20});await ui.context().close();
  }
  check(errors.length===0,'No browser JavaScript errors');
 }catch(error){errors.push(error.message);process.exitCode=1;}
 finally{for(const context of contexts)await context.close().catch(()=>{});await browser.close();fs.writeFileSync(path.join(out,'report.json'),JSON.stringify({checks,measurements,errors},null,2));console.log(JSON.stringify({checks:checks.length,errors,output:out}));}
})();
