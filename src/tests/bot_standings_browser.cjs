'use strict';
// Optional current-source Chromium regression; use an isolated loopback server.
// node src/tests/bot_standings_browser.cjs http://127.0.0.1:18139 --disposable
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const {chromium}=require('playwright'),{assetPath}=require('./web_assets.cjs');
const address=process.argv.find(a=>/^https?:/.test(a));assert.ok(address&&process.argv.includes('--disposable'),'Supply a disposable loopback backend and --disposable.');
const target=new URL(address);assert.ok(['localhost','127.0.0.1','[::1]'].includes(target.hostname)&&target.pathname==='/'&&!target.search&&!target.hash&&!target.username&&!target.password,'Only an uncredentialed loopback origin is allowed.');
const root=path.resolve(__dirname,'../..'),web=path.join(root,'src/web'),output=fs.mkdtempSync(path.join(os.tmpdir(),'leqra-bot-standings-browser-'));
const profiles=[{name:'desktop',width:1280,height:900,mobile:false},{name:'portrait',width:390,height:844,mobile:true},{name:'landscape',width:844,height:390,mobile:true}],checks=[],errors=[],records=[];
const check=(value,label)=>{assert.ok(value,label);checks.push(label);};
const entries=[
 {id:11,name:'Bot 1 - Dumb',difficulty:'dumb',bot:true,score:2147483647,colorIndex:0},
 {id:12,name:'Bot 2 - Medium',difficulty:'normal',bot:true,score:99999999,colorIndex:1},
 {id:13,name:'Bot 3 - Godlike',difficulty:'godlike',bot:true,score:1234567,colorIndex:2},
 {id:14,name:'RUST',difficulty:'hard',bot:true,score:12345,colorIndex:3},
 {id:15,name:'ABCDEFGHIJKLMNOP',difficulty:'easy',bot:true,score:1234,colorIndex:4},
 {id:2,name:'Godlike 1 - Normal',difficulty:'godlike',bot:false,score:999,colorIndex:5},
 {id:3,name:'UNBROKENLONGNAME',bot:false,score:123,colorIndex:6},
 {id:1,name:'Local Human',bot:false,score:12,colorIndex:7},
 ...Array.from({length:14},(_,i)=>({id:20+i,name:'Bot '+(20+i)+' - Dumb',difficulty:'dumb',bot:true,score:0,colorIndex:i%8})),
].map((e,i)=>({...e,rank:i+1}));
const gameHooks=String.raw`
window.__botStandings=Object.assign(window.__botStandings||{}, {
 rulesSetup(name,legacy=false){window.leqraInfinity.close();for(const d of document.querySelectorAll('dialog[open]'))d.close();mode='room';phase='menu';infinityOnline=false;infinityOffline=true;localRoom.self=0;localRoom.players=[{id:0,member:1,kind:'human',name,owner:0,team:0}];rememberCallsign(name);setLocalRules({...defaultRoomRules(),infinity:true,infinityRandomBots:true,...(legacy?{infinityBotDifficulty:'normal',infinityRandomDifficulty:true,infinityBotSpawnRate:2}:{infinityBotSpawnRates:{normal:2}})});setScreen('room');renderOnlineRoom();},
 rules(){return JSON.parse(JSON.stringify(currentRules()));},
 openRules(){openFeature('rules');},
 openPresets(){openFeature('presets');},
 publish(code){$('localRoomName').value=code;shareLocalRoom();},
 join(code,name){connectOnline({type:'join',code,name});},
 onlineRules(){return online.roomData?.rules;},
 onlineCode(){return online.connected&&online.roomData?.code||null;},
 preview(){window.leqraInfinity.close();mode='room';phase='menu';infinityOffline=false;infinityOnline=true;localRoom.rules={...defaultRoomRules(),infinity:false};setScreen('room');renderOnlineRoom();window.leqraInfinityPreview.sync();},
 roomPreview(){window.leqraInfinity.close();mode='room';phase='menu';infinityOnline=false;infinityOffline=false;localRoom.rules={...defaultRoomRules(),infinity:true};localRoom.players=[{id:0,member:1,kind:'human',name:'Room Pilot',team:0},{id:1,member:2,kind:'bot',name:'RUST',difficulty:'hard',team:0}];setScreen('room');renderOnlineRoom();window.leqraInfinityPreview.sync();}
});
`;
const infinityHooks=String.raw`
window.__botStandings.arena=function(entries,spectator,room){
 window.leqraInfinity.close();window.leqraInfinity.start('offline',{name:'Local Human',roomRules:{...window.__test.defaultRoomRules(),infinity:true,infinityRandomBots:false}});
 const w=session;w.online=true;w.public=!room;w.spectating=spectator;w.joined=false;w.room=room?{code:'PROBE',token:'fixture'}:null;w.sent=[];
 socket={readyState:WebSocket.OPEN,bufferedAmount:0,send:message=>w.sent.push(JSON.parse(message)),close(){}};const ws=socket;
 const recv=message=>receive(ws,{data:JSON.stringify(message)});
 recv({type:'welcome',id:spectator?0:1,seed:37,spectating:spectator,following:spectator?11:0});
 w.maze={wallsNear:()=>[],visitWalls:()=>false,blocked:()=>false};w.mapCache.clear();
 const tanks=entries.map((e,i)=>({...e,hp:1,alive:true,x:350+(i%4)*56,y:350+Math.floor(i/4)*56,angle:0,vx:0,vy:0,spawnSerial:1,power:'',invulnerable:0,spawnProtected:false}));
 recv({type:'state',tick:60,tanks,bullets:[],pickups:[],effects:[],players:3,leaderboard:entries,following:spectator?11:0});
 Object.assign(w.camera,{x:434,y:434});w.nextHUD=0;renderScores(w,w.tanks.find(t=>t.id===1));
 const labels=[],fillText=ctx.fillText;ctx.fillText=function(text,...args){labels.push({text:String(text),font:this.font});return fillText.call(this,text,...args);};
 draw(w,performance.now(),0);ctx.fillText=fillText;
 leaderboardPanel.open=true;syncScoreboardButton();
 return {labels,count:w.leaderboard.length};
};
window.__botStandings.sent=()=>session.sent;
window.__botStandings.identityLifecycle=()=>{
 window.leqraInfinity.close();window.leqraInfinity.start('offline',{name:'Local Human',roomRules:{...window.__test.defaultRoomRules(),infinity:true,infinityRandomBots:true,infinityBotSpawnRates:{dumb:2}}});
 const w=session,pilot=w.tanks[0],identities=[],checks=[],expect=(value,label)=>{if(!value)throw Error(label);checks.push(label);};
 w.nextPickup=Infinity;pilot.invulnerable=10000;w.maze={wallsNear:()=>[],visitWalls:()=>false,blocked:()=>false};
 for(const difficulty of BOT_LEVELS){
  w.rules={...w.rules,infinityRandomBots:true,infinityBotSpawnRates:{[difficulty]:2}};w.nextBot=0;offlineStep(w,STEP);
  const bot=w.tanks.find(t=>t.ambient);expect(bot?.difficulty===difficulty,'spawn '+difficulty);bot.score=10+identities.length;identities.push(bot);
  w.rules={...w.rules,infinityRandomBots:false};offlineStep(w,STEP);expect(w.botPool.includes(bot),'park '+difficulty);
 }
 expect(new Set(identities.map(b=>b.botNumber)).size===BOT_LEVELS.length,'unique numbers across tier pools');const allocated=w.lastBot;
 for(const bot of identities){
  const serial=bot.spawnSerial,score=bot.score;w.rules={...w.rules,infinityRandomBots:true,infinityBotSpawnRates:{[bot.difficulty]:2}};w.nextBot=0;offlineStep(w,STEP);
  expect(w.tanks.includes(bot)&&bot.spawnSerial===serial+1&&bot.score===score,'reuse same '+bot.difficulty+' identity and score');
  w.rules={...w.rules,infinityRandomBots:false};offlineStep(w,STEP);
 }
 expect(w.lastBot===allocated,'reuse allocates no replacement identities');
 const normal=identities.find(b=>b.difficulty==='normal');w.rules={...w.rules,infinityRandomBots:true,infinityBotSpawnRates:{normal:2}};w.nextBot=0;offlineStep(w,STEP);
 const serial=normal.spawnSerial;Object.assign(normal,{hp:0,alive:false,respawn:1});w.nextBot=Infinity;
 for(let i=0;i<30;i++)offlineStep(w,STEP);expect(w.tanks.includes(normal)&&normal.hp===0,'corpse retained for contact playback');
 for(let i=0;i<40;i++)offlineStep(w,STEP);expect(w.botPool.includes(normal)&&normal.spawnSerial===serial,'death waits for spawn opportunity');
 renderScores(w,pilot);leaderboardPanel.open=true;syncScoreboardButton();
 expect(identities.every(bot=>[...leaderboard.children].some(row=>row.querySelector('.leaderboard-name')?.textContent===bot.name&&Number(row.querySelector('.leaderboard-score')?.textContent)===bot.score)),'parked identities stay on leaderboard');
 w.nextBot=0;offlineStep(w,STEP);expect(w.tanks.includes(normal)&&normal.spawnSerial===serial+1,'matching tier returns same dead identity');
 return {checks,identities:identities.map(b=>({id:b.id,name:b.name,difficulty:b.difficulty,score:b.score,number:b.botNumber}))};
};
`;
function boot(){
 for(const [key,value]of Object.entries({'introTour.v1':'1',name:'Fixture Pilot',local2Name:'Fixture Wing',infinityOnline:'0',infinityOffline:'0',muted:'1'}))localStorage.setItem('leqra.'+key,value);
 window.requestAnimationFrame=()=>1;
}
async function pageFor(browser,profile){
 const context=await browser.newContext({viewport:{width:profile.width,height:profile.height},deviceScaleFactor:profile.mobile?2:1,isMobile:profile.mobile,hasTouch:profile.mobile,serviceWorkers:'block'});await context.addInitScript(boot);
 const page=await context.newPage();page.on('pageerror',error=>errors.push(error.message));
 await page.route('**/*',async route=>{
  const request=route.request(),url=new URL(request.url());if(request.method()!=='GET')return route.continue();
  if(url.pathname==='/api/infinity')return route.fulfill({json:{players:3,tankCount:entries.length,capacity:32,leaders:entries.slice(0,10)}});
  const file=url.pathname==='/'?path.join(web,'index.html'):path.resolve(web,'.'+url.pathname);
  if(!file.startsWith(web+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile())return route.continue();
  let body=fs.readFileSync(file);
  if(file===assetPath('game.js')){body=body.toString();const marker='window.leqraInfinityArt=Object.freeze({';assert.ok(body.includes(marker));body=body.replace(marker,gameHooks+'\n'+marker);}
  if(file===assetPath('infinite.js')){body=body.toString();const at=body.lastIndexOf('})();');assert.ok(at>0);body=body.slice(0,at)+infinityHooks+body.slice(at);}
  const mime={'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.webmanifest':'application/manifest+json'};
  await route.fulfill({status:200,contentType:mime[path.extname(file)]||'application/octet-stream',body});
 });
 await page.goto(target.origin+'/?test=1');await page.waitForFunction(()=>window.__botStandings?.arena&&window.__test,null,{polling:20});return page;
}
async function inspect(page,selector){return page.locator(selector).evaluate(list=>{
 const bounds=list.getBoundingClientRect(),panel=list.closest('details'),rect=panel.getBoundingClientRect();
 return {width:rect.width,scrollWidth:panel.scrollWidth,clientWidth:panel.clientWidth,listScroll:list.scrollWidth,listWidth:list.clientWidth,viewport:innerWidth,
 rows:[...list.children].map(row=>{const name=row.querySelector('.leaderboard-name'),badge=row.querySelector('.leaderboard-difficulty'),score=row.querySelector('.leaderboard-score'),identity=row.querySelector('.leaderboard-identity');return{name:name?.textContent,badge:badge?.textContent||'',score:score?.textContent,text:row.textContent,font:parseFloat(getComputedStyle(name).fontSize),badgeFont:badge?parseFloat(getComputedStyle(badge).fontSize):null,fontWeight:getComputedStyle(name).fontWeight,width:row.clientWidth,scrollWidth:row.scrollWidth,nameHeight:name.getBoundingClientRect().height,identityWidth:identity.getBoundingClientRect().width};})};
 });}
function validate(result,label,all){
 check(result.rows.length===(all?entries.length:10),label+' expected complete row count');
 for(const [i,row]of result.rows.entries()){
  const e=entries[i],expected=e.bot?(i<3?'Bot '+(i+1):i===3?'Bot Rust':i===4?'Bot Abcdefghijklmnop':e.name.replace(/ - Dumb$/,'')):e.id===1?(row.name.includes('(P1)')?row.name:e.name):e.name;
  check(row.name===expected,label+' name '+i+': '+row.name);
  check(row.badge===(e.bot?({easy:'EASY',normal:'MEDIUM',hard:'HARD'}[e.difficulty]||e.difficulty.toUpperCase()):''),label+' actual difficulty '+i);
  check(!/\bBOT\b/.test(row.badge),label+' no redundant BOT badge '+i);
  check(row.font>=10&&(!row.badgeFont||row.badgeFont>=10),label+' minimum font '+i);
  check(row.scrollWidth<=row.width+1,label+' row fits horizontally '+i+': '+JSON.stringify(row));
 }
 check(result.scrollWidth<=result.clientWidth+1,label+' panel has no horizontal overflow '+JSON.stringify(result));
}

const tiers=['dumb','easy','normal','hard','godlike'];
const sameRates=(a,b)=>tiers.every(t=>(a?.[t]||0)===(b?.[t]||0))&&Object.keys(a||{}).every(t=>tiers.includes(t));
async function applyMix(page,mix,master=true){
 await page.evaluate(()=>__botStandings.openRules());
 await page.locator('#rule-infinityRandomBots').setChecked(true);
 for(const tier of tiers)await page.locator('#rule-infinityBotSpawnRate-'+tier).selectOption(String(mix[tier]||0));
 if(!master)await page.locator('#rule-infinityRandomBots').uncheck();
 await page.locator('#applyRulesBtn').click();await page.waitForFunction(()=>!document.getElementById('rulesDialog').open,null,{polling:20});
 return page.evaluate(()=>__botStandings.rules());
}
async function checkRules(page,profile,browser){
 const nonce=String(Date.now()).slice(-7),name='check'+nonce+profile.name[0];
 await page.evaluate(({name})=>__botStandings.rulesSetup(name,true),{name});await page.evaluate(()=>__botStandings.openRules());
 for(const tier of tiers){const select=page.locator('#rule-infinityBotSpawnRate-'+tier),options=await select.locator('option').evaluateAll(items=>items.map(o=>o.value));
  const title={dumb:'Dumb',easy:'Easy',normal:'Medium',hard:'Hard',godlike:'Godlike'}[tier];check((await select.evaluate(e=>e.closest('label').textContent)).startsWith(title.toUpperCase()+' SPAWN RATE'),profile.name+' '+tier+' uses '+title+' label');
  check(['0','0.5','1','2','4'].every(v=>options.includes(v)),profile.name+' '+tier+' standard choices');
  check(Number(await select.inputValue())===(['dumb','easy','normal'].includes(tier)?2/3:0),profile.name+' '+tier+' exact legacy fraction');
  for(const rate of [0,.5,1,2,4]){await select.selectOption(String(rate));check(Number(await select.inputValue())===rate,profile.name+' '+tier+' accepts '+rate);}
 }
 const layout=await page.locator('#rulesDialog').evaluate(d=>({width:d.clientWidth,scroll:d.scrollWidth,body:[...d.querySelectorAll('.feature-body')].map(e=>({w:e.clientWidth,s:e.scrollWidth})),labels:[...d.querySelectorAll('#rule-infinity-bot-options label')].map(e=>({font:parseFloat(getComputedStyle(e).fontSize),w:e.clientWidth,s:e.scrollWidth}))}));
 check(layout.scroll<=layout.width+1&&layout.body.every(e=>e.s<=e.w+1)&&layout.labels.every(e=>e.font>=10&&e.s<=e.w+1),profile.name+' rate dialog wraps without overflow '+JSON.stringify(layout));
 await page.locator('#rule-infinity-bot-options').scrollIntoViewIfNeeded();await page.screenshot({path:path.join(output,profile.name+'-rates.png')});
 await page.locator('[data-close-dialog="rulesDialog"]').click();
 const mix={dumb:.5,easy:1,normal:2,hard:4,godlike:0};let rules=await applyMix(page,mix);
 check(sameRates(rules.infinityBotSpawnRates,mix),profile.name+' Apply persists exact tier mix');
 await page.locator('#roomSettings').evaluate(e=>e.open=true);await page.locator('[data-room-mode="elimination"]').click();await page.locator('[data-room-mode="infinity"]').click();
 rules=await page.evaluate(()=>__botStandings.rules());check(sameRates(rules.infinityBotSpawnRates,mix),profile.name+' mode roundtrip retains mix');
 await page.evaluate(()=>__botStandings.openPresets());await page.locator('#presetName').fill('Browser mix '+profile.name);await page.locator('#savePresetBtn').click();
 const stored=await page.evaluate(()=>JSON.parse(localStorage.getItem('leqra.presets.v1')).items.at(-1));check(sameRates(stored.rules.infinityBotSpawnRates,mix),profile.name+' saved preset contains mix');
 await page.locator('[data-close-dialog="presetsDialog"]').click();rules=await applyMix(page,{normal:4});
 await page.evaluate(()=>__botStandings.openPresets());await page.locator('#presetSelect').selectOption('saved:0');await page.locator('#loadPresetBtn').click();
 rules=await page.evaluate(()=>__botStandings.rules());check(sameRates(rules.infinityBotSpawnRates,mix),profile.name+' preset load restores mix');
 rules=await applyMix(page,mix,false);check(!rules.infinityRandomBots&&sameRates(rules.infinityBotSpawnRates,mix),profile.name+' master Off preserves choices');
 rules=await applyMix(page,{});check(rules.infinityRandomBots&&Object.values(rules.infinityBotSpawnRates).every(v=>v===0),profile.name+' explicit all Off persists');
 rules=await applyMix(page,mix);const code='browser-bots-'+nonce+'-'+profile.name;await page.evaluate(code=>__botStandings.publish(code),code);
 await page.waitForFunction(()=>__botStandings.onlineCode(),null,{timeout:12000,polling:20});
 const actual=await page.evaluate(()=>__botStandings.onlineRules());check(sameRates(actual.infinityBotSpawnRates,mix)&&actual.infinityRandomBots,profile.name+' actual server publish roundtrip');
 // Exercise actual online Apply acknowledgement, not only local preferences.
 await page.evaluate(()=>__botStandings.openRules());await page.locator('#rule-infinityBotSpawnRate-godlike').selectOption('0.5');await page.locator('#applyRulesBtn').click();
 await page.waitForFunction(()=>__botStandings.onlineRules()?.infinityBotSpawnRates?.godlike===.5,null,{polling:20});check(true,profile.name+' actual online rules acknowledgement');
 const guest=await pageFor(browser,profile);
 try{await guest.evaluate(({code,name})=>__botStandings.join(code,name),{code,name:'guest'+nonce+profile.name[0]});await guest.waitForFunction(()=>__botStandings.onlineCode(),null,{timeout:12000,polling:20});await guest.evaluate(()=>__botStandings.openRules());
  const disabled=await guest.locator('[id^="rule-infinityBotSpawnRate-"]').evaluateAll(items=>items.length===5&&items.every(e=>e.disabled));check(disabled,profile.name+' guest sees read-only tier controls');check(await guest.locator('#applyRulesBtn').isDisabled(),profile.name+' guest cannot Apply rules');
  const guestRules=await guest.evaluate(()=>__botStandings.onlineRules());check(guestRules.infinityBotSpawnRates.godlike===.5,profile.name+' guest receives authoritative mix');await guest.screenshot({path:path.join(output,profile.name+'-guest-rates.png')});
 }finally{await guest.context().close();}
 records.push({profile:profile.name,view:'tier-controls',rules:actual,layout});
}
async function run(){
 const browser=await chromium.launch({headless:true,args:['--disable-features=LocalNetworkAccessChecks']});
 try{
  for(const profile of profiles){const page=await pageFor(browser,profile);
   try{
    await page.evaluate(()=>__botStandings.preview());await page.waitForFunction(()=>document.querySelector('#infinityPreviewLeaders .leaderboard-difficulty'),null,{polling:20});
    await page.locator('#infinityPreviewScoreboardBtn').click();const preview=await inspect(page,'#infinityPreviewLeaders');validate(preview,profile.name+' public preview',false);records.push({profile:profile.name,view:'preview',result:preview});await page.screenshot({path:path.join(output,profile.name+'-preview.png')});
    for(const [view,spectator,room]of [['public',false,false],['room',false,true],['spectator',true,true]]){
     const arena=await page.evaluate(({entries,spectator,room})=>__botStandings.arena(entries,spectator,room),{entries,spectator,room});
     const result=await inspect(page,'#infiniteLeaderboard');validate(result,profile.name+' '+view,spectator);records.push({profile:profile.name,view,result});
     check(['Bot 1 - Dumb','Bot 2 - Medium','Bot 3 - Godlike'].every(name=>arena.labels.some(row=>row.text===name)),profile.name+' '+view+' full canonical arena labels retained');
     check(arena.labels.some(row=>row.text==='Bot Rust'),profile.name+' '+view+' room bot arena label retained');
     await page.screenshot({path:path.join(output,profile.name+'-'+view+'.png')});
     if(spectator){const last=page.locator('#infiniteLeaderboard [data-follow-id="33"]');await last.scrollIntoViewIfNeeded();await last.click();const sent=await page.evaluate(()=>__botStandings.sent());check(sent.some(message=>message.type==='follow'&&message.target===33),profile.name+' spectator follows numeric ID after scrolling');}
    }
    const lifecycle=await page.evaluate(()=>__botStandings.identityLifecycle());for(const label of lifecycle.checks)check(true,profile.name+' '+label);records.push({profile:profile.name,view:'persistent-identities',...lifecycle});
    await checkRules(page,profile,browser);
   }catch(error){await page.screenshot({path:path.join(output,profile.name+'-failure.png')});throw error;}finally{await page.context().close();}
  }
  check(errors.length===0,'No browser runtime errors');
 }catch(error){errors.push(error.stack||error.message);process.exitCode=1;}
 finally{await browser.close();fs.writeFileSync(path.join(output,'report.json'),JSON.stringify({checks,records,errors},null,2));console.log(JSON.stringify({checks:checks.length,cases:records.length,errors,output}));}
}
run().catch(error=>{console.error(error);process.exitCode=1;});
