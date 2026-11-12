'use strict';
const {test} = require('node:test'), assert = require('node:assert/strict');
const {readFileSync} = require('node:fs'), vm = require('node:vm');
const {assetPath, assetVersion} = require('./web_assets.cjs');
const source = readFileSync(assetPath('sw.js'), 'utf8');
const origin = 'https://leqra.test', asset = '/assets/' + assetVersion + '/game.js';

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return {promise, resolve, reject};
}
function boot({fetchResponse = () => new Response('fresh content'),
  match = async () => undefined, open = async () => ({put: async () => {}}),
  schedule = setTimeout, cancel = clearTimeout} = {}) {
  const handlers = new Map(), calls = {fetch: 0, open: 0, match: []};
  vm.runInNewContext(source, {
    URL, Request, Response, AbortController, setTimeout: schedule, clearTimeout: cancel,
    self: {location: {origin, href: origin + '/sw.js'}, addEventListener: (type, handler) => handlers.set(type, handler)},
    fetch: (request, options) => { calls.fetch++; return Promise.resolve().then(() => fetchResponse(request, options)); },
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
  assert.equal(stored[0].key, asset);
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

test('versioned assets never use a same-URL response from another cache', async () => {
  for (const installed of [false, true]) {
    const h = boot({match: async (_request, options) => {
      if (options?.cacheName !== 'leqra-app-' + assetVersion) return new Response('wrong release header');
      return installed ? new Response('installed release asset') : undefined;
    }}), event = h.dispatch(asset, 'same-origin');
    assert.equal(await (await event.response).text(), installed ? 'installed release asset' : 'fresh content');
    await Promise.all(event.waits);
    assert.equal(h.calls.fetch, installed ? 0 : 1);
  }
});

test('a failed asset cache lookup still serves a healthy network response', async () => {
  const h = boot({match: async () => { throw Error('cache read unavailable'); }});
  const event = h.dispatch(asset, 'same-origin');
  assert.equal(await (await event.response).text(), 'fresh content');
  await Promise.all(event.waits);
  assert.equal(h.calls.fetch, 1);
});

test('runtime asset misses do not contaminate this cache with another build’s response', async () => {
  const h = boot({fetchResponse: () => new Response('newer build asset', {
    headers: {'X-Leqra-Build': assetVersion + '-2222222222222222'}
  })}), event = h.dispatch(asset, 'same-origin');
  assert.equal(await (await event.response).text(), 'newer build asset');
  await Promise.all(event.waits);
  assert.equal(h.calls.open, 0, 'a cache miss must not merge two builds into one offline bundle');
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

test('a stalled navigation uses the installed shell and cancels the network request', async () => {
  const pending = deferred();
  let signal, timeout;
  const h = boot({
    fetchResponse: (_request, options) => { signal = options.signal; return pending.promise; },
    match: async () => new Response('installed shell'),
    schedule: callback => { timeout = callback; }
  }), event = h.dispatch();
  await timeout();
  assert.equal(await (await event.response).text(), 'installed shell');
  assert.equal(signal.aborted, true);
  await Promise.all(event.waits);
});

test('a slow cache lookup cannot abort a navigation that wins the race', async () => {
  const pending = deferred(), lookup = deferred();
  let signal, timeout;
  const h = boot({
    fetchResponse: (_request, options) => { signal = options.signal; return pending.promise; },
    match: () => lookup.promise,
    schedule: callback => { timeout = callback; }
  }), event = h.dispatch();
  const expired = timeout();
  pending.resolve(new Response('fresh shell'));
  assert.equal(await (await event.response).text(), 'fresh shell');
  lookup.resolve(new Response('installed shell'));
  await expired;
  assert.equal(signal.aborted, false);
});

test('temporary upstream errors use this release’s cached shell when available', async () => {
  for (const status of [502, 503, 504]) {
    const h = boot({
      fetchResponse: () => new Response('upstream unavailable', {status}),
      match: async (key, options) => {
        assert.equal(key, '/');
        assert.equal(options.cacheName, 'leqra-app-' + assetVersion);
        return new Response('installed shell');
      }
    });
    const event = h.dispatch('/index.html?room=ARENA');
    assert.equal(await (await event.response).text(), 'installed shell');
    await Promise.all(event.waits);
    assert.equal(h.calls.open, 0);
  }
});

test('failed cache reads and non-temporary HTTP responses preserve navigation responses', async () => {
  const upstream = boot({
    fetchResponse: () => new Response('upstream unavailable', {status: 503}),
    match: async () => { throw Error('cache read unavailable'); }
  });
  assert.equal((await upstream.dispatch().response).status, 503);
  const missing = boot({fetchResponse: () => new Response('missing', {status: 404})});
  assert.equal((await missing.dispatch().response).status, 404);
  assert.equal(missing.calls.match.length, 0);
});

test('APIs, sockets, foreign origins, non-GETs and unrelated files remain network-only', () => {
  const h = boot();
  for (const [pathname, mode, method] of [
    ['/ws', 'navigate', 'GET'], ['/healthz', 'navigate', 'GET'], ['/api/config', 'navigate', 'GET'], ['/sw.js', 'same-origin', 'GET'],
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
  assert.equal(stored[0].key, asset);
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
  const current = assetVersion, next = current.replace(/\d+$/, patch => String(Number(patch) + 1)), storage = new Map();
  const currentBuild = current + '-1111111111111111', nextBuild = current + '-2222222222222222', requests = [];
  let serverVersion = current, serverBuild, offline = false, failedAsset = '', failedStatus = 0, mixedShell = false, assetTag = '', wrongBuildAsset = '';
  const shell = (version, build) => '<meta name="leqra-version" content="' + version + '">' + (build ? '<meta name="leqra-build" content="' + build + '">' : '') + '<script src="assets/' + version + '/game.js' + (build ? '?build=' + build : '') + '"></script>';
  const cacheName = version => 'leqra-app-' + version;
  const keyFor = request => new URL(typeof request === 'string' ? request : request.url, origin).href;
  const network = async (request, options) => {
    const url = new URL(keyFor(request));
    requests.push({url: url.href, options});
    if (offline || url.pathname === failedAsset && !failedStatus) throw Error('connection interrupted');
    if (url.pathname === failedAsset) return new Response('asset unavailable', {status: failedStatus});
    const headers = serverBuild ? {'X-Leqra-Build': url.pathname === wrongBuildAsset ? currentBuild : serverBuild} : {};
    return new Response(url.pathname === '/' ? shell(serverVersion, serverBuild) + (mixedShell ? '<link rel="stylesheet" href="assets/' + current + '/style.css">' : '') : 'asset ' + url.pathname + assetTag, {headers});
  };
  function worker(version, build) {
    const handlers = new Map(), lifecycle = {skipWaiting: 0, claim: 0};
    vm.runInNewContext(source.replace("const VERSION = '" + current + "';", "const VERSION = '" + version + "';"), {
      URL, Request, Response, AbortController, setTimeout, clearTimeout,
      self: {
        LEQRA_BUILD: build, location: {origin, href: origin + '/sw.js'}, addEventListener: (type, handler) => handlers.set(type, handler),
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
              if (responses.some(response => !response.ok)) throw Error('precache HTTP failure');
              paths.forEach((path, i) => entries.set(keyFor(path), responses[i]));
            },
            put: async (key, response) => entries.set(keyFor(key), response.clone())
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
    async function message(data) {
      const replies = [], waits = [];
      handlers.get('message')({data, ports: [{postMessage: reply => replies.push(reply)}], waitUntil: promise => waits.push(promise)});
      await Promise.all(waits);
      return replies;
    }
    return {event, request, message, lifecycle};
  }
  return {
    current, next, currentBuild, nextBuild, storage, shell, cacheName, keyFor, worker, requests,
    deploy() { serverVersion = next; },
    serveBuild(build) { serverBuild = build; },
    tagAssets(tag) { assetTag = tag; },
    mismatchAssetBuild(path) { wrongBuildAsset = path; },
    interruptInstall() { failedAsset = '/assets/' + next + '/icon-512.png'; },
    failInstallHTTP(status, version = next) { failedAsset = '/assets/' + version + '/style.css'; failedStatus = status; },
    serveMixedShell() { mixedShell = true; },
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

test('HTTP precache failures preserve the old complete release and never activate the new worker', async () => {
  for (const status of [404, 503]) {
    const h = releaseHarness(), oldWorker = h.worker(h.current);
    await oldWorker.event('install');
    const previous = h.storage.get(h.cacheName(h.current)).size;
    h.deploy();h.failInstallHTTP(status);
    const nextWorker = h.worker(h.next);
    await assert.rejects(nextWorker.event('install'), /asset|precache|unavailable|HTTP/i);
    assert.equal(nextWorker.lifecycle.skipWaiting, 0);
    assert.equal(h.storage.get(h.cacheName(h.current)).size, previous);
    h.offline();
    assert.equal(await (await oldWorker.request()).text(), h.shell(h.current));
    assert.match(await (await oldWorker.request('/assets/' + h.current + '/style.css', 'same-origin')).text(), /asset .*style\.css/);
  }
});

test('a current version marker cannot install a shell with assets from an older release', async () => {
  const h = releaseHarness(), oldWorker = h.worker(h.current);
  await oldWorker.event('install');h.deploy();h.serveMixedShell();
  const nextWorker = h.worker(h.next);
  await assert.rejects(nextWorker.event('install'), /shell|release|asset/i);
  assert.equal(nextWorker.lifecycle.skipWaiting, 0);
  h.offline();
  assert.equal(await (await oldWorker.request()).text(), h.shell(h.current));
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
  assert.equal(h.storage.has(h.cacheName(h.current)), true, 'a prior complete release remains available to retained clients');
  assert.equal(h.storage.has('other-app'), true);
  h.offline();
  assert.equal(await (await nextWorker.request()).text(), h.shell(h.next));
  assert.match(await (await nextWorker.request('/assets/' + h.next + '/game.js', 'same-origin')).text(),
    /asset .*game\.js/);
});

test('a worker refuses a root shell served by a different release', async () => {
  const h = releaseHarness(), installed = h.worker(h.current);
  await installed.event('install');
  h.deploy();
  const stale = h.worker(h.current);
  await assert.rejects(stale.event('install'), /shell changed/);
  assert.equal(stale.lifecycle.skipWaiting, 0);
  h.offline();
  assert.equal(await (await installed.request()).text(), h.shell(h.current));
});

test('a same-version build switches the offline shell and canonical assets together', async () => {
  const h = releaseHarness();h.serveBuild(h.currentBuild);h.tagAssets(' committed');
  const installed = h.worker(h.current, h.currentBuild);await installed.event('install');
  h.serveBuild(h.nextBuild);h.tagAssets(' replacement');const before = h.requests.length;
  const replacement = h.worker(h.current, h.nextBuild);await replacement.event('install');await replacement.event('activate');
  const requests = h.requests.slice(before), root = requests.find(request => new URL(request.url).pathname === '/');
  assert.equal(root.options.cache, 'no-store');
  for (const request of requests.filter(request => new URL(request.url).pathname.startsWith('/assets/'))) {
    assert.equal(new URL(request.url).searchParams.get('build'), h.nextBuild);
    assert.equal(request.options.cache, 'reload');
  }
  const asset = '/assets/' + h.current + '/game.js', cache = h.storage.get(h.cacheName(h.nextBuild));
  assert.ok(cache.has(h.keyFor(asset)), 'the cache stores canonical paths');
  assert.equal(cache.has(h.keyFor(asset + '?build=' + h.nextBuild)), false);
  h.offline();
  assert.equal(await (await replacement.request()).text(), h.shell(h.current, h.nextBuild));
  assert.equal(await (await replacement.request(asset + '?build=' + h.nextBuild, 'same-origin')).text(), 'asset ' + asset + ' replacement');
  assert.equal(await (await replacement.request(asset + '?build=' + h.currentBuild, 'same-origin')).text(), 'asset ' + asset + ' committed');
  assert.equal(await (await installed.request()).text(), h.shell(h.current, h.currentBuild));
});

test('a failed reinstall cannot partially overwrite an already complete build cache', async () => {
  const h = releaseHarness();h.serveBuild(h.currentBuild);h.tagAssets(' committed');
  const installed = h.worker(h.current, h.currentBuild);await installed.event('install');
  h.tagAssets(' uncommitted');h.failInstallHTTP(503, h.current);
  await assert.rejects(h.worker(h.current, h.currentBuild).event('install'));
  h.offline();
  const asset = '/assets/' + h.current + '/theme.js';
  assert.equal(await (await installed.request(asset, 'same-origin')).text(), 'asset ' + asset + ' committed');
  assert.equal(await (await installed.request()).text(), h.shell(h.current, h.currentBuild));
});

test('worker build mismatches reject both a stale root shell and a stale asset response', async () => {
  for (const mismatch of ['shell', 'asset']) {
    const h = releaseHarness();h.serveBuild(h.currentBuild);
    const installed = h.worker(h.current, h.currentBuild);await installed.event('install');
    if (mismatch === 'asset') {h.serveBuild(h.nextBuild);h.mismatchAssetBuild('/assets/' + h.current + '/style.css');}
    const replacement = h.worker(h.current, h.nextBuild);
    await assert.rejects(replacement.event('install'), /build|shell|asset/i);
    assert.equal(replacement.lifecycle.skipWaiting, 0);
    h.offline();assert.equal(await (await installed.request()).text(), h.shell(h.current, h.currentBuild));
  }
});

test('activation keeps only two previous app caches and leaves other applications alone', async () => {
  const h = releaseHarness();
  h.storage.set('other-app', new Map());
  const previous = Array.from({length:5}, (_, i) => 'leqra-app-previous-' + i);
  for (const name of previous) h.storage.set(name, new Map());
  const worker = h.worker(h.current);await worker.event('install');await worker.event('activate');
  assert.deepEqual([...h.storage.keys()].filter(name => name.startsWith('leqra-app-')).sort(), [...previous.slice(-2), h.cacheName(h.current)].sort());
  assert.equal(h.storage.has('other-app'), true);
});

test('worker build probes reply with the actual injected build and release', async () => {
  const h = releaseHarness(), injected = h.worker(h.current, h.currentBuild), raw = h.worker(h.current);
  assert.deepEqual(JSON.parse(JSON.stringify(await injected.message({type:'LEQRA_BUILD_INFO'}))), [{build:h.currentBuild,version:h.current}]);
  assert.deepEqual(JSON.parse(JSON.stringify(await raw.message({type:'LEQRA_BUILD_INFO'}))), [{build:h.current,version:h.current}]);
  assert.deepEqual(await injected.message({type:'UNRELATED'}), []);
});
