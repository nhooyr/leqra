(() => {
'use strict';
const VERSION = 'v4.49.28';
if (!['http:', 'https:'].includes(location.protocol)) return;
const serviceWorker = window.isSecureContext === false ? null : navigator.serviceWorker;

const loadedBuild = document.querySelector('meta[name="leqra-build"]')?.content || VERSION;
let registration, checking, latestBuild, pendingBuild, retry, reloading = false, lastCheck = -Infinity;

function applyUpdate() {
 if (!pendingBuild || reloading || document.hidden || navigator.onLine === false) return;
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
  const close = () => {channel.port1.close();channel.port2.close();};
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
 if (!worker || !latestBuild) return;
 const build = await workerBuild(worker);
 // A fresh page can still have the previous controller until installation
 // finishes. Only adopt the complete worker that matches the current server.
 if (worker !== serviceWorker.controller || build !== latestBuild || build === loadedBuild) return;
 pendingBuild = build;
 applyUpdate();
}

function checkUpdate(force=false) {
 if (document.hidden || navigator.onLine === false) return;
 applyUpdate();
 if (checking || !force && performance.now()-lastCheck<30000) return;
 lastCheck = performance.now();
 checking = (async () => {
  const response = await fetch('/api/build',{cache:'no-store'});
  if (!response.ok) return;
  const info = await response.json();
  if (typeof info.build !== 'string' || !/^v\d+\.\d+\.\d+-[0-9a-f]{16}$/.test(info.build)) return;
  latestBuild = info.build;
  // LAN HTTP web clips cannot install a worker, but can still refresh safely
  // while online using the fingerprinted asset URLs in the new shell.
  if (!serviceWorker) {
   if (latestBuild !== loadedBuild) {pendingBuild = latestBuild;applyUpdate();}
   return;
  }
  registration ||= await serviceWorker.register('/sw.js',{scope:'/',updateViaCache:'none'});
  await registration.update().catch(() => {});
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
setInterval(checkUpdate,60000);
})();
