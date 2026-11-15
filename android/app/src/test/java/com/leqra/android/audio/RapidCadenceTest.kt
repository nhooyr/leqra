package com.leqra.android.audio

import com.leqra.core.*
import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class RapidCadenceTest {
    private fun localTimeline(star: Boolean, rate: Int, jitter: Boolean): List<Double> {
        val model = PracticeArena(42, "Pilot", 0, 0, world = ArenaWorld(2016.0, 1176.0, 24, 14))
        PracticeArena::class.java.getDeclaredField("pickupRate").apply { isAccessible = true }.set(model, "off")
        model.snapshot.tanks.single().apply {
            x = 100.0; y = 588.0; angle = 0.0; spawnProtected = false; invulnerable = 0.0
            if (star) PracticeArena.applyPower(this, "starman")
            PracticeArena.applyPower(this, "rapid")
        }
        val router = AudioEventRouter()
        router.consume(model.snapshot, 1, false, false, 0.0)
        val times = ArrayList<Double>()
        for (frame in 1..rate * 2) {
            val now = frame.toDouble() / rate + if (jitter) sin(frame * .73) * .003 else 0.0
            val tick = floor(now * 60 + 1e-8).toLong()
            while (model.snapshot.tick < tick) model.step(GameInput(fire = true), 1.0 / 60)
            if (router.consume(model.snapshot, 1, false, false, now).any { it.cue == AudioCue.RAPID }) times += now
            assertTrue("Retained physics snapshots never replay a second cue", router.consume(model.snapshot, 1, false, false, now).none { it.cue == AudioCue.RAPID })
        }
        return times
    }

    @Test fun localStarAndOrdinaryMachineGunsHaveIdenticalAudioThroughFrameJitter() {
        for (rate in listOf(60, 90, 120, 144, 165)) for (jitter in listOf(false, true)) {
            val ordinary = localTimeline(false, rate, jitter)
            val star = localTimeline(true, rate, jitter)
            assertEquals("$rate Hz jitter=$jitter must not double-throttle Star feedback", ordinary, star)
            assertEquals("The single gate preserves15Hz without double-throttling", 30, star.size)
            val gaps = star.zipWithNext { a, b -> b - a }
            assertTrue("No machine-gun silence beyond one coarse display interval", gaps.max() < .105)
            assertTrue("No catch-up bursts", gaps.min() + 1e-9 >= .065 - 1.0 / 60)
        }
    }

    @Test fun coalescedOnlineCuesKeepTheirPhaseWithoutReplayingPredictedOrRetainedShots() {
        for (rate in listOf(60, 90, 120, 144, 165)) for (jitter in listOf(false, true)) for (wireRate in listOf(20, 30, 60)) {
            val router = AudioEventRouter()
            val tank = ArenaTank(id = 1, power = "rapid", starmanTime = 8.0)
            val base = ArenaSnapshot(tanks = listOf(tank))
            router.consume(base, 1, true, true, 0.0)
            val times = ArrayList<Double>()
            for (frame in 1..rate * 4) {
                val now = frame.toDouble() / rate + if (jitter) sin(frame * .73) * .004 else 0.0
                val tick = floor(now * wireRate + 1e-8).toLong() * (60 / wireRate)
                val effects = (max(1L, tick - 12)..tick).filter { it % 4 == 1L }.map { ArenaEffect(id = it.toInt(), kind = "shot:rapid", owner = 1, tick = it.toInt()) } +
                    ArenaEffect(id = -1, kind = "shot:rapid", owner = 1)
                val state = base.copy(tick = tick, effects = effects)
                val cues = router.consume(state, 1, true, true, now).count { it.cue == AudioCue.RAPID }
                assertTrue("One cue at most from a coalesced packet", cues <= 1)
                if (cues == 1) times += now
                assertTrue(router.consume(state, 1, true, true, now).isEmpty())
            }
            assertEquals("$rate Hz/$wireRate wire jitter=$jitter preserves every15Hz source cue", 60, times.size)
            assertTrue("No catch-up bursts from the server", times.zipWithNext { a, b -> b - a }.min() + 1e-9 >= .065 / 2)
        }
    }

    @Test fun twentyHertzSourcePhasesSurviveFiftyMillisecondArrivalsWithoutCatchupBursts() {
        val router = AudioEventRouter()
        val base = ArenaSnapshot(tanks = listOf(ArenaTank(id = 1, power = "rapid", starmanTime = 8.0)))
        router.consume(base, 1, true, true, 0.0)
        var heard = 0
        var id = 0
        for (source in 1..237 step 4) {
            val now = ceil(source / 3.0) / 20
            val event = ArenaEffect(id = ++id, kind = "shot:rapid", owner = 1, tick = source)
            val state = base.copy(tick = ceil(source / 3.0).toLong() * 3, effects = listOf(event))
            heard += router.consume(state, 1, true, true, now).count { it.cue == AudioCue.RAPID }
            assertTrue(router.consume(state, 1, true, true, now).isEmpty())
        }
        assertEquals("All60 source cues survive the50/50/100ms arrival phase", 60, heard)
        // A real arrival shorter than the physical floor is intentionally dropped, never queued.
        val short = base.copy(effects = listOf(ArenaEffect(id = ++id, kind = "shot:rapid", owner = 1, tick = 241)))
        assertTrue(router.consume(short, 1, true, true, 3.98).isEmpty())
        assertTrue(router.consume(short, 1, true, true, 4.2).isEmpty())
    }

    @Test fun outOfOrderSourceTicksAndClockRewindsCannotReplayOlderShotPhases() {
        val router = AudioEventRouter()
        val base = ArenaSnapshot(tanks = listOf(ArenaTank(id = 1, power = "rapid")))
        router.consume(base, 1, true, true, 0.0)
        fun state(id: Int, tick: Int) = base.copy(effects = listOf(ArenaEffect(id = id, kind = "shot:rapid", owner = 1, tick = tick)))
        assertEquals(1, router.consume(state(1, 100), 1, true, true, 1.0).size)
        assertTrue(router.consume(state(2, 99), 1, true, true, 1.2).isEmpty())
        assertTrue("Real-clock rewind does not replay an old source tick", router.consume(state(3, 98), 1, true, true, .5).isEmpty())
        assertEquals(1, router.consume(state(4, 104), 1, true, true, .6).size)
        assertTrue(router.consume(state(5, 108), 1, true, true, .62).isEmpty())
        assertTrue("Rejected source phase stays consumed", router.consume(state(6, 108), 1, true, true, .8).isEmpty())
        assertEquals(1, router.consume(state(7, 112), 1, true, true, .9).size)
        router.reset(); router.consume(base, 1, true, true, 1.0)
        assertEquals("A true new scene resets the source epoch", 1, router.consume(state(8, 1), 1, true, true, 1.1).size)
    }

    @Test fun backwardsClockAndLongGapsResetTheDeadlineWithoutReplayingHistory() {
        val router = AudioEventRouter()
        val tank = ArenaTank(id = 1, power = "rapid", starmanTime = 8.0)
        fun state(id: Int, count: Int = 1) = ArenaSnapshot(tanks = listOf(tank), effects = (id until id + count).map { ArenaEffect(id = it, kind = "shot:rapid", owner = 1) })
        router.consume(state(0, 0), 1, false, true, 0.0)
        assertEquals(1, router.consume(state(1), 1, false, true, 5.0).size)
        assertEquals(1, router.consume(state(2), 1, false, true, 4.0).size)
        assertTrue(router.consume(state(2), 1, false, true, 4.0).isEmpty())
        assertTrue(router.consume(state(3), 1, false, true, 4.0).isEmpty())
        assertEquals(1, router.consume(state(4, 100), 1, false, true, 100.0).size)
        assertTrue("Dropped batch cues do not replay later", router.consume(state(4, 100), 1, false, true, 100.2).isEmpty())
    }
}
