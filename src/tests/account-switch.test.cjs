"use strict"
const { extractFunction } = require("./source_helpers.cjs")
const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  vm = require("node:vm"),
  { readFileSync } = require("node:fs"),
  { webcrypto } = require("node:crypto"),
  { assetPath } = require("./web_assets.cjs")
const source = readFileSync(assetPath("game.js"), "utf8")
const foldSource = readFileSync(assetPath("callsigns.js"), "utf8")
  .split("// BEGIN GENERATED CALLSIGN FOLD\n")[1]
  .split("// END GENERATED CALLSIGN FOLD")[0]
function declaration(name) {
  return extractFunction(source, name)
}
const old = "p_" + "A".repeat(43),
  saved = "p_" + "B".repeat(43),
  flush = () => new Promise(setImmediate)
function boot(existing) {
  const storage =
      existing ||
      new Map([
        ["leqra.publicToken", old],
        ["leqra.name", "Alpha"],
      ]),
    requests = [],
    player = { id: 0, name: "Alpha" },
    elements = new Map()
  const s = {
    URL,
    AbortController,
    Uint8Array,
    crypto: webcrypto,
    btoa,
    Array,
    MAX_TANKS: 8,
    mode: "online",
    phase: "playing",
    gameStarted: true,
    scores: [17],
    online: { connected: true },
    localRoom: { self: 0, players: [player] },
    navigator: { onLine: true },
    window: {
      leqraInfinity: {
        close() {
          s.closed = true
        },
      },
    },
    location: { protocol: "https:", href: "https://game.test/" },
    accountImportAllowed: () => s.mode === "room" && !s.online.connected,
    accountSeat: () => 0,
    syncAccountImport() {},
    accountNotice(id, text) {
      s.notice = text
    },
    pendingAccountKeys: () => [],
    renderSavedCallsignAccounts() {},
    confirmGameAction: async (options) => {
      s.confirmation = options
      return s.confirm !== false
    },
    localStorage: {
      getItem: (k) => storage.get(k) || null,
      setItem: (k, v) => storage.set(k, v),
      removeItem: (k) => storage.delete(k),
    },
    setTimeout,
    clearTimeout,
    fetch(url, options) {
      requests.push({ url: String(url), body: JSON.parse(options.body) })
      return new Promise((resolve, reject) => Object.assign(requests.at(-1), { resolve, reject }))
    },
    cleanPilotName: (n) => n.trim(),
    generatedCallsign: () => player.name,
    secondaryMember: () => null,
    rememberCallsign: (name) => {
      player.name = name
      storage.set("leqra.name", name)
    },
    rememberLocalCallsign() {},
    persistLocalRoomRules() {},
    readyRoom() {
      s.phase = "menu"
    },
    syncCallsignEditors() {},
    renderOnlineRoom() {},
    updateHUD() {},
    leaveOnline() {
      s.left = true
      s.mode = "room"
      s.online.connected = false
    },
    $: (id) => {
      if (!elements.has(id)) elements.set(id, { replaceChildren() {}, classList: { toggle() {} } })
      return elements.get(id)
    },
  }
  vm.createContext(s)
  vm.runInContext(foldSource, s)
  s.window.leqraCallsigns = { canonical: s.canonical }
  for (const name of [
    "publicIdentityToken",
    "rememberPublicIdentity",
    "localAccountRegistrationPending",
    "accountKeyValid",
    "fetchAccountInfo",
    "accountNameKey",
    "savedCallsignAccounts",
    "saveCallsignAccount",
    "forgetSavedCallsignAccount",
    "boundCallsignName",
    "rememberCurrentCallsignAccount",
    "newCallsignAccount",
    "claimCallsignAccount",
    "offlineAccountFallback",
    "adoptCallsignAccount",
    "selectCallsignAccount",
    "captureCallsignAccountScope",
    "ensureSelectedCallsignAccounts",
    "clearReleasedAccountReferences",
    "freshReleasedSeat",
    "releaseCallsignAccount",
  ])
    vm.runInContext(declaration(name), s)
  const answer = (request, status, names, score = 0) =>
    request.resolve({
      ok: status === 200,
      status,
      json: async () => ({
        names,
        publicProfile: { name: names[0], score },
        message: "Callsign unavailable",
      }),
    })
  return { s, storage, requests, player, answer }
}
test("new names stage a durable fresh key and only replace the old account after successful claim", async () => {
  const h = boot(),
    p = h.s.selectCallsignAccount(0, "Bravo")
  await flush()
  const r = h.requests[0]
  assert.equal(new URL(r.url).pathname, "/api/account/create")
  assert.notEqual(r.body.publicToken, old)
  assert.equal(JSON.parse(h.storage.get("leqra.accountSwitch.0")).token, r.body.publicToken)
  assert.equal(h.s.publicIdentityToken(), old)
  assert.equal(h.s.left, undefined)
  h.answer(r, 200, ["Bravo"])
  await p
  assert.equal(h.s.publicIdentityToken(), r.body.publicToken)
  assert.equal(h.player.name, "Bravo")
  assert.equal(h.s.left, true)
  assert.deepEqual([...h.s.scores], Array(8).fill(0))
  assert.equal(h.s.savedCallsignAccounts().find((a) => a.name === "Alpha").token, old)
})
test("denied new name and stale success keep the prior key, name and live match", async () => {
  for (const stale of [false, true]) {
    const h = boot()
    let current = true
    const p = h.s.selectCallsignAccount(0, "Bravo", "Alpha", () => current)
    await flush()
    current = !stale
    h.answer(h.requests[0], stale ? 200 : 409, ["Bravo"])
    await assert.rejects(p)
    assert.equal(h.s.publicIdentityToken(), old)
    assert.equal(h.player.name, "Alpha")
    assert.equal(h.s.left, undefined)
  }
})
test("typing a saved callsign signs in with its stored key and keeps its own score", async () => {
  const h = boot()
  h.s.saveCallsignAccount("Bravo", saved)
  const p = h.s.selectCallsignAccount(0, "Bravo")
  await flush()
  assert.deepEqual(h.requests[0].body, { publicToken: saved, signIn: true })
  h.answer(h.requests[0], 200, ["Bravo"], 29)
  await p
  assert.equal(h.s.publicIdentityToken(), saved)
  assert.equal(h.requests.length, 1)
  assert.equal(h.s.savedCallsignAccounts().find((a) => a.name === "Alpha").token, old)
})
test("expired saved account uses a new key only after the callsign is successfully reclaimed", async () => {
  const h = boot()
  h.s.saveCallsignAccount("Bravo", saved)
  const p = h.s.selectCallsignAccount(0, "Bravo")
  await flush()
  h.answer(h.requests[0], 401, ["Bravo"])
  await flush()
  assert.equal(h.requests.length, 2)
  assert.notEqual(h.requests[1].body.publicToken, saved)
  h.answer(h.requests[1], 200, ["Bravo"])
  await p
  assert.equal(h.s.publicIdentityToken(), h.requests[1].body.publicToken)
})
test("same callsign is a no-op and offline new names retain a pending fresh account for later claim", async () => {
  const h = boot()
  await h.s.selectCallsignAccount(0, "ALPHA")
  assert.equal(h.requests.length, 0)
  assert.equal(h.s.publicIdentityToken(), old)
  h.s.navigator.onLine = false
  await h.s.selectCallsignAccount(0, "Bravo")
  assert.notEqual(h.s.publicIdentityToken(), old)
  assert.equal(h.s.savedCallsignAccounts().find((a) => a.name === "Bravo").pending, true)
  h.s.navigator.onLine = true
  const p = h.s.ensureSelectedCallsignAccounts([0])
  await flush()
  h.answer(h.requests[0], 200, ["Bravo"])
  await p
  assert.equal(h.s.savedCallsignAccounts().find((a) => a.name === "Bravo").pending, false)
})

test("pending account retries reuse the durable key after failure and reload", async () => {
  const h = boot()
  let attempt = h.s.selectCallsignAccount(0, "Bravo")
  await flush()
  const candidate = h.requests[0].body.publicToken
  h.requests[0].reject(Error("Lost response"))
  await assert.rejects(attempt)
  const reloaded = boot(h.storage)
  attempt = reloaded.s.selectCallsignAccount(0, "Bravo")
  await flush()
  assert.equal(reloaded.requests[0].body.publicToken, candidate)
  reloaded.answer(reloaded.requests[0], 200, ["Bravo"])
  await attempt
  assert.equal(reloaded.s.publicIdentityToken(), candidate)
  assert.equal(reloaded.s.savedCallsignAccounts().find((a) => a.name === "Alpha").token, old)
  const anotherOrigin = boot()
  assert.equal(
    anotherOrigin.s.savedCallsignAccounts().some((a) => a.name === "Bravo"),
    false,
    "browser-origin storage isolates the account history",
  )
})
test("an offline pending saved account is claimed using its same key before selection", async () => {
  const h = boot()
  h.s.saveCallsignAccount("Bravo", saved, true)
  const p = h.s.selectCallsignAccount(0, "Bravo")
  await flush()
  assert.equal(new URL(h.requests[0].url).pathname, "/api/account/create")
  assert.equal(h.requests[0].body.publicToken, saved)
  h.answer(h.requests[0], 200, ["Bravo"])
  await p
  assert.equal(h.s.publicIdentityToken(), saved)
})
test("offline room callsign changes survive unavailable servers with a durable pending key", async () => {
  for (const status of [0, 503]) {
    const h = boot()
    h.s.mode = "room"
    h.s.online.connected = false
    const pending = h.s.selectCallsignAccount(0, "Bravo")
    await flush()
    const key = h.requests[0].body.publicToken
    if (status) h.answer(h.requests[0], status, [])
    else h.requests[0].reject(TypeError("Network unavailable"))
    await pending
    assert.equal(h.player.name, "Bravo")
    assert.equal(h.s.publicIdentityToken(), key)
    assert.equal(h.s.savedCallsignAccounts().find((a) => a.name === "Bravo").pending, true)
  }
})
test("offline fallback never accepts rejected or unauthorized claims", async () => {
  for (const status of [400, 401, 403, 409, 429]) {
    const h = boot()
    h.s.mode = "room"
    h.s.online.connected = false
    const pending = h.s.selectCallsignAccount(0, "Bravo")
    await flush()
    h.answer(h.requests[0], status, [])
    await assert.rejects(pending)
    assert.equal(h.s.publicIdentityToken(), old)
    assert.equal(h.player.name, "Alpha")
  }
  const h = boot()
  h.s.mode = "room"
  h.s.online.connected = false
  const pending = h.s.selectCallsignAccount(0, "Bravo")
  await flush()
  h.answer(h.requests[0], 200, ["Unexpected"])
  await assert.rejects(pending)
  assert.equal(h.s.publicIdentityToken(), old)
})

test("starting online checks only the participating saved accounts and replaces expired keys", async () => {
  const h = boot()
  h.s.saveCallsignAccount("Alpha", old)
  h.s.saveCallsignAccount("Bravo", saved)
  h.storage.set("leqra.localPublicToken", saved)
  const p = h.s.ensureSelectedCallsignAccounts([0])
  await flush()
  assert.deepEqual(h.requests[0].body, { publicToken: old, signIn: true })
  h.answer(h.requests[0], 401, ["Alpha"])
  await flush()
  assert.equal(h.requests.length, 2)
  assert.notEqual(h.requests[1].body.publicToken, old)
  h.answer(h.requests[1], 200, ["Alpha"])
  await p
  assert.equal(h.s.publicIdentityToken(), h.requests[1].body.publicToken)
  assert.equal(
    h.s.savedCallsignAccounts().some((a) => a.token === old),
    false,
  )
  assert.equal(h.s.publicIdentityToken(1), saved)
})

test("releasing a saved callsign confirms deletion, then removes only its key after server acknowledgement", async () => {
  const h = boot()
  h.s.mode = "room"
  h.s.online.connected = false
  h.s.saveCallsignAccount("Bravo", saved)
  const p = h.s.releaseCallsignAccount(saved, "Bravo")
  await flush()
  assert.match(h.s.confirmation.message, /permanently deletes Bravo’s score/)
  assert.equal(new URL(h.requests[0].url).pathname, "/api/account/release")
  assert.deepEqual(h.requests[0].body, { publicToken: saved })
  assert.equal(h.s.savedCallsignAccounts().length, 1)
  h.requests[0].resolve({ ok: true, json: async () => ({ released: true }) })
  assert.equal(await p, true)
  assert.equal(h.s.savedCallsignAccounts().length, 0)
  assert.equal(h.s.publicIdentityToken(), old)
  assert.equal(h.player.name, "Alpha")
})
test("release cancellation and backend failure preserve credentials and current identity", async () => {
  const h = boot()
  h.s.mode = "room"
  h.s.online.connected = false
  h.s.saveCallsignAccount("Alpha", old)
  h.s.confirm = false
  assert.equal(await h.s.releaseCallsignAccount(old, "Alpha"), false)
  assert.equal(h.requests.length, 0)
  h.s.confirm = true
  const p = h.s.releaseCallsignAccount(old, "Alpha")
  await flush()
  h.requests[0].resolve({ ok: false, status: 503, json: async () => ({}) })
  assert.equal(await p, false)
  assert.equal(h.s.publicIdentityToken(), old)
  assert.equal(h.player.name, "Alpha")
  assert.equal(h.s.savedCallsignAccounts()[0].token, old)
})
test("releasing the current account gives only that seat a fresh local name and clears matching pending references", async () => {
  const h = boot()
  h.s.mode = "room"
  h.s.online.connected = false
  h.storage.set("leqra.localPublicToken", saved)
  h.s.saveCallsignAccount("Alpha", old)
  h.s.saveCallsignAccount("Bravo", saved)
  h.storage.set("leqra.accountSwitch.0", JSON.stringify({ token: old, previous: saved }))
  h.storage.set("leqra.autoCallsign.0", JSON.stringify({ owner: old, name: "Alpha" }))
  const p = h.s.releaseCallsignAccount(old, "Alpha")
  await flush()
  h.requests[0].resolve({ ok: true, json: async () => ({ released: true }) })
  assert.equal(await p, true)
  assert.equal(h.s.publicIdentityToken(), "")
  assert.match(h.player.name, /^pilot#/)
  assert.equal(h.s.publicIdentityToken(1), saved)
  assert.equal(h.s.savedCallsignAccounts().length, 1)
  assert.equal(h.storage.has("leqra.accountSwitch.0"), false)
  assert.equal(h.storage.has("leqra.autoCallsign.0"), false)
})

test("released current account can play again with a new durable key, while other recovery candidates survive", async () => {
  const h = boot()
  h.s.mode = "room"
  h.s.online.connected = false
  h.s.saveCallsignAccount("Alpha", old)
  h.storage.set("leqra.accountSwitch.0", JSON.stringify({ token: saved, previous: old, name: "Bravo" }))
  const p = h.s.releaseCallsignAccount(old, "Alpha")
  await flush()
  h.requests[0].resolve({ ok: true, json: async () => ({ released: true }) })
  await p
  assert.equal(h.s.savedCallsignAccounts().find((a) => a.name === "Bravo").token, saved)
  const play = h.s.ensureSelectedCallsignAccounts([0])
  await flush()
  const request = h.requests[1]
  assert.equal(new URL(request.url).pathname, "/api/account/create")
  assert.notEqual(request.body.publicToken, old)
  assert.equal(JSON.parse(h.storage.get("leqra.accountSwitch.0")).token, request.body.publicToken)
  h.answer(request, 200, [request.body.name])
  await play
  assert.equal(h.s.publicIdentityToken(), request.body.publicToken)
})

test("starting play makes a pending callsign response stale without interrupting the new match", async () => {
  for (const status of [200, 503]) {
    const h = boot()
    h.s.mode = "room"
    h.s.phase = "menu"
    h.s.gameStarted = false
    h.s.online.connected = false
    const pending = h.s.selectCallsignAccount(0, "Bravo")
    await flush()
    const candidate = h.requests[0].body.publicToken
    h.s.phase = "countdown"
    h.s.gameStarted = true
    h.s.localRoom.countdownSerial = 1
    h.answer(h.requests[0], status, ["Bravo"])
    await assert.rejects(pending)
    assert.equal(h.s.phase, "countdown")
    assert.equal(h.s.gameStarted, true)
    assert.equal(h.s.publicIdentityToken(), old)
    assert.equal(h.player.name, "Alpha")
    assert.equal(h.s.closed, undefined)
    if (status === 200)
      assert.equal(
        h.s.savedCallsignAccounts().find((a) => a.name === "Bravo").token,
        candidate,
        "a confirmed unused account remains recoverable",
      )
    else
      assert.equal(
        JSON.parse(h.storage.get("leqra.accountSwitch.0")).token,
        candidate,
        "the unconfirmed candidate remains recoverable",
      )
  }
})

test("late account preflight cannot replace a new game and keeps a confirmed replacement recoverable", async () => {
  for (const afterExpiry of [false, true]) {
    const h = boot()
    h.s.mode = "room"
    h.s.phase = "menu"
    h.s.gameStarted = false
    h.s.online.connected = false
    h.s.saveCallsignAccount("Alpha", old)
    const pending = h.s.ensureSelectedCallsignAccounts([0])
    await flush()
    if (afterExpiry) {
      h.answer(h.requests[0], 401, ["Alpha"])
      await flush()
    }
    h.s.phase = "countdown"
    h.s.gameStarted = true
    h.s.localRoom.countdownSerial = 1
    const request = h.requests.at(-1)
    h.answer(request, afterExpiry ? 200 : 401, ["Alpha"])
    await assert.rejects(pending, /selection changed/)
    assert.equal(h.s.phase, "countdown")
    assert.equal(h.s.gameStarted, true)
    assert.equal(h.s.publicIdentityToken(), old)
    assert.equal(h.s.closed, undefined)
    if (afterExpiry)
      assert.equal(
        h.s.savedCallsignAccounts().find((a) => a.token === request.body.publicToken).pending,
        false,
        "confirmed replacement remains recoverable",
      )
    else assert.equal(h.requests.length, 1, "stale expiry cannot start another account request")
  }
})

test("a release beginning during account preflight invalidates the pending game entry", async () => {
  for (const ok of [true, false]) {
    const h = boot()
    h.s.mode = "room"
    h.s.phase = "menu"
    h.s.gameStarted = false
    h.s.online.connected = false
    h.s.saveCallsignAccount("Alpha", old)
    const pending = h.s.ensureSelectedCallsignAccounts([0])
    await flush()
    const release = h.s.releaseCallsignAccount(old, "Alpha")
    await flush()
    assert.ok(h.s.$("accountDialog").accountReleaseRequest)
    h.answer(h.requests[0], 200, ["Alpha"])
    await assert.rejects(pending, /selection changed/)
    assert.equal(h.s.publicIdentityToken(), old)
    assert.equal(h.s.closed, undefined)
    h.requests[1].resolve({ ok, status: ok ? 200 : 503, json: async () => (ok ? { released: true } : {}) })
    await release
    assert.equal(h.s.$("accountDialog").accountReleaseRequest, undefined)
  }
})

test("concurrent local seats cannot adopt the same saved account after asynchronous confirmation", async () => {
  const h = boot(),
    third = "p_" + "C".repeat(43)
  h.s.mode = "room"
  h.s.phase = "menu"
  h.s.gameStarted = false
  h.s.online.connected = false
  h.storage.set("leqra.localPublicToken", saved)
  h.storage.set("leqra.local2Name", "Beta")
  h.s.saveCallsignAccount("Gamma", third)
  const first = h.s.selectCallsignAccount(0, "Gamma"),
    second = h.s.selectCallsignAccount(1, "Gamma", "Beta")
  await flush()
  h.answer(h.requests[0], 200, ["Gamma"])
  await first
  h.answer(h.requests[1], 200, ["Gamma"])
  await assert.rejects(second, /separate accounts/)
  assert.equal(h.s.publicIdentityToken(), third)
  assert.equal(h.s.publicIdentityToken(1), saved)
  assert.equal(h.s.savedCallsignAccounts().find((a) => a.name === "Gamma").token, third)
})

test("Unicode-equivalent saved callsigns reuse their authenticated account", async () => {
  const h = boot()
  h.s.saveCallsignAccount("Σnow", saved)
  const pending = h.s.selectCallsignAccount(0, "ςNOW")
  await flush()
  assert.deepEqual(h.requests[0].body, { publicToken: saved, signIn: true })
  h.answer(h.requests[0], 200, ["Σnow"], 41)
  await pending
  assert.equal(h.s.publicIdentityToken(), saved)
  assert.equal(h.player.name, "Σnow")
})

test("distinct sharp-s and dotless-I callsigns never borrow another saved key", async () => {
  for (const [stored, requested] of [
    ["ß", "SS"],
    ["ı", "i"],
  ]) {
    const h = boot()
    h.s.saveCallsignAccount(stored, saved)
    const pending = h.s.selectCallsignAccount(0, requested)
    await flush()
    assert.equal(new URL(h.requests[0].url).pathname, "/api/account/create")
    assert.notEqual(h.requests[0].body.publicToken, saved)
    h.answer(h.requests[0], 200, [requested])
    await pending
    assert.notEqual(h.s.publicIdentityToken(), saved)
  }
})

test("a pending release blocks starting another game and releases that gate on success or failure", async () => {
  for (const ok of [true, false]) {
    const h = boot()
    h.s.mode = "room"
    h.s.phase = "menu"
    h.s.online.connected = false
    h.s.saveCallsignAccount("Alpha", old)
    h.s.document = { getElementById: h.s.$ }
    h.s.window.leqraCallsigns.reserved = () => false
    vm.runInContext(declaration("roomStartError"), h.s)
    const room = { rules: { infinity: true }, players: [{ kind: "human", name: "Alpha" }] }
    const release = h.s.releaseCallsignAccount(old, "Alpha")
    await flush()
    assert.equal(h.s.roomStartError(room), "Finish releasing the callsign before starting a game.")
    assert.throws(() => h.s.adoptCallsignAccount(0, "Bravo", saved, old), /Finish releasing/)
    assert.equal(h.s.publicIdentityToken(), old)
    vm.runInContext(declaration("connectOnline"), h.s)
    h.s.online.publishing = true
    h.s.connectOnline({})
    assert.equal(h.s.online.publishing, false)
    h.requests[0].resolve({ ok, status: ok ? 200 : 503, json: async () => (ok ? { released: true } : {}) })
    await release
    assert.equal(h.s.roomStartError(room), "")
  }
})
