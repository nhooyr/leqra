package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class CannonPiercingTest {
    @Test
    fun cannonContinuesThroughEveryTankWithoutRepeatingShieldDamage() {
        val world =
            ArenaWorld(900.0, 420.0, 11, 5, listOf(MazeWall(300.0, 0.0, 8.0, 420.0, "v", 304.0)))
        val arena = PracticeArena(42, "CANNON", 0, 0, world = world)
        arena.configure(RoomRules(pickupRate = "off"))
        arena.snapshot.tanks =
            listOf(
                ArenaTank(
                    id = 1,
                    x = 90.0,
                    y = 210.0,
                    powerTime = 10.0,
                    power = "cannon",
                    charges = 3,
                    team = 1,
                ),
                ArenaTank(id = 2, x = 190.0, y = 210.0, shield = 10.0, shieldCharges = 3, team = 2),
                ArenaTank(id = 3, x = 290.0, y = 210.0, team = 2),
                ArenaTank(
                    id = 4,
                    x = 390.0,
                    y = 210.0,
                    invulnerable = 2.0,
                    spawnProtected = true,
                    team = 2,
                ),
                ArenaTank(id = 5, x = 490.0, y = 210.0, team = 1),
                ArenaTank(id = 6, x = 590.0, y = 210.0, team = 2),
            )
        arena.step(GameInput(fire = true), 1.0 / 60)
        repeat(31) { arena.step(GameInput(), 1.0 / 60) }
        assertEquals(listOf(1, 1, 0, 1, 1, 0), arena.snapshot.tanks.map { it.hp })
        assertEquals(2, arena.snapshot.tanks[1].shieldCharges)
        assertEquals(1, arena.snapshot.bullets.count { it.kind == "cannon" })
        assertEquals(5.3 - 32.0 / 60, arena.snapshot.bullets.single().life, 1e-8)
        assertTrue(arena.snapshot.bullets.single().x > 590.0)
        repeat(60) { arena.step(GameInput(), 1.0 / 60) }
        assertEquals(
            "Returning shell must not repeatedly drain the same shield",
            2,
            arena.snapshot.tanks[1].shieldCharges,
        )
    }

    @Test
    fun targetScoreFinalizesAfterEveryVictimInTheCurrentCannonSegment() {
        val arena = PracticeArena(42, "CANNON", 0, 0)
        arena.configure(
            RoomRules(
                infinity = true,
                infinityTarget = 1,
                infinityRandomBots = false,
                pickupRate = "off",
            ),
        )
        arena.snapshot.tanks =
            listOf(
                ArenaTank(
                    id = 1,
                    x = 100.0,
                    y = 100.0,
                    powerTime = 10.0,
                    power = "cannon",
                    charges = 3,
                ),
                ArenaTank(id = 2, x = 145.0, y = 100.0),
                ArenaTank(id = 3, x = 150.0, y = 100.0),
                ArenaTank(id = 4, x = 155.0, y = 100.0),
            )
        arena.step(GameInput(fire = true), 1.0 / 60)
        assertEquals(listOf(1, 0, 0, 0), arena.snapshot.tanks.map { it.hp })
        assertEquals(3, arena.snapshot.result!!.score)
        assertTrue(arena.snapshot.bullets.any { it.kind == "cannon" })
    }
}
