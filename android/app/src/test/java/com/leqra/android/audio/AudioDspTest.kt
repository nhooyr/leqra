package com.leqra.android.audio

import com.leqra.core.*
import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class AudioDspTest {
    @Test
    fun synthesizedVoicesMatchIndependentBrowserOfflineAudioReference() {
        // Captured from the browser's 48kHz OfflineAudioContext, also used by iOS.
        val references =
            listOf(
                Triple(AudioCue.REGULAR, .0036482660528818927, .04722806438803673),
                Triple(AudioCue.LASER, .002774291993038309, .026573486626148224),
                Triple(AudioCue.PICKUP, .0021029309166631753, .012912243604660034),
                Triple(AudioCue.EXPLOSION, .007940465198757839, .05132853239774704),
                Triple(AudioCue.GRENADE_EXPLOSION, .010716303496570814, .06949907541275024),
            )
        for ((cue, rms, peak) in references) {
            val pcm = AudioSynthesis.samples(cue)
            assertEquals(
                "$cue RMS",
                rms,
                sqrt(pcm.sumOf { it.toDouble() * it } / 28_800),
                rms * .001,
            )
            assertEquals("$cue peak", peak, pcm.maxOf { abs(it) }.toDouble(), peak * .001)
        }
    }

    @Test
    fun shortCueMixMatchesBrowserOfflineAudioReference() {
        val references =
            listOf(
                Triple(AudioCue.REGULAR, .2438400536775589, .021938487078701455),
                Triple(AudioCue.RAPID, .10355628281831741, .008488832582143476),
                Triple(AudioCue.LASER, .15497878193855286, .02378347603170648),
                Triple(AudioCue.CANNON, .33652395009994507, .055846590780702775),
                Triple(AudioCue.PICKUP, .17037874460220337, .027143030315682107),
            )
        for ((cue, expectedPeak, expectedRMS) in references) {
            val raw = AudioSynthesis.samples(cue)
            val processor = AudioMixProcessor()
            var peak = 0.0
            var energy = 0.0
            repeat(28_800) { frame ->
                val sample = processor.process(if (frame < raw.size) raw[frame] else 0f).toDouble()
                peak = max(peak, abs(sample))
                energy += sample * sample
            }
            assertEquals(
                "$cue mixed peak",
                expectedPeak,
                peak,
                expectedPeak * if (cue == AudioCue.PICKUP) .025 else .005,
            )
            assertEquals("$cue mixed RMS", expectedRMS, sqrt(energy / 28_800), expectedRMS * .005)
        }
    }

    @Test
    fun recipesMatchWebAndIOSGainsAndTiming() {
        val rapid = AudioSynthesis.recipe(AudioCue.RAPID).tones.single()
        assertEquals(210.0, rapid.frequency, 0.0)
        assertEquals(120.0, rapid.endFrequency, 0.0)
        assertEquals(.023, rapid.gain, 0.0)
        assertEquals(.06, rapid.duration, 0.0)
        assertEquals(AudioWaveform.TRIANGLE, rapid.waveform)
        assertEquals(.014, AudioSynthesis.recipe(AudioCue.RAPID, false).tones.single().gain, 0.0)
        assertEquals(
            listOf(0.0, .07, .14),
            AudioSynthesis.recipe(AudioCue.PICKUP).tones.map { it.delay },
        )
        assertEquals(320.0, AudioSynthesis.recipe(AudioCue.EXPLOSION).noise!!.cutoff, 0.0)
        assertEquals(750.0, AudioSynthesis.recipe(AudioCue.GRENADE_EXPLOSION).noise!!.cutoff, 0.0)
        for (cue in AudioCue.entries) {
            val recipe = AudioSynthesis.recipe(cue)
            val samples = AudioSynthesis.samples(cue)
            assertEquals(ceil(recipe.duration * 48_000).toInt(), samples.size)
            assertTrue(
                "$cue finite audible PCM",
                samples.all { it.isFinite() } && samples.any { abs(it) > .0001 },
            )
            assertEquals("$cue has no hard attack", 0f, samples.first(), .000001f)
            assertEquals("$cue has no hard tail", 0f, samples.last(), .000001f)
        }
    }

    @Test
    fun noiseAndSweepAreDeterministicAndSmooth() {
        val first = AudioSynthesis.samples(AudioCue.GRENADE_EXPLOSION)
        assertArrayEquals(first, AudioSynthesis.samples(AudioCue.GRENADE_EXPLOSION), 0f)
        val tone = AudioSynthesis.recipe(AudioCue.REGULAR).tones.single()
        assertEquals(0.0, AudioSynthesis.phase(tone, 0.0), 0.0)
        assertEquals(
            tone.gain,
            AudioSynthesis.envelope(tone, min(.012, tone.duration * .16)),
            .0000001,
        )
        assertEquals(0.0, AudioSynthesis.envelope(tone, tone.duration + .008), 0.0)
        assertTrue(AudioSynthesis.samples(AudioRecipe(), 48_000.0).isEmpty())
        assertTrue(AudioSynthesis.samples(AudioCue.REGULAR, sampleRate = Double.NaN).isEmpty())
    }

    @Test
    fun sharedBusProtectsPeaksAndAppliesVolumeAfterLimiting() {
        val full = AudioMixProcessor(volume = 1f)
        val half = AudioMixProcessor(volume = .5f)
        repeat(48_000) { index ->
            val sample = (sin(index * .2) * 20).toFloat()
            val a = full.process(sample)
            val b = half.process(sample)
            assertTrue(abs(a) <= .980001f)
            assertEquals(a * .5f, b, .000001f)
        }
        full.process(Float.NaN)
        full.process(Float.POSITIVE_INFINITY)
        repeat(1000) { assertTrue(full.process(.01f).isFinite()) }
    }

    @Test
    fun muteRampsAndClearingDoesNotReplayDelayedAudio() {
        val bus = AudioMixProcessor(volume = 1f)
        repeat(5000) { bus.process(.01f) }
        bus.setVolume(0f)
        repeat(576) {
            // Repeated UI refreshes must not keep restarting the same fade.
            if (it % 32 == 0) bus.setVolume(0f)
            bus.process(.01f)
        }
        repeat(100) { assertEquals(0f, bus.process(.01f), .0000001f) }
        bus.setVolume(1f, true)
        bus.reset()
        repeat(bus.latencyFrames) { assertEquals(0f, bus.process(.01f), 0f) }
    }

    @Test
    fun voicePoolIsBoundedWithoutTruncatingPlayingVoices() {
        val mixer = AudioVoiceMixer(capacity = 32)
        val voice = FloatArray(512) { .001f }
        repeat(32) { assertTrue(mixer.enqueue(voice)) }
        assertFalse(mixer.enqueue(voice))
        assertEquals(32, mixer.activeVoices)
        mixer.render(FloatArray(256))
        assertEquals(32, mixer.activeVoices)
        mixer.render(FloatArray(256))
        assertEquals(0, mixer.activeVoices)
        assertTrue(mixer.enqueue(voice))
        mixer.clear()
        assertEquals(0, mixer.activeVoices)
    }

    @Test
    fun routerBaselinesHistoryAndBoundsStarmanSounds() {
        val router = AudioEventRouter()
        val tank = ArenaTank(id = 1, starmanTime = 5.0)
        val baseline =
            ArenaSnapshot(
                tanks = listOf(tank),
                effects = listOf(ArenaEffect(id = 1, kind = "shot:rapid", owner = 1)),
            )
        assertTrue(router.consume(baseline, 1, true, false, 0.0).isEmpty())
        var heard = 0
        repeat(120) { frame ->
            val next =
                baseline.copy(
                    effects = listOf(ArenaEffect(id = frame + 2, kind = "shot:rapid", owner = 1)),
                )
            val requests = router.consume(next, 1, true, false, frame / 120.0)
            heard += requests.count { it.cue == AudioCue.RAPID }
            assertTrue(router.consume(next, 1, true, false, frame / 120.0).isEmpty())
        }
        assertTrue("120Hz snapshots must not create 120 voices per second", heard in 14..16)
    }

    @Test
    fun grenadeExplosionHasIndependentGateAndRemoteInfinityCuesAreCulled() {
        val router = AudioEventRouter()
        val tank = ArenaTank(id = 1)
        val state = ArenaSnapshot(tanks = listOf(tank))
        router.consume(state, 1, true, true, 0.0)
        val next =
            state.copy(
                effects =
                    listOf(
                        ArenaEffect(id = 1, kind = "hit"),
                        ArenaEffect(id = 2, kind = "blast"),
                        ArenaEffect(id = 3, kind = "shot:cannon", x = 10000.0),
                    ),
            )
        assertEquals(
            listOf(AudioCue.EXPLOSION, AudioCue.GRENADE_EXPLOSION),
            router.consume(next, 1, true, true, 1.0).map { it.cue },
        )
    }
}
