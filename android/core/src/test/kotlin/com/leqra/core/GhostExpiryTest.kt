package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class GhostExpiryTest {
    private val dt = 1.0 / 60

    @Test fun everyGhostEndingThisTickClearsWallsBeforeEitherActorCanFire() {
        for (fixed in listOf(false, true)) for (reverse in listOf(false, true)) {
            val world = if (fixed) ArenaWorld(1008.0, 672.0, 12, 8,
                listOf(MazeWall(248.0, 0.0, 8.0, 672.0, "v", 252.0))) else null
            val arena = PracticeArena(42, "Shooter", 0, 0, world = world)
            arena.configureLocal("Target", 1)
            val wall = world?.walls?.single() ?: arena.maze.walls(168.0, 84.0, 840.0, 756.0).first {
                it.axis == "v" && it.h >= 84 &&
                    !arena.maze.segmentBlocked(it.x - 98, it.y + 42, 83.0, 0.0)
            }
            val y = if (fixed) 210.0 else wall.y + 42
            val shooter = arena.snapshot.tanks.first { it.id == 1 }.apply {
                x = wall.x - 98; this.y = y; angle = 0.0
                invulnerable = 0.0; spawnProtected = false
            }
            val target = arena.snapshot.tanks.first { it.id == 2 }.apply {
                x = wall.x + 5; this.y = y
                ghostTime = dt / 2; invulnerable = 0.0; spawnProtected = false
            }
            PracticeArena.applyPower(shooter, "laser")
            val epoch = target.ammoEpoch
            if (reverse) arena.snapshot.tanks = arena.snapshot.tanks.reversed()
            arena.step(mapOf(1 to GameInput(fire = true)), dt)
            assertEquals("Expired Ghost is behind the wall before a laser in either order", 1, target.hp)
            assertEquals(0.0, target.ghostTime, 0.0)
            assertFalse(arena.maze.blocked(target.x, target.y, 17.0))
            assertEquals("Ghost expiry refills once", epoch + 1, target.ammoEpoch)
            assertTrue(arena.snapshot.effects.any { it.kind == "laser" })
            assertFalse(arena.snapshot.effects.any { it.kind == "hit" })
        }
    }

    @Test fun survivingGhostTimersAgeOnlyOnceAndSimultaneousExpiriesRefillOnce() {
        val arena = PracticeArena(42, "Pilot", 0, 0, world = ArenaWorld(1008.0, 672.0, 12, 8))
        val tank = arena.snapshot.tanks.single().apply {
            x = 500.0; y = 300.0; ghostTime = 1.0
            shield = dt / 2; shieldCharges = 1; speedTime = dt / 2; speedStacks = 2
            invulnerable = 0.0; spawnProtected = false
        }
        val epoch = tank.ammoEpoch
        arena.step(GameInput(), dt)
        assertEquals(1.0 - dt, tank.ghostTime, 1e-12)
        assertEquals(epoch + 1, tank.ammoEpoch)
        tank.ghostTime = dt / 2; tank.shield = dt / 2; tank.shieldCharges = 1
        tank.speedTime = dt / 2; tank.speedStacks = 2
        arena.step(GameInput(), dt)
        assertEquals(0.0, tank.ghostTime, 0.0)
        assertEquals(epoch + 2, tank.ammoEpoch)
    }
}
