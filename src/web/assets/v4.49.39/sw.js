'use strict';
const VERSION = 'v4.49.39';
const BUILD = self.LEQRA_BUILD || VERSION;
const CACHE = 'leqra-app-' + BUILD;
let resetting=false;
const writes=new Set();
function trackWrite(promise){writes.add(promise);promise.then(()=>writes.delete(promise),()=>writes.delete(promise));return promise;}
const BASE = '/assets/' + VERSION + '/';
const SHELL = [
  BASE + 'theme.js',
  BASE + 'theme.css',
  BASE + 'style.css',
  BASE + 'favicon.svg',
  BASE + 'favicon-256.png',
  BASE + 'netcode.js',
  BASE + 'game.js',
  BASE + 'infinite-maze.js',
  BASE + 'infinite.js',
  BASE + 'pwa.js',
  BASE + 'manifest.webmanifest',
  BASE + 'icon-192.png',
  BASE + 'icon-512.png',
  BASE + 'icon-1024.png',
  BASE + 'icon-maskable-512.png',
  BASE + 'icon-maskable-1024.png',
  BASE + 'apple-touch-icon.png',
  BASE + 'apple-touch-icon-512.png'
];

async function installShell() {
  if(resetting)return;
  const response = await fetch('/', {cache: 'no-store'});
  if (!response.ok) throw new Error('The leqra shell is unavailable.');
  const html = await response.clone().text();
  const shellVersion = '<meta name="leqra-version" content="' + VERSION + '">';
  const links = [...html.matchAll(/\b(?:src|href)="(assets\/[^\"]+)"/g)].map(match => match[1].split('?')[0]);
  if (!html.includes(shellVersion) || !links.includes(BASE.slice(1) + 'game.js') || links.some(path => !path.startsWith(BASE.slice(1)))) {
    throw new Error('The leqra shell changed while installing.');
  }
  if (BUILD !== VERSION && !html.includes('<meta name="leqra-build" content="' + BUILD + '">')) {
    throw new Error('The leqra build changed while installing.');
  }
  // Fetch a complete, fresh bundle before writing it. A build query also avoids
  // an older immutable HTTP entry when CSS changed without a version change.
  const files = await Promise.all(SHELL.map(async path => {
    const url = new URL(path, self.location.origin);
    url.searchParams.set('build', BUILD);
    const asset = await fetch(url.href, {cache: 'reload'});
    const build = asset.headers.get('X-Leqra-Build');
    if (!asset.ok || build && build !== BUILD) throw new Error('A leqra asset changed while installing.');
    return [path, asset];
  }));
  const existed = (await caches.keys()).includes(CACHE);
  if(resetting)return;
  await trackWrite((async()=>{
    try {
      const cache = await caches.open(CACHE);
      if(resetting)return;
      await Promise.all(files.map(([path, asset]) => cache.put(path, asset)));
      if(!resetting)await cache.put('/', response);
    } catch (error) {
      if (!existed) await caches.delete(CACHE).catch(() => {});
      throw error;
    }
  })());
  if(!resetting)await self.skipWaiting();
}

self.addEventListener('install', event => event.waitUntil(installShell()));

self.addEventListener('activate', event => {
  if(resetting)return;
  event.waitUntil(caches.keys().then(keys => Promise.all(
    // Keep two prior bundles available to pages that defer an update mid-match.
    keys.filter(key => key.startsWith('leqra-app-') && key !== CACHE).slice(0, -2).map(key => caches.delete(key))
  )).then(() => {if(!resetting)return self.clients.claim();}));
});

self.addEventListener('message', event => {
  if (event.data?.type === 'LEQRA_BUILD_INFO') event.ports?.[0]?.postMessage({build: BUILD, version: VERSION});
  if(event.data?.type==='LEQRA_RESET'){
    resetting=true;
    const stopped=Promise.allSettled([...writes]).then(()=>event.ports?.[0]?.postMessage({type:'LEQRA_RESET_DONE'}));
    event.waitUntil?.(stopped);
  }
});

async function appNavigation(request) {
  const cachedShell = () => caches.match('/', {cacheName: CACHE}).catch(() => undefined);
  const controller = new AbortController();
  const network = fetch(request, {signal: controller.signal, cache: 'no-store'}).then(async result => {
    if (![502, 503, 504].includes(result.status)) return result;
    return (await cachedShell()) || result;
  }, cachedShell);
  let timer;
  const slow = new Promise(resolve => {
    timer = setTimeout(async () => {
      const response = await cachedShell();
      if (response) resolve({response, fallback: true});
    }, 3000);
  });
  try {
    const {response, fallback} = await Promise.race([network.then(response => ({response})), slow]);
    if (fallback) controller.abort();
    return response;
  } finally {
    clearTimeout(timer);
  }
}

self.addEventListener('fetch', event => {
  if(resetting)return;
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Online APIs and sockets remain network-only.
  if (url.pathname === '/ws' || url.pathname === '/ws/infinite' || url.pathname === '/healthz' || url.pathname.startsWith('/api/')) return;

  let cacheWrite = Promise.resolve();
  const storeResponse = (key, response) => {
    if (response.ok&&!resetting) {
      // Clone before returning the response: the browser may consume its body
      // while opening Cache Storage is still pending.
      const copy = response.clone();
      cacheWrite = trackWrite(Promise.resolve().then(() => resetting?null:caches.open(CACHE))
        .then(cache => {if(cache&&!resetting)return cache.put(key, copy);}).catch(() => {}));
    }
    return response;
  };

  let response;
  // Keep the installed shell paired with this version's precached assets.
  // New-release HTML can load online, but must not replace the offline fallback
  // before its own worker finishes installing the complete replacement.
  if (request.mode === 'navigate' && (url.pathname === '/' || url.pathname === '/index.html')) {
    response = appNavigation(request);
  } else {
    const asset = url.pathname.match(/^\/assets\/(v\d+\.\d+\.\d+)\/([^/]+)$/);
    if (!asset || !SHELL.includes(BASE + asset[2])) return;
    const requested = url.searchParams.get('build');
    const cacheBuild = requested && new RegExp('^' + asset[1].replaceAll('.', '\\.') + '(?:-[0-9a-f]{16})?$').test(requested)
      ? requested : asset[1] === VERSION ? BUILD : asset[1];
    response = caches.match(url.pathname, {cacheName: 'leqra-app-' + cacheBuild}).catch(() => undefined).then(cached =>
      cached || fetch(request).then(result => cacheBuild === BUILD && url.pathname.startsWith(BASE) &&
        (!result.headers.get('X-Leqra-Build') || result.headers.get('X-Leqra-Build') === BUILD)
        ? storeResponse(url.pathname, result) : result)
    );
  }

  event.respondWith(response);
  // Register synchronously, and keep the worker alive through the eventual
  // cache write. Storage failures must not turn a valid response into an error.
  event.waitUntil(response.then(() => cacheWrite).catch(() => {}));
});
