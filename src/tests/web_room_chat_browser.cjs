"use strict"
// Run against an isolated loopback server: node src/tests/web_room_chat_browser.cjs URL --disposable OUTPUT
const { chromium, webkit } = require("playwright"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  path = require("node:path"),
  os = require("node:os")
const args = process.argv.slice(2),
  address = args.find((v) => /^https?:/.test(v))
if (!args.includes("--disposable") || !address)
  throw Error("Provide an isolated loopback server and --disposable.")
const origin = new URL(address)
if (
  !["localhost", "127.0.0.1", "[::1]"].includes(origin.hostname) ||
  origin.username ||
  origin.password ||
  origin.pathname !== "/"
)
  throw Error("Use a loopback origin.")
const output = path.resolve(
    args.find((v) => v !== address && v !== "--disposable") ||
      fs.mkdtempSync(path.join(os.tmpdir(), "leqra-web-chat-")),
  ),
  root = path.resolve(__dirname, "../..")
if (output === root || output.startsWith(root + path.sep))
  throw Error("Keep generated results outside the repository.")
fs.mkdirSync(output, { recursive: true })
const profiles = [
    ["desktop", "chromium", 1280, 900, false],
    ["mobile", "chromium", 390, 844, false],
    ["landscape", "webkit", 844, 390, false],
    ["pwa-portrait", "webkit", 390, 844, true],
    ["pwa-landscape", "chromium", 844, 390, true],
  ],
  errors = [],
  checks = []
;(async () => {
  const browsers = {
    chromium: await chromium.launch({ args: ["--disable-features=LocalNetworkAccessChecks"] }),
    webkit: await webkit.launch(),
  }
  let serial = 0
  const run = Date.now().toString(36).slice(-5)
  async function open(browser, name, width, height, standalone) {
    const c = await browser.newContext({
      viewport: { width, height },
      hasTouch: width !== 1280,
      isMobile: width !== 1280,
      serviceWorkers: "allow",
    })
    await c.addInitScript(
      ({ name, standalone }) => {
        localStorage.setItem("leqra.name", name)
        localStorage.setItem("leqra.introTour.v1", "1")
        localStorage.setItem("leqra.infinityOnline", "0")
        sessionStorage.setItem("leqra.safariNoticeDismissed", "1")
        if (standalone) {
          Object.defineProperty(navigator, "standalone", { get: () => true })
          const original = window.matchMedia.bind(window)
          window.matchMedia = (query) => {
            const m = original(query)
            return query === "(display-mode: standalone)"
              ? new Proxy(m, {
                  get(target, key) {
                    if (key === "matches") return true
                    const v = Reflect.get(target, key, target)
                    return typeof v === "function" ? v.bind(target) : v
                  },
                })
              : m
          }
        }
      },
      { name, standalone },
    )
    const p = await c.newPage()
    p.on("pageerror", (e) => errors.push(e.message))
    return { c, p }
  }
  async function send(from, to, text, label) {
    await from.locator("#chatBtn").click()
    await from.locator("#chatInput").fill(text)
    await from.locator("#chatSendBtn").click()
    await to.waitForFunction(
      (text) => __test.roomChat.channels.room.messages.some((m) => m.text === text),
      text,
    )
    assert(await from.locator("#chatPanel").isVisible())
    assert.equal(await from.locator("#chatInput").inputValue(), "")
    await from.locator("#chatCloseBtn").click()
    checks.push(label)
  }
  try {
    for (const [label, engine, width, height, standalone] of profiles)
      for (const infinity of [false, true]) {
        const host = await open(browsers.chromium, "CH" + run + ++serial, 1280, 900, false),
          guest = await open(browsers[engine], "CG" + run + serial, width, height, standalone)
        try {
          await host.p.goto(origin + "?test=1")
          await host.p.waitForFunction(() => window.__test)
          await host.p.evaluate(() => (document.getElementById("roomSettings").open = true))
          await host.p.locator(infinity ? '[data-room-mode="infinity"]' : '[data-room-mode="ctf"]').click()
          await host.p.locator("#copyInviteBtn").click()
          await host.p.waitForFunction(() => __test.online.connected)
          const code = await host.p.evaluate(() => __test.online.code)
          await guest.p.goto(origin + "?test=1&room=" + code)
          await guest.p.locator("#joinRoomBtn").click()
          await guest.p.waitForFunction(() => __test.online.connected)
          await send(guest.p, host.p, "Lobby " + serial, label + " lobby send")
          await guest.p.locator("#readyBtn").click()
          await host.p.waitForFunction(() => !document.getElementById("startRoomBtn").disabled)
          await host.p.locator("#startRoomBtn").click()
          await Promise.all(
            [host.p, guest.p].map((p) =>
              p.waitForFunction(
                (infinity) =>
                  infinity ? document.getElementById("infiniteArena").open : __test.phase === "playing",
                infinity,
              ),
            ),
          )
          await send(
            host.p,
            guest.p,
            "Host " + serial,
            label + " " + (infinity ? "Room Infinity" : "fixed") + " receive",
          )
          await send(
            guest.p,
            host.p,
            "Guest " + serial,
            label + " " + (infinity ? "Room Infinity" : "fixed") + " send",
          )
          if (standalone && infinity) {
            await guest.c.setOffline(true)
            await host.p.waitForTimeout(6000)
            await guest.c.setOffline(false)
            await guest.p.waitForFunction(
              () => __test.online.connected && document.getElementById("infiniteStatus").hidden,
            )
            await send(guest.p, host.p, "Reconnect " + serial, label + " Room Infinity reconnect send")
            await send(host.p, guest.p, "Restored " + serial, label + " Room Infinity reconnect receive")
          }
          if (standalone)
            assert(
              await guest.p.evaluate(
                () => navigator.standalone && matchMedia("(display-mode: standalone)").matches,
              ),
            )
          await guest.p.locator("#chatBtn").click()
          await guest.p.screenshot({
            path: path.join(output, label + "-" + (infinity ? "infinity" : "fixed") + ".png"),
          })
          await guest.p.locator("#chatCloseBtn").click()
          assert.equal(errors.length, 0, errors.join("\n"))
          console.log("PASS " + label + " " + (infinity ? "Room Infinity" : "fixed") + " chat")
        } finally {
          await host.c.close()
          await guest.c.close()
        }
      }
  } finally {
    await Promise.all(Object.values(browsers).map((b) => b.close()))
    fs.writeFileSync(
      path.join(output, "report.json"),
      JSON.stringify(
        {
          checks,
          errors,
          standaloneNote:
            "PWA cases use real service workers and simulate standalone display mode; no physical home-screen installation.",
        },
        null,
        2,
      ),
    )
  }
  assert.equal(errors.length, 0)
  console.log(JSON.stringify({ checks: checks.length, errors, output }))
})().catch((e) => {
  console.error(e)
  process.exitCode = 1
})
