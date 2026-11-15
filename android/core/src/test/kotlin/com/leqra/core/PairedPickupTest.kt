package com.leqra.core

import kotlin.math.hypot
import org.junit.Assert.*
import org.junit.Test

class PairedPickupTest {
    private fun populate(arena: PracticeArena) {
        PracticeArena::class.java.getDeclaredField("time").apply { isAccessible = true }.setDouble(arena, 10.0)
        PracticeArena::class.java.getDeclaredField("nextPickup").apply { isAccessible = true }.setDouble(arena, 0.0)
        PracticeArena::class.java.getDeclaredMethod("populatePickups", Double::class.javaPrimitiveType).apply { isAccessible = true }.invoke(arena, 1.0 / 60)
    }

    @Test fun everyLivingSeparatedPilotGetsNearbyPickupsOnTheSameInterval() {
        val arena = PracticeArena(123, "One", 0, 0)
        arena.configureLocal("Two", 1)
        arena.snapshot.tanks[1].apply { x = 10000.0; y = -10000.0 }
        populate(arena)
        for (pilot in arena.snapshot.tanks) assertEquals(3, arena.snapshot.pickups.count { hypot(it.x - pilot.x, it.y - pilot.y) < 5 * 84 })
        arena.snapshot.pickups = emptyList()
        arena.snapshot.tanks[0].hp = 0
        populate(arena)
        assertEquals(3, arena.snapshot.pickups.size)
        assertTrue(arena.snapshot.pickups.all { hypot(it.x - 10000, it.y + 10000) < 5 * 84 })
    }

    @Test fun deadSeatsKeepTheirAnchoredPickupsAndContributeToTheGlobalBudget() {
        val arena = PracticeArena(123, "One", 0, 0)
        arena.configureLocal("Two", 1)
        val dead = arena.snapshot.tanks[1].apply { x = 10000.0; y = -10000.0; hp = 0 }
        arena.snapshot.pickups = (0..6).map { ArenaPickup(id = 200 + it, x = dead.x + it * 90, y = dead.y, type = "speed") } +
            ArenaPickup(id = 999, x = -100000.0, y = 100000.0, type = "shield")
        populate(arena)
        assertEquals("All seven dead-seat anchors remain, while the living seat receives three", 10, arena.snapshot.pickups.size)
        assertFalse(arena.snapshot.pickups.any { it.id == 999 })
        assertTrue(arena.snapshot.pickups.filter { it.id in 200..206 }.all { it.life < 30 })
        assertEquals(3, arena.snapshot.pickups.count { hypot(it.x - arena.snapshot.tanks[0].x, it.y - arena.snapshot.tanks[0].y) < 5 * 84 })
    }
}
