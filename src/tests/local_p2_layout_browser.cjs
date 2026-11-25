"use strict"
// Optional phone/tablet HUD regression test against a disposable loopback server.
// node src/tests/local_p2_layout_browser.cjs http://127.0.0.1:8080 --browser=chromium
const assert = require("node:assert/strict"),
  fs = require("node:fs"),
  os = require("node:os"),
  path = require("node:path")
const { chromium, webkit } = require("playwright")
const address = process.argv.find((value) => /^https?:/.test(value)) || "http://127.0.0.1:8080"
const url = new URL(address)
assert.ok(["127.0.0.1", "localhost", "[::1]"].includes(url.hostname), "Use a disposable loopback server.")
url.searchParams.set("test", "1")
const output = process.env.LEQRA_BROWSER_OUTPUT || fs.mkdtempSync(path.join(os.tmpdir(), "leqra-p2-layout-"))
fs.mkdirSync(output, { recursive: true })
const selected = process.argv.find((value) => value.startsWith("--browser="))?.split("=")[1]
const widthFilter = Number(process.argv.find((value) => value.startsWith("--width="))?.split("=")[1])
const profiles = [
  [320, 568],
  [390, 844],
  [568, 320],
  [844, 390],
  [768, 1024],
  [1024, 768],
  [500, 768, true, 768, 1024],
  [1280, 900, false],
].filter(([width]) => !widthFilter || widthFilter === width)
const names = ["WIDE PILOT ALPHA", "WIDE PILOT BRAVO"]
const errors = []
async function checkStatusPlacement(page, arena, label) {
  const data = await page.evaluate((arena) => {
    const root = arena === "showcase" ? document.querySelector("#showcaseDialog") : document,
      header = root.querySelector(arena === "showcase" ? ".header" : "#gameHeader"),
      stage = root.querySelector(arena === "fixed" ? "#arenaWrap" : ".infinite-stage"),
      status =
        arena === "fixed"
          ? document.getElementById(
              document.body.classList.contains("public-infinity-preview")
                ? "infinityPreviewBar"
                : "arenaStatusBar",
            )
          : root.querySelector(arena === "showcase" ? ".arena-bar" : "#infiniteStatusbar"),
      rect = (node) => {
        const { top, bottom, height, left, right, width } = node.getBoundingClientRect()
        return { top, bottom, height, left, right, width }
      }
    return {
      footer: document.body.classList.contains("status-footer"),
      combined: document.body.classList.contains("tablet-header"),
      header: rect(header),
      stage: rect(stage),
      status: rect(status),
      height: innerHeight,
      statusInHeader: header.contains(status),
      headerStatusCount: header.querySelectorAll(".arena-bar").length,
      headerOverflows: header.scrollWidth > header.clientWidth + 1,
      statusOverflows: status.scrollWidth > status.clientWidth + 1,
      statusChildren: [...status.children]
        .filter((node) => node.getClientRects().length && !node.hidden)
        .map(rect),
      brand: rect(header.querySelector(".brand")),
      actions: rect(header.querySelector(".header-right")),
      statusText: [...status.querySelectorAll("span,strong,h2,button")]
        .filter((node) => node.getClientRects().length && !node.hidden && node.textContent.trim())
        .map((node) => ({
          text: node.textContent,
          font: parseFloat(getComputedStyle(node).fontSize),
          overflow: node.scrollWidth > node.clientWidth + 1,
          icon: getComputedStyle(node, "::after").maskImage !== "none",
        })),
    }
  }, arena)
  assert.ok(data.status.height > 0, label + " status hidden")
  assert.ok(data.header.bottom <= data.stage.top + 1, label + " main header moved below the maze")
  if (data.combined) {
    assert.equal(data.statusInHeader, true, label + " tablet status is outside main header")
    assert.equal(data.headerStatusCount, 1, label + " tablet header duplicates arena status")
    assert.ok(
      data.status.top >= data.header.top - 1 && data.status.bottom <= data.header.bottom + 1,
      label + " combined status leaves header",
    )
    assert.equal(data.headerOverflows, false, label + " combined header overflows")
    assert.ok(data.brand.right <= data.status.left + 1, label + " brand overlaps status")
    assert.ok(data.status.right <= data.actions.left + 1, label + " status overlaps actions")
    for (const child of data.statusChildren)
      assert.ok(
        Math.abs(child.top + child.height / 2 - (data.status.top + data.status.height / 2)) <= 1,
        label + " tablet status wraps or is not vertically centered",
      )
    if (!data.statusOverflows && data.statusChildren.length) {
      const left = Math.min(...data.statusChildren.map((child) => child.left)),
        right = Math.max(...data.statusChildren.map((child) => child.right))
      assert.ok(
        Math.abs((left + right) / 2 - (data.status.left + data.status.right) / 2) <= 1,
        label + " tablet status is not horizontally centered",
      )
    }
    if (data.header.width >= 750)
      assert.equal(data.statusOverflows, false, label + " ordinary tablet status needs horizontal scrolling")
  } else {
    assert.equal(data.statusInHeader, false, label + " separate arena status moved into main header")
    if (data.footer)
      assert.ok(data.status.top >= data.stage.bottom - 1, label + " status is not below the maze")
    else assert.ok(data.status.bottom <= data.stage.top + 1, label + " phone status moved below the maze")
  }
  for (const text of data.statusText) {
    assert.ok(text.font >= 10, label + " status text too small: " + text.text)
    if (!text.icon) assert.equal(text.overflow, false, label + " status text clipped: " + text.text)
  }
  assert.ok(data.status.bottom <= data.height + 1, label + " status outside viewport")
}
async function checkPreviewCoverage(page, label) {
  await page.evaluate(() => {
    const toggle = document.querySelector("#infinityToggle")
    toggle.checked = true
    toggle.dispatchEvent(new Event("change", { bubbles: true }))
  })
  await page.waitForFunction(() => document.body.classList.contains("infinity-preview"))
  const data = await page.evaluate(() => {
    const stage = document.querySelector(".arena-stage").getBoundingClientRect(),
      wrap = document.querySelector(".arena-wrap").getBoundingClientRect(),
      canvas = document.querySelector("#arena").getBoundingClientRect(),
      hud = document.querySelector(".underbar")
    return {
      stage: stage.bottom,
      wrap: wrap.bottom,
      canvas: canvas.bottom,
      hudHeight: hud.getBoundingClientRect().height,
      hudDisplay: getComputedStyle(hud).display,
      touch: document.body.classList.contains("touch-ui"),
    }
  })
  if (!data.touch) {
    assert.equal(data.hudDisplay, "none", label + " inactive HUD still reserves preview space")
    assert.equal(data.hudHeight, 0, label + " blank strip below preview")
    assert.ok(Math.abs(data.stage - data.wrap) < 1, label + " preview does not fill the stage")
  }
  assert.ok(Math.abs(data.canvas - data.wrap) < 1, label + " preview canvas leaves a bottom gap")
  await checkStatusPlacement(page, "fixed", label + " preview")
  await page.screenshot({ path: path.join(output, label.replace(/[^a-z0-9]+/gi, "-") + "-preview.png") })
  if (await page.evaluate(() => document.body.classList.contains("tablet-header"))) {
    await page.locator("#infinityPreviewScoreboardBtn").click()
    assert.equal(
      await page.locator("#infinityPreviewScoreboard").evaluate((panel) => panel.open && !panel.hidden),
      true,
      label + " tablet leaderboard does not open",
    )
    await page.locator("#infinityPreviewScoreboardNote").click()
    assert.equal(
      await page.locator("#infinityPreviewScoreboard").evaluate((panel) => panel.open && !panel.hidden),
      true,
      label + " interacting with tablet leaderboard closes it",
    )
    await page.locator("#infinityPreviewScoreboardBtn").click()
  }
  await page.evaluate(() => {
    const toggle = document.querySelector("#infinityToggle")
    toggle.checked = false
    toggle.dispatchEvent(new Event("change", { bubbles: true }))
  })
}
async function checkHUD(page, arena, variant, label) {
  const data = await page.evaluate(
    ({ arena, variant, names }) => {
      const T = window.__test,
        ids =
          arena === "fixed"
            ? ["pilotLoadout1", "pilotLoadout2"]
            : ["infinitePilotLoadout1", "infiniteLocalLoadout"]
      const pilots = T.tanks.filter((tank) => tank.human).slice(0, 2)
      for (const [index, tank] of pilots.entries()) {
        Object.assign(tank, {
          name: names[index],
          alive: true,
          power: variant === "machine" ? "rapid" : "scatter",
          powerTime: 10,
          charges: 10,
          machineRounds: 90,
          shield: 10,
          shieldCharges: 5,
          speedTime: 10,
          speedStacks: 5,
          ghostTime: 10,
          starmanTime: 0,
          cooldown: 0.6,
          cooldownTotal: 0.8,
          invulnerable: 0,
          spawnProtected: false,
        })
        T.setPilotFeedback(index, "", 0)
      }
      if (arena === "fixed") {
        T.updateHUD(true)
        T.updateCombatFeedback(true)
      } else
        for (const [index, tank] of pilots.entries())
          window.leqraInfinityArt.renderLoadout(
            tank,
            index + 1,
            { ammo: 0, grenades: 0, grenadeLife: 0, locked: true },
            false,
            "playing",
            true,
          )
      const rect = (e) => {
        const { left, top, right, bottom, width, height } = e.getBoundingClientRect()
        return { left, top, right, bottom, width, height }
      }
      return {
        width: innerWidth,
        height: innerHeight,
        touch: document.body.classList.contains("touch-ui"),
        tablet: document.body.classList.contains("tablet-header"),
        bodyWidth: document.body.scrollWidth,
        version: rect(document.querySelector("#headerVersion")),
        versionText: document.querySelector("#headerVersion").textContent,
        github: rect(document.querySelector(".github-link")),
        captions: document.querySelector(arena === "fixed" ? "#touchControls" : ".infinite-touch-controls")
          .innerText,
        header: rect(document.querySelector("#gameHeader")),
        stage: rect(document.querySelector(arena === "fixed" ? "#arenaWrap" : ".infinite-stage")),
        panels: ids.map((id) => {
          const panel = document.getElementById(id),
            name = panel.querySelector(".loadout-name")
          return {
            rect: rect(panel),
            name: name.textContent,
            color: getComputedStyle(name).color,
            weight: getComputedStyle(name).fontWeight,
            text: [
              ...panel.querySelectorAll(
                ".loadout-name,.weapon,.buff-label,.cooldown-line>span,.lock-status,.firing-budget strong",
              ),
            ]
              .filter((e) => e.getClientRects().length && getComputedStyle(e).visibility !== "hidden")
              .map((e) => ({
                text: e.textContent,
                rect: rect(e),
                font: parseFloat(getComputedStyle(e).fontSize),
                w: e.clientWidth,
                sw: e.scrollWidth,
                h: e.clientHeight,
                sh: e.scrollHeight,
              })),
          }
        }),
      }
    },
    { arena, variant, names },
  )
  assert.ok(data.bodyWidth <= data.width + 1, label + " page overflows")
  assert.ok(data.stage.height > 30, label + " arena collapsed")
  assert.ok(data.versionText, label + " version text removed")
  if (data.tablet && data.width <= 960)
    assert.ok(data.github.width > 0 && data.github.height > 0, label + " GitHub icon hidden")
  else assert.ok(data.version.width > 0 && data.version.height > 0, label + " version hidden")
  assert.doesNotMatch(data.captions, /\b(STEER|FIRE|LET IT RIP)\b/, label + " touch captions returned")
  const [first, second] = data.panels
  assert.ok(
    first.rect.right <= second.rect.left + 1 || first.rect.bottom <= second.rect.top + 1,
    label + " local HUD panels overlap",
  )
  if (data.tablet && data.width >= 768)
    assert.ok(Math.abs(first.rect.top - second.rect.top) < 1, label + " tablet pilots are stacked")
  assert.notEqual(first.color, second.color, label + " pilot colors lost")
  for (const [index, panel] of data.panels.entries()) {
    assert.equal(panel.name, names[index] + " (P" + (index + 1) + ")", label + " identity")
    assert.ok(Number(panel.weight) >= 700, label + " identity is not bold")
    if (data.touch)
      assert.ok(
        panel.rect.top >= data.header.bottom - 1 && panel.rect.bottom <= data.stage.top + 1,
        label + " pilot status must stay between the header and playfield",
      )
    else assert.ok(panel.rect.top >= data.stage.bottom - 1, label + " desktop status stays below the arena")
    assert.ok(
      panel.rect.left >= -1 &&
        panel.rect.right <= data.width + 1 &&
        panel.rect.top >= 0 &&
        panel.rect.bottom <= data.height + 1,
      label + " panel leaves viewport",
    )
    assert.ok(
      panel.text.some((item) => item.text.includes("COOLDOWN")),
      label + " readiness missing",
    )
    assert.ok(
      panel.text.some(
        (item) => item.text.includes("SHD") && item.text.includes("SPD") && item.text.includes("GHO"),
      ),
      label + " buffs missing",
    )
    for (const item of panel.text) {
      assert.ok(item.font >= 10, label + " tiny text " + item.text)
      assert.ok(item.sw <= item.w + 1 && item.sh <= item.h + 1, label + " clipped " + item.text)
      assert.ok(
        item.rect.left >= panel.rect.left - 1 &&
          item.rect.right <= panel.rect.right + 1 &&
          item.rect.top >= panel.rect.top - 1 &&
          item.rect.bottom <= panel.rect.bottom + 1,
        label + " text outside pilot panel " + item.text,
      )
    }
  }
  await checkStatusPlacement(page, arena, label)
  await page.screenshot({ path: path.join(output, label.replace(/[^a-z0-9]+/gi, "-") + ".png") })
}
;(async () => {
  for (const [name, type] of Object.entries({ chromium, webkit })) {
    if (selected && selected !== name) continue
    const browser = await type.launch({ headless: true })
    for (const [width, height, touch = true, deviceWidth = width, deviceHeight = height] of profiles) {
      const context = await browser.newContext({
        viewport: { width, height },
        screen: { width: deviceWidth, height: deviceHeight },
        hasTouch: touch,
        isMobile: touch,
        serviceWorkers: "block",
      })
      await context.addInitScript(() => {
        localStorage.setItem("leqra.introTour.v1", "1")
        localStorage.setItem("leqra.infinityOnline", "0")
        localStorage.setItem("leqra.infinityOffline", "0")
        localStorage.setItem("leqra.name", "WIDE PILOT ALPHA")
        localStorage.setItem("leqra.local2Name", "WIDE PILOT BRAVO")
      })
      const page = await context.newPage()
      page.on("pageerror", (error) => errors.push(name + " " + error.message))
      await page.goto(url.href)
      await page.waitForFunction(() => window.__test)
      const dismiss = page.getByRole("button", { name: "Dismiss browser recommendation" })
      if (await dismiss.count()) await dismiss.click()
      await checkStatusPlacement(page, "fixed", name + " " + width + "x" + height + " ready room")
      await checkPreviewCoverage(page, name + " " + width + "x" + height)
      await page.evaluate((names) => {
        window.requestAnimationFrame = () => 0
        const T = __test
        T.addRoomSeat("local")
        for (const player of T.localRoom.players)
          if (player.kind === "human" || player.kind === "local")
            player.name = names[player.kind === "local" ? 1 : 0]
        document.querySelector("#startRoomBtn").click()
        T.setPhase("playing")
      }, names)
      for (const variant of ["equipment", "machine"])
        await checkHUD(page, "fixed", variant, name + " " + width + "x" + height + " fixed " + variant)
      await page.evaluate(
        (names) =>
          window.leqraInfinity.start("offline", {
            name: names[0],
            localName: names[1],
            roomRules: { infinityRandomBots: false },
          }),
        names,
      )
      for (const variant of ["equipment", "machine"])
        await checkHUD(page, "infinite", variant, name + " " + width + "x" + height + " infinite " + variant)
      await page.evaluate(() => {
        window.leqraInfinity.close()
        window.leqraShowcase.open()
      })
      await checkStatusPlacement(page, "showcase", name + " " + width + "x" + height + " showcase")
      await context.close()
      console.log("PASS " + name + " " + width + "x" + height + " two-pilot fixed/Infinity HUD")
    }
    await browser.close()
  }
  assert.deepEqual(errors, [])
  console.log("Screenshots: " + output)
})().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
