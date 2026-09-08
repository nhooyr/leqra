'use strict';
const VERSION = 'v4.38.0';
const CACHE = 'leqra-app-' + VERSION;
const BASE = '/assets/' + VERSION + '/';
const SHELL = [
  '/',
  BASE + 'theme.js',
  BASE + 'theme.css',
  BASE + 'style.css',
  BASE + 'favicon.svg',
  BASE + 'netcode.js',
  BASE + 'game.js',
  BASE + 'pwa.js',
  BASE + 'manifest.webmanifest',
  BASE + 'icon-192.png',
  BASE + 'icon-512.png',
  BASE + 'icon-maskable-512.png',
  BASE + 'apple-touch-icon.png'
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

  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request).then(response => {
        if (response.ok) caches.open(CACHE).then(cache => cache.put('/', response.clone()));
        return response;
      }).catch(() => caches.match('/'))
    );
    return;
  }

  if (url.pathname.startsWith(BASE)) {
    event.respondWith(caches.match(request).then(cached => cached || fetch(request).then(response => {
      if (response.ok) caches.open(CACHE).then(cache => cache.put(request, response.clone()));
      return response;
    })));
  }
});
