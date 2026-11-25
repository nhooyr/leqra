"use strict"
const { functionEnd, sourceIndex } = require("./source_helpers.cjs")
const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  vm = require("node:vm")
const { readFileSync } = require("node:fs"),
  { assetPath } = require("./web_assets.cjs")
const source = readFileSync(assetPath("game.js"), "utf8")

test("FPS uses the fixed canvas corner and the Infinity header, with one shared visibility setting", () => {
  const nodes = new Map(),
    insertions = []
  const $ = (id) => {
    if (!nodes.has(id)) nodes.set(id, {})
    return nodes.get(id)
  }
  const parent = (name) => ({
    insertAdjacentHTML(position, html) {
      insertions.push({ name, position, html })
      const id = html.match(/id="([^"]+)"/)
      if (id) $(id[1])
    },
  })
  const wrap = parent("fixed canvas"),
    header = parent("Infinity status header"),
    stage = parent("Infinity stage")
  nodes.set("infiniteStatusbar", header)
  $("infiniteCanvas").parentElement = stage
  nodes.set("resetAllSettingsBtn", parent("Reset All Settings"))
  const s = {
    $,
    wrap,
    GAME_VERSION: "test",
    combatPrefs: { fps: true, performance: false },
    resetFrameSample() {},
    initMenuPing() {},
    updateSettingsVersion() {},
    resize() {},
    storePerformancePrefs() {},
    document: { addEventListener() {} },
  }
  vm.createContext(s)
  const start = sourceIndex(source, "function initFrameSettings("),
    end = functionEnd(source, start)
  vm.runInContext(source.slice(start, end), s)
  s.initFrameSettings()
  assert.equal(insertions.find((row) => row.html.includes('id="fpsIndicator"')).name, "fixed canvas")
  assert.equal(
    insertions.find((row) => row.html.includes('id="infiniteFPSIndicator"')).name,
    "Infinity status header",
  )
  const performance = insertions.find((row) => row.name === "Reset All Settings")
  assert.equal(performance.position, "beforebegin")
  assert.match(performance.html, /> FPS and ping time<\/label>/)
  const version = insertions.find((row) => row.html.includes('id="settingsVersion"'))
  assert.equal(version.position, "afterend", "The version appears at the bottom, after Reset")
  assert.equal($("fpsIndicator").hidden, false)
  assert.equal($("infiniteFPSIndicator").hidden, false)
  $("showFPS").checked = false
  $("showFPS").onchange()
  assert.equal($("fpsIndicator").hidden, true)
  assert.equal($("infiniteFPSIndicator").hidden, true)
  $("showFPS").checked = true
  $("showFPS").onchange()
  assert.equal($("fpsIndicator").hidden, false)
  assert.equal($("infiniteFPSIndicator").hidden, false)
})

test("Settings footer shows only the current connected room or Infinity server version", () => {
  const label = { textContent: "" }
  const env = {
    GAME_VERSION: "v5.8.2-dev",
    online: { connected: false, serverVersion: "v5.7.0" },
    window: { leqraInfinity: { serverVersion: "" } },
    $: () => label,
  }
  vm.createContext(env)
  for (const name of ["settingsVersionText", "updateSettingsVersion"]) {
    const start = sourceIndex(source, "function " + name + "(")
    vm.runInContext(source.slice(start, functionEnd(source, start)), env)
  }
  env.updateSettingsVersion()
  assert.equal(label.textContent, "leqra v5.8.2-dev")
  env.online.connected = true
  env.updateSettingsVersion()
  assert.equal(label.textContent, "leqra v5.8.2-dev (server v5.7.0)")
  env.window.leqraInfinity.serverVersion = "v9.0.0-dev"
  env.updateSettingsVersion()
  assert.equal(label.textContent, "leqra v5.8.2-dev (server v9.0.0-dev)")
  env.online.connected = false
  env.window.leqraInfinity.serverVersion = ""
  env.updateSettingsVersion()
  assert.equal(label.textContent, "leqra v5.8.2-dev")
})

test("frame readouts label real ping during online play and omit it for offline matches", () => {
  function reading(
    mode,
    phase = "playing",
    measured = true,
    latency = 47,
    surface = "fpsIndicator",
    override,
    tablet = false,
  ) {
    const nodes = new Map(),
      $ = (id) => {
        if (!nodes.has(id)) nodes.set(id, { classList: { toggle() {} } })
        return nodes.get(id)
      }
    const s = {
      $,
      mode,
      phase,
      online: { connected: true, pingMeasured: measured, latency },
      combatPrefs: { fps: true },
      document: { body: { classList: { contains: () => tablet } } },
    }
    vm.createContext(s)
    vm.runInContext(
      source.slice(
        sourceIndex(source, "const frameStats="),
        sourceIndex(source, "function initFrameSettings("),
      ),
      s,
    )
    for (let i = 0; i < 90; i++) {
      const args = [1000 + (i * 1000) / 60, 2, surface]
      if (override) args.push(override.latency)
      s.sampleFrame(...args)
    }
    return $(surface)
  }
  assert.equal(reading("room").textContent, "fps: 60")
  assert.equal(reading("online", "onlineLobby").textContent, "fps: 60, ping: 47 ms")
  const online = reading("online")
  assert.equal(online.textContent, "fps: 60, ping: 47 ms")
  assert.match(online.title, /Browser frame interval: 16\.7 ms/)
  assert.match(online.title, /Network round trip: 47 ms/)
  assert.equal(reading("online", "playing", false).textContent, "fps: 60, ping: —")
  assert.equal(reading("online", "playing", true, 0).textContent, "fps: 60, ping: 0 ms")
  assert.equal(
    reading("room", "menu", false, 0, "infiniteFPSIndicator", { latency: 83 }).textContent,
    "fps: 60, ping: 83 ms",
  )
  assert.equal(
    reading("online", "playing", true, 47, "infiniteFPSIndicator", { latency: null }).textContent,
    "fps: 60",
  )
  assert.equal(
    reading("online", "playing", true, 47, "infiniteFPSIndicator", undefined, true).textContent,
    "fps: 60, 47 ms",
  )
})

test("menu responses and new game ping samples update the HUD without waiting for the FPS interval", () => {
  const nodes = new Map(),
    $ = (id) => {
      if (!nodes.has(id)) nodes.set(id, { classList: { toggle() {} } })
      return nodes.get(id)
    }
  const s = {
    $,
    mode: "room",
    phase: "menu",
    online: {},
    combatPrefs: { fps: true },
    document: { body: { classList: { contains: () => false } } },
  }
  vm.createContext(s)
  vm.runInContext(
    source.slice(
      sourceIndex(source, "const frameStats="),
      sourceIndex(source, "function initFrameSettings("),
    ),
    s,
  )
  s.beginMenuPing()
  s.sampleFrame(100, 0)
  assert.equal($("fpsIndicator").textContent, "fps: —, ping: —")
  s.setMenuPing(23)
  assert.equal($("fpsIndicator").textContent, "fps: —, ping: 23 ms")
  s.sampleFrame(110, 0, "infiniteFPSIndicator", 81)
  assert.equal($("infiniteFPSIndicator").textContent, "fps: —, ping: 81 ms")
  s.sampleFrame(120, 0, "infiniteFPSIndicator", 19)
  assert.equal($("infiniteFPSIndicator").textContent, "fps: —, ping: 19 ms")
})
