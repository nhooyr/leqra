package com.leqra.core

import kotlin.math.hypot
import org.junit.Assert.*
import org.junit.Test

class LaserTuningTest {
    @Test
    fun laserPiercesEveryOpponentOnceAndKeepsDefenses() {
        val world =
            ArenaWorld(
                672.0,
                420.0,
                8,
                5,
                listOf(
                    MazeWall(-4.0, -4.0, 680.0, 8.0, "h", 0.0),
                    MazeWall(-4.0, 416.0, 680.0, 8.0, "h", 420.0),
                    MazeWall(-4.0, -4.0, 8.0, 428.0, "v", 0.0),
                    MazeWall(668.0, -4.0, 8.0, 428.0, "v", 672.0),
                ),
            )
        val arena = PracticeArena(42, "LASER", 0, 0, world = world)
        arena.configure(RoomRules(pickupRate = "off"))
        arena.snapshot.tanks =
            listOf(
                ArenaTank(
                    id = 1,
                    x = 90.0,
                    y = 210.0,
                    powerTime = 10.0,
                    power = "laser",
                    charges = 3,
                    team = 1,
                ),
                ArenaTank(id = 2, x = 190.0, y = 210.0, shield = 10.0, shieldCharges = 3, team = 2),
                ArenaTank(id = 3, x = 290.0, y = 210.0, team = 2),
                ArenaTank(
                    id = 4,
                    x = 390.0,
                    y = 210.0,
                    invulnerable = 1.0,
                    spawnProtected = true,
                    team = 2,
                ),
                ArenaTank(id = 5, x = 490.0, y = 210.0, team = 1),
                ArenaTank(id = 6, x = 590.0, y = 210.0, team = 2),
            )
        arena.step(GameInput(fire = true), 1.0 / 60)
        assertEquals(listOf(1, 1, 0, 1, 1, 0), arena.snapshot.tanks.map { it.hp })
        assertEquals(2, arena.snapshot.tanks[1].shieldCharges)
        assertEquals(2, arena.snapshot.tanks[0].charges)
        val points = arena.snapshot.effects.first { it.kind == "laser" }.points
        assertEquals(
            4 * (world.width + world.height) - 28,
            points.zipWithNext().sumOf { (a, b) -> hypot(b.x - a.x, b.y - a.y) },
            .1,
        )
    }

    @Test
    fun chargedLaserAndCannonShareTheFasterReloadCadence() {
        for (kind in listOf("laser", "cannon")) {
            assertEquals(.85 / 3, PracticeArena.spec(kind).cooldown, 1e-12)
            val arena = PracticeArena(123, "Pilot", 0, 0, world = ArenaWorld(1000.0, 1000.0))
            arena.snapshot.tanks.first().apply {
                x = 500.0
                y = 500.0
                invulnerable = 0.0
                spawnProtected = false
            }
            val tank = arena.snapshot.tanks.first()
            PracticeArena.applyPower(tank, kind)
            arena.step(GameInput(fire = true), 1.0 / 60)
            assertEquals(.85 / 3, tank.cooldownTotal, 1e-12)
            assertEquals(2, tank.charges)
            repeat(16) { arena.step(GameInput(fire = true), 1.0 / 60) }
            assertEquals("$kind cannot fire before its17tick reload", 2, tank.charges)
            arena.step(GameInput(fire = true), 1.0 / 60)
            assertEquals("$kind fires its next charge after17ticks", 1, tank.charges)
            val hud =
                PilotReadout(
                    tank.copy(cooldown = .85 / 6, cooldownTotal = 0.0),
                    arena.snapshot,
                    false,
                )
            assertEquals(.5, hud.progress, 1e-12)
        }
        assertEquals(5.3, PracticeArena.spec("cannon").life, 0.0)
        assertEquals(18 * 84.0 / 235, PracticeArena.spec("homing").life, 0.0)
    }

    @Test
    fun doubledLaserBudgetSurvivesMoreThan128CorridorReflections() {
        val world =
            ArenaWorld(
                4200.0,
                168.0,
                50,
                2,
                listOf(
                    MazeWall(0.0, 0.0, 4.0, 168.0, "v", 0.0),
                    MazeWall(110.0, 0.0, 8.0, 168.0, "v", 114.0),
                ),
            )
        val maze = InfiniteMaze(world)
        val budget = 4 * (world.width + world.height)
        val guide = maze.laserGuide(42.0, 42.0, 0.0, range = budget)
        assertTrue("The true2x beam exceeds the old128reflection cap", guide.size > 129)
        assertTrue(guide.size <= 257)
        assertEquals(
            budget - 28,
            guide.zipWithNext().sumOf { (a, b) -> hypot(b.x - a.x, b.y - a.y) },
            .5,
        )
        val arena = PracticeArena(123, "Pilot", 0, 0, world = world)
        arena.snapshot.tanks.first().apply {
            x = 42.0
            y = 42.0
            angle = 0.0
            invulnerable = 0.0
            spawnProtected = false
        }
        PracticeArena.applyPower(arena.snapshot.tanks.first(), "laser")
        arena.step(GameInput(fire = true), 1.0 / 60)
        val beam = arena.snapshot.effects.single { it.kind == "laser" }
        assertEquals(guide.size, beam.points.size)
        assertEquals(guide.last().x, beam.points.last().x, 1e-6)
        val infinityGuide = InfiniteMaze(123).laserGuide(42.0, 42.0, 0.0)
        assertEquals(
            36 * 84.0 - 28,
            infinityGuide.zipWithNext().sumOf { (a, b) -> hypot(b.x - a.x, b.y - a.y) },
            .5,
        )
    }
}
