package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class PressFireFeedbackTest {
    private fun tank(power: String = "") =
        ArenaTank(
            id = 1,
            spawnSerial = 1,
            power = power,
            ammoUsed = 115,
            charges = 0,
            machineRounds = 0,
        )

    @Test
    fun dryAmmoClassificationUsesCurrentBanksWeaponNeedsAndUnlimitedStar() {
        fun empty(
            tank: ArenaTank,
            bullets: List<ArenaBullet> = emptyList(),
            boosted: List<Int> = emptyList(),
        ) =
            PressFireFeedback.ammoUnavailable(
                tank,
                ArenaSnapshot(tanks = listOf(tank), bullets = bullets, boostedBulletIds = boosted),
            )
        assertTrue(empty(tank().copy(ammoUsed = 5)))
        assertFalse(empty(tank().copy(ammoUsed = 4)))
        assertTrue(empty(tank("scatter").copy(charges = 5, ammoUsed = 10)))
        assertFalse(empty(tank("scatter").copy(charges = 5, ammoUsed = 9)))
        assertTrue(empty(tank("rapid").copy(machineRounds = 0, ammoUsed = 0)))
        assertTrue(empty(tank("rapid").copy(machineRounds = 180, ammoUsed = 115)))
        assertFalse(empty(tank("rapid").copy(machineRounds = 180, ammoUsed = 114)))
        for (power in listOf("scatter", "homing", "laser", "cannon")) {
            assertTrue(empty(tank(power).copy(ammoUsed = 0)))
            assertFalse(empty(tank(power).copy(charges = 1, ammoUsed = 0)))
        }
        val pilot = tank().copy(ammoUsed = 0, ammoEpoch = 7)
        val old = List(5) { ArenaBullet(id = it + 1, owner = 1, ammoEpoch = 6) }
        assertFalse(empty(pilot, old))
        val current = old.map { it.copy(ammoEpoch = 7) }
        assertTrue(empty(pilot, current))
        assertFalse(empty(pilot, current, boosted = current.map { it.id }))
        assertFalse(empty(tank("rapid").copy(starmanTime = 1.0)))
        val feedback = PressFireFeedback()
        assertTrue(feedback.controls(true, pilot, 0, true, 0.0))
        assertFalse(feedback.controls(true, pilot, 0, true, .5))
    }

    @Test
    fun anEmptyFreshPressHasOneHundredMillisecondLinearRecoilWithoutChangingAuthority() {
        val feedback = PressFireFeedback()
        val tank = tank()
        val before = tank.copy()
        feedback.controls(true, tank, 7, true, 0.0)
        assertEquals(1.0, feedback.pulse(tank, 7, true, 0.0), 1e-12)
        assertEquals(.5, feedback.pulse(tank, 7, true, .05), 1e-12)
        assertEquals(0.0, feedback.pulse(tank, 7, true, .1), 1e-12)
        feedback.controls(true, tank, 7, true, .4)
        assertEquals(0.0, feedback.pulse(tank, 7, true, .4), 1e-12)
        assertEquals(before, tank)
    }

    @Test
    fun weaponEndingWhileHeldCannotInventAStandardPulseOrDryClick() {
        for (power in listOf("rapid", "scatter", "homing", "grenade", "laser", "cannon")) {
            val feedback = PressFireFeedback()
            val tank = tank(power).copy(ammoUsed = 0, charges = 1, machineRounds = 1)
            feedback.controls(true, tank, 1, true, 0.0)
            tank.power = ""
            AmmoEpoch.refill(tank)
            val before = tank.copy()
            assertFalse(
                "Held $power end is not a new accepted press",
                feedback.controls(true, tank, 1, true, .2),
            )
            assertEquals(0.0, feedback.pulse(tank, 1, true, .2), 0.0)
            assertFalse(
                PressFireFeedback.ammoUnavailable(tank, ArenaSnapshot(tanks = listOf(tank))),
            )
            assertEquals(before, tank)
            feedback.controls(false, tank, 1, true, .4)
            assertTrue(feedback.controls(true, tank, 1, true, .8))
        }
    }

    @Test
    fun blockedPressesAreConsumedAndWeaponCadencesMatchTheWeb() {
        for ((power, cadence) in
            listOf(
                "" to .34,
                "rapid" to .15,
                "scatter" to .27,
                "homing" to .36,
                "laser" to .85 / 3,
                "cannon" to .85 / 3,
            )) {
            val feedback = PressFireFeedback()
            val tank = tank(power)
            assertTrue(feedback.controls(true, tank, 0, true, 0.0))
            feedback.controls(false, tank, 0, true, .01)
            feedback.controls(true, tank, 0, true, cadence - .001)
            feedback.controls(true, tank, 0, true, cadence + .2)
            assertEquals(
                "Held/early repress cannot create a later pulse: $power",
                0.0,
                feedback.pulse(tank, 0, true, cadence + .2),
                1e-12,
            )
            feedback.controls(false, tank, 0, true, cadence + .201)
            feedback.controls(true, tank, 0, true, cadence + .202)
            assertEquals(1.0, feedback.pulse(tank, 0, true, cadence + .202), 1e-12)
        }
    }

    @Test
    fun starUsesSixtyFiveMillisecondsAndNetworkTimersUseAuthorityAge() {
        val feedback = PressFireFeedback()
        val tank =
            tank().apply {
                starmanTime = 1.0
                cooldown = 1.0
            }
        feedback.controls(true, tank, 0, true, 0.0)
        feedback.controls(false, tank, 0, true, .01)
        feedback.controls(true, tank, 0, true, .065)
        assertEquals(1.0, feedback.pulse(tank, 0, true, .065), 1e-12)
        feedback.reset()
        tank.starmanTime = 0.0
        tank.cooldown = .2
        tank.spawnProtected = true
        tank.invulnerable = .2
        feedback.controls(true, tank, 0, true, 1.0, authorityAge = .21)
        assertEquals(1.0, feedback.pulse(tank, 0, true, 1.0), 1e-12)
    }

    @Test
    fun deadPausedProtectedCooldownGrenadeAndDetonationStatesDoNotPulse() {
        val tanks =
            listOf(
                tank().apply { hp = 0 },
                tank().apply {
                    spawnProtected = true
                    invulnerable = 1.0
                },
                tank().apply { cooldown = .2 },
                tank("grenade"),
                tank().apply { grenades = 1 },
            )
        for (tank in tanks) {
            val feedback = PressFireFeedback()
            assertFalse(feedback.controls(true, tank, 0, true, 0.0))
            tank.hp = 1
            tank.spawnProtected = false
            tank.invulnerable = 0.0
            tank.cooldown = 0.0
            tank.power = ""
            tank.grenades = 0
            assertFalse(feedback.controls(true, tank, 0, true, .5))
            assertEquals(0.0, feedback.pulse(tank, 0, true, .5), 1e-12)
        }
        val feedback = PressFireFeedback()
        val tank = tank()
        feedback.controls(true, tank, 0, false, 0.0)
        feedback.controls(true, tank, 0, true, .5)
        assertEquals(0.0, feedback.pulse(tank, 0, true, .5), 1e-12)
    }

    @Test
    fun quickTapsSurviveUntilDrawButLifeSceneOwnershipAndControlResetClearThem() {
        val feedback = PressFireFeedback()
        val tank = tank()
        feedback.controls(true, tank, 1, true, 0.0)
        feedback.controls(false, tank, 1, true, .001)
        assertTrue(feedback.pulse(tank, 1, true, .008) > .9)
        assertEquals(0.0, feedback.pulse(tank.copy(spawnSerial = 2), 1, true, .009), 0.0)
        feedback.controls(true, tank, 1, true, .02)
        assertEquals(0.0, feedback.pulse(tank, 2, true, .021), 0.0)
        feedback.controls(false, tank, 2, true, .03)
        feedback.controls(true, tank, 2, true, .04)
        assertEquals(0.0, feedback.pulse(tank.copy(id = 2), 2, true, .041), 0.0)
        feedback.reset(true)
        feedback.controls(true, tank, 2, true, .5)
        assertEquals(0.0, feedback.pulse(tank, 2, true, .5), 0.0)
        val other = PressFireFeedback()
        other.controls(true, tank.copy(id = 2), 2, true, .5)
        assertEquals(1.0, other.pulse(tank.copy(id = 2), 2, true, .5), 1e-12)
        assertEquals(0.0, feedback.pulse(tank, 2, true, .5), 0.0)
    }
}
