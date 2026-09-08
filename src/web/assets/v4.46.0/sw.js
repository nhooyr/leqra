'use strict';
const VERSION = 'v4.46.0';
const CACHE = 'leqra-app-' + VERSION;
const BASE = '/assets/' + VERSION + '/';
const SHELL = [
  '/',
  BASE + 'theme.js',
  BASE + 'theme.css',
  BASE + 'style.css',
  BASE + 'favicon.svg',
  BASE + 'favicon-256.png',
  BASE + 'netcode.js',
  BASE + 'game.js',
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

self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(
    keys.filter(key => key.startsWith('leqra-app-') && key !== CACHE).map(key => caches.delete(key))
  )).then(() => self.clients.claim()));
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Online APIs and sockets remain network-only. Local/offline play never opens
  // them unless the player explicitly shares/joins a room or uses matchmaking.
  if (url.pathname === '/ws' || url.pathname === '/healthz' || url.pathname.startsWith('/api/')) return;

  let cacheWrite = Promise.resolve();
  const storeResponse = (key, response) => {
    if (response.ok) {
      // Clone before returning the response: the browser may consume its body
      // while opening Cache Storage is still pending.
      const copy = response.clone();
      cacheWrite = Promise.resolve().then(() => caches.open(CACHE))
        .then(cache => cache.put(key, copy)).catch(() => {});
    }
    return response;
  };

  let response;
  // Keep the installed shell paired with this version's precached assets.
  // New-release HTML can load online, but must not replace the offline fallback
  // before its own worker finishes installing the complete replacement.
  if (request.mode === 'navigate' && (url.pathname === '/' || url.pathname === '/index.html')) {
    response = fetch(request).catch(() => caches.match('/', {cacheName: CACHE}));
  } else if (url.pathname.startsWith(BASE)) {
    response = caches.match(request).catch(() => undefined).then(cached =>
      cached || fetch(request).then(result => storeResponse(request, result))
    );
  } else return;

  event.respondWith(response);
  // Register synchronously, and keep the worker alive through the eventual
  // cache write. Storage failures must not turn a valid response into an error.
  event.waitUntil(response.then(() => cacheWrite).catch(() => {}));
});
