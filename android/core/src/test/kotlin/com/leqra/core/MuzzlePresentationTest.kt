package com.leqra.core

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MuzzlePresentationTest {
    @Test
    fun independentTurretFiresAlongBarrelWhileHullKeepsDriving() {
        for (kind in listOf("", "rapid", "scatter", "homing", "grenade", "cannon", "laser")) {
            val game =
                PracticeArena(
                    seed = 42,
                    name = "Pilot",
                    colorIndex = 0,
                    botCount = 0,
                    world = ArenaWorld(width = 840.0, height = 840.0),
                )
            val pilot = ArenaTank(id = 1, x = 200.0, y = 200.0)
            if (kind.isNotEmpty()) PracticeArena.applyPower(pilot, kind)
            game.snapshot.tanks = listOf(pilot)
            game.step(GameInput(fire = true, stickX = 1.0, aimY = -1.0), 1.0 / 120)
            val moved = game.snapshot.tanks.first()
            assertTrue(moved.x > 200)
            assertEquals(200.0, moved.y, 1e-8)
            assertEquals(0.0, moved.movementAngle, 1e-8)
            assertEquals(-PI / 2, moved.angle, 1e-8)
            if (kind == "laser") {
                val points = game.snapshot.effects.first { it.kind == "laser" }.points
                assertEquals(moved.x, points.first().x, 1e-8)
                assertTrue(points.first().y < moved.y)
                assertEquals(points.first().x, points[1].x, 1e-8)
                assertTrue(points[1].y < points.first().y)
            } else {
                assertTrue(kind, game.snapshot.bullets.isNotEmpty())
                for (bullet in game.snapshot.bullets) {
                    assertTrue(kind, bullet.vy < 0)
                    assertTrue(kind, kotlin.math.abs(bullet.vx) < kotlin.math.abs(bullet.vy) * .25)
                    assertTrue(kind, bullet.y < moved.y)
                    if (kind != "scatter") assertEquals(moved.x, bullet.x, 1e-8)
                }
            }
        }
    }

    @Test
    fun barrelRetractsToWallAndExtendsWhenTurningAway() {
        val maze =
            InfiniteMaze(
                ArenaWorld(
                    width = 840.0,
                    height = 840.0,
                    walls = listOf(MazeWall(122.0, 50.0, 8.0, 100.0)),
                ),
            )
        for (recoil in listOf(0.0, .5, 1.0)) {
            val tank = ArenaTank(x = 100.0, y = 100.0, angle = 0.0)
            assertEquals(9.5, MuzzlePresentation.retraction(tank, maze, recoil), 1e-7)
            tank.angle = PI
            assertEquals(recoil * 4, MuzzlePresentation.retraction(tank, maze, recoil), 1e-7)
        }
    }

    @Test
    fun touchKeepsFastTurnsAndFineAim() {
        val touch = GameInput(stickY = 1.0, touchAim = true)
        val stick = GameInput(stickY = 1.0, touchAim = false)
        assertEquals(9.0 / 60, TankMovement.steer(0.0, touch, dt = 1.0 / 60).angle, 1e-12)
        assertEquals(5.8 / 60, TankMovement.steer(0.0, stick, dt = 1.0 / 60).angle, 1e-12)
        val fine = GameInput(stickX = cos(.04), stickY = sin(.04), touchAim = true)
        assertEquals(.04, TankMovement.steer(0.0, fine, dt = 1.0 / 60).angle, 1e-12)
    }

    @Test
    fun cornerGrazingUsesProjectileWidth() {
        val maze =
            InfiniteMaze(
                ArenaWorld(
                    width = 840.0,
                    height = 840.0,
                    walls = listOf(MazeWall(122.0, 102.5, 8.0, 40.0)),
                ),
            )
        val tank = ArenaTank(x = 100.0, y = 100.0, angle = 0.0)
        assertTrue(MuzzlePresentation.retraction(tank, maze) > 0)
        tank.power = "rapid"
        assertEquals(0.0, MuzzlePresentation.retraction(tank, maze), 0.0)
    }

    @Test
    fun nearWallLaunchDoesNotInstantlyTravelBackThroughBarrel() {
        val wall = MazeWall(122.0, 50.0, 8.0, 100.0)
        for (kind in listOf("", "rapid", "scatter", "homing", "grenade")) {
            val game =
                PracticeArena(
                    seed = 42,
                    name = "Pilot",
                    colorIndex = 0,
                    botCount = 0,
                    world = ArenaWorld(width = 840.0, height = 840.0, walls = listOf(wall)),
                )
            val pilot = ArenaTank(id = 1, x = 100.0, y = 100.0)
            if (kind.isNotEmpty()) PracticeArena.applyPower(pilot, kind)
            game.snapshot.tanks = listOf(pilot)
            game.step(GameInput(fire = true), 1.0 / 120)
            val bullet = game.snapshot.bullets.first()
            val spec = PracticeArena.spec(kind)
            assertTrue(kind, bullet.vx < 0)
            assertTrue(kind, bullet.x >= wall.x - spec.radius - .13 - spec.speed / 120)
        }
    }

    @Test
    fun pointBlankPlaybackStartsAtContactInsteadOfTankCentre() {
        for (kind in listOf("", "rapid", "scatter", "homing", "grenade")) {
            val game =
                PracticeArena(
                    seed = 42,
                    name = "Pilot",
                    colorIndex = 0,
                    botCount = 0,
                    world = ArenaWorld(width = 840.0, height = 840.0),
                )
            val pilot = ArenaTank(id = 1, x = 100.0, y = 100.0)
            if (kind.isNotEmpty()) PracticeArena.applyPower(pilot, kind)
            game.snapshot.tanks = listOf(pilot, ArenaTank(id = 2, x = 135.0, y = 100.0))
            game.step(GameInput(fire = true), 1.0 / 120)
            val flight = game.snapshot.effects.mapNotNull { it.flight }.first()
            assertTrue(kind, flight.points.first().x > 101)
        }
    }

    @Test
    fun ghostCentreOutsideWallHandlesAnOverlappingMuzzle() {
        val wall = MazeWall(122.0, 50.0, 8.0, 100.0)
        for (kind in listOf("", "rapid", "scatter", "homing", "grenade")) {
            val game =
                PracticeArena(
                    seed = 42,
                    name = "Ghost",
                    colorIndex = 0,
                    botCount = 0,
                    world = ArenaWorld(width = 840.0, height = 840.0, walls = listOf(wall)),
                )
            val pilot =
                ArenaTank(id = 1, x = 121.0, y = 100.0, bodyAngle = PI / 2, independentAim = true)
            PracticeArena.applyPower(pilot, "ghost")
            if (kind.isNotEmpty()) PracticeArena.applyPower(pilot, kind)
            assertTrue(30 - MuzzlePresentation.retraction(pilot, game.maze) <= 1.1)
            game.snapshot.tanks = listOf(pilot)
            game.step(GameInput(fire = true, aimX = 1.0), 1.0 / 120)
            assertEquals(PI / 2, game.snapshot.tanks.first().movementAngle, 1e-8)
            val bullet = game.snapshot.bullets.first()
            assertTrue(bullet.vx < 0)
            assertTrue(
                bullet.x >=
                    wall.x -
                        PracticeArena.spec(kind).radius -
                        .13 -
                        kotlin.math.hypot(bullet.vx, bullet.vy) / 120,
            )
        }
    }
}
