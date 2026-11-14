package com.leqra.android

import org.junit.Assert.*
import org.junit.Test

class BotNamesTest {
    @Test
    fun newBotNamesUseTitleCaseAndAvoidExistingMixedCaseNames() {
        assertEquals("Rust", BotNames.next(emptyList(), 2))
        assertEquals("Vapor", BotNames.next(listOf("RUST"), 3))
        assertEquals("Ember", BotNames.next(listOf("rust", "VAPOR"), 4))
        assertEquals(
            "Bot 9",
            BotNames.next(listOf("Rust", "Vapor", "Ember", "Nova", "Comet", "Onyx", "Blitz"), 9),
        )
    }
}
