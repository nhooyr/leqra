package com.leqra.core

import kotlin.math.hypot
import org.junit.Assert.*
import org.junit.Test

class LaserTuningTest {
    @Test fun chargedLaserAndCannonReloadInTwoThirdsOfTheirPreviousTime() {
        for (kind in listOf("laser", "cannon")) {
            assertEquals(.85 * 2 / 3, PracticeArena.spec(kind).cooldown, 1e-12)
            val arena = PracticeArena(123, "Pilot", 0, 0, world = ArenaWorld(1000.0, 1000.0))
            arena.snapshot.tanks.first().apply { x = 500.0; y = 500.0; invulnerable = 0.0; spawnProtected = false }
            val tank = arena.snapshot.tanks.first()
            PracticeArena.applyPower(tank, kind)
            arena.step(GameInput(fire = true), 1.0 / 60)
            assertEquals(.85 * 2 / 3, tank.cooldownTotal, 1e-12)
            assertEquals(2, tank.charges)
            repeat(34) { arena.step(GameInput(fire = true), 1.0 / 60) }
            assertEquals("$kind fires its next charge after34ticks", 1, tank.charges)
            val hud = PilotReadout(tank.copy(cooldown = .85 / 3, cooldownTotal = 0.0), arena.snapshot, false)
            assertEquals(.5, hud.progress, 1e-12)
        }
        assertEquals(5.3, PracticeArena.spec("cannon").life, 0.0)
        assertEquals(18 * 84.0 / 235, PracticeArena.spec("homing").life, 0.0)
    }

    @Test fun doubledLaserBudgetSurvivesMoreThan128CorridorReflections() {
        val world = ArenaWorld(4200.0, 168.0, 50, 2,
            listOf(MazeWall(0.0, 0.0, 4.0, 168.0, "v", 0.0), MazeWall(110.0, 0.0, 8.0, 168.0, "v", 114.0)))
        val maze = InfiniteMaze(world)
        val budget = 4 * (world.width + world.height)
        val guide = maze.laserGuide(42.0, 42.0, 0.0, range = budget)
        assertTrue("The true2x beam exceeds the old128reflection cap", guide.size > 129)
        assertTrue(guide.size <= 257)
        assertEquals(budget - 28, guide.zipWithNext().sumOf { (a,b) -> hypot(b.x-a.x,b.y-a.y) }, .5)
        val arena = PracticeArena(123, "Pilot", 0, 0, world = world)
        arena.snapshot.tanks.first().apply { x = 42.0; y = 42.0; angle = 0.0; invulnerable = 0.0; spawnProtected = false }
        PracticeArena.applyPower(arena.snapshot.tanks.first(), "laser")
        arena.step(GameInput(fire = true), 1.0 / 60)
        val beam = arena.snapshot.effects.single { it.kind == "laser" }
        assertEquals(guide.size, beam.points.size)
        assertEquals(guide.last().x, beam.points.last().x, 1e-6)
        val infinityGuide = InfiniteMaze(123).laserGuide(42.0, 42.0, 0.0)
        assertEquals(36 * 84.0 - 28, infinityGuide.zipWithNext().sumOf { (a,b) -> hypot(b.x-a.x,b.y-a.y) }, .5)
    }
}
