'use strict';
// Actual browser/Canvas rendering with controlled production RAF timestamps.
// These are motion-cadence measurements, not physical display FPS claims.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const {execFileSync}=require('node:child_process'),{chromium}=require('playwright');
const {assetPath,assetVersion}=require('./web_assets.cjs');
const root=path.resolve(__dirname,'../..'),web=path.join(root,'src/web');
const output=path.resolve(process.argv[2]||'/tmp/leqra-speed-motion-browser');
const baseline=process.argv.find(arg=>arg.startsWith('--baseline='))?.slice(11)||'HEAD';
fs.mkdirSync(output,{recursive:true});

const fixedHooks=String.raw`
window.__motion.fixed=function(kind){
 window.leqraInfinity?.close();this.arena='fixed';this.kind=kind;
 let seed=44938;Math.random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
 mode='room';localRoom.rules=validateRoomRules({...defaultRoomRules(),infinity:false,mode:'elimination',mapSize:'ultrawide',teamMode:'ffa',timeLimit:600});
 localRoom.players=[0,1].map(id=>({id,member:id+1,kind:'human',name:id?'CO-PILOT':'PILOT',owner:0,team:0,colorIndex:id}));
 startMatch();phase='playing';time=0;spawnClock=1e9;pickups=[];bullets=[];
 for(const t of tanks)Object.assign(t,{x:420+t.id*1800,y:420,angle:0,track:0,human:true,localIndex:t.id,invulnerable:1e6,spawnProtected:false,ghostTime:1e6,starmanTime:1e6,speedTime:1e6,speedStacks:5});
 window.__test.setWorld({width:3360,height:840,cols:40,rows:10,walls:[]});mapCanvas=null;wallIndex=null;
 clearInput();lastFrame=performance.now();accumulator=0;
 this.beforeFrame=()=>{keys.clear();stick.mag=0;stick.x=stick.y=0;stick.assisted=false;
  if(kind==='keyboard'){keys.add('KeyW');keys.add('KeyD');}else{const a=this.clock/1000*6;Object.assign(stick,{x:Math.cos(a),y:Math.sin(a),mag:1,assisted:true});}};
 this.read=()=>({pose:this.pose,authority:{x:tanks[0].x,y:tanks[0].y,angle:tanks[0].angle}});
};
const motionDrawTank=drawTank;drawTank=function(t,...args){if(window.__motion.arena==='fixed'&&t.id===0)window.__motion.pose={x:t.x,y:t.y,angle:t.angle};return motionDrawTank(t,...args);};
`;
const infinityHooks=String.raw`
window.__motion.infinity=function(kind){
 window.leqraInfinity.close();this.arena='infinity';this.kind=kind;
 window.leqraInfinity.start('offline',{name:'PILOT',roomRules:{infinity:true,infinityRandomBots:false,teamMode:'ffa'}});
 const w=session;w.maze=geometry.create(44938);w.nextPickup=1e9;w.pickups=[];w.bullets=[];w.time=0;
 const t=makeTank(w.id,420,420,false);Object.assign(t,{angle:0,track:0,invulnerable:1e6,spawnProtected:false,ghostTime:1e6,starmanTime:1e6,speedTime:1e6,speedStacks:5});w.tanks=[t];
 resetControls();lastTime=performance.now();accumulator=0;
 this.beforeFrame=()=>{pressed.clear();Object.assign(touchAim,{x:0,y:0,assisted:false});mouseAim=null;
  if(kind==='keyboard'){pressed.add('KeyW');pressed.add('KeyD');}else{const a=this.clock/1000*6;Object.assign(touchAim,{x:Math.cos(a),y:Math.sin(a),assisted:true});}};
 this.read=()=>({pose:{x:w.camera.x,y:w.camera.y,angle:w.display?.angle??w.tanks[0].angle},authority:{x:w.tanks[0].x,y:w.tanks[0].y,angle:w.tanks[0].angle}});
};
`;
function source(name,variant){
 let text=variant==='before'?execFileSync('git',['show',baseline+':'+path.relative(root,assetPath(name))],{cwd:root,encoding:'utf8'}):fs.readFileSync(assetPath(name),'utf8');
 if(name==='game.js'){
  const marker="if(new URLSearchParams(location.search).has('test'))window.__test=";
  assert.ok(text.includes(marker));text=text.replace(marker,fixedHooks+'\n'+marker);
 }
 if(name==='infinite.js'){
  const marker='window.leqraInfinity =';assert.ok(text.includes(marker));text=text.replace(marker,infinityHooks+'\n'+marker);
 }
 return text;
}
function distribution(values){const sorted=[...values].sort((a,b)=>a-b);return{mean:values.reduce((a,b)=>a+b,0)/values.length,p95:sorted[Math.floor((sorted.length-1)*.95)],max:sorted.at(-1)};}
function metrics(samples){
 const speed=[],acceleration=[],jerk=[];let previous,velocity,accel,stalled=0;
 for(const frame of samples){
  if(previous){const dt=frame.at-previous.at,dx=frame.x-previous.x,dy=frame.y-previous.y,v={x:dx/dt,y:dy/dt,at:(frame.at+previous.at)/2};
   if(Math.hypot(dx,dy)<1e-7)stalled++;speed.push(Math.hypot(v.x,v.y));
   if(velocity){const span=v.at-velocity.at,a={x:(v.x-velocity.x)/span,y:(v.y-velocity.y)/span,at:(v.at+velocity.at)/2};acceleration.push(Math.hypot(a.x,a.y));if(accel)jerk.push(Math.hypot(a.x-accel.x,a.y-accel.y)/(a.at-accel.at));accel=a;}velocity=v;
  }previous=frame;
 }
 return{frames:samples.length,stalled,speed:distribution(speed),acceleration:distribution(acceleration),jerk:distribution(jerk)};
}

(async()=>{
 const served=new Map();for(const variant of ['before','after'])for(const name of ['game.js','infinite.js','netcode.js'])served.set(variant+'/'+name,source(name,variant));
 const server=http.createServer((request,response)=>{
  const url=new URL(request.url,'http://localhost'),variant=url.searchParams.get('variant')||request.headers.cookie?.match(/variant=(before|after)/)?.[1]||'after';
  if(url.pathname==='/'){response.setHeader('Set-Cookie','variant='+variant+'; SameSite=Lax');response.setHeader('Content-Type','text/html');response.end(fs.readFileSync(path.join(web,'index.html')));return;}
  if(url.pathname==='/healthz'){response.end('ok');return;}
  if(url.pathname==='/api/infinity'){response.setHeader('Content-Type','application/json');response.end('{"players":0,"tankCount":0,"capacity":64,"leaders":[]}');return;}
  const file=path.resolve(web,'.'+url.pathname);if(!file.startsWith(web+path.sep)){response.writeHead(403).end();return;}
  const name=path.basename(file);if(url.pathname===`/assets/${assetVersion}/${name}`&&served.has(variant+'/'+name)){response.setHeader('Content-Type','application/javascript');response.end(served.get(variant+'/'+name));return;}
  if(!fs.existsSync(file)){response.writeHead(404).end();return;}
  response.setHeader('Content-Type',({'.js':'application/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.webmanifest':'application/manifest+json'})[path.extname(file)]||'application/octet-stream');response.end(fs.readFileSync(file));
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 let browser;try{browser=await chromium.launch({headless:true});}catch(error){server.close();throw error;}
 const results=[],errors=[];
 try{
  for(const variant of ['before','after'])for(const arena of ['fixed','infinity'])for(const control of ['keyboard','touch'])for(const cadence of ['60','120','144','variable']){
   const context=await browser.newContext({viewport:{width:390,height:844},deviceScaleFactor:3,isMobile:true,hasTouch:true,serviceWorkers:'block'});
   await context.addInitScript(()=>{
    localStorage.setItem('leqra.introTour.v1','1');localStorage.setItem('leqra.muted','1');
    window.__motion={clock:1000,queue:[],pose:null};
    window.requestAnimationFrame=fn=>{__motion.queue.push(fn);return __motion.queue.length;};
    Object.defineProperty(performance,'now',{value:()=>__motion.clock});
   });
   const page=await context.newPage();page.on('pageerror',error=>errors.push({variant,arena,control,cadence,message:error.message}));
   await page.goto('http://127.0.0.1:'+server.address().port+'/?test=1&variant='+variant);
   await page.waitForFunction(()=>window.__test&&window.__motion.infinity);
   const raw=await page.evaluate(({arena,control,cadence})=>{
    const m=window.__motion;m[arena](control);const samples=[],intervals=cadence==='variable'?[1/144,1/90,1/120,1/75,1/120]:[1/Number(cadence)];
    for(let i=0;i<480;i++){
     const dt=intervals[i%intervals.length];m.clock+=dt*1000;m.beforeFrame();
     const pending=m.queue;m.queue=[];for(const callback of pending)callback(m.clock);
     const state=m.read();if(i>=120)samples.push({...state.pose,dt,at:m.clock/1000});
    }
    return{samples,end:m.read().authority};
   },{arena,control,cadence});
   assert.ok(raw.samples.every(p=>Number.isFinite(p.x)&&Number.isFinite(p.y)),'missing rendered motion '+JSON.stringify({variant,arena,control,cadence}));
   const record={variant,arena,control,cadence,...metrics(raw.samples),authority:raw.end};results.push(record);
   if(variant==='after'&&cadence==='144')await page.screenshot({path:path.join(output,arena+'-'+control+'.png')});
   console.log(JSON.stringify(record));await context.close();
  }
  assert.deepEqual(errors,[],'browser runtime errors');
  const comparisons=results.filter(r=>r.variant==='after').map(after=>{
   const before=results.find(r=>r.variant==='before'&&r.arena===after.arena&&r.control===after.control&&r.cadence===after.cadence);
   for(const key of ['x','y','angle'])assert.ok(Math.abs(after.authority[key]-before.authority[key])<1e-7,'presentation changed simulation: '+JSON.stringify({before,after}));
   if(Number(after.cadence)>60||after.cadence==='variable')assert.equal(after.stalled,0,'unexpected repeated moving pose');
   return{arena:after.arena,control:after.control,cadence:after.cadence,before,after};
  });
  fs.writeFileSync(path.join(output,'report.json'),JSON.stringify({environment:'macOS headless Chromium, real production RAF callbacks/Canvas2D/DOM with controlled 60/120/144/variable timestamps. Speed5+Ghost isolates free movement. No physical display FPS or Safari claim.',baseline,comparisons,errors},null,2));
 }finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
