"use strict"
// Optional real browser input regression against a disposable loopback server.
// node src/tests/local_p2_input_browser.cjs http://127.0.0.1:8080 --disposable
// Physics is stepped explicitly so short, real DOM presses are deterministic.
const assert = require("node:assert/strict"),
  fs = require("node:fs"),
  os = require("node:os"),
  path = require("node:path")
const { chromium, webkit } = require("playwright")
const args = process.argv.slice(2),
  address = args.find((value) => /^https?:/.test(value))
assert.ok(address && args.includes("--disposable"), "Supply a disposable loopback server and --disposable.")
const url = new URL(address)
assert.ok(
  ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname) &&
    url.pathname === "/" &&
    !url.username &&
    !url.password &&
    !url.search &&
    !url.hash,
  "Use an uncredentialed loopback origin.",
)
url.searchParams.set("test", "1")
const output = process.env.LEQRA_BROWSER_OUTPUT || fs.mkdtempSync(path.join(os.tmpdir(), "leqra-p2-input-"))
fs.mkdirSync(output, { recursive: true })
const selected = args.find((value) => value.startsWith("--browser="))?.split("=")[1],
  profileFilter = args.find((value) => value.startsWith("--profile="))?.split("=")[1]
const profiles = [
  { name: "phone", width: 390, height: 844 },
  { name: "tablet", width: 1024, height: 768 },
].filter((p) => !profileFilter || p.name === profileFilter)
const records = [],
  errors = []
let serial = 0
const infinityProbe = String.raw`
window.__p2Input={
 read(){const w=session;return w?{joined:!!w.joined,online:w.online,paired:!!w.local,ids:w.controllers.map(s=>s.id),inputs:w.controllers.map(s=>inputState(s)),tanks:w.controllers.map(s=>{const t=w.tanks.find(t=>t.id===s.id);return t&&{id:t.id,x:t.x,y:t.y,angle:t.angle,bodyAngle:net.bodyHeading(t),alive:t.hp>0};}),bullets:w.bullets.map(b=>({owner:b.owner,vx:b.vx,vy:b.vy}))}:null;},
 send(){sendInput(session,performance.now(),true);},
 step(count=1){for(let i=0;i<count;i++)offlineStep(session,1/60);},
 prepare(){const w=session;w.maze={wallsNear:()=>[],visitWalls:()=>false,blocked:()=>false};w.nextBot=w.nextPickup=1e9;w.pickups=[];w.bullets=[];for(const [i,t]of w.tanks.entries())Object.assign(t,{x:100+i*300,y:100,angle:0,invulnerable:0,spawnProtected:false,power:'',powerTime:0,cooldown:0,charges:0});},
 readyShot(){session.bullets=[];for(const t of session.tanks)t.cooldown=0;},
 primaryPoint(){const r=canvas.getBoundingClientRect(),[w,h]=primaryView(r.width,r.height,!!session.local);return{x:r.left+w/2,y:r.top+h/2};},
 mousePoint(){const r=canvas.getBoundingClientRect(),[w,h]=primaryView(r.width,r.height,!!session.local),left=w<r.width?w:0,top=h<r.height?h:0;return{x:r.left+left+(r.width-left)/2+35,y:r.top+top+(r.height-top)/2-25};}
};
`
async function fixedRead(page) {
  return page.evaluate(() => ({
    ids: __test.tanks.filter((t) => t.human).map((t) => t.id),
    tanks: __test.tanks
      .filter((t) => t.human)
      .map((t) => ({
        id: t.id,
        x: t.x,
        y: t.y,
        angle: t.angle,
        bodyAngle: window.leqraNet.bodyHeading(t),
        alive: t.alive,
      })),
    bullets: __test.bullets.map((b) => ({ owner: b.owner, vx: b.vx, vy: b.vy })),
  }))
}
async function state(page, mode) {
  return mode === "fixed" ? fixedRead(page) : page.evaluate(() => __p2Input.read())
}
async function step(page, mode, count = 1) {
  await page.evaluate(
    ({ mode, count }) => {
      if (mode === "fixed") {
        for (let i = 0; i < count; i++) __test.update(1 / 60)
      } else __p2Input.step(count)
    },
    { mode, count },
  )
}
async function readyShot(page, mode) {
  await page.evaluate((mode) => {
    if (mode === "fixed") {
      __test.clearBullets()
      for (const t of __test.tanks) t.cooldown = 0
    } else __p2Input.readyShot()
  }, mode)
}
async function canvasFocus(page, mode) {
  await page.locator(mode === "fixed" ? "#arena" : "#infiniteCanvas").focus()
}
const moved = (a, b) => Math.hypot(a.x - b.x, a.y - b.y),
  turn = (a, b) => Math.abs(Math.atan2(Math.sin(a.angle - b.angle), Math.cos(a.angle - b.angle)))
async function movement(page, mode, key, label, packets) {
  const packetStart = packets.length,
    before = await state(page, mode)
  await page.keyboard.down(key)
  if (mode === "online") {
    const s = await state(page, mode)
    assert.equal(s.inputs[0].forward, false, label + " P1 keyboard")
    assert.equal(s.inputs[1].forward, true, label + " P2 keyboard")
    await page.waitForTimeout(30)
    const sent = packets.slice(packetStart).filter((p) => p.type === "input" && p.forward)
    assert.ok(
      sent.some((p) => p.local === true),
      label + " missing P2 movement packet",
    )
    assert.ok(
      sent.every((p) => p.local === true),
      label + " movement leaked to P1 wire",
    )
  } else {
    await step(page, mode, 4)
    const after = await state(page, mode)
    assert.ok(moved(before.tanks[0], after.tanks[0]) < 1e-7, label + " moved P1")
    assert.ok(moved(before.tanks[1], after.tanks[1]) > 1, label + " did not move P2")
  }
  await page.keyboard.up(key)
  if (mode === "online") {
    const s = await state(page, mode)
    assert.equal(s.inputs[1].forward, false, label + " stuck P2 key")
  }
}
async function fire(page, mode, source, label, packets) {
  if (mode !== "online") await readyShot(page, mode)
  const before = packets.length
  if (source === "keyboard") {
    await page.keyboard.down("q")
  } else if (source === "mouse") {
    const p = await mousePoint(page, mode)
    await page.mouse.move(p.x, p.y)
    await page.mouse.down()
  } else {
    const box = await page.locator(mode === "fixed" ? "#fireBtn" : "#infiniteFire").boundingBox()
    assert.ok(box, label + " missing fire control")
    await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2)
  }
  if (mode === "online") {
    await page.waitForTimeout(40)
    const sent = packets.slice(before).filter((p) => p.type === "input" && p.fire)
    assert.ok(
      sent.some((p) => !!p.local === (source !== "touch")),
      label + " fire reached wrong online seat: " + JSON.stringify(sent),
    )
    assert.ok(!sent.some((p) => !!p.local === (source === "touch")), label + " fire leaked to other seat")
    if (source === "mouse")
      assert.ok(
        sent.some((p) => !p.aimOnly && Math.hypot(p.aimX, p.aimY) > 0.9),
        label + " pointer aim missing from P2 wire",
      )
  } else {
    await step(page, mode)
    const s = await state(page, mode),
      expected = s.ids[source === "touch" ? 0 : 1]
    assert.ok(
      s.bullets.some((b) => b.owner === expected),
      label + " no expected projectile: " + JSON.stringify(s),
    )
    assert.ok(
      s.bullets.every((b) => b.owner === expected),
      label + " fired other pilot",
    )
  }
  if (source === "keyboard") await page.keyboard.up("q")
  else if (source === "mouse") await page.mouse.up()
}
async function mousePoint(page, mode) {
  return mode === "fixed"
    ? page.evaluate(() => {
        const r = document.querySelector("#arena").getBoundingClientRect(),
          v = __test.view,
          t =
            __test.tanks.find((t) => t.human && t.localIndex === 1) || __test.tanks.filter((t) => t.human)[1]
        return { x: r.left + v.offsetX + t.x * v.scale + 30, y: r.top + v.offsetY + t.y * v.scale - 25 }
      })
    : page.evaluate(() => __p2Input.mousePoint())
}
async function primaryPoint(page, mode) {
  return mode === "fixed"
    ? page.evaluate(() => {
        const r = document.querySelector("#arena").getBoundingClientRect(),
          v = __test.view,
          t = __test.tanks.find((t) => t.human)
        return { x: r.left + v.offsetX + t.x * v.scale, y: r.top + v.offsetY + t.y * v.scale }
      })
    : page.evaluate(() => __p2Input.primaryPoint())
}
async function aim(page, mode, label) {
  const before = await state(page, mode),
    mouse = await mousePoint(page, mode)
  await page.mouse.move(mouse.x, mouse.y)
  if (mode === "online") {
    const s = await state(page, mode)
    assert.ok(Math.hypot(s.inputs[1].aimX, s.inputs[1].aimY) > 0.1, label + " mouse did not aim P2")
    assert.ok(!s.inputs[1].aimOnly, label + " mouse controlled P2 body")
    assert.ok(!s.inputs[0].aimX && !s.inputs[0].aimY, label + " mouse aimed P1")
  } else {
    await step(page, mode, 4)
    const after = await state(page, mode)
    assert.ok(turn(before.tanks[0], after.tanks[0]) < 1e-7, label + " mouse turned P1")
    assert.ok(turn(before.tanks[1], after.tanks[1]) > 0.01, label + " mouse did not turn P2")
    assert.equal(after.tanks[1].bodyAngle, before.tanks[1].bodyAngle, label + " mouse turned P2 body")
  }
  const point = await primaryPoint(page, mode),
    first = await state(page, mode)
  await page.touchscreen.tap(point.x + 20, point.y - 15)
  if (mode === "online") {
    const s = await state(page, mode)
    assert.ok(s.inputs[0].aimOnly && s.inputs[0].snapAim, label + " touch did not snap P1")
    assert.ok(Math.hypot(s.inputs[1].aimX, s.inputs[1].aimY) > 0.1, label + " touch altered P2 mouse aim")
  } else {
    await step(page, mode)
    const after = await state(page, mode)
    assert.ok(moved(first.tanks[0], after.tanks[0]) < 1e-7, label + " quick aim moved P1")
    assert.ok(turn(first.tanks[0], after.tanks[0]) > 0.01, label + " touch did not turn P1")
  }
}
async function driveWhileAiming(page, mode, label) {
  const pointer = await mousePoint(page, mode)
  await page.mouse.move(pointer.x, pointer.y)
  const before = await state(page, mode)
  await page.keyboard.down("ArrowUp")
  await page.keyboard.down("ArrowRight")
  if (mode === "online") {
    const s = await state(page, mode),
      input = s.inputs[1]
    assert.ok(input.forward && input.right, label + " missing arrow movement")
    assert.ok(Math.hypot(input.aimX, input.aimY) > 0.1, label + " turning cleared mouse aim")
    assert.ok(!input.aimOnly, label + " turret aim steered body")
    await page.waitForTimeout(250)
  } else await step(page, mode, 12)
  await page.keyboard.up("ArrowRight")
  await page.keyboard.up("ArrowUp")
  const after = await state(page, mode)
  assert.ok(moved(before.tanks[1], after.tanks[1]) > 1, label + " did not drive P2")
  assert.ok(Math.abs(after.tanks[1].bodyAngle - before.tanks[1].bodyAngle) > 0.05, label + " did not turn P2")
  assert.ok(Math.abs(after.tanks[1].bodyAngle - after.tanks[1].angle) > 0.05, label + " turret followed hull")
}
async function touchStick(page, mode, label) {
  const selector = mode === "fixed" ? "#stickZone" : "#infiniteStick",
    base = await page.locator(mode === "fixed" ? "#stickBase" : "#infiniteStickBase").boundingBox()
  assert.ok(base, label + " missing stick")
  const event = {
    pointerId: 91,
    pointerType: "touch",
    button: 0,
    buttons: 1,
    clientX: base.x + base.width * 0.8,
    clientY: base.y + base.height * 0.5,
  }
  // Portable held touch: Playwright dispatches a real PointerEvent through the DOM handlers.
  const before = await state(page, mode)
  await page.locator(selector).dispatchEvent("pointerdown", event)
  if (mode === "online") {
    const s = await state(page, mode)
    assert.ok(s.inputs[0].stickX > 0.1 && !s.inputs[0].aimOnly, label + " touch stick did not drive P1")
    assert.equal(s.inputs[1].forward, false, label + " touch stick drove P2")
  } else {
    await step(page, mode, 6)
    const after = await state(page, mode)
    assert.ok(moved(before.tanks[0], after.tanks[0]) > 0.1, label + " touch stick did not move P1")
    assert.ok(moved(before.tanks[1], after.tanks[1]) < 1e-7, label + " touch stick moved P2")
  }
  await page.locator(selector).dispatchEvent("pointerup", { ...event, buttons: 0 })
}
async function instrumentInfinity(context) {
  await context.route("**/infinite.js*", async (route) => {
    const response = await route.fetch(),
      body = await response.text()
    assert.ok(body.includes("window.leqraInfinity = Object.freeze"), "Infinity probe insertion point")
    await route.fulfill({
      response,
      body: body.replace(
        "window.leqraInfinity = Object.freeze",
        infinityProbe + "\nwindow.leqraInfinity = Object.freeze",
      ),
    })
  })
}
async function desktop(browser, engine) {
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    serviceWorkers: "block",
  })
  await context.addInitScript(
    (name) => {
      for (const [key, value] of Object.entries({
        "introTour.v1": "1",
        infinityOnline: "0",
        infinityOffline: "0",
        muted: "1",
        name,
      }))
        localStorage.setItem("leqra." + key, value)
      window.requestAnimationFrame = () => 0
    },
    "D" + Date.now().toString(36) + (serial++).toString(36),
  )
  await instrumentInfinity(context)
  const page = await context.newPage(),
    packets = []
  page.on("pageerror", (error) => errors.push(engine + " desktop " + error.message))
  page.on("websocket", (socket) =>
    socket.on("framesent", (frame) => {
      try {
        packets.push(JSON.parse(frame.payload))
      } catch {}
    }),
  )
  await page.goto(url.href)
  await page.waitForFunction(() => window.__test && window.__p2Input, {}, { polling: 100 })
  await page.evaluate(() => {
    document.querySelector("#startRoomBtn").click()
    __test.setPhase("playing")
    __test.setWorld({ width: 840, height: 504, cols: 10, rows: 6, walls: [] })
    __test.pickups.length = 0
    __test.clearBullets()
    for (const [i, t] of __test.tanks.entries())
      Object.assign(t, {
        x: 250 + i * 150,
        y: 200,
        angle: 0,
        invulnerable: 0,
        spawnProtected: false,
        cooldown: 0,
        power: null,
      })
  })
  for (const mode of ["fixed", "offline", "online"]) {
    const label = engine + " desktop " + mode
    if (mode !== "fixed") {
      await page.evaluate((mode) => {
        window.leqraInfinity.close()
        window.leqraInfinity.start(mode, {
          name: localStorage.getItem("leqra.name"),
          public: mode === "online",
          roomRules: { infinityRandomBots: false },
        })
      }, mode)
      if (mode === "online")
        await page.waitForFunction(
          () => {
            const s = __p2Input.read()
            return s?.joined && s.ids.length === 1 && s.tanks.every(Boolean)
          },
          {},
          { timeout: 20000, polling: 100 },
        )
      else await page.evaluate(() => __p2Input.prepare())
    }
    await canvasFocus(page, mode)
    const point = await primaryPoint(page, mode)
    await page.mouse.move(point.x + 90, point.y - 65)
    const before = await state(page, mode)
    assert.equal(before.ids.length, 1, label + " unexpectedly added P2")
    await page.keyboard.down("ArrowUp")
    await page.keyboard.down("ArrowRight")
    if (mode === "online") {
      const s = await state(page, mode)
      assert.ok(s.inputs[0].forward && s.inputs[0].right, label + " arrows did not control P1")
      assert.ok(Math.hypot(s.inputs[0].aimX, s.inputs[0].aimY) > 0.1, label + " keyboard cleared mouse aim")
      await page.waitForTimeout(250)
    } else await step(page, mode, 12)
    await page.keyboard.up("ArrowRight")
    await page.keyboard.up("ArrowUp")
    const after = await state(page, mode)
    assert.ok(moved(before.tanks[0], after.tanks[0]) > 1, label + " P1 did not move")
    assert.ok(
      Math.abs(after.tanks[0].bodyAngle - before.tanks[0].bodyAngle) > 0.05,
      label + " P1 hull did not turn",
    )
    assert.ok(
      Math.abs(after.tanks[0].bodyAngle - after.tanks[0].angle) > 0.05,
      label + " turret followed hull",
    )
    if (mode !== "online") await readyShot(page, mode)
    const start = packets.length
    await page.mouse.down()
    if (mode === "online") {
      await page.waitForTimeout(40)
      assert.ok(
        packets
          .slice(start)
          .some((p) => p.type === "input" && p.fire && !p.local && Math.hypot(p.aimX, p.aimY) > 0.1),
        label + " mouse fire omitted turret aim",
      )
    } else {
      await step(page, mode)
      assert.ok(
        (await state(page, mode)).bullets.some((p) => p.owner === after.ids[0]),
        label + " mouse did not fire",
      )
    }
    await page.mouse.up()
    if (mode !== "online") await readyShot(page, mode)
    const padStart = packets.length
    await page.evaluate((mode) => {
      const art = window.leqraInfinityArt,
        pad = {
          connected: true,
          mapping: "standard",
          index: 9,
          id: "Mouse aim regression controller",
          axes: [0, 0, 0, 0],
          buttons: Array.from({ length: 17 }, () => ({ pressed: false, value: 0 })),
        }
      art.clearGamepads()
      art.sampleGamepads([pad], "mouse-fire:" + mode, true, false, false)
      pad.buttons[0] = { pressed: true, value: 1 }
      art.sampleGamepads([pad], "mouse-fire:" + mode, true, false, false)
      if (mode === "online") __p2Input.send()
    }, mode)
    if (mode === "online") {
      await page.waitForTimeout(40)
      assert.ok(
        packets.slice(padStart).some((p) => p.type === "input" && p.fire && Math.hypot(p.aimX, p.aimY) > 0.1),
        label + " gamepad Fire dropped mouse turret aim",
      )
    } else {
      await step(page, mode)
      const fired = await state(page, mode),
        shot = fired.bullets.find((b) => b.owner === fired.ids[0])
      assert.ok(shot, label + " gamepad Fire did not fire")
      assert.ok(
        Math.abs(Math.atan2(shot.vy, shot.vx) - fired.tanks[0].angle) < 0.02,
        label + " gamepad shot missed turret direction",
      )
      assert.ok(
        Math.abs(fired.tanks[0].bodyAngle - fired.tanks[0].angle) > 0.05,
        label + " gamepad Fire reset mouse turret",
      )
    }
    await page.evaluate((mode) => {
      window.leqraInfinityArt.clearGamepads()
      if (mode === "online") __p2Input.send()
    }, mode)
    records.push({
      engine,
      profile: "desktop",
      mode,
      checks: [
        "P1 arrow movement and turning",
        "independent mouse turret",
        "mouse firing",
        "gamepad Fire preserves mouse turret",
      ],
    })
    await page.screenshot({ path: path.join(output, engine + "-desktop-" + mode + ".png") })
    console.log("PASS " + label + " independent turret")
  }
  await context.close()
}
;(async () => {
  for (const [engine, type] of Object.entries({ chromium, webkit })) {
    if (selected && selected !== engine) continue
    const browser = await type.launch({ headless: true })
    if (!profileFilter || profileFilter === "desktop") await desktop(browser, engine)
    for (const profile of profiles) {
      const label = engine + " " + profile.name,
        stem = "I" + Date.now().toString(36) + (serial++).toString(36),
        names = [stem + "A", stem + "B"]
      const context = await browser.newContext({
        viewport: profile,
        hasTouch: true,
        isMobile: true,
        serviceWorkers: "block",
        ...(engine === "webkit"
          ? {
              userAgent:
                "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            }
          : {}),
      })
      await context.addInitScript((names) => {
        if (!navigator.maxTouchPoints) Object.defineProperty(navigator, "maxTouchPoints", { get: () => 5 })
        for (const [key, value] of Object.entries({
          "introTour.v1": "1",
          infinityOnline: "0",
          infinityOffline: "0",
          name: names[0],
          local2Name: names[1],
          muted: "1",
        }))
          localStorage.setItem("leqra." + key, value)
        window.requestAnimationFrame = () => 0
      }, names)
      await instrumentInfinity(context)
      const page = await context.newPage(),
        packets = []
      page.on("pageerror", (error) => errors.push(label + " " + error.message))
      page.on("websocket", (socket) =>
        socket.on("framesent", (frame) => {
          try {
            packets.push(JSON.parse(frame.payload))
          } catch {}
        }),
      )
      await page.goto(url.href)
      await page.waitForFunction(() => window.__test && window.__p2Input, {}, { polling: 100 })
      assert.equal(
        await page.evaluate(() => __test.localRoom.players.filter((p) => p.kind === "local").length),
        0,
        label + " auto-added P2",
      )
      await page.evaluate((names) => {
        const T = __test
        T.addRoomSeat("local")
        T.localRoom.players = T.localRoom.players.filter((p) => p.kind === "human" || p.kind === "local")
        for (const p of T.localRoom.players) p.name = names[p.kind === "local" ? 1 : 0]
        document.querySelector("#startRoomBtn").click()
        T.setPhase("playing")
        T.setWorld({ width: 840, height: 504, cols: 10, rows: 6, walls: [] })
        T.pickups.length = 0
        T.clearBullets()
        for (const [i, t] of T.tanks.entries())
          Object.assign(t, {
            x: 250 + i * 300,
            y: 200,
            angle: 0,
            invulnerable: 0,
            spawnProtected: false,
            cooldown: 0,
            power: null,
          })
      }, names)
      for (const mode of ["fixed", "offline", "online"]) {
        if (mode !== "fixed") {
          await page.evaluate(
            ({ mode, names }) => {
              window.leqraInfinity.close()
              window.leqraInfinity.start(mode, {
                name: names[0],
                localName: names[1],
                public: mode === "online",
                roomRules: { infinityRandomBots: false },
              })
            },
            { mode, names },
          )
          if (mode === "online")
            await page.waitForFunction(
              () => {
                const s = __p2Input.read()
                return s?.joined && s.ids.length === 2 && s.tanks.every(Boolean)
              },
              {},
              { timeout: 20000, polling: 100 },
            )
          else await page.evaluate(() => __p2Input.prepare())
        }
        await canvasFocus(page, mode)
        const s = await state(page, mode)
        assert.equal(s.ids.length, 2, label + " " + mode + " missing explicit P2")
        await movement(page, mode, "w", label + " " + mode + " WASD", packets)
        await movement(page, mode, "ArrowUp", label + " " + mode + " arrows", packets)
        await fire(page, mode, "keyboard", label + " " + mode + " keyboard", packets)
        await aim(page, mode, label + " " + mode + " aim")
        await driveWhileAiming(page, mode, label + " " + mode + " independent turret")
        await fire(page, mode, "mouse", label + " " + mode + " mouse", packets)
        await touchStick(page, mode, label + " " + mode + " joystick")
        await fire(page, mode, "touch", label + " " + mode + " touch", packets)
        records.push({
          engine,
          profile: profile.name,
          mode,
          checks: [
            "WASD→P2",
            "arrows→P2",
            "keyboard fire→P2",
            "mouse aim/fire→P2",
            "arrow movement with independent mouse turret→P2",
            "touch quick aim→P1",
            "touch joystick→P1",
            "touch fire→P1",
          ],
        })
        await page.screenshot({ path: path.join(output, engine + "-" + profile.name + "-" + mode + ".png") })
        console.log("PASS " + label + " " + mode + " input routing")
      }
      await page.evaluate(() => window.leqraInfinity.close())
      await context.close()
    }
    await browser.close()
  }
  assert.deepEqual(errors, [])
  fs.writeFileSync(path.join(output, "results.json"), JSON.stringify({ records, errors }, null, 2))
  console.log("PASS " + records.length + " scenarios; artifacts " + output)
})().catch((error) => {
  fs.writeFileSync(
    path.join(output, "failure.json"),
    JSON.stringify({ records, errors, error: error.stack }, null, 2),
  )
  console.error(error)
  process.exit(1)
})
