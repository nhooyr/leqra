"use strict"
const { performance, PerformanceObserver, constants } = require("node:perf_hooks"),
  path = require("node:path")
const { assetPath } = require("./web_assets.cjs")
const Net = require(
  process.env.LEQRA_NETCODE_SOURCE ? path.resolve(process.env.LEQRA_NETCODE_SOURCE) : assetPath("netcode.js"),
)

function retainedBatch({ count = 864, contacts = 8, kind = "mixed", points = 2 } = {}) {
  const kinds = ["regular", "rapid", "scatter", "homing", "grenade", "cannon"],
    events = [],
    tanks = []
  for (let index = 0; index < count; index++) {
    const id = index + 1,
      type = kind === "mixed" ? kinds[index % kinds.length] : kind,
      radius = type === "cannon" ? 14 : type === "grenade" ? 6 : type === "rapid" ? 3.5 / 3 : 3.5
    const path = Array.from({ length: points }, (_, i) => ({
      x: 100 + id * 40 + i * 2 + (i % 2 ? 10 : 0),
      y: 100 + (i % 3) * 3,
      tick: 10 + (2 * i) / (points - 1),
    }))
    const flight = {
        id,
        owner: index % 8,
        colorIndex: index % 8,
        kind: type,
        radius,
        startTick: 10,
        endTick: 12,
        points: path,
      },
      event = { id, owner: flight.owner, flight }
    if (index < contacts) {
      const last = path.at(-1),
        before = {
          x: last.x + 17 + radius,
          y: last.y,
          angle: 0,
          vx: 0,
          vy: 0,
          hp: 1,
          shield: 0,
          shieldCharges: 0,
          invulnerable: 0,
          spawnProtected: false,
        }
      event.contact = { projectileId: id, kind: type, tick: 12, target: 10000 + id, spawnSerial: 4, before }
      tanks.push({ id: event.contact.target, spawnSerial: 4, ...before, hp: 0, alive: false, score: 123 })
    }
    events.push(event)
  }
  const cache = new Net.ProjectileFlights()
  cache.rememberTanks(tanks, 0)
  cache.accept(events, 0)
  return { cache, events, tanks }
}

async function run() {
  const gcEntries = [],
    observer = new PerformanceObserver((list) => gcEntries.push(...list.getEntries()))
  observer.observe({ entryTypes: ["gc"] })
  const frames = Math.max(100, Number(process.env.LEQRA_FLIGHT_FRAMES) || 800),
    results = []
  for (const spec of [
    { name: "mixed-two-point", kind: "mixed", points: 2 },
    { name: "scatter-32-point", kind: "scatter", points: 32 },
    { name: "rapid-two-point", kind: "rapid", points: 2 },
  ]) {
    const { cache, tanks } = retainedBatch(spec),
      samples = []
    let sink = 0
    const frame = () => {
      const shells = cache.sample(11, 10)
      globalThis.__leqraFlightBenchmark = shells
      for (const tank of tanks) cache.visualTank(tank, tank, null, 10)
      sink += shells.length + shells[0].x
    }
    for (let i = 0; i < 200; i++) frame()
    if (global.gc) global.gc()
    const heapBefore = process.memoryUsage().heapUsed,
      started = performance.now()
    for (let i = 0; i < frames; i++) {
      const start = performance.now()
      frame()
      samples.push((performance.now() - start) * 1000)
    }
    const ended = performance.now(),
      heapAfter = process.memoryUsage().heapUsed
    await new Promise((resolve) => setTimeout(resolve, 10))
    gcEntries.push(...observer.takeRecords())
    const collected = gcEntries.filter((entry) => entry.startTime >= started && entry.startTime <= ended)
    samples.sort((a, b) => a - b)
    const at = (p) => samples[Math.min(samples.length - 1, Math.floor(samples.length * p))]
    results.push({
      case: spec.name,
      flights: cache.items.size,
      contacts: cache.contactCount,
      frames,
      meanUs: samples.reduce((a, b) => a + b, 0) / samples.length,
      p50Us: at(0.5),
      p95Us: at(0.95),
      p99Us: at(0.99),
      maxUs: samples.at(-1),
      heapDeltaBytes: heapAfter - heapBefore,
      minorGCCount: collected.filter((entry) => entry.detail.kind === constants.NODE_PERFORMANCE_GC_MINOR)
        .length,
      gcMs: collected.reduce((sum, entry) => sum + entry.duration, 0),
      sink,
    })
  }
  delete globalThis.__leqraFlightBenchmark
  observer.disconnect()
  console.log(
    JSON.stringify(
      {
        runtime: process.version,
        source: process.env.LEQRA_NETCODE_SOURCE || assetPath("netcode.js"),
        scope:
          "864 retained authoritative terminal paths plus8contacts: sampled immutable shells/trails and held tank presentation. Node/V8 CPU and transient heap only; excludes Canvas/GPU/audio/networking. Each case warms200frames, then samples the same retained live tick.",
        results,
      },
      null,
      2,
    ),
  )
}
if (require.main === module)
  run().catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
module.exports = { retainedBatch }
