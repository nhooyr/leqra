package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class WeaponTapTest {
    @Test
    fun lastPowerUpChargeDoesNotFireStandardAmmoDuringATap() {
        for (fixed in listOf(false, true)) for (weapon in
            listOf("rapid", "scatter", "homing", "grenade", "laser", "cannon")) {
            for (ticks in listOf(1, 3, 6, 10)) {
                val arena =
                    PracticeArena(
                        42,
                        "TAP",
                        0,
                        0,
                        world = if (fixed) ArenaWorld(1000.0, 1000.0, 12, 12) else null,
                    )
                val tank = arena.snapshot.tanks.first()
                tank.x = 42.0
                tank.y = 42.0
                tank.invulnerable = 0.0
                tank.spawnProtected = false
                PracticeArena.applyPower(tank, weapon)
                tank.charges = 1
                tank.machineRounds = 1
                val epoch = tank.ammoEpoch + 1
                arena.captureFire(tank.id, true)
                repeat(ticks) { arena.step(GameInput(fire = true), 1.0 / 60) }
                arena.captureFire(tank.id, false)
                repeat(30) { arena.step(GameInput(), 1.0 / 60) }
                assertEquals(weapon, "", tank.power)
                assertFalse(
                    "A single $ticks-tick $weapon tap must not fire standard ammo, fixed=$fixed",
                    arena.snapshot.bullets.any { it.kind.isEmpty() && it.ammoEpoch == epoch },
                )
            }
        }
    }
}
