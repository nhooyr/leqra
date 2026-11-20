package com.leqra.core

import kotlin.math.hypot
import org.junit.Assert.*
import org.junit.Test

class ShotgunTuningTest {
    private fun arena(finite: Boolean, boosted: Boolean = false): PracticeArena {
        val arena =
            PracticeArena(
                42,
                "RELOAD",
                0,
                0,
                world = if (finite) ArenaWorld(1000.0, 1000.0) else null,
            )
        arena.snapshot.tanks.first().apply {
            x = 42.0
            y = 42.0
            angle = 0.0
            spawnProtected = false
            invulnerable = 0.0
        }
        PracticeArena.applyPower(arena.snapshot.tanks.first(), "scatter")
        if (boosted) PracticeArena.applyPower(arena.snapshot.tanks.first(), "starman")
        return arena
    }

    @Test
    fun fixedAndInfinityShotgunReloadInSeventeenTicksWithoutChangingPellets() {
        val spec = PracticeArena.spec("scatter")
        assertEquals(.27, spec.cooldown, 1e-12)
        assertEquals(3.5, spec.radius, 0.0)
        assertEquals(3.9, spec.life, 0.0)
        assertEquals(12, spec.capacity)
        for (finite in listOf(false, true)) {
            val arena = arena(finite)
            val tank = arena.snapshot.tanks.first()
            arena.step(GameInput(fire = true), 1.0 / 60)
            assertEquals(.27, tank.cooldownTotal, 1e-12)
            assertEquals(4, tank.charges)
            assertEquals(3, arena.snapshot.bullets.size)
            for (pellet in arena.snapshot.bullets) {
                assertEquals("scatter", pellet.kind)
                assertEquals(846.0, hypot(pellet.vx, pellet.vy), 1e-8)
                assertEquals(3.9 - 1.0 / 60, pellet.life, 1e-8)
            }
            repeat(16) { arena.step(GameInput(fire = true), 1.0 / 60) }
            assertEquals("No volley before reload expiry", 4, tank.charges)
            arena.step(GameInput(fire = true), 1.0 / 60)
            assertEquals(3, tank.charges)
            assertTrue(arena.snapshot.effects.any { it.kind == "shot:scatter" })
        }
    }

    @Test
    fun shotgunReadinessFallbackMatchesTheNewRateAndKeepsItsCapacity() {
        for (infinity in listOf(false, true)) {
            val tank =
                ArenaTank(id = 1, cooldown = .135, powerTime = 15.0, power = "scatter", charges = 5)
            val readout = PilotReadout(tank, ArenaSnapshot(tanks = listOf(tank)), infinity)
            assertEquals(.5, readout.progress, 1e-12)
            assertEquals(12, readout.capacity)
        }
    }

    @Test
    fun starmanShotgunRetainsZeroReloadAndFreeCharges() {
        for (finite in listOf(false, true)) {
            val arena = arena(finite, boosted = true)
            val pellets = mutableSetOf<Int>()
            repeat(8) {
                arena.step(GameInput(fire = true), 1.0 / 60)
                pellets.addAll(arena.snapshot.bullets.map { it.id })
            }
            val tank = arena.snapshot.tanks.first()
            assertEquals(0.0, tank.cooldown, 0.0)
            assertEquals(0.0, tank.cooldownTotal, 0.0)
            assertEquals(5, tank.charges)
            assertEquals(24, pellets.size)
            assertEquals(1.0, PilotReadout(tank, arena.snapshot, !finite).progress, 0.0)
        }
    }
}
