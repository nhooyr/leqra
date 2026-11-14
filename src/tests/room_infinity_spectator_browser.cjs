'use strict';
// Optional real-browser/API regression. Use an isolated loopback backend.
// node src/tests/room_infinity_spectator_browser.cjs http://127.0.0.1:18107 --disposable
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto'),{chromium}=require('playwright');
const {assetPath}=require('./web_assets.cjs'),args=process.argv.slice(2),address=args.find(value=>/^https?:/.test(value));
if(!args.includes('--disposable')||!address)throw Error('Supply an isolated loopback backend URL and --disposable.');
const url=new URL(address);if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.username||url.password||url.search||url.hash||url.pathname!=='/')throw Error('Only an uncredentialed loopback origin is allowed.');
const origin=url.origin,repo=path.resolve(__dirname,'../..'),web=path.join(repo,'src/web'),assetPrefix='/'+path.relative(web,path.dirname(assetPath('game.js'))).split(path.sep).join('/')+'/';
const out=process.env.LEQRA_BROWSER_OUTPUT?path.resolve(process.env.LEQRA_BROWSER_OUTPUT):fs.mkdtempSync(path.join(os.tmpdir(),'leqra-room-spectators-'));fs.mkdirSync(out,{recursive:true});
const checks=[],errors=[],measurements=[],profiles=[{name:'desktop',width:1280,height:720,mobile:false},{name:'portrait',width:390,height:844,mobile:true},{name:'landscape',width:844,height:390,mobile:true}],run=crypto.randomBytes(4).toString('hex');
const redact=value=>String(value).replace(/p_[A-Za-z0-9_-]{43}/g,'[REDACTED]'),check=(condition,label)=>{if(!condition)throw Error(label);checks.push(label);};
const mime={'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.webmanifest':'application/manifest+json'};
const infinityProbe=`
window.__spectatorProbe={state(){const w=session;if(!w)return null;const target=w.tanks.find(t=>t.id===w.following);return{spectating:w.spectating,id:w.id,following:w.following,joined:w.joined,failed:w.failed,seed:w.seed,players:w.players,tankCount:w.tankCount,leaderboard:w.leaderboard.map(t=>({id:t.id,name:t.name,score:t.score,bot:t.bot})),camera:w.camera&&{x:w.camera.x,y:w.camera.y},display:w.display&&{id:w.display.id,x:w.display.x,y:w.display.y},target:target&&{id:target.id,x:target.x,y:target.y,hp:target.hp,spawnSerial:target.spawnSerial},controllers:w.controllers.map(c=>({id:c.id,predicted:!!c.predictor?.state})),socket:socket?.readyState};},drop(){socket?.close(4001,'Browser reconnect check');},respawnBounds(){const w=session,p=w.tanks.find(t=>t.id===w.following);renderScores({...w,personalScoreRows:null},{...p,hp:0});const bounds={};for(const id of ['infiniteStatusbar','infiniteCanvas']){const r=document.getElementById(id).getBoundingClientRect();bounds[id]={x:r.x,y:r.y,width:r.width,height:r.height};}renderScores({...w,personalScoreRows:null},p);return bounds;}};
`;
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--disable-features=LocalNetworkAccessChecks']});const contexts=[],pages=[];
 async function make(profile,name,query=''){
  const context=await browser.newContext({viewport:{width:profile.width,height:profile.height},isMobile:profile.mobile,hasTouch:profile.mobile,deviceScaleFactor:profile.mobile?2:1,serviceWorkers:'block'});contexts.push(context);
  await context.addInitScript(name=>{
   for(const [key,value]of Object.entries({'introTour.v1':'1',name,local2Name:name+'W',infinityOnline:'0',infinityOffline:'0',muted:'0'}))localStorage.setItem('leqra.'+key,value);
   window.__wireSent=[];window.__wireReceived=[];
   const WS=window.WebSocket;window.WebSocket=class extends WS{
    constructor(...args){super(...args);this.auditPath=new URL(args[0],location.href).pathname;this.addEventListener('message',event=>{try{const p=JSON.parse(event.data);if(p.type!=='state')__wireReceived.push({path:this.auditPath,type:p.type,code:p.code,spectating:p.spectating,id:p.id,following:p.following,hasKey:!!p.publicToken,hasLocalKey:!!p.localPublicToken});}catch(_){}});}
    send(value){try{const p=JSON.parse(value);__wireSent.push({path:this.auditPath,type:p.type,target:p.target,spectating:p.spectating,hasRoomToken:!!p.token,hasPublicKey:!!p.publicToken,hasLocalKey:!!p.localPublicToken});}catch(_){}return super.send(value);}
   };
  },name);
  const page=await context.newPage();pages.push({page,name});page.on('pageerror',error=>errors.push(redact(error.message)));
  await page.route('**/*',async route=>{
   const request=route.request(),u=new URL(request.url());if(request.method()!=='GET')return route.continue();
   const file=u.pathname==='/'?path.join(web,'index.html'):u.pathname.startsWith(assetPrefix)?path.join(web,u.pathname):'';
   if(!file||!fs.existsSync(file))return route.continue();let body=fs.readFileSync(file);
   if(file.endsWith('/infinite.js')){const s=body.toString(),at=s.lastIndexOf('})();');body=Buffer.from(s.slice(0,at)+infinityProbe+s.slice(at));}
   if(file.endsWith('/game.js')){const s=body.toString(),at=s.lastIndexOf('})();');body=Buffer.from(s.slice(0,at)+"\nwindow.__spectatorAudioProbe=()=>({playing:!!starmanSource,wanted:starmanWanted});\n"+s.slice(at));}
   return route.fulfill({status:200,contentType:mime[path.extname(file)]||'application/octet-stream',body});
  });
  await page.goto(origin+'/?test=1'+query);await page.waitForFunction(()=>window.__test&&window.__spectatorProbe);return{page,context};
 }
 const state=page=>page.evaluate(()=>__spectatorProbe.state());
 async function joinViewer(profile,name,code){const env=await make(profile,name,'&room='+encodeURIComponent(code)+'&spectate=1');await env.page.locator('#joinRoomBtn').click();await env.page.waitForFunction(()=>__test.online.connected&&__test.online.spectating);return env;}
 async function watchReady(page){await page.waitForFunction(()=>document.getElementById('infiniteArena').open&&__spectatorProbe.state()?.spectating&&__spectatorProbe.state()?.joined,null,{timeout:15000});}
 async function screenshot(page,label){await page.screenshot({path:path.join(out,label+'.png'),fullPage:true});}
 try{
  for(const [index,profile]of profiles.entries()){
   const label=profile.name,{page:host,context:hostContext}=await make(profile,'H'+run+index);
   await host.evaluate(()=>{while(__test.localRoom.players.length<8)__test.addRoomSeat('bot');for(const p of __test.localRoom.players)if(p.kind==='bot')__test.changeSeat(p,{difficulty:'dumb'});__test.changeSeat(__test.localRoom.players.find(p=>p.kind==='bot'),{name:'天地玄黃宇宙洪荒日月盈昃辰宿列張'});__test.setLocalRules({...__test.currentRules(),infinity:true,infinityRandomBots:true,infinityBotDifficulty:'dumb',teamMode:'ffa'});});
   await host.locator('#copyInviteBtn').click();await host.waitForFunction(()=>__test.online.connected&&__test.online.roomData?.rules.infinity);const code=await host.evaluate(()=>__test.online.code);
   const {page:viewer,context:viewerContext}=await joinViewer(profile,'V'+run+index,code);
   check(!await viewer.locator('#infiniteArena').evaluate(node=>node.open),label+' pre-start spectator stays in the ready room');
   await host.locator('#startRoomBtn').click();await Promise.all([watchReady(viewer),host.waitForFunction(()=>document.getElementById('infiniteArena').open&&__spectatorProbe.state()?.joined,null,{timeout:15000})]);
   // A background controller deliberately holds respawn. Keep the real human
   // host focused while waiting for its normal roaming-bot population.
   await host.bringToFront();
   await viewer.waitForFunction(()=>__spectatorProbe.state().leaderboard.length>10,null,{timeout:25000});
   const joined=await state(viewer);
   check(joined.id===0&&joined.spectating&&joined.controllers.every(c=>!c.predicted)&&await viewer.evaluate(()=>leqraInfinity.localPilots().length===0),label+' auto-open observer has no pilot, prediction or local HUD identity');
   check(await viewer.evaluate(()=>__wireReceived.some(p=>p.path==='/ws/infinite'&&p.type==='welcome'&&p.spectating&&p.id===0&&!p.hasKey&&!p.hasLocalKey)),label+' observer welcome has no tank or account bearer');
   const panel=viewer.locator('#infiniteLeaderboardPanel');await panel.evaluate(node=>node.open=true);
   const before=await viewer.evaluate(()=>{const panel=document.getElementById('infiniteLeaderboardPanel'),button=document.querySelector('#infiniteLeaderboard .infinite-follow-target:last-child');panel.scrollTop=panel.scrollHeight;button?.focus({preventScroll:true});return{count:__spectatorProbe.state().leaderboard.length,scroll:panel.scrollTop,focused:document.activeElement?.dataset.followId};});
   await host.bringToFront();
   await viewer.waitForFunction(count=>__spectatorProbe.state().leaderboard.length>count,before.count,{timeout:6000});
   const after=await viewer.evaluate(()=>({scroll:document.getElementById('infiniteLeaderboardPanel').scrollTop,focused:document.activeElement?.dataset.followId}));
   check(after.focused===before.focused&&Math.abs(after.scroll-before.scroll)<1,label+' new ranked entries preserve leaderboard focus and scroll');
   await viewer.waitForFunction(()=>{const p=document.getElementById('infiniteLeaderboardPanel');return p.scrollHeight>p.clientHeight+5;},null,{timeout:18000});
   const scroll=await panel.evaluate(node=>{node.scrollTop=node.scrollHeight;return{scrollTop:node.scrollTop,scrollHeight:node.scrollHeight,clientHeight:node.clientHeight};});
   check(scroll.scrollTop>0,label+' full real leaderboard scrolls beyond its viewport');
   const target=await viewer.locator('#infiniteLeaderboard [data-follow-id]').last().getAttribute('data-follow-id');await viewer.locator('#infiniteLeaderboard [data-follow-id="'+target+'"]').click();
   await viewer.waitForFunction(id=>{const w=__spectatorProbe.state();return w?.following===id&&w.display?.id===id&&Math.hypot(w.camera.x-w.display.x,w.camera.y-w.display.y)<1;},Number(target));
   check((await state(viewer)).following===Number(target),label+' clicking a real tank follows its rendered authoritative camera');
   if(profile.mobile&&profile.height>profile.width)check(!await panel.evaluate(node=>node.open),label+' selecting a tank dismisses the portrait leaderboard');
   const bounds=()=>viewer.evaluate(()=>{const result={};for(const id of ['infiniteStatusbar','infiniteCanvas']){const r=document.getElementById(id).getBoundingClientRect();result[id]={x:r.x,y:r.y,width:r.width,height:r.height};}return result;}),shortBounds=await bounds(),longTarget=joined.leaderboard.find(t=>t.name==='天地玄黃宇宙洪荒日月盈昃辰宿列張').id;
   await panel.evaluate(node=>node.open=true);await viewer.locator('#infiniteLeaderboard [data-follow-id="'+longTarget+'"]').click();await viewer.waitForFunction(id=>__spectatorProbe.state()?.following===id&&document.getElementById('infiniteKills').textContent.includes('天地玄黃宇宙洪荒日月盈昃辰宿列張'),longTarget);
   const longBounds=await bounds(),respawnBounds=await viewer.evaluate(()=>__spectatorProbe.respawnBounds());measurements.push({profile:label,shortBounds,longBounds,respawnBounds});
   check(JSON.stringify(shortBounds)===JSON.stringify(longBounds),label+' short and maximum-length CJK follow labels retain arena bounds');
   check(JSON.stringify(shortBounds)===JSON.stringify(respawnBounds),label+' maximum-length CJK respawn label retains arena bounds');
   await panel.evaluate(node=>node.open=true);await viewer.locator('#infiniteLeaderboard [data-follow-id="'+target+'"]').click();await viewer.waitForFunction(id=>__spectatorProbe.state()?.following===id,Number(target));
   await screenshot(viewer,label+'-following');
   await viewer.keyboard.press('KeyW');await viewer.keyboard.press('Space');const rename=await viewer.evaluate(()=>leqraInfinity.renamePilot(0,'SpectatorHack').then(()=>false,()=>true));
   check(rename&&await viewer.evaluate(()=>!__wireSent.some(p=>p.path==='/ws/infinite'&&['input','rename'].includes(p.type))&&!__spectatorAudioProbe().playing&&!__spectatorAudioProbe().wanted),label+' viewer cannot send tank inputs, rename or start local Starman music');
   await viewer.locator('#pauseBtn').click();await viewer.waitForFunction(()=>document.getElementById('infinitePauseMenu').open);await viewer.locator('#infiniteResumeBtn').click();await viewer.waitForFunction(()=>!document.getElementById('infinitePauseMenu').open);
   check((await state(viewer)).following===Number(target),label+' pause and resume retain the followed identity');
   const joins=await viewer.evaluate(()=>__wireSent.filter(p=>p.path==='/ws/infinite'&&p.type==='join').length);await viewer.evaluate(()=>__spectatorProbe.drop());
   await viewer.waitForFunction(({joins,target})=>__wireSent.filter(p=>p.path==='/ws/infinite'&&p.type==='join').length>joins&&__spectatorProbe.state()?.joined&&__spectatorProbe.state()?.following===target,{joins,target:Number(target)},{timeout:15000});
   check(await viewer.evaluate(id=>__wireSent.some(p=>p.path==='/ws/infinite'&&p.type==='join'&&p.spectating&&p.target===id&&!p.hasPublicKey&&!p.hasLocalKey),Number(target)),label+' reconnect restores the chosen target without an account-bearing pilot join');
   await viewer.locator('#pauseBtn').click();await viewer.locator('#infiniteExit').click();await viewer.waitForFunction(()=>!document.getElementById('infiniteArena').open);
   const roomPackets=await viewer.evaluate(()=>__wireReceived.filter(p=>p.path==='/ws'&&p.type==='room').length);await viewer.evaluate(()=>__test.online.socket.send(JSON.stringify({type:'spectate',spectating:true})));
   await viewer.waitForFunction(count=>__wireReceived.filter(p=>p.path==='/ws'&&p.type==='room').length>count,roomPackets);
   check(await viewer.evaluate(()=>__test.online.connected&&!document.getElementById('infiniteArena').open)&&await viewer.locator('#startRoomBtn').innerText().then(text=>text.includes('WATCH INFINITY')),label+' explicit exit stays in the room through duplicate updates and offers Watch Infinity');
   await viewer.locator('#startRoomBtn').click();await watchReady(viewer);
   check((await state(viewer)).spectating,label+' Watch Infinity reenters the current run as an observer');
   const {page:late,context:lateContext}=await joinViewer(profile,'L'+run+index,code);await watchReady(late);
   check((await state(late)).spectating,label+' a late spectator joins the already running arena');
   const seed=(await state(viewer)).seed;await host.evaluate(()=>leqraInfinity.close());
   await viewer.waitForFunction(()=>{const w=__spectatorProbe.state();return w?.joined&&w.following===0&&w.tankCount===0&&w.leaderboard.length===0&&w.camera.x===42&&w.camera.y===42;});
   check(true,label+' last controller departure produces an empty arena with an origin camera and no phantom tank');
   await host.locator('#startRoomBtn').click();await viewer.waitForFunction(()=>__spectatorProbe.state()?.following>0&&__spectatorProbe.state()?.tankCount>=8);
   check((await state(viewer)).seed===seed,label+' a real controller returning preserves the observed maze');
   const identity=await late.evaluate(()=>({target:__test.online.id,member:__test.online.member}));await host.evaluate(identity=>__test.online.socket.send(JSON.stringify({type:'kick',...identity})),identity);
   await late.waitForFunction(()=>!document.getElementById('infiniteArena').open&&!__test.online.connected);
   check((await state(viewer)).joined,label+' kicking one spectator removes its view while the other remains connected');
   await host.evaluate(()=>__test.online.socket.send(JSON.stringify({type:'lobby'})));await viewer.waitForFunction(()=>!document.getElementById('infiniteArena').open&&!__test.online.roomData.infinityActive);
   check(await viewer.evaluate(()=>__test.online.connected&&__test.online.spectating),label+' host ending the run closes only the observer arena and retains room membership');
   await host.evaluate(()=>__test.online.socket.send(JSON.stringify({type:'unshare'})));await viewer.waitForFunction(()=>!__test.online.connected);
   check(!await viewer.locator('#infiniteArena').evaluate(node=>node.open),label+' unsharing closes spectator room access');
   measurements.push({profile:label,leaderCount:joined.leaderboard.length,scroll,target:Number(target),role:joined.spectating,id:joined.id});
   for(const context of [lateContext,viewerContext,hostContext])await context.close();
  }
  check(errors.length===0,'No browser JavaScript errors');
 }catch(error){errors.push(redact(error.message));const diagnostics=[];for(const {page,name}of pages)if(!page.isClosed()){try{diagnostics.push({name,...await page.evaluate(()=>({state:__spectatorProbe.state(),phase:__test.phase,roomConnected:__test.online.connected,rules:__test.online.roomData?.rules,roomActive:__test.online.roomData?.infinityActive,audio:__spectatorAudioProbe()}))});await screenshot(page,'failure-'+name);}catch(_){}}fs.writeFileSync(path.join(out,'diagnostics.json'),JSON.stringify(diagnostics,null,2));process.exitCode=1;}
 finally{for(const context of contexts)await context.close().catch(()=>{});await browser.close();fs.writeFileSync(path.join(out,'report.json'),JSON.stringify({checks,measurements,errors},null,2));console.log(JSON.stringify({checks:checks.length,measurements,errors,output:out}));}
})();
