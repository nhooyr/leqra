"use strict"
const { test } = require("node:test"),
  assert = require("node:assert/strict")
const { retainedBatch } = require("./projectile_flights_performance.bench.cjs")

for (const spec of [
  { kind: "mixed", points: 2 },
  { kind: "scatter", points: 32 },
  { kind: "rapid", points: 2 },
])
  test(
    spec.kind + " retained864-flight presentation keeps immutable samples and exact8-contact endpoints",
    () => {
      const { cache, events, tanks } = retainedBatch(spec),
        source = JSON.stringify(events),
        authority = JSON.stringify(tanks)
      const first = cache.sample(11, 10),
        firstJSON = JSON.stringify(first)
      assert.equal(first.length, 864)
      assert.equal(cache.contactCount, 8)
      const next = cache.sample(11.5, 20)
      assert.equal(next.length, 864)
      assert.equal(
        JSON.stringify(first),
        firstJSON,
        "later frames cannot overwrite a retained sampled snapshot",
      )
      assert.notEqual(first, next)
      assert.notEqual(first[0], next[0])
      assert.notEqual(first[0].trail, next[0].trail)
      if (first[0].trail.length) {
        assert.notEqual(first[0].trail[0], events[0].flight.points[0])
        assert.notEqual(first[0].trail[0], next[0].trail[0])
      }
      const sounds = []
      for (let i = 0; i < 8; i++) cache.deferContact(i + 1, () => sounds.push(i + 1))
      const endpoints = cache.sample(12, 100)
      cache.flush()
      assert.equal(endpoints.length, 864)
      assert.equal(cache.contactCount, 8)
      assert.deepEqual(sounds, [])
      for (let i = 0; i < endpoints.length; i++) {
        const expected = events[i].flight.points.at(-1),
          shell = endpoints[i]
        assert.equal(shell.id, i + 1)
        assert.equal(shell.x, expected.x)
        assert.equal(shell.y, expected.y)
        if (shell.trail.length) {
          assert.deepEqual(shell.trail.at(-1), { x: expected.x, y: expected.y })
          for (const point of shell.trail) assert.ok(Number.isFinite(point.x) && Number.isFinite(point.y))
        }
      }
      for (let i = 0; i < 8; i++) {
        const tank = cache.visualTank(tanks[i], tanks[i], null, 100),
          shell = endpoints[i]
        assert.equal(tank.hp, 1)
        assert.ok(Math.abs(Math.hypot(shell.x - tank.x, shell.y - tank.y) - 17 - shell.r) < 1e-7)
        assert.equal(tank.score, 123)
      }
      assert.equal(cache.sample(12, 109).length, 0)
      cache.flush()
      assert.equal(cache.contactCount, 0)
      assert.deepEqual(sounds, [1, 2, 3, 4, 5, 6, 7, 8])
      for (const tank of tanks) assert.equal(cache.visualTank(tank, tank, null, 109).hp, 0)
      assert.equal(JSON.stringify(first), firstJSON)
      assert.equal(JSON.stringify(events), source)
      assert.equal(JSON.stringify(tanks), authority)
    },
  )

// Preserve the previous independent filter/map construction as a trail oracle
// while production builds the same immutable output without temporary arrays.
function originalTrail(f, at, shell) {
  if (f.kind === "rapid") return []
  const points = f.points,
    tailTick = Math.max(f.startTick, at - 6)
  let tail = points[0]
  for (let i = 1; i < points.length; i++)
    if (points[i].tick >= tailTick) {
      const previous = points[i - 1],
        next = points[i],
        span = next.tick - previous.tick,
        fraction = span > 0 ? Math.max(0, Math.min(1, (tailTick - previous.tick) / span)) : 0
      tail = {
        x: previous.x + (next.x - previous.x) * fraction,
        y: previous.y + (next.y - previous.y) * fraction,
      }
      break
    }
  return [
    { x: tail.x, y: tail.y },
    ...points.filter((p) => p.tick > tailTick && p.tick < at).map((p) => ({ x: p.x, y: p.y })),
    { x: shell.x, y: shell.y },
  ]
}
for (const kind of ["regular", "rapid", "scatter", "homing", "grenade", "cannon"])
  test(
    kind + " trail construction exactly matches original through clipped tails and instantaneous reflections",
    () => {
      for (const count of [2, 3, 32])
        for (const instant of [false, true]) {
          const { cache, events } = retainedBatch({ count: 1, contacts: 0, kind, points: count })
          cache.reset()
          const f = events[0].flight
          f.startTick = 10
          f.endTick = instant ? 10 : 30
          f.points.forEach((point, i) => {
            point.tick = instant ? 10 : 10 + (20 * i) / (count - 1)
            point.x = i === 0 ? -0 : point.x
          })
          cache.accept(events, 0)
          for (const [i, at] of (instant ? [10, 10, 10] : [10, 12.5, 27.5, 30]).entries()) {
            const shells = cache.sample(at, instant ? i * 25 : i * 8)
            assert.equal(shells.length, 1)
            assert.deepEqual(shells[0].trail, originalTrail(f, at, shells[0]))
          }
        }
    },
  )
