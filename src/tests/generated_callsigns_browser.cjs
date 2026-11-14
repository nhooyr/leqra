'use strict';
// Optional production integration check. Claims survive resets: use a fresh disposable backend.
// node src/tests/generated_callsigns_browser.cjs http://127.0.0.1:18091 --disposable
// Screenshots/results default to os.tmpdir(); LEQRA_BROWSER_OUTPUT can select another artifact directory.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),{chromium}=require('playwright');
const {assetPath}=require('./web_assets.cjs'),repo=path.resolve(__dirname,'../..'),webRoot=path.join(repo,'src/web');
const args=process.argv.slice(2),address=args.find(value=>/^https?:/.test(value));
if(!args.includes('--disposable')||!address)throw Error('Supply a fresh disposable loopback backend URL and --disposable.');
const url=new URL(address);if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.username||url.password||url.search||url.hash||url.pathname!=='/')throw Error('Only a loopback origin without credentials, path or query is allowed.');
const origin=url.origin,assetPrefix='/'+path.relative(webRoot,path.dirname(assetPath('game.js'))).split(path.sep).join('/')+'/';
const out=process.env.LEQRA_BROWSER_OUTPUT?path.resolve(process.env.LEQRA_BROWSER_OUTPUT):fs.mkdtempSync(path.join(os.tmpdir(),'leqra-generated-callsigns-'));
fs.mkdirSync(out,{recursive:true});
const checks=[],bugs=[],errors=[],layouts=[];
const redact=value=>String(value).replace(/p_[A-Za-z0-9_-]{43}/g,'[REDACTED]');
const check=(value,label)=>{if(!value){bugs.push(label);throw Error(label);}checks.push(label);};
const mime={'.js':'text/javascript','.css':'text/css','.png':'image/png','.svg':'image/svg+xml','.webmanifest':'application/manifest+json'};
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--disable-features=LocalNetworkAccessChecks']});
 async function make(label,mobile=false,saved){
  const context=await browser.newContext({viewport:mobile?{width:390,height:844}:{width:1440,height:1000},isMobile:mobile,hasTouch:mobile,deviceScaleFactor:mobile?2:1,serviceWorkers:'block'});
  await context.addInitScript(saved=>{
   localStorage.setItem('leqra.introTour.v1','1');
   if(saved&&!localStorage.getItem('__callsignSeeded')){localStorage.setItem('leqra.name',saved[0]);localStorage.setItem('leqra.local2Name',saved[1]);localStorage.setItem('__callsignSeeded','1');}
   window.__generationAudit=[];window.__safePackets=[];window.__delayGeneration=0;
   const fetchOriginal=window.fetch.bind(window);
   window.fetch=async(input,options)=>{
    const url=new URL(typeof input==='string'?input:input instanceof URL?input.href:input.url,location.href);
    if(url.pathname==='/api/callsigns/generate'){
     const body=JSON.parse(options.body);
     __generationAudit.push({accounts:body.accounts.map(account=>{let local=null,pending=null;try{local=JSON.parse(localStorage.getItem('leqra.localAccountRegistration')||'null');pending=JSON.parse(localStorage.getItem('leqra.autoCallsign.'+account.seat)||'null');}catch(_){}const selected=account.seat===0?localStorage.getItem('leqra.publicToken'):localStorage.getItem('leqra.localPublicToken')||local?.token;return{seat:account.seat,keyPersisted:selected===account.publicToken,noncePersisted:pending?.requestId===body.requestId,ownerBound:pending?.owner===account.publicToken};})});
     if(window.__delayGeneration)await new Promise(resolve=>setTimeout(resolve,window.__delayGeneration));
    }
    return fetchOriginal(input,options);
   };
   const WS=window.WebSocket;window.WebSocket=class extends WS{constructor(...args){super(...args);this.addEventListener('message',event=>{try{const p=JSON.parse(event.data);if(['welcome','error','renamed'].includes(p.type))__safePackets.push({type:p.type,code:p.code,id:p.id,localId:p.localId,resumed:p.resumed,public:p.public,hasKey:!!p.publicToken,hasLocalKey:!!p.localPublicToken});}catch(_){}});}};
  },saved);
  const page=await context.newPage();
  page.on('pageerror',error=>errors.push({label,message:redact(error.message),stack:redact(error.stack)}));page.on('console',message=>{if(message.type()==='error')console.log('BROWSER',redact(message.text()));});
  await page.route('**/*',async route=>{
   const request=route.request(),url=new URL(request.url());
   if(request.method()==='GET'&&(url.pathname==='/'||url.pathname==='/index.html'))return route.fulfill({status:200,contentType:'text/html',body:fs.readFileSync(path.join(repo,'src/web/index.html'))});
   if(request.method()==='GET'&&url.pathname.startsWith(assetPrefix)){const file=path.join(repo,'src/web',url.pathname);if(fs.existsSync(file))return route.fulfill({status:200,contentType:mime[path.extname(file)]||'application/octet-stream',body:fs.readFileSync(file)});}
   await route.continue();
  });
  await page.goto(origin+'/?test=1');await page.waitForFunction(()=>window.__test&&window.leqraCallsigns);
  await page.waitForFunction(()=>![0,1].some(window.leqraCallsigns.isPending),null,{timeout:15000});
  return{context,page,label};
 }
 const layout=page=>page.evaluate(()=>{
  const result={};for(const id of ['roomCallsignForm','roomCallsign','roomCallsignStatus','roomP2CallsignForm','roomSettings','startRoomBtn','copyInviteBtn']){const node=document.getElementById(id);if(!node||node.hidden)continue;const r=node.getBoundingClientRect();let scroll=window.scrollY;for(let p=node.parentElement;p;p=p.parentElement)scroll+=p.scrollTop;result[id]={x:r.x,y:r.y+scroll,width:r.width,height:r.height};}return result;
 });
 const stable=(a,b,label)=>{let largest=0;for(const id of Object.keys(a))if(b[id])for(const key of ['x','y','width','height'])largest=Math.max(largest,Math.abs(a[id][key]-b[id][key]));layouts.push({label,maxDifference:largest});check(largest<.2,label+' preserves geometry');};
 try{
  const owner=await make('owner');
  const occupied=await owner.page.evaluate(()=>new Promise((resolve,reject)=>{const ws=new WebSocket(location.origin.replace('http','ws')+'/ws/infinite');window.__rustOwner=ws;const timer=setTimeout(()=>reject(Error('RUST claim timeout, state '+ws.readyState+', events '+JSON.stringify(__safePackets))),7000);ws.onerror=()=>{clearTimeout(timer);reject(Error('RUST socket network error'));};ws.onclose=e=>{clearTimeout(timer);reject(Error('RUST socket closed '+e.code+' '+e.reason));};ws.onopen=()=>ws.send(JSON.stringify({type:'join',version:leqra.version,name:'RUST'}));ws.onmessage=event=>{const p=JSON.parse(event.data);if(p.type==='welcome'){clearTimeout(timer);resolve(true);}if(p.type==='error'){clearTimeout(timer);resolve(p.code==='callsign_taken');}};}));
  check(occupied,'The live Go registry makes RUST unavailable');
  const generated=[];
  for(const mobile of [false,true]){
   const env=await make(mobile?'mobile':'desktop',mobile),page=env.page;
   const state=await page.evaluate(()=>({names:[localStorage.getItem('leqra.name'),localStorage.getItem('leqra.local2Name')],keysDistinct:leqraIdentity.token(0)!==leqraIdentity.token(1),keysValid:[0,1].every(seat=>/^p_[A-Za-z0-9_-]{43}$/.test(leqraIdentity.token(seat))),audit:__generationAudit}));
   check(state.names.every(name=>/^pilot#[A-HJ-NP-Z2-9]{6}$/.test(name))&&state.names[0]!==state.names[1],env.label+' fresh storage gets distinct random P1/P2 names');
   check(state.keysDistinct&&state.keysValid,env.label+' persists distinct valid account keys');
   check(state.audit.length===2&&state.audit.every(row=>row.accounts.every(account=>account.keyPersisted&&account.noncePersisted&&account.ownerBound)),env.label+' saves bearer, UUID and owner binding before API claims');
   generated.push(...state.names);
   await page.evaluate(()=>__test.addRoomSeat('local'));
   await page.screenshot({path:path.join(out,env.label+'-fresh.png'),fullPage:true});
   const before=await layout(page),field=page.locator('#roomCallsign'),status=page.locator('#roomCallsignStatus');
   await field.fill('RUST');await page.waitForFunction(()=>document.querySelector('#roomCallsignStatus .callsign-random-action'));
   const taken=await layout(page);stable(before,taken,env.label+' taken feedback');
   const lines=await status.evaluate(node=>({spans:[...node.children].map(n=>({tag:n.tagName,text:n.textContent,display:getComputedStyle(n).display,height:n.getBoundingClientRect().height})),import:node.querySelectorAll('.callsign-account-action:not(.callsign-random-action)').length,random:node.querySelectorAll('.callsign-random-action').length,height:node.getBoundingClientRect().height}));
   check(lines.import===1&&lines.random===1&&lines.spans.length===3,env.label+' taken feedback has three lines with Import and Generate actions');
   await page.screenshot({path:path.join(out,env.label+'-taken.png'),fullPage:true});
   await page.evaluate(()=>window.__delayGeneration=450);
   await status.locator('.callsign-random-action').click();await page.waitForFunction(()=>document.querySelector('#roomCallsignStatus').textContent.includes('Generating'));
   stable(taken,await layout(page),env.label+' generating feedback');
   await page.screenshot({path:path.join(out,env.label+'-generating.png'),fullPage:true});
   await page.waitForFunction(()=>/^pilot#[A-HJ-NP-Z2-9]{6}$/.test(document.querySelector('#roomCallsign').value)&&!document.querySelector('#roomCallsignStatus').textContent.includes('Generating'));
   stable(before,await layout(page),env.label+' repaired feedback');
   await page.evaluate(()=>window.__delayGeneration=0);
   await page.locator('#startRoomBtn').click();await page.waitForFunction(()=>__safePackets.some(p=>p.type==='welcome'&&p.public&&p.hasKey&&p.hasLocalKey),null,{timeout:10000});
   check(await page.evaluate(()=>__safePackets.some(p=>p.type==='welcome'&&p.public&&p.localId!=null)),env.label+' first online entry succeeds with both independent seats');
   await page.evaluate(()=>leqraInfinity.close());await env.context.close();
  }
  check(new Set(generated).size===generated.length,'Fresh desktop/mobile contexts never reuse each other’s generated names');
  const saved=await make('saved',false,['SavedAlpha','SavedBeta']);
  const savedResult=await saved.page.evaluate(()=>({names:[localStorage.getItem('leqra.name'),localStorage.getItem('leqra.local2Name')],requests:__generationAudit.length}));
  check(savedResult.names.join('|')==='SavedAlpha|SavedBeta'&&savedResult.requests===0,'Existing chosen names remain unchanged without automatic claims');
  await saved.page.reload();await saved.page.waitForFunction(()=>window.__test);
  check(await saved.page.evaluate(()=>localStorage.getItem('leqra.name')==='SavedAlpha'&&localStorage.getItem('leqra.local2Name')==='SavedBeta'),'Saved names remain unchanged after reload');
  const reserved=await make('reserved',true,['bOt RUST','SavedWing']);
  const page=reserved.page,field=page.locator('#roomCallsign'),feedback=page.locator('#roomCallsignStatus');
  await field.focus();await page.waitForFunction(()=>document.querySelector('#roomCallsignStatus').textContent.includes('reserved'));
  const reservedUI=await feedback.evaluate(node=>({random:node.querySelectorAll('.callsign-random-action').length,imports:node.querySelectorAll('.callsign-account-action:not(.callsign-random-action)').length}));
  check(reservedUI.random===1&&reservedUI.imports===0,'Reserved casefolded Bot-space name offers Generate and no misleading account import');
  await page.screenshot({path:path.join(out,'mobile-reserved.png'),fullPage:true});check(await page.locator('#startRoomBtn').isDisabled(),'A saved reserved human name disables public Play');await page.locator('#infinityToggle').uncheck();check(await page.locator('#startRoomBtn').isDisabled(),'A saved reserved human name blocks Play offline');
  const beforeRepair=await layout(page);await feedback.locator('.callsign-random-action').click();
  await page.waitForFunction(()=>/^pilot#[A-HJ-NP-Z2-9]{6}$/.test(document.querySelector('#roomCallsign').value));
  stable(beforeRepair,await layout(page),'mobile reserved-name repair');
  check(await page.locator('#startRoomBtn').isEnabled(),'Generated repair restores Play');
  await field.fill('Botanist');await field.press('Tab');await page.waitForFunction(()=>__test.localRoom.players.some(p=>p.kind==='human'&&p.name==='Botanist'));
  check(await page.locator('#startRoomBtn').isEnabled()&&!await feedback.textContent().then(s=>s.includes('reserved')),'Botanist remains an allowed human callsign');
  await page.screenshot({path:path.join(out,'mobile-botanist.png'),fullPage:true});
  const typing=await make('late-typing'),typingPage=typing.page,typingField=typingPage.locator('#roomCallsign');
  await typingField.fill('RUST');await typingPage.waitForFunction(()=>document.querySelector('#roomCallsignStatus .callsign-random-action'));
  await typingPage.evaluate(()=>window.__delayGeneration=600);
  await typingPage.locator('#roomCallsignStatus .callsign-random-action').click();
  await typingPage.waitForFunction(()=>document.querySelector('#roomCallsignStatus').textContent.includes('Generating'));
  await typingField.fill('TypedPilot');await typingField.press('Tab');
  await typingPage.waitForFunction(()=>!leqraCallsigns.isPending(0));
  check(await typingField.inputValue()==='TypedPilot'&&await typingPage.evaluate(()=>localStorage.getItem('leqra.name')==='TypedPilot'),'Late generation does not overwrite a newly submitted callsign');
  check(errors.length===0,'No browser JavaScript runtime errors');
 }catch(error){const message=redact(error.message);if(!bugs.includes(message))bugs.push(message);}
 finally{fs.writeFileSync(path.join(out,'report.json'),JSON.stringify({checks,bugs,errors,layouts},null,2));await browser.close();console.log(JSON.stringify({checks:checks.length,bugs,errors,output:out}));if(bugs.length)process.exitCode=1;}
})();
