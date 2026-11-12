(() => {
'use strict';
const VERSION = 'v4.49.41';
const webOrigin=['http:', 'https:'].includes(location.protocol);
let serviceWorker=null;
try{if(webOrigin&&window.isSecureContext!==false)serviceWorker=navigator.serviceWorker;}catch(_){}
let registration,registering,checking,latestBuild,pendingBuild,retry,pollTimer,buildController,buildTimeout,resetTask;
let reloading=false,resetting=false,lastCheck=-Infinity,stopInstallHint=()=>{};
const workerProbes=new Set();

function ownRegistration(value){
 try{
  const scope=new URL(value.scope,location.href),root=new URL('/',location.href);
  return scope.href===root.href&&[value.active,value.waiting,value.installing].some(worker=>{
   if(!worker)return false;const url=new URL(worker.scriptURL,location.href);return url.origin===root.origin&&url.pathname==='/sw.js';
  });
 }catch(_){return false;}
}
function pauseWorkerWrites(worker){
 if(!worker||typeof MessageChannel!=='function')return Promise.resolve();
 return new Promise(resolve=>{
  const channel=new MessageChannel();let done=false;
  const finish=()=>{if(done)return;done=true;clearTimeout(timer);channel.port1.close();channel.port2.close();resolve();};
  const timer=setTimeout(finish,1000);channel.port1.onmessage=event=>{if(event.data?.type==='LEQRA_RESET_DONE')finish();};
  try{worker.postMessage({type:'LEQRA_RESET'},[channel.port2]);}catch(_){finish();}
 });
}
async function clearWorkers(){
 if(!serviceWorker)return;
 const pending=registering?new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>reject(Error('A service worker update is still pending. Try reset again.')),3000);
  registering.then(value=>{clearTimeout(timer);resolve(value);},error=>{clearTimeout(timer);reject(error);});
 }):Promise.resolve(null);
 const discovery=await Promise.allSettled([Promise.resolve().then(()=>serviceWorker.getRegistrations?.()||[]),pending]);
 const candidates=[registration,...discovery.flatMap(result=>result.status==='fulfilled'?(Array.isArray(result.value)?result.value:[result.value]):[])];
 const own=[...new Set(candidates.filter(value=>value&&ownRegistration(value)))];
 const writes=[...new Set(own.flatMap(value=>[value.active,value.waiting,value.installing]).filter(Boolean))];
 if(serviceWorker.controller&&writes.every(worker=>worker!==serviceWorker.controller)&&own.some(value=>value.active?.scriptURL===serviceWorker.controller.scriptURL))writes.push(serviceWorker.controller);
 await Promise.allSettled(writes.map(pauseWorkerWrites));
 const removed=await Promise.allSettled(own.map(value=>Promise.resolve().then(()=>value.unregister())));
 if([...discovery,...removed].some(result=>result.status==='rejected'))throw Error('Could not unregister every leqra service worker. Try reset again.');
}
async function clearAppCaches(){
 if(!webOrigin)return;
 const storage=window.caches;if(!storage)return;
 let names;try{names=await storage.keys();}catch(_){throw Error('Could not read leqra offline caches. Try reset again.');}
 const removed=await Promise.allSettled(names.filter(name=>name.startsWith('leqra-app-')).map(name=>Promise.resolve().then(()=>storage.delete(name))));
 if(removed.some(result=>result.status==='rejected'))throw Error('Could not clear every leqra offline cache. Try reset again.');
}
function resetPWA(){
 if(resetTask)return resetTask;
 resetting=true;pendingBuild=latestBuild=null;clearTimeout(retry);clearTimeout(buildTimeout);clearInterval(pollTimer);buildController?.abort();
 for(const cancel of [...workerProbes])cancel();stopInstallHint();
 resetTask=(async()=>{
  // Stop current workers before deleting their caches. A failed unregister
  // must still attempt cache deletion, and a failed deletion remains retryable.
  const workers=await Promise.allSettled([clearWorkers()]);
  const caches=await Promise.allSettled([clearAppCaches()]);
  if([...workers,...caches].some(result=>result.status==='rejected'))throw Error([...workers,...caches].filter(result=>result.status==='rejected').map(result=>result.reason?.message||'Could not clear leqra offline data.').join(' '));
 })().catch(error=>{resetTask=null;throw error;});
 return resetTask;
}
window.leqraPWA=Object.freeze({reset:resetPWA});
if(!webOrigin)return;

function initInstallHint() {
 const ua=navigator.userAgent||'',ios=/iP(?:hone|ad|od)/.test(ua)||navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1;
 const mobile=ios||navigator.userAgentData?.mobile===true||/Android/.test(ua)||window.matchMedia?.('(pointer: coarse)')?.matches;
 if (!serviceWorker||window.isSecureContext!==true||!mobile||typeof MutationObserver!=='function') return;
 const standalone=window.matchMedia?.('(display-mode: standalone)'),storageKey='leqra.installHint.v1';
 const saved=()=>{try{return localStorage.getItem(storageKey);}catch(_){return null;}};
 const remember=value=>{try{localStorage.setItem(storageKey,value);}catch(_){}};
 if (navigator.standalone===true||standalone?.matches) {remember('installed');return;}
 if (saved()) return;
 // iOS has no install prompt event. Only known full browsers get Share-sheet
 // instructions; embedded app browsers and generic web views stay quiet.
 const embedded=/FBAN|FBAV|Instagram|Line\/|GSA\/|DuckDuckGo|TikTok|Snapchat/i.test(ua);
 const manual=ios&&'standalone' in navigator&&/AppleWebKit\//.test(ua)&&!embedded&&
  (/CriOS\/|FxiOS\/|EdgiOS\//.test(ua)||/Version\/[\d.]+.*Safari\//.test(ua));
 if (ios&&!manual) return;
 let notice,promptEvent,observer,stopped=false;
 function finish(value) {
  if (stopped) return;
  stopped=true;if(value)remember(value);promptEvent=null;observer?.disconnect();notice?.remove();
  window.removeEventListener('beforeinstallprompt',offer);
  window.removeEventListener('appinstalled',installed);
  window.removeEventListener('pageshow',sync);
  window.removeEventListener('storage',storageChanged);
  document.removeEventListener('visibilitychange',sync);
  standalone?.removeEventListener?.('change',sync);
 }
 stopInstallHint=()=>finish();
 function installed(){finish('installed');}
 function storageChanged(event){if(event.key===storageKey&&saved())finish();}
 function observeDialogs(){for(const dialog of document.querySelectorAll('dialog'))observer.observe(dialog,{attributes:true,attributeFilter:['open']});}
 function sync() {
  if (stopped) return;
  if (navigator.standalone===true||standalone?.matches) {installed();return;}
  if (saved()) {finish();return;}
  let visible=false;try{visible=!document.hidden&&window.leqra?.canShowInstallHint?.()===true;}catch(_){}
  visible=visible&&(manual||!!promptEvent);
  if (!notice&&visible) {
   notice=document.createElement('section');notice.className='pwa-install-hint'+(manual?' pwa-install-manual':'');notice.setAttribute('aria-label','Install leqra');
   const copy=document.createElement('div'),title=document.createElement('strong'),message=document.createElement('p');
   title.textContent='Play leqra as an app';
   message.textContent=(manual?'Add to the Home Screen for a full screen experience. Tap Share, then Add to Home Screen.':'Add to the Home Screen for a full screen experience.')+' Native iOS app coming soon.';
   copy.append(title,message);notice.append(copy);
   if (!manual) {
    const install=document.createElement('button');install.type='button';install.className='secondary pwa-install-action';install.textContent='INSTALL';
    install.addEventListener('click',async()=>{
     const event=promptEvent;if(!event||stopped)return;promptEvent=null;install.disabled=true;sync();
     try{await event.prompt();await event.userChoice;}catch(_){}
     finish('dismissed');
    });notice.append(install);
   }
   const dismiss=document.createElement('button');dismiss.type='button';dismiss.className='pwa-install-dismiss';dismiss.textContent='×';dismiss.setAttribute('aria-label','Dismiss installation suggestion');
   dismiss.addEventListener('click',()=>finish('dismissed'));notice.append(dismiss);document.body.append(notice);
  }
  if(notice&&notice.hidden===visible)notice.hidden=!visible;
 }
 function offer(event){
  if(stopped||typeof event.prompt!=='function')return;
  event.preventDefault();promptEvent=event;sync();
 }
 observer=new MutationObserver(records=>{if(records.some(record=>record.type==='childList'))observeDialogs();sync();});
 observer.observe(document.body,{attributes:true,attributeFilter:['class'],childList:true});observeDialogs();
 if(!manual)window.addEventListener('beforeinstallprompt',offer);
 window.addEventListener('appinstalled',installed);window.addEventListener('pageshow',sync);window.addEventListener('storage',storageChanged);
 document.addEventListener('visibilitychange',sync);standalone?.addEventListener?.('change',sync);sync();
}

const loadedBuild = document.querySelector('meta[name="leqra-build"]')?.content || VERSION;

function applyUpdate() {
 if (resetting||!pendingBuild || reloading || document.hidden || navigator.onLine === false) return;
 let ready = false;
 try { ready = window.leqra?.prepareUpdate?.() === true; } catch (_) {}
 if (ready) {
  reloading = true;
  clearTimeout(retry);
  location.reload();
 } else {
  clearTimeout(retry);
  retry = setTimeout(applyUpdate,1000);
 }
}

function workerBuild(worker) {
 return new Promise((resolve,reject) => {
  const channel = new MessageChannel();
  const close = () => {workerProbes.delete(cancel);channel.port1.close();channel.port2.close();};
  const cancel=()=>{clearTimeout(timeout);close();reject(Error('PWA reset'));};workerProbes.add(cancel);
  const timeout = setTimeout(() => {close();reject(Error('Worker did not report its build.'));},3000);
  channel.port1.onmessage = event => {
   clearTimeout(timeout);close();resolve(event.data?.build);
  };
  try { worker.postMessage({type:'LEQRA_BUILD_INFO'},[channel.port2]); }
  catch (error) {clearTimeout(timeout);close();reject(error);}
 });
}

async function inspectController() {
 const worker = serviceWorker?.controller;
 if (resetting||!worker || !latestBuild) return;
 const build = await workerBuild(worker);
 // A fresh page can still have the previous controller until installation
 // finishes. Only adopt the complete worker that matches the current server.
 if (resetting||worker !== serviceWorker.controller || build !== latestBuild || build === loadedBuild) return;
 pendingBuild = build;
 applyUpdate();
}

function checkUpdate(force=false) {
 if (resetting||document.hidden || navigator.onLine === false) return;
 applyUpdate();
 if (checking || !force && performance.now()-lastCheck<30000) return;
 lastCheck = performance.now();
 checking = (async () => {
  const controller = new AbortController(), timeout = setTimeout(() => controller.abort(),8000);
  buildController=controller;buildTimeout=timeout;
  let info;
  try {
   const response = await fetch('/api/build',{cache:'no-store',signal:controller.signal});
   if (!response.ok) return;
   info = await response.json();
  } finally {clearTimeout(timeout);if(buildController===controller)buildController=null;}
  if(resetting)return;
  if (typeof info.build !== 'string' || !/^v\d+\.\d+\.\d+-[0-9a-f]{16}$/.test(info.build)) return;
  latestBuild = info.build;
  // LAN HTTP web clips cannot install a worker, but can still refresh safely
  // while online using the fingerprinted asset URLs in the new shell.
  if (!serviceWorker) {
   if (latestBuild !== loadedBuild) {pendingBuild = latestBuild;applyUpdate();}
   return;
  }
  if(!registration){
   const pending=serviceWorker.register('/sw.js',{scope:'/',updateViaCache:'none'});registering=pending;
   try{registration=await pending;}finally{if(registering===pending)registering=null;}
   if(resetting){await Promise.allSettled([registration.active,registration.waiting,registration.installing].filter(Boolean).map(pauseWorkerWrites));await registration.unregister().catch(()=>{});return;}
  }
  if(resetting)return;
  await registration.update().catch(() => {});
  if(resetting)return;
  await inspectController();
 })().catch(() => {}).finally(() => {checking = null;});
}

serviceWorker?.addEventListener('controllerchange',() => {
 // The first check may still be awaiting update() when the controller changes.
 inspectController().catch(() => {});
 checkUpdate(true);
});
window.addEventListener('pageshow',event => checkUpdate(event.persisted === true));
window.addEventListener('online',() => checkUpdate(true));
document.addEventListener('visibilitychange',() => {
 if (!document.hidden) checkUpdate(true);
});
if (document.readyState === 'complete') checkUpdate();
else window.addEventListener('load',() => checkUpdate(),{once:true});
// Installed iOS apps can remain alive for days without another navigation.
pollTimer=setInterval(checkUpdate,60000);
initInstallHint();
})();
