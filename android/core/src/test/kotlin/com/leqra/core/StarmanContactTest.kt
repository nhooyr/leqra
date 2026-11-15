package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class StarmanContactTest {
    private val dt = 1.0 / 60
    private fun arena(fixed: Boolean, reversed: Boolean = false): PracticeArena {
        val model = PracticeArena(42, "Alpha", 0, 0,
            world = if (fixed) ArenaWorld(1008.0, 672.0, 12, 8) else null)
        model.configureLocal("Bravo", 1)
        model.snapshot.tanks.forEachIndexed { i, t ->
            t.x = 42.0 + i * 25; t.y = 42.0; t.spawnProtected = false; t.invulnerable = 0.0
            t.starmanTime = 8.0; t.score = 5
        }
        if (reversed) model.snapshot.tanks = model.snapshot.tanks.reversed()
        return model
    }

    @Test fun twoStarmenDieWithMutualCreditRegardlessOfActorOrderAndDoNotKillAThirdTank() {
        for (fixed in listOf(false, true)) for (reversed in listOf(false, true)) {
            val model = arena(fixed, reversed)
            val observer=ArenaTank(id = 3, name = "Observer", x = 54.0, y = 65.0, score = 5)
            model.snapshot.tanks = if(reversed) listOf(observer)+model.snapshot.tanks else model.snapshot.tanks+observer
            model.step(GameInput(), dt)
            val first = model.snapshot.tanks.first { it.id == 1 }
            val second = model.snapshot.tanks.first { it.id == 2 }
            assertEquals(0, first.hp); assertEquals(0, second.hp)
            assertEquals(5, first.score); assertEquals(5, second.score)
            assertEquals("Bravo", first.killedBy); assertEquals("Alpha", second.killedBy)
            assertEquals("Dead Starmen cannot kill a third tank", 1, model.snapshot.tanks.first { it.id == 3 }.hp)
            val before = model.snapshot.effects.mapNotNull { it.contact }.filter { it.kind == "starman" }
            assertEquals(2, before.size)
            assertTrue(before.all { it.before.hp == 1 })
        }
    }

    @Test fun mutualStarRespectsTeamAndFriendlyFireAndOverridesShields() {
        for (fixed in listOf(false, true)) for (friendly in listOf(false, true)) {
            val model = arena(fixed); model.friendlyFire = friendly
            model.snapshot.tanks.forEach { it.team = 1; it.shield = 10.0; it.shieldCharges = 5; it.invulnerable = 1.0 }
            model.step(GameInput(), dt)
            assertTrue(model.snapshot.tanks.all { it.hp == if (friendly) 0 else 1 })
        }
    }

    @Test fun mutualStarCannotCrossAWallAndOneStarStillKillsAnUnboostedTank() {
        val wall = MazeWall(55.0, 0.0, 8.0, 84.0, "v", 59.0)
        val model = arena(true)
        model.snapshot = model.snapshot.copy(world = ArenaWorld(1008.0, 672.0, 12, 8, listOf(wall)))
        // Use a fresh arena whose collision geometry contains the separating wall.
        val blocked = PracticeArena(42, "Alpha", 0, 0, world = model.snapshot.world)
        blocked.snapshot.tanks = model.snapshot.tanks.map { it.copy() }
        val resolve = PracticeArena::class.java.getDeclaredMethod("starmanContacts").apply { isAccessible = true }
        resolve.invoke(blocked)
        assertTrue(blocked.snapshot.tanks.all { it.hp == 1 })
        val ordinary = arena(true); ordinary.snapshot.tanks.last().starmanTime = 0.0
        ordinary.step(GameInput(), dt)
        assertEquals(1, ordinary.snapshot.tanks.first().hp); assertEquals(0, ordinary.snapshot.tanks.last().hp)
    }
}
