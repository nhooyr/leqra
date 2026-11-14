package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class RoamingBotRatesTest {
    private val step = 1.0 / 60
    private fun configured(rates: Map<String, Double>, roster: Int = 0, enabled: Boolean = true) =
        PracticeArena(123, "P1", 0, roster, difficulty = "hard").apply {
            configure(RoomRules(infinity = true, infinityRandomBots = enabled, infinityBotSpawnRates = rates))
            snapshot.tanks.first().invulnerable = 10000.0
        }

    @Test
    fun finiteTargetsNeedOpponentsWhenTheMasterIsOnButEveryTierIsOff() {
        val rules = RoomRules(infinity = true, infinityTarget = 10, infinityRandomBots = true, infinityBotSpawnRates = emptyMap())
        assertNotNull(rules.infinityStartError(listOf(1)))
        assertNull(rules.infinityStartError(listOf(1, 1)))
        assertNotNull(rules.copy(teamMode = "teams").infinityStartError(listOf(1, 1)))
        assertNull(rules.copy(teamMode = "teams").infinityStartError(listOf(1, 2)))
        assertNull(rules.copy(infinityTarget = 0).infinityStartError(listOf(1)))
        assertNull(rules.copy(infinityBotSpawnRates = mapOf("dumb" to .5)).infinityStartError(listOf(1)))
        assertNotNull(rules.copy(infinityRandomBots = false, infinityBotSpawnRates = mapOf("dumb" to .5)).infinityStartError(listOf(1)))
    }

    @Test
    fun missingMapsMigrateEveryLegacyTierAndUniformCeilingWithoutChangingTotal() {
        assertEquals(mapOf("dumb" to 0.0, "easy" to 0.0, "normal" to 2.0, "hard" to 0.0, "godlike" to 0.0), RoomRules().roamingBotSpawnRates())
        for ((index, level) in BotDifficulty.names.withIndex()) for (rate in listOf(.5, 1.0, 2.0, 4.0)) for (random in listOf(false, true)) {
            val rules = RoomRules(infinityBotDifficulty = level, infinityBotSpawnRate = rate, infinityRandomDifficulty = random)
            val actual = rules.roamingBotSpawnRates()
            for ((i, tier) in BotDifficulty.names.withIndex()) assertEquals(if (random && i <= index) rate / (index + 1) else if (!random && i == index) rate else 0.0, actual.getValue(tier), 0.0)
            assertEquals(rate, actual.values.sum(), 1e-12)
            assertEquals(actual, rules.copy(infinityRandomBots = true).roamingBotSpawnRates())
        }
    }

    @Test
    fun explicitMapsAreAuthoritativeAndEmptyOrMasterOffNeverSpawnRoamingBots() {
        val empty = RoomRules(infinityRandomBots = true, infinityBotDifficulty = "godlike", infinityBotSpawnRate = 4.0, infinityBotSpawnRates = emptyMap())
        assertTrue(empty.roamingBotSpawnRates().values.all { it == 0.0 })
        assertNull(empty.roamingBotDifficulty(.2))
        for (enabled in listOf(false, true)) {
            val arena = configured(if (enabled) emptyMap() else mapOf("normal" to 4.0), roster = 1, enabled = enabled)
            repeat(200) { arena.step(GameInput(), step) }
            assertEquals(1, arena.snapshot.tanks.count { it.bot })
            val roster = arena.snapshot.tanks.single { it.bot }
            roster.hp = 0; roster.respawnTime = step; roster.score = 7
            arena.step(GameInput(), step)
            val respawned = arena.snapshot.tanks.single { it.bot }
            assertEquals(1, respawned.hp); assertEquals("hard", respawned.difficulty); assertEquals(7, respawned.score)
        }
        val invalid = empty.copy(infinityBotSpawnRates = mapOf("normal" to Double.NaN, "hard" to 5.0, "dumb" to -1.0, "easy" to Double.POSITIVE_INFINITY))
        assertTrue(invalid.roamingBotSpawnRates().values.all { it == 0.0 })
    }

    @Test
    fun weightedTierBoundariesNeverSelectOffLevels() {
        val rules = RoomRules(infinityRandomBots = true, infinityBotSpawnRates = mapOf("dumb" to .5, "normal" to 1.0, "godlike" to 2.5))
        assertEquals("dumb", rules.roamingBotDifficulty(0.0))
        assertEquals("normal", rules.roamingBotDifficulty(.125))
        assertEquals("godlike", rules.roamingBotDifficulty(.375))
        assertEquals("godlike", rules.roamingBotDifficulty(1.0))
        val counts = (0 until 4000).map { rules.roamingBotDifficulty((it + .5) / 4000) }.groupingBy { it }.eachCount()
        assertEquals(mapOf("dumb" to 500, "normal" to 1000, "godlike" to 2500), counts)
        assertNull(rules.copy(infinityRandomBots = false).roamingBotDifficulty(.5))
    }

    @Test
    fun totalRateControlsWaveCadenceAndAllTiersShareOnePerHumanBudget() {
        val slow = configured(mapOf("dumb" to 1.0, "normal" to 1.0))
        val fast = configured(mapOf("dumb" to 4.0, "normal" to 4.0))
        slow.step(GameInput(), step); fast.step(GameInput(), step)
        fun next(arena: PracticeArena) = PracticeArena::class.java.getDeclaredField("nextRoamingSpawn").run { isAccessible = true; getDouble(arena) } - step
        assertEquals(next(slow) * 2, next(fast) * 8, 1e-12)
        val arena = configured(BotDifficulty.names.associateWith { 4.0 })
        arena.configureLocal("P2", 1)
        arena.snapshot.tanks.first { !it.bot && it.id != arena.localID }.apply { x = 10000.0; y = 10000.0; invulnerable = 10000.0 }
        repeat(600) { arena.step(GameInput(), step); assertTrue(arena.snapshot.tanks.count { it.bot } <= 32) }
        assertEquals(32, arena.snapshot.tanks.count { it.bot })
    }

    @Test
    fun ambientDeathsWaitForMatchingTierSpawnWhileRosterRespawnsUnchanged() {
        val arena = configured(mapOf("dumb" to 2.0), roster = 1)
        val roster = arena.snapshot.tanks.single { it.bot }
        arena.step(GameInput(), step)
        val ambient = arena.snapshot.tanks.first { it.bot && it.id != roster.id }
        ambient.score = 17; ambient.hp = 0; ambient.respawnTime = step
        roster.score = 9; roster.hp = 0; roster.respawnTime = step
        arena.step(GameInput(), step)
        assertFalse(arena.snapshot.tanks.any { it.id == ambient.id })
        assertEquals(17, arena.snapshot.leaderboard.single { it.id == ambient.id }.score)
        assertEquals("hard", arena.snapshot.tanks.single { it.id == roster.id }.difficulty)
        assertEquals(9, arena.snapshot.tanks.single { it.id == roster.id }.score)
        repeat(60) { arena.step(GameInput(), step) }
        val next = arena.snapshot.tanks.single { it.id == ambient.id }
        assertEquals(ambient.spawnSerial + 1, next.spawnSerial)
        assertEquals("dumb", next.difficulty); assertEquals(17, next.score)
    }
}
