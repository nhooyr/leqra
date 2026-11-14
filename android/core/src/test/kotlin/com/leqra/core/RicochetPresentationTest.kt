package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class RicochetPresentationTest {
    @Test
    fun wallAndCornerRicochetsMoveOnBothSidesOfTheActualImpact() {
        for (corner in listOf(false, true)) for (kind in listOf("", "rapid", "scatter")) {
            val world =
                ArenaWorld(
                    width = 200.0,
                    height = 200.0,
                    walls =
                        listOf(MazeWall(x = 100.0, y = 0.0, w = 6.0, h = 200.0)) +
                            if (corner) listOf(MazeWall(x = 0.0, y = 100.0, w = 200.0, h = 6.0))
                            else emptyList(),
                )
            val maze = InfiniteMaze(world)
            val radius = PracticeArena.spec(kind).radius
            val contact = 100 - radius
            val first =
                ArenaBullet(
                    id = 1,
                    kind = kind,
                    x = 90.0,
                    y = if (corner) 90.0 else 50.0,
                    vx = 300.0,
                    vy = if (corner) 300.0 else 0.0,
                    life = 5.0,
                )
            val span = 1.0 / 30
            val after = contact - .08 - (300 * span - (contact - first.x))
            val second =
                first.copy(
                    x = after,
                    y = if (corner) after else first.y,
                    vx = -300.0,
                    vy = if (corner) -300.0 else 0.0,
                    bounces = 1,
                    life = first.life - span,
                )
            val savedFirst = first.copy()
            val savedSecond = second.copy()
            val path = RicochetPath.between(first, second, span, maze)
            assertNotNull("$kind corner=$corner", path)
            val samples = (0..4).map { path!!.sample(second, first, it / 4.0) }
            assertEquals(first.x, samples.first().x, 1e-9)
            assertEquals(second.x, samples.last().x, 1e-9)
            assertTrue(samples[1].x > samples[0].x)
            val impactFraction = (contact - first.x) / (300 * span)
            assertTrue(path!!.sample(second, first, (impactFraction + 1) / 2).x > second.x)
            assertTrue(
                samples.all { it.x <= contact + 1e-9 && (!corner || it.y <= contact + 1e-9) }
            )
            assertEquals(savedFirst, first)
            assertEquals(savedSecond, second)
            val timeline = OnlinePresentation(localID = 99, maze = maze)
            timeline.accept(ArenaSnapshot(tick = 0, world = world, bullets = listOf(first)), 0.0)
            timeline.accept(ArenaSnapshot(tick = 2, world = world, bullets = listOf(second)), span)
            val image = timeline.render(.1, GameInput(), .1) {}!!.bullets.single()
            assertTrue("Ricochet must not hold the old 30 Hz pose", image.x > first.x)
            assertTrue(image.x <= contact)
        }
    }

    @Test
    fun cannonProjectsOnlyOuterBoundaryAndBadOrGuidedPathsStaySafe() {
        val maze = InfiniteMaze(ArenaWorld(width = 200.0, height = 200.0))
        val first =
            ArenaBullet(id = 1, x = 180.0, y = 90.0, vx = 1128.0, life = 5.0, kind = "cannon")
        val duration = 1.0 / 30
        val second =
            first.copy(
                x = 182 - .08 - (1128 * duration - 2),
                vx = -1128.0,
                life = 5 - duration,
                bounces = 1,
            )
        assertNotNull(RicochetPath.between(first, second, duration, maze))
        assertNull(RicochetPath.between(first, second.copy(x = second.x - 2), duration, maze))
        assertNull(RicochetPath.between(first, second.copy(bounces = 2), duration, maze))
        assertNull(
            RicochetPath.between(
                first.copy(kind = "homing"),
                second.copy(kind = "homing"),
                duration,
                maze,
            )
        )
        assertNull(RicochetPath.between(first, second, duration, null))
    }
}
