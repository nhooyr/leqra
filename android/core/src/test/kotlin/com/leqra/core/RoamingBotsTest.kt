package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class RoamingBotsTest {
    private fun arena(rate: Double = 2.0): PracticeArena =
        PracticeArena(123, "P1", 0, 0).apply {
            configure(
                RoomRules(
                    infinity = true,
                    infinityRandomBots = true,
                    infinityBotDifficulty = "dumb",
                    infinityBotSpawnRate = rate,
                )
            )
            snapshot.tanks.first().invulnerable = 10000.0
        }

    @Test
    fun ambientBotsArriveInPerHumanWavesAndFillSixteenPerPlayer() {
        val arena = arena()
        arena.configureLocal("P2", 1)
        arena.snapshot.tanks[1].apply {
            x = 10000.0
            y = 10000.0
            invulnerable = 10000.0
        }
        assertEquals(0, arena.snapshot.tanks.count { it.bot })
        arena.step(GameInput(), 1.0 / 60)
        assertEquals(2, arena.snapshot.tanks.count { it.bot })
        assertEquals(1, arena.snapshot.tanks.count { it.bot && it.x < 5000 })
        assertEquals(1, arena.snapshot.tanks.count { it.bot && it.x > 5000 })
        repeat(1500) {
            arena.step(GameInput(), 1.0 / 60)
            assertTrue(arena.snapshot.tanks.count { it.bot } <= 32)
        }
        assertEquals(32, arena.snapshot.tanks.count { it.bot })
    }

    @Test
    fun spawnRatePersistsAndFasterCadenceFillsMoreQuickly() {
        val slow = arena(.5)
        val fast = arena(4.0)
        repeat(360) {
            slow.step(GameInput(), 1.0 / 60)
            fast.step(GameInput(), 1.0 / 60)
        }
        assertTrue(fast.snapshot.tanks.count { it.bot } > slow.snapshot.tanks.count { it.bot })
        assertEquals(.5, slow.snapshot.rules!!.infinityBotSpawnRate, 0.0)
        assertEquals(4.0, fast.snapshot.rules!!.infinityBotSpawnRate, 0.0)
    }

    @Test
    fun leavingARegionRetiresOnlyAmbientBotsWithoutTeleportOrScoreChanges() {
        val arena = PracticeArena(123, "P1", 0, 1)
        arena.configure(RoomRules(infinity = true, infinityRandomBots = true))
        val human = arena.snapshot.tanks.first()
        human.invulnerable = 10000.0
        val configured =
            arena.snapshot.tanks
                .first { it.bot }
                .apply {
                    name = "Rust"
                    score = 7
                }
        arena.step(GameInput(), 1.0 / 60)
        val ambient = arena.snapshot.tanks.first { it.bot && it.id != configured.id }
        val configuredX = configured.x
        human.x += 10000
        human.y += 10000
        val score = human.score
        arena.step(GameInput(), 1.0 / 60)
        assertFalse(arena.snapshot.tanks.any { it.id == ambient.id })
        assertTrue(arena.snapshot.tanks.any { it.id == configured.id })
        assertEquals(7, configured.score)
        assertEquals(1, configured.spawnSerial)
        assertTrue(kotlin.math.abs(configured.x - configuredX) < 10)
        assertEquals(score, human.score)
    }

    @Test
    fun aTemporaryHumanDeathKeepsNearbyBotsButDoesNotSpawnAnotherWave() {
        val arena = arena()
        arena.step(GameInput(), 1.0 / 60)
        val bot = arena.snapshot.tanks.first { it.bot }.apply { score = 9 }
        val human =
            arena.snapshot.tanks
                .first { !it.bot }
                .apply {
                    hp = 0
                    respawnTime = 10000.0
                }
        repeat(120) { arena.step(GameInput(), 1.0 / 60) }
        assertEquals(1, arena.snapshot.tanks.count { it.bot })
        assertTrue(arena.snapshot.tanks.any { it.id == bot.id && it.score == 9 })
        human.x += 10000
        human.y += 10000
        arena.step(GameInput(), 1.0 / 60)
        assertFalse(arena.snapshot.tanks.any { it.id == bot.id })
        assertEquals(0, arena.snapshot.tanks.count { it.bot })
    }
}
