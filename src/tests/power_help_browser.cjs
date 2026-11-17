'use strict';
const {chromium,webkit}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const address=process.argv[2]||'http://127.0.0.1:8080',url=new URL(address);assert.ok(['localhost','127.0.0.1','[::1]'].includes(url.hostname));url.searchParams.set('test','1');
const output=fs.mkdtempSync(path.join(os.tmpdir(),'leqra-power-help-'));
(async()=>{
 for(const [engine,type]of Object.entries({chromium,webkit})){
  const browser=await type.launch();
  for(const [width,height]of [[390,844],[1024,768]]){
   const context=await browser.newContext({viewport:{width,height},hasTouch:true,serviceWorkers:'block'});
   await context.addInitScript(()=>{localStorage.setItem('leqra.introTour.v1','1');localStorage.setItem('leqra.name','Help tester');localStorage.setItem('leqra.infinityOnline','0');localStorage.setItem('leqra.infinityOffline','0');sessionStorage.setItem('leqra.safariNoticeDismissed','1');});
   const page=await context.newPage(),errors=[];page.on('pageerror',error=>errors.push(error.message));await page.goto(url.href);assert.deepEqual(errors,[]);await page.waitForFunction(()=>window.__test);
   await page.locator('#roomSettings > summary').click();
   const savedRules=await page.evaluate(()=>JSON.stringify(__test.currentRules()));
   await page.locator('#infinityToggle').check();
   for(const id of ['roomModePicker','roomConfigActions','rulesSummary'])assert.equal(await page.locator('#'+id).isVisible(),false,id+' remains visible in Public Infinity');
   assert.equal(await page.locator('#localRoomName').isVisible(),true);assert.equal(await page.locator('#copyInviteBtn').isVisible(),true);assert.equal(await page.locator('#publicRoomSettingsNote').isVisible(),true);
   await page.locator('#infinityToggle').uncheck();assert.equal(await page.evaluate(()=>JSON.stringify(__test.currentRules())),savedRules,'Public Infinity changed the saved room rules');
   assert.equal(await page.locator('#roomModePicker').isVisible(),true);assert.equal(await page.locator('#roomRulesBtn').isVisible(),true);
   for(const [mode,mapSize,duration,star,expiry]of [['elimination','compact',10,4,30],['ctf','large',10,5,32],['koth','huge',15,6,45],['survival','giant',15,7,61],['elimination','ultrawide',15,8,90]]){
    await page.evaluate(({mode,mapSize})=>__test.setLocalRules({...__test.currentRules(),mode,mapSize,infinity:false,pickupRate:'slow',weapons:['laser'],teamMode:mode==='ctf'||mode==='survival'?'teams':'ffa'}),{mode,mapSize});
    const note=await page.locator('#gameSidebar .power-note').textContent();assert.ok(note.includes('Most last '+duration+' seconds'));assert.ok(note.includes('Starman lasts '+star+' seconds'));assert.ok(note.includes('expire after '+expiry+' seconds'));
    const cards=await page.locator('#gameSidebar .power-row').evaluateAll(rows=>rows.map(row=>({kind:row.querySelector('canvas').dataset.powerIcon,text:row.querySelector('.power-info span').textContent})));
    for(const card of cards)assert.equal(card.text.startsWith('Disabled in this room.'),card.kind!=='laser');
    await page.locator('#roomRulesBtn').click();assert.ok((await page.locator('#rule-pickup-density').textContent()).includes('every 7–10 seconds'));
    await page.locator('#rule-pickupRate').selectOption('off');assert.equal(await page.locator('#rule-pickup-density').textContent(),'Power-ups disabled.');await page.keyboard.press('Escape');
   }
   await page.evaluate(()=>__test.setLocalRules({...__test.currentRules(),infinity:true,pickupRate:'off',weapons:[]}));await page.locator('#roomRulesBtn').click();
   const help=await page.locator('#rule-pickup-density').textContent();assert.ok(help.includes('All ten power-ups'));assert.ok(help.includes('15 seconds'));assert.ok(help.includes('8 seconds'));assert.ok(help.includes('30 seconds'));
   assert.equal(await page.locator('#gameSidebar .power-info span').evaluateAll(nodes=>nodes.some(node=>node.textContent.startsWith('Disabled in this room.'))),false);
   await page.screenshot({path:path.join(output,engine+'-'+width+'-rules.png')});await page.keyboard.press('Escape');await page.locator('#roomControlsBtn').click();assert.equal(await page.locator('#controlsPickupInfo').count(),0);assert.ok(!(await page.locator('#controlsDialog').textContent()).includes('MAZE POWER-UPS'));assert.deepEqual(errors,[]);
   await context.close();console.log('PASS '+engine+' '+width+' mode-aware sidebar and Rules help');
  }
  await browser.close();
 }
 console.log('Screenshots: '+output);
})().catch(error=>{console.error(error);process.exit(1);});
