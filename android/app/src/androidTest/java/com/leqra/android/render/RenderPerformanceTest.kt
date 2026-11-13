package com.leqra.android.render

import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.view.FrameMetrics
import android.view.Window
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import java.io.File
import java.util.Collections
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Device/emulator timing evidence, not a claim that an emulator represents physical 120Hz hardware.
 */
@RunWith(AndroidJUnit4::class)
class RenderPerformanceTest {
    @Test
    fun allPowerUpsRemainBoundedAndRenderInBothOrientations() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val activity =
            instrumentation.startActivitySync(
                Intent(context, RenderBenchmarkActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            ) as RenderBenchmarkActivity
        val device = UiDevice.getInstance(instrumentation)
        // Android's one-time immersive-mode education is a system overlay, not
        // part of this app. Dismiss it before measuring or taking screenshots.
        device.wait(Until.findObject(By.text("Got it")), 1500)?.click()
        device.waitForIdle()
        val metricsThread = HandlerThread("leqra-frame-metrics").apply { start() }
        val total = Collections.synchronizedList(ArrayList<Long>())
        val draw = Collections.synchronizedList(ArrayList<Long>())
        val gpu = Collections.synchronizedList(ArrayList<Long>())
        val swap = Collections.synchronizedList(ArrayList<Long>())
        val gpuWork = Collections.synchronizedList(ArrayList<Long>())
        val unknown = Collections.synchronizedList(ArrayList<Long>())
        val deadlines = Collections.synchronizedList(ArrayList<Long>())
        val missedDeadlines = AtomicLong()
        val active = AtomicBoolean(false)
        val dropped = AtomicLong()
        val listener = Window.OnFrameMetricsAvailableListener { _, metrics, missed ->
            if (active.get()) {
                val duration = metrics.getMetric(FrameMetrics.TOTAL_DURATION)
                if (duration > 0) {
                    total += duration
                    draw += metrics.getMetric(FrameMetrics.DRAW_DURATION)
                    gpu +=
                        metrics.getMetric(FrameMetrics.SYNC_DURATION) +
                            metrics.getMetric(FrameMetrics.COMMAND_ISSUE_DURATION)
                    swap += metrics.getMetric(FrameMetrics.SWAP_BUFFERS_DURATION)
                    unknown += metrics.getMetric(FrameMetrics.UNKNOWN_DELAY_DURATION)
                    if (Build.VERSION.SDK_INT >= 31) {
                        gpuWork += metrics.getMetric(FrameMetrics.GPU_DURATION)
                        // Android's API defines a met deadline as TOTAL_DURATION < DEADLINE.
                        // https://developer.android.com/reference/android/view/FrameMetrics#DEADLINE
                        val deadline = metrics.getMetric(FrameMetrics.DEADLINE)
                        deadlines += deadline
                        if (deadline > 0 && duration >= deadline) missedDeadlines.incrementAndGet()
                    }
                }
                dropped.addAndGet(missed.toLong())
            }
        }
        instrumentation.runOnMainSync {
            activity.window.addOnFrameMetricsAvailableListener(
                listener,
                Handler(metricsThread.looper),
            )
        }
        val output = File(context.cacheDir, "render-benchmark").apply { mkdirs() }
        val reports = ArrayList<String>()
        try {
            for (landscape in listOf(false, true)) for (fixed in listOf(false, true)) {
                active.set(false)
                instrumentation.runOnMainSync {
                    activity.requestedOrientation =
                        if (landscape) ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                        else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    activity.configure(fixed)
                }
                val deadline = SystemClock.elapsedRealtime() + 5000
                var correct = false
                while (!correct && SystemClock.elapsedRealtime() < deadline) {
                    instrumentation.runOnMainSync {
                        correct =
                            activity.arena.width > 0 &&
                                (activity.arena.width > activity.arena.height) == landscape
                    }
                    if (!correct) SystemClock.sleep(40)
                }
                assertTrue("Requested orientation is available", correct)
                SystemClock.sleep(2000) // Warm JIT, terrain rasters, and GPU artwork uploads.
                total.clear()
                draw.clear()
                gpu.clear()
                swap.clear()
                gpuWork.clear()
                unknown.clear()
                deadlines.clear()
                missedDeadlines.set(0)
                dropped.set(0)
                var beforeFrames = 0L
                var beforeTiles = 0L
                instrumentation.runOnMainSync {
                    beforeFrames = activity.arena.renderedFrames
                    beforeTiles = activity.arena.terrainTilesBuilt
                }
                val started = SystemClock.elapsedRealtimeNanos()
                active.set(true)
                SystemClock.sleep(3000)
                active.set(false)
                val elapsed = (SystemClock.elapsedRealtimeNanos() - started) / 1e9
                var frames = 0L
                var tiles = 0L
                instrumentation.runOnMainSync {
                    frames = activity.arena.renderedFrames - beforeFrames
                    tiles = activity.arena.terrainTilesBuilt - beforeTiles
                }
                assertTrue("The native arena produced frames", frames >= 10)
                assertTrue("Window frame metrics were received", total.size >= 10)
                assertTrue("Steady movement must reuse map tiles", tiles < 100)
                val name =
                    (if (fixed) "fixed" else "infinity") +
                        "-" +
                        (if (landscape) "landscape" else "portrait")
                val screenshot = instrumentation.uiAutomation.takeScreenshot()
                assertNotNull("Full-screen render screenshot", screenshot)
                File(output, "$name.png").outputStream().use {
                    screenshot.compress(Bitmap.CompressFormat.PNG, 100, it)
                }
                screenshot.recycle()
                val line =
                    "$name frames=$frames fps=${"%.1f".format(frames / elapsed)} tiles=$tiles missedMetrics=${dropped.get()} totalMs=${percentiles(total)} drawMs=${percentiles(draw)} renderThreadMs=${percentiles(gpu)} gpuMs=${percentiles(gpuWork)} swapMs=${percentiles(swap)} unknownMs=${percentiles(unknown)} deadlineMs=${percentiles(deadlines)} missedDeadlines=${missedDeadlines.get()}/${total.size}"
                reports += line
                Log.i("leqra-benchmark", line)
            }
            File(output, "timings.txt").writeText(reports.joinToString("\n", postfix = "\n"))
            Log.i("leqra-benchmark", "Artifacts: ${output.absolutePath}")
        } finally {
            active.set(false)
            instrumentation.runOnMainSync {
                activity.window.removeOnFrameMetricsAvailableListener(listener)
                activity.finish()
            }
            metricsThread.quitSafely()
        }
    }

    private fun percentiles(values: List<Long>): String {
        val sorted = synchronized(values) { values.sorted() }
        if (sorted.isEmpty()) return "none"
        fun percentile(fraction: Double) = sorted[((sorted.size - 1) * fraction).toInt()] / 1e6
        return "p50=%.3f,p95=%.3f,p99=%.3f".format(percentile(.5), percentile(.95), percentile(.99))
    }
}
