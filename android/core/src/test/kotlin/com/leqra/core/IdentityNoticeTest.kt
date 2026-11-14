package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class IdentityNoticeTest {
    @Test
    fun onlyActualBotsGetBotIdentityWhilePublicNamesRemainOriginal() {
        assertEquals("Bot Rust", PilotIdentity.label("RUST", true))
        assertEquals("Bot Dark Knight", PilotIdentity.label("DARK KNIGHT", true))
        assertEquals("Bot Rust", PilotIdentity.label("BOT RUST", true))
        assertEquals("Bot Rust", PilotIdentity.leaderboardLabel("RUST", true))
        assertEquals(
            "Bot 50",
            PilotIdentity.leaderboardLabel("Bot 50 - Godlike", true),
        )
        assertEquals("Godlike Bot 50", PilotIdentity.leaderboardLabel("Godlike Bot 50", false))
        assertEquals("Bot 17", PilotIdentity.label("Bot 17", true))
        assertEquals("Bot 50 - Godlike", PilotIdentity.label("Bot 50 - Godlike", true))
        assertEquals("Bot Godlike Bot 50", PilotIdentity.label("Godlike Bot 50", true))
        assertEquals("Godlike Bot 50 (P1)", PilotIdentity.label("Godlike Bot 50", false, 1))
        assertEquals("RUST (P2)", PilotIdentity.label("RUST", false, 2))
        assertEquals("BOT RUST (P1)", PilotIdentity.label("BOT RUST", false, 1))
        val longPublicName = "Bot 1234567890 - Godlike"
        assertTrue(longPublicName.length > 16)
        assertEquals(longPublicName, PilotIdentity.label(longPublicName, true))
        assertEquals("Bot 1234567890", PilotIdentity.leaderboardLabel(longPublicName, true))
    }

    @Test
    fun standingsSeparateNumberedBotNamesFromActualDifficultyWithoutSpoofingHumans() {
        for (level in BotDifficulty.names) {
            val suffix = level.replaceFirstChar { it.titlecase() }
            val name = "Bot 9182 - $suffix"
            assertEquals(name, PilotIdentity.label(name, true))
            assertEquals("Bot 9182", PilotIdentity.leaderboardLabel(name, true))
            assertEquals(level, PilotIdentity.leaderboardDifficulty(name, true))
            assertEquals("normal", PilotIdentity.leaderboardDifficulty(name, true, "normal"))
            assertEquals(name, PilotIdentity.leaderboardLabel(name, false))
            assertNull(PilotIdentity.leaderboardDifficulty(name, false, level))
        }
        assertEquals("Bot Rust", PilotIdentity.leaderboardLabel("RUST", true))
        assertEquals("hard", PilotIdentity.leaderboardDifficulty("RUST", true, "hard"))
        assertNull(PilotIdentity.leaderboardDifficulty("RUST", true))
        assertNull(PilotIdentity.leaderboardDifficulty("Bot 17", true))
        assertNull(PilotIdentity.leaderboardDifficulty("Bot 17", true, "unknown"))
        assertEquals("normal", PilotIdentity.leaderboardDifficulty("Bot 17 - Normal", true, "unknown"))
        assertEquals("Pilot (P2)", PilotIdentity.leaderboardLabel("Pilot", false, 2))
    }

    @Test
    fun humanBotNamespaceValidationMatchesCanonicalServerCleaning() {
        for (name in listOf("Bot 1", "bOt RUST", " BOT  rust ", "Bot", "bot _")) assertTrue(
            name,
            Callsigns.botReserved(name),
        )
        for (name in
            listOf(
                "Botanist",
                "BotRUST",
                "Bot-RUST",
                "Bo#t Rust",
                "pilot#ABC234",
                "Bot\tRUST",
                "RUST",
                "Godlike Bot 1",
                "GODLIKE 1",
                "godlike-1",
            )) assertFalse(name, Callsigns.botReserved(name))
    }

    @Test
    fun noticesArePassiveSixSecondsAndDeduplicatedByLifeAcrossReconnects() {
        val notices = GodlikeSpawnNotices()
        val first = GodlikeSpawn(7, 1, "Bot 50 - Godlike")
        notices.accept(listOf(first), 0.0)
        assertEquals("Bot 50 - Godlike spawned nearby. Watch out!", notices.current(5.99))
        notices.accept(listOf(first), 5.0)
        assertNull(notices.current(6.0))
        notices.accept(listOf(first), 8.0)
        assertNull(notices.current(8.0))
        notices.accept(listOf(first.copy(spawnSerial = 2)), 9.0)
        assertNotNull(notices.current(9.0))
        val longName = "Bot 1234567890 - Godlike"
        notices.accept(listOf(first.copy(spawnSerial = 3, name = longName)), 9.5)
        assertEquals("$longName spawned nearby. Watch out!", notices.current(9.5))
        repeat(200) { notices.accept(listOf(GodlikeSpawn(it + 100, 1, "Bot $it - Godlike")), 10.0) }
        assertTrue(notices.rememberedLives <= 128)
        notices.clear()
        assertNull(notices.current(10.0))
        assertEquals(0, notices.rememberedLives)
    }
}
