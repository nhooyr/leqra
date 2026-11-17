'use strict';
// Optional phone/tablet HUD regression against a disposable loopback server.
// node src/tests/local_p2_layout_browser.cjs http://127.0.0.1:8080 --browser=chromium
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {chromium,webkit}=require('playwright');
const address=process.argv.find(value=>/^https?:/.test(value))||'http://127.0.0.1:8080';
const url=new URL(address);assert.ok(['127.0.0.1','localhost','[::1]'].includes(url.hostname),'Use a disposable loopback server.');url.searchParams.set('test','1');
const output=process.env.LEQRA_BROWSER_OUTPUT||fs.mkdtempSync(path.join(os.tmpdir(),'leqra-p2-layout-'));
fs.mkdirSync(output,{recursive:true});
const selected=process.argv.find(value=>value.startsWith('--browser='))?.split('=')[1];
const widthFilter=Number(process.argv.find(value=>value.startsWith('--width='))?.split('=')[1]);
const profiles=[[320,568],[390,844],[568,320],[844,390],[768,1024],[1024,768]].filter(([width])=>!widthFilter||widthFilter===width);
const names=['WIDE PILOT ALPHA','WIDE PILOT BRAVO'];
const errors=[];
async function checkHUD(page,arena,variant,label){
 const data=await page.evaluate(({arena,variant,names})=>{
  const T=window.__test,ids=arena==='fixed'?['pilotLoadout1','pilotLoadout2']:['infinitePilotLoadout1','infiniteLocalLoadout'];
  const pilots=T.tanks.filter(tank=>tank.human).slice(0,2);
  for(const [index,tank]of pilots.entries()){
   Object.assign(tank,{name:names[index],alive:true,power:variant==='machine'?'rapid':'scatter',powerTime:10,charges:10,machineRounds:90,shield:10,shieldCharges:5,speedTime:10,speedStacks:5,ghostTime:10,starmanTime:0,cooldown:.6,cooldownTotal:.8,invulnerable:0,spawnProtected:false});
   T.setPilotFeedback(index,'',0);
  }
  if(arena==='fixed'){T.updateHUD(true);T.updateCombatFeedback(true);}
  else for(const [index,tank]of pilots.entries())window.leqraInfinityArt.renderLoadout(tank,index+1,{ammo:0,grenades:0,grenadeLife:0,locked:true},false,'playing',true);
  const rect=e=>{const {left,top,right,bottom,width,height}=e.getBoundingClientRect();return{left,top,right,bottom,width,height};};
  return{width:innerWidth,height:innerHeight,bodyWidth:document.body.scrollWidth,version:rect(document.querySelector('#headerVersion')),versionText:document.querySelector('#headerVersion').textContent,
   captions:document.querySelector(arena==='fixed'?'#touchControls':'.infinite-touch-controls').innerText,
   stage:rect(document.querySelector(arena==='fixed'?'#arenaWrap':'.infinite-stage')),
   panels:ids.map(id=>{const panel=document.getElementById(id),name=panel.querySelector('.loadout-name');return{rect:rect(panel),name:name.textContent,color:getComputedStyle(name).color,weight:getComputedStyle(name).fontWeight,
    text:[...panel.querySelectorAll('.loadout-name,.weapon,.buff-label,.cooldown-line>span,.lock-status,.firing-budget strong')].filter(e=>e.getClientRects().length&&getComputedStyle(e).visibility!=='hidden').map(e=>({text:e.textContent,rect:rect(e),font:parseFloat(getComputedStyle(e).fontSize),w:e.clientWidth,sw:e.scrollWidth,h:e.clientHeight,sh:e.scrollHeight}))};})};
 },{arena,variant,names});
 assert.ok(data.bodyWidth<=data.width+1,label+' page overflows');assert.ok(data.stage.height>30,label+' arena collapsed');
 assert.ok(data.versionText&&data.version.width>0&&data.version.height>0,label+' version hidden');
 assert.doesNotMatch(data.captions,/\b(STEER|FIRE|LET IT RIP)\b/,label+' touch captions returned');
 const [first,second]=data.panels;
 assert.ok(first.rect.right<=second.rect.left+1||first.rect.bottom<=second.rect.top+1,label+' local HUD panels overlap');
 assert.notEqual(first.color,second.color,label+' pilot colors lost');
 for(const [index,panel]of data.panels.entries()){
  assert.equal(panel.name,names[index]+' (P'+(index+1)+')',label+' identity');assert.ok(Number(panel.weight)>=700,label+' identity is not bold');
  assert.ok(panel.rect.left>=-1&&panel.rect.right<=data.width+1&&panel.rect.top>=0&&panel.rect.bottom<=data.height+1,label+' panel leaves viewport');
  assert.ok(panel.text.some(item=>item.text.includes('COOLDOWN')),label+' readiness missing');
  assert.ok(panel.text.some(item=>item.text.includes('SHD')&&item.text.includes('SPD')&&item.text.includes('GHO')),label+' buffs missing');
  for(const item of panel.text){assert.ok(item.font>=10,label+' tiny text '+item.text);assert.ok(item.sw<=item.w+1&&item.sh<=item.h+1,label+' clipped '+item.text);assert.ok(item.rect.left>=panel.rect.left-1&&item.rect.right<=panel.rect.right+1&&item.rect.top>=panel.rect.top-1&&item.rect.bottom<=panel.rect.bottom+1,label+' text outside pilot panel '+item.text);}
 }
 await page.screenshot({path:path.join(output,label.replace(/[^a-z0-9]+/gi,'-')+'.png')});
}
(async()=>{
 for(const [name,type]of Object.entries({chromium,webkit})){
  if(selected&&selected!==name)continue;
  const browser=await type.launch({headless:true});
  for(const [width,height]of profiles){
   const context=await browser.newContext({viewport:{width,height},hasTouch:true,isMobile:true,serviceWorkers:'block'});
   await context.addInitScript(()=>{localStorage.setItem('leqra.introTour.v1','1');localStorage.setItem('leqra.infinityOnline','0');localStorage.setItem('leqra.infinityOffline','0');localStorage.setItem('leqra.name','WIDE PILOT ALPHA');localStorage.setItem('leqra.local2Name','WIDE PILOT BRAVO');});
   const page=await context.newPage();page.on('pageerror',error=>errors.push(name+' '+error.message));await page.goto(url.href);await page.waitForFunction(()=>window.__test);
   await page.evaluate(names=>{window.requestAnimationFrame=()=>0;const T=__test;T.addRoomSeat('local');for(const player of T.localRoom.players)if(player.kind==='human'||player.kind==='local')player.name=names[player.kind==='local'?1:0];document.querySelector('#startRoomBtn').click();T.setPhase('playing');},names);
   for(const variant of ['equipment','machine'])await checkHUD(page,'fixed',variant,name+' '+width+'x'+height+' fixed '+variant);
   await page.evaluate(names=>window.leqraInfinity.start('offline',{name:names[0],localName:names[1],roomRules:{infinityRandomBots:false}}),names);
   for(const variant of ['equipment','machine'])await checkHUD(page,'infinite',variant,name+' '+width+'x'+height+' infinite '+variant);
   await context.close();console.log('PASS '+name+' '+width+'x'+height+' two-pilot fixed/Infinity HUD');
  }
  await browser.close();
 }
 assert.deepEqual(errors,[]);console.log('Screenshots: '+output);
})().catch(error=>{console.error(error);process.exitCode=1;});
