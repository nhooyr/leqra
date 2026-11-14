package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class DifficultyDisplayTest {
    @Test
    fun everyDifficultyHasItsNewDisplayTitleWithoutChangingProtocolKeysOrTuning() {
        assertEquals(listOf("dumb", "easy", "normal", "hard", "godlike"), BotDifficulty.names)
        assertEquals(listOf("Dumb", "Easy", "Medium", "Hard", "Godlike"), BotDifficulty.titles)
        for ((index, key) in BotDifficulty.names.withIndex()) {
            assertEquals(index, BotDifficulty.index(key))
            assertEquals(BotDifficulty.titles[index], BotDifficulty.title(key))
            assertEquals(BotDifficulty.entries[index], BotDifficulty.from(key))
        }
        assertEquals("Medium", BotDifficulty.title("normal"))
        assertEquals(BotDifficulty.NORMAL, BotDifficulty.from("normal"))
    }

    @Test
    fun canonicalAndLegacyNumberedBotSuffixesShareOneNormalTierAndDisplayMedium() {
        for (name in listOf("Bot 17 - Medium", "Bot 17 - Normal", "BOT 17 - NORMAL", "bot 17 - medium")) {
            assertEquals("Bot 17 - Medium", PilotIdentity.botName(name))
            assertEquals("Bot 17 - Medium", PilotIdentity.label(name, true))
            assertEquals("Bot 17", PilotIdentity.leaderboardLabel(name, true))
            assertEquals("normal", PilotIdentity.leaderboardDifficulty(name, true))
            assertEquals("normal", PilotIdentity.leaderboardDifficulty(name, true, "unknown"))
            assertEquals("hard", PilotIdentity.leaderboardDifficulty(name, true, "hard"))
        }
    }

    @Test
    fun humanCallsignsAndAuthoredBotNamesContainingDifficultyWordsRemainTheirNames() {
        for (name in listOf("Normal", "Chill", "Fierce", "Medium", "Normal Pilot", "Bot 17 - Normal", "BOT 17 - NORMAL", "Bot 17 - Medium")) {
            assertEquals(name, PilotIdentity.label(name, false))
            assertEquals("$name (P2)", PilotIdentity.label(name, false, 2))
            assertEquals(name, PilotIdentity.leaderboardLabel(name, false))
            assertNull(PilotIdentity.leaderboardDifficulty(name, false, "normal"))
        }
        assertEquals("Bot Normal", PilotIdentity.label("NORMAL", true))
        assertEquals("Bot Chill", PilotIdentity.label("CHILL", true))
        assertEquals("Bot Fierce", PilotIdentity.label("FIERCE", true))
        assertEquals("Bot Rust - Normal", PilotIdentity.label("Rust - Normal", true))
        assertNull(PilotIdentity.leaderboardDifficulty("Rust - Normal", true))
    }

    @Test
    fun survivalBossNamesMatchTheNewTitlesWhileTheirDifficultyKeysStayCompatible() {
        val arena = FixedArena(RoomRules.localDefaults("survival").copy(scoreTarget = 20), "Pilot", 0, botCount = 0, seed = 42)
        for ((wave, name, difficulty) in listOf(Triple(5, "MEDIUM BOSS", "normal"), Triple(10, "HARD BOSS", "hard"), Triple(15, "GODLIKE BOSS", "godlike"))) {
            arena.objectives!!.survival!!.wave = wave
            arena.restartWave()
            val boss = arena.snapshot.tanks.single { it.survivalBoss }
            assertEquals(name, boss.name)
            assertEquals(difficulty, boss.difficulty)
        }
    }
}
