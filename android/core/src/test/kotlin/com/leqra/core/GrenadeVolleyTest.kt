package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class GrenadeVolleyTest {
    @Test
    fun targetScoreIsCheckedAfterEveryVictimInTheBlast() {
        val arena = PracticeArena(42, "Attacker", 0, 0)
        arena.configure(
            RoomRules.localDefaults("infinity")
                .copy(infinityTarget = 1, infinityRandomBots = false),
        )
        val attacker = ArenaTank(id = 1, name = "Attacker", x = 500.0, y = 500.0)
        val victims =
            (2..4).map { ArenaTank(id = it, name = "Victim$it", x = 500.0 + it * 10, y = 500.0) }
        arena.snapshot.tanks = listOf(attacker) + victims
        val blast = ArenaBullet(id = 80, owner = 1, x = 530.0, y = 500.0, kind = "grenade")
        val detonate =
            PracticeArena::class
                .java
                .getDeclaredMethod(
                    "detonate",
                    ArenaBullet::class.java,
                    ProjectileFlight::class.java,
                )
                .apply { isAccessible = true }
        detonate.invoke(arena, blast, null)
        assertTrue(victims.all { it.hp == 0 })
        assertEquals(3, attacker.score)
        val standings =
            PracticeArena::class.java.getDeclaredMethod("updateStandings").apply {
                isAccessible = true
            }
        standings.invoke(arena)
        assertEquals(3, arena.snapshot.result!!.score)
    }
}
