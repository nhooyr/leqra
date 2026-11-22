"use strict"
const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  vm = require("node:vm"),
  { readFileSync } = require("node:fs"),
  { join } = require("node:path")
const source = readFileSync(join(__dirname, "..", "leaderboard_admin_ui.go"), "utf8").match(
  /const leaderboardAdminJS = `([\s\S]*?)`/,
)[1]
function fixture({ confirmed = true, clipboardFails = false, fallbackCopies = true } = {}) {
  const nodes = new Map(),
    requests = [],
    copied = [],
    confirmations = []
  const node = () => ({
    value: "",
    disabled: false,
    children: [],
    listeners: {},
    addEventListener(type, fn) {
      this.listeners[type] = fn
    },
    replaceChildren() {
      this.children = []
    },
    append(...children) {
      this.children.push(...children)
    },
    focus() {
      this.focused = true
    },
    select() {
      this.selected = true
    },
  })
  const context = vm.createContext({
    document: {
      querySelector(selector) {
        if (!nodes.has(selector)) {
          const value = node()
          if (selector === "#pattern") value.value = "old"
          nodes.set(selector, value)
        }
        return nodes.get(selector)
      },
      createElement: node,
      execCommand: () => fallbackCopies,
    },
    fetch: (url, options) =>
      new Promise((resolve, reject) => requests.push({ url, options, resolve, reject })),
    confirm: (message) => {
      confirmations.push(message)
      return confirmed
    },
    crypto: { getRandomValues: (bytes) => bytes.fill(3) },
    btoa: (value) => Buffer.from(value, "binary").toString("base64"),
    navigator: {
      clipboard: {
        writeText: async (value) => {
          if (clipboardFails) throw new Error("Clipboard denied")
          copied.push(value)
        },
      },
    },
    clearTimeout() {},
    setTimeout() {},
    setInterval() {},
  })
  vm.runInContext(source, context)
  return { context, nodes, requests, copied, confirmations }
}
const response = (matched = 3, accounts = [], entries = []) => ({
  ok: true,
  json: async () => ({
    csrfToken: "secret",
    matched,
    total: matched,
    connected: 0,
    entries,
    accounts,
    accountTotal: accounts.length,
    accountMatched: accounts.length,
  }),
})

test("admin recovery lists accounts safely and waits for confirmation", async () => {
  const account = { id: "opaque", names: ["<script>test</script>"] }
  const { context, nodes, requests } = fixture({ confirmed: false })
  requests[0].resolve(response(0, [account]))
  await settle()
  const row = nodes.get("#entries").children[0]
  assert.equal(row.children[0].textContent, account.names[0])
  assert.equal(row.children[1].textContent, "—")
  assert.equal(row.children[3].textContent, "—")
  assert.equal(row.children[4].children[0].textContent, "Recover key")
  await context.recover(account)
  assert.equal(requests.length, 1, "cancel must not replace any key")
})

test("admin table combines scores and recovery by account identity without duplicate rows", async () => {
  const accounts = [
    { id: "owner-a", names: ["Canonical Pilot"] },
    { id: "owner-b", names: ["Private Pilot"] },
  ]
  const entries = [
    { id: 1, name: "Display Pilot", score: 19, bot: false, connected: true, accountId: "owner-a" },
    { id: 2, name: "Bot", score: 5, bot: true, connected: true },
    { id: 3, name: "Historical Pilot", score: -7, bot: false, connected: false },
  ]
  const { nodes, requests, confirmations } = fixture({ confirmed: false })
  requests[0].resolve(response(3, accounts, entries))
  await settle()
  const rows = nodes.get("#entries").children
  assert.equal(rows.length, 4)
  assert.equal(rows[0].children[0].textContent, "Display Pilot")
  assert.equal(rows[0].children[1].textContent, "19")
  await rows[0].children[4].children[0].listeners.click()
  assert.match(confirmations[0], /Canonical Pilot/)
  assert.equal(rows[1].children[4].textContent, "—", "bots have no account key")
  assert.equal(rows[2].children[4].textContent, "—", "unowned scores cannot recover another account")
  assert.equal(rows[3].children[0].textContent, "Private Pilot")
  assert.equal(nodes.has("#accounts"), false, "one table contains every row")
})

test("admin recovery uses a new key and copies only the confirmed replacement", async () => {
  const account = { id: "opaque", names: ["Pilot"] }
  const { context, nodes, requests, copied } = fixture()
  requests[0].resolve(response(0, [account]))
  await settle()
  const recovery = context.recover(account)
  assert.equal(requests[1].url, "/api/recover-account")
  assert.equal(requests[1].options.method, "POST")
  assert.equal(requests[1].options.headers["X-Leqra-Admin-CSRF"], "secret")
  const body = JSON.parse(requests[1].options.body)
  assert.equal(body.accountId, account.id)
  assert.match(body.newPublicToken, /^p_[A-Za-z0-9_-]{43}$/)
  assert.equal(nodes.get("#copyKey").disabled, true)
  requests[1].resolve({ ok: true, json: async () => ({ recovered: true }) })
  await settle()
  requests[2].resolve(response(0, [{ ...account, id: "replacement" }]))
  await recovery
  assert.equal(nodes.get("#recoveryKey").value, body.newPublicToken)
  await context.copyRecoveryKey()
  assert.deepEqual(copied, [body.newPublicToken])
  nodes.get("#closeKey").listeners.click()
  assert.equal(nodes.get("#recoveryKey").value, "")
  assert.equal(nodes.get("#recovery").hidden, true)
})

test("admin recovery retains an uncertain candidate and never presents a rejected key as ready", async () => {
  for (const uncertain of [false, true]) {
    const { context, nodes, requests } = fixture()
    requests[0].resolve(response())
    await settle()
    const recovery = context.recover({ id: "opaque", names: ["Pilot"] })
    if (uncertain) requests[1].reject(new Error("Connection lost"))
    else requests[1].resolve({ ok: false, text: async () => "Account changed" })
    await recovery
    assert.equal(nodes.get("#copyKey").disabled, !uncertain)
    if (uncertain) {
      assert.match(nodes.get("#recoveryKey").value, /^p_/)
      assert.match(nodes.get("#recoveryStatus").textContent, /not confirmed/)
      await context.copyRecoveryKey()
      assert.match(nodes.get("#recoveryStatus").textContent, /not confirmed/)
    } else assert.equal(nodes.get("#recoveryKey").value, "")
  }
})

test("admin key copying has a manual selection fallback", async () => {
  const { context, nodes, copied } = fixture({ clipboardFails: true, fallbackCopies: false })
  nodes.get("#recoveryKey").value = "test replacement"
  nodes.get("#copyKey").disabled = false
  await context.copyRecoveryKey()
  assert.equal(nodes.get("#recoveryKey").selected, true)
  assert.deepEqual(copied, [])
  assert.match(nodes.get("#recoveryStatus").textContent, /manually/)
})
async function settle() {
  for (let i = 0; i < 5; i++) await Promise.resolve()
}

test("admin Clear matches stays disabled after failed or invalidated mutation refreshes", async () => {
  for (const outcome of ["failed", "changed"]) {
    const { context, nodes, requests } = fixture(),
      pattern = nodes.get("#pattern"),
      remove = nodes.get("#remove")
    requests[0].resolve(response())
    await settle()
    assert.equal(remove.disabled, false)
    const mutation = context.change("/api/remove", { pattern: "old" }, "Clear old matches?")
    requests[1].resolve({ ok: true, json: async () => ({ affected: 3 }) })
    await settle()
    assert.equal(requests[2].url, "/api/leaderboard?pattern=old")
    if (outcome === "changed") {
      pattern.value = "new"
      pattern.listeners.input()
      requests[2].resolve(response(99))
    } else requests[2].resolve({ ok: false, text: async () => "refresh failed" })
    await mutation
    assert.equal(remove.disabled, true, outcome)
    const before = requests.length
    await context.change("/api/remove", { pattern: pattern.value }, "Clear unverified matches?")
    assert.equal(requests.length, before, outcome + " cannot mutate with stale match counts")
  }
})
