package com.leqra.core

import com.sun.management.ThreadMXBean
import java.lang.management.ManagementFactory
import java.security.MessageDigest
import org.junit.Assert.*
import org.junit.Test

/** Repeatable desktop allocation/timing evidence; not a physical Android frame-rate claim. */
class PerformanceTest {
    @Test fun retainedStarShotgunContactsReportTheirWorstBatchCost() {
        val tanks = (1..8).map { ArenaTank(id = it, x = 140.0, y = 42.0, spawnSerial = 2, hp = 0) }
        val effects = (1..864).flatMap { id -> val path = ArenaEffect(id = id * 2, kind = "projectileFlight", tick = 6, flight = ProjectileFlight(id, 0, 0, 0.0, 6.0,
                listOf(ProjectileFlightPoint(40.0,42.0,0.0),ProjectileFlightPoint(119.5,42.0,6.0)),"scatter",3.5))
            val hit = ArenaEffect(id = id * 2 + 1, kind = "hit", tick = 6, contact = CombatContact(id,"scatter",6.0,1 + id % 8,2,ContactTankState(140.0,42.0,0.0)))
            if(id>856) listOf(path,hit) else listOf(path) }
        val flights = ProjectileFlightPresentation(); val contacts = CombatContactPresentation()
        fun run() {
            flights.reset(); contacts.reset()
            flights.accept(effects,0.0,8); contacts.accept(effects,tanks,0.0,6.0)
            for (t in listOf(.05,.11,.12)) {
                val image = flights.render(emptyList(),effects,t,contacts::canCompleteProjectile)
                contacts.render(tanks,image.effects,t,flights)
            }
        }
        repeat(100) { run() }
        val before = bytes(); val samples = LongArray(300)
        repeat(samples.size) { index -> val start=System.nanoTime(); run(); samples[index]=System.nanoTime()-start }
        samples.sort()
        println("864retained contacts accept+3frames: p50=${samples[150]/1e6}ms p95=${samples[285]/1e6}ms p99=${samples[297]/1e6}ms bytes/batch=${(bytes()-before)/samples.size}")
    }
    @Test
    fun fullRoomRoamingPopulationRemainsBoundedAndReportsItsSimulationCost() {
        val arena = PracticeArena(123, "Pilot", 0, 0)
        arena.configure(RoomRules(infinity = true, infinityRandomBots = true, infinityBotSpawnRate = 4.0))
        arena.snapshot.tanks = List(8) { index -> ArenaTank(id = index + 1, x = index * 4000.0 + 42, y = 42.0, invulnerable = 10000.0) }
        repeat(600) { arena.step(GameInput(), 1.0 / 60) }
        assertEquals(128, arena.snapshot.tanks.count { it.bot })
        val samples = LongArray(300)
        val before = bytes()
        repeat(samples.size) { index ->
            val start = System.nanoTime()
            arena.step(GameInput(), 1.0 / 60)
            samples[index] = System.nanoTime() - start
            assertTrue(arena.snapshot.tanks.count { it.bot } <= 128)
        }
        samples.sort()
        println("Room Infinity128 roaming bots: p50=${samples[150] / 1e6}ms p95=${samples[285] / 1e6}ms p99=${samples[297] / 1e6}ms bytes/tick=${(bytes() - before) / samples.size}")
    }
    private val allocation =
        (ManagementFactory.getThreadMXBean() as? ThreadMXBean)?.apply {
            if (isThreadAllocatedMemorySupported) isThreadAllocatedMemoryEnabled = true
        }

    private fun bytes() = allocation?.getThreadAllocatedBytes(Thread.currentThread().id) ?: 0

    @Test
    fun pairedPredictionSharesTheProjectileTimeline() {
        fun state(tick: Long) =
            ArenaSnapshot(
                tick = tick,
                generation = 1,
                tanks =
                    List(12) {
                        ArenaTank(
                            id = it + 1,
                            x = 100.0 + it * 60 + tick,
                            y = 200.0,
                            spawnSerial = 1,
                        )
                    },
                bullets =
                    List(768) {
                        ArenaBullet(
                            id = it + 1000,
                            x = 100.0 + it + tick,
                            y = 300.0,
                            vx = 60.0,
                            life = 5.0,
                        )
                    },
            )
        for (paired in listOf(false, true)) {
            val timeline =
                OnlinePresentation(
                    movement = { tank, input, dt -> if (input.forward) tank.x += dt * 60 },
                )
            timeline.setLocalIDs(1, if (paired) 2 else null)
            var now = 0.0
            var frame = 0
            val input = GameInput(forward = true)
            fun render() {
                if (frame % 4 == 0) timeline.accept(state((frame / 2).toLong()), now)
                now += 1.0 / 120
                frame++
                timeline.render(1.0 / 120, input, now, input2 = input, sendLocal = {}) {}
            }
            repeat(600) { render() }
            val before = bytes()
            val samples = LongArray(1200)
            repeat(samples.size) { index ->
                val start = System.nanoTime()
                render()
                samples[index] = System.nanoTime() - start
            }
            val allocation = (bytes() - before) / samples.size
            samples.sort()
            println(
                "online ${if(paired) "paired" else "solo"}768projectiles: p50=${samples[600]/1e6}ms p95=${samples[1140]/1e6}ms p99=${samples[1188]/1e6}ms bytes/frame+quarterPacket=$allocation",
            )
            assertTrue(timeline.bufferedAcknowledgementCount <= 240)
            assertTrue(timeline.secondaryAcknowledgementCount <= 240)
        }
    }

    @Test
    fun collisionTraversalAndStackedWeaponsStayBounded() {
        for (fixed in listOf(false, true)) {
            val world =
                if (fixed) FixedArena(RoomRules.localDefaults(), "Pilot", 0, 7, seed = 42).world
                else null
            val maze = world?.let(::InfiniteMaze) ?: InfiniteMaze(42)
            var digest = 0L
            fun queries(index: Int) {
                val x = 42.0 + (index % 15) * 84 + (index % 17) * .7
                val y = 42.0 + (index % 9) * 84 + (index % 19) * .5
                if (maze.blocked(x, y, 17.0)) digest++
                val hit = maze.rayHit(x, y, 57.1, -83.3, 4.0)
                digest += hit?.let { (it.fraction * 10000).toLong() } ?: 1L
                if (maze.segmentBlocked(x, y, -84.0, 84.0)) digest += 3
            }
            repeat(10000, ::queries)
            val before = bytes()
            val started = System.nanoTime()
            repeat(30000, ::queries)
            val duration = System.nanoTime() - started
            println(
                "collision ${if(fixed) "fixed" else "infinity"}: ns/query=${duration/90000} bytes/query=${(bytes()-before)/90000} digest=$digest",
            )
            assertTrue(digest > 0)

            val arena = PracticeArena(42, "Pilot", 0, if (fixed) 7 else 8, world = world)
            val pilot = arena.snapshot.tanks[0]
            for (power in listOf("shield", "speed", "ghost", "starman", "scatter")) PracticeArena
                .applyPower(pilot, power)
            val input = GameInput(forward = true, right = true, fire = true, touchAim = false)
            fun frame() {
                arena.snapshot.tanks[0].starmanTime = 8.0
                arena.snapshot.tanks[0].invulnerable = 8.0
                arena.step(input, 1.0 / 60)
                arena.presentationSnapshot(.5, input)
                arena.presentationSnapshot(.99, input)
            }
            repeat(300) { frame() }
            val allocations = bytes()
            val samples = LongArray(1200)
            repeat(samples.size) { index ->
                val time = System.nanoTime()
                frame()
                samples[index] = System.nanoTime() - time
            }
            val perFrame = (bytes() - allocations) / samples.size
            samples.sort()
            println(
                "stacked ${if(fixed) "fixed" else "infinity"}: p50=${samples[600]/1e6}ms p95=${samples[1140]/1e6}ms p99=${samples[1188]/1e6}ms bytes/step+twoFrames=$perFrame tick=${arena.snapshot.tick} bullets=${arena.snapshot.bullets.size}",
            )
            val fingerprint =
                MessageDigest.getInstance("SHA-256")
                    .digest(arena.snapshot.toString().toByteArray())
                    .joinToString("") { "%02x".format(it) }
            println("state ${if(fixed) "fixed" else "infinity"} sha256=$fingerprint")
            assertTrue(arena.snapshot.bullets.size <= 8 * 115)
        }
    }
}
