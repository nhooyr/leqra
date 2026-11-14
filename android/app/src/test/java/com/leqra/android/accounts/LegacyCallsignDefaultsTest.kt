package com.leqra.android.accounts

import org.junit.Assert.*
import org.junit.Test

class LegacyCallsignDefaultsTest {
    @Test
    fun compactPlayerNamesRemainChosenCustomNamesWithoutAnAccount() {
        val saved = listOf("Player1", "Player2")
        val names = saved.map { it.takeUnless { LegacyCallsignDefaults.shouldGenerate(it, false) } }
        val drafts = CallsignDrafts(names, listOf(false, false), listOf(null, null))
        assertEquals(saved[0], drafts.name(0))
        assertEquals(saved[1], drafts.name(1))
        assertFalse(drafts.pending(0))
        assertFalse(drafts.pending(1))
    }

    @Test
    fun onlyKnownShippedDefaultsWithoutAnAccountAreUpgraded() {
        val defaults =
            listOf(
                "PILOT",
                " player 1 ",
                "pLaYeR   2",
                "PLAYER    1",
                "Co-pilot",
                "YOU",
                " Snow   Fox ",
                "Pilot 100",
                "pilot 999",
            )
        for (name in defaults) {
            assertTrue(name, LegacyCallsignDefaults.shouldGenerate(name, false))
            assertFalse(
                "Any existing key protects $name",
                LegacyCallsignDefaults.shouldGenerate(name, true),
            )
        }
        for (name in
            listOf(
                null,
                "",
                "Rust",
                "Pilot 99",
                "Pilot 1000",
                "Pilot 001",
                "Player1",
                "player2",
                "Player 3",
                "Player 10",
                "Player 01",
                "SnowFox",
                "pilot#ABC234",
                "pilot-abcdefghij",
                "Bot Rust",
            )) assertFalse(name, LegacyCallsignDefaults.shouldGenerate(name, false))
    }

    @Test
    fun migratedSeatsBecomeDistinctPendingDefaultsAndCustomOtherSeatIsPreserved() {
        val old = listOf("PILOT", "CO-PILOT")
        val names = old.map { it.takeUnless { LegacyCallsignDefaults.shouldGenerate(it, false) } }
        val drafts = CallsignDrafts(names, listOf(null, null), listOf(null, null))
        assertNotEquals(drafts.name(0), drafts.name(1))
        assertTrue(
            (0..1).all {
                drafts.pending(it) &&
                    Regex("pilot#[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}").matches(drafts.name(it))
            }
        )
        val mixed = CallsignDrafts(listOf(null, "MY NAME"), listOf(null, false), listOf(null, null))
        assertEquals("MY NAME", mixed.name(1))
        assertFalse(mixed.pending(1))
    }
}
