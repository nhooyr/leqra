package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class StarmanMovementTest {
    @Test
    fun authoritativeTicksAgeStarmanOnceAndPredictionExpiresWithoutAnotherSnapshot() {
        val world = ArenaWorld(width = 10000.0, height = 10000.0)
        val arena = PracticeArena(123, "P1", 0, 0, world = world)
        val tank =
            arena.snapshot.tanks.first().apply {
                x = 5000.0
                y = 5000.0
                starmanTime = .02
                spawnProtected = false
            }
        val input = GameInput(forward = true, touchAim = false)
        arena.step(input, 1.0 / 60)
        assertEquals(.02 - 1.0 / 60, tank.starmanTime, 1e-10)
        val timeline = OnlinePresentation(maze = InfiniteMaze(world))
        timeline.accept(
            ArenaSnapshot(
                tick = 1,
                world = world,
                tanks = listOf(ArenaTank(id = 1, x = 5000.0, y = 5000.0, starmanTime = .02)),
            ),
            0.0,
        )
        timeline.render(1.0 / 60, input, 1.0 / 60) {}
        val second = timeline.render(1.0 / 60, input, 2.0 / 60) {}!!.tanks.single()
        assertEquals(0.0, second.starmanTime, 0.0)
        assertEquals(5000 + (128 * 2.3 + 128) / 60, second.x, 1e-8)
    }

    @Test
    fun starmanMatchesTwoSpeedPickupsWithoutReplacingStrongerEquipment() {
        val input = GameInput(forward = true, right = true, touchAim = false)
        val world = ArenaWorld(width = 20000.0, height = 20000.0)
        for (stacks in 0..5) for (bot in listOf(false, true)) {
            val tank =
                ArenaTank(
                    x = 5000.0,
                    y = 5000.0,
                    starmanTime = 8.0,
                    speedTime = if (stacks > 0) 15.0 else 0.0,
                    speedStacks = stacks,
                )
            val expected =
                tank.copy(starmanTime = 0.0, speedTime = 15.0, speedStacks = maxOf(2, stacks))
            if (bot) {
                TankMovement.stepBot(tank, input.copy(stickX = 1.0, stickY = 1.0), 1.0 / 60, world)
                TankMovement.stepBot(
                    expected,
                    input.copy(stickX = 1.0, stickY = 1.0),
                    1.0 / 60,
                    world,
                )
            } else {
                TankMovement.step(tank, input, 1.0 / 60, world.walls, world.width, world.height)
                TankMovement.step(expected, input, 1.0 / 60, world.walls, world.width, world.height)
            }
            assertEquals("movement stacks=$stacks bot=$bot", expected.x, tank.x, 1e-10)
            assertEquals(expected.y, tank.y, 1e-10)
            assertEquals(expected.angle, tank.angle, 1e-10)
            assertEquals("Starman must preserve actual pickup count", stacks, tank.speedStacks)
            assertEquals(if (stacks > 0) 15.0 - 1.0 / 60 else 0.0, tank.speedTime, 1e-10)
            tank.starmanTime = 0.0
            assertEquals(stacks, TankMovement.effectiveSpeedStacks(tank))
        }
    }

    @Test
    fun infinityAndPresentationUseTheSameSpeedFloorWithoutMutatingAuthoritativeEquipment() {
        val maze = InfiniteMaze(123)
        val tank = ArenaTank(x = 42.0, y = 42.0, starmanTime = 8.0, ghostTime = 8.0)
        val expected = tank.copy(starmanTime = 0.0, speedTime = 15.0, speedStacks = 2)
        val input = GameInput(forward = true, right = true, touchAim = false)
        val move: (ArenaTank, GameInput, Double) -> Unit = { t, i, dt ->
            TankMovement.step(t, i, dt, maze)
        }
        val before = tank.copy()
        for (fraction in listOf(.1, .5, .9)) {
            val actual = TankMovement.presentation(tank, input, fraction, move = move)
            val reference = TankMovement.presentation(expected, input, fraction, move = move)
            assertEquals(reference.x, actual.x, 1e-10)
            assertEquals(reference.y, actual.y, 1e-10)
            assertEquals(reference.angle, actual.angle, 1e-10)
        }
        assertEquals(before, tank)
        TankMovement.step(tank, input, 1.0 / 60, maze)
        TankMovement.step(expected, input, 1.0 / 60, maze)
        assertEquals(expected.x, tank.x, 1e-10)
        assertEquals(expected.y, tank.y, 1e-10)
    }
}
