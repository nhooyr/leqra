"use strict"
// Optional real-browser check against a disposable server binary. No production data is used.
// NODE_PATH=... node src/tests/admin_recovery_browser.cjs /path/to/leqra /tmp/artifacts
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { randomBytes } = require("node:crypto")
const { spawn } = require("node:child_process")
const { chromium, webkit, devices } = require("playwright")

const binary = path.resolve(process.argv[2])
const output = path.resolve(process.argv[3] || path.join(os.tmpdir(), "leqra-admin-recovery-browser"))
const directory = fs.mkdtempSync(path.join(os.tmpdir(), "leqra-admin-recovery-server-"))
fs.mkdirSync(output, { recursive: true })
const server = spawn(binary, [], {
  cwd: directory,
  env: {
    ...process.env,
    ADDR: "127.0.0.1:0",
    LEQRA_ADMIN_ADDR: "localhost:0",
    LEQRA_DATA: path.join(directory, "data.sqlite"),
  },
  stdio: ["ignore", "pipe", "pipe"],
})
let log = ""
server.stdout.on("data", (chunk) => {
  log += chunk
})
server.stderr.on("data", (chunk) => {
  log += chunk
})
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

async function main() {
  let admin
  for (let attempt = 0; attempt < 200; attempt++) {
    admin = [...log.matchAll(/^admin: (http:\/\/\S+)/gm)].map((match) => match[1])
    if (admin.length === 2) break
    if (server.exitCode !== null) throw Error("Disposable server exited: " + log)
    await delay(25)
  }
  assert.equal(admin.length, 2, log)
  const port = log.match(/^http:\/\/localhost:(\d+)/m)[1]
  const origin = "http://127.0.0.1:" + port
  async function accountRequest(route, body) {
    const response = await fetch(origin + route, {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: origin },
      body: JSON.stringify(body),
    })
    return { status: response.status, body: await response.json() }
  }
  const reports = []
  for (const [label, engine, profile, adminURL] of [
    ["desktop-chromium", chromium, { viewport: { width: 1280, height: 900 } }, admin[0]],
    ["mobile-webkit", webkit, devices["iPhone 13"], admin[1]],
  ]) {
    const name = "Recover " + reports.length
    const old = "p_" + randomBytes(32).toString("base64url")
    assert.equal((await accountRequest("/api/account/create", { publicToken: old, name })).status, 200)
    const browser = await engine.launch({ headless: true })
    try {
      const context = await browser.newContext(profile)
      if (engine === chromium) await context.grantPermissions(["clipboard-read", "clipboard-write"])
      const page = await context.newPage()
      const errors = []
      page.on("pageerror", (error) => errors.push(error.message))
      await page.addInitScript(() => {
        const write = navigator.clipboard?.writeText.bind(navigator.clipboard)
        if (write)
          navigator.clipboard.writeText = async (value) => {
            await write(value)
            window.copiedRecoveryKey = value
          }
        const exec = document.execCommand.bind(document)
        document.execCommand = (...args) => {
          const result = exec(...args)
          if (args[0] === "copy" && result) window.copiedRecoveryKey = document.activeElement.value
          return result
        }
      })
      await page.goto(adminURL)
      assert.equal(await page.locator("table").count(), 1)
      assert.equal(
        await page.locator(".table").evaluate((table) => table.scrollWidth <= table.clientWidth + 1),
        true,
        label + " table fits the viewport",
      )
      await page.locator("#pattern").fill(name)
      await page.waitForFunction(
        (name) => document.querySelector("#entries")?.textContent.includes(name),
        name,
      )
      const row = page.locator("#entries tr").filter({ hasText: name })
      page.once("dialog", (dialog) => {
        assert(dialog.message().includes("old key will stop working"))
        return dialog.accept()
      })
      await row.getByRole("button", { name: "Recover key" }).click()
      await page.waitForFunction(() => !document.querySelector("#copyKey").disabled)
      const replacement = await page.locator("#recoveryKey").inputValue()
      assert.match(replacement, /^p_[A-Za-z0-9_-]{43}$/)
      assert.notEqual(replacement, old)
      const revoked = await accountRequest("/api/account", { publicToken: old })
      assert.equal(revoked.status, 401)
      assert.equal(revoked.body.code, "account_key_revoked")
      const restored = await accountRequest("/api/account", { publicToken: replacement })
      assert.equal(restored.status, 200)
      assert.deepEqual(restored.body.names, [name])
      await page.locator("#copyKey").click()
      await page.waitForFunction(
        () =>
          window.copiedRecoveryKey ||
          document.querySelector("#recoveryStatus").textContent.includes("manually"),
      )
      assert.equal(
        await page.evaluate((key) => window.copiedRecoveryKey === key, replacement),
        true,
        label + " copied the replacement key",
      )
      await page.locator("#recoveryKey").evaluate((input) => {
        input.value = "p_" + "A".repeat(43)
      })
      await page.screenshot({ path: path.join(output, label + ".png"), fullPage: true })
      await page.locator("#closeKey").click()
      assert.equal(await page.locator("#recoveryKey").inputValue(), "")
      assert.deepEqual(errors, [])
      reports.push({ label, recovered: true, copied: true, oldKeyRevoked: true })
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
    server.kill("SIGTERM")
    const ended = new Promise((resolve) => server.once("exit", resolve))
    await Promise.race([ended, delay(6000)])
    if (server.exitCode === null) {
      server.kill("SIGKILL")
      await ended
    }
    fs.rmSync(directory, { recursive: true, force: true })
  })
