package com.leqra.android.audio

import com.leqra.core.*
import org.junit.Assert.*
import org.junit.Test

class AudioRoutingTest {
    @Test
    fun startingAnotherMatchDoesNotSilenceItsLowerEffectIDs() {
        val router = AudioEventRouter()
        fun frame(tick: Long, id: Int) =
            ArenaSnapshot(
                tick = tick,
                effects =
                    if (id == 0) emptyList()
                    else listOf(ArenaEffect(id = id, kind = "shot:regular", owner = 1)),
            )
        assertTrue(router.consume(frame(500, 500), 1, true, false, 0.0).isEmpty())
        assertEquals(
            AudioCue.REGULAR,
            router.consume(frame(501, 501), 1, true, false, .1).single().cue,
        )
        assertTrue(router.consume(frame(0, 0), 1, true, false, .2).isEmpty())
        assertEquals(AudioCue.REGULAR, router.consume(frame(1, 1), 1, true, false, .3).single().cue)
    }

    @Test
    fun denseProjectileHistoryHandlesSparseIDsAndDoesNotReplayDespawnedBounces() {
        val router = AudioEventRouter()
        val ids = List(2048) { (it * 195179) + 128 } + listOf(Int.MAX_VALUE, Int.MIN_VALUE)
        var now = 0.0
        fun bounce(count: Int, visible: Boolean = true): List<AudioCueRequest> {
            now += .08
            val frame =
                ArenaSnapshot(
                    tick = (now * 60).toLong(),
                    bullets =
                        if (visible) ids.map { ArenaBullet(id = it, bounces = count) }
                        else emptyList(),
                )
            return router.consume(frame, 1, false, false, now)
        }
        assertTrue(bounce(0).isEmpty())
        repeat(3) { assertEquals(AudioCue.RICOCHET, bounce(it + 1).single().cue) }
        assertTrue(bounce(3).isEmpty())
        assertTrue(bounce(0, false).isEmpty())
        assertTrue(bounce(9).isEmpty())
        assertEquals(AudioCue.RICOCHET, bounce(10).single().cue)
    }

    @Test
    fun coldAudioQueueIsBoundedAndCannotReplayLateShotsAfterReset() {
        val queue = AudioCueQueue(capacity = 2, maxAgeNanos = 100)
        val played = mutableListOf<FloatArray>()
        val pcm = floatArrayOf(.1f)
        assertTrue(queue.offer(0, 0))
        assertTrue(queue.offer(1, 0))
        assertFalse(queue.offer(2, 0))
        assertEquals(
            0,
            queue.drain(50, { null }) {
                played.add(it)
                true
            },
        )
        assertEquals(2, queue.size)
        assertEquals(
            0,
            queue.drain(101, { pcm }) {
                played.add(it)
                true
            },
        )
        assertEquals(0, queue.size)
        assertTrue(played.isEmpty())
        queue.offer(1, 102)
        queue.clear()
        assertEquals(
            0,
            queue.drain(103, { pcm }) {
                played.add(it)
                true
            },
        )
        queue.offer(1, 104)
        assertEquals(
            1,
            queue.drain(110, { pcm }) {
                played.add(it)
                true
            },
        )
        assertSame(pcm, played.single())
        assertEquals(6L, queue.lastLatencyNanos)
    }

    @Test
    fun changingControlledSeatBaselinesItsRetainedSounds() {
        val router = AudioEventRouter()
        val frame =
            ArenaSnapshot(
                tick = 5,
                tanks = listOf(ArenaTank(id = 1), ArenaTank(id = 2)),
                effects = listOf(ArenaEffect(id = 10, kind = "shot:regular", owner = 2)),
            )
        router.consume(frame, 1, true, true, 0.0)
        assertTrue(router.consume(frame, 2, true, true, .1).isEmpty())
        val next =
            frame.copy(
                tick = 6,
                effects = listOf(ArenaEffect(id = 11, kind = "shot:regular", owner = 2)),
            )
        assertTrue(router.consume(next, 2, true, true, .2).single().local)
    }
}
