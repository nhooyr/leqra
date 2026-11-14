package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class RoamingBotIdentityTest {
    private val step = 1.0 / 60

    private fun rules(level: String, enabled: Boolean = true, teams: Boolean = false) =
        RoomRules(infinity = true, infinityRandomBots = enabled, infinityBotSpawnRates = mapOf(level to .5), teamMode = if (teams) "teams" else "ffa")

    private fun arena(level: String = "dumb", teams: Boolean = false) =
        PracticeArena(123, "P1", 0, 0).apply {
            configure(rules(level, teams = teams))
            snapshot.tanks.first().invulnerable = 10000.0
            step(GameInput(), step)
        }

    private fun nextSpawn(arena: PracticeArena, at: Double) {
        PracticeArena::class.java.getDeclaredField("nextRoamingSpawn").apply { isAccessible = true }.setDouble(arena, at)
    }

    @Test
    fun corpseStaysForOneSecondAndCannotBypassTheConfiguredSpawnCadence() {
        val arena = arena()
        val bot = arena.snapshot.tanks.single { it.bot }.apply { score = 17; hp = 0; respawnTime = 1.0 }
        arena.configurePilot(bot.id, "Changed", 3, difficulty = "godlike")
        assertEquals("dumb", bot.difficulty)
        assertEquals("Bot 1", bot.name)
        nextSpawn(arena, 100.0)
        repeat(59) { arena.step(GameInput(), step) }
        assertEquals(0, arena.snapshot.tanks.single { it.id == bot.id }.hp)
        arena.step(GameInput(), step)
        assertFalse(arena.snapshot.tanks.any { it.id == bot.id })
        assertEquals(17, arena.snapshot.leaderboard.single { it.id == bot.id }.score)
        repeat(120) { arena.step(GameInput(), step) }
        assertFalse(arena.snapshot.tanks.any { it.bot })
        nextSpawn(arena, 0.0)
        arena.step(GameInput(), step)
        val revived = arena.snapshot.tanks.single { it.bot }
        assertEquals(bot.id, revived.id); assertEquals(bot.name, revived.name)
        assertEquals("dumb", revived.difficulty); assertEquals(17, revived.score)
        assertEquals(bot.spawnSerial + 1, revived.spawnSerial)
    }

    @Test
    fun rateChangesReuseOnlyTheMatchingPermanentTierAndKeepOffIdentitiesInStandings() {
        val arena = arena("godlike", teams = true)
        val identities = mutableMapOf<String, Pair<Int, String>>()
        for (cycle in 0 until 25) for ((index, level) in BotDifficulty.names.withIndex()) {
            arena.configure(rules(level, teams = true))
            arena.step(GameInput(), step)
            val bot = arena.snapshot.tanks.single { it.bot }
            val previous = identities.putIfAbsent(level, bot.id to bot.name)
            if (previous != null) {
                assertEquals(previous.first, bot.id); assertEquals(previous.second, bot.name)
                assertEquals(index + 1, bot.score)
            }
            assertEquals(level, bot.difficulty)
            bot.score = index + 1
        }
        arena.configure(rules("dumb", enabled = false, teams = true))
        repeat(120) { arena.step(GameInput(), step) }
        assertEquals(0, arena.snapshot.tanks.count { it.bot })
        val bots = arena.snapshot.leaderboard.filter { it.bot }
        assertEquals(5, bots.size)
        assertEquals(5, bots.map { it.id }.distinct().size)
        assertEquals(5, bots.map { it.name }.distinct().size)
        for ((index, level) in BotDifficulty.names.withIndex()) {
            val bot = bots.single { it.difficulty == level }
            assertEquals(identities.getValue(level).first, bot.id)
            assertEquals(index + 1, bot.score)
        }
        assertEquals(15, arena.snapshot.teamScores.sum())
        assertEquals(6, arena.snapshot.tankCount)
    }

    @Test
    fun retirementPreservesOutgoingProjectilesAndCreditsTheParkedShooter() {
        val arena = arena(teams = true)
        val bot = arena.snapshot.tanks.single { it.bot }.apply {
            x = 42.0; y = 42.0; angle = 0.0; invulnerable = 0.0; spawnProtected = false
            power = "cannon"; powerTime = 15.0; charges = 3
        }
        val human = arena.snapshot.tanks.single { !it.bot }.apply {
            x = 160.0; y = 42.0; invulnerable = 0.0; spawnProtected = false
        }
        assertNotEquals(human.team, bot.team)
        PracticeArena::class.java.getDeclaredMethod("fireShot", Int::class.javaPrimitiveType).apply { isAccessible = true }
            .invoke(arena, arena.snapshot.tanks.indexOf(bot))
        bot.x = 10000.0; bot.y = 10000.0
        nextSpawn(arena, 100.0)
        arena.step(GameInput(), step)
        assertFalse(arena.snapshot.tanks.any { it.id == bot.id })
        assertTrue(arena.snapshot.bullets.any { it.owner == bot.id && it.kind == "cannon" })
        repeat(8) { arena.step(GameInput(), step) }
        assertEquals(0, human.hp); assertEquals(-1, human.score)
        assertEquals(bot.name, human.killedBy)
        assertEquals(1, arena.snapshot.leaderboard.single { it.id == bot.id }.score)
        assertEquals(1, arena.snapshot.teamScores[bot.team - 1])
        assertEquals(-1, arena.snapshot.teamScores[human.team - 1])
    }

    @Test
    fun enablingP2ReservesItsIDWithoutLosingAnInactiveBotIdentityOrScore() {
        val arena = arena()
        val bot = arena.snapshot.tanks.single { it.bot }.apply { score = 17 }
        assertEquals(2, bot.id)
        arena.configure(rules("dumb", enabled = false))
        arena.configureLocal("P2", 1)
        val parked = arena.snapshot.leaderboard.single { it.bot }
        assertNotEquals(2, parked.id); assertEquals(bot.name, parked.name); assertEquals(17, parked.score)
        assertEquals(1, arena.snapshot.tanks.count { it.id == 2 && !it.bot })
        arena.configure(rules("dumb"))
        arena.step(GameInput(), step)
        val revived = arena.snapshot.tanks.single { it.id == parked.id }
        assertEquals(bot.name, revived.name); assertEquals(17, revived.score); assertEquals("dumb", revived.difficulty)
        assertEquals(arena.snapshot.leaderboard.size, arena.snapshot.leaderboard.map { it.id }.distinct().size)
        assertEquals(arena.snapshot.leaderboard.size, arena.snapshot.leaderboard.map { it.name }.distinct().size)
    }

    @Test
    fun earlyRetirementCannotReuseADeadIdentityBeforeItsRemainingCorpseDelay() {
        val arena = arena()
        val original = arena.snapshot.tanks.single { it.bot }.apply { hp = 0; respawnTime = 1.0; score = 17 }
        arena.configure(rules("dumb", enabled = false))
        arena.configure(rules("dumb"))
        arena.step(GameInput(), step)
        val replacement = arena.snapshot.tanks.single { it.bot }
        assertNotEquals(original.id, replacement.id)
        assertEquals(17, arena.snapshot.leaderboard.single { it.id == original.id }.score)
        arena.configure(rules("dumb", enabled = false))
        repeat(60) { arena.step(GameInput(), step) }
        arena.configure(rules("dumb"))
        arena.step(GameInput(), step)
        val revived = arena.snapshot.tanks.single { it.bot }
        assertEquals(original.id, revived.id)
        assertEquals(original.spawnSerial + 1, revived.spawnSerial)
        assertEquals(17, revived.score)
    }

    @Test
    fun waitingIdentitiesRespectThePermanentPerTierLimitWithoutGrowingOrBypassingDeathDelay() {
        val arena = arena()
        repeat(128) { index ->
            if (index > 0) {
                arena.configure(rules("dumb"))
                arena.step(GameInput(), step)
            }
            arena.snapshot.tanks.single { it.bot }.apply { hp = 0; respawnTime = 10000.0; score = index }
            arena.configure(rules("dumb", enabled = false))
        }
        val first = arena.snapshot.leaderboard.filter { it.bot }.minBy { it.id }
        arena.configure(rules("dumb"))
        repeat(120) { arena.step(GameInput(), step) }
        assertFalse(arena.snapshot.tanks.any { it.bot })
        assertEquals(128, arena.snapshot.leaderboard.count { it.bot })
        assertEquals(128, arena.snapshot.leaderboard.filter { it.bot }.map { it.name }.distinct().size)
        PracticeArena::class.java.getDeclaredField("time").apply { isAccessible = true }.setDouble(arena, 100000.0)
        nextSpawn(arena, 0.0)
        arena.step(GameInput(), step)
        val revived = arena.snapshot.tanks.single { it.bot }
        assertEquals(first.id, revived.id); assertEquals(first.score, revived.score)
        assertEquals(128, arena.snapshot.leaderboard.count { it.bot })
    }

    @Test
    fun anAvailableIdentityPoolDoesNotOverrideWeightedRatesOrReviveDisabledTiers() {
        val arena = arena()
        for (level in BotDifficulty.names) {
            arena.configure(rules(level))
            arena.step(GameInput(), step)
        }
        arena.configure(RoomRules(infinity = true, infinityRandomBots = true,
            infinityBotSpawnRates = mapOf("dumb" to .5, "normal" to 1.0, "godlike" to 2.5)))
        val counts = mutableMapOf<String, Int>()
        repeat(300) {
            arena.snapshot.tanks.filter { it.bot }.forEach { it.x = 10000.0; it.y = 10000.0 }
            nextSpawn(arena, 0.0)
            arena.step(GameInput(), step)
            val bot = arena.snapshot.tanks.single { it.bot }
            counts[bot.difficulty] = counts.getOrDefault(bot.difficulty, 0) + 1
            assertEquals(5, arena.snapshot.leaderboard.count { it.bot })
        }
        assertEquals(setOf("dumb", "normal", "godlike"), counts.keys)
        assertTrue(counts.getValue("godlike") > counts.getValue("normal"))
        assertTrue(counts.getValue("normal") > counts.getValue("dumb"))
    }
}
