'use strict';
const {test} = require('node:test'), assert = require('node:assert/strict');
const {readFileSync} = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const source = readFileSync(path.join(__dirname, '../web/assets/v4.46.0/sw.js'), 'utf8');
const origin = 'https://leqra.test', asset = '/assets/v4.46.0/game.js';

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return {promise, resolve, reject};
}
function boot({fetchResponse = () => new Response('fresh content'),
  match = async () => undefined, open = async () => ({put: async () => {}})} = {}) {
  const handlers = new Map(), calls = {fetch: 0, open: 0, match: []};
  vm.runInNewContext(source, {
    URL, self: {location: {origin}, addEventListener: (type, handler) => handlers.set(type, handler)},
    fetch: request => { calls.fetch++; return Promise.resolve().then(() => fetchResponse(request)); },
    caches: {
      match: (request, options) => { calls.match.push(request); return Promise.resolve().then(() => match(request, options)); },
      open: key => { calls.open++; return open(key); }
    }
  });
  function dispatch(pathname = '/', mode = 'navigate', method = 'GET') {
    const request = {method, mode, url: new URL(pathname, origin).href}, waits = [];
    let response, active = true;
    handlers.get('fetch')({
      request,
      respondWith(promise) { assert.ok(active); response = promise; },
      waitUntil(promise) {
        assert.ok(active, 'event lifetime must be extended during dispatch');
        waits.push(promise);
      }
    });
    active = false;
    return {request, waits, get response() { return response; }};
  }
  return {calls, dispatch};
}

test('asset misses clone before body consumption and keep cache writes alive', async () => {
  const opened = deferred(), putDone = deferred(), putStarted = deferred(), stored = [];
  const h = boot({open: () => opened.promise}), event = h.dispatch(asset, 'same-origin');
  assert.equal(event.waits.length, 1, 'fetch event registers its cache lifetime synchronously');
  const response = await event.response;
  assert.equal(await response.text(), 'fresh content');
  let finished = false;
  const lifetime = Promise.all(event.waits).then(() => { finished = true; });
  await Promise.resolve();
  assert.equal(finished, false, 'pending cache open keeps the event alive');
  opened.resolve({async put(key, copy) {
    stored.push({key, text: await copy.text()});
    putStarted.resolve();
    await putDone.promise;
  }});
  await putStarted.promise;
  assert.equal(stored.length, 1);
  assert.equal(stored[0].text, 'fresh content');
  assert.equal(stored[0].key, event.request);
  assert.equal(finished, false, 'pending cache put keeps the event alive');
  putDone.resolve();
  await lifetime;
  assert.equal(finished, true);
  assert.equal(h.calls.fetch, 1);
});

for (const failure of ['open', 'put']) {
  test('asset misses preserve their network response when cache ' + failure + ' fails', async () => {
    const h = boot({open: () => failure === 'open'
      ? Promise.reject(Error('storage unavailable'))
      : Promise.resolve({put: () => Promise.reject(Error('quota exceeded'))})});
    const event = h.dispatch(asset, 'same-origin'), response = await event.response;
    assert.equal(await response.text(), 'fresh content');
    await Promise.all(event.waits);
  });
}

for (const [pathname, mode] of [['/', 'navigate'], [asset, 'same-origin']]) {
  test(mode + ' does not cache an HTTP error response', async () => {
    const h = boot({fetchResponse: () => new Response('server error', {status: 503})});
    const event = h.dispatch(pathname, mode), response = await event.response;
    assert.equal(response.status, 503);
    assert.equal(await response.text(), 'server error');
    await Promise.all(event.waits);
    assert.equal(h.calls.open, 0);
  });
}

test('asset cache hits avoid a network request and a redundant cache write', async () => {
  const h = boot({match: async () => new Response('cached asset')}), event = h.dispatch(asset, 'same-origin');
  assert.equal(await (await event.response).text(), 'cached asset');
  await Promise.all(event.waits);
  assert.equal(h.calls.fetch, 0);
  assert.equal(h.calls.open, 0);
});

test('a failed asset cache lookup still serves a healthy network response', async () => {
  const h = boot({match: async () => { throw Error('cache read unavailable'); }});
  const event = h.dispatch(asset, 'same-origin');
  assert.equal(await (await event.response).text(), 'fresh content');
  await Promise.all(event.waits);
  assert.equal(h.calls.fetch, 1);
});

test('offline navigation falls back to the cached shell', async () => {
  const h = boot({
    fetchResponse: () => { throw Error('offline'); },
    match: async key => { assert.equal(key, '/'); return new Response('offline shell'); }
  }), event = h.dispatch('/?room=ARENA');
  assert.equal(await (await event.response).text(), 'offline shell');
  await Promise.all(event.waits);
  assert.equal(h.calls.open, 0);
});

test('APIs, sockets, foreign origins, non-GETs and unrelated files remain network-only', () => {
  const h = boot();
  for (const [pathname, mode, method] of [
    ['/ws', 'navigate', 'GET'], ['/healthz', 'navigate', 'GET'], ['/api/config', 'navigate', 'GET'],
    ['https://other.test' + asset, 'same-origin', 'GET'], [asset, 'same-origin', 'POST'],
    ['/unrelated.js', 'same-origin', 'GET']
  ]) {
    const event = h.dispatch(pathname, mode, method);
    assert.equal(event.response, undefined);
    assert.equal(event.waits.length, 0);
  }
  assert.equal(h.calls.fetch, 0);
  assert.equal(h.calls.open, 0);
  assert.equal(h.calls.match.length, 0);
});


test('direct asset navigation caches the asset without replacing the offline shell', async () => {
  const stored = [];
  const h = boot({open: async () => ({put: async (key, copy) => {
    stored.push({key, text: await copy.text()});
  }})}), event = h.dispatch(asset, 'navigate');
  assert.equal(await (await event.response).text(), 'fresh content');
  await Promise.all(event.waits);
  assert.equal(stored.length, 1);
  assert.equal(stored[0].key, event.request);
  assert.equal(stored[0].text, 'fresh content');
});

test('unrelated navigations neither replace nor fall back to the offline shell', () => {
  const h = boot();
  for (const pathname of ['/missing', '/unrelated.js']) {
    const event = h.dispatch(pathname, 'navigate');
    assert.equal(event.response, undefined);
    assert.equal(event.waits.length, 0);
  }
  assert.equal(h.calls.fetch, 0);
  assert.equal(h.calls.open, 0);
  assert.equal(h.calls.match.length, 0);
});

test('online app navigation returns fresh HTML without replacing the installed fallback', async () => {
  for (const pathname of ['/?room=ARENA', '/index.html?room=ARENA']) {
    const h = boot({open: async () => { throw Error('storage unavailable'); }});
    const event = h.dispatch(pathname);
    assert.equal(await (await event.response).text(), 'fresh content');
    await Promise.all(event.waits);
    assert.equal(h.calls.open, 0);
    assert.equal(h.calls.match.length, 0);
  }
});


function releaseHarness() {
  const current = 'v4.46.0', next = 'v4.47.0', storage = new Map();
  let serverVersion = current, offline = false, failedAsset = '';
  const shell = version => '<script src="/assets/' + version + '/game.js"></script>';
  const cacheName = version => 'leqra-app-' + version;
  const keyFor = request => new URL(typeof request === 'string' ? request : request.url, origin).href;
  const network = async request => {
    const url = new URL(keyFor(request));
    if (offline || url.pathname === failedAsset) throw Error('connection interrupted');
    return new Response(url.pathname === '/' ? shell(serverVersion) : 'asset ' + url.pathname);
  };
  function worker(version) {
    const handlers = new Map(), lifecycle = {skipWaiting: 0, claim: 0};
    vm.runInNewContext(source.replace("const VERSION = 'v4.46.0';", "const VERSION = '" + version + "';"), {
      URL,
      self: {
        location: {origin}, addEventListener: (type, handler) => handlers.set(type, handler),
        skipWaiting: async () => { lifecycle.skipWaiting++; },
        clients: {claim: async () => { lifecycle.claim++; }}
      },
      fetch: network,
      caches: {
        keys: async () => [...storage.keys()],
        delete: async key => storage.delete(key),
        open: async name => {
          if (!storage.has(name)) storage.set(name, new Map());
          const entries = storage.get(name);
          return {
            // Cache.addAll commits its batch only after every fetch succeeds.
            async addAll(paths) {
              const responses = await Promise.all(paths.map(network));
              paths.forEach((path, i) => entries.set(keyFor(path), responses[i]));
            },
            put: async (key, response) => entries.set(keyFor(key), response)
          };
        },
        match: async (key, options) => {
          const stores = options?.cacheName ? [storage.get(options.cacheName)] : storage.values();
          for (const entries of stores) {
            const response = entries?.get(keyFor(key));
            if (response) return response.clone();
          }
        }
      }
    });
    async function event(type) {
      const waits = [];
      handlers.get(type)({waitUntil: promise => waits.push(promise)});
      await Promise.all(waits);
    }
    async function request(pathname = '/', mode = 'navigate') {
      const waits = [];
      let response;
      handlers.get('fetch')({
        request: {method: 'GET', mode, url: new URL(pathname, origin).href},
        respondWith: promise => { response = promise; },
        waitUntil: promise => waits.push(promise)
      });
      const result = await response;
      await Promise.all(waits);
      return result;
    }
    return {event, request, lifecycle};
  }
  return {
    current, next, storage, shell, cacheName, keyFor, worker,
    deploy() { serverVersion = next; },
    interruptInstall() { failedAsset = '/assets/' + next + '/icon-512.png'; },
    offline() { offline = true; }
  };
}

test('an interrupted release install preserves the old complete offline game', async () => {
  const h = releaseHarness(), oldWorker = h.worker(h.current);
  await oldWorker.event('install');
  h.deploy();
  assert.equal(await (await oldWorker.request('/?room=ARENA')).text(), h.shell(h.next),
    'online navigation still loads the new release');
  h.interruptInstall();
  const nextWorker = h.worker(h.next);
  await assert.rejects(nextWorker.event('install'), /connection interrupted/);
  assert.equal(nextWorker.lifecycle.skipWaiting, 0);
  h.offline();
  assert.equal(await (await oldWorker.request('/index.html?room=ARENA')).text(), h.shell(h.current));
  assert.match(await (await oldWorker.request('/assets/' + h.current + '/game.js', 'same-origin')).text(),
    /asset .*game\.js/);
  assert.equal(h.storage.get(h.cacheName(h.current)).size > 1, true);
});

test('a successful release install switches offline shell and assets together', async () => {
  const h = releaseHarness();
  // Another same-origin application may also have cached '/' first.
  h.storage.set('other-app', new Map([[h.keyFor('/'), new Response('unrelated shell')]]));
  const oldWorker = h.worker(h.current);
  await oldWorker.event('install');
  h.deploy();
  const nextWorker = h.worker(h.next);
  await nextWorker.event('install');
  await nextWorker.event('activate');
  assert.equal(nextWorker.lifecycle.skipWaiting, 1);
  assert.equal(nextWorker.lifecycle.claim, 1);
  assert.equal(h.storage.has(h.cacheName(h.current)), false);
  assert.equal(h.storage.has('other-app'), true);
  h.offline();
  assert.equal(await (await nextWorker.request()).text(), h.shell(h.next));
  assert.match(await (await nextWorker.request('/assets/' + h.next + '/game.js', 'same-origin')).text(),
    /asset .*game\.js/);
});
