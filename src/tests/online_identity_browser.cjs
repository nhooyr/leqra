'use strict';
// Run against a disposable server/database; claims deliberately survive resets.
// node src/tests/online_identity_browser.cjs http://127.0.0.1:18081 http://127.0.0.1:18082 /tmp/leqra-identity-browser
const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const origin=process.argv[2]||'http://127.0.0.1:18081',admin=process.argv[3]||'http://127.0.0.1:18082',output=path.resolve(process.argv[4]||'/tmp/leqra-identity-browser');
const suffix=Date.now().toString(36),names=['OWN '+suffix,'WING '+suffix],fresh=['NEW '+suffix,'PAIR '+suffix];
fs.mkdirSync(output,{recursive:true});
(async()=>{
 const browser=await chromium.launch({headless:true});const errors=[],checks=[];const check=(value,message)=>{assert.ok(value,message);checks.push(message);};
 try{
  const owner=await browser.newContext({serviceWorkers:'block'}),pilot=await owner.newPage();await pilot.goto(origin+'/?test=1');
  const joined=await pilot.evaluate(async names=>{
   window.identityPackets=[];window.identitySockets=[];
   const join=name=>new Promise((resolve,reject)=>{const ws=new WebSocket(location.origin.replace('http','ws')+'/ws/infinite');identitySockets.push(ws);const timeout=setTimeout(()=>reject(Error('public join timed out')),7000);ws.onopen=()=>ws.send(JSON.stringify({type:'join',version:leqra.version,name,score:999999,id:1,rank:1}));ws.onmessage=event=>{const packet=JSON.parse(event.data);identityPackets.push(packet);if(packet.type==='error')reject(Error(packet.message));if(packet.type==='welcome'){clearTimeout(timeout);resolve(packet);}};});
   return Promise.all(names.map(join));
  },names);
  check(joined.every(packet=>typeof packet.publicToken==='string'),'Each online owner receives its own bearer');check(joined[0].publicToken!==joined[1].publicToken,'Separate clients never share ownership by callsign');
  const anon=await pilot.evaluate(async names=>(await fetch('/api/callsigns',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({names})})).json(),names);
  check(anon.names.every(row=>!row.available),'Anonymous availability rejects both claimed names');
  const owned=await pilot.evaluate(async({name,token})=>(await fetch('/api/callsigns',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({names:[name],publicToken:token})})).json(),{name:names[0],token:joined[0].publicToken});check(owned.names[0].available,'Bearer ownership permits its own reserved callsign');
  const rejectedManual=await pilot.evaluate(async({token,taken,clear})=>{
   const attempt=names=>new Promise((resolve,reject)=>{const ws=new WebSocket(location.origin.replace('http','ws')+'/ws/infinite'),timer=setTimeout(()=>{ws.close();reject(Error('manual public conflict timed out'))},7000);ws.onopen=()=>ws.send(JSON.stringify({type:'join',version:leqra.version,publicToken:token,resume:true,updateNames:true,...names}));ws.onmessage=event=>{const packet=JSON.parse(event.data);if(packet.type==='error'){clearTimeout(timer);ws.close();resolve(packet)}else if(packet.type==='welcome'){clearTimeout(timer);ws.close();reject(Error('conflicting public manual rename was accepted'))}};});
   return [await attempt({name:taken}),await attempt({name:clear,localName:taken})];
  },{token:joined[0].publicToken,taken:names[1],clear:fresh[0]});
  check(rejectedManual.every(packet=>packet.code==='callsign_taken'),'Manual public entry rejects another owner’s reserved name');
  check(rejectedManual[0].conflicts.some(row=>row.seat===0)&&rejectedManual[1].conflicts.some(row=>row.seat===1),'Manual public conflicts identify the primary and local editor separately');
  check(await pilot.evaluate(()=>identitySockets.every(ws=>ws.readyState===WebSocket.OPEN)),'A rejected manual rename never replaces the original live session');
  const unclaimed=await pilot.evaluate(async name=>(await fetch('/api/callsigns',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({names:[name]})})).json(),fresh[0]);
  check(unclaimed.names[0].available,'A rejected public P1/P2 batch does not reserve its otherwise clear name');

  const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true,deviceScaleFactor:2,serviceWorkers:'block'});
  await context.addInitScript(name=>{localStorage.setItem('leqra.name',name);localStorage.setItem('leqra.introTour.v1','1');},fresh[0]);
  const page=await context.newPage();page.on('pageerror',error=>errors.push(error.message));await page.goto(origin+'/?test=1');await page.waitForFunction(()=>window.__test);
  const field=page.locator('#roomCallsign'),feedback=page.locator('#roomCallsignStatus');
  await field.fill(names[0]);const before=await page.locator('#copyInviteBtn').boundingBox();await page.waitForFunction(()=>document.querySelector('#roomCallsignStatus').textContent.includes('Used online'));
  const after=await page.locator('#copyInviteBtn').boundingBox();check(Math.abs(before.y-after.y)<.1,'Availability feedback does not move the share button');
  await field.press('Tab');await page.evaluate(()=>__test.addRoomSeat('local'));await page.locator('#roomP2Callsign').fill(names[1]);await page.locator('#roomP2Callsign').press('Tab');
  await page.locator('#copyInviteBtn').click();await page.waitForFunction(()=>!__test.online.connecting&&document.querySelector('#roomStatus').textContent.includes('marked callsigns'));
  check((await feedback.textContent()).includes('Already used'),'Rejected online publish marks P1');check((await page.locator('#roomP2CallsignStatus').textContent()).includes('Already used'),'Rejected online publish marks P2');check(await page.evaluate(()=>__test.localRoom.players.filter(player=>player.kind==='human'||player.kind==='local').length===2),'Rejected publish preserves the offline roster');
  await page.screenshot({path:path.join(output,'mobile-conflicts.png'),fullPage:true});
  await field.fill(fresh[0]);await field.press('Tab');await page.locator('#roomP2Callsign').fill(fresh[1]);await page.locator('#roomP2Callsign').press('Tab');
  await page.locator('#copyInviteBtn').click();await page.waitForFunction(()=>__test.online.connected);check(await page.evaluate(()=>!!localStorage.getItem('leqra.publicToken')),'Private room welcome saves durable ownership');
  const publicData=await pilot.evaluate(async()=>{await new Promise(resolve=>setTimeout(resolve,100));return (await fetch('/api/infinity')).json();});
  check(publicData.leaders.filter(row=>names.includes(row.name)).every(row=>row.score===0),'Forged client score fields do not change authoritative standings');check(!JSON.stringify(publicData).includes(joined[0].publicToken),'Public standings do not expose ownership bearers');
  const publicAdmin=await page.request.get(origin+'/api/leaderboard');check(publicAdmin.status()===404,'Admin routes are absent from the public game listener');
  const adminPage=await context.newPage();adminPage.on('pageerror',error=>errors.push(error.message));await adminPage.goto(admin);await adminPage.waitForFunction(()=>document.querySelector('#counts').textContent.includes('entries'));
  const regex='^(OWN|WING) '+suffix+'$';await adminPage.locator('#pattern').fill(regex);await adminPage.waitForFunction(()=>document.querySelector('#counts').textContent.includes('2 matches'));
  await adminPage.screenshot({path:path.join(output,'admin-preview.png'),fullPage:true});
  adminPage.on('dialog',dialog=>dialog.accept());await adminPage.locator('#remove').click();await adminPage.waitForFunction(()=>document.querySelector('#status').textContent.includes('Leaderboard updated'));
  await pilot.waitForFunction(()=>identityPackets.some(packet=>packet.type==='leaderboard_reset'&&packet.selected===true));check(await pilot.evaluate(()=>identitySockets.every(ws=>ws.readyState===WebSocket.OPEN)),'Selected reset broadcasts without disconnecting public players');
  await adminPage.locator('#reset').click();await adminPage.waitForFunction(()=>document.querySelector('#status').textContent.includes('Leaderboard updated'));
  await pilot.waitForFunction(()=>identityPackets.some(packet=>packet.type==='leaderboard_reset'&&!packet.selected));
  const reserved=await pilot.evaluate(async names=>(await fetch('/api/callsigns',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({names})})).json(),names);check(reserved.names.every(row=>!row.available),'Leaderboard resets never release callsign ownership');
  check(errors.length===0,'No browser JavaScript errors');fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({checks,errors},null,2));console.log(JSON.stringify({passed:checks.length,output}));
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
