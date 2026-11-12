'use strict';
// Real Canvas2D, DOM and WebAudio stress fixture; all staging hooks are injected
// into temporary served copies. No fixture controls ship in the game assets.
// node src/tests/powerup_stress_browser.cjs /tmp/leqra-powerup-browser
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),{execFileSync}=require('node:child_process');
const {chromium}=require('playwright'),{assetPath,assetVersion}=require('./web_assets.cjs');
const root=path.resolve(__dirname,'../..'),web=path.join(root,'src/web'),output=path.resolve(process.argv[2]||'/tmp/leqra-powerup-browser');
const only=process.argv.find(arg=>arg.startsWith('--only='))?.slice(7);
const variants=process.argv.find(arg=>arg.startsWith('--variant='))?.slice(10).split(',')||['before','after'];
const arenas=process.argv.find(arg=>arg.startsWith('--arena='))?.slice(8).split(',')||['fixed','infinity'];
const powers=['rapid','scatter','shield','homing','grenade','speed','laser','cannon','ghost','starman'];
const cases=[...powers.map(kind=>({name:kind,powers:[kind],grenade:kind==='grenade'})),...['regular','rapid','scatter','homing','grenade','laser','cannon'].map(kind=>({name:'stacked-'+kind,powers:[...Array(5).fill('shield'),...Array(5).fill('speed'),'ghost','starman',...(kind==='regular'?[]:[kind])],grenade:kind==='grenade'}))].filter(item=>!only||item.name===only);
fs.mkdirSync(output,{recursive:true});

const fixedHooks=String.raw`
window.__stress={capture:false,spec:null,frames:[],longTasks:[],renderMs:0,maxProjectiles:0,maxParticles:0,maxEffects:0,audioSources:0,held:false,
 reset(){this.frames=[];this.longTasks=[];this.maxProjectiles=this.maxParticles=this.maxEffects=this.audioSources=0;this.capture=true;},
 record(now,work){if(!this.capture)return;const infinity=$('infiniteArena').open,w=infinity?window.__stressInfinity?.world():null;this.frames.push({at:now,work,render:this.renderMs});this.maxProjectiles=Math.max(this.maxProjectiles,w?w.bullets.length:bullets.length);this.maxParticles=Math.max(this.maxParticles,w?0:particles.length);this.maxEffects=Math.max(this.maxEffects,w?w.visualEffects.length:traces.length+rings.length);},
 controls(clock,set){const held=!this.spec?.grenade||Math.floor(clock*4)%2===0;set.add('KeyW');set.add('KeyD');if(held)set.add('KeyQ');else set.delete('KeyQ');return held;},
 fixed(spec){window.leqraInfinity?.close();this.capture=false;this.spec=spec;this.arena='fixed';this.held=false;let seed=44937;Math.random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};mode='room';localRoom.rules=validateRoomRules({...defaultRoomRules(),infinity:false,mode:'elimination',mapSize:'ultrawide',teamMode:'ffa',timeLimit:600,scoreTarget:20});localRoom.players=Array.from({length:8},(_,id)=>({id,member:id+1,kind:id?'bot':'human',name:['PILOT','RUST','VAPOR','EMBER','NOVA','COMET','ONYX','BLITZ'][id],owner:0,team:0,colorIndex:id,difficulty:'normal'}));startMatch();phase='playing';time=0;spawnClock=1e9;pickups=[];for(const t of tanks){Object.assign(t,{x:(1+t.id%4*5+.5)*CELL,y:(1+Math.floor(t.id/4)*8+.5)*CELL,angle:t.id*Math.PI/4,human:true,localIndex:0,invulnerable:1000,spawnProtected:false,cooldown:0,ghostTime:0,starmanTime:0,power:null,powerTime:0,shield:0,shieldCharges:0,speedTime:0,speedStacks:0,fireHeld:false});for(const power of spec.powers)grantPower(t,power);}clearInput();initAudio();setArenaAudio(true);audio?.resume();updateHUD(true);return this.initial();},
 initial(){return{audio:audio?.state||'none',volume:audioVolume,canvas:{width:canvas.width,height:canvas.height},powers:tanks.map(t=>({power:t.power,shield:shieldCount(t),speed:speedCount(t),ghost:t.ghostTime,starman:t.starmanTime}))};},
 finish(){this.capture=false;return{frames:this.frames,longTasks:this.longTasks,maxProjectiles:this.maxProjectiles,maxParticles:this.maxParticles,maxEffects:this.maxEffects,audio:audio?.state||'none',audioEnabled:canPlayAudio(),audioSources:this.audioSources};}
};
window.__stress.verifyGameplay=function(){
 this.fixed({name:'checks',powers:[]});this.spec=null;clearInput();const passed=[],check=(value,label)=>{if(!value)throw Error(label);passed.push(label);};
 const a=tanks[0],b=tanks[1];for(const t of tanks.slice(2))t.alive=false;Object.assign(a,{x:100,y:210,angle:0,ghostTime:0,starmanTime:0,cooldown:0});Object.assign(b,{x:400,y:210,invulnerable:0,spawnProtected:false});
 window.__test.setWorld({width:8000,height:1000,cols:95,rows:12,walls:[{x:-4,y:-4,w:8008,h:8},{x:-4,y:996,w:8008,h:8},{x:-4,y:-4,w:8,h:1008},{x:7996,y:-4,w:8,h:1008}]});
 grantPower(a,'laser');grantPower(a,'starman');for(let i=0;i<5;i++)grantPower(b,'shield');
 for(let i=0;i<5;i++){time+=1/60;b.invulnerable=0;check(fireLaser(a)&&b.alive&&shieldCount(b)===4-i,'Shield absorbs laser hit '+(i+1));}
 time+=1/60;b.invulnerable=0;fireLaser(a);check(!b.alive,'sixth laser hit destroys an exhausted five-shield tank');
 Object.assign(a,{power:null,ghostTime:0,starmanTime:0,cooldown:0,x:100,y:210,angle:0,speedTime:0,speedStacks:0});for(let i=0;i<5;i++)grantPower(a,'speed');keys.add('KeyW');humanControl(a,1/60);keys.clear();check(Math.abs(a.x-100-128*(1+.65*5)/60)<1e-6,'five Speed stacks retain exact movement multiplier');
 walls.push({x:200,y:0,w:8,h:1000});wallIndex=null;a.x=180;moveTank(a,10,0);check(a.x<=183.01,'ordinary tank is blocked by the internal wall');a.x=180;grantPower(a,'ghost');moveTank(a,50,0);check(a.x>208,'Ghost moves through the internal wall');
 Object.assign(a,{x:100,y:210,ghostTime:0,starmanTime:0,cooldown:0,angle:0});bullets=[];grantPower(a,'cannon');check(fire(a),'Cannon launch succeeds');const shell=bullets[0];check(shell.life===5.3,'Cannon retains its 5.3-second lifetime');updateBullets(.1);check(!shell.dead&&shell.x>208&&shell.vx>0,'Cannon penetrates the internal wall');updateBullets(5.199);check(!shell.dead,'Cannon survives until its original lifetime');updateBullets(.001);check(shell.dead,'Cannon expires at 5.3 seconds');
 bullets=[];Object.assign(a,{x:100,y:210,cooldown:0,ghostTime:0,starmanTime:0});grantPower(a,'grenade');weaponControl(a,true,true);const grenade=bullets[0];check(grenade?.kind==='grenade'&&!grenade.dead,'fresh Grenade press launches');weaponControl(a,false,false);const count=rings.length;weaponControl(a,true,true);check(grenade.dead&&rings.length>count,'release then fresh Grenade press detonates with a blast visual');check(a.charges===2,'remote detonation does not spend another Grenade charge');
 return passed;
};
window.__stress.verifyCannonTrails=function(){
 const T=window.__test;if(!T.setCannonTrailCache)return[];const results=[];
 for(const ratio of [.5,1,2,3]){
  const paint=on=>{const image=document.createElement('canvas');image.width=image.height=1024;const c=image.getContext('2d');c.fillStyle='#0e171d';c.fillRect(0,0,1024,1024);c.setTransform(ratio,0,0,ratio,512,512);T.setCannonTrailCache(on);for(let id=0;id<16;id++){const angle=id*.63,ux=Math.cos(angle),uy=Math.sin(angle),x=id%4*45,y=Math.floor(id/4)*45,trail=Array.from({length:11},(_,i)=>({x:x-ux*9.4*(11-i),y:y-uy*9.4*(11-i)}));T.drawBullet({kind:'cannon',r:14,color:COLORS[id%8],x,y,trail},c,0,true);}return c.getImageData(0,0,1024,1024).data;};
  const original=paint(false),cached=paint(true);let energy=0,active=0,lightBefore=0,lightAfter=0,max=0;for(let i=0;i<original.length;i+=4){if(original[i]===14&&original[i+1]===23&&original[i+2]===29&&cached[i]===14&&cached[i+1]===23&&cached[i+2]===29)continue;active++;for(let k=0;k<3;k++){const d=original[i+k]-cached[i+k];energy+=d*d;max=Math.max(max,Math.abs(d));lightBefore+=original[i+k]-[14,23,29][k];lightAfter+=cached[i+k]-[14,23,29][k];}}const rms=Math.sqrt(energy/(active*3)),lightChange=Math.abs(lightAfter/lightBefore-1);results.push({ratio,rms,max,lightChange,activePixels:active});if(rms>3||lightChange>.01)throw Error('Cannon trail appearance changed: '+JSON.stringify(results));
 }
 T.setCannonTrailCache(true);return results;
};
const stressSample=sampleFrame;sampleFrame=function(now,work,...args){window.__stress.record(now,work);return stressSample(now,work,...args);};
const stressAudioSource=trackAudioSource;trackAudioSource=function(...args){if(window.__stress.capture)window.__stress.audioSources++;return stressAudioSource(...args);};
const stressRender=render;render=function(){const start=performance.now();const result=stressRender();window.__stress.renderMs=performance.now()-start;return result;};
const stressUpdate=update;update=function(dt){const s=window.__stress;if(s.spec&&s.arena==='fixed'){const held=s.controls(time,keys);if(held&&!s.held)for(const t of tanks)firePresses.add(t.id);s.held=held;}return stressUpdate(dt);};
try{new PerformanceObserver(list=>{if(window.__stress.capture)for(const entry of list.getEntries())window.__stress.longTasks.push(entry.duration);}).observe({type:'longtask'});}catch(_){}
`;
const infinityHooks=String.raw`
window.__stressInfinity={world:()=>session,prepare(spec){window.leqraInfinity.close();window.__stress.capture=false;window.__stress.spec=spec;window.__stress.arena='infinity';window.leqraInfinity.start('offline',{name:'PILOT',roomRules:{infinity:true,infinityRandomBots:false,teamMode:'ffa'}});const w=session;w.maze=geometry.create(44937);w.tanks=[];w.nextPickup=1e9;w.pickups=[];w.time=0;for(let id=0;id<8;id++){const t=makeTank(id?'stress-'+id:w.id,(id%4*2+.5)*CELL,(Math.floor(id/4)*2+.5)*CELL,false);Object.assign(t,{name:['PILOT','RUST','VAPOR','EMBER','NOVA','COMET','ONYX','BLITZ'][id],angle:id*Math.PI/4,colorIndex:id,invulnerable:1000,spawnProtected:false,cooldown:0});for(const power of spec.powers)art.grantPower(t,power,15,8);w.tanks.push(t);}w.camera.x=w.tanks[0].x;w.camera.y=w.tanks[0].y;resetControls();w.nextHUD=0;draw(w,performance.now(),0);return{audio:window.__stress.initial().audio,powers:w.tanks.map(t=>({power:t.power,shield:t.shieldCharges||0,speed:t.speedStacks||0,ghost:t.ghostTime,starman:t.starmanTime})),canvas:{width:canvas.width,height:canvas.height}};}};
const stressOfflineStep=offlineStep;offlineStep=function(w,dt){if(window.__stress.spec&&window.__stress.arena==='infinity')window.__stress.controls(w.time,pressed);return stressOfflineStep(w,dt);};
const stressDraw=draw;draw=function(...args){const start=performance.now();const result=stressDraw(...args);window.__stress.renderMs=performance.now()-start;return result;};
`;

function staged(name,variant){
 const source=variant==='before'?execFileSync('git',['show','HEAD:'+path.relative(root,assetPath(name))],{cwd:root,encoding:'utf8'}):fs.readFileSync(assetPath(name),'utf8');
 if(name==='game.js'){
  const marker="if(new URLSearchParams(location.search).has('test'))window.__test=";
  if(!source.includes(marker))throw Error('fixed fixture marker missing');
  return source.replace(marker,fixedHooks+'\n'+marker);
 }
 if(name==='infinite.js')return source.replace('window.leqraInfinity =',infinityHooks+'\nwindow.leqraInfinity =');
 return source;
}
function summary(values){if(!values.length)return null;const sorted=[...values].sort((a,b)=>a-b),at=p=>sorted[Math.min(sorted.length-1,Math.floor(sorted.length*p))];return{samples:values.length,mean:values.reduce((a,b)=>a+b)/values.length,p50:at(.5),p95:at(.95),p99:at(.99),max:sorted.at(-1)};}

(async()=>{
 const served=new Map();for(const variant of ['before','after'])for(const name of ['game.js','infinite.js'])served.set(variant+'/'+name,staged(name,variant));
 const server=http.createServer((request,response)=>{
  const url=new URL(request.url,'http://localhost'),variant=url.searchParams.get('variant')||request.headers.cookie?.match(/variant=(before|after)/)?.[1]||'after';
  if(url.pathname==='/'){response.setHeader('Set-Cookie','variant='+variant+'; SameSite=Lax');response.setHeader('Content-Type','text/html');response.end(fs.readFileSync(path.join(web,'index.html')));return;}
  if(url.pathname==='/healthz'){response.end('ok');return;}
  if(url.pathname==='/api/infinity'){response.setHeader('Content-Type','application/json');response.end(JSON.stringify({players:0,tankCount:0,capacity:64,leaders:[]}));return;}
  const file=path.resolve(web,'.'+url.pathname);if(!file.startsWith(web+path.sep)){response.writeHead(403).end();return;}
  const name=path.basename(file);if(url.pathname===`/assets/${assetVersion}/${name}`&&served.has(variant+'/'+name)){response.setHeader('Content-Type','application/javascript');response.end(served.get(variant+'/'+name));return;}
  if(!fs.existsSync(file)){response.writeHead(404).end();return;}
  const ext=path.extname(file);response.setHeader('Content-Type',({'.js':'application/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.webmanifest':'application/manifest+json'})[ext]||'application/octet-stream');response.end(fs.readFileSync(file));
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const origin='http://127.0.0.1:'+server.address().port;
 let browser;try{browser=await chromium.launch({headless:true,args:['--autoplay-policy=no-user-gesture-required']});}catch(error){server.close();throw error;}
 const results=[],errors=[],validations=[];
 try{
  for(const variant of variants){
   const context=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:3,isMobile:true,hasTouch:true,serviceWorkers:'block'});
   await context.addInitScript(()=>{localStorage.setItem('leqra.introTour.v1','1');localStorage.setItem('leqra.muted','0');localStorage.setItem('leqra.volume','50');localStorage.setItem('leqra.feedback.v1',JSON.stringify({fps:true}));});
   const page=await context.newPage();page.on('pageerror',error=>errors.push({variant,message:error.message}));
   await page.goto(origin+'/?test=1&variant='+variant);await page.waitForFunction(()=>window.__test&&window.__stressInfinity);
   await page.locator('#soundBtn').click();await page.evaluate(()=>{if(document.querySelector('#soundBtn').getAttribute('aria-pressed')==='false')document.querySelector('#soundBtn').click();__test.initAudio();});
   const cdp=await context.newCDPSession(page);await cdp.send('Performance.enable');
   for(const arena of arenas)for(const spec of cases){
    const initial=await page.evaluate(({arena,spec})=>arena==='fixed'?__stress.fixed(spec):__stressInfinity.prepare(spec),{arena,spec});
    const weapon=spec.powers.filter(power=>['rapid','scatter','homing','grenade','laser','cannon'].includes(power)).at(-1)||'';
    if(initial.powers.length!==8||initial.powers.some(tank=>(tank.power||'')!==weapon||tank.shield!==Math.min(5,spec.powers.filter(power=>power==='shield').length)||tank.speed!==Math.min(5,spec.powers.filter(power=>power==='speed').length)||spec.powers.includes('ghost')&&!(tank.ghost>0)||spec.powers.includes('starman')&&!(tank.starman>0)))throw Error('Power fixture failed: '+JSON.stringify({arena,spec,initial}));
    await page.waitForTimeout(spec.name.startsWith('stacked-')?2000:250);
    await page.evaluate(()=>{__test.initAudio();__stress.reset();});
    const before=(await cdp.send('Performance.getMetrics')).metrics;
    await page.waitForTimeout(spec.name.startsWith('stacked-')?2000:1250);
    const after=(await cdp.send('Performance.getMetrics')).metrics;
    const raw=await page.evaluate(()=>__stress.finish()),intervals=raw.frames.slice(1).map((frame,index)=>frame.at-raw.frames[index].at);
    const metric=name=>(after.find(m=>m.name===name)?.value||0)-(before.find(m=>m.name===name)?.value||0);
    const record={variant,arena,case:spec.name,initial,frames:summary(intervals),frameWorkMs:summary(raw.frames.map(frame=>frame.work)),renderSubmissionMs:summary(raw.frames.map(frame=>frame.render)),over25ms:intervals.filter(value=>value>25).length,longTasks:raw.longTasks,maxProjectiles:raw.maxProjectiles,maxParticles:raw.maxParticles,maxEffects:raw.maxEffects,audio:raw.audio,audioSources:raw.audioSources,scriptSeconds:metric('ScriptDuration'),taskSeconds:metric('TaskDuration'),layoutSeconds:metric('LayoutDuration')};
    if(raw.frames.length<30)throw Error('Insufficient actual animation frames: '+arena+'/'+spec.name);
    if(raw.audio!=='running'||!raw.audioEnabled||!raw.audioSources)throw Error('WebAudio did not render active sources: '+JSON.stringify(record));
    results.push(record);fs.writeFileSync(path.join(output,'report.json'),JSON.stringify({browser:browser.version(),environment:'Headless Chromium, macOS, mobile touch 390×844 DPR3. Actual production RAF, Canvas2D, DOM and running WebAudio. Frames are 60Hz headless scheduling; no iPhone/Safari/ProMotion FPS claim. Protected tanks sustain deterministic load. Test-only seeded 8-pilot inputs move/rotate/fire; grenade inputs alternate press/release/detonate. Before=HEAD game assets, after=working tree; current HTML/CSS/PWA are shared.',results,validations,errors},null,2));
    console.log(JSON.stringify({variant,arena,case:spec.name,frames:record.frames.samples,frameP95:record.frames.p95,workP95:record.frameWorkMs.p95,renderP95:record.renderSubmissionMs.p95,projectiles:record.maxProjectiles,audio:raw.audio}));
    if(spec.name==='stacked-laser')await page.screenshot({path:path.join(output,variant+'-'+arena+'-stacked-laser.png')});
   }
   validations.push({variant,checks:await page.evaluate(()=>__stress.verifyGameplay()),cannonTrailPixels:await page.evaluate(()=>__stress.verifyCannonTrails())});
   await context.close();
  }
  const report=JSON.parse(fs.readFileSync(path.join(output,'report.json'),'utf8'));report.validations=validations;report.errors=errors;fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));
  if(errors.length)throw Error('Browser runtime errors: '+JSON.stringify(errors));
 }finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
