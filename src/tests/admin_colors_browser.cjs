"use strict"
// Real clients against a disposable database; sqlite3 seeds a stable test leader while the server is stopped.
// node src/tests/admin_colors_browser.cjs /path/to/leqra /tmp/artifacts
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { randomBytes } = require("node:crypto")
const { spawn, execFileSync } = require("node:child_process")
const { chromium, webkit, devices } = require("playwright")

const binary = path.resolve(process.argv[2])
const output = path.resolve(process.argv[3] || path.join(os.tmpdir(), "leqra-admin-colors-browser"))
const directory = fs.mkdtempSync(path.join(os.tmpdir(), "leqra-admin-colors-server-"))
const database = path.join(directory, "data.sqlite")
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
let server,
  origin,
  adminURL,
  log = ""
fs.mkdirSync(output, { recursive: true })

async function startServer() {
  log = ""
  server = spawn(binary, [], {
    cwd: directory,
    env: {
      ...process.env,
      ADDR: origin ? new URL(origin).host : "127.0.0.1:0",
      LEQRA_ADMIN_ADDR: adminURL ? new URL(adminURL).host : "127.0.0.1:0",
      LEQRA_DATA: database,
    },
    stdio: ["ignore", "pipe", "pipe"],
  })
  for (const pipe of [server.stdout, server.stderr]) pipe.on("data", (chunk) => (log += chunk))
  for (let attempt = 0; attempt < 400; attempt++) {
    const game = log.match(/^http:\/\/localhost:(\d+)/m)
    const admin = log.match(/^admin: (http:\/\/\S+)/m)
    if (game && admin) {
      origin = "http://127.0.0.1:" + game[1]
      adminURL = admin[1]
      return
    }
    if (server.exitCode !== null) throw Error("Disposable server exited: " + log)
    await delay(25)
  }
  throw Error("Disposable server did not start: " + log)
}

async function stopServer() {
  if (!server || server.exitCode !== null) return
  const ended = new Promise((resolve) => server.once("exit", resolve))
  server.kill("SIGTERM")
  await Promise.race([ended, delay(6000)])
  if (server.exitCode === null) {
    server.kill("SIGKILL")
    await ended
  }
}

async function register(name) {
  const key = "p_" + randomBytes(32).toString("base64url")
  const response = await fetch(origin + "/api/account/create", {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: origin },
    body: JSON.stringify({ name, publicToken: key }),
  })
  assert.equal(response.status, 200, "create disposable account " + name)
  return key
}

async function gameContext(browser, profile, names, keys, errors) {
  const context = await browser.newContext({ ...profile, serviceWorkers: "block" })
  await context.addInitScript(
    ({ names, keys }) => {
      localStorage.setItem("leqra.introTour.v1", "1")
      localStorage.setItem("leqra.muted", "1")
      if (!localStorage.getItem("__adminColorsSeeded")) {
        localStorage.setItem("leqra.name", names[0])
        localStorage.setItem("leqra.publicToken", keys[0])
        if (names[1]) {
          localStorage.setItem("leqra.local2Name", names[1])
          localStorage.setItem("leqra.localPublicToken", keys[1])
        }
        localStorage.setItem("leqra.pilotColors", JSON.stringify(names[1] ? [2, 3] : [4, 5]))
        localStorage.setItem("__adminColorsSeeded", "1")
      }
      window.__colors = { opens: 0, closes: 0, welcomes: [], state: null, states: 0 }
      const RealSocket = WebSocket
      window.WebSocket = class extends RealSocket {
        constructor(...args) {
          super(...args)
          if (!String(args[0]).includes("/ws/infinite")) return
          this.addEventListener("open", () => __colors.opens++)
          this.addEventListener("close", () => __colors.closes++)
          this.addEventListener("message", (event) => {
            const packet = JSON.parse(event.data)
            if (packet.type === "welcome")
              __colors.welcomes.push({ id: packet.id, localId: packet.localId, resumed: packet.resumed })
            if (packet.type === "state") {
              const copy = (tank) => ({
                id: tank.id,
                name: tank.name,
                bot: !!tank.bot,
                colorIndex: tank.colorIndex,
                score: tank.score,
              })
              __colors.state = {
                tick: packet.tick,
                tanks: packet.tanks.map(copy),
                leaderboard: packet.leaderboard.map(copy),
              }
              __colors.states++
            }
          })
        }
      }
    },
    { names, keys },
  )
  const page = await context.newPage()
  page.on("pageerror", (error) => errors.push(error.message))
  await page.goto(origin + "/?test=1")
  await startGame(page, names)
  return { context, page, names }
}

async function startGame(page, names) {
  await page.waitForFunction(() => window.__test && window.leqraInfinity)
  await page.evaluate((names) => {
    if (names[1] && !__test.localRoom.players.some((player) => player.kind === "local"))
      __test.addRoomSeat("local")
    const colors = JSON.parse(localStorage.getItem("leqra.pilotColors") || "[]")
    leqraInfinity.start("online", {
      public: true,
      name: names[0],
      localName: names[1],
      colorIndex: colors[0],
      localColorIndex: colors[1],
    })
  }, names)
  await page.waitForFunction(
    (paired) =>
      __colors.welcomes.length && __colors.state && leqraInfinity.localPilots().length === (paired ? 2 : 1),
    !!names[1],
  )
}

const read = (page) =>
  page.evaluate(() => ({
    ...__colors,
    pilots: leqraInfinity.localPilots(),
    saved: JSON.parse(localStorage.getItem("leqra.pilotColors") || "[]"),
    palette: leqraInfinityArt.colors,
  }))

async function main() {
  await startServer()
  const reports = []
  for (const [label, engine, profile] of [
    ["desktop-chromium", chromium, { viewport: { width: 1280, height: 900 } }],
    ["mobile-webkit", webkit, devices["iPhone 13"]],
  ]) {
    const names = [
      "Color Lead " + reports.length,
      "Color Wing " + reports.length,
      "Color Remote " + reports.length,
    ]
    const keys = []
    for (const name of names) keys.push(await register(name))
    const browser = await engine.launch({ headless: true })
    try {
      const errors = []
      const paired = await gameContext(browser, profile, names.slice(0, 2), keys.slice(0, 2), errors)
      const remote = await gameContext(browser, profile, names.slice(2), keys.slice(2), errors)
      const leaderID = (await read(paired.page)).welcomes.at(-1).id
      await paired.page.waitForFunction(() => __colors.state.tanks.some((tank) => tank.bot))
      await stopServer()
      execFileSync("sqlite3", [
        database,
        "UPDATE infinity_scores SET score=CASE WHEN id=" + leaderID + " THEN 10000 ELSE 0 END;",
      ])
      await startServer()
      for (const client of [paired, remote])
        await client.page.waitForFunction(
          (leaderID) =>
            __colors.welcomes.length >= 2 &&
            __colors.state?.leaderboard[0]?.id === leaderID &&
            __colors.state.leaderboard[0].score > 9000,
          leaderID,
          { timeout: 20000 },
        )
      const before = await Promise.all([read(paired.page), read(remote.page)])
      const baseline = new Map(
        before
          .flatMap((item) => [...item.state.tanks, ...item.state.leaderboard])
          .map((tank) => [tank.id, tank]),
      )
      const admin = await paired.context.newPage()
      admin.on("pageerror", (error) => errors.push(error.message))
      await admin.goto(adminURL)
      await admin.locator("#pattern").fill("NO MATCHING PILOT")
      await admin.waitForFunction(() => document.querySelector("#counts").textContent.includes("0 shown"))
      admin.once("dialog", (dialog) => dialog.accept())
      await admin.getByRole("button", { name: "Randomize tank colors" }).click()
      await admin.waitForFunction(() =>
        document.querySelector("#status").textContent.startsWith("Tank colors randomized."),
      )
      const expected = Object.fromEntries([...baseline].map(([id, tank]) => [id, tank.colorIndex]))
      for (const client of [paired, remote])
        await client.page.waitForFunction(
          ({ expected, leaderID }) => {
            const current = __colors.state
            if (
              !current ||
              current.leaderboard[0]?.id !== leaderID ||
              current.leaderboard[0].colorIndex !== 0
            )
              return false
            const welcome = __colors.welcomes.at(-1)
            return [welcome.id, welcome.localId].filter(Number.isInteger).every((id) => {
              const tank = current.tanks.find((tank) => tank.id === id)
              return (
                tank &&
                (id === leaderID
                  ? tank.colorIndex === 0
                  : tank.colorIndex > 0 && tank.colorIndex !== expected[id])
              )
            })
          },
          { expected, leaderID },
        )
      const after = await Promise.all([read(paired.page), read(remote.page)])
      let checkedBots = 0
      for (let index = 0; index < after.length; index++) {
        const value = after[index]
        assert.equal(value.opens, before[index].opens, "randomization does not reconnect clients")
        assert.equal(value.closes, before[index].closes, "randomization keeps connections open")
        assert.equal(value.welcomes.length, before[index].welcomes.length)
        for (const tank of [...value.state.tanks, ...value.state.leaderboard]) {
          const previous = baseline.get(tank.id)
          if (!previous) continue
          assert.equal(tank.colorIndex === 0, tank.id === leaderID, "only the leader is blue")
          if (tank.id !== leaderID)
            assert.notEqual(tank.colorIndex, previous.colorIndex, "new color for " + tank.name)
          if (tank.bot) checkedBots++
        }
        value.pilots.forEach((pilot, seat) => {
          const tank = value.state.tanks.find((tank) => tank.id === pilot.id)
          assert.equal(value.saved[seat], tank.colorIndex, "client saved authoritative color")
          assert.equal(pilot.color, value.palette[tank.colorIndex], "rendered pilot uses authoritative color")
        })
      }
      assert(checkedBots > 0, "live bot colors were checked")
      assert.equal(
        await admin.locator(".table").evaluate((table) => table.scrollWidth <= table.clientWidth + 1),
        true,
        label + " admin table fits the viewport",
      )
      await admin.screenshot({ path: path.join(output, label + ".png"), fullPage: true })
      await paired.page.screenshot({ path: path.join(output, label + "-game.png"), fullPage: true })
      for (let index = 0; index < after.length; index++) {
        const client = [paired, remote][index]
        await client.page.reload()
        await startGame(client.page, client.names)
        const resumed = await read(client.page)
        assert.equal(resumed.welcomes.at(-1).resumed, true)
        assert.deepEqual(resumed.saved, after[index].saved, "saved colors survive reload")
        assert.deepEqual(
          resumed.pilots.map((pilot) => pilot.color),
          after[index].pilots.map((pilot) => pilot.color),
        )
      }
      assert.deepEqual(errors, [])
      reports.push({
        label,
        clients: 2,
        pilots: 3,
        botsChecked: checkedBots,
        liveUpdate: true,
        reloadPreserved: true,
      })
    } finally {
      await browser.close()
    }
  }
  fs.writeFileSync(path.join(output, "results.json"), JSON.stringify(reports, null, 2))
  console.log(JSON.stringify({ reports, output }))
}

main()
  .catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
  .finally(async () => {
    await stopServer()
    fs.rmSync(directory, { recursive: true, force: true })
  })
