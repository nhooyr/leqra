package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class AmmoResetTest {
    private val dt = 1.0 / 60
    private val weapons = listOf("rapid", "scatter", "homing", "grenade", "laser", "cannon")
    private fun arena(fixed: Boolean = true) = PracticeArena(42, "Pilot", 0, 0,
        world = if (fixed) ArenaWorld(10000.0, 10000.0, 120, 120) else null).apply {
        snapshot.tanks.first().apply { x = if (fixed) 5000.0 else 42.0; y = x; invulnerable = 0.0; spawnProtected = false }
    }
    private fun shots(arena: PracticeArena) = arena.snapshot.effects.count { it.kind.startsWith("shot:") || it.kind == "laser" }
    private fun full(tank: ArenaTank, power: String, epoch: Long, remoteGrenades: Int = 0, cooldown: Double = 0.0) {
        assertEquals(power, tank.power)
        assertEquals(epoch, tank.ammoEpoch)
        assertEquals(cooldown, tank.cooldown, 0.0); assertEquals(cooldown, tank.cooldownTotal, 0.0)
        assertEquals(0, tank.ammoUsed); assertEquals(remoteGrenades, tank.grenades)
        if (remoteGrenades == 0) assertEquals(0.0, tank.grenadeLife, 0.0) else assertTrue(tank.grenadeLife > 0)
        assertEquals(if (power == "scatter") 5 else if (power in weapons && power != "rapid") 3 else 0, tank.charges)
        assertEquals(if (power == "rapid") 180 else 0, tank.machineRounds)
    }

    @Test fun everyPickupRefillsTheEquippedWeaponAndClearsCooldownWithoutRemovingBuffs() {
        for (kind in PracticeArena.pickupKinds) {
            val tank = ArenaTank(id = 1, power = "cannon", powerTime = 10.0, charges = 1, cooldown = .8,
                cooldownTotal = .8, ammoUsed = 3, grenades = 1, grenadeLife = 5.0, ammoEpoch = 7)
            PracticeArena.applyPower(tank, kind)
            full(tank, if (kind in weapons) kind else "cannon", 8)
            when (kind) {
                "shield" -> assertTrue(tank.shield > 0)
                "speed" -> assertTrue(tank.speedTime > 0)
                "ghost" -> assertTrue(tank.ghostTime > 0)
                "starman" -> assertTrue(tank.starmanTime > 0)
            }
        }
        val wrapped = ArenaTank(ammoEpoch = AmmoEpoch.maximum)
        PracticeArena.applyPower(wrapped, "speed")
        assertEquals(1L, wrapped.ammoEpoch)
    }

    @Test fun everyTimerEndRefillsOnceAndWeaponEndReturnsToFullStandardAmmo() {
        for (fixed in listOf(false, true)) for (kind in PracticeArena.pickupKinds) {
            val arena = arena(fixed)
            val tank = arena.snapshot.tanks.first()
            PracticeArena.applyPower(tank, "cannon")
            PracticeArena.applyPower(tank, kind, duration = .001, starDuration = .001)
            tank.cooldown = .7; tank.cooldownTotal = .7; tank.charges = 1; tank.ammoUsed = 3
            val epoch = tank.ammoEpoch
            arena.step(GameInput(), dt)
            full(tank, if (kind in weapons) "" else "cannon", epoch + 1)
            assertEquals(if (kind in weapons) 5 else 3, PilotReadout(tank, arena.snapshot, !fixed).available)
        }
        val arena = arena()
        val tank = arena.snapshot.tanks.first().apply {
            power = "rapid"; powerTime = .001; machineRounds = 1; shield = .001; shieldCharges = 1
            speedTime = .001; speedStacks = 2; ghostTime = .001; starmanTime = .001; cooldown = .7
        }
        arena.step(GameInput(), dt)
        full(tank, "", 1)
    }

    @Test fun everyWeaponDepletionKeepsTryingTheReadyStandardBankWithoutASameTickDoubleShot() {
        for (fixed in listOf(false, true)) for (kind in weapons) {
            val arena = arena(fixed); val tank = arena.snapshot.tanks.first()
            PracticeArena.applyPower(tank, kind)
            if (kind == "rapid") tank.machineRounds = 1 else tank.charges = 1
            val epoch = tank.ammoEpoch
            arena.step(GameInput(fire = true), dt)
            val reload = if (kind == "grenade") .8 else if (kind == "homing") .36 else .34
            full(tank, "", epoch + 1, if (kind == "grenade") 1 else 0, reload)
            assertFalse("Last $kind charge cannot also shoot standard", arena.snapshot.bullets.any { it.kind.isEmpty() })
            repeat(kotlin.math.ceil(reload / dt).toInt()) { arena.step(GameInput(fire = true), dt) }
            assertTrue("Held $kind continues after reload", shots(arena) > 0)
            assertEquals(1, arena.snapshot.bullets.count { it.kind.isEmpty() })
        }
    }

    @Test fun everyHeldWeaponExpiryFiresTheNewBankImmediately() {
        for (fixed in listOf(false, true)) for (kind in weapons) {
            val arena = arena(fixed); val tank = arena.snapshot.tanks.first()
            PracticeArena.applyPower(tank, kind); arena.step(GameInput(fire = true), dt)
            tank.powerTime = .001; val epoch = tank.ammoEpoch; val serial = shots(arena)
            arena.step(GameInput(fire = true), dt)
            assertEquals("", tank.power); assertEquals(epoch + 1, tank.ammoEpoch)
            assertEquals("Held $kind expiry keeps firing", serial + 1, shots(arena))
            assertEquals(1, arena.snapshot.bullets.count { it.kind.isEmpty() })
        }
    }

    @Test fun passiveExpiryKeepsTryingTheCurrentWeaponAndRestoredStandardBank() {
        for (fixed in listOf(false, true)) for (buff in listOf("shield", "speed", "ghost", "starman")) {
            val arena = arena(fixed)
            val tank = arena.snapshot.tanks.first()
            PracticeArena.applyPower(tank, "homing")
            arena.step(GameInput(fire = true), dt)
            PracticeArena.applyPower(tank, buff, duration = .001, starDuration = .001)
            arena.step(GameInput(fire = true), dt)
            assertEquals("Passive $buff expiry retains homing", "homing", tank.power)
            assertEquals("Passive $buff expiry keeps held weapon firing", 2, tank.charges)
            assertEquals(2, arena.snapshot.bullets.count { it.kind == "homing" })

            tank.charges = 1
            tank.cooldown = 0.0
            arena.step(GameInput(fire = true), dt)
            PracticeArena.applyPower(tank, buff, duration = .001, starDuration = .001)
            repeat(8) { arena.step(GameInput(fire = true), dt) }
            assertTrue("Passive $buff expiry keeps held standard firing", arena.snapshot.bullets.any { it.kind.isEmpty() })
            assertEquals(4, PilotReadout(tank, arena.snapshot, !fixed).available)
        }
    }

    @Test fun capturedSubphysicsPressesWorkOnceAndReleaseRearmsEveryDepletedWeapon() {
        for (fixed in listOf(false, true)) for (kind in weapons) {
            val arena = arena(fixed)
            val tank = arena.snapshot.tanks.first()
            PracticeArena.applyPower(tank, kind)
            if (kind == "rapid") tank.machineRounds = 1 else tank.charges = 1
            arena.captureFire(tank.id, true)
            arena.step(GameInput(fire = true), dt)
            assertEquals("", tank.power)
            arena.captureFire(tank.id, false)
            repeat(48) { arena.step(GameInput(), dt) }
            arena.captureFire(tank.id, true)
            arena.captureFire(tank.id, false)
            arena.step(GameInput(), dt)
            if (kind == "grenade") {
                assertFalse(arena.snapshot.bullets.any { it.kind == "grenade" || it.kind.isEmpty() })
                arena.captureFire(tank.id, true)
                arena.captureFire(tank.id, false)
                arena.step(GameInput(), dt)
            }
            assertEquals("A real quick $kind release/repress fires once", 1, arena.snapshot.bullets.count { it.kind.isEmpty() })
            repeat(8) { arena.step(GameInput(), dt) }
            assertEquals(1, arena.snapshot.bullets.count { it.kind.isEmpty() })
        }
        val arena = arena()
        val tank = arena.snapshot.tanks.first()
        tank.spawnProtected = true; tank.invulnerable = 1.0
        arena.captureFire(tank.id, true); arena.captureFire(tank.id, false)
        arena.step(GameInput(), dt)
        tank.spawnProtected = false; tank.invulnerable = 0.0
        arena.step(GameInput(), dt)
        assertTrue("A blocked quick press cannot fire later", arena.snapshot.bullets.isEmpty())
        arena.captureFire(tank.id, true)
        arena.resetFire(tank.id)
        arena.step(GameInput(), dt)
        assertTrue("Reset discards queued press edges", arena.snapshot.bullets.isEmpty())
    }

    @Test fun finalGrenadeAndActualRefillsKeepHeldFireTryingWhileOldFusesStayNatural() {
        for (fixed in listOf(false, true)) {
            val arena = arena(fixed); val tank = arena.snapshot.tanks.first()
            PracticeArena.applyPower(tank, "grenade"); tank.charges = 1
            arena.step(GameInput(fire = true), dt); val grenade = arena.snapshot.bullets.single().id
            repeat(48) { arena.step(GameInput(fire = true), dt) }
            assertEquals(1, arena.snapshot.bullets.count { it.kind.isEmpty() })
            val serial = shots(arena)
            arena.snapshot.pickups = listOf(ArenaPickup(id = 999, x = tank.x, y = tank.y, type = "speed"))
            arena.step(GameInput(fire = true), dt)
            assertEquals(serial + 1, shots(arena)); assertNull(tank.grenadeEpoch)
            assertTrue("A true refill leaves old grenades on natural fuses", arena.snapshot.bullets.any { it.id == grenade })
            PracticeArena.applyPower(tank, "shield", duration = .001)
            arena.step(GameInput(fire = true), dt)
            assertEquals(serial + 2, shots(arena))
        }
    }

    @Test fun finalGrenadeKeepsItsRemoteBankUntilPoppedOrAnActualRefill() {
        for (fixed in listOf(false, true)) for (epoch in listOf(0L, AmmoEpoch.maximum)) {
            val arena = arena(fixed)
            val tank = arena.snapshot.tanks.first()
            PracticeArena.applyPower(tank, "grenade")
            tank.ammoEpoch = epoch
            tank.charges = 1
            arena.step(GameInput(fire = true), dt)
            val grenade = arena.snapshot.bullets.single()
            assertEquals(epoch, grenade.ammoEpoch)
            assertEquals(epoch, tank.grenadeEpoch)
            assertEquals(AmmoEpoch.next(epoch), tank.ammoEpoch)
            full(tank, "", AmmoEpoch.next(epoch), 1, .8)
            val hud = PilotReadout(tank, arena.snapshot, !fixed)
            assertEquals(5, hud.available)
            assertEquals("DETONATE READY", hud.readiness)
            assertEquals("BOOM", hud.fireLabel)
            repeat(48) { arena.step(GameInput(fire = true), dt) }
            assertTrue(arena.snapshot.bullets.any { it.id == grenade.id })
            assertEquals(1, arena.snapshot.bullets.count { it.kind.isEmpty() })
            arena.step(GameInput(), dt)
            arena.step(GameInput(fire = true), dt)
            assertFalse("A fresh press pops the final grenade", arena.snapshot.bullets.any { it.kind == "grenade" })
            assertEquals("Pop does not also shoot", 1, arena.snapshot.bullets.count { it.kind.isEmpty() })
            assertNull(tank.grenadeEpoch)
            tank.cooldown = 0.0
            arena.step(GameInput(fire = true), dt)
            assertEquals("Holding the pop must not shoot standard", 1, arena.snapshot.bullets.count { it.kind.isEmpty() })
            arena.step(GameInput(), dt)
            arena.step(GameInput(fire = true), dt)
            assertEquals("A fresh press fires standard", 2, arena.snapshot.bullets.count { it.kind.isEmpty() })
        }
        for (power in PracticeArena.pickupKinds) {
            val arena = arena()
            val tank = arena.snapshot.tanks.first()
            PracticeArena.applyPower(tank, "grenade")
            tank.charges = 1
            arena.step(GameInput(fire = true), dt)
            val grenade = arena.snapshot.bullets.single().id
            PracticeArena.applyPower(tank, power)
            assertNull("A real $power pickup starts a new remote cycle", tank.grenadeEpoch)
            arena.step(GameInput(), dt)
            assertTrue("Old fuses remain natural", arena.snapshot.bullets.any { it.id == grenade })
        }
    }

    @Test fun oldFlyingShotsKeepTheirQuotaFreePhysicsAndCanStillKillAfterARefill() {
        for (kind in listOf("", "cannon")) {
            val arena = arena()
            val tank = arena.snapshot.tanks.first().apply { x = 100.0; y = 100.0; angle = 0.0 }
            arena.snapshot.tanks += ArenaTank(id = 2, name = "Target", x = 300.0, y = 100.0)
            if (kind.isNotEmpty()) PracticeArena.applyPower(tank, kind)
            arena.step(GameInput(fire = true), dt)
            val old = arena.snapshot.bullets.single().copy()
            PracticeArena.applyPower(tank, "speed")
            arena.step(GameInput(), dt)
            assertTrue(arena.snapshot.bullets.any { it.id == old.id && it.ammoEpoch == old.ammoEpoch })
            assertEquals(0, tank.ammoUsed)
            repeat(60) { if (arena.snapshot.tanks[1].hp > 0) arena.step(GameInput(), dt) }
            assertEquals(0, arena.snapshot.tanks[1].hp)
            assertEquals(1, tank.score)
        }
    }

    @Test fun aNewBankCanFillWhileOldBulletsRemainAndStarmanRecyclingIsBankLocal() {
        val arena = arena()
        val tank = arena.snapshot.tanks.first()
        repeat(5) { tank.cooldown = 0.0; arena.step(GameInput(fire = true), dt) }
        assertEquals(5, tank.ammoUsed)
        val old = arena.snapshot.bullets.map { it.id }.toSet()
        PracticeArena.applyPower(tank, "speed")
        repeat(5) { tank.cooldown = 0.0; arena.step(GameInput(fire = true), dt) }
        assertEquals(5, tank.ammoUsed)
        assertTrue(arena.snapshot.bullets.map { it.id }.containsAll(old))
        assertEquals(10, arena.snapshot.bullets.size)
        val star = arena()
        val pilot = star.snapshot.tanks.first()
        PracticeArena.applyPower(pilot, "starman"); PracticeArena.applyPower(pilot, "scatter")
        repeat(41) { star.step(GameInput(fire = true), dt) }
        val firstBank = pilot.ammoEpoch
        assertEquals(115, star.snapshot.bullets.size)
        PracticeArena.applyPower(pilot, "speed")
        repeat(41) { star.step(GameInput(fire = true), dt) }
        assertEquals(115, star.snapshot.bullets.count { it.ammoEpoch == firstBank })
        assertEquals(115, star.snapshot.bullets.count { it.ammoEpoch == pilot.ammoEpoch })
    }

    @Test fun aRefillPreservesRapidTickGuardAndStartsAFreshHeldGrenadeBank() {
        val arena = arena(); val tank = arena.snapshot.tanks.first()
        PracticeArena.applyPower(tank, "rapid")
        val fire = PracticeArena::class.java.getDeclaredMethod("fireShot", Int::class.javaPrimitiveType).apply { isAccessible = true }
        fire.invoke(arena, 0); PracticeArena.applyPower(tank, "shield"); fire.invoke(arena, 0)
        arena.step(GameInput(fire = true), dt)
        assertEquals(2, arena.snapshot.bullets.size); assertEquals(179, tank.machineRounds)
        val grenades = arena(); val pilot = grenades.snapshot.tanks.first()
        PracticeArena.applyPower(pilot, "grenade"); grenades.step(GameInput(fire = true), dt)
        val old = grenades.snapshot.bullets.single().id
        PracticeArena.applyPower(pilot, "speed"); grenades.step(GameInput(fire = true), dt)
        assertEquals(2, grenades.snapshot.bullets.size); assertEquals(1, pilot.grenades)
        grenades.step(GameInput(), dt); grenades.step(GameInput(fire = true), dt)
        assertEquals("Pop controls only the new bank", listOf(old), grenades.snapshot.bullets.map { it.id })
        pilot.cooldown = 0.0; grenades.step(GameInput(fire = true), dt)
        assertEquals("Held detonation does not throw another grenade", 1, grenades.snapshot.bullets.size)
        grenades.step(GameInput(), dt); grenades.step(GameInput(fire = true), dt)
        assertEquals("Releasing permits the next throw", 2, grenades.snapshot.bullets.size)
    }

    @Test fun finalShieldChargeAndRespawnEachStartAFullBank() {
        val arena = arena()
        val tank = arena.snapshot.tanks.first().apply {
            x = 160.0; y = 100.0; shield = 10.0; shieldCharges = 1
            power = "cannon"; powerTime = 10.0; charges = 1; cooldown = .5; cooldownTotal = .5; ammoEpoch = 8
        }
        arena.snapshot.tanks += ArenaTank(id = 2, name = "Shooter", x = 100.0, y = 100.0, angle = 0.0)
        repeat(12) { if (tank.shield > 0) arena.step(mapOf(1 to GameInput(), 2 to GameInput(fire = true)), dt) }
        assertEquals(1, tank.hp)
        full(tank, "cannon", 9)
        tank.hp = 0; tank.respawnTime = dt
        arena.step(GameInput(), dt)
        val revived = arena.snapshot.tanks.first()
        assertEquals(1, revived.hp)
        full(revived, "", 10)
        assertEquals(5, PilotReadout(revived, arena.snapshot, false).available)
    }

    @Test fun bothOnlineBanksAdoptRefillsWithoutDroppingUnacknowledgedMovement() {
        val timeline = OnlinePresentation(movement = { tank, input, dt -> if (input.forward) tank.x += 60 * dt })
        timeline.setLocalIDs(1, 2)
        fun state(tick: Long, epoch: Long, used: Int, cooldown: Double) = ArenaSnapshot(tick = tick, generation = 1,
            tanks = listOf(ArenaTank(id = 1, x = 100.0, spawnSerial = 1, ammoEpoch = epoch, ammoUsed = used, cooldown = cooldown, cooldownTotal = .34),
                ArenaTank(id = 2, x = 500.0, spawnSerial = 1, ammoEpoch = epoch, ammoUsed = used, cooldown = cooldown, cooldownTotal = .34)))
        timeline.accept(state(0, 7, 5, .34), 0.0)
        repeat(6) { index -> timeline.render(dt / 2, GameInput(forward = true), (index + 1) * dt / 2,
            input2 = GameInput(forward = true), sendLocal = {}) {} }
        val history = timeline.bufferedFrameCount
        assertTrue(history > 0)
        timeline.accept(state(2, 8, 0, 0.0), .05)
        val image = timeline.render(0.0, GameInput(forward = true), .05, input2 = GameInput(forward = true), sendLocal = {}) {}!!
        assertEquals(history, timeline.bufferedFrameCount)
        for (tank in image.tanks) {
            assertEquals(8L, tank.ammoEpoch)
            assertEquals(0, tank.ammoUsed)
            assertEquals(0.0, tank.cooldown, 0.0)
            assertTrue(tank.x > if (tank.id == 1) 100 else 500)
            val readout = PilotReadout(tank, image, true)
            assertEquals(5, readout.available); assertEquals("READY", readout.readiness)
        }
    }
}
