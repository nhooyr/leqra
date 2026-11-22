"use strict"
// Real clients and WebSockets; the opt-in native muzzle server only arranges positions.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { chromium, webkit, devices } = require("playwright")
const { assetPath } = require("./web_assets.cjs")
const { replaceSource } = require("./source_helpers.cjs")
const server = process.argv[2] || "http://127.0.0.1:18125"
const output = path.resolve(process.argv[3] || "/tmp/leqra-online-turret-web")
fs.mkdirSync(output, { recursive: true })
const game = replaceSource(
  fs.readFileSync(assetPath("game.js"), "utf8"),
  "window.leqraInfinityArt=Object.freeze({",
  `
window.__turretRoom = {
  setup(infinity, code) {
    createLocalRoom();
    localRoom.rules=validateRoomRules({...defaultRoomRules(),infinity,infinityRandomBots:false,pickupRate:'off'});
    infinityOffline=infinity;
    localRoom.players=localRoom.players.filter(p=>p.id===localRoom.self);
    localRoom.players.push({id:1,member:++localRoom.nextMember,kind:'bot',name:'Bot 1',difficulty:'normal',team:0,colorIndex:1});
    $('localRoomName').value=code;shareLocalRoom();
  },
  start(){sendOnline({type:'start'});},
  enter(){startRoomInfinity();},
  read(){
    const t=tanks.find(t=>t.id===online.id), p=roomMember(online.id);
    return {connected:online.connected,ready:online.roomData?.canStart,infinityActive:online.roomData?.infinityActive,
      code:online.code,name:p?.name,phase,mode,errors:window.__turretErrors,
      generation:online.generation,latest:online.snapshots.at(-1)?.tanks.map(t=>({id:t.id,x:t.x,y:t.y,serial:t.spawnSerial})),
      x:t?.x,y:t?.y,angle:t?.angle,bodyAngle:t&&Net.bodyHeading(t),serial:t?.spawnSerial};
  }
};
window.leqraInfinityArt=Object.freeze({`,
)
const infinity = replaceSource(
  fs.readFileSync(assetPath("infinite.js"), "utf8"),
  "window.leqraInfinity =",
  `
window.__turretInfinity = () => {
  const t=session?.tanks.find(t=>t.id===session.id);
  return t&&{name:t.name,joined:session.joined,x:t.x,y:t.y,angle:t.angle,bodyAngle:net.bodyHeading(t),serial:t.spawnSerial};
};
window.leqraInfinity =`,
)

async function main() {
  const reports = []
  for (const [platform, engine, device] of [
    ["iphone", webkit, devices["iPhone 13"]],
    ["android", chromium, devices["Pixel 7"]],
  ]) {
    const browser = await engine.launch({ headless: true })
    try {
      for (const landscape of [false, true])
        for (const endless of [false, true]) {
          const label = `${platform}-${landscape ? "landscape" : "portrait"}-${endless ? "infinity" : "fixed"}`
          if (process.env.LEQRA_TURRET_CASE && process.env.LEQRA_TURRET_CASE !== label) continue
          console.log("START " + label)
          const viewport = landscape
            ? { width: device.viewport.height, height: device.viewport.width }
            : device.viewport
          const context = await browser.newContext({ ...device, viewport, serviceWorkers: "block" })
          try {
            await context.addInitScript(() => {
              localStorage.setItem("leqra.introTour.v1", "1")
              localStorage.setItem("leqra.muted", "1")
            })
            await context.route(/\/(game|infinite|callsigns)\.js(?:\?|$)/, (route) =>
              route.fulfill({
                body: route.request().url().includes("/infinite.js")
                  ? infinity
                  : route.request().url().includes("/callsigns.js")
                    ? fs.readFileSync(assetPath("callsigns.js"), "utf8")
                    : game,
                contentType: "text/javascript",
              }),
            )
            const page = await context.newPage(),
              errors = []
            page.setDefaultTimeout(10000)
            page.on("pageerror", (e) => {
              errors.push(e.message)
              console.error("PAGE", e.message)
            })
            await page.addInitScript(() => {
              window.__turretErrors = []
              window.addEventListener("error", (e) => window.__turretErrors.push(e.message))
            })
            await page.goto(server + "/?test=1")
            console.log("LOADED " + label)
            await page.waitForFunction(() => window.__turretRoom && !window.leqraCallsigns.isPending(0))
            await page.evaluate(
              ({ endless, label }) =>
                window.__turretRoom.setup(endless, label + "-" + Date.now().toString(36)),
              { endless, label },
            )
            await page.waitForFunction(() => window.__turretRoom.read().ready)
            console.log("CONNECTED " + label)
            await page.evaluate(() => window.__turretRoom.start())
            if (endless) {
              await page.waitForFunction(() => window.__turretRoom.read().infinityActive)
              await page.evaluate(() => window.__turretRoom.enter())
              await page.waitForFunction(() => window.__turretInfinity()?.joined)
            } else await page.waitForFunction(() => window.__turretRoom.read().phase === "playing")
            const read = () =>
              page.evaluate(
                (endless) => ({
                  ...window.__turretRoom.read(),
                  ...(endless ? window.__turretInfinity() : {}),
                }),
                endless,
              )
            const identity = await read()
            console.log("PLAYING " + label)
            let serial = 300000
            async function fixture({ open = true, ghost = false, read = false } = {}) {
              const response = await fetch(server + "/_fixture/muzzle", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                  name: identity.name,
                  code: identity.code,
                  infinity: endless,
                  open,
                  ghost,
                  gap: ghost ? 1 : 0,
                  bodyAngle: ghost ? Math.PI / 2 : 0,
                  read,
                  serial: read ? serial : ++serial,
                }),
              })
              assert.equal(response.status, 200, await response.clone().text())
              return response.json()
            }
            async function until(predicate) {
              const deadline = Date.now() + 5000
              let state
              do {
                state = await fixture({ read: true })
                if (predicate(state)) return state
                await page.waitForTimeout(20)
              } while (Date.now() < deadline)
              assert.fail(label + " server state: " + JSON.stringify(state))
            }
            async function arranged(options) {
              const state = await fixture(options)
              await page
                .waitForFunction(
                  ({ endless, serial }) =>
                    (endless ? window.__turretInfinity() : window.__turretRoom.read())?.serial === serial,
                  { endless, serial },
                )
                .catch(async (error) => {
                  console.error("POSITION", JSON.stringify({ expected: state, actual: await read() }))
                  error.message += "\n" + JSON.stringify({ expected: state, actual: await read() })
                  throw error
                })
              return state
            }
            const fireSelector = endless ? "#infiniteFire" : "#fireBtn",
              stickSelector = endless ? "#infiniteStick" : "#stickZone"
            const baseSelector = endless ? "#infiniteStickBase" : "#stickBase"
            const fireBox = await page.locator(fireSelector).boundingBox(),
              stickBox = await page.locator(baseSelector).boundingBox()
            const fx = fireBox.x + fireBox.width / 2,
              fy = fireBox.y + fireBox.height / 2
            async function pointer(selector, type, id, x, y) {
              await page.evaluate(
                ({ selector, type, id, x, y }) => {
                  const target = type === "pointerdown" ? document.querySelector(selector) : window
                  target.dispatchEvent(
                    new PointerEvent(type, {
                      pointerType: "touch",
                      pointerId: id,
                      button: 0,
                      buttons: type === "pointerup" ? 0 : 1,
                      clientX: x,
                      clientY: y,
                      bubbles: true,
                      cancelable: true,
                    }),
                  )
                },
                { selector, type, id, x, y },
              )
            }
            const fire = (type, x = fx, y = fy) => pointer(fireSelector, type, 10, x, y)
            const start = await arranged()
            await fire("pointerdown")
            await fire("pointermove", fx, fy - 32)
            await pointer(
              stickSelector,
              "pointerdown",
              20,
              stickBox.x + stickBox.width / 2 + 24,
              stickBox.y + stickBox.height / 2,
            )
            await page.waitForTimeout(500)
            const driving = await until((s) => s.input.stickX > 0.1 && s.input.aimY < -0.9)
            assert(driving.x > start.x + 10, label + " moved east")
            assert(Math.abs(driving.y - start.y) < 0.1, label + " movement ignored turret heading")
            assert(
              Math.abs(driving.angle + Math.PI / 2) < 0.01 && Math.abs(driving.bodyAngle) < 0.01,
              label + " separate headings",
            )
            assert.equal(driving.shots, 0)
            assert.equal(driving.input.fire, false)
            await pointer(stickSelector, "pointerup", 20, 0, 0)
            await fire("pointerup")
            await arranged()
            await fire("pointerdown")
            await fire("pointermove", fx, fy - 32)
            await fire("pointerup")
            await until((s) => s.independentAim && Math.abs(s.angle + Math.PI / 2) < 0.01)
            await fire("pointerdown")
            await fire("pointerup")
            const fired = await until((s) => s.shots > 0),
              bullet = fired.bullets[0]
            assert(
              bullet && bullet.vy < 0 && Math.abs(bullet.vx) < 0.001,
              label + " projectile follows turret",
            )
            assert(
              Math.abs(bullet.x - fired.x) < 0.01 && bullet.y < fired.y - 20,
              label + " projectile exits barrel",
            )
            await fire("pointerdown")
            await page.waitForTimeout(750)
            const held = await until((s) => s.shots >= fired.shots + 2)
            await fire("pointerup")
            await fire("pointerdown")
            await fire("pointermove", fx + 32, fy)
            await fire("pointerup")
            const wall = await arranged({ open: false, ghost: true })
            await fire("pointerdown")
            await fire("pointermove", fx + 32, fy)
            await fire("pointerup")
            await until(
              (s) =>
                s.independentAim && Math.abs(s.angle) < 0.01 && Math.abs(s.bodyAngle - Math.PI / 2) < 0.01,
            )
            await fire("pointerdown")
            await fire("pointerup")
            const ghost = await until((s) => s.shots > 0),
              reflected = ghost.bullets[0]
            assert(
              reflected && reflected.vx < 0 && Math.abs(reflected.vy) < 0.001 && reflected.bounces > 0,
              label + " Ghost reflects from muzzle wall",
            )
            assert(reflected.x < wall.wallX)
            assert.deepEqual(errors, [])
            await page.screenshot({ path: path.join(output, label + ".png") })
            reports.push({ label, driving, fired, held, ghost })
            console.log("PASS " + label)
          } finally {
            await context.close()
          }
        }
    } finally {
      await browser.close()
    }
  }
  fs.writeFileSync(path.join(output, "results.json"), JSON.stringify(reports, null, 2))
  console.log(JSON.stringify({ checks: reports.length, output }))
}
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
