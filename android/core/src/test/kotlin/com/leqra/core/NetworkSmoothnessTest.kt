package com.leqra.core

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import org.junit.Assert.*
import org.junit.Test

/** Ordered deterministic WebSocket delays exercise real prediction at 120 Hz. */
class NetworkSmoothnessTest {
    @Test
    fun retainedCorrectionVelocityCannotOvershootGhostRadiusAfterAnAuthorityTurn() {
        val world = ArenaWorld(width = 20000.0, height = 20000.0)
        val movement: (ArenaTank, GameInput, Double) -> Unit = { tank, input, dt ->
            TankMovement.step(tank, input, dt, emptyList(), world.width, world.height)
        }
        val timeline = OnlinePresentation(movement = movement)
        val initial =
            ArenaTank(
                id = 1,
                x = 5000.0,
                y = 5000.0,
                speedStacks = 5,
                speedTime = 60.0,
                ghostTime = 15.0,
                spawnSerial = 1,
            )
        timeline.accept(ArenaSnapshot(tick = 0, tanks = listOf(initial), world = world), 0.0)
        val input = GameInput(forward = true, touchAim = false)
        timeline.render(1.0 / 60, input, 1.0 / 60) {}
        val authority =
            initial.copy(x = initial.x + 544.0 / 60, angle = kotlin.math.PI, ack = 1, ackSteps = 1)
        timeline.accept(ArenaSnapshot(tick = 1, tanks = listOf(authority), world = world), 1.0 / 60)
        val expected = authority.copy()
        for (frame in 1..120) {
            movement(expected, input, 1.0 / 120)
            val pose =
                timeline.render(1.0 / 120, input, 1.0 / 60 + frame / 120.0) {}!!.tanks.single()
            assertTrue(
                "Ghost authority bias must remain within its12px radius",
                hypot(pose.x - expected.x, pose.y - expected.y) <= 12.00001,
            )
            assertTrue(abs(TankMovement.angleDelta(pose.angle, expected.angle)) <= .700001)
        }
    }

    private data class InputDelivery(val at: Double, val input: GameInput)

    private data class StateDelivery(val at: Double, val state: ArenaSnapshot)

    private data class Profile(
        val local: MutableList<Double> = ArrayList(),
        val remote: MutableList<Double> = ArrayList(),
        val bullets: MutableList<Double> = ArrayList(),
        var stalls: Int = 0,
    )

    private fun p95(values: List<Double>) = values.sorted()[((values.size - 1) * .95).toInt()]

    private fun profile(rtt: Double, jitter: Double, turning: Boolean, paired: Boolean): Profile {
        val world = ArenaWorld(width = 20000.0, height = 20000.0, cols = 238, rows = 238)
        val move: (ArenaTank, GameInput, Double) -> Unit = { tank, input, dt ->
            TankMovement.step(tank, input, dt, emptyList(), world.width, world.height)
        }
        val timeline = OnlinePresentation(movement = move)
        if (paired) timeline.setLocalIDs(1, 3)
        val pilots =
            Array(if (paired) 2 else 1) { seat ->
                ArenaTank(
                    id = if (seat == 0) 1 else 3,
                    name = "LOCAL",
                    x = 10000.0,
                    y = 10000.0 + seat * 1000,
                    spawnSerial = 1,
                    speedTime = 60.0,
                    speedStacks = 5,
                )
            }
        val inbound = Array(pilots.size) { ArrayDeque<InputDelivery>() }
        val outbound = ArrayDeque<StateDelivery>()
        val current = Array(pilots.size) { GameInput() }
        val ackSteps = IntArray(pilots.size)
        val lastInputAt = DoubleArray(pilots.size)
        val sent = IntArray(pilots.size)
        var lastStateAt = 0.0
        var serverTick = 0L
        var stateCount = 0
        val pattern = doubleArrayOf(-1.0, .4, .9, -.2, .7, -.8, .1, .5)
        fun variation(number: Int) = pattern[number % pattern.size] * jitter
        fun state(): ArenaSnapshot {
            val time = serverTick / 60.0
            return ArenaSnapshot(
                tick = 600 + serverTick,
                generation = 1,
                world = world,
                tanks =
                    pilots.mapIndexed { seat, tank ->
                        tank.copy(ack = current[seat].seq, ackSteps = ackSteps[seat])
                    } + ArenaTank(id = 2, x = 1000 + time * 384, y = 1000.0, spawnSerial = 1),
                bullets =
                    listOf(
                        ArenaBullet(
                            id = 1,
                            x = 1000 + time * 846,
                            y = 2000.0,
                            vx = 846.0,
                            life = 100.0,
                        )
                    ),
            )
        }
        timeline.accept(state(), 0.0)
        val result = Profile()
        var previous: DoubleArray? = null
        var previousVelocity: DoubleArray? = null
        for (frame in 1..1440) {
            val now = frame / 120.0
            if (frame % 2 == 0) {
                for (seat in pilots.indices) {
                    while (inbound[seat].firstOrNull()?.at?.let { it <= now + 1e-9 } == true) {
                        val next = inbound[seat].removeFirst()
                        if (next.input.seq > current[seat].seq) {
                            current[seat] = next.input
                            ackSteps[seat] = 0
                        }
                    }
                    ackSteps[seat]++
                    move(pilots[seat], current[seat], 1.0 / 60)
                }
                serverTick++
                if (serverTick % 2L == 0L) {
                    stateCount++
                    lastStateAt =
                        max(lastStateAt + 1e-6, now + max(0.0, rtt / 2 + variation(stateCount)))
                    outbound.addLast(StateDelivery(lastStateAt, state()))
                }
            }
            while (outbound.firstOrNull()?.at?.let { it <= now + 1e-9 } == true) timeline.accept(
                outbound.removeFirst().state,
                now,
            )
            fun send(seat: Int, packet: GameInput) {
                sent[seat]++
                lastInputAt[seat] =
                    max(
                        lastInputAt[seat] + 1e-6,
                        now + max(0.0, rtt / 2 + variation(sent[seat] + 3 + seat)),
                    )
                inbound[seat].addLast(InputDelivery(lastInputAt[seat], packet.copy()))
            }
            val input = GameInput(forward = true, right = turning, touchAim = false)
            val rendered =
                timeline.render(
                    1.0 / 120,
                    input,
                    now,
                    input2 = input.takeIf { paired },
                    sendLocal = { send(1, it) },
                ) {
                    send(0, it)
                }!!
            val own = pilots.map { local -> rendered.tanks.first { it.id == local.id } }
            val remote = rendered.tanks.first { it.id == 2 }
            val bullet = rendered.bullets.single()
            val pose =
                own.flatMap { listOf(it.x, it.y) }.toDoubleArray() +
                    doubleArrayOf(remote.x, bullet.x)
            previous?.let { prior ->
                val velocity =
                    DoubleArray(pilots.size + 2) { index ->
                        if (index < pilots.size)
                            hypot(
                                pose[index * 2] - prior[index * 2],
                                pose[index * 2 + 1] - prior[index * 2 + 1],
                            ) * 120
                        else
                            (pose[pilots.size * 2 + index - pilots.size] -
                                prior[pilots.size * 2 + index - pilots.size]) * 120
                    }
                previousVelocity?.let { old ->
                    if (now > 3) {
                        for (seat in pilots.indices) result.local.add(
                            abs(velocity[seat] - old[seat])
                        )
                        result.remote.add(abs(velocity[pilots.size] - old[pilots.size]))
                        result.bullets.add(abs(velocity[pilots.size + 1] - old[pilots.size + 1]))
                        if (velocity[pilots.size] < 1 || velocity[pilots.size + 1] < 1)
                            result.stalls++
                    }
                }
                previousVelocity = velocity
            }
            previous = pose
        }
        return result
    }

    @Test
    fun orderedLatencyAndJitterKeepBothSeatsRemoteTanksAndProjectilesContinuous() {
        for (rtt in listOf(.001, .01, .025, .05, .15, .25, .4)) for (jitter in
            listOf(0.0, .012)) for (turning in listOf(false, true)) for (paired in
            listOf(false, true)) {
            val result = profile(rtt, jitter, turning, paired)
            println(
                "Android network RTT=${(rtt * 1000).toInt()} jitter=${(jitter * 1000).toInt()} turn=$turning paired=$paired local=${p95(result.local)}/${result.local.max()} remote=${p95(result.remote)} bullets=${p95(result.bullets)} stalls=${result.stalls}"
            )
            assertEquals(0, result.stalls)
            assertTrue("Local jitter pulse at RTT=$rtt paired=$paired", p95(result.local) < 26)
            assertTrue("Local maximum pulse at RTT=$rtt paired=$paired", result.local.max() < 30)
            assertTrue("Remote tank jitter at RTT=$rtt", p95(result.remote) < 2.5)
            assertTrue("Projectile jitter at RTT=$rtt", p95(result.bullets) < 5)
        }
    }
}
