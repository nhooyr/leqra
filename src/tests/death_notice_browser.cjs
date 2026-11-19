'use strict';
// Current-source layout checks. The disposable server only listens on loopback.
// node src/tests/death_notice_browser.cjs [output-directory]
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const playwright=require('playwright'),{assetPath}=require('./web_assets.cjs');
const web=path.resolve(__dirname,'../web'),output=path.resolve(process.argv[2]||'/tmp/leqra-death-notice-browser');
fs.mkdirSync(output,{recursive:true});
const killer='A very long killer callsign with 雪 and <literal> text';
const fixed=String.raw`
window.__deathFixed=(paired,small)=>{
 window.leqraInfinity.close();mode='room';localRoom.rules=validateRoomRules({...defaultRoomRules(),infinity:false,pickupRate:'off'});
 localRoom.players=[{id:0,member:1,kind:'human',name:'Victim',team:0,colorIndex:0},...(paired?[{id:1,member:1,kind:'local',owner:0,name:'Wing',team:0,colorIndex:1}]:[]),{id:2,member:2,kind:'bot',name:'Witness',team:0,colorIndex:5}];
 startMatch();phase='playing';time=1;accumulator=0;pickups=[];bullets=[];clearInput();
 __test.setWorld({width:small?336:840,height:small?336:840,cols:small?4:10,rows:small?4:10,walls:[]});mapCanvas=null;wallIndex=null;
 for(const t of tanks)Object.assign(t,{x:W/2+(t.id===2?60:0),y:H/2,alive:t.id===2,killedBy:__deathKiller,killedByColor:COLORS[5]});
 document.body.classList.toggle('two-local-pilots',paired);$('announcer').hidden=true;updateHUD(true);
 renderDeathNotice(tanks.find(t=>t.id===0),1,paired);renderDeathNotice(paired?tanks.find(t=>t.id===1):null,2,paired);
 __deathLabels.length=0;render();
};
`;
const infinite=String.raw`
window.__deathInfinity=paired=>{
 window.leqraInfinity.close();window.leqraInfinity.start('offline',{name:'Victim',localName:paired?'Wing':'',roomRules:{infinity:true,infinityRandomBots:false,pickupRate:'off'}});
 const w=session;w.nextBot=w.nextPickup=Infinity;w.pickups=[];w.bullets=[];w.time=1;
 for(const t of w.tanks)Object.assign(t,{hp:0,alive:false,killedBy:__deathKiller,killedByColor:COLORS[5]});
 const first=w.tanks[0];w.tanks.push({...first,id:99,name:'Witness',hp:1,alive:true,colorIndex:5,x:first.x+60});
 w.nextHUD=0;__deathLabels.length=0;draw(w,performance.now(),0);
};
`;
const scripts=new Map([
 ['game.js',fs.readFileSync(assetPath('game.js'),'utf8').replace('window.leqraInfinityArt=Object.freeze({',fixed+'\nwindow.leqraInfinityArt=Object.freeze({')],
 ['infinite.js',fs.readFileSync(assetPath('infinite.js'),'utf8').replace('window.leqraInfinity =',infinite+'\nwindow.leqraInfinity =')],
]);
const server=http.createServer((req,res)=>{
 const url=new URL(req.url,'http://localhost'),file=path.resolve(web,'.'+(url.pathname==='/'?'/index.html':url.pathname));
 if(url.pathname.startsWith('/api/')){res.setHeader('Content-Type','application/json');res.end('{"players":0,"tankCount":0,"capacity":64,"leaders":[]}');return;}
 if(!file.startsWith(web+path.sep)||!fs.existsSync(file)){res.writeHead(404).end();return;}
 res.setHeader('Content-Type',({'.js':'application/javascript','.html':'text/html','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.webmanifest':'application/manifest+json'})[path.extname(file)]||'application/octet-stream');
 res.end(scripts.get(path.basename(file))||fs.readFileSync(file));
});
(async()=>{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const results=[];
 try{
  for(const engine of ['chromium','webkit']){
   const browser=await playwright[engine].launch();
   try{for(const profile of [{name:'desktop',width:1280,height:900},{name:'iphone',width:390,height:844,touch:true},{name:'android',width:412,height:915,touch:true},{name:'landscape',width:844,height:390,touch:true}]){
    const context=await browser.newContext({viewport:{width:profile.width,height:profile.height},isMobile:!!profile.touch,hasTouch:!!profile.touch,serviceWorkers:'block'});
    try{
     await context.addInitScript(killer=>{
      localStorage.setItem('leqra.introTour.v1','1');window.requestAnimationFrame=()=>0;window.cancelAnimationFrame=()=>{};
      window.__deathKiller=killer;window.__deathLabels=[];
      const original=CanvasRenderingContext2D.prototype.fillText;
      CanvasRenderingContext2D.prototype.fillText=function(text,...args){
       if(String(text).includes('Witness')){const matrix=this.getTransform(),rect=this.canvas.getBoundingClientRect();window.__deathLabels.push({text,size:parseFloat(this.font.replace(/^(bold|normal) /,''))*Math.hypot(matrix.a,matrix.b)*rect.width/this.canvas.width});}
       return original.call(this,text,...args);
      };
     },killer);
     const page=await context.newPage(),errors=[];page.on('pageerror',error=>errors.push(String(error)));
     await page.goto('http://127.0.0.1:'+server.address().port+'/?test=1');
     await page.waitForFunction(()=>typeof __deathFixed==='function'&&typeof __deathInfinity==='function');
     for(const mode of ['fixed','fixed-small','infinity'])for(const paired of [false,true]){
      await page.evaluate(({mode,paired})=>mode==='infinity'?__deathInfinity(paired):__deathFixed(paired,mode==='fixed-small'),{mode,paired});
      const measurement=await page.evaluate(mode=>{
       const root=document.getElementById(mode==='infinity'?'infiniteArena':'arenaWrap');
       return {labels:__deathLabels,notices:[...root.querySelectorAll('.death-notice')].filter(n=>!n.hidden).map(n=>({text:n.textContent,size:parseFloat(getComputedStyle(n).fontSize),width:n.getBoundingClientRect().width,height:n.getBoundingClientRect().height,inside:n.getBoundingClientRect().left>=root.getBoundingClientRect().left&&n.getBoundingClientRect().right<=root.getBoundingClientRect().right,overflow:n.scrollWidth>n.clientWidth+1}))};
      },mode);
      assert.ok(measurement.labels.length,{engine,profile:profile.name,mode,paired,measurement});
      assert.equal(measurement.notices.length,paired?2:1,JSON.stringify({engine,profile:profile.name,mode,paired,measurement}));
      for(const notice of measurement.notices){
       assert.ok(Math.abs(notice.size-measurement.labels[0].size)<.05,JSON.stringify({engine,profile:profile.name,mode,paired,measurement}));
       assert.ok(notice.size>=10&&notice.inside&&!notice.overflow,JSON.stringify(notice));
       assert.equal(notice.text,'Killed by '+killer);assert.ok(notice.height>notice.size*2,'Long killer names wrap');
      }
      await page.screenshot({path:path.join(output,[engine,profile.name,mode,paired?'two':'one'].join('-')+'.png')});
      results.push({engine,profile:profile.name,mode,paired,...measurement});
     }
     assert.deepEqual(errors,[]);
    }finally{await context.close();}
   }}finally{await browser.close();}
  }
  fs.writeFileSync(path.join(output,'results.json'),JSON.stringify(results,null,2));console.log('PASS '+results.length+' browser layouts: matching text size, wrapping, and independent local notices.');
 }finally{await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
