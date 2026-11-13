package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class MazeQueryTest {
    @Test
    fun fixedBinsKeepExactWorldOrderWithoutDuplicatesAcrossOverlappingCells() {
        val world =
            FixedArena(
                    RoomRules.localDefaults().apply { mapSize = "giant" },
                    "Pilot",
                    0,
                    0,
                    seed = 42,
                )
                .world
        val maze = InfiniteMaze(world)
        var state = 42
        fun random(max: Int): Int {
            state = state xor (state shl 13)
            state = state xor (state ushr 17)
            state = state xor (state shl 5)
            return Integer.remainderUnsigned(state, max)
        }
        repeat(2000) {
            val x0 = random((world.width + 168).toInt()).toDouble() - 84
            val y0 = random((world.height + 168).toInt()).toDouble() - 84
            val x1 = x0 + random(840)
            val y1 = y0 + random(840)
            val expected =
                world.walls.filter {
                    it.x <= x1 && it.x + it.w >= x0 && it.y <= y1 && it.y + it.h >= y0
                }
            assertEquals(expected, maze.walls(x0, y0, x1, y1))
            maze.blocked(x0, y0, 17.0)
            maze.rayHit(x0, y0, x1 - x0, y1 - y0, 4.0)
            assertEquals(expected, maze.walls(x0, y0, x1, y1))
        }
    }

    @Test
    fun artworkGeometryCannotMutateTheCollisionIndexAndChunkCacheStaysBounded() {
        val world =
            ArenaWorld(840.0, 840.0, 10, 10, listOf(MazeWall(80.0, 0.0, 8.0, 840.0, "v", 84.0)))
        val maze = InfiniteMaze(world)
        val art = maze.walls(0.0, 0.0, 840.0, 840.0)
        art[0].x = 9000.0
        assertTrue(maze.blocked(84.0, 42.0, 17.0))
        assertEquals(80.0, world.walls[0].x, 0.0)
        val infinite = InfiniteMaze(42)
        repeat(1000) { index -> infinite.blocked(index * 672.0 + 42, 42.0, 17.0) }
        assertTrue(infinite.cachedChunkCount <= 128)
        val fresh = InfiniteMaze(42)
        for (x in listOf(42.0, 714.0, 1398.0, -42.0)) assertEquals(
            fresh.walls(x - 84, -84.0, x + 84, 84.0),
            infinite.walls(x - 84, -84.0, x + 84, 84.0),
        )
    }
}
