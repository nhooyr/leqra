"use strict"
// Run against a disposable loopback server; screenshots remain outside the repo.
const { chromium, webkit } = require("playwright"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  os = require("node:os"),
  path = require("node:path"),
  { createHash } = require("node:crypto")
const hash = (data) => createHash("sha256").update(data).digest("hex")
const address = process.argv[2] || "http://127.0.0.1:8080",
  origin = new URL(address)
assert.ok(["localhost", "127.0.0.1", "[::1]"].includes(origin.hostname))
const output = fs.mkdtempSync(path.join(os.tmpdir(), "leqra-showcase-"))
;(async () => {
  for (const [engine, type] of Object.entries({ chromium, webkit })) {
    const browser = await type.launch()
    for (const [width, height, mobile] of [
      [1560, 930, false],
      [1712, 1000, false],
      [320, 568, true],
      [390, 844, true],
      [440, 956, true],
      [844, 390, true],
      [768, 1024, true],
      [1024, 768, true],
    ]) {
      const context = await browser.newContext({
        viewport: { width, height },
        hasTouch: mobile,
        serviceWorkers: "block",
      })
      await context.addInitScript(() => {
        localStorage.setItem("leqra.introTour.v1", "1")
        localStorage.setItem("leqra.name", "Showcase tester")
        sessionStorage.setItem("leqra.safariNoticeDismissed", "1")
        localStorage.setItem("leqra.muted", "1")
        localStorage.setItem(
          "leqra.feedback.v1",
          JSON.stringify({ fps: false, mouseAim: false, mouseFire: false }),
        )
        localStorage.setItem(
          "leqra.bindings.v1",
          JSON.stringify({
            version: 4,
            bindings: [
              {
                forward: "KeyI",
                reverse: "KeyS",
                left: "KeyA",
                right: "KeyD",
                fire: "KeyQ",
                fireAlt: "KeyC",
              },
              {
                forward: "ArrowUp",
                reverse: "ArrowDown",
                left: "ArrowLeft",
                right: "ArrowRight",
                fire: "Space",
                fireAlt: "Enter",
              },
            ],
          }),
        )
      })
      await context.addInitScript(() => {
        window.showcaseDrawnLabels = []
        window.showcaseCannonStrokes = []
        const fillRect = CanvasRenderingContext2D.prototype.fillRect,
          fillText = CanvasRenderingContext2D.prototype.fillText,
          moveTo = CanvasRenderingContext2D.prototype.moveTo,
          lineTo = CanvasRenderingContext2D.prototype.lineTo,
          stroke = CanvasRenderingContext2D.prototype.stroke
        CanvasRenderingContext2D.prototype.fillRect = function (x, y, w, h) {
          if (
            this.canvas.classList.contains("showcase-canvas") &&
            x === 0 &&
            y === 0 &&
            w === this.canvas.clientWidth &&
            h === this.canvas.clientHeight
          ) {
            window.showcaseDrawnLabels = []
            window.showcaseCannonStrokes = []
          }
          return fillRect.call(this, x, y, w, h)
        }
        CanvasRenderingContext2D.prototype.fillText = function (text, x, y, ...args) {
          if (this.canvas.classList.contains("showcase-canvas")) {
            const m = this.getTransform()
            window.showcaseDrawnLabels.push({
              text,
              x: m.a * x + m.c * y + m.e,
              y: m.b * x + m.d * y + m.f,
              width: this.measureText(text).width * Math.hypot(m.a, m.b),
              canvasWidth: this.canvas.width,
              canvasHeight: this.canvas.height,
            })
          }
          return fillText.call(this, text, x, y, ...args)
        }
        CanvasRenderingContext2D.prototype.moveTo = function (x, y) {
          this.showcaseStart = { x, y }
          return moveTo.call(this, x, y)
        }
        CanvasRenderingContext2D.prototype.lineTo = function (x, y) {
          this.showcaseEnd = { x, y }
          return lineTo.call(this, x, y)
        }
        CanvasRenderingContext2D.prototype.stroke = function (...args) {
          if (
            this.canvas.classList.contains("showcase-canvas") &&
            this.lineWidth === 12 &&
            this.showcaseStart &&
            this.showcaseEnd
          ) {
            const m = this.getTransform(),
              a = this.showcaseStart,
              b = this.showcaseEnd,
              x = (a.x + b.x) / 2,
              y = (a.y + b.y) / 2
            window.showcaseCannonStrokes.push({
              x: m.a * x + m.c * y + m.e,
              y: m.b * x + m.d * y + m.f,
              length: Math.hypot(b.x - a.x, b.y - a.y) * Math.hypot(m.a, m.b),
              alpha: this.globalAlpha,
              canvasWidth: this.canvas.width,
              canvasHeight: this.canvas.height,
            })
          }
          return stroke.apply(this, args)
        }
      })
      const page = await context.newPage(),
        errors = []
      page.on("pageerror", (error) => errors.push(error.message))
      await page.goto(address)
      await page.locator("#roomControlsBtn").click()
      const before = await page.evaluate(() => JSON.stringify({ ...localStorage }))
      await page.locator("#showcaseBtn").click()
      assert.deepEqual(errors, [])
      assert.equal(
        await page.locator("#showcaseDialog").evaluate((el) => el.open),
        true,
        JSON.stringify(errors),
      )
      if (width === 1560) {
        await page.setViewportSize({ width: 390, height: 844 })
        await page.waitForFunction(
          () =>
            document.querySelector("#showcaseDialog").dataset.scene === "portrait" &&
            document.querySelector("#showcaseDialog").classList.contains("showcase-mobile"),
        )
        await page.setViewportSize({ width, height })
        await page.waitForFunction(
          () =>
            document.querySelector("#showcaseDialog").dataset.scene === "desktop" &&
            !document.querySelector("#showcaseDialog").classList.contains("showcase-mobile"),
        )
      }
      const pixels = await page.locator(".showcase-canvas").evaluate((canvas) => {
        const c = canvas.getContext("2d"),
          d = c.getImageData(0, 0, canvas.width, canvas.height).data
        let colored = 0
        for (let i = 0; i < d.length; i += 4) if (d[i] > 80 || d[i + 1] > 90 || d[i + 2] > 100) colored++
        return { width: canvas.clientWidth, height: canvas.clientHeight, colored }
      })
      assert.equal(pixels.width, width)
      assert.ok(pixels.colored > 1000)
      const portrait = mobile && height > width,
        sceneKind = portrait ? "portrait" : mobile ? "wide" : "desktop"
      assert.equal(await page.locator("#showcaseDialog").getAttribute("data-scene"), sceneKind)
      const wrecks = await page.evaluate(
        (kind) =>
          (kind === "wide" ? leqraShowcaseScene : leqraShowcaseScene[kind]).tanks
            .filter((tank) => !tank.hp)
            .map((tank) => leqraInfinityArt.botName(tank.name, tank.bot)),
        sceneKind,
      )
      assert.equal(wrecks.length, 1, "the frozen laser destroys exactly one named tank")
      for (const name of wrecks) {
        assert.ok(
          await page.evaluate(
            (name) =>
              window.showcaseDrawnLabels.some(
                (label) =>
                  label.text === name &&
                  label.x - label.width / 2 >= 0 &&
                  label.x + label.width / 2 <= label.canvasWidth &&
                  label.y > 0 &&
                  label.y < label.canvasHeight,
              ),
            name,
          ),
          "destroyed tank callsign must still be drawn inside the viewport: " + name,
        )
        assert.ok(
          (await page.locator(".showcase-canvas").getAttribute("aria-label")).includes(name),
          "destroyed tank is included in the scene description",
        )
      }
      assert.ok(
        await page.evaluate(() =>
          window.showcaseCannonStrokes.some(
            (stroke) =>
              stroke.alpha >= 0.25 &&
              stroke.length >= 4 &&
              stroke.x > 0 &&
              stroke.x < stroke.canvasWidth &&
              stroke.y > 0 &&
              stroke.y < stroke.canvasHeight,
          ),
        ),
        "a stronger Showcase Cannon trail is actually stroked inside the canvas",
      )
      if (width === 320) {
        const visible = await page.evaluate(() => {
          const scene = leqraShowcaseScene.portrait,
            hero = scene.tanks.find((tank) => tank.id === scene.localID),
            canvas = document.querySelector(".showcase-canvas")
          const normal = Math.max(
              0.7,
              Math.min(1.2, Math.min(canvas.clientWidth, canvas.clientHeight) / (84 * 5)),
            ),
            zoom = Math.min(normal, canvas.clientHeight / 632),
            powers = new Set()
          for (const tank of scene.tanks.filter((tank) => tank.hp > 0)) {
            if (
              Math.abs(tank.x - hero.x) + 24 > canvas.clientWidth / (2 * zoom) ||
              Math.abs(tank.y - hero.y) + 24 > canvas.clientHeight / (2 * zoom)
            )
              return false
            const name =
              tank.id === scene.localID ? tank.name + " (P1)" : leqraInfinityArt.botName(tank.name, tank.bot)
            if (
              !window.showcaseDrawnLabels.some(
                (label) =>
                  label.text === name &&
                  label.x - label.width / 2 >= 0 &&
                  label.x + label.width / 2 <= label.canvasWidth &&
                  label.y >= 10 &&
                  label.y < label.canvasHeight,
              )
            )
              return false
            if (tank.power && tank.powerTime > 0) powers.add(tank.power)
            if (tank.shield > 0) powers.add("shield")
            if (tank.speedTime > 0) powers.add("speed")
            if (tank.ghostTime > 0) powers.add("ghost")
            if (tank.starmanTime > 0) powers.add("starman")
          }
          return powers.size === 10
        })
        assert.ok(visible, "short portrait shows every living hull and label, carrying all ten powers")
      }
      assert.ok(pixels.height < height - 100, "gameplay chrome must reserve space")
      for (const selector of [".showcase-header", ".infinite-statusbar", ".showcase-underbar"])
        assert.equal(await page.locator("#showcaseDialog " + selector).isVisible(), true, selector)
      assert.ok((await page.locator("#showcaseDialog .showcase-underbar").textContent()).includes("LASER ×3"))
      assert.ok((await page.locator("#showcaseDialog .showcase-underbar").textContent()).includes("SHD×2"))
      assert.equal(
        await page.locator('#showcaseDialog [data-showcase-source="headerVersion"]').isVisible(),
        true,
      )
      assert.equal(await page.locator("#showcaseDialog .fps-indicator").textContent(), "fps: 120, ping: 8 ms")
      const expectedColor = await page.evaluate(() => {
        const span = document.createElement("span")
        span.style.color = leqraInfinityArt.colors[0]
        return span.style.color
      })
      assert.equal(
        await page.locator("#showcaseDialog .infinite-personal-score").evaluate((el) => el.style.color),
        expectedColor,
        "status uses the rendered tank palette",
      )
      const footer = await page.locator("#showcaseDialog .showcase-underbar").boundingBox()
      assert.ok(Math.abs(footer.y + footer.height - height) <= 1)
      if (mobile) {
        assert.equal(await page.locator("#showcaseDialog .infinite-touch-controls").isVisible(), true)
        const selected = await page.evaluate(
          (portrait) => (portrait ? leqraShowcaseScene.portrait : leqraShowcaseScene),
          portrait,
        )
        assert.equal(selected.tanks.length, portrait ? 10 : 8)
        assert.equal(selected.pickups.length, portrait ? 4 : 10)
      } else {
        const list = page.locator("#showcaseDialog .infinite-leaderboard")
        assert.equal(await list.isVisible(), true)
        assert.equal(await list.evaluate((el) => el.open), true)
        assert.equal(await list.locator("li").count(), 10)
        assert.ok((await list.locator("li").first().textContent()).includes("aqsnow (P1)"))
        assert.ok((await list.locator("li").first().textContent()).includes("19"))
        assert.equal(
          await list.locator('li[data-local="p1"]').evaluate((el) => {
            const span = document.createElement("span")
            span.style.color = el.style.getPropertyValue("--tank-color")
            return span.style.color
          }),
          expectedColor,
          "leaderboard uses the rendered tank palette",
        )
        assert.equal(await page.locator('#showcaseDialog [data-showcase-source="roomBtn"]').isVisible(), true)
        const hint = await page.locator("#showcaseDialog .showcase-controls-hint").textContent()
        for (const text of ["Forward", "Reverse", "Left", "Right", "Fire", "Mouse Aim", "Mouse Fire"])
          assert.ok(hint.includes(text), text)
        assert.equal(
          await page.locator("#showcaseDialog .showcase-controls-hint kbd").first().textContent(),
          "W",
          "saved remappings do not rewrite the staged controls",
        )
        assert.equal(
          await page
            .locator("#showcaseDialog .sound-off-line")
            .evaluate((el) => getComputedStyle(el).display),
          "none",
          "saved mute preference does not rewrite staged sound icon",
        )
        assert.equal(await page.locator("#showcaseDialog .infinite-touch-controls").count(), 0)
        const header = await page.locator("#showcaseDialog .showcase-header").boundingBox(),
          status = await page.locator("#showcaseDialog .infinite-statusbar").boundingBox(),
          canvas = await page.locator(".showcase-canvas").boundingBox()
        assert.equal(header.y, 0)
        assert.ok(Math.abs(header.y + header.height - status.y) <= 1)
        assert.ok(Math.abs(status.y + status.height - canvas.y) <= 1)
        assert.ok(Math.abs(canvas.y + canvas.height - footer.y) <= 1)
        const coverage = await page.evaluate(() => {
          const scene = leqraShowcaseScene.desktop,
            hero = scene.tanks.find((tank) => tank.id === scene.localID),
            canvas = document.querySelector(".showcase-canvas"),
            zoom = Math.max(0.7, Math.min(1.2, Math.min(canvas.clientWidth, canvas.clientHeight) / (84 * 5)))
          const inside = (item, radius = 0) =>
            Math.abs(item.x - hero.x) + radius <= canvas.clientWidth / (2 * zoom) &&
            Math.abs(item.y - hero.y) + radius <= canvas.clientHeight / (2 * zoom)
          const occupied = new Set()
          for (const item of [...scene.tanks, ...scene.pickups, ...scene.bullets].filter((item) =>
            inside(item),
          )) {
            const col = Math.min(4, Math.floor((((item.x - hero.x) * zoom) / canvas.clientWidth + 0.5) * 5)),
              row = Math.min(2, Math.floor((((item.y - hero.y) * zoom) / canvas.clientHeight + 0.5) * 3))
            occupied.add(col + "," + row)
          }
          const labels = scene.tanks.filter((tank) => {
            const name =
              tank.id === scene.localID ? tank.name + " (P1)" : leqraInfinityArt.botName(tank.name, tank.bot)
            return window.showcaseDrawnLabels.some(
              (label) =>
                label.text === name &&
                label.x - label.width / 2 >= 0 &&
                label.x + label.width / 2 <= label.canvasWidth &&
                label.y >= 10 &&
                label.y < label.canvasHeight,
            )
          })
          return {
            tanks: scene.tanks.filter((item) => inside(item, 24)).length,
            pickups: scene.pickups.filter((item) => inside(item, 22)).length,
            bullets: scene.bullets.filter((item) => inside(item)).length,
            occupied: occupied.size,
            labels: labels.length,
          }
        })
        assert.equal(coverage.tanks, 20, "all desktop tanks fit in the screenshot")
        assert.equal(coverage.labels, 20, "all desktop callsigns are actually drawn inside the viewport")
        assert.equal(coverage.pickups, 26, "all desktop pickups fit in the screenshot")
        assert.ok(coverage.bullets >= 125, "projectile activity spans the desktop canvas")
        assert.equal(
          coverage.occupied,
          15,
          "entities fill every cell of a five-column, three-row desktop grid",
        )
        if (width === 1712) {
          const visible = await page.evaluate(() => {
            const scene = leqraShowcaseScene.desktop,
              hero = scene.tanks.find((tank) => tank.id === scene.localID),
              canvas = document.querySelector(".showcase-canvas"),
              zoom = Math.max(
                0.7,
                Math.min(1.2, Math.min(canvas.clientWidth, canvas.clientHeight) / (84 * 5)),
              )
            return scene.pickups
              .filter(
                (pickup) =>
                  Math.abs(pickup.x - hero.x) + 22 <= canvas.clientWidth / (2 * zoom) &&
                  Math.abs(pickup.y - hero.y) + 22 <= canvas.clientHeight / (2 * zoom),
              )
              .map((pickup) => pickup.type)
          })
          assert.equal(
            new Set(visible).size,
            10,
            "desktop capture keeps all ten power-up types inside the canvas",
          )
        }
      }
      await page.evaluate(
        () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))),
      )
      const first = hash(await page.locator(".showcase-canvas").evaluate((c) => c.toDataURL())),
        firstChrome = await page.locator("#showcaseDialog").innerHTML()
      await page.keyboard.press("q")
      await page.mouse.click(width / 2, height / 2)
      await page.locator('#showcaseDialog [data-showcase-source="pauseBtn"]').click({ force: true })
      await page
        .locator('#showcaseDialog [data-showcase-source="infiniteScoreboardBtn"]')
        .click({ force: true })
      await page.waitForTimeout(120)
      assert.equal(await page.locator("#showcaseDialog").evaluate((el) => el.open), true)
      assert.equal(
        hash(await page.locator(".showcase-canvas").evaluate((c) => c.toDataURL())),
        first,
        "frozen frame changed",
      )
      assert.equal(await page.locator("#showcaseDialog").innerHTML(), firstChrome, "frozen chrome changed")
      if (width === 390) {
        await page.setViewportSize({ width: 844, height: 390 })
        await page.waitForFunction(
          () =>
            document.querySelector("#showcaseDialog").dataset.scene === "wide" &&
            document.body.classList.contains("touch-landscape"),
        )
        await page.setViewportSize({ width, height })
        await page.waitForFunction(
          () =>
            document.querySelector("#showcaseDialog").dataset.scene === "portrait" &&
            !document.body.classList.contains("touch-landscape"),
        )
        await page.evaluate(
          () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))),
        )
        assert.equal(
          hash(await page.locator(".showcase-canvas").evaluate((c) => c.toDataURL())),
          first,
          "rotation must restore the same portrait frame",
        )
      }
      await page.screenshot({ path: path.join(output, engine + "-" + width + "x" + height + ".png") })
      await page.keyboard.press("Escape")
      assert.equal(await page.locator("#showcaseDialog").evaluate((el) => el.open), false)
      assert.equal(await page.locator("#controlsDialog").evaluate((el) => el.open), true)
      assert.equal(await page.evaluate(() => JSON.stringify({ ...localStorage })), before)
      await page.locator("#showcaseBtn").click()
      await page.evaluate(() => {
        Object.defineProperty(document, "hidden", { configurable: true, value: true })
        document.dispatchEvent(new Event("visibilitychange"))
        Object.defineProperty(document, "hidden", { configurable: true, value: false })
        document.dispatchEvent(new Event("visibilitychange"))
      })
      assert.equal(await page.locator("#showcaseDialog").evaluate((el) => el.open), false)
      assert.deepEqual(errors, [])
      await context.close()
      console.log("PASS " + engine + " " + width + "x" + height + " frozen showcase and exits")
    }
    const offline = await browser.newContext({
      viewport: { width: 390, height: 844 },
      hasTouch: true,
      serviceWorkers: "allow",
    })
    await offline.addInitScript(() => {
      localStorage.setItem("leqra.introTour.v1", "1")
      localStorage.setItem("leqra.name", "Offline showcase")
    })
    const page = await offline.newPage()
    await page.goto(address)
    await page.evaluate(async () => {
      await navigator.serviceWorker.ready
      if (!navigator.serviceWorker.controller)
        await new Promise((resolve) =>
          navigator.serviceWorker.addEventListener("controllerchange", resolve, { once: true }),
        )
    })
    await offline.setOffline(true)
    await page.reload()
    await page.locator("#roomControlsBtn").click()
    await page.locator("#showcaseBtn").click()
    assert.equal(await page.locator("#showcaseDialog").evaluate((el) => el.open), true)
    assert.ok((await page.locator(".showcase-canvas").evaluate((c) => c.toDataURL())).length > 10000)
    await page.keyboard.press("Escape")
    await offline.close()
    console.log("PASS " + engine + " offline cached Showcase")
    await browser.close()
  }
  console.log("Screenshots: " + output)
})().catch((error) => {
  console.error(error)
  process.exit(1)
})
