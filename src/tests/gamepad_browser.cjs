'use strict';
const assert = require('node:assert/strict');
const {chromium} = require('playwright');

const [address] = process.argv.slice(2);
assert.ok(address && process.argv.includes('--disposable'), 'Supply a disposable loopback server and --disposable.');
const url = new URL(address);
assert.ok(['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) &&
 url.pathname === '/' && !url.username && !url.password && !url.search && !url.hash, 'Use an uncredentialed loopback origin.');
url.searchParams.set('test', '1');

// Expose observations of the real Infinity session only in this test context.
const infinityProbe = `
 window.__gamepadInfinity = {
  read: () => session && ({
   joined: session.joined,
   ids: session.controllers.map(seat => seat.id),
   tanks: session.controllers.map(seat => session.tanks.find(tank => tank.id === seat.id)),
   owners: session.bullets.map(bullet => bullet.owner)
  }),
  prepare() {
   session.maze = {wallsNear: () => [], visitWalls: () => false, blocked: () => false};
   session.nextBot = session.nextPickup = Infinity;
   session.tanks.forEach((tank, index) => Object.assign(tank, {
    x: 100 + index * 300, y: 100, angle: 0, invulnerable: 0, spawnProtected: false
   }));
  }
 };
`;

async function frames(page, count = 5) {
 await page.evaluate(count => new Promise(resolve => {
  function next() {
   if (--count === 0) resolve();
   else requestAnimationFrame(next);
  }
  requestAnimationFrame(next);
 }), count);
}

async function updatePad(page, index, axes = [0, 0, 0, 0], pressed = []) {
 await page.evaluate(({index, axes, pressed}) => window.setTestPad(index, axes, pressed), {index, axes, pressed});
}

async function disconnect(page, index) {
 await page.evaluate(index => window.setTestPad(index, null), index);
}

function displacement(from, to) {
 return Math.hypot(to.x - from.x, to.y - from.y);
}

async function state(page, infinity) {
 return page.evaluate(infinity => infinity ? __gamepadInfinity.read() : {
  tanks: __test.tanks.filter(tank => tank.human),
  owners: __test.bullets.map(bullet => bullet.owner)
 }, infinity);
}

async function verifyDrive(page, infinity, index, pilot) {
 const before = await state(page, infinity);
 await updatePad(page, index, [1, 0, 0, 0]);
 await page.waitForFunction(({infinity, pilot, from}) => {
  const tanks = infinity ? __gamepadInfinity.read().tanks : __test.tanks.filter(tank => tank.human);
  return Math.hypot(tanks[pilot].x - from.x, tanks[pilot].y - from.y) > 8;
 }, {infinity, pilot, from: before.tanks[pilot]});
 await updatePad(page, index);
 await frames(page);
 const after = await state(page, infinity);
 assert.ok(displacement(before.tanks[1 - pilot], after.tanks[1 - pilot]) < .01, 'Drive crossed to the other pilot');
}

async function verifyFire(page, infinity, index, pilot) {
 const before = await state(page, infinity);
 const owner = before.tanks[pilot].id;
 await updatePad(page, index, [0, 0, 0, 0], [pilot ? 7 : 0]);
 await page.waitForFunction(({infinity, owner}) => {
  const owners = infinity ? __gamepadInfinity.read().owners : __test.bullets.map(bullet => bullet.owner);
  return owners.includes(owner);
 }, {infinity, owner});
 await updatePad(page, index);
 const after = await state(page, infinity);
 assert.equal(after.owners.includes(before.tanks[1 - pilot].id), false, 'Fire crossed to the other pilot');
}

async function pauseWithStart(page, infinity) {
 const paused = desired => page.waitForFunction(({infinity, desired}) =>
  (infinity ? document.getElementById('infinitePauseMenu').open : __test.phase === 'paused') === desired,
 {infinity, desired});
 await updatePad(page, 2, [0, 0, 0, 0], [9]);
 await paused(true);
 await frames(page);
 await paused(true);
 await updatePad(page, 2);
 await frames(page);
 await updatePad(page, 2, [0, 0, 0, 0], [9]);
 await paused(false);
 await updatePad(page, 2);
 await frames(page);
}

async function verifyTour(page) {
 const next = page.locator('#introTourNext');
 assert.equal(await page.locator('#manualContent').getByText('Connect a game controller to play.', {exact: true}).count(), 1);
 await page.locator('#roomControlsBtn').click();
 assert.equal(await page.getByLabel('Game controller support', {exact: true}).count(), 1);
 assert.equal(await page.locator('#gamepadSupport').isChecked(), true);
 await page.locator('#openIntroTour').click();
 await frames(page);
 await updatePad(page, 2, [1, 0, 0, 0]);
 await page.locator('#introTourNext:enabled').waitFor();
 await updatePad(page, 2);
 await next.click();
 await frames(page);
 await updatePad(page, 2, [0, 0, 0, 0], [5]);
 await page.locator('#introTourNext:enabled').waitFor();
 await updatePad(page, 2);
 await next.click();
 await frames(page);
 await updatePad(page, 2, [0, 0, 0, 0], [0]);
 await page.locator('#introTourNext:enabled').waitFor();
 assert.equal(await page.locator('#introTourScore').textContent(), '1');
 await updatePad(page, 2);
 await next.click();
 await next.click();
 await page.getByRole('button', {name: 'Close controls'}).click();
 console.log('PASS Quick Tour drive, fire and score with a gamepad');
}

async function startFixed(page) {
 await page.evaluate(() => {
  const game = __test;
  game.addRoomSeat('local');
  game.localRoom.players = game.localRoom.players.filter(player => player.kind !== 'bot');
  document.getElementById('startRoomBtn').click();
  game.setPhase('playing');
  game.setWorld({width: 1100, height: 700, cols: 13, rows: 8, walls: []});
  game.pickups.length = 0;
  game.clearBullets();
  for (const [index, tank] of game.tanks.entries()) Object.assign(tank, {
   x: 100 + 400 * index, y: 200, angle: 0, invulnerable: 0, spawnProtected: false, cooldown: 0
  });
 });
 assert.equal((await state(page, false)).tanks.length, 2);
 await page.locator('#arena').focus();
 await frames(page);
}

async function verifyFixed(page) {
 await startFixed(page);
 await verifyDrive(page, false, 2, 0);
 await verifyDrive(page, false, 5, 1);
 const beforeAim = await state(page, false);
 await updatePad(page, 5, [0, 0, 0, 1]);
 await page.waitForFunction(() => __test.tanks.find(tank => tank.localIndex === 1).angle > .35);
 await updatePad(page, 5);
 const afterAim = await state(page, false);
 assert.ok(displacement(beforeAim.tanks[1], afterAim.tanks[1]) < .01, 'Right stick moved the aiming tank');
 assert.equal(beforeAim.tanks[0].angle, afterAim.tanks[0].angle, 'Right stick turned the other pilot');
 await verifyFire(page, false, 5, 1);
 await page.evaluate(() => __test.clearBullets());
 await verifyFire(page, false, 2, 0);
 await disconnect(page, 2);
 await frames(page);
 await verifyDrive(page, false, 5, 1);
 await updatePad(page, 2);
 await frames(page);
 await pauseWithStart(page, false);
 console.log('PASS fixed arena two-pad steering, aim, fire, stable seats and Start');
}

async function verifyInfinity(page) {
 await page.evaluate(() => {
  __test.returnToRoom();
  leqraInfinity.start('offline', {
   name: 'Controller tester', localName: 'Controller co-pilot',
   roomRules: {...__test.defaultRoomRules(), infinityRandomBots: false}
  });
  __gamepadInfinity.prepare();
 });
 assert.equal((await state(page, true)).tanks.length, 2);
 await page.locator('#infiniteCanvas').focus();
 await frames(page);
 await verifyDrive(page, true, 5, 1);
 await verifyFire(page, true, 5, 1);
 await pauseWithStart(page, true);
 await page.evaluate(() => leqraInfinity.close());
 console.log('PASS offline Infinity two-seat drive, fire and Start');
}

async function verifySetting(page) {
 await page.locator('#roomControlsBtn').click();
 const toggle = page.locator('#gamepadSupport');
 assert.equal(await toggle.isChecked(), true);
 await toggle.uncheck();
 await page.getByRole('button', {name: 'Close controls'}).click();
 await startFixed(page);
 const before = await state(page, false);
 await updatePad(page, 2, [1, 0, 0, 0], [0, 9]);
 await frames(page, 15);
 const after = await state(page, false);
 assert.ok(displacement(before.tanks[0], after.tanks[0]) < .01, 'Disabled gamepad could drive');
 assert.equal(after.owners.length, 0, 'Disabled gamepad could fire');
 assert.equal(await page.evaluate(() => __test.phase), 'playing', 'Disabled gamepad could pause');
 await page.reload();
 await page.locator('#roomControlsBtn').click();
 assert.equal(await toggle.isChecked(), false, 'Gamepad preference did not persist through reload');
 console.log('PASS disabled gamepads remain neutral and the setting persists');
}

async function verifyOnlineInput(page, arena, wing) {
 const start = await page.evaluate(() => window.testPadInputs.length);
 const isWing = packet => arena === '/ws/infinite' ? packet.local : packet.player === wing;
 // A right stick aimed up and a trigger pressed on only the second controller.
 await updatePad(page, 5, [0, 0, 0, -1], [7]);
 const active = await page.waitForFunction(({start, arena, wing}) => {
  const index = window.testPadInputs.findIndex((p, i) => i >= start && p.arena === arena &&
   (arena === '/ws/infinite' ? p.local : p.player === wing) && p.fire && p.aimOnly && p.stickY < -.9);
  return index >= start ? index + 1 : false;
 }, {start, arena, wing});
 await updatePad(page, 5);
 await page.waitForFunction(({start, arena, wing}) => window.testPadInputs.slice(start).some(p =>
  p.arena === arena && (arena === '/ws/infinite' ? p.local : p.player === wing) &&
  !p.fire && !p.stickX && !p.stickY), {start: await active.jsonValue(), arena, wing});
 const packets = await page.evaluate(({start, arena}) => window.testPadInputs.slice(start).filter(p => p.arena === arena), {start, arena});
 assert.ok(packets.filter(p => p.fire || p.aimOnly).every(isWing), 'Aim or fire reached the other online pilot');
}

async function verifyOnline(page) {
 await page.locator('#gamepadSupport').check();
 await page.getByRole('button', {name: 'Close controls'}).click();
 await page.evaluate(() => leqraInfinity.start('online', {
  public: true, name: 'Controller tester', localName: 'Controller co-pilot'
 }));
 await page.waitForFunction(() => {
  const state = __gamepadInfinity.read();
  return state?.joined && state.ids.length === 2 && state.ids.every(Number.isInteger);
 });
 await frames(page);
 await verifyOnlineInput(page, '/ws/infinite');
 await pauseWithStart(page, true);
 await page.evaluate(() => leqraInfinity.close());
 console.log('PASS public Infinity routes gamepad aim, fire and release on the correct input stream');

 await page.evaluate(() => {
  __test.addRoomSeat('local');
  __test.localRoom.players = __test.localRoom.players.filter(player => player.kind !== 'bot');
 });
 await page.locator('#copyInviteBtn').click();
 await page.waitForFunction(() => __test.online.connected && __test.phase === 'onlineLobby');
 await page.locator('#startRoomBtn').click();
 await page.waitForFunction(() => __test.phase === 'playing');
 await frames(page);
 const wing = await page.evaluate(() => __test.online.roomData.players.find(player =>
  player.kind === 'local' && player.owner === __test.online.id).id);
 await verifyOnlineInput(page, '/ws', wing);
 console.log('PASS fixed online room routes gamepad aim, fire and release on the correct input stream');
}

(async () => {
 const args = process.env.LEQRA_BROWSER_SINGLE_PROCESS === '1'
  ? ['--single-process', '--disable-gpu', '--in-process-gpu'] : [];
 const browser = await chromium.launch({headless: true, args});
 try {
  const context = await browser.newContext({viewport: {width: 1280, height: 900}, serviceWorkers: 'block'});
  await context.addInitScript(() => {
   if (!/^https?:$/.test(location.protocol)) return;
   const settings = {'introTour.v1': '1', infinityOnline: '0', infinityOffline: '0', name: 'Controller tester', local2Name: 'Controller co-pilot', muted: '1'};
   for (const [key, value] of Object.entries(settings)) localStorage.setItem('leqra.' + key, value);
   const pads = Array(8).fill(null);
   const neutral = [0, 0, 0, 0];
   window.setTestPad = (index, axes, pressed = []) => {
    pads[index] = axes && {
     connected: true, id: 'Test controller ' + index, index, mapping: 'standard', axes,
     buttons: Array.from({length: 17}, (_, button) => {
      const down = pressed.includes(button);
      return {pressed: down, touched: down, value: down ? 1 : 0};
     })
    };
   };
   window.setTestPad(2, neutral);
   window.setTestPad(5, neutral);
   Object.defineProperty(navigator, 'getGamepads', {value: () => pads});
   window.testPadInputs = [];
   const send = WebSocket.prototype.send;
   WebSocket.prototype.send = function (data) {
    const packet = JSON.parse(data);
    if (packet.type === 'input') {
     const {player, local, fire, aimOnly, stickX, stickY} = packet;
     window.testPadInputs.push({arena: new URL(this.url).pathname, player, local, fire, aimOnly, stickX, stickY});
    }
    return send.call(this, data);
   };
   Object.defineProperty(navigator, 'clipboard', {value: {writeText: async () => {}}});
  });
  await context.route('**/infinite.js*', async route => {
   const response = await route.fetch();
   const body = await response.text();
   const marker = 'window.leqraInfinity = Object.freeze';
   assert.ok(body.includes(marker), 'Infinity probe insertion point');
   await route.fulfill({response, body: body.replace(marker, infinityProbe + marker)});
  });
  const page = await context.newPage();
  page.setDefaultTimeout(8000);
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(url.href);
  await page.waitForFunction(() => window.__test && window.__gamepadInfinity);
  await verifyTour(page);
  await verifyFixed(page);
  await verifyInfinity(page);
  await verifySetting(page);
  await verifyOnline(page);
  assert.deepEqual(errors, []);
 } finally {
  await browser.close();
 }
})().catch(error => {
 console.error(error);
 process.exitCode = 1;
});
