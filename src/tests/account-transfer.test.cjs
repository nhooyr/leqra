"use strict"
const { extractFunction, sourceIndex } = require("./source_helpers.cjs")
const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  vm = require("node:vm"),
  fs = require("node:fs")
const { assetPath } = require("./web_assets.cjs"),
  { webcrypto } = require("node:crypto")
const source = fs.readFileSync(assetPath("game.js"), "utf8"),
  key = "p_" + "A".repeat(43),
  oldKey = "p_" + "B".repeat(43)
function declaration(name) {
  return extractFunction(source, name)
}
function boot() {
  const nodes = new Map(),
    storage = new Map([["leqra.publicToken", oldKey]]),
    requests = [],
    timers = new Map()
  let serial = 0
  class Node {
    value = ""
    textContent = ""
    dataset = {}
    hidden = false
    disabled = false
    open = false
    type = "password"
    checked = false
    children = []
    lastChild = { textContent: "" }
    classList = {
      toggle(name, on) {
        this[name] = on
      },
    }
    replaceChildren(...children) {
      this.children = [...children]
      this.value = ""
    }
    append(...children) {
      this.children.push(...children)
      if (this.children.length === children.length) this.value = children[0]?.value || ""
    }
    setAttribute(name, value) {
      this[name] = value
    }
    focus() {
      this.focused = true
    }
    select() {
      this.selected = true
    }
  }
  const $ = (id) => {
    if (!nodes.has(id)) nodes.set(id, new Node())
    return nodes.get(id)
  }
  $("accountDialog").open = true
  const primary = { id: 0, kind: "human", name: "OLD" },
    local = { id: 1, kind: "local", owner: 0, name: "OLD WING" }
  const s = {
    $,
    URL,
    AbortController,
    Set,
    Uint8Array,
    btoa,
    crypto: webcrypto,
    confirmGameAction: async () => true,
    mode: "room",
    phase: "menu",
    online: { connected: false, connecting: false },
    localRoom: { self: 0, players: [primary, local] },
    document: { createElement: () => new Node() },
    location: { href: "https://leqra.test/" },
    navigator: { clipboard: { writeText: async () => {} } },
    localStorage: {
      get length() {
        return storage.size
      },
      key: (index) => [...storage.keys()][index],
      getItem: (key) => storage.get(key),
      setItem: (key, value) => storage.set(key, value),
      removeItem: (key) => storage.delete(key),
    },
    setTimeout(fn) {
      timers.set(++serial, fn)
      return serial
    },
    clearTimeout: (id) => timers.delete(id),
    fetch(url, request) {
      return new Promise((resolve, reject) => requests.push({ url, request, resolve, reject }))
    },
    generatedCallsign: (seat) => (seat ? local.name : primary.name),
    secondaryMember: () => local,
    rememberCallsign: (name) => {
      $("pilotName").value = name
    },
    rememberLocalCallsign: (name) => {
      s.localName = name
    },
    persistLocalRoomRules() {
      s.persisted = true
    },
    syncCallsignEditors() {
      s.synced = true
    },
    renderOnlineRoom() {
      s.rendered = true
    },
    updateHUD() {},
    callsignForms: () => [],
    scheduleCallsignAvailability() {},
    openFeature() {},
  }
  vm.createContext(s)
  for (const name of [
    "publicIdentityToken",
    "rememberPublicIdentity",
    "cleanPilotName",
    "prepareLocalAccount",
    "localAccountRegistrationPending",
    "accountNameKey",
    "savedCallsignAccounts",
    "saveCallsignAccount",
    "forgetSavedCallsignAccount",
    "boundCallsignName",
    "rememberCurrentCallsignAccount",
    "renderSavedCallsignAccounts",
    "accountScoreLabel",
    "loadSavedCallsignScores",
    "accountSeat",
    "accountStorageKey",
    "accountImportAllowed",
    "accountNotice",
    "accountKeyValid",
    "fetchAccountInfo",
    "renderAccountInfo",
    "clearAccountImport",
    "syncAccountImport",
    "openAccount",
    "copyAccountKey",
    "checkImportedAccount",
    "showAccountImportReview",
    "pendingAccountKeys",
    "savePendingAccountKey",
    "clearPendingAccountKeys",
    "completeAccountReset",
    "resolvePendingAccountKeys",
    "rotateAccountKey",
    "forgetRevokedAccount",
    "useImportedAccount",
  ])
    vm.runInContext(declaration(name), s)
  return { s, $, requests, storage, primary, local }
}
const info = {
  names: ["SAVED", "WING"],
  totalNames: 2,
  publicProfile: { name: "SAVED", score: 17, localName: "WING", localScore: 9 },
}

test("saved callsign selection disables both in-use keys and follows the selected account", () => {
  const { s, $, storage } = boot(),
    unusedKey = "p_" + "C".repeat(43)
  storage.set("leqra.localPublicToken", key)
  s.saveCallsignAccount("OLD", oldKey)
  s.saveCallsignAccount("WING", key)
  s.saveCallsignAccount("SAVED", unusedKey)
  const actions = () =>
    Object.fromEntries(
      $("accountSavedAccounts").children.map((row) => [row.children[0].textContent, row.children]),
    )
  for (const seat of [0, 1]) {
    $("accountDialog").dataset.accountSeat = String(seat)
    s.renderSavedCallsignAccounts()
    const rows = actions()
    assert.equal(rows.OLD[0].disabled, true, "P1 in-use key cannot be selected again")
    assert.equal(rows.WING[0].disabled, true, "P2 in-use key cannot be selected again")
    assert.equal(rows.SAVED[0].disabled, false, "unused saved key remains selectable")
    assert.equal(rows.OLD[1].disabled, false, "disabling selection preserves explicit release")
  }
  s.rememberPublicIdentity(unusedKey, undefined, 1)
  s.renderSavedCallsignAccounts()
  assert.equal(actions().WING[0].disabled, false, "previous account becomes selectable")
  assert.equal(actions().SAVED[0].disabled, true, "newly active account becomes disabled")
  $("accountDialog").accountReleaseRequest = {}
  s.renderSavedCallsignAccounts()
  assert.ok(
    Object.values(actions()).every(([use, release]) => use.disabled && release.disabled),
    "release in progress disables all account actions",
  )
})

test("saved callsign scores load independently without signing in and failures never display zero", async () => {
  const { s, $, requests } = boot(),
    third = "p_" + "C".repeat(43),
    fourth = "p_" + "D".repeat(43),
    fifth = "p_" + "E".repeat(43)
  s.saveCallsignAccount("OLD", oldKey)
  s.saveCallsignAccount("SAVED", key)
  s.saveCallsignAccount("THIRD", third)
  s.saveCallsignAccount("FOURTH", fourth)
  s.saveCallsignAccount("STALE", fifth)
  $("accountDialog").accountSavedScores = new Map()
  s.loadSavedCallsignScores(oldKey)
  s.renderSavedCallsignAccounts()
  assert.equal(requests.length, 2, "score lookups are bounded")
  assert.deepEqual(
    requests.map((r) => JSON.parse(r.request.body)),
    [{ publicToken: key }, { publicToken: third }],
  )
  requests[1].resolve(response({ names: ["THIRD"], publicProfile: { name: "THIRD", score: 0 } }))
  await flush()
  assert.equal(requests.length, 3)
  requests[0].resolve(response({ names: ["SAVED"], publicProfile: { name: "SAVED", score: 42 } }))
  requests[2].resolve(response({}, 401))
  await flush()
  requests[3].resolve(response({ names: ["RENAMED"], publicProfile: { name: "RENAMED", score: 99 } }))
  await flush()
  const rows = Object.fromEntries(
    $("accountSavedAccounts").children.map((row) => [
      row.children[0].textContent,
      row.children[2].textContent,
    ]),
  )
  assert.equal(rows.SAVED, "Score: 42")
  assert.equal(rows.THIRD, "Score: 0")
  assert.equal(rows.FOURTH, "Score unavailable")
  assert.equal(rows.STALE, "Score unavailable", "a stale label must not show another callsign’s score")
  assert.equal(rows.OLD, "Loading score…", "current score uses the existing current-account request")
  assert.equal(s.publicIdentityToken(), oldKey)
})

test("a server-confirmed new callsign starts at zero before its first public game", () => {
  const { s } = boot()
  assert.equal(s.accountScoreLabel({ names: ["Fresh"] }, "fresh"), "Score: 0")
  assert.equal(s.accountScoreLabel({ names: ["Fresh"] }), "Score: 0")
  assert.equal(s.accountScoreLabel({ names: ["Fresh"] }, "Other"), "Score unavailable")
  assert.equal(s.accountScoreLabel({ names: [] }, "Fresh"), "Score unavailable")
  assert.equal(
    s.accountScoreLabel({ names: ["Fresh"], publicProfile: { name: "Other", score: 15 } }, "Fresh"),
    "Score unavailable",
  )
})

test("stale saved-score replies cannot overwrite a reopened account menu", async () => {
  const { s, $, requests } = boot()
  s.saveCallsignAccount("SAVED", key)
  const dialog = $("accountDialog")
  dialog.accountSavedScores = new Map()
  s.loadSavedCallsignScores(oldKey)
  const old = requests[0]
  dialog.accountSavedScores = new Map()
  s.loadSavedCallsignScores(oldKey)
  assert.equal(old.request.signal.aborted, true)
  old.resolve(response({ names: ["SAVED"], publicProfile: { name: "SAVED", score: 99 } }))
  await flush()
  assert.equal(dialog.accountSavedScores.has(key), false)
  requests[1].resolve(response({ names: ["SAVED"], publicProfile: { name: "SAVED", score: 7 } }))
  await flush()
  assert.equal(dialog.accountSavedScores.get(key), "Score: 7")
})

test("P1-only room welcomes preserve the pending P2 key until P2 is acknowledged", () => {
  for (const localPublicToken of [undefined, ""]) {
    const { s, storage } = boot(),
      candidate = s.prepareLocalAccount().localPublicToken
    storage.set("leqra.local2Name", "pilot#TEST42")
    s.window = { leqraIdentity: { remember: s.rememberPublicIdentity } }
    s.request = { publicToken: oldKey, localPublicToken: candidate }
    s.msg = { publicToken: oldKey, localPublicToken }
    const start = sourceIndex(source, "   window.leqraIdentity?.remember?.(msg.publicToken"),
      end = sourceIndex(source, "\n   matchmakingWelcome", start),
      welcomeIdentity = source.slice(start, end)
    assert.ok(start >= 0 && end > start, "actual room welcome identity handler")
    vm.runInContext(welcomeIdentity, s)
    assert.equal(s.publicIdentityToken(1), candidate)
    assert.equal(JSON.parse(storage.get("leqra.localAccountRegistration")).token, candidate)
    assert.equal(storage.get("leqra.local2Name"), "pilot#TEST42")
    const reloaded = boot()
    for (const [key, value] of storage) reloaded.storage.set(key, value)
    assert.equal(
      reloaded.s.prepareLocalAccount().localPublicToken,
      candidate,
      "reload keeps ownership of the generated name",
    )
    assert.equal(reloaded.s.prepareLocalAccount().localNewAccount, true)
    s.msg.localPublicToken = candidate
    vm.runInContext(welcomeIdentity, s)
    assert.equal(storage.get("leqra.localPublicToken"), candidate)
    assert.equal(
      storage.has("leqra.localAccountRegistration"),
      false,
      "only the real P2 acknowledgement completes registration",
    )
  }
})

test("invalid and unverified account keys never replace the current account", async () => {
  const { s, $, requests } = boot()
  $("accountImportKey").value = "bad"
  await s.checkImportedAccount()
  assert.equal(requests.length, 0)
  assert.equal(s.publicIdentityToken(), oldKey)
  assert.match($("accountImportNotice").textContent, /complete account key/)
  $("accountImportKey").value = key
  const pending = s.checkImportedAccount()
  assert.equal(s.publicIdentityToken(), oldKey)
  assert.equal($("accountUseBtn").disabled, true)
  requests[0].resolve({ ok: false, status: 401, json: async () => ({ message: key }) })
  await pending
  assert.equal(s.publicIdentityToken(), oldKey)
  assert.equal($("accountImportNotice").textContent, "That account key is invalid or unavailable.")
  assert.ok(!$("accountImportNotice").textContent.includes(key), "server error text must not leak a bearer")
})

test("checking a key only previews; explicit offline import restores chosen callsigns", async () => {
  const { s, $, requests, primary, local } = boot()
  $("accountImportKey").value = key
  const pending = s.checkImportedAccount()
  const request = requests[0]
  assert.equal(new URL(request.url).pathname, "/api/account")
  assert.deepEqual(JSON.parse(request.request.body), { publicToken: key })
  assert.ok(!String(request.url).includes(key))
  request.resolve({ ok: true, status: 200, json: async () => info })
  await pending
  assert.equal(s.publicIdentityToken(), oldKey)
  assert.equal(primary.name, "OLD")
  assert.equal(local.name, "OLD WING")
  assert.equal($("accountImportReview").hidden, false)
  assert.equal($("accountImportName").value, "SAVED")
  assert.equal($("accountImportName").disabled, true)
  assert.equal($("accountImportName").children.length, 1, "legacy aliases are not selectable")
  s.openAccount = () => {}
  const use = s.useImportedAccount()
  requests.at(-1).resolve(response({ names: [$("accountImportName").value] }))
  await use
  assert.equal(s.publicIdentityToken(), key)
  assert.equal(primary.name, "SAVED")
  assert.equal(local.name, "OLD WING", "importing P1 never changes P2")
  assert.equal(s.persisted, true)
  assert.equal(s.synced, true)
  assert.equal(s.rendered, true)
  assert.equal(primary.score, undefined, "scores remain server-owned")
})

test("joining online or changing identity while a key check runs prevents replacement", async () => {
  for (const change of ["online", "owner", "draft"]) {
    const { s, $, requests } = boot()
    $("accountImportKey").value = key
    const pending = s.checkImportedAccount()
    if (change === "online") s.online.connected = true
    else if (change === "owner") s.rememberPublicIdentity("p_" + "C".repeat(43))
    else $("accountImportKey").value = "p_" + "D".repeat(43)
    requests[0].resolve({ ok: true, status: 200, json: async () => info })
    await pending
    assert.notEqual(s.publicIdentityToken(), key, change)
    assert.equal($("accountImportReview").hidden, true, change)
  }
})

test("commit refuses a key checked for a previous roster or online session", async () => {
  for (const change of ["online", "roster"]) {
    const { s, $, requests } = boot()
    $("accountImportKey").value = key
    const pending = s.checkImportedAccount()
    requests[0].resolve({ ok: true, status: 200, json: async () => info })
    await pending
    if (change === "online") s.online.connecting = true
    else s.localRoom.players = [...s.localRoom.players]
    s.useImportedAccount()
    assert.equal(s.publicIdentityToken(), oldKey, change)
    assert.match($("accountImportNotice").textContent, /Check the key again/)
  }
})

test("account copy uses an explicit clipboard action and reveals only as its fallback", async () => {
  const { s, $ } = boot(),
    copied = []
  s.navigator.clipboard.writeText = async (value) => copied.push(value)
  await s.copyAccountKey()
  assert.deepEqual(copied, [oldKey])
  assert.equal($("accountKey").type, "password")
  s.navigator.clipboard.writeText = async () => {
    throw Error("unavailable")
  }
  await s.copyAccountKey()
  assert.equal($("accountKey").type, "text")
  assert.equal($("accountKey").value, oldKey)
  assert.equal($("accountKey").selected, true)
})

test("account import is unavailable in online rooms and active local games", () => {
  const { s, $ } = boot()
  assert.equal(s.accountImportAllowed(), true)
  for (const phase of ["playing", "paused", "countdown"]) {
    s.phase = phase
    assert.equal(s.accountImportAllowed(), false, phase)
  }
  s.phase = "menu"
  s.mode = "online"
  s.online.code = "ROOM"
  assert.equal(s.accountImportAllowed(), false)
  s.mode = "room"
  s.online.code = ""
  $("infiniteArena").open = true
  assert.equal(s.accountImportAllowed(), false)
})

const flush = () => new Promise((resolve) => setImmediate(resolve))
const response = (data = info, status = 200) => ({ ok: status === 200, status, json: async () => data })

test("reset persists a CSPRNG replacement before HTTP and exposes it only after acknowledgement", async () => {
  const { s, $, requests, storage } = boot(),
    task = s.rotateAccountKey()
  await flush()
  assert.equal(requests.length, 1)
  assert.equal(s.publicIdentityToken(), oldKey)
  const request = requests[0],
    body = JSON.parse(request.request.body),
    records = s.pendingAccountKeys()
  assert.equal(records.length, 1)
  assert.equal(body.publicToken, oldKey)
  assert.equal(body.newPublicToken, records[0].replacement)
  assert.ok(s.accountKeyValid(body.newPublicToken))
  assert.notEqual(body.newPublicToken, oldKey)
  assert.ok(!String(request.url).includes(body.newPublicToken))
  request.resolve(response({ ...info, publicToken: body.newPublicToken }))
  await task
  assert.equal(s.publicIdentityToken(), body.newPublicToken)
  assert.equal(s.pendingAccountKeys().length, 0)
  assert.equal($("accountKey").value, body.newPublicToken)
  assert.equal($("accountKey").type, "password")
  const copied = []
  s.navigator.clipboard.writeText = async (value) => copied.push(value)
  await s.copyAccountKey()
  assert.deepEqual(copied, [body.newPublicToken])
  assert.equal(storage.get("leqra.publicToken"), body.newPublicToken)
})

test("a rejected key reset retains its candidate and retries that same replacement", async () => {
  const { s, requests } = boot(),
    task = s.rotateAccountKey()
  await flush()
  requests[0].resolve(response({}, 500))
  await flush()
  assert.equal(requests.length, 2)
  requests[1].resolve(response({ code: "account_key_invalid" }, 401))
  await flush()
  assert.equal(requests.length, 3)
  requests[2].resolve(response())
  await task
  assert.equal(s.publicIdentityToken(), oldKey)
  assert.equal(s.pendingAccountKeys().length, 1)
  const candidate = s.pendingAccountKeys()[0].replacement
  const retry = s.rotateAccountKey()
  await flush()
  assert.equal(JSON.parse(requests[3].request.body).newPublicToken, candidate)
  requests[3].resolve(response({ ...info, publicToken: candidate }))
  await retry
  assert.equal(s.publicIdentityToken(), candidate)
  assert.equal(s.pendingAccountKeys().length, 0)
})

test("a lost reset response recovers the durable candidate instead of losing the account", async () => {
  const { s, requests } = boot(),
    task = s.rotateAccountKey()
  await flush()
  const candidate = s.pendingAccountKeys()[0].replacement
  requests[0].reject(Error("connection lost"))
  await flush()
  requests[1].resolve(response())
  await task
  assert.equal(s.publicIdentityToken(), candidate)
  assert.equal(s.pendingAccountKeys().length, 0)
})

test("an ambiguous reset keeps its candidate and a later account opening recovers it", async () => {
  const { s, requests } = boot(),
    task = s.rotateAccountKey()
  await flush()
  const candidate = s.pendingAccountKeys()[0].replacement
  requests[0].reject(Error("offline"))
  await flush()
  requests[1].reject(Error("offline"))
  await task
  assert.equal(s.publicIdentityToken(), oldKey)
  assert.equal(s.pendingAccountKeys()[0].replacement, candidate)
  const recovery = s.resolvePendingAccountKeys()
  requests[2].resolve(response())
  await recovery
  assert.equal(s.publicIdentityToken(), candidate)
  assert.equal(s.pendingAccountKeys().length, 0)
})

test("racing tab candidates cannot overwrite each other and recovery selects the committed winner", async () => {
  const { s, requests } = boot(),
    first = s.savePendingAccountKey(oldKey),
    second = s.savePendingAccountKey(oldKey)
  assert.notEqual(first.storageKey, second.storageKey)
  assert.notEqual(first.replacement, second.replacement)
  assert.equal(s.pendingAccountKeys().length, 2)
  const task = s.resolvePendingAccountKeys()
  requests[0].resolve(response({ code: "account_key_invalid" }, 401))
  requests[1].resolve(response())
  await task
  assert.equal(s.publicIdentityToken(), second.replacement)
  assert.equal(s.pendingAccountKeys().length, 0)
})

test("a recovered key never silently replaces a different currently selected account", async () => {
  const { s, $, requests } = boot(),
    record = s.savePendingAccountKey(oldKey),
    other = "p_" + "C".repeat(43)
  s.rememberPublicIdentity(other)
  const task = s.resolvePendingAccountKeys()
  requests[0].resolve(response())
  await task
  assert.equal(s.publicIdentityToken(), other)
  assert.equal($("accountImportReview").hidden, false)
  assert.equal($("accountImportKey").value, record.replacement)
  assert.equal(s.pendingAccountKeys().length, 1)
})

test("storage refusal prevents reset requests and late revocation cannot clear a newer key", async () => {
  const { s, requests } = boot()
  s.localStorage.setItem = () => {
    throw Error("disabled")
  }
  await s.rotateAccountKey()
  assert.equal(requests.length, 0)
  assert.equal(s.publicIdentityToken(), oldKey)
  s.rememberPublicIdentity(key)
  s.forgetRevokedAccount(oldKey)
  assert.equal(s.publicIdentityToken(), key)
  s.forgetRevokedAccount(key)
  assert.equal(s.publicIdentityToken(), "")
})

test("a completed reset retains its recovery record if saving the active key fails", async () => {
  const { s, requests, storage } = boot(),
    original = s.localStorage.setItem
  const task = s.rotateAccountKey()
  await flush()
  const candidate = s.pendingAccountKeys()[0].replacement
  s.localStorage.setItem = (key, value) => {
    if (key === "leqra.publicToken") throw Error("denied")
    original(key, value)
  }
  requests[0].resolve(response({ ...info, publicToken: candidate }))
  await task
  assert.equal(s.publicIdentityToken(), candidate)
  assert.equal(storage.get("leqra.publicToken"), oldKey)
  assert.equal(s.pendingAccountKeys().length, 1)
  s.localStorage.setItem = original
  const recovery = s.resolvePendingAccountKeys()
  requests[1].resolve(response())
  await recovery
  assert.equal(storage.get("leqra.publicToken"), candidate)
  assert.equal(s.pendingAccountKeys().length, 0)
})

test("recovery checks a candidate again after learning that its previous key was revoked", async () => {
  const { s, requests } = boot(),
    record = s.savePendingAccountKey(oldKey),
    task = s.resolvePendingAccountKeys()
  requests[0].resolve(response({ code: "account_key_invalid" }, 401))
  await flush()
  requests[1].resolve(response({ code: "account_key_revoked" }, 401))
  await flush()
  assert.equal(s.pendingAccountKeys().length, 1, "the candidate remains durable across the commit race")
  requests[2].resolve(response())
  await task
  assert.equal(s.publicIdentityToken(), record.replacement)
  assert.equal(s.pendingAccountKeys().length, 0)
})

test("negative recovery does not delete a newer tab candidate it has not checked", async () => {
  const { s, requests } = boot(),
    first = s.savePendingAccountKey(oldKey),
    task = s.resolvePendingAccountKeys()
  requests[0].resolve(response({ code: "account_key_invalid" }, 401))
  await flush()
  const later = s.savePendingAccountKey(oldKey)
  requests[1].resolve(response({ code: "account_key_revoked" }, 401))
  await flush()
  requests[2].resolve(response({ code: "account_key_invalid" }, 401))
  await task
  assert.equal(s.pendingAccountKeys().length, 1)
  assert.equal(s.pendingAccountKeys()[0].storageKey, later.storageKey)
  assert.notEqual(first.storageKey, later.storageKey)
})

test("queued old welcomes and fallback clears cannot overwrite a newly imported or reset key", () => {
  const { s } = boot()
  s.rememberPublicIdentity(key)
  s.rememberPublicIdentity(oldKey, oldKey)
  assert.equal(s.publicIdentityToken(), key)
  s.rememberPublicIdentity("", oldKey)
  assert.equal(s.publicIdentityToken(), key)
  s.forgetRevokedAccount(oldKey)
  assert.equal(s.publicIdentityToken(), key)
  s.rememberPublicIdentity(oldKey, key)
  assert.equal(
    s.publicIdentityToken(),
    oldKey,
    "a handshake for the currently selected key can save its acknowledged credential",
  )
})

test("P2 copy and import select only the independent P2 credential and callsign", async () => {
  const { s, $, requests, primary, local } = boot()
  $("accountDialog").dataset.accountSeat = "1"
  $("accountImportKey").value = key
  const pending = s.checkImportedAccount()
  requests[0].resolve(response({ names: ["WING"], publicProfile: { name: "WING", score: 9 } }))
  await pending
  s.openAccount = () => {}
  const use = s.useImportedAccount()
  requests.at(-1).resolve(response({ names: [$("accountImportName").value] }))
  await use
  assert.equal(s.publicIdentityToken(), oldKey)
  assert.equal(s.publicIdentityToken(1), key)
  assert.equal(primary.name, "OLD")
  assert.equal(local.name, "WING")
  const copied = []
  s.navigator.clipboard.writeText = async (token) => copied.push(token)
  await s.copyAccountKey()
  assert.deepEqual(copied, [key])
})

test("the same account key cannot be imported into both local players", async () => {
  const { s, $, requests } = boot()
  $("accountDialog").dataset.accountSeat = "1"
  $("accountImportKey").value = oldKey
  await s.checkImportedAccount()
  assert.equal(requests.length, 0)
  assert.match($("accountImportNotice").textContent, /separate account keys/)
  assert.equal(s.publicIdentityToken(1), "")
})

test("P2 reset and a late P2 revocation never change P1 proof", async () => {
  const { s, $, requests } = boot()
  $("accountDialog").dataset.accountSeat = "1"
  s.rememberPublicIdentity(key, undefined, 1)
  const task = s.rotateAccountKey()
  await flush()
  const record = s.pendingAccountKeys()[0]
  assert.equal(record.seat, 1)
  assert.equal(JSON.parse(requests[0].request.body).publicToken, key)
  requests[0].resolve(response({ ...info, publicToken: record.replacement }))
  await task
  assert.equal(s.publicIdentityToken(), oldKey)
  assert.equal(s.publicIdentityToken(1), record.replacement)
  s.forgetRevokedAccount(key, 1)
  assert.equal(s.publicIdentityToken(1), record.replacement)
  s.forgetRevokedAccount(record.replacement, 1)
  assert.equal(s.publicIdentityToken(1), "")
  assert.equal(s.publicIdentityToken(), oldKey)
})

test("P2 registration stores its candidate durably before joining and retries the same candidate", () => {
  const { s, storage } = boot(),
    first = s.prepareLocalAccount()
  assert.ok(s.accountKeyValid(first.localPublicToken))
  assert.equal(first.localNewAccount, true)
  assert.equal(JSON.parse(storage.get("leqra.localAccountRegistration")).token, first.localPublicToken)
  assert.equal(s.publicIdentityToken(1), first.localPublicToken)
  const second = s.prepareLocalAccount()
  assert.equal(second.localPublicToken, first.localPublicToken)
  assert.equal(second.localNewAccount, true)
  s.rememberPublicIdentity(first.localPublicToken, first.localPublicToken, 1)
  assert.equal(storage.has("leqra.localAccountRegistration"), false)
  assert.equal(s.prepareLocalAccount().localNewAccount, undefined)
})

test("failed P2 registration persistence prevents an unbacked candidate and revocation clears its saved candidate", () => {
  const { s, storage } = boot(),
    write = s.localStorage.setItem
  s.localStorage.setItem = () => {
    throw Error("denied")
  }
  assert.throws(() => s.prepareLocalAccount())
  assert.equal(s.publicIdentityToken(1), "")
  s.localStorage.setItem = write
  const candidate = s.prepareLocalAccount().localPublicToken
  s.forgetRevokedAccount(candidate, 1)
  assert.equal(s.publicIdentityToken(1), "")
  assert.equal(storage.has("leqra.localAccountRegistration"), false)
  assert.equal(s.publicIdentityToken(), oldKey)
})

test("an unregistered P2 candidate cannot be copied or reset until the server confirms it", async () => {
  const { s, $, requests, storage } = boot(),
    candidate = s.prepareLocalAccount().localPublicToken
  s.openAccount(1)
  assert.equal($("accountCopyBtn").disabled, true)
  assert.equal($("accountRotateBtn").disabled, true)
  requests[0].resolve(response({ code: "account_key_invalid" }, 401))
  await flush()
  assert.match($("accountCurrentNotice").textContent, /Go online with P2 to activate/)
  assert.equal($("accountCopyBtn").disabled, true)
  assert.equal(storage.has("leqra.localAccountRegistration"), true)
  s.openAccount(1)
  requests[1].resolve(response({ names: ["WING"], publicProfile: { name: "WING", score: 9 } }))
  await flush()
  assert.equal($("accountCopyBtn").disabled, false)
  assert.equal(s.publicIdentityToken(1), candidate)
  assert.equal(storage.has("leqra.localAccountRegistration"), false)
  assert.equal(s.publicIdentityToken(), oldKey)
})

test("reading or rotating a generated P2 key preserves first-game migration intent", async () => {
  const { s, $, requests, storage } = boot(),
    candidate = s.prepareLocalAccount().localPublicToken
  s.openAccount(1)
  requests[0].resolve(response({ names: ["pilot-abcdefgh23"] }))
  await flush()
  assert.equal($("accountCopyBtn").disabled, false)
  assert.equal(JSON.parse(storage.get("leqra.localAccountRegistration")).token, candidate)
  assert.equal(s.prepareLocalAccount().localNewAccount, true)
  const reset = s.savePendingAccountKey(candidate, 1)
  s.completeAccountReset(reset, { names: ["pilot-abcdefgh23"] })
  assert.equal(s.publicIdentityToken(1), reset.replacement)
  assert.equal(JSON.parse(storage.get("leqra.localAccountRegistration")).token, reset.replacement)
  assert.equal(s.prepareLocalAccount().localNewAccount, true)
})

test("malformed P2 registration data fails closed without leaking its contents", () => {
  const { s, storage } = boot()
  storage.set("leqra.localAccountRegistration", "private-malformed-key")
  assert.throws(
    () => s.prepareLocalAccount(),
    (error) => !error.message.includes("private-malformed-key"),
  )
  assert.equal(storage.get("leqra.localAccountRegistration"), "private-malformed-key")
  assert.equal(s.publicIdentityToken(), oldKey)
})

test("importing another P2 key keeps an in-flight activation candidate recoverable", async () => {
  const { s, $, requests, storage } = boot(),
    candidate = s.prepareLocalAccount().localPublicToken
  s.rememberPublicIdentity(key, undefined, 1)
  assert.equal(JSON.parse(storage.get("leqra.localAccountRegistration")).token, candidate)
  assert.equal(s.publicIdentityToken(1), key)
  $("accountDialog").dataset.accountSeat = "1"
  const resolve = s.resolvePendingAccountKeys()
  requests[0].resolve(response({ names: ["LEGACY WING"], publicProfile: { name: "LEGACY WING", score: 17 } }))
  await resolve
  assert.equal(
    s.publicIdentityToken(1),
    key,
    "a late registration never silently replaces the imported account",
  )
  assert.equal($("accountImportKey").value, candidate)
  assert.equal($("accountImportReview").hidden, false)
  s.openAccount = () => {}
  const use = s.useImportedAccount()
  requests.at(-1).resolve(response({ names: [$("accountImportName").value] }))
  await use
  assert.equal(s.publicIdentityToken(1), candidate)
  assert.equal(storage.has("leqra.localAccountRegistration"), false)
  assert.equal(s.publicIdentityToken(), oldKey)
})

test("an unconfirmed previous P2 activation is retained while another P2 account is selected", async () => {
  const { s, $, requests, storage } = boot(),
    candidate = s.prepareLocalAccount().localPublicToken
  s.rememberPublicIdentity(key, undefined, 1)
  $("accountDialog").dataset.accountSeat = "1"
  const task = s.resolvePendingAccountKeys()
  requests[0].resolve(response({ code: "account_key_invalid" }, 401))
  await task
  assert.equal(s.publicIdentityToken(1), key)
  assert.equal(JSON.parse(storage.get("leqra.localAccountRegistration")).token, candidate)
  assert.equal(requests.length, 1)
})

test("joining a match while explicit import sign-in is pending preserves the active account", async () => {
  const { s, $, requests } = boot()
  $("accountImportKey").value = key
  const check = s.checkImportedAccount()
  requests[0].resolve(response(info))
  await check
  s.openAccount = () => {}
  const use = s.useImportedAccount()
  assert.equal(JSON.parse(requests[1].request.body).signIn, true)
  s.online.connected = true
  requests[1].resolve(response(info))
  await use
  assert.equal(s.publicIdentityToken(), oldKey)
  assert.match($("accountImportNotice").textContent, /joined online play/)
})
