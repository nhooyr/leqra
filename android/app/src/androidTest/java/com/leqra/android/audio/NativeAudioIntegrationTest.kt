package com.leqra.android.audio

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.core.*
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NativeAudioIntegrationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    private fun main(block: () -> Unit) = instrumentation.runOnMainSync(block)

    private fun waitUntil(message: String, condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 10000
        while (SystemClock.elapsedRealtime() < deadline) {
            if (condition()) return
            SystemClock.sleep(5)
        }
        fail(message)
    }

    @Test
    fun mutedLaunchNeverStartsNativeOutputAndRapidCuesStayBounded() {
        lateinit var audio: NativeAudio
        main {
            audio = NativeAudio(instrumentation.targetContext)
            audio.enabled = false
        }
        try {
            main {
                repeat(1000) { audio.play(AudioCue.RAPID) }
                audio.preview(AudioCue.UNMUTE)
                assertEquals(0, audio.outputStarts)
                assertEquals(0, audio.pendingCueCount)
                audio.enabled = true
                audio.volume = 0f
                audio.play(AudioCue.REGULAR)
                assertEquals(0, audio.outputStarts)
                audio.volume = .5f
            }
            waitUntil("Native PCM bank did not warm") {
                audio.preparedVoiceCount == AudioCue.entries.size * 2
            }
            main { audio.play(AudioCue.REGULAR) }
            waitUntil("Native output did not accept samples") { audio.framesWritten > 0 }
            val starts = audio.outputStarts
            main {
                repeat(1000) { audio.play(AudioCue.RAPID) }
                assertTrue(audio.pendingCueCount <= 32)
            }
            waitUntil("Pending sounds never drained") { audio.pendingCueCount == 0 }
            assertEquals(starts, audio.outputStarts)
        } finally {
            main { audio.release() }
        }
    }

    @Test
    fun warmCueLatencyAndPauseDoNotDependOnTheSynthesisExecutor() {
        lateinit var audio: NativeAudio
        main { audio = NativeAudio(instrumentation.targetContext) }
        val latencies = ArrayList<Long>()
        val pauses = ArrayList<Long>()
        try {
            waitUntil("Native PCM bank did not warm") {
                audio.preparedVoiceCount == AudioCue.entries.size * 2
            }
            main { audio.play(AudioCue.REGULAR) }
            waitUntil("Native output did not start") {
                audio.framesWritten > 0 && audio.pendingCueCount == 0
            }
            repeat(20) {
                main { audio.play(AudioCue.RAPID) }
                waitUntil("Cue backlog grew instead of playing") { audio.pendingCueCount == 0 }
                latencies.add(audio.lastCueLatencyNanos)
                SystemClock.sleep(8)
            }
            repeat(5) {
                main {
                    val start = System.nanoTime()
                    audio.pause()
                    pauses.add(System.nanoTime() - start)
                    audio.play(AudioCue.REGULAR)
                }
                waitUntil("Audio did not resume") {
                    audio.pendingCueCount == 0 && audio.outputStarts > it + 1
                }
            }
            assertTrue(latencies.all { it in 0..125_000_000L })
            val report =
                "cue handoff ms ${percentiles(latencies)}\nUI pause ms ${percentiles(pauses)}\n"
            File(instrumentation.targetContext.cacheDir, "audio-performance.txt").writeText(report)
        } finally {
            main { audio.release() }
        }
    }

    @Test
    fun previewStopsWithoutStoppingSubsequentGameplayAudio() {
        lateinit var audio: NativeAudio
        main { audio = NativeAudio(instrumentation.targetContext) }
        try {
            waitUntil("Native PCM bank did not warm") {
                audio.preparedVoiceCount == AudioCue.entries.size * 2
            }
            main { audio.preview(AudioCue.UNMUTE) }
            waitUntil("Preview did not play") { audio.framesWritten > 0 }
            SystemClock.sleep(550)
            val stopped = audio.framesWritten
            SystemClock.sleep(80)
            assertEquals(
                "Ready-room previews should release their output",
                stopped,
                audio.framesWritten,
            )
            main {
                audio.preview(AudioCue.UNMUTE)
                audio.consume(ArenaSnapshot(), 1, true, false)
                audio.play(AudioCue.REGULAR)
            }
            SystemClock.sleep(500)
            val playing = audio.framesWritten
            SystemClock.sleep(80)
            assertTrue("A stale preview timer stopped the game", audio.framesWritten > playing)
        } finally {
            main { audio.release() }
        }
    }

    private fun percentiles(values: List<Long>): String {
        val ordered = values.sorted()
        fun p(fraction: Double) = ordered[((ordered.size - 1) * fraction).toInt()] / 1e6
        return "p50=%.3f p95=%.3f max=%.3f".format(p(.5), p(.95), p(1.0))
    }
}
