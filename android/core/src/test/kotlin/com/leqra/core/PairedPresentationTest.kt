package com.leqra.core

import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class PairedPresentationTest {
    private val step = 1.0 / 60

    private fun timeline() =
        OnlinePresentation(
                movement = { tank, input, dt ->
                    tank.x += (if (input.forward) 60.0 else if (input.reverse) -60.0 else 0.0) * dt
                },
            )
            .apply { setLocalIDs(1, 2) }

    private fun state(
        tick: Long = 0,
        firstX: Double = 100.0,
        secondX: Double = 500.0,
        firstAck: Long = 0,
        secondAck: Long = 0,
        firstSteps: Int = 0,
        secondSteps: Int = 0,
        secondHP: Int = 1,
        secondLife: Int = 1,
    ) =
        ArenaSnapshot(
            tick = tick,
            generation = 1,
            tanks =
                listOf(
                    ArenaTank(
                        id = 1,
                        x = firstX,
                        y = 100.0,
                        spawnSerial = 1,
                        ack = firstAck,
                        ackSteps = firstSteps,
                    ),
                    ArenaTank(
                        id = 2,
                        x = secondX,
                        y = 200.0,
                        spawnSerial = secondLife,
                        ack = secondAck,
                        ackSteps = secondSteps,
                        hp = secondHP,
                    ),
                ),
        )

    @Test
    fun bothSeatsRespondInTheFirstSubframeWithIndependentSixtyHzSequences() {
        for (hz in listOf(60, 90, 120, 144)) {
            val t = timeline()
            t.reset(10, 100)
            t.accept(state(), 0.0)
            val first = mutableListOf<GameInput>()
            val second = mutableListOf<GameInput>()
            var image = state()
            for (frame in 1..hz) {
                image =
                    t.render(
                        1.0 / hz,
                        GameInput(forward = true),
                        frame.toDouble() / hz,
                        input2 = GameInput(reverse = true),
                        sendLocal = { second.add(it) },
                    ) {
                        first.add(it)
                    }!!
                if (frame == 1) {
                    assertTrue(image.tanks[0].x > 100)
                    assertTrue("P2 must not wait for the85ms remote buffer", image.tanks[1].x < 500)
                }
            }
            assertEquals(60, first.size)
            assertEquals(60, second.size)
            assertEquals((11L..70L).toList(), first.map { it.seq })
            assertEquals((101L..160L).toList(), second.map { it.seq })
            assertEquals(160.0, image.tanks[0].x, 1e-9)
            assertEquals(440.0, image.tanks[1].x, 1e-9)
        }
    }

    @Test
    fun eachAcknowledgementReplaysOnlyItsOwnUnconsumedInputs() {
        val t = timeline()
        t.accept(state(tick = 60), 0.0)
        t.render(
            step * 2,
            GameInput(forward = true),
            step * 2,
            input2 = GameInput(reverse = true),
            sendLocal = {},
        ) {}
        t.render(
            step * 2,
            GameInput(reverse = true),
            step * 4,
            input2 = GameInput(forward = true),
            sendLocal = {},
        ) {}
        t.accept(
            state(62, 102.0, 499.0, firstAck = 1, firstSteps = 2, secondAck = 3, secondSteps = 1),
            step * 4,
        )
        t.neutralize()
        val image = t.render(0.0, GameInput(), step * 4, input2 = GameInput(), sendLocal = {}) {}!!
        assertEquals(100.0, image.tanks[0].x, 1e-9)
        assertEquals(500.0, image.tanks[1].x, 1e-9)
        assertEquals(2, t.bufferedFrameCount)
        assertEquals(1, t.secondaryFrameCount)
    }

    @Test
    fun secondaryDeathAndRespawnDoNotDiscardPrimaryHistoryOrReuseSequences() {
        val t = timeline()
        t.accept(state(), 0.0)
        val first = mutableListOf<Long>()
        val second = mutableListOf<Long>()
        t.render(
            step * 3,
            GameInput(forward = true),
            step * 3,
            input2 = GameInput(reverse = true),
            sendLocal = { second.add(it.seq) },
        ) {
            first.add(it.seq)
        }
        t.accept(state(3, 102.0, 497.0, firstAck = 2, secondHP = 0), step * 3)
        assertEquals(1, t.bufferedFrameCount)
        assertEquals(0, t.secondaryFrameCount)
        t.neutralize()
        var image = t.render(0.0, GameInput(), step * 3, input2 = GameInput(), sendLocal = {}) {}!!
        assertEquals(103.0, image.tanks[0].x, 1e-9)
        assertEquals(0, image.tanks[1].hp)
        t.accept(state(4, 103.0, 800.0, firstAck = 3, secondLife = 2), step * 4)
        image =
            t.render(
                step,
                GameInput(),
                step * 5,
                input2 = GameInput(forward = true),
                sendLocal = { second.add(it.seq) },
            ) {
                first.add(it.seq)
            }!!
        assertEquals(801.0, image.tanks[1].x, 1e-9)
        assertEquals(listOf(1L, 2L, 3L, 4L), first)
        assertEquals(listOf(1L, 2L, 3L, 4L), second)
    }

    @Test
    fun neutralPacketsAndSocketResetKeepEachCounterSeparate() {
        val t = timeline()
        t.reset(100, 200)
        t.accept(state(), 0.0)
        val first = mutableListOf<Long>()
        val second = mutableListOf<Long>()
        t.render(
            step,
            GameInput(forward = true),
            step,
            input2 = GameInput(reverse = true),
            sendLocal = { second.add(it.seq) },
        ) {
            first.add(it.seq)
        }
        assertEquals(102, t.neutralPacket().seq)
        assertEquals(202, t.neutralLocalPacket()!!.seq)
        t.render(
            step,
            GameInput(),
            step * 2,
            input2 = GameInput(),
            sendLocal = { second.add(it.seq) },
        ) {
            first.add(it.seq)
        }
        assertEquals(listOf(101L, 103L), first)
        assertEquals(listOf(201L, 203L), second)
        t.reset(300, 400)
        t.accept(state(), 1.0)
        t.render(
            step,
            GameInput(),
            1.0 + step,
            input2 = GameInput(),
            sendLocal = { second.add(it.seq) },
        ) {
            first.add(it.seq)
        }
        assertEquals(301L, first.last())
        assertEquals(401L, second.last())
    }

    @Test
    fun removingP2StopsItsPacketsAndNeverMutatesBufferedAuthority() {
        val t = timeline()
        val source = state()
        t.accept(source, 0.0)
        t.render(step, GameInput(), step, input2 = GameInput(reverse = true), sendLocal = {}) {}
        assertEquals(500.0, source.tanks[1].x, 0.0)
        t.setLocalIDs(1, null)
        val sent = mutableListOf<GameInput>()
        t.render(
            step,
            GameInput(forward = true),
            step * 2,
            input2 = GameInput(reverse = true),
            sendLocal = { sent.add(it) },
        ) {}
        assertTrue(sent.isEmpty())
        assertNull(t.neutralLocalPacket())
        assertEquals(100.0, source.tanks[0].x, 0.0)
        assertEquals(500.0, source.tanks[1].x, 0.0)
    }

    @Test
    fun stalePairedConnectionFreezesBothAndBoundsBothHistories() {
        val t = timeline()
        t.accept(state(), 0.0)
        var previous: List<Double>? = null
        repeat(1200) { index ->
            val now = (index + 1) / 120.0
            val stale = now > 2.5
            val result =
                t.render(
                    1.0 / 120,
                    GameInput(forward = true, fire = true),
                    now,
                    input2 = GameInput(reverse = true, fire = true),
                    sendLocal = {
                        if (stale) {
                            assertFalse(it.fire)
                            assertFalse(it.reverse)
                        }
                    },
                ) {
                    if (stale) {
                        assertFalse(it.fire)
                        assertFalse(it.forward)
                    }
                }!!
            if (now > 3) {
                val positions = result.tanks.map { it.x }
                previous?.let { assertEquals(it, positions) }
                previous = positions
            }
        }
        assertTrue(t.bufferedAcknowledgementCount <= 240)
        assertTrue(t.secondaryAcknowledgementCount <= 240)
        assertTrue(t.bufferedFrameCount <= 240)
        assertTrue(t.secondaryFrameCount <= 240)
    }

    @Test
    fun reassigningOrReattachingP2PreservesTheSocketSequence() {
        val t = timeline()
        t.accept(state(), 0.0)
        val second = mutableListOf<Long>()
        t.render(
            step * 3,
            GameInput(),
            step * 3,
            input2 = GameInput(reverse = true),
            sendLocal = { second.add(it.seq) },
        ) {}
        t.setLocalIDs(1, null)
        t.setLocalIDs(1, 2)
        t.render(
            step,
            GameInput(),
            step * 4,
            input2 = GameInput(),
            sendLocal = { second.add(it.seq) },
        ) {}
        assertEquals(listOf(1L, 2L, 3L, 4L), second)
        t.setLocalIDs(1, null, localInitialSequence = 100)
        t.setLocalIDs(1, 2)
        t.render(
            step,
            GameInput(),
            step * 5,
            input2 = GameInput(),
            sendLocal = { second.add(it.seq) },
        ) {}
        assertEquals(101L, second.last())
    }

    @Test
    fun duplicateLocalIdsCannotMixAuthority() {
        try {
            timeline().setLocalIDs(1, 1)
            fail("Duplicate local tanks were accepted")
        } catch (_: IllegalArgumentException) {}
    }
}
