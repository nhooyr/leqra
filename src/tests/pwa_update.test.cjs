'use strict';
const {test} = require('node:test'), assert = require('node:assert/strict');
const {readFileSync} = require('node:fs'), vm = require('node:vm');
const {assetPath, assetVersion} = require('./web_assets.cjs');
const source = readFileSync(assetPath('pwa.js'), 'utf8');
const buildA = assetVersion + '-1111111111111111', buildB = assetVersion + '-2222222222222222';

function target(properties = {}) {
  const listeners = new Map();
  return Object.assign(properties, {
    addEventListener(type, listener, options) {
      if (!listeners.has(type)) listeners.set(type, []);
      listeners.get(type).push({listener, once: !!options?.once});
    },
    dispatch(type, properties = {}) {
      for (const entry of [...listeners.get(type) || []]) {
        if (entry.once) listeners.set(type, listeners.get(type).filter(item => item !== entry));
        entry.listener({type, ...properties});
      }
    }
  });
}

function boot({pageBuild = buildA, controllerBuild = buildA, latestBuild = buildA,
  readyState = 'loading', protocol = 'https:', supported = true, secure = true, safe = true} = {}) {
  let now = 0, nextTimer = 0;
  const timers = new Map(), calls = {register: [], update: 0, fetch: [], probes: [], reload: 0, prepare: 0};
  const state = {safe, latestBuild, fetchError: null, updateError: null, registerError: null, responseOK: true};
  const schedule = (callback, delay, interval) => {
    const id = ++nextTimer;
    timers.set(id, {callback, at: now + delay, interval});
    return id;
  };
  const clear = id => timers.delete(id);
  const worker = (build, {silent = false, error = false} = {}) => ({
    postMessage(message, ports) {
      calls.probes.push({worker: this, message});
      if (error) throw Error('worker unavailable');
      if (!silent) queueMicrotask(() => ports[0].postMessage({build, version: assetVersion}));
    }
  });
  class Channel {
    constructor() {
      this.port1 = {onmessage: null, closed: false, close() { this.closed = true; }};
      this.port2 = {closed: false, close() { this.closed = true; }, postMessage: data => {
        if (!this.port1.closed) this.port1.onmessage?.({data});
      }};
    }
  }
  const registration = {async update() {
    calls.update++;
    if (state.updateError) throw state.updateError;
    await state.onUpdate?.();
  }};
  const sw = target({controller: controllerBuild ? worker(controllerBuild) : null,
    async register(path, options) {
      calls.register.push({path, options});
      if (state.registerError) throw state.registerError;
      return registration;
    }
  });
  const navigator = {onLine: true};
  if (supported) navigator.serviceWorker = sw;
  const document = target({hidden: false, readyState,
    querySelector: selector => selector === 'meta[name="leqra-build"]' && pageBuild ? {content: pageBuild} : null
  });
  const window = target({isSecureContext: secure, leqra: {prepareUpdate() {
    calls.prepare++;
    if (state.prepareError) throw state.prepareError;
    return state.safe;
  }}});
  vm.runInNewContext(source, {
    window, document, navigator, MessageChannel: Channel,
    location: {protocol, reload() { calls.reload++; }}, performance: {now: () => now},
    setTimeout: (callback, delay) => schedule(callback, delay, 0), clearTimeout: clear,
    setInterval: (callback, delay) => schedule(callback, delay, delay), clearInterval: clear,
    AbortController,
    fetch: async (url, options) => {
      calls.fetch.push({url, options});
      await state.onFetch?.(options);
      if (state.fetchError) throw state.fetchError;
      return {ok: state.responseOK, json: async () => ({version: assetVersion.slice(1), build: state.latestBuild})};
    }
  });
  const flush = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };
  async function advance(milliseconds) {
    const end = now + milliseconds;
    for (let iterations = 0; iterations < 1000; iterations++) {
      let next;
      for (const [id, timer] of timers) if (timer.at <= end && (!next || timer.at < next[1].at)) next = [id, timer];
      if (!next) break;
      const [id, timer] = next;
      now = timer.at;
      if (timer.interval) timer.at += timer.interval;
      else timers.delete(id);
      timer.callback();
      await flush();
      assert.ok(iterations < 999, 'timer loop must remain bounded');
    }
    now = end;
    await flush();
  }
  async function fire(surface, type, properties) { surface.dispatch(type, properties); await flush(); }
  async function changeController(build, options) {
    sw.controller = build ? worker(build, options) : null;
    await fire(sw, 'controllerchange');
  }
  return {state, calls, window, document, navigator, sw, worker, timers, flush, advance, fire, changeController,
    load: () => fire(window, 'load')};
}

test('PWA discovers its build without HTTP caching and registers the stable worker', async () => {
  const h = boot();
  assert.equal(h.calls.register.length, 0);
  await h.load();
  assert.equal(h.calls.fetch.length, 1);
  assert.equal(h.calls.fetch[0].url, '/api/build');
  assert.equal(h.calls.fetch[0].options.cache, 'no-store');
  assert.ok(h.calls.fetch[0].options.signal instanceof AbortSignal);
  assert.deepEqual(JSON.parse(JSON.stringify(h.calls.register)), [{path: '/sw.js', options: {scope: '/', updateViaCache: 'none'}}]);
  assert.equal(h.calls.update, 1);
  assert.equal(h.calls.reload, 0);
});

test('PWA also starts when loaded after the window load event', async () => {
  const h = boot({readyState: 'complete'});
  await h.flush();
  assert.equal(h.calls.register.length, 1);
});

test('direct file launches do not start update work', async () => {
  const h = boot({protocol: 'file:'});
  await h.load();
  await h.advance(120000);
  assert.equal(h.calls.fetch.length, 0);
  assert.equal(h.calls.register.length, 0);
  assert.equal(h.timers.size, 0);
});

test('LAN HTTP and browsers without service workers refresh safely from fresh build metadata', async () => {
  for (const options of [{protocol: 'http:', secure: false}, {supported: false}]) {
    const h = boot({...options, latestBuild: buildB, safe: false});
    await h.load();
    assert.equal(h.calls.fetch.length, 1);
    assert.equal(h.calls.register.length, 0);
    assert.equal(h.calls.probes.length, 0);
    assert.equal(h.calls.reload, 0, 'an insecure web clip still preserves a live match');
    await h.advance(2000);
    assert.equal(h.calls.reload, 0);
    h.state.safe = true;
    await h.advance(1000);
    assert.equal(h.calls.reload, 1);
    await h.advance(3000);
    assert.equal(h.calls.reload, 1);
  }
});

test('LAN HTTP never refreshes a current build or an offline retained game', async () => {
  const h = boot({protocol: 'http:', secure: false});
  await h.load();
  assert.equal(h.calls.reload, 0);
  h.navigator.onLine = false;
  h.state.latestBuild = buildB;
  await h.advance(60000);
  await h.fire(h.document, 'visibilitychange');
  assert.equal(h.calls.fetch.length, 1);
  assert.equal(h.calls.reload, 0);
  h.navigator.onLine = true;
  await h.fire(h.window, 'online');
  assert.equal(h.calls.reload, 1);
});

test('a first same-build controller claim never reloads a fresh page', async () => {
  const h = boot({controllerBuild: null});
  await h.load();
  await h.changeController(buildA);
  await h.advance(1000);
  assert.equal(h.calls.reload, 0);
  assert.equal(h.calls.prepare, 0);
});

test('fresh HTML does not downgrade to an old controller while the new worker installs', async () => {
  const h = boot({pageBuild: buildB, controllerBuild: buildA, latestBuild: buildB});
  await h.load();
  assert.equal(h.calls.reload, 0);
  assert.equal(h.calls.prepare, 0);
  await h.changeController(buildB);
  await h.advance(1000);
  assert.equal(h.calls.reload, 0);
});

test('retained pages discover a new same-version build and reload only after its worker activates', async () => {
  const h = boot();
  await h.load();
  h.state.latestBuild = buildB;
  await h.advance(30000);
  await h.fire(h.window, 'pageshow');
  assert.equal(h.calls.update, 2, 'a retained document checks the stable registration again');
  assert.equal(h.calls.register.length, 1);
  assert.equal(h.calls.reload, 0, 'server metadata alone cannot replace an incomplete worker');
  await h.changeController(buildB);
  assert.equal(h.calls.reload, 1);
  await h.changeController(buildB);
  await h.fire(h.window, 'online');
  await h.advance(60000);
  assert.equal(h.calls.reload, 1, 'controller and foreground events cannot reload twice');
});

test('a restored old document recognizes a controller already updated while it was suspended', async () => {
  const h = boot({pageBuild: buildA, controllerBuild: buildB, latestBuild: buildB});
  await h.load();
  assert.equal(h.calls.reload, 1);
});

test('live gameplay defers an available update until the safe-update hook allows it', async () => {
  const h = boot({controllerBuild: buildB, latestBuild: buildB, safe: false});
  await h.load();
  await h.advance(3000);
  assert.ok(h.calls.prepare >= 2);
  assert.equal(h.calls.reload, 0);
  h.state.safe = true;
  await h.advance(1000);
  assert.equal(h.calls.reload, 1);
  await h.advance(10000);
  assert.equal(h.calls.reload, 1);
});

test('offline and hidden retained games defer pending reloads until usable in the foreground', async () => {
  for (const blocked of ['offline', 'hidden']) {
    const h = boot({controllerBuild: buildB, latestBuild: buildB, safe: false});
    await h.load();
    h.state.safe = true;
    if (blocked === 'offline') h.navigator.onLine = false;
    else h.document.hidden = true;
    const preparations = h.calls.prepare;
    await h.advance(5000);
    assert.equal(h.calls.reload, 0, blocked);
    assert.equal(h.calls.prepare, preparations, 'hidden or offline pages do not enter the save/reload hook');
    h.navigator.onLine = true;
    h.document.hidden = false;
    await h.fire(blocked === 'offline' ? h.window : h.document, blocked === 'offline' ? 'online' : 'visibilitychange');
    assert.equal(h.calls.reload, 1, blocked);
  }
});

test('missing and throwing safe-update hooks leave the current game running', async () => {
  for (const missing of [false, true]) {
    const h = boot({controllerBuild: buildB, latestBuild: buildB});
    if (missing) delete h.window.leqra;
    else h.state.prepareError = Error('storage denied');
    await h.load();
    await h.advance(3000);
    assert.equal(h.calls.reload, 0);
  }
});

test('ordinary pageshows are throttled while foreground, reconnect and periodic checks discover updates', async () => {
  const h = boot();
  await h.load();
  await h.fire(h.window, 'pageshow');
  assert.equal(h.calls.fetch.length, 1);
  h.document.hidden = true;
  await h.fire(h.document, 'visibilitychange');
  assert.equal(h.calls.fetch.length, 1);
  h.document.hidden = false;
  await h.fire(h.document, 'visibilitychange');
  assert.equal(h.calls.fetch.length, 2, 'returning to a retained installed app checks even within the throttle');
  await h.fire(h.window, 'online');
  assert.equal(h.calls.fetch.length, 3, 'network recovery bypasses the ordinary foreground throttle');
  await h.advance(60000);
  assert.equal(h.calls.fetch.length, 4, 'an installed foreground page can discover a release without navigation');
});

test('BFCache restoration checks a release even inside the ordinary pageshow throttle', async () => {
  const h = boot();
  await h.load();
  h.state.latestBuild = buildB;
  h.sw.controller = h.worker(buildB);
  await h.fire(h.window, 'pageshow', {persisted: true});
  assert.equal(h.calls.fetch.length, 2);
  assert.equal(h.calls.reload, 1);
});

test('unavailable metadata and invalid build data cannot trigger an unsafe reload', async () => {
  for (const failure of ['network', 'http', 'invalid']) {
    const h = boot({controllerBuild: buildB});
    if (failure === 'network') h.state.fetchError = Error('offline');
    if (failure === 'http') h.state.responseOK = false;
    if (failure === 'invalid') h.state.latestBuild = 'untrusted-build';
    await h.load();
    assert.equal(h.calls.register.length, 0);
    assert.equal(h.calls.reload, 0);
    h.state.fetchError = null;
    h.state.responseOK = true;
    h.state.latestBuild = buildB;
    await h.fire(h.window, 'online');
    assert.equal(h.calls.reload, 1, 'a failed check must not poison later successful discovery');
  }
});

test('failed worker registration, update and build probes leave the game usable', async () => {
  for (const failure of ['register', 'update', 'probe', 'timeout']) {
    const h = boot({controllerBuild: buildB, latestBuild: buildB});
    if (failure === 'register') h.state.registerError = Error('registration denied');
    if (failure === 'update') h.state.updateError = Error('update network unavailable');
    if (failure === 'probe') h.sw.controller = h.worker(buildB, {error: true});
    if (failure === 'timeout') h.sw.controller = h.worker(buildB, {silent: true});
    await h.load();
    await h.advance(4000);
    if (failure === 'update') assert.equal(h.calls.reload, 1, 'an already complete latest worker remains usable after an update-network error');
    else assert.equal(h.calls.reload, 0, failure);
  }
});

test('overlapping foreground events coalesce discovery rather than flooding registration', async () => {
  const h = boot();
  h.window.dispatch('load');
  h.window.dispatch('online');
  h.window.dispatch('pageshow');
  h.document.dispatch('visibilitychange');
  await h.flush();
  assert.equal(h.calls.fetch.length, 1);
  assert.equal(h.calls.register.length, 1);
  assert.equal(h.calls.update, 1);
});


test('a stalled build lookup times out so network recovery can discover an update', async () => {
  const h = boot({supported: false});
  let signal;
  h.state.onFetch = options => new Promise((resolve, reject) => {
    signal = options.signal;
    signal?.addEventListener('abort', () => reject(Error('aborted')), {once: true});
  });
  await h.load();
  await h.advance(10000);
  h.state.onFetch = null;
  h.state.latestBuild = buildB;
  await h.fire(h.window, 'online');
  assert.equal(h.calls.fetch.length, 2);
  assert.equal(h.calls.reload, 1);
  assert.equal(signal?.aborted, true, 'a stalled request must release the discovery lock');
});
