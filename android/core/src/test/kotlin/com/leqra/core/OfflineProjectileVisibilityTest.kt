package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class OfflineProjectileVisibilityTest {
    @Test
    fun winningInfinityProjectileFinishesAfterTheSimulationFreezesAtItsResult() {
        val arena = PracticeArena(123, "P1", 0, 1)
        arena.configure(RoomRules(infinity = true, infinityTarget = 1))
        arena.snapshot.tanks.first().apply { x = 100.0; y = 100.0; angle = 0.0; invulnerable = 0.0; spawnProtected = false }
        arena.snapshot.tanks[1].apply { x = 140.0; y = 100.0; invulnerable = 0.0; spawnProtected = false }
        PracticeArena.applyPower(arena.snapshot.tanks.first(), "cannon")
        arena.step(GameInput(fire = true), 1.0 / 60)
        assertNotNull(arena.snapshot.result)
        val tick = arena.snapshot.tick
        val score = arena.snapshot.tanks.first().score
        assertTrue(arena.presentationSnapshot(0.0, nowSeconds = 10.0).bullets.any { it.kind == "cannon" })
        assertFalse(arena.presentationSnapshot(0.0, nowSeconds = 10.1).bullets.any { it.kind == "cannon" })
        assertEquals(tick, arena.snapshot.tick)
        assertEquals(score, arena.snapshot.tanks.first().score)
    }
    @Test
    fun closeRangeKillingShotsRemainVisibleEvenWhenTheyNeverReachASnapshot() {
        for (kind in listOf("", "rapid", "scatter", "homing", "grenade", "cannon")) {
            val arena =
                PracticeArena(123, "P1", 0, 0, world = ArenaWorld(width = 1000.0, height = 1000.0))
            arena.snapshot.tanks.first().apply {
                x = 100.0
                y = 100.0
                angle = 0.0
                invulnerable = 0.0
                spawnProtected = false
            }
            arena.snapshot.tanks +=
                ArenaTank(id = 2, name = "Target", x = 140.0, y = 100.0, bot = true)
            if (kind.isNotEmpty()) PracticeArena.applyPower(arena.snapshot.tanks.first(), kind)
            arena.step(GameInput(fire = true), 1.0 / 60)
            assertEquals(
                "The authoritative close shot should still kill $kind",
                0,
                arena.snapshot.tanks[1].hp,
            )
            val authoritative = arena.snapshot.tanks.map { it.copy() }
            val terminalIDs = arena.snapshot.effects.mapNotNull { it.flight?.id }.toSet()
            val initial = arena.presentationSnapshot(0.0, nowSeconds = 10.0)
            assertTrue(
                "The terminal projectile must be visible for $kind",
                initial.bullets.any { it.kind == kind || kind.isEmpty() && it.kind == "regular" },
            )
            val later = arena.presentationSnapshot(0.0, nowSeconds = 10.025)
            assertTrue(later.bullets.isNotEmpty())
            val ended = arena.presentationSnapshot(0.0, nowSeconds = 10.1)
            assertFalse(ended.bullets.any { it.id in terminalIDs })
            assertEquals(authoritative, arena.snapshot.tanks)
        }
    }

    @Test
    fun terminalFlightContinuesWhenAnEliminationRoundEnds() {
        val arena =
            FixedArena(
                RoomRules(mode = "elimination", mapSize = "compact"),
                "P1",
                0,
                1,
                "dumb",
                123,
            )
        repeat(181) { arena.step(GameInput(), 1.0 / 60) }
        val first = arena.combat.snapshot.tanks.first()
        val target = arena.combat.snapshot.tanks[1]
        first.apply {
            x = 100.0
            y = 100.0
            angle = 0.0
            invulnerable = 0.0
            spawnProtected = false
        }
        target.apply {
            x = 140.0
            y = 100.0
            invulnerable = 0.0
            spawnProtected = false
        }
        PracticeArena.applyPower(first, "cannon")
        arena.step(GameInput(fire = true), 1.0 / 60)
        assertNotEquals("playing", arena.snapshot.phase)
        assertTrue(
            arena.presentationSnapshot(0.0, nowSeconds = 20.0).bullets.any { it.kind == "cannon" }
        )
        assertFalse(
            arena.presentationSnapshot(0.0, nowSeconds = 20.1).bullets.any { it.kind == "cannon" }
        )
    }
}
