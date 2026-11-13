package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class CallsignsTest {
    @Test
    fun sixteenSupplementaryCharactersSurviveImportAndPersistence() {
        val name = "🚀".repeat(16)
        assertEquals(name, Callsigns.limit(name))
        assertEquals(name, Callsigns.limit(name + "extra"))
        assertEquals("a".repeat(15) + "🚀", Callsigns.limit("a".repeat(15) + "🚀extra"))
    }

    @Test
    fun nativeArenaConstructorsAndIndependentSeatsKeepFullUnicodeCallsigns() {
        val name = "🚀".repeat(16)
        val second = "🛰".repeat(16)
        val practice = PracticeArena(42, name, 0, 0)
        practice.configureLocal(second, 1)
        assertEquals(name, practice.snapshot.tanks.first { it.id == 1 }.name)
        assertEquals(second, practice.snapshot.tanks.first { it.id == 2 }.name)
        practice.configurePilot(1, second, 0)
        assertEquals(second, practice.snapshot.tanks.first { it.id == 1 }.name)
        val fixed = FixedArena(RoomRules.localDefaults(), name, 0, 0, seed = 42)
        fixed.configureLocal(second, 1)
        assertEquals(name, fixed.snapshot.tanks.first { it.id == 1 }.name)
        assertEquals(second, fixed.snapshot.tanks.first { it.id == 2 }.name)
    }
}
