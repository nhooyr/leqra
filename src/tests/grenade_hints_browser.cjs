"use strict"
const { replaceSource, sourceIndex } = require("./source_helpers.cjs")
// Optional real-browser geometry regression. Runs an isolated staged loopback fixture.
// node src/tests/grenade_hints_browser.cjs /tmp/leqra-grenade-hints
const fs = require("node:fs"),
  path = require("node:path"),
  http = require("node:http"),
  assert = require("node:assert/strict")
const { chromium, webkit } = require("playwright"),
  { assetPath, assetVersion } = require("./web_assets.cjs")
const root = path.resolve(__dirname, "../.."),
  web = path.join(root, "src/web"),
  out = path.resolve(
    process.env.LEQRA_BROWSER_OUTPUT ||
      process.argv[2] ||
      fs.mkdtempSync(path.join(require("node:os").tmpdir(), "leqra-grenade-hints-")),
  )
if (out === root || out.startsWith(root + path.sep))
  throw Error("Keep generated screenshots outside the repository.")
fs.mkdirSync(out, { recursive: true })
const injection = `
window.__hintFixture={start(){mode='room';localRoom.rules=validateRoomRules({...defaultRoomRules(),mode:'elimination',infinity:false});localRoom.players=[{id:0,member:1,kind:'human',name:'Hint#BDF3XZ',colorIndex:0,team:0},{id:1,member:2,kind:'bot',name:'Rust',difficulty:'normal',colorIndex:1,team:0}];startMatch();phase='playing';updateHUD(true);render();},set(power,grenades,infinity=false){const t={alive:true,spawnProtected:false,invulnerable:0,starmanTime:0,power:power||null,cooldown:0,charges:3,machineRounds:0};renderPilotReadiness(t,1,{grenades,ammo:0,locked:false},false,null,infinity?infinityHUDId:undefined);}};
`
const source = fs.readFileSync(assetPath("game.js"), "utf8")
assert(sourceIndex(source, "if(new URLSearchParams(location.search).has('test'))window.__test=") >= 0)
const server = http.createServer((req, res) => {
  let pathname = new URL(req.url, "http://local").pathname
  if (pathname.startsWith("/api/")) {
    let body = ""
    req.on("data", (d) => (body += d))
    req.on("end", () => {
      let b = {}
      try {
        b = JSON.parse(body || "{}")
      } catch {}
      let v =
        pathname === "/api/build"
          ? { version: assetVersion, build: "fixture" }
          : pathname === "/api/infinity"
            ? { players: 0, tankCount: 0, capacity: 32, leaders: [] }
            : pathname === "/api/callsigns/generate"
              ? { names: (b.accounts || []).map((a) => ({ seat: a.seat, name: "pilot#BDF3XZ" })) }
              : {
                  names: (b.names || []).map((name, seat) => ({ name, seat, available: true, owned: false })),
                }
      res.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" })
      res.end(JSON.stringify(v))
    })
    return
  }
  const file = path.resolve(web, "." + (pathname === "/" ? "/index.html" : pathname))
  if (!file.startsWith(web + path.sep) || !fs.existsSync(file)) {
    res.writeHead(404)
    res.end()
    return
  }
  let body = fs.readFileSync(file)
  if (file.endsWith("/game.js"))
    body = Buffer.from(
      replaceSource(
        source,
        "if(new URLSearchParams(location.search).has('test'))window.__test=",
        injection + "if(new URLSearchParams(location.search).has('test'))window.__test=",
      ),
    )
  const types = {
    ".html": "text/html",
    ".js": "text/javascript",
    ".css": "text/css",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".webmanifest": "application/manifest+json",
  }
  res.writeHead(200, {
    "content-type": types[path.extname(file)] || "application/octet-stream",
    "cache-control": "no-store",
  })
  res.end(body)
})
;(async () => {
  await new Promise((r) => server.listen(0, "127.0.0.1", r))
  const origin = "http://127.0.0.1:" + server.address().port
  let browser
  const results = [],
    errors = []
  try {
    browser = await (process.env.LEQRA_BROWSER === "webkit" ? webkit : chromium).launch({ headless: true })
    for (const [label, width, height] of [
      ["smallest", 320, 568],
      ["small", 360, 780],
      ["narrow", 375, 812],
      ["portrait", 390, 844],
      ["landscape", 844, 390],
      ["compact-landscape", 568, 320],
      ["tablet-portrait", 768, 1024],
      ["tablet-landscape", 1024, 768],
    ]) {
      const context = await browser.newContext({
        viewport: { width, height },
        isMobile: true,
        hasTouch: true,
        deviceScaleFactor: 2,
        serviceWorkers: "block",
      })
      await context.addInitScript(() => {
        localStorage.setItem("leqra.introTour.v1", "1")
        localStorage.setItem("leqra.name", "Hint#BDF3XZ")
        localStorage.setItem("leqra.infinityOnline", "0")
        localStorage.setItem("leqra.infinityOffline", "0")
        localStorage.setItem("leqra.sound", "0")
        window.requestAnimationFrame = () => 0
      })
      const page = await context.newPage()
      page.on("pageerror", (e) => errors.push(e.message))
      await page.goto(origin + "/?test=1")
      await page.waitForFunction(() => window.__hintFixture && window.__test && window.leqraInfinity)
      await page.evaluate(() => window.__hintFixture.start())
      await page.waitForTimeout(100)
      await page.evaluate(() => {
        window.__test.resize()
        window.__test.render()
      })
      for (const arena of ["fixed", "infinity"]) {
        if (arena === "infinity") {
          await page.evaluate(() =>
            window.leqraInfinity.start("offline", {
              name: "Hint#BDF3XZ",
              roomRules: { infinityRandomBots: false },
            }),
          )
          await page.waitForTimeout(100)
        }
        const cases = [
            ["standard", "", 0],
            ["throw", "grenade", 0],
            ["equipped", "grenade", 1],
            ["depleted", "", 1],
          ],
          values = []
        for (const [name, power, grenades] of cases) {
          await page.evaluate(
            ({ power, grenades, arena }) => window.__hintFixture.set(power, grenades, arena === "infinity"),
            { power, grenades, arena },
          )
          await page.waitForTimeout(30)
          const base = await page
            .locator(arena === "fixed" ? "#stickBase" : "#infiniteStickBase")
            .boundingBox()
          await page.mouse.move(base.x + base.width / 2, base.y + base.height / 2)
          await page.mouse.down()
          await page.mouse.move(base.x + base.width / 2, base.y + base.height / 2 + 60)
          const value = await page.evaluate(
            ({ arena }) => {
              const ids =
                arena === "fixed"
                  ? {
                      fire: "fireBtn",
                      stick: "stickZone",
                      base: "stickBase",
                      controls: "touchControls",
                      hint: "fireHint",
                    }
                  : {
                      fire: "infiniteFire",
                      stick: "infiniteStick",
                      base: "infiniteStickBase",
                      controls: null,
                      hint: "infiniteFireHint",
                    }
              const rect = (n) => {
                if (!n) return null
                const r = n.getBoundingClientRect ? n.getBoundingClientRect() : n
                return { x: r.x, y: r.y, width: r.width, height: r.height, right: r.right, bottom: r.bottom }
              }
              const node = (id) => document.getElementById(id)
              const fire = node(ids.fire),
                stick = node(ids.stick),
                hint = node(ids.hint)
              const hit = (n) => {
                const r = n.getBoundingClientRect()
                return n.contains(document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2))
              }
              const center = hint?.closest(".touch-center"),
                label = stick.querySelector(".touch-label"),
                knob = stick.querySelector(".stick-knob"),
                controls = stick.closest(".touch-controls,.infinite-touch-controls")
              const range = hint && document.createRange()
              if (range) range.selectNodeContents(hint)
              return {
                fire: rect(fire),
                stick: rect(stick),
                base: rect(node(ids.base)),
                label: rect(label),
                visibleLabels: controls.querySelectorAll(".touch-label").length,
                version: rect(document.getElementById("headerVersion")),
                versionText: document.getElementById("headerVersion").textContent,
                target: rect(fire.querySelector("svg")),
                knob: rect(knob),
                controlsText: controls.textContent,
                overlaid: getComputedStyle(controls).position === "absolute",
                loadoutTop: document
                  .querySelector(arena === "fixed" ? ".underbar" : ".infinite-underbar")
                  .getBoundingClientRect().top,
                sidebarHint: document.querySelector(".manual-fire-tip")?.textContent,
                hint: hint?.textContent || null,
                center: rect(center),
                hintLines: range ? [...range.getClientRects()].map(rect) : [],
                hitFire: hit(fire),
                hitStick: hit(stick),
                scrollWidth: document.documentElement.scrollWidth,
                viewport: innerWidth,
                hintDisplay: center && getComputedStyle(center).display,
                aria: fire.getAttribute("aria-label"),
              }
            },
            { arena },
          )
          value.name = name
          values.push(value)
          assert(
            value.version.width > 0 && value.version.height > 0 && value.versionText.startsWith("v"),
            `${label}/${arena}/${name} hides the header version`,
          )
          assert.equal(value.visibleLabels, 0, `${label}/${arena}/${name} retains a control caption`)
          assert(
            Math.abs(value.target.y + value.target.height / 2 - value.fire.y - value.fire.height / 2) < 0.5 &&
              Math.abs(value.target.x + value.target.width / 2 - value.fire.x - value.fire.width / 2) < 0.5,
            `${label}/${arena}/${name} target symbol is not centered`,
          )
          assert(value.knob.bottom <= height, `${label}/${arena}/${name} thumb is clipped`)
          if (value.overlaid)
            assert(
              value.knob.bottom <= value.loadoutTop + 0.5 && value.fire.bottom + 8 <= value.loadoutTop + 0.5,
              `${label}/${arena}/${name} controls overlap the loadout`,
            )
          assert(
            !/LET IT RIP|HOLD TO FIRE|HOLD TO THROW/.test(value.controlsText),
            `${label}/${arena}/${name} repeats firing instructions`,
          )
          assert.match(value.sidebarHint || "", /Hold.*fire/i)
          await page.mouse.up()
          await page.screenshot({ path: path.join(out, label + "-" + arena + "-" + name + ".png") })
          assert(value.hitFire && value.hitStick, `${label}/${arena}/${name} control covered`)
          assert(
            value.fire.x >= 0 &&
              value.fire.right <= width &&
              value.stick.x >= 0 &&
              value.stick.right <= width,
            `${label}/${arena}/${name} control overflow`,
          )
          assert(value.scrollWidth <= width, `${label}/${arena}/${name} document overflow`)
          if (value.center && value.hintDisplay !== "none") {
            assert(
              value.center.y >= 0 && value.center.bottom <= height,
              `${label}/${arena}/${name} hint clipped vertically`,
            )
            for (const line of value.hintLines)
              assert(
                line.x >= value.base.right - 0.5 && line.right <= value.fire.x + 0.5,
                `${label}/${arena}/${name} hint overlaps a touch control`,
              )
          }
        }
        const a = values.find((v) => v.name === "equipped"),
          b = values.find((v) => v.name === "depleted")
        for (const value of values) {
          for (const target of ["fire", "stick", "base"]) {
            for (const key of ["x", "y", "width", "height"])
              assert(
                Math.abs(value[target][key] - values[0][target][key]) < 0.01,
                `${label}/${arena}/${value.name}: ${target}.${key} moved with hint`,
              )
          }
        }
        const delta = {
          fireX: b.fire.x - a.fire.x,
          fireY: b.fire.y - a.fire.y,
          fireW: b.fire.width - a.fire.width,
          stickX: b.stick.x - a.stick.x,
          stickW: b.stick.width - a.stick.width,
        }
        results.push({ label, arena, values, delta })
      }
      await context.close()
    }
    fs.writeFileSync(path.join(out, "report.json"), JSON.stringify({ results, errors }, null, 2))
    assert.equal(errors.length, 0)
    console.log(
      JSON.stringify(
        {
          results: results.map((r) => ({
            label: r.label,
            arena: r.arena,
            delta: r.delta,
            controls: r.values.map((v) => ({
              name: v.name,
              fire: v.fire,
              stick: v.stick,
              hint: v.hint,
              center: v.center,
            })),
          })),
          errors,
        },
        null,
        2,
      ),
    )
  } finally {
    if (browser) await browser.close()
    await new Promise((r) => server.close(r))
  }
})().catch((e) => {
  console.error(e.stack)
  process.exitCode = 1
})
