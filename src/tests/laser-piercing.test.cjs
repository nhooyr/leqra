"use strict"
const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  vm = require("node:vm")
const { boot, tank, declaration } = require("./godlike426-harness.cjs")

test("Laser pierces all opponents once across reflections while keeping shields, teams, and protection", () => {
  const s = boot({
      cols: 8,
      rows: 5,
      wallList: [
        { x: -4, y: -4, w: 680, h: 8 },
        { x: -4, y: 416, w: 680, h: 8 },
        { x: -4, y: -4, w: 8, h: 428 },
        { x: 668, y: -4, w: 8, h: 428 },
      ],
    }),
    noop = () => {}
  const shooter = tank(0, 90, 210, { team: 1, human: true, power: "laser", powerTime: 10, charges: 3 })
  const shield = tank(1, 190, 210, { team: 2, shield: 10, shieldCharges: 3 }),
    first = tank(2, 290, 210, { team: 2 }),
    protectedTank = tank(3, 390, 210, { team: 2, invulnerable: 1, spawnProtected: true }),
    ally = tank(4, 490, 210, { team: 1 }),
    last = tank(5, 590, 210, { team: 2 })
  Object.assign(s, {
    tanks: [shooter, shield, first, protectedTank, ally, last],
    time: 0,
    POWER: { laser: { color: "#fff" } },
    laserEffect: noop,
    shotSound: noop,
    boom: noop,
    shieldSound: noop,
    burst: noop,
    addRing: noop,
    recordLocalDeath: noop,
    setKiller: noop,
    addLog: noop,
  })
  const hits = []
  s.hurt = (target, bullet) => {
    hits.push(target.id)
    if (target.shield > 0) target.shieldCharges--
    else target.alive = false
    assert.equal(bullet.owner, shooter.id)
  }
  vm.runInContext(declaration("fireLaser"), s)
  const beam = s.laserTrace(shooter)
  assert.deepEqual(
    Array.from(beam.targets, (t) => t.id),
    [1, 2, 5],
  )
  assert.ok(beam.points.length > 3)
  assert.equal(s.fireLaser(shooter), true)
  assert.deepEqual(hits, [1, 2, 5])
  assert.equal(shield.shieldCharges, 2)
  assert.equal(first.alive, false)
  assert.equal(last.alive, false)
  assert.equal(shooter.alive, true)
  assert.equal(ally.alive, true)
  assert.equal(protectedTank.alive, true)
  assert.equal(shooter.charges, 2)
})
