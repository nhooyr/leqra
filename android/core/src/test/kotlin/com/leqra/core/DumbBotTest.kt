package com.leqra.core

import kotlin.math.PI
import org.junit.Assert.*
import org.junit.Test

class DumbBotTest {
    @Test
    fun finiteDumbMovementAndDefaultAreExplicit() {
        val tuning = BotDifficulty.from("dumb")
        assertEquals(60.0, tuning.speed, 0.0)
        assertEquals(1.8, tuning.turn, 0.0)
        assertEquals(.9, tuning.think, 0.0)
        assertEquals(BotDifficulty.NORMAL, BotDifficulty.from("invalid"))
        assertEquals(BotDifficulty.index("normal"), BotDifficulty.index("invalid"))
        assertEquals(0, BotDifficulty.index("dumb"))
        assertEquals(listOf("dumb", "easy", "normal", "hard", "godlike"), BotDifficulty.names)
        val world = ArenaWorld(width = 1000.0, height = 1000.0)
        val tank = ArenaTank(x = 500.0, y = 500.0, bot = true, difficulty = "dumb")
        TankMovement.stepBot(tank, GameInput(stickX = 1.0), .1, world)
        assertEquals(506.0, tank.x, 1e-9)
        TankMovement.stepBot(tank, GameInput(stickY = 1.0, aimOnly = true), .1, world)
        assertEquals(.18, tank.angle, 1e-9)
    }

    @Test
    fun decisionsKeepBiasedAimStaleAndSometimesDeclineToAttack() {
        val brain = DumbBotBrain(0.0)
        val samples = ArrayDeque(listOf(.5, 1.0, .349, .5, 0.0))
        val random = { samples.removeFirst() }
        assertTrue(brain.reconsider(0.0, 7, 0.0, true, random))
        assertEquals(.6, brain.aim, 1e-9)
        assertTrue(brain.tracks(7, true))
        assertFalse(brain.reconsider(.89, 7, PI, true, random))
        assertEquals(.6, brain.aim, 1e-9)
        assertFalse(brain.tracks(8, true))
        assertFalse(brain.tracks(7, false))
        assertTrue(brain.reconsider(.9, 7, PI, true, random))
        assertFalse(brain.tracks(7, true))
        assertFalse(brain.trigger(1.8, brain.aim, true))
        assertTrue(brain.reconsider(1.8, 7, 0.0, true, random))
        assertEquals(-.6, brain.aim, 1e-9)
        assertTrue(samples.isEmpty())
    }

    @Test
    fun triggerPulsesWaitAtBirthAndBetweenShotsEvenWhenRapidIsHeld() {
        val brain = DumbBotBrain(0.0)
        brain.reconsider(0.0, 7, 0.0, true) { .5 }
        assertFalse(brain.trigger(1.79, 0.0, true))
        assertFalse(brain.trigger(1.8, .361, true))
        assertFalse(brain.trigger(1.8, 0.0, false))
        assertTrue(brain.trigger(1.8, 0.0, true))
        for (tick in 109 until 216) assertFalse(brain.trigger(tick / 60.0, 0.0, true))
        assertTrue(brain.trigger(3.6, 0.0, true))
        val respawned = DumbBotBrain(10.0)
        assertFalse(respawned.trigger(11.8, 0.0, true))
        respawned.reconsider(10.0, 7, 0.0, true) { .5 }
        assertFalse(respawned.trigger(11.79, 0.0, true))
        assertTrue(respawned.trigger(11.8, 0.0, true))
    }

    @Test
    fun privateInfinityDumbSelectionDoesNotIntroducePublicBossSchedule() {
        val arena = PracticeArena(name = "PILOT", colorIndex = 0, botCount = 0)
        arena.configure(
            RoomRules.localDefaults("infinity")
                .copy(
                    infinityBotDifficulty = "dumb",
                    infinityRandomBots = true,
                    infinityRandomDifficulty = true,
                )
        )
        assertEquals(0, arena.snapshot.tanks.count { it.bot })
        arena.snapshot.tanks.first().invulnerable = 1000.0
        repeat(1200) { arena.step(GameInput(), 1.0 / 60) }
        assertEquals(16, arena.snapshot.tanks.count { it.bot })
        repeat(7) {
            arena.snapshot.tanks
                .filter { it.bot }
                .forEach {
                    it.hp = 0
                    it.respawnTime = .01
                }
            arena.step(GameInput(), 1.0 / 60)
            assertTrue(
                arena.snapshot.tanks
                    .filter { it.bot }
                    .all { it.difficulty == "dumb" && !it.isGodlikeBot }
            )
        }
        val invalid = PracticeArena(name = "PILOT", colorIndex = 0, botCount = 0)
        invalid.configure(
            RoomRules.localDefaults("infinity")
                .copy(infinityBotDifficulty = "invalid", infinityRandomBots = true)
        )
        invalid.step(GameInput(), 1.0 / 60)
        assertTrue(invalid.snapshot.tanks.filter { it.bot }.all { it.difficulty == "normal" })
    }

    @Test
    fun godlikeWarningRequiresActualBotTierNotItsCallsign() {
        assertTrue(ArenaTank(bot = true, difficulty = "godlike", name = "BOT").isGodlikeBot)
        assertFalse(ArenaTank(bot = true, difficulty = "dumb", name = "Bot 1 - Godlike").isGodlikeBot)
        assertFalse(
            ArenaTank(bot = false, difficulty = "godlike", name = "Godlike Bot 1").isGodlikeBot
        )
        assertFalse(ArenaTank(bot = true, difficulty = "unknown").isGodlikeBot)
    }
}
