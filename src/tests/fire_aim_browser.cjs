"use strict"
// Run after go build -o bin/leqra ./src. Uses only a disposable loopback server.
// NODE_PATH=/path/to/playwright/node_modules node src/tests/fire_aim_browser.cjs /tmp/fire-aim
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { spawn } = require("node:child_process")
const { chromium, webkit, devices } = require("playwright")
const { replaceSource } = require("./source_helpers.cjs")
const { assetPath } = require("./web_assets.cjs")
const root = path.resolve(__dirname, "../..")
const output = path.resolve(process.argv[2] || fs.mkdtempSync("/tmp/leqra-fire-aim-"))
assert(output !== root && !output.startsWith(root + path.sep), "Keep test artifacts outside the repository")
fs.mkdirSync(output, { recursive: true })
const scripts = {
  "game.js": replaceSource(
    fs.readFileSync(assetPath("game.js"), "utf8"),
    "window.leqraInfinityArt=Object.freeze({",
    `
window.__fireFixed = {
 seen: new Set(),
 setup(near) {
  this.seen.clear();
  this.firstShot=null;
  window.leqraInfinity.close(); mode='room';
  localRoom.rules=validateRoomRules({...defaultRoomRules(),infinity:false,pickupRate:'off'});
  localRoom.players=[0,1].map(id=>({id,member:id+1,kind:'human',name:id?'Observer':'Pilot',team:0,colorIndex:id}));
  startMatch(); phase='playing'; clearInput();
  __test.setWorld({width:504,height:420,cols:6,rows:5,walls:near?[{x:172,y:110,w:8,h:200}]:[]});
  Object.assign(tanks[0],{x:150,y:210,angle:0,invulnerable:1000,spawnProtected:false,localIndex:0});
  Object.assign(tanks[1],{x:430,y:340,invulnerable:1000,spawnProtected:false,localIndex:1});
  cacheMap(); updateHUD(true); render();
 },
 read() { const t=tanks[0], r=canvas.getBoundingClientRect();for(const b of bullets)if(b.owner===t.id){this.seen.add(b.id);this.firstShot??={vx:b.vx,vy:b.vy,bounces:b.bounces||0};}return {x:t.x,y:t.y,angle:t.angle,bodyAngle:window.leqraNet.bodyHeading(t),hp:t.hp,independentAim:t.independentAim,input:typeof inputState==="function"?inputState(session):null,fired:this.seen.size,firstShot:this.firstShot,fire:primaryFireHeld(),aim:directAim.active,screenX:r.left+offsetX+t.x*scale,screenY:r.top+offsetY+t.y*scale}; }
};
window.leqraInfinityArt=Object.freeze({`,
  ),
  "infinite.js": replaceSource(
    fs.readFileSync(assetPath("infinite.js"), "utf8"),
    "window.leqraInfinity =",
    `
window.__fireInfinity = {
 seen: new Set(),
 setup(online) { this.seen.clear(); this.firstShot=null; stop(); start(online?'online':'offline',{public:online,roomRules:{infinity:true,infinityRandomBots:false,pickupRate:'off'}}); if(!online) for(const tank of session.tanks) Object.assign(tank,{spawnProtected:false,invulnerable:1000}); },
 read() { const t=session?.tanks.find(t=>t.id===session.id), r=canvas.getBoundingClientRect();if(t)for(const b of session.bullets)if(b.owner===t.id){this.seen.add(b.id);this.firstShot??={vx:b.vx,vy:b.vy,bounces:b.bounces||0};}return t?{x:t.x,y:t.y,angle:t.angle,bodyAngle:window.leqraNet.bodyHeading(t),hp:t.hp,independentAim:t.independentAim,input:typeof inputState==="function"?inputState(session):null,fired:this.seen.size,firstShot:this.firstShot,fire:inputState(session).fire,aim:!!inputState(session).snapAim||Math.hypot(inputState(session).aimX||0,inputState(session).aimY||0)>0.1,joined:session.joined||!session.online,screenX:r.left+r.width/2,screenY:r.top+r.height/2}:null; }
};
window.leqraInfinity =`,
  ),
}
const server = spawn(path.join(root, "bin/leqra"), ["-addr", "127.0.0.1:0"], {
  cwd: root,
  env: {
    ...process.env,
    LEQRA_DATA: path.join(output, "data.sqlite"),
    LEQRA_ADMIN_ADDR: "off",
    ALLOWED_ORIGINS: "",
  },
  stdio: ["ignore", "pipe", "pipe"],
})
let log = ""
server.stdout.on("data", (data) => {
  log += data
})
server.stderr.on("data", (data) => {
  log += data
})
async function main() {
  const url = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(Error("Local server failed to start: " + log)), 15000)
    server.on("exit", (code) => {
      clearTimeout(timer)
      reject(Error("Server exited: " + code + log))
    })
    server.stdout.on("data", () => {
      const match = log.match(/http:\/\/(?:127\.0\.0\.1|localhost):\d+/)
      if (match) {
        clearTimeout(timer)
        resolve(match[0])
      }
    })
  })
  const results = []
  for (const [name, engine, device] of [
    ["iphone", webkit, devices["iPhone 13"]],
    ["android", chromium, devices["Pixel 7"]],
  ]) {
    const browser = await engine.launch({ headless: true })
    try {
      for (const landscape of [false, true]) {
        const viewport = landscape
          ? { width: device.viewport.height, height: device.viewport.width }
          : device.viewport
        const context = await browser.newContext({ ...device, viewport, serviceWorkers: "block" })
        await context.addInitScript(() => {
          localStorage.setItem("leqra.introTour.v1", "1")
          localStorage.setItem("leqra.muted", "1")
        })
        await context.route(/\/(game|infinite)\.js(?:\?|$)/, (route) => {
          const file = new URL(route.request().url()).pathname.split("/").pop()
          return route.fulfill({ body: scripts[file], contentType: "text/javascript" })
        })
        const page = await context.newPage()
        const errors = []
        page.on("pageerror", (error) => errors.push(error.message))
        await page.goto(url + "/?test=1")
        await page.waitForFunction(() => window.__fireFixed && window.__fireInfinity)
        for (const [mode, center] of ["fixed", "fixed-wall", "infinity", "online-infinity"].flatMap(
          (mode) => [
            [mode, true],
            [mode, false],
          ],
        )) {
          const caseName = `${name}:${landscape ? "landscape" : "portrait"}:${mode}:${center ? "center" : "outer"}`
          if (process.env.LEQRA_FIRE_CASE && process.env.LEQRA_FIRE_CASE !== caseName) continue
          console.log("Checking " + caseName)
          const fixed = mode.startsWith("fixed")
          const hook = fixed ? "__fireFixed" : "__fireInfinity"
          await page.evaluate(
            ({ hook, mode }) => window[hook].setup(mode === "fixed-wall" || mode === "online-infinity"),
            { hook, mode },
          )
          await page.waitForFunction((hook) => {
            const state = window[hook].read()
            return state && (state.joined ?? true)
          }, hook)
          const selector = fixed ? "#fireBtn" : "#infiniteFire"
          await page.locator(selector).waitFor({ state: "visible" })
          const box = await page.locator(selector).boundingBox()
          const buttonCenter = { x: box.x + box.width / 2, y: box.y + box.height / 2 }
          const start = { x: buttonCenter.x, y: buttonCenter.y - (center ? 0 : 32) }
          async function pointer(type, x = start.x, y = start.y) {
            await page.evaluate(
              ({ selector, type, x, y }) => {
                const target = type === "pointerdown" ? document.querySelector(selector) : window
                target.dispatchEvent(
                  new PointerEvent(type, {
                    pointerId: 91,
                    pointerType: "touch",
                    button: 0,
                    buttons: type === "pointerup" ? 0 : 1,
                    clientX: x,
                    clientY: y,
                    bubbles: true,
                    cancelable: true,
                  }),
                )
              },
              { selector, type, x, y },
            )
          }
          const before = await page.evaluate((hook) => window[hook].read(), hook)
          await pointer("pointerdown")
          await page.waitForFunction((hook) => window[hook].read().fired > 0, hook)
          if (!center) {
            const first = await page.evaluate((hook) => window[hook].read(), hook)
            assert(first.aim, caseName + " must aim on the initial press")
            assert(
              Math.abs(first.firstShot.vx) < 1e-6,
              caseName + " first shot must use the new vertical aim",
            )
            assert(Math.abs(first.firstShot.vy) > 1, caseName + " first shot must move along the aimed axis")
            if (!first.firstShot.bounces)
              assert(first.firstShot.vy < 0, caseName + " first shot must travel north")
          }
          if (center) await page.waitForTimeout(50)
          await pointer("pointermove", buttonCenter.x + 5, buttonCenter.y)
          const tapped = await page.evaluate((hook) => window[hook].read(), hook)
          assert.equal(tapped.aim, !center, mode + " dead zone retains any existing aim")
          assert.equal(tapped.fire, true, "Touch-down starts continuous fire")
          for (const angle of [-Math.PI / 2, Math.PI, Math.PI / 4]) {
            await pointer(
              "pointermove",
              buttonCenter.x + Math.cos(angle) * 32,
              buttonCenter.y + Math.sin(angle) * 32,
            )
            await page.waitForFunction(
              ({ hook, angle }) => {
                const state = window[hook].read()
                return state && Math.cos(state.angle - angle) > 0.995
              },
              { hook, angle },
            )
            const aimed = await page.evaluate((hook) => window[hook].read(), hook)
            assert(Math.hypot(aimed.x - before.x, aimed.y - before.y) < 0.01, mode + " moved while aiming")
            assert.equal(aimed.fire, true)

            const crosshair = await page.locator(selector).evaluate((button) => {
              const base = button.getBoundingClientRect(),
                glyph = button.querySelector("svg").getBoundingClientRect()
              return {
                x: glyph.x + glyph.width / 2 - base.x - base.width / 2,
                y: glyph.y + glyph.height / 2 - base.y - base.height / 2,
                reach: Math.min(24, Math.min(base.width, base.height) / 2 - 17),
              }
            })
            assert(
              Math.abs(crosshair.x - Math.cos(angle) * crosshair.reach) < 0.2,
              "Crosshair must follow horizontal aim",
            )
            assert(
              Math.abs(crosshair.y - Math.sin(angle) * crosshair.reach) < 0.2,
              "Crosshair must follow vertical aim",
            )
          }
          await page.screenshot({
            path: path.join(
              output,
              `${name}-${landscape ? "landscape" : "portrait"}-${mode}-${center ? "center" : "outer"}-drag.png`,
            ),
          })
          await pointer("pointerup")
          assert.equal((await page.evaluate((hook) => window[hook].read(), hook)).fire, false)
          const centered = await page.locator(selector).evaluate((button) => {
            const base = button.getBoundingClientRect(),
              glyph = button.querySelector("svg").getBoundingClientRect()
            return Math.hypot(
              glyph.x + glyph.width / 2 - base.x - base.width / 2,
              glyph.y + glyph.height / 2 - base.y - base.height / 2,
            )
          })
          assert(centered < 0.2, "Crosshair must recenter after release")
          if (center) {
            await page.waitForFunction((hook) => window[hook].read().fired > 0, hook)
            await pointer("pointerdown")
            await pointer("pointerup")
            if (mode !== "online-infinity")
              await page.waitForFunction((hook) => window[hook].read().fired > 0, hook)
          }
          if (center) {
            await pointer("pointerdown")
            await page.waitForTimeout(250)
            assert.equal(
              (await page.evaluate((hook) => window[hook].read(), hook)).fire,
              true,
              "Center hold fires",
            )
            await pointer("pointerup")
            assert.equal(
              (await page.evaluate((hook) => window[hook].read(), hook)).fire,
              false,
              "Center release stops firing",
            )
          }
          const stickSelector = fixed ? "#stickZone" : "#infiniteStick"
          const stickBase = await page.locator(fixed ? "#stickBase" : "#infiniteStickBase").boundingBox()
          await page.dispatchEvent(stickSelector, "pointerdown", {
            pointerId: 93,
            pointerType: "touch",
            button: 0,
            clientX: stickBase.x + stickBase.width / 2 + 24,
            clientY: stickBase.y + stickBase.height / 2,
          })
          await page.waitForFunction((hook) => Math.cos(window[hook].read().bodyAngle) > 0.999, hook)
          const driveBefore = await page.evaluate((hook) => window[hook].read(), hook)
          await pointer("pointerdown")
          await pointer("pointermove", buttonCenter.x, buttonCenter.y - 32)
          await page.waitForTimeout(500)
          const driving = await page.evaluate((hook) => window[hook].read(), hook)
          if (mode !== "fixed-wall")
            assert(
              Math.hypot(driving.x - driveBefore.x, driving.y - driveBefore.y) > 1,
              mode + " must move while the turret aims north",
            )
          assert(
            Math.cos(driving.angle + Math.PI / 2) > 0.95,
            caseName + " must aim north: " + JSON.stringify({ driveBefore, driving }),
          )
          assert(Math.cos(driving.bodyAngle) > 0.95, mode + " hull must face east while turret aims north")
          assert(Math.abs(driving.y - driveBefore.y) < 1, mode + " driving must not follow the turret north")
          await pointer("pointerup")
          await page.dispatchEvent(stickSelector, "pointerup", {
            pointerId: 93,
            pointerType: "touch",
            button: 0,
          })
          if (mode !== "online-infinity") {
            const state = await page.evaluate((hook) => window[hook].read(), hook)
            await page.dispatchEvent(fixed ? "#arena" : "#infiniteCanvas", "pointerdown", {
              pointerId: 92,
              pointerType: "touch",
              button: 0,
              clientX: state.screenX + 35,
              clientY: state.screenY,
            })
            await page.waitForFunction((hook) => window[hook].read().aim, hook)
            await page.dispatchEvent(fixed ? "#arena" : "#infiniteCanvas", "pointerup", {
              pointerId: 92,
              pointerType: "touch",
              button: 0,
            })
          }
          await page.screenshot({
            path: path.join(
              output,
              `${name}-${landscape ? "landscape" : "portrait"}-${mode}-${center ? "center" : "outer"}.png`,
            ),
          })
          results.push({ name, landscape, mode, stationary: true, firing: true })
        }
        assert.deepEqual(errors, [])
        await context.close()
      }
    } finally {
      await browser.close()
    }
  }
  fs.writeFileSync(path.join(output, "results.json"), JSON.stringify(results, null, 2))
  console.log(JSON.stringify({ output, checks: results.length }))
}
main()
  .catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
  .finally(async () => {
    server.kill("SIGTERM")
    await new Promise((resolve) => {
      server.once("exit", resolve)
      setTimeout(resolve, 3000).unref()
    })
    fs.writeFileSync(path.join(output, "server.log"), log)
  })
