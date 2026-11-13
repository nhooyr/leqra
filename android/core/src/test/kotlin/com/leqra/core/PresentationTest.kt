package com.leqra.core

import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class PresentationTest {
    private fun read(
        t: ArenaTank,
        state: ArenaSnapshot = ArenaSnapshot(tanks = listOf(t)),
        infinity: Boolean = false,
        paused: Boolean = false,
        online: Boolean = true,
    ) = PilotReadout(t, state, infinity, paused, online)

    @Test
    fun everyWeaponHasCorrectCapacityAndLaserUsesCharges() {
        for ((power, capacity) in
            listOf(
                "" to 5,
                "rapid" to 115,
                "scatter" to 12,
                "homing" to 3,
                "grenade" to 3,
                "laser" to 3,
                "cannon" to 3,
            )) {
            val t =
                ArenaTank(id = 1, powerTime = 5.0, power = power, charges = 3, machineRounds = 180)
            assertEquals(capacity, read(t).capacity)
            assertEquals(capacity, read(t).available)
        }
        val laser = read(ArenaTank(id = 1, powerTime = 4.01, power = "laser", charges = 2))
        assertEquals(2, laser.available)
        assertEquals("LASER ×2, 5s", laser.weapon)
    }

    @Test
    fun ordinaryAmmoExcludesOtherOwnersAndBoostedBullets() {
        val tank = ArenaTank(id = 1)
        val state =
            ArenaSnapshot(
                tanks = listOf(tank),
                bullets =
                    listOf(
                        ArenaBullet(id = 1, owner = 1),
                        ArenaBullet(id = 2, owner = 1),
                        ArenaBullet(id = 3, owner = 1),
                        ArenaBullet(id = 4, owner = 2),
                    ),
                boostedBulletIds = listOf(2, 3),
            )
        val r = read(tank, state)
        assertEquals(4, r.available)
        assertEquals("READY", r.readiness)
        assertEquals("STANDARD", r.weapon)
    }

    @Test
    fun authoritativeAmmoSurvivesDelayedProjectileDisplay() {
        val r = read(ArenaTank(id = 1, ammoUsed = 5))
        assertEquals(0, r.available)
        assertEquals("WAITING FOR AMMO", r.readiness)
        assertEquals("WAIT", r.fireLabel)
    }

    @Test
    fun machineGunHasThreeSecondsOfFiringBudgetIndependentFromPickupTimer() {
        val t = ArenaTank(id = 1, powerTime = 15.0, power = "rapid", machineRounds = 180)
        assertEquals(3.0, read(t).firingSeconds!!, 0.0)
        assertEquals("MACHINE GUN, EXPIRES 15s", read(t).weapon)
        t.machineRounds = 114
        t.powerTime = 13.0
        assertEquals(1.9, read(t).firingSeconds!!, 0.0)
    }

    @Test
    fun starmanOverridesCooldownAmmoAndMachineGunBudget() {
        val t =
            ArenaTank(
                id = 1,
                cooldown = 1.0,
                cooldownTotal = 1.0,
                powerTime = 15.0,
                starmanTime = 3.1,
                power = "rapid",
                machineRounds = 12,
                ammoUsed = 115,
            )
        val r = read(t, infinity = true)
        assertTrue(r.unlimited)
        assertNull(r.firingSeconds)
        assertEquals("MACHINE GUN, ∞ AMMO", r.weapon)
        assertEquals("STAR 4s", r.buffs)
        assertEquals("READY", r.readiness)
        assertEquals(1.0, r.progress, 0.0)
    }

    @Test
    fun boostedGrenadeRetainsDetonationWithoutUsingAmmoSlot() {
        val t = ArenaTank(id = 1, powerTime = 15.0, power = "grenade", charges = 3)
        val state =
            ArenaSnapshot(
                tanks = listOf(t),
                bullets = listOf(ArenaBullet(id = 9, owner = 1, kind = "grenade", life = 7.24)),
                boostedBulletIds = listOf(9),
            )
        val r = read(t, state)
        assertEquals(3, r.available)
        assertEquals("GRENADE, 7.2s", r.weapon)
        assertEquals("DETONATE READY", r.readiness)
        assertEquals("BOOM", r.fireLabel)
        assertEquals("TAP TO DETONATE", r.fireHint)
    }

    @Test
    fun infinityReadsOffscreenGrenadeAndAmmoMetadata() {
        val t =
            ArenaTank(
                id = 1,
                grenadeLife = 4.5,
                power = "grenade",
                charges = 2,
                ammoUsed = 3,
                grenades = 1,
            )
        val ready = read(t, infinity = true)
        assertEquals(0, ready.available)
        assertEquals("DETONATE READY", ready.readiness)
        assertEquals("GRENADE, 4.5s", ready.weapon)
        t.grenadeLife = 0.0
        assertEquals("WAITING FOR AMMO", read(t, infinity = true).readiness)
    }

    @Test
    fun cooldownUsesWeaponProgressAndWebRounding() {
        val t = ArenaTank(id = 1, cooldown = .17)
        val half = read(t)
        assertEquals(.5, half.progress, 1e-12)
        assertEquals("COOLDOWN 0.2s", half.readiness)
        t.cooldown = .25
        assertEquals("COOLDOWN 0.3s", read(t).readiness)
        t.cooldown = 0.0
        t.ghostTime = 5.0
        assertEquals("READY", read(t).readiness)
        assertEquals("FIRE", read(t).fireLabel)
    }

    @Test
    fun spawnProtectionSuppressesFireAndLockWarning() {
        val r =
            read(
                ArenaTank(id = 1, spawnProtected = true, invulnerable = .5, locked = true),
                infinity = true,
            )
        assertEquals("SPAWN PROTECTION", r.readiness)
        assertEquals("WAIT", r.fireLabel)
        assertEquals("WAIT TO FIRE", r.fireHint)
        assertEquals(0.0, r.progress, 0.0)
        assertFalse(r.locked)
    }

    @Test
    fun fixedMatchPhasesTakePriorityOverOldLife() {
        val dead = ArenaTank(id = 1, hp = 0, respawnTime = 1.0)
        for ((phase, text, label, progress) in
            listOf(
                listOf("countdown", "GET READY", "FIRE", 0.0),
                listOf("roundOver", "ROUND COMPLETE", "DONE", 1.0),
                listOf("matchOver", "MATCH COMPLETE", "DONE", 1.0),
            )) {
            val r = read(dead, ArenaSnapshot(tanks = listOf(dead), phase = phase as String))
            assertEquals(text, r.readiness)
            assertEquals(label, r.fireLabel)
            assertEquals(progress as Double, r.progress, 0.0)
            assertEquals("", r.weapon)
            assertEquals(0, r.available)
        }
    }

    @Test
    fun deathReadinessDistinguishesEliminationObjectivesAndSurvival() {
        val dead = ArenaTank(id = 1, hp = 0, respawnTime = 2.4)
        for ((mode, text) in
            listOf(
                "elimination" to "OUT",
                "ctf" to "RESPAWN 2.4s",
                "koth" to "RESPAWN 2.4s",
                "survival" to "BACK NEXT WAVE",
            )) {
            val r = read(dead, ArenaSnapshot(objectives = ArenaObjectives(mode = mode)))
            assertEquals(text, r.readiness)
            assertEquals("OUT", r.fireLabel)
        }
        assertEquals(
            "OUT",
            read(
                    dead,
                    ArenaSnapshot(objectives = ArenaObjectives(mode = "ctf", suddenDeath = true)),
                )
                .readiness,
        )
    }

    @Test
    fun survivalBreakHasOneStatusEvenWhenFallen() {
        val dead = ArenaTank(id = 1, hp = 0)
        val r =
            read(
                dead,
                ArenaSnapshot(
                    objectives =
                        ArenaObjectives(
                            mode = "survival",
                            survival = ArenaSurvival(wave = 2, breakTime = 1.2, status = "break"),
                        ),
                ),
            )
        assertEquals("NEXT WAVE 2s", r.readiness)
        assertEquals("WAIT", r.fireLabel)
        assertEquals("NEXT WAVE", r.fireHint)
    }

    @Test
    fun infinityPauseDistinguishesOnlineHeldRespawnAndOfflinePause() {
        val dead = ArenaTank(id = 1, hp = 0, respawnTime = .8)
        assertEquals(
            "RESPAWN HELD",
            read(dead, infinity = true, paused = true, online = true).readiness,
        )
        assertEquals(
            "RESPAWN 0.8s",
            read(dead, infinity = true, paused = true, online = false).readiness,
        )
        val r = read(ArenaTank(id = 1, locked = true), infinity = true, paused = true)
        assertEquals("PAUSED", r.readiness)
        assertFalse(r.locked)
    }

    @Test
    fun buffsCompactExactlyLikeTheWeb() {
        val t = ArenaTank(id = 1, shield = 2.1, speedTime = 4.1, ghostTime = 1.1)
        assertEquals("SHD×1 SPD×15 GHO2", read(t).buffs)
        val stale = ArenaTank(id = 1, shieldCharges = 4)
        assertEquals("", read(stale).buffs)
        stale.shield = 2.0
        assertEquals("SHD×4 2s", read(stale).buffs)
    }

    @Test
    fun friendlyHomingLockHonorsTeamAndFriendlyFire() {
        val t = ArenaTank(id = 1, team = 1)
        val owner = ArenaTank(id = 2, team = 1)
        val state =
            ArenaSnapshot(
                tanks = listOf(t, owner),
                rules = RoomRules(friendlyFire = false),
                bullets =
                    listOf(ArenaBullet(id = 9, owner = 2, kind = "homing", target = 1, life = 2.0)),
            )
        assertFalse(read(t, state).locked)
        state.rules!!.friendlyFire = true
        assertTrue(read(t, state).locked)
        state.rules!!.friendlyFire = false
        owner.team = 2
        assertTrue(read(t, state).locked)
    }

    @Test
    fun winningSideIncludesTeamButNotFfaOrMissingPilots() {
        val team =
            ArenaSnapshot(
                tanks = listOf(ArenaTank(id = 1, team = 2), ArenaTank(id = 3, team = 2)),
                winner = 3,
            )
        assertEquals(true, team.isWinningSide(1))
        assertEquals(true, team.isWinningSide(3))
        team.tanks[0].team = 0
        assertEquals(false, team.isWinningSide(1))
        assertNull(team.isWinningSide(99))
        assertNull(team.copy(winner = -1).isWinningSide(1))
    }

    @Test
    fun independentP2PresentationPreservesPoseWhenControlsChangeBetweenTicks() {
        val world = ArenaWorld(8400.0, 8400.0, 100, 100)
        val a = PracticeArena(42, "P1", 0, 0, world = world)
        a.configureLocal("P2", 1)
        a.snapshot.tanks =
            listOf(
                ArenaTank(
                    id = 1,
                    x = 4000.0,
                    y = 4000.0,
                    speedTime = 100.0,
                    ghostTime = 100.0,
                    speedStacks = 5,
                ),
                ArenaTank(
                    id = 2,
                    x = 4200.0,
                    y = 4200.0,
                    speedTime = 100.0,
                    ghostTime = 100.0,
                    speedStacks = 5,
                ),
            )
        val forward = GameInput(forward = true)
        val before = a.presentationSnapshot(.5, GameInput(), forward).tanks.first { it.id == 2 }
        for (input in listOf(GameInput(), GameInput(reverse = true), GameInput(stickY = 1.0))) {
            val after = a.presentationSnapshot(.5, GameInput(), input).tanks.first { it.id == 2 }
            assertEquals(before.x, after.x, 1e-9)
            assertEquals(before.y, after.y, 1e-9)
            assertEquals(before.angle, after.angle, 1e-9)
        }
        assertEquals(4200.0, a.snapshot.tanks[1].x, 0.0)
        assertEquals(4000.0, a.snapshot.tanks[0].x, 0.0)
    }
}
