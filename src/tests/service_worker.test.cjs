'use strict';
const {test} = require('node:test'), assert = require('node:assert/strict');
const {readFileSync} = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const source = readFileSync(path.join(__dirname, '../web/assets/v4.45.1/sw.js'), 'utf8');
const origin = 'https://leqra.test', asset = '/assets/v4.45.1/game.js';

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
      match: request => { calls.match.push(request); return Promise.resolve().then(() => match(request)); },
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

for (const [label, pathname, mode] of [['navigation', '/', 'navigate'], ['asset miss', asset, 'same-origin']]) {
  test(label + ' clones before body consumption and keeps cache writes alive', async () => {
    const opened = deferred(), putDone = deferred(), putStarted = deferred(), stored = [];
    const h = boot({open: () => opened.promise}), event = h.dispatch(pathname, mode);
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
    assert.equal(stored[0].key, mode === 'navigate' ? '/' : event.request);
    assert.equal(finished, false, 'pending cache put keeps the event alive');
    putDone.resolve();
    await lifetime;
    assert.equal(finished, true);
    assert.equal(h.calls.fetch, 1);
  });

  for (const failure of ['open', 'put']) {
    test(label + ' preserves its network response when cache ' + failure + ' fails', async () => {
      const h = boot({open: () => failure === 'open'
        ? Promise.reject(Error('storage unavailable'))
        : Promise.resolve({put: () => Promise.reject(Error('quota exceeded'))})});
      const event = h.dispatch(pathname, mode), response = await event.response;
      assert.equal(await response.text(), 'fresh content');
      await Promise.all(event.waits);
    });
  }

  test(label + ' does not cache an HTTP error response', async () => {
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
