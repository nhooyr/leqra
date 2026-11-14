package com.leqra.core

import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class OnlinePresentationTest {
    private val tick = 1.0 / 60

    @Test
    fun projectileIndicesHandleAllIntKeysGrowthAndRemovalWithoutOldEntities() {
        val t = timeline()
        val ids = listOf(0, Int.MAX_VALUE, Int.MIN_VALUE, -1, 16, 65536, 1_000_000)
        fun sample(tick: Long, keys: List<Int>) =
            state(tick = tick).apply {
                bullets = keys.mapIndexed { index, id ->
                    ArenaBullet(id = id, x = index * 10.0 + tick, y = 300.0, life = 5.0)
                }
            }
        t.accept(sample(0, ids), 0.0)
        t.accept(sample(2, ids), 2.0 / 60)
        var image = render(t, now = 2.0 / 60)
        assertEquals(ids, image.bullets.map { it.id })
        ids.forEachIndexed { index, _ -> assertEquals(index * 10.0, image.bullets[index].x, 1e-9) }
        val grown = (1000..3999).toList()
        t.accept(sample(4, grown), 4.0 / 60)
        repeat(30) { index -> image = render(t, 1.0 / 120, now = 4.0 / 60 + (index + 1) / 120.0) }
        assertEquals(grown.toSet(), image.bullets.map { it.id }.toSet())
        t.accept(sample(6, listOf(Int.MIN_VALUE, 0)), .4)
        repeat(30) { index -> image = render(t, 1.0 / 120, now = .4 + (index + 1) / 120.0) }
        assertEquals(setOf(Int.MIN_VALUE, 0), image.bullets.map { it.id }.toSet())
        t.reset()
        t.accept(sample(8, emptyList()), 1.0)
        assertTrue(render(t, now = 1.0).bullets.isEmpty())
    }

    private fun timeline(localID: Int = 1, speed: Double = 60.0, maze: InfiniteMaze? = null) =
        OnlinePresentation(
            localID = localID,
            maze = maze,
            movement = { t, c, dt ->
                if (c.forward) {
                    t.x += dt * speed
                    t.track += dt * speed
                }
                if (c.reverse) {
                    t.x -= dt * speed
                    t.track -= dt * speed
                }
            },
        )

    private fun state(
        tick: Long = 0,
        generation: Int = 1,
        x: Double = 100.0,
        hp: Int = 1,
        spawn: Int = 1,
        ack: Long = 0,
        ackSteps: Int = 0,
        ghost: Double = 0.0,
        world: ArenaWorld? = null,
    ) =
        ArenaSnapshot(
            tick = tick,
            generation = generation,
            tanks =
                listOf(
                    ArenaTank(
                        id = 1,
                        name = "PILOT",
                        x = x,
                        y = 210.0,
                        hp = hp,
                        spawnSerial = spawn,
                        ack = ack,
                        ackSteps = ackSteps,
                        track = x,
                        ghostTime = ghost,
                        speedTime = 15.0,
                        speedStacks = 5,
                    ),
                ),
            world = world,
        )

    private fun render(
        t: OnlinePresentation,
        dt: Double = 0.0,
        input: GameInput = GameInput(),
        now: Double = 0.0,
        send: (GameInput) -> Unit = {},
    ): ArenaSnapshot = t.render(dt, input, now, send = send)!!

    @Test
    fun everyDisplayRateEmitsOnlySixtyInputsAndSameMovement() {
        for (hz in listOf(60, 90, 120, 144)) {
            val t = timeline()
            t.accept(state(x = 0.0), 0.0)
            val packets = mutableListOf<GameInput>()
            var image = state()
            for (frame in 1..hz) image =
                render(t, 1.0 / hz, GameInput(forward = true), frame.toDouble() / hz) {
                    packets.add(it)
                }
            assertEquals(60, packets.size)
            assertEquals((1L..60L).toList(), packets.map { it.seq })
            assertEquals(60.0, image.tanks.first().x, 1e-9)
        }
    }

    @Test
    fun subframeMovesWithoutExtraPacketAndStallsBoundCatchUp() {
        val t = timeline()
        t.accept(state(x = 0.0), 0.0)
        val packets = mutableListOf<GameInput>()
        val half = render(t, 1.0 / 120, GameInput(forward = true), 1.0 / 120) { packets.add(it) }
        assertEquals(.5, half.tanks[0].x, 1e-9)
        assertTrue(packets.isEmpty())
        val full = render(t, 1.0 / 120, GameInput(forward = true), tick) { packets.add(it) }
        assertEquals(1.0, full.tanks[0].x, 1e-9)
        assertEquals(1, packets.size)
        packets.clear()
        render(t, 5.0, GameInput(forward = true), 1.0) { packets.add(it) }
        assertEquals(6, packets.size)
    }

    @Test
    fun heldAcknowledgementReplaysOnlyUnconsumedSteps() {
        val t = timeline()
        t.accept(state(tick = 60, x = 0.0), 0.0)
        render(t, 2 * tick, GameInput(forward = true), 2 * tick)
        render(t, 2 * tick, GameInput(reverse = true), 4 * tick)
        t.accept(state(tick = 62, x = 2.0, ack = 1, ackSteps = 2), 4 * tick)
        t.neutralize()
        assertEquals(0.0, render(t, now = 4 * tick).tanks[0].x, 1e-9)
        t.accept(state(tick = 64, x = 4.0, ack = 1, ackSteps = 4), 5 * tick)
        assertEquals(0.0, render(t, now = 5 * tick).tanks[0].x, 1e-9)
        var result = state()
        for (frame in 1..120) result = render(t, 1.0 / 120, now = 5 * tick + frame / 120.0)
        assertEquals(4.0, result.tanks[0].x, .001)
    }

    @Test
    fun deathRespawnAndGenerationDiscardOldLifeButKeepSequenceIncreasing() {
        val t = timeline()
        t.accept(state(tick = 100, x = 0.0), 0.0)
        val packets = mutableListOf<GameInput>()
        render(t, 2 * tick, GameInput(forward = true), 2 * tick) { packets.add(it) }
        t.accept(state(tick = 102, x = 500.0, hp = 0), 3 * tick)
        val dead = render(t, tick, GameInput(forward = true), 4 * tick) { packets.add(it) }
        assertEquals(0, dead.tanks[0].hp)
        assertEquals(500.0, dead.tanks[0].x, 0.0)
        t.accept(state(tick = 1, generation = 2, x = 800.0, spawn = 2), 5 * tick)
        val fresh = render(t, now = 5 * tick)
        assertEquals(800.0, fresh.tanks[0].x, 0.0)
        assertEquals(2, fresh.tanks[0].spawnSerial)
        render(t, tick, now = 6 * tick) { packets.add(it) }
        assertEquals(listOf(1L, 2L, 3L, 4L), packets.map { it.seq })
    }

    @Test
    fun oldPacketsCannotResurrectOrRewindGeneration() {
        val t = timeline()
        t.accept(state(tick = 10, x = 100.0, hp = 0), 0.0)
        t.accept(state(tick = 9, x = 80.0), .01)
        assertEquals(0, render(t, now = .01).tanks[0].hp)
        t.accept(state(tick = 200, generation = 0, x = 80.0), .02)
        val latest = render(t, now = .02)
        assertEquals(1, latest.generation)
        assertEquals(10L, latest.tick)
    }

    @Test
    fun remoteDeathRespawnAndGhostExpiryNeverInterpolateOldLife() {
        val t = timeline(99)
        t.accept(state(x = 0.0), 0.0)
        t.accept(state(tick = 2, x = 10.0, hp = 0), 2 * tick)
        assertEquals(10.0, render(t, 1.0 / 120, now = 3 * tick).tanks[0].x, 0.0)
        t.accept(state(tick = 4, x = 100.0, spawn = 2), 4 * tick)
        assertEquals(100.0, render(t, 1.0 / 120, now = 5 * tick).tanks[0].x, 0.0)
        val g = timeline(99)
        g.accept(state(x = 84.0, ghost = .02), 0.0)
        g.accept(state(tick = 2, x = 62.99), 2 * tick)
        assertEquals(62.99, render(g, 1.0 / 120, now = 3 * tick).tanks[0].x, 0.0)
    }

    @Test
    fun staleConnectionFreezesAndSendsNeutralWithBoundedHistory() {
        val t = timeline()
        t.accept(state(x = 0.0), 0.0)
        val held = GameInput(forward = true, fire = true, stickX = 1.0, stickY = -.5)
        render(t, tick, held, tick)
        val packets = mutableListOf<GameInput>()
        val frozen = render(t, tick, held, 3.0) { packets.add(it) }
        assertTrue(t.stale)
        assertEquals(1.0, frozen.tanks[0].x, 1e-9)
        repeat(1200) { i ->
            val image = render(t, tick, held, 4 + i * tick) { packets.add(it) }
            assertEquals(1.0, image.tanks[0].x, 1e-9)
        }
        assertTrue(
            packets.all {
                !it.fire &&
                    !it.forward &&
                    !it.reverse &&
                    !it.left &&
                    !it.right &&
                    it.stickX == 0.0 &&
                    it.stickY == 0.0
            },
        )
        repeat(1000) { t.neutralPacket() }
        assertTrue(t.bufferedAcknowledgementCount <= 240)
        assertTrue(t.bufferedFrameCount <= 240)
    }

    @Test
    fun pauseNeutralPacketsAreMonotonicAndRecoverySnapsWithoutReplayingOldInput() {
        val t = timeline()
        t.accept(state(), 0.0)
        val packets = mutableListOf<GameInput>()
        render(t, tick, GameInput(fire = true), tick) { packets.add(it) }
        packets.add(t.neutralPacket())
        render(t, 1.0 / 120, GameInput(fire = true), 2 * tick) { packets.add(it) }
        packets.add(t.neutralPacket())
        render(t, tick, GameInput(fire = true), 3 * tick) { packets.add(it) }
        assertEquals(listOf(1L, 2L, 3L, 4L), packets.map { it.seq })
        assertFalse(packets[1].fire)
        assertFalse(packets[2].fire)
        t.accept(state(tick = 180, x = 120.0, ack = 4), 3.0)
        assertEquals(120.0, render(t, now = 3.0).tanks[0].x, 0.0)
        assertFalse(t.stale)
        var seq = 0L
        render(t, tick, now = 3 + tick) { seq = it.seq }
        assertEquals(5L, seq)
    }

    @Test
    fun projectilesEnterDelayedTimelineMonotonicallyAndDespawnImmediately() {
        val t = timeline(99)
        t.accept(ArenaSnapshot(tick = 0), 0.0)
        val positions = mutableListOf<Double>()
        for (frame in 1..48) {
            val now = frame / 120.0
            if (frame % 4 == 0) {
                val stamp = (frame / 2).toLong()
                t.accept(
                    ArenaSnapshot(
                        tick = stamp,
                        bullets =
                            listOf(
                                ArenaBullet(
                                    id = 1,
                                    x = stamp * 10.0,
                                    y = 42.0,
                                    vx = 600.0,
                                    owner = 2,
                                    kind = "cannon",
                                    life = 5.0,
                                ),
                            ),
                    ),
                    now,
                )
            }
            render(t, 1.0 / 120, now = now).bullets.firstOrNull()?.let { positions.add(it.x) }
        }
        assertTrue(positions.size > 20)
        positions.zipWithNext().forEach { assertTrue(it.second >= it.first) }
        assertTrue(positions.toSet().size > 20)
        t.accept(ArenaSnapshot(tick = 26), .41)
        assertTrue(render(t, now = .41).bullets.isEmpty())
    }

    @Test
    fun ricochetsAndReusedIdsNeverReuseOldGeometry() {
        val t = timeline(99)
        val before = ArenaBullet(id = 1, x = 75.0, y = 42.0, vx = 282.0, life = 5.0)
        val after = before.copy(x = 73.0, y = 48.0, vx = -282.0, bounces = 1)
        t.accept(ArenaSnapshot(tick = 0, bullets = listOf(before)), 0.0)
        t.accept(ArenaSnapshot(tick = 2, bullets = listOf(after)), 2 * tick)
        assertEquals(before, render(t, .1, now = .1).bullets[0])
        for (g in 1..2) {
            t.accept(
                state(tick = 60, generation = g, x = g * 100.0)
                    .copy(bullets = listOf(ArenaBullet(id = 8, x = g * 300.0))),
                g.toDouble(),
            )
            val image = render(t, now = g.toDouble())
            assertEquals(g * 100.0, image.tanks[0].x, 0.0)
            assertEquals(g * 300.0, image.bullets[0].x, 0.0)
        }
    }

    @Test
    fun cornerInterpolationRespectsWallsAndAllowsGhost() {
        val wall = MazeWall(80.0, 80.0, 8.0, 84.0, "v", 84.0)
        val world = ArenaWorld(252.0, 252.0, 3, 3, listOf(wall))
        for (ghost in listOf(0.0, 5.0)) {
            val t = timeline(99)
            val before = ArenaTank(id = 1, x = 62.0, y = 98.0, ghostTime = ghost)
            val after = before.copy(x = 98.0, y = 62.0)
            t.accept(ArenaSnapshot(tick = 0, tanks = listOf(before), world = world), 0.0)
            t.accept(ArenaSnapshot(tick = 2, tanks = listOf(after), world = world), 2 * tick)
            val shown = render(t, .1, now = .1).tanks[0]
            if (ghost == 0.0) {
                assertEquals(before.x, shown.x, 0.0)
                assertEquals(before.y, shown.y, 0.0)
            } else {
                assertTrue(shown.x > before.x)
                assertTrue(shown.y < before.y)
            }
        }
    }

    @Test
    fun seededInfinityRejectsInterpolationAcrossWalls() {
        val maze = InfiniteMaze(42)
        val wall = maze.walls(0.0, 0.0, 100.0, 100.0).first { it.axis == "h" }
        val x = wall.x + wall.w / 2
        val before = ArenaTank(id = 1, x = x, y = wall.y - 18)
        val after = before.copy(y = wall.y + wall.h + 18)
        assertFalse(maze.blocked(before.x, before.y, 17.0))
        assertFalse(maze.blocked(after.x, after.y, 17.0))
        val t = timeline(99, maze = maze)
        t.accept(ArenaSnapshot(tick = 0, tanks = listOf(before)), 0.0)
        t.accept(ArenaSnapshot(tick = 2, tanks = listOf(after)), 2 * tick)
        assertEquals(before.y, render(t, .1, now = .1).tanks[0].y, 0.0)
    }

    @Test
    fun smallAuthoritativeCorrectionsPreservePoseThenSettle() {
        val t = timeline(speed = 544.0)
        t.accept(state(), 0.0)
        val first = render(t, tick, GameInput(forward = true), tick).tanks[0]
        t.accept(state(tick = 1, x = first.x + 3, ack = 1, ackSteps = 1), tick)
        assertEquals(first.x, render(t, now = tick).tanks[0].x, 1e-9)
        var settled = first
        for (frame in 1..120) settled = render(t, 1.0 / 120, now = tick + frame / 120.0).tanks[0]
        assertEquals(first.x + 3, settled.x, .001)
    }

    @Test
    fun authorityRebaseDoesNotApplyControlTransitionBiasTwice() {
        val t = timeline(speed = 544.0)
        t.accept(state(), 0.0)
        val first = render(t, 1.0 / 120, GameInput(forward = true), 1.0 / 120).tanks[0]
        assertEquals(first.x, render(t, input = GameInput(), now = 1.0 / 120).tanks[0].x, 1e-9)
        t.accept(state(tick = 1, x = 103.0), 1.0 / 120)
        assertEquals(first.x, render(t, now = 1.0 / 120).tanks[0].x, 1e-9)
        val boundary = render(t, 1.0 / 120, now = tick).tanks[0]
        val dt = 1.0 / 120
        val authoritySettle = 3 * (1 - (1 + 20 * dt) * exp(-20 * dt))
        assertEquals(100 + (first.x - 100) * exp(-dt / .04) + authoritySettle, boundary.x, 1e-9)
    }

    @Test
    fun repeatedSpeedCorrectionsCannotCreateLargeDisplaySteps() {
        val t = timeline(speed = 544.0)
        t.accept(state(), 0.0)
        var seq = 0L
        val positions = mutableListOf<Double>()
        for (frame in 1..240) {
            val now = frame / 120.0
            val pose =
                render(t, 1.0 / 120, GameInput(forward = true), now) { seq = it.seq }.tanks[0]
            if (frame > 60) positions.add(pose.x)
            if (frame % 4 == 0)
                t.accept(
                    state(
                        tick = (frame / 2).toLong(),
                        x = 100 + now * 544 + if (frame % 8 == 0) 3 else -3,
                        ack = seq,
                        ackSteps = 1,
                    ),
                    now,
                )
        }
        val largest = positions.zipWithNext().maxOf { abs((it.second - it.first) - 544.0 / 120) }
        assertTrue("largest corrected step error=$largest", largest < .7)
    }

    @Test
    fun headingCorrectionCrossesAngleWrapByTheShortPath() {
        val t = timeline()
        val first = state().also { it.tanks[0].angle = 179 * PI / 180 }
        val second = state(tick = 1).also { it.tanks[0].angle = -179 * PI / 180 }
        t.accept(first, 0.0)
        t.accept(second, tick)
        var previous = render(t, now = tick).tanks[0].angle
        assertEquals(first.tanks[0].angle, previous, 1e-9)
        for (frame in 1..120) {
            val angle = render(t, 1.0 / 120, now = tick + frame / 120.0).tanks[0].angle
            assertTrue(abs(TankMovement.angleDelta(angle, previous)) < .01)
            previous = angle
        }
        assertEquals(second.tanks[0].angle, previous, .001)
    }

    @Test
    fun authorityCorrectionNeverCarriesAcrossWallOrOutsideGhostBounds() {
        val wall = MazeWall(480.0, 0.0, 8.0, 1000.0, "v")
        val world = ArenaWorld(1000.0, 1000.0, 12, 12, listOf(wall))
        val t = timeline()
        t.accept(state(x = 450.0, world = world), 0.0)
        t.accept(state(tick = 1, x = 510.0, world = world), tick)
        assertEquals(510.0, render(t, now = tick).tanks[0].x, 1e-9)
        val small = ArenaWorld(252.0, 252.0, 3, 3)
        val g = OnlinePresentation(maze = InfiniteMaze(small))
        val initial = state(x = 21.0, ghost = 15.0).also { it.tanks[0].angle = PI }
        g.accept(initial, 0.0)
        render(g, tick, GameInput(forward = true), tick)
        g.accept(
            state(tick = 2, x = 24.0, ack = 1, ackSteps = 1, ghost = 15.0).also {
                it.tanks[0].angle = PI
            },
            tick,
        )
        assertTrue(render(g, tick, GameInput(forward = true), 2 * tick).tanks[0].x >= 21)
    }

    @Test
    fun remoteCurveFallsBackWhenArcWouldCrossSolidWallOrOuterRim() {
        val world = ArenaWorld(500.0, 500.0, 6, 6, listOf(MazeWall(60.0, 70.0, 120.0, 10.0, "h")))
        val t = timeline(99)
        listOf(140.0, 100.0, 100.0, 140.0, 160.0).forEachIndexed { i, y ->
            t.accept(
                state(tick = i * 2L, x = 80 + i * 20.0, world = world).also { it.tanks[0].y = y },
                i / 30.0,
            )
        }
        t.neutralize()
        val pose = render(t, now = 4.0 / 30).tanks[0]
        assertTrue(pose.x > 100 && pose.x < 120)
        assertEquals(100.0, pose.y, 1e-9)
        for (includesWorld in listOf(false, true)) {
            val small = ArenaWorld(252.0, 252.0, 3, 3)
            val g = timeline(99, maze = InfiniteMaze(small))
            listOf(24.0, 21.0, 21.0, 21.0, 21.0).forEachIndexed { i, x ->
                g.accept(
                    state(
                            tick = i * 2L,
                            x = x,
                            ghost = 15.0,
                            world = if (includesWorld) small else null,
                        )
                        .also { it.tanks[0].y = 100 + i * 10.0 },
                    i / 30.0,
                )
            }
            g.neutralize()
            val image = render(g, now = 4.0 / 30).tanks[0]
            assertEquals(21.0, image.x, 1e-9)
            assertTrue(image.y > 110 && image.y < 120)
        }
    }

    @Test
    fun remoteFastTurnsUseContinuousCurvesAtAllRefreshRates() {
        val speed = 544.0
        val turn = 3.65 * 2.25
        val radius = speed / turn
        fun point(time: Double) =
            BeamPoint(1000 + sin(time * turn) * radius, 1000 + (1 - cos(time * turn)) * radius)
        fun sample(packet: Int): ArenaSnapshot {
            val time = packet / 30.0
            val p = point(time)
            return state(tick = packet * 2L, x = p.x).also {
                it.tanks[0].y = p.y
                it.tanks[0].angle = time * turn
            }
        }
        for (refresh in listOf(60, 120, 144)) {
            val t = timeline(99)
            t.accept(sample(0), 0.0)
            var packet = 0
            val poses = mutableListOf<BeamPoint>()
            val linear = mutableListOf<BeamPoint>()
            for (frame in 1..refresh * 3) {
                val now = frame.toDouble() / refresh
                while ((packet + 1) / 30.0 <= now + 1e-9) {
                    packet++
                    t.accept(sample(packet), now)
                }
                val pose = render(t, 1.0 / refresh, now = now).tanks[0]
                if (frame > refresh) {
                    poses.add(BeamPoint(pose.x, pose.y))
                    val stamp = pose.angle / turn * 30
                    val first = floor(stamp)
                    val alpha = stamp - first
                    val a = point(first / 30)
                    val b = point((first + 1) / 30)
                    linear.add(BeamPoint(a.x + (b.x - a.x) * alpha, a.y + (b.y - a.y) * alpha))
                }
            }
            fun largestChange(values: List<BeamPoint>): Double {
                val velocities =
                    values.zipWithNext().map {
                        BeamPoint(
                            (it.second.x - it.first.x) * refresh,
                            (it.second.y - it.first.y) * refresh,
                        )
                    }
                return velocities.zipWithNext().maxOf {
                    hypot(it.second.x - it.first.x, it.second.y - it.first.y)
                }
            }
            val before = largestChange(linear)
            val after = largestChange(poses)
            assertTrue("$refresh Hz $after/$before", after < before * .65)
        }
    }

    @Test
    fun localSpeedFiveTurningHasContinuousVelocityAtTheTickBoundary() {
        val world = ArenaWorld(4000.0, 4000.0, 48, 48)
        val t = OnlinePresentation(maze = InfiniteMaze(world))
        val initial = state(x = 2000.0, world = world)
        t.accept(initial, 0.0)
        val input = GameInput(forward = true, right = true)
        val epsilon = .000001
        var packets = 0
        val before = render(t, tick - epsilon, input, tick - epsilon) { packets++ }.tanks[0]
        val boundary = render(t, epsilon, input, tick) { packets++ }.tanks[0]
        val after = render(t, epsilon, input, tick + epsilon) { packets++ }.tanks[0]
        val change =
            hypot(
                (after.x - boundary.x) / epsilon - (boundary.x - before.x) / epsilon,
                (after.y - boundary.y) / epsilon - (boundary.y - before.y) / epsilon,
            )
        assertTrue(change < 1)
        val expected = initial.tanks[0].copy()
        TankMovement.step(expected, input, tick, InfiniteMaze(world))
        assertEquals(expected.x, boundary.x, 1e-9)
        assertEquals(expected.y, boundary.y, 1e-9)
        assertEquals(1, packets)
    }

    @Test
    fun switchingLocalSeatNeverMutatesBufferedAuthority() {
        val t = timeline(localID = 99)
        val original = state(x = 100.0)
        t.accept(original, 0.0)
        t.setLocalID(1)
        render(t, tick, GameInput(forward = true), tick)
        assertEquals(100.0, original.tanks[0].x, 0.0)
    }

    @Test
    fun malformedFrameTimeCannotPoisonFuturePrediction() {
        val t = timeline()
        t.accept(state(x = 0.0), 0.0)
        render(t, Double.NaN, GameInput(forward = true), 0.0)
        assertEquals(1.0, render(t, tick, GameInput(forward = true), tick).tanks[0].x, 1e-9)
    }
}
