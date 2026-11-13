package com.leqra.android

import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.*
import android.view.FrameMetrics
import android.view.Window
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiSelector
import com.leqra.android.accounts.EncryptedAccountStore
import com.leqra.android.render.NativeArenaView
import com.leqra.android.render.RenderStressScene
import com.leqra.core.*
import java.io.File
import java.util.Collections
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Profiles the actual Activity, HUD, status and standings, not just an isolated arena View. */
@RunWith(AndroidJUnit4::class)
class MainAppPerformanceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    private fun main(block: () -> Unit) = instrumentation.runOnMainSync(block)

    @Suppress("UNCHECKED_CAST")
    private fun <T> get(owner: Any, name: String): T =
        owner.javaClass.getDeclaredField(name).run {
            isAccessible = true
            get(owner) as T
        }

    private fun set(owner: Any, name: String, value: Any?) {
        owner.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(owner, value)
    }

    private fun waitUntil(message: String, predicate: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 8000
        while (SystemClock.elapsedRealtime() < deadline) {
            var done = false
            main { done = predicate() }
            if (done) return
            SystemClock.sleep(25)
        }
        val capture = instrumentation.uiAutomation.takeScreenshot()
        File(instrumentation.targetContext.cacheDir, "main-app-benchmark-failure.png")
            .outputStream()
            .use { capture.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        capture.recycle()
        fail(message)
    }

    @Test
    fun allPowerUpsKeepTheWholeAppResponsiveWithStandingsOpenOrClosed() {
        val context = instrumentation.targetContext
        val prefs = context.getSharedPreferences("leqra-settings", 0)
        val savedPrefs = prefs.all.toMap()
        val store = EncryptedAccountStore(context)
        val savedIntent = store.activeIntent()
        store.setActiveIntent(null)
        prefs
            .edit()
            .clear()
            .putBoolean("muted", true)
            .putBoolean("publicSelected", false)
            .putString(
                "server",
                InstrumentationRegistry.getArguments().getString("server")
                    ?: "http://10.0.2.2:8080",
            )
            .commit()
        val activity =
            instrumentation.startActivitySync(
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK),
            ) as MainActivity
        val device = UiDevice.getInstance(instrumentation)
        val education = device.findObject(UiSelector().text("Got it"))
        if (education.waitForExists(500)) education.click()
        val thread = HandlerThread("leqra-app-frame-metrics").apply { start() }
        val recording = AtomicBoolean(false)
        val totals = Collections.synchronizedList(ArrayList<Long>())
        val draws = Collections.synchronizedList(ArrayList<Long>())
        val callbacks = Collections.synchronizedList(ArrayList<Long>())
        val misses = AtomicInteger()
        val listener = Window.OnFrameMetricsAvailableListener { _, metric, _ ->
            if (recording.get()) {
                val total = metric.getMetric(FrameMetrics.TOTAL_DURATION)
                if (total > 0) {
                    totals.add(total)
                    draws.add(metric.getMetric(FrameMetrics.DRAW_DURATION))
                    if (Build.VERSION.SDK_INT >= 31) {
                        val deadline = metric.getMetric(FrameMetrics.DEADLINE)
                        if (deadline > 0 && total >= deadline) misses.incrementAndGet()
                    }
                }
            }
        }
        val output = File(context.cacheDir, "main-app-benchmark").apply { mkdirs() }
        val reports = ArrayList<String>()
        lateinit var session: GameSession
        lateinit var arena: NativeArenaView
        lateinit var hud: NativeHudView
        lateinit var status: NativeStatusView
        lateinit var originalFrame: (Long) -> Unit
        var fixture = RenderStressScene(false)
        var start = 0L
        try {
            main {
                session = get(activity, "session")
                arena = get(activity, "arena")
                hud = get(activity, "loadout")
                status = get(activity, "statusLine")
                originalFrame = arena.onFrame!!
                activity.window.addOnFrameMetricsAvailableListener(listener, Handler(thread.looper))
                arena.onFrame = { nanos ->
                    if (start == 0L) start = nanos
                    set(session, "snapshot", fixture.update((nanos - start) / 1e9))
                    val before = System.nanoTime()
                    originalFrame(nanos)
                    if (recording.get()) callbacks.add(System.nanoTime() - before)
                }
                set(session, "online", true)
                set(session, "screen", Screen.PLAYING)
                set(session, "localID", 1)
            }
            for (landscape in listOf(false, true)) for (fixed in
                listOf(false, true)) for (standings in listOf(false, true)) {
                main {
                    fixture = RenderStressScene(fixed)
                    start = 0
                    set(session, "infinity", !fixed)
                    session.mode = if (fixed) "elimination" else "infinity"
                    session.rules = RoomRules.localDefaults(session.mode)
                    set(session, "maze", fixture.maze)
                    set(session, "snapshot", fixture.update(0.0))
                    set(activity, "showScores", standings)
                    activity.requestedOrientation =
                        if (landscape) ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                        else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    session.changed(true)
                }
                var geometry = ""
                waitUntil("The full app did not rotate") {
                    geometry =
                        "arena=${arena.width}x${arena.height} window=${activity.window.decorView.width}x${activity.window.decorView.height} wantedLandscape=$landscape fixed=$fixed paused=${session.paused} screen=${session.screen}"
                    File(output, "geometry.txt").writeText(geometry)
                    arena.width > 0 &&
                        arena.height > 0 &&
                        (activity.window.decorView.width > activity.window.decorView.height) ==
                            landscape
                }
                SystemClock.sleep(2000)
                totals.clear()
                draws.clear()
                callbacks.clear()
                misses.set(0)
                var frameStart = 0L
                var scoreStart = 0L
                var labelStart = 0L
                var statusStart = 0L
                main {
                    frameStart = arena.renderedFrames
                    scoreStart = activity.scorePanelBuilds
                    labelStart = hud.contentUpdates
                    statusStart = status.textUpdates
                }
                val allocated = runtimeStat("art.gc.bytes-allocated")
                val gcCount = runtimeStat("art.gc.blocking-gc-count")
                val now = SystemClock.elapsedRealtimeNanos()
                recording.set(true)
                SystemClock.sleep(2000)
                recording.set(false)
                val elapsed = (SystemClock.elapsedRealtimeNanos() - now) / 1e9
                var frames = 0L
                var scoreBuilds = 0L
                var textUpdates = 0L
                var statusUpdates = 0L
                main {
                    frames = arena.renderedFrames - frameStart
                    scoreBuilds = activity.scorePanelBuilds - scoreStart
                    textUpdates = hud.contentUpdates - labelStart
                    statusUpdates = status.textUpdates - statusStart
                }
                assertTrue("The full native app must continue drawing", frames >= 30)
                assertTrue("Window frame metrics are available", totals.size >= 20)
                assertEquals("Unchanged standings must not rebuild on every frame", 0L, scoreBuilds)
                val title =
                    (if (fixed) "fixed" else "infinity") +
                        "-" +
                        (if (landscape) "landscape" else "portrait") +
                        if (standings) "-scores" else ""
                val report =
                    "$title fps=${"%.1f".format(frames/elapsed)} missedDeadlines=${misses.get()} totalMs=${percentiles(totals)} drawMs=${percentiles(draws)} callbackMs=${percentiles(callbacks)} allocatedMBps=${"%.2f".format((runtimeStat("art.gc.bytes-allocated")-allocated)/1e6/elapsed)} blockingGCs=${runtimeStat("art.gc.blocking-gc-count")-gcCount} scoreBuilds=$scoreBuilds hudTextUpdates=$textUpdates statusTextUpdates=$statusUpdates"
                reports.add(report)
                File(output, "timings.txt").writeText(reports.joinToString("\n", postfix = "\n"))
                android.util.Log.i("leqra-app-benchmark", report)
                val png = instrumentation.uiAutomation.takeScreenshot()
                File(output, "$title.png").outputStream().use {
                    png.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                }
                png.recycle()
            }
            File(output, "timings.txt").writeText(reports.joinToString("\n", postfix = "\n"))
        } finally {
            recording.set(false)
            main {
                activity.window.removeOnFrameMetricsAvailableListener(listener)
                activity.finish()
            }
            thread.quitSafely()
            val editor = prefs.edit().clear()
            for ((key, value) in savedPrefs) when (value) {
                is String -> editor.putString(key, value)
                is Int -> editor.putInt(key, value)
                is Boolean -> editor.putBoolean(key, value)
                is Float -> editor.putFloat(key, value)
                is Long -> editor.putLong(key, value)
                is Set<*> ->
                    @Suppress("UNCHECKED_CAST") editor.putStringSet(key, value as Set<String>)
            }
            editor.commit()
            store.setActiveIntent(savedIntent)
        }
    }

    private fun runtimeStat(key: String) = Debug.getRuntimeStat(key)?.toLongOrNull() ?: 0L

    private fun percentiles(values: List<Long>): String {
        val ordered = synchronized(values) { values.sorted() }
        if (ordered.isEmpty()) return "none"
        fun p(fraction: Double) = ordered[((ordered.size - 1) * fraction).toInt()] / 1e6
        return "p50=%.3f,p95=%.3f,p99=%.3f".format(p(.5), p(.95), p(.99))
    }
}
