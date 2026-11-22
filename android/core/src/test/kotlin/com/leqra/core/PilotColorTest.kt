package com.leqra.core

import kotlin.random.Random
import org.junit.Assert.*
import org.junit.Test

class PilotColorTest {
    @Test
    fun newPilotColorAvoidsOldPaintOtherPilotAndBots() {
        val seen =
            (0..100).map { GamePalette.randomPilotColor(0, listOf(1, 2, 3), Random(it)) }.toSet()
        assertEquals(setOf(4, 5, 6, 7), seen)
    }

    @Test
    fun fullPaletteKeepsCurrentColor() {
        assertEquals(2, GamePalette.randomPilotColor(2, (0..7).toList()))
    }
}
