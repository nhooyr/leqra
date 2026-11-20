"use strict"
// Use only with a disposable local test server and its temporary database.
const assert = require("node:assert/strict"),
  { chromium } = require("playwright")
const origin = process.argv[2] || "http://127.0.0.1:18133",
  suffix = Date.now().toString(36),
  names = ["ReleaseA" + suffix, "ReleaseB" + suffix]
;(async () => {
  const browser = await chromium.launch({ headless: true }),
    context = await browser.newContext({
      viewport: { width: 390, height: 844 },
      isMobile: true,
      hasTouch: true,
      serviceWorkers: "block",
    }),
    errors = []
  await context.addInitScript(() => {
    localStorage.setItem("leqra.introTour.v1", "1")
    localStorage.setItem("leqra.infinityOnline", "0")
  })
  const page = await context.newPage()
  page.on("pageerror", (error) => errors.push(error.message))
  try {
    await page.goto(origin + "/?test=1")
    await page.waitForFunction(() => window.__test)
    async function choose(name) {
      const field = page.locator("#roomCallsign")
      await field.fill(name)
      await field.press("Enter")
      await page.waitForFunction((name) => localStorage.getItem("leqra.name") === name, name)
    }
    async function open() {
      await page.locator("#roomCallsignForm .callsign-account-button").click()
      await page.waitForFunction(() =>
        document.querySelector("#accountCurrentInfo").textContent.includes("Callsign:"),
      )
    }
    await choose(names[0])
    const first = await page.evaluate(() => localStorage.getItem("leqra.publicToken"))
    await choose(names[1])
    const second = await page.evaluate(() => localStorage.getItem("leqra.publicToken"))
    assert.notEqual(first, second)
    await open()
    await page.getByRole("button", { name: "Release " + names[0], exact: true }).click()
    await page.locator("#actionConfirmCancel").click()
    assert.equal(
      await page.evaluate(
        (name) => JSON.parse(localStorage.getItem("leqra.accounts.v1")).some((entry) => entry.name === name),
        names[0],
      ),
      true,
    )
    await page.route("**/api/account/release", (route) =>
      route.fulfill({
        status: 503,
        contentType: "application/json",
        body: JSON.stringify({ message: "Temporary failure" }),
      }),
    )
    await page.getByRole("button", { name: "Release " + names[0], exact: true }).click()
    await page.locator("#actionConfirmAccept").click()
    await page.waitForFunction(() =>
      document.querySelector("#accountCurrentNotice").textContent.includes("Could not release"),
    )
    assert.equal(
      await page.evaluate(
        (name) => JSON.parse(localStorage.getItem("leqra.accounts.v1")).some((entry) => entry.name === name),
        names[0],
      ),
      true,
    )
    await page.unroute("**/api/account/release")
    await page.getByRole("button", { name: "Release " + names[0], exact: true }).click()
    await page.locator("#actionConfirmAccept").click()
    await page.waitForFunction(
      (name) => !JSON.parse(localStorage.getItem("leqra.accounts.v1")).some((entry) => entry.name === name),
      names[0],
    )
    assert.equal(await page.evaluate(() => localStorage.getItem("leqra.publicToken")), second)
    await page.locator("#accountReleaseBtn").click()
    await page.locator("#actionConfirmAccept").click()
    await page.waitForFunction(() => !localStorage.getItem("leqra.publicToken"))
    assert.match(await page.locator("#roomCallsign").inputValue(), /^pilot#/)
    await page.locator('[data-close-dialog="accountDialog"]').click()
    await page.locator("#infinityToggle").check()
    await page.locator("#startRoomBtn").click()
    await page.waitForFunction(
      () => !!localStorage.getItem("leqra.publicToken") && document.querySelector("#infiniteArena").open,
    )
    assert.notEqual(await page.evaluate(() => localStorage.getItem("leqra.publicToken")), second)
    assert.deepEqual(errors, [])
    console.log(
      JSON.stringify({
        checks: [
          "cancel retains saved account",
          "backend failure retains saved key",
          "saved release keeps selected account",
          "current release clears selected key",
          "next Play creates fresh account",
          "no browser errors",
        ],
      }),
    )
  } finally {
    await browser.close()
  }
})().catch((error) => {
  console.error("Account release browser check failed: " + error.message)
  process.exitCode = 1
})
