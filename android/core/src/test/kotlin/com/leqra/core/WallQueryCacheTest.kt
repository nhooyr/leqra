package com.leqra.core

import org.junit.Assert.assertEquals
import org.junit.Test

class WallQueryCacheTest {
    @Test
    fun exactBoundsAndOriginalWallOrderSurviveCacheReplacement() {
        val world = FixedArena(RoomRules(mapSize = "ultrawide"), "PERF", 0, 0, seed = 42).world
        val maze = InfiniteMaze(world)
        repeat(1200) { index ->
            val x = (index * 37 % 2100) - 50.0
            val y = (index * 53 % 1200) - 50.0
            for (offset in listOf(0.0, .75)) {
                val x0 = x + offset
                val y0 = y + offset
                val x1 = x0 + 91
                val y1 = y0 + 173
                val expected =
                    world.walls.filter {
                        it.x <= x1 && it.x + it.w >= x0 && it.y <= y1 && it.y + it.h >= y0
                    }
                assertEquals(expected, maze.walls(x0, y0, x1, y1))
            }
        }
    }
}
