package com.leqra.android.audio

import com.leqra.core.*
import java.io.File
import kotlin.math.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class StarmanAudioTest {
    @Test
    fun originalLoopMatchesSharedBrowserPcmAtEveryReferenceRate() {
        val root =
            generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }
                .first { File(it, "src/tests/starman-audio-fixtures.json").isFile }
        val profiles =
            JSONObject(File(root, "src/tests/starman-audio-fixtures.json").readText())
                .getJSONArray("profiles")
        repeat(profiles.length()) { index ->
            val profile = profiles.getJSONObject(index)
            val samples = StarmanSynthesis.samples(profile.getDouble("rate"))
            assertEquals(profile.getInt("frames"), samples.size)
            assertTrue(samples.all(Float::isFinite))
            assertEquals(profile.getDouble("peak"), samples.maxOf { abs(it).toDouble() }, 1e-8)
            assertEquals(
                profile.getDouble("rms"),
                sqrt(samples.sumOf { it.toDouble() * it } / samples.size),
                1e-8,
            )
            val references = profile.getJSONArray("samples")
            repeat(references.length()) {
                val sample = references.getJSONObject(it)
                assertEquals(
                    sample.getDouble("value"),
                    samples[sample.getInt("index")].toDouble(),
                    1e-8,
                )
            }
            assertEquals(0f, samples.first(), 0f)
            assertEquals(0f, samples.last(), 0f)
            assertArrayEquals(samples, StarmanSynthesis.samples(profile.getDouble("rate")), 0f)
        }
        assertTrue(StarmanSynthesis.samples(Double.NaN).isEmpty())
    }

    @Test
    fun repeatedSnapshotsKeepOneUninterruptedLoopBesideTheBoundedEffectsPool() {
        val samples = FloatArray(480) { (sin(it * 2 * PI / 480) * .001).toFloat() }
        val once = AudioVoiceMixer()
        val repeated = AudioVoiceMixer()
        once.setLoop(samples, true)
        repeated.setLoop(samples, true)
        val a = FloatArray(192)
        val b = FloatArray(192)
        repeat(500) {
            repeated.setLoop(samples, true)
            once.render(a)
            repeated.render(b)
            assertArrayEquals("No phase reset or duplicate loop after update$it", a, b, 0f)
            assertEquals(1, repeated.activeLoops)
        }
        repeat(32) { assertTrue(repeated.enqueue(FloatArray(384) { .0001f })) }
        assertFalse(repeated.enqueue(samples))
        assertEquals(32, repeated.activeVoices)
        assertEquals(1, repeated.activeLoops)
        repeated.render(FloatArray(384))
        assertEquals(0, repeated.activeVoices)
        assertEquals(1, repeated.activeLoops)
    }

    @Test
    fun endingPowerFadesOnceThenClearsWithoutReplayingTheBusTail() {
        val mixer = AudioVoiceMixer()
        val samples = FloatArray(128) { .001f }
        mixer.setLoop(samples, true)
        val warm = FloatArray(4800)
        mixer.render(warm)
        assertTrue(warm.any { abs(it) > .0001f })
        mixer.setLoop(samples, false)
        repeat(3) {
            mixer.setLoop(samples, false)
            mixer.render(FloatArray(192))
        }
        assertEquals(0, mixer.activeLoops)
        val tail = FloatArray(288 + 96)
        mixer.render(tail)
        assertTrue(tail.takeLast(96).all { it == 0f })
        mixer.setLoop(samples, true)
        assertEquals(1, mixer.activeLoops)
        mixer.clear()
        assertEquals(0, mixer.activeLoops)
        val cleared = FloatArray(480)
        mixer.render(cleared)
        assertTrue(cleared.all { it == 0f })
    }

    @Test
    fun eitherLivingLocalSeatCanPowerTheSingleLoopButOtherTanksCannot() {
        val first = ArenaTank(id = 1)
        val second = ArenaTank(id = 2, starmanTime = 8.0)
        val state = ArenaSnapshot(tanks = listOf(first, second))
        assertTrue(StarmanLoopState.active(state, 1, 2, true))
        assertFalse(StarmanLoopState.active(state, 1, null, true))
        first.starmanTime = 8.0
        assertTrue(StarmanLoopState.active(state, 1, 2, true))
        assertFalse(StarmanLoopState.active(state, 1, 2, false))
        first.hp = 0
        second.bot = true
        assertFalse(StarmanLoopState.active(state, 1, 2, true))
        second.bot = false
        second.hp = 0
        assertFalse(StarmanLoopState.active(state, 1, 2, true))
        second.hp = 1
        state.phase = "countdown"
        assertFalse(StarmanLoopState.active(state, 1, 2, true))
        state.phase = "playing"
        state.result = ArenaResult()
        assertFalse(StarmanLoopState.active(state, 1, 2, true))
    }
    @Test
    fun cachedLoopSelectionAndRenderingDoNotAllocatePerAudioBlock() {
        val mixer = AudioVoiceMixer()
        mixer.setLoop(StarmanSynthesis.samples(), true)
        val block = FloatArray(192)
        val effect = FloatArray(8192) { .0001f }
        val state = ArenaSnapshot(tanks = List(12) { ArenaTank(id = it + 190, starmanTime = if (it == 10) 8.0 else 0.0) })
        val secondary: Int? = 200
        repeat(1000) { mixer.render(block); StarmanLoopState.active(state, 190, secondary, true) }
        // App unit tests compile against Android's boot classes, so desktop-only
        // allocation instrumentation is reached reflectively, outside the measured loop.
        val allocation = Class.forName("java.lang.management.ManagementFactory").getMethod("getThreadMXBean").invoke(null)
        val allocationClass = Class.forName("com.sun.management.ThreadMXBean")
        assertEquals(true, allocationClass.getMethod("isThreadAllocatedMemorySupported").invoke(allocation))
        allocationClass.getMethod("setThreadAllocatedMemoryEnabled", Boolean::class.javaPrimitiveType).invoke(allocation, true)
        val allocatedBytes = allocationClass.getMethod("getThreadAllocatedBytes", Long::class.javaPrimitiveType)
        val thread = Thread.currentThread().id
        val samples = LongArray(2000)
        var active = 0
        val before = (allocatedBytes.invoke(allocation, thread) as Number).toLong()
        repeat(samples.size) { index ->
            val started = System.nanoTime()
            if (index % 16 == 0) mixer.enqueue(effect)
            if (StarmanLoopState.active(state, 190, secondary, true)) active++
            mixer.render(block)
            samples[index] = System.nanoTime() - started
        }
        val allocated = (allocatedBytes.invoke(allocation, thread) as Number).toLong() - before
        samples.sort()
        println("Starman loop+12-tank selection: p95=${samples[1900] / 1e6}ms, bytes/block=${allocated / samples.size}, active loops=${mixer.activeLoops}")
        assertEquals(samples.size, active)
        assertEquals(1, mixer.activeLoops)
        assertTrue("Cached music must not allocate per render block", allocated <= 4096)
    }

}
