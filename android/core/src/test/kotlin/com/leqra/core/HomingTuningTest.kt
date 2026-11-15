package com.leqra.core

import kotlin.math.hypot
import org.junit.Assert.*
import org.junit.Test

class HomingTuningTest {
    private val dt = 1.0 / 60

    private fun arena(fixed: Boolean, boosted: Boolean = false) =
        PracticeArena(42, "RELOAD", 0, 0, world = if (fixed) ArenaWorld(1000.0, 1000.0) else null).apply {
            snapshot.tanks.first().apply { x = 42.0; y = 42.0; angle = 0.0; invulnerable = 0.0; spawnProtected = false }
            PracticeArena.applyPower(snapshot.tanks.first(), "homing")
            if (boosted) PracticeArena.applyPower(snapshot.tanks.first(), "starman")
        }

    @Test fun heldMissilesReloadInTwentyTwoTicksWithUnchangedSpeedRangeAndCharges() {
        val spec = PracticeArena.spec("homing")
        assertEquals(.36, spec.cooldown, 1e-12)
        assertEquals(235.0, spec.speed, 0.0)
        assertEquals(5.0, spec.radius, 0.0)
        assertEquals(18 * 84.0 / 235, spec.life, 0.0)
        assertEquals(3, spec.capacity)
        for (fixed in listOf(false, true)) {
            val arena = arena(fixed)
            val tank = arena.snapshot.tanks.first()
            assertEquals(3, tank.charges)
            arena.step(GameInput(fire = true), dt)
            assertEquals(.36, tank.cooldownTotal, 1e-12)
            assertEquals(2, tank.charges)
            val missile = arena.snapshot.bullets.single()
            assertEquals("homing", missile.kind)
            assertEquals(235.0, hypot(missile.vx, missile.vy), 1e-8)
            val life = if (fixed) 2000.0 / 235 + .5 else spec.life
            assertEquals(life - dt, missile.life, 1e-8)
            repeat(21) { arena.step(GameInput(fire = true), dt) }
            assertEquals("No missile before the reload expires", 2, tank.charges)
            arena.step(GameInput(fire = true), dt)
            assertEquals("Held fire launches the second missile after 22 ticks", 1, tank.charges)
        }
    }

    @Test fun missileReadinessFallbackMatchesTheNewReloadAndHonorsExplicitServerTiming() {
        for (infinity in listOf(false, true)) {
            val tank = ArenaTank(id = 1, power = "homing", powerTime = 15.0, charges = 3, cooldown = .18)
            val state = ArenaSnapshot(tanks = listOf(tank))
            val readout = PilotReadout(tank, state, infinity)
            assertEquals(.5, readout.progress, 1e-12)
            assertEquals(3, readout.capacity)
            tank.cooldownTotal = .72
            assertEquals(.75, PilotReadout(tank, state, infinity).progress, 1e-12)
        }
    }

    @Test fun starmanMissilesStillUseZeroReloadAndFreeCharges() {
        for (fixed in listOf(false, true)) {
            val arena = arena(fixed, boosted = true)
            val missiles = mutableSetOf<Int>()
            repeat(8) {
                arena.step(GameInput(fire = true), dt)
                missiles.addAll(arena.snapshot.bullets.map { it.id })
            }
            val tank = arena.snapshot.tanks.first()
            assertEquals(8, missiles.size)
            assertEquals(0.0, tank.cooldown, 0.0)
            assertEquals(0.0, tank.cooldownTotal, 0.0)
            assertEquals(3, tank.charges)
        }
    }
}
