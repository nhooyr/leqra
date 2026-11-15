package com.leqra.android

import android.content.Intent
import android.os.*
import android.view.FrameMetrics
import android.view.Window
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.android.accounts.EncryptedAccountStore
import com.leqra.android.render.NativeArenaView
import com.leqra.core.*
import java.io.File
import java.util.Collections
import java.util.concurrent.atomic.AtomicBoolean
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Actual pickup collision + held fire through the Activity, renderer, HUD and audio path. */
@RunWith(AndroidJUnit4::class)
class PickupFirePerformanceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private fun set(owner: Any, name: String, value: Any?) = owner.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(owner, value)
    @Suppress("UNCHECKED_CAST") private fun <T> get(owner: Any, name: String): T = owner.javaClass.getDeclaredField(name).run { isAccessible = true; get(owner) as T }
    private fun main(block: () -> Unit) = instrumentation.runOnMainSync(block)

    @Test fun everyFirstPickupAndShotReportsTheSameFixedAndInfinityEventWindow() {
        val context = instrumentation.targetContext
        val preferences = context.getSharedPreferences("leqra-settings", 0)
        val saved = preferences.all.toMap()
        val store = EncryptedAccountStore(context)
        val intent = store.activeIntent()
        store.setActiveIntent(null)
        val output = File(context.cacheDir, "pickup-fire-benchmark").apply { mkdirs() }
        val reports = ArrayList<String>()
        val worker = HandlerThread("leqra-event-metrics").apply { start() }
        try {
            for (fixed in listOf(false, true)) for (audible in listOf(false, true)) for (kind in listOf("") + PracticeArena.pickupKinds) {
                preferences.edit().clear().putBoolean("muted", !audible).putBoolean("publicSelected", false)
                    .putString("callsign", "pilot#ABC234").putString("server", "http://127.0.0.1:1").commit()
                val monitor = instrumentation.addMonitor(MainActivity::class.java.name, null, false)
                val activity = try {
                    context.startActivity(Intent(context, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
                    monitor.waitForActivityWithTimeout(10000) as? MainActivity
                        ?: error("Activity did not launch")
                } finally { instrumentation.removeMonitor(monitor) }
                val recording = AtomicBoolean(false)
                val callbacks = Collections.synchronizedList(ArrayList<Long>())
                val draws = Collections.synchronizedList(ArrayList<Long>())
                val totals = Collections.synchronizedList(ArrayList<Long>())
                var begun = false
                var pickedUp = false
                var shots = 0
                var frames = 0L
                var start = 0L
                val listener = Window.OnFrameMetricsAvailableListener { _, metrics, _ -> if (recording.get()) {
                    draws += metrics.getMetric(FrameMetrics.DRAW_DURATION)
                    totals += metrics.getMetric(FrameMetrics.TOTAL_DURATION)
                } }
                lateinit var session: GameSession
                lateinit var view: NativeArenaView
                lateinit var practice: PracticeArena
                try {
                    main {
                        session = get(activity, "session")
                        view = get(activity, "arena")
                        practice = PracticeArena(42, "pilot#ABC234", 0, 0, world = if (fixed) FixedArena(RoomRules.localDefaults(), "pilot#ABC234", 0, 0, seed = 42).world else null)
                        set(practice, "pickupRate", "off")
                        practice.snapshot.tanks.first().apply { invulnerable = 0.0; spawnProtected = false }
                        set(session, "practice", practice); set(session, "fixed", null)
                        set(session, "online", false); set(session, "screen", Screen.PLAYING)
                        set(session, "infinity", !fixed); set(session, "localID", 1)
                        set(session, "maze", practice.maze); set(session, "snapshot", practice.snapshot)
                        session.mode = if (fixed) "elimination" else "infinity"
                        session.rules = RoomRules.localDefaults(session.mode)
                        session.input = GameInput(forward = true, right = true)
                        val frame = view.onFrame!!
                        activity.window.addOnFrameMetricsAvailableListener(listener, Handler(worker.looper))
                        view.onFrame = { nanos ->
                            if (start == 0L) start = nanos
                            val elapsed = (nanos - start) / 1e9
                            if (!begun && elapsed >= .5) {
                                val tank = practice.snapshot.tanks.first()
                                if (kind.isNotEmpty()) practice.snapshot.pickups = listOf(ArenaPickup(id = 90001, x = tank.x, y = tank.y, type = kind))
                                session.input.fire = true
                                begun = true
                                recording.set(true)
                            }
                            val before = System.nanoTime()
                            frame(nanos)
                            if (recording.get()) { callbacks += System.nanoTime() - before; frames++ }
                            if (begun) {
                                if (kind.isEmpty() || practice.snapshot.effects.any { it.kind == "pickup" }) pickedUp = true
                                shots = maxOf(shots, practice.snapshot.effects.count { it.kind.startsWith("shot:") || it.kind == "laser" })
                            }
                        }
                        session.changed(true)
                    }
                    val deadline = SystemClock.elapsedRealtime() + 5000
                    while (SystemClock.elapsedRealtime() < deadline && !recording.get()) SystemClock.sleep(10)
                    assertTrue("Event scene starts", recording.get())
                    val bytes = Debug.getRuntimeStat("art.gc.bytes-allocated")?.toLongOrNull() ?: 0
                    SystemClock.sleep(650)
                    recording.set(false)
                    main {
                        assertTrue("The $kind pickup is collected", pickedUp)
                        assertTrue("The $kind first shot fires", shots > 0)
                        view.onFrame = null
                    }
                    val allocated = (Debug.getRuntimeStat("art.gc.bytes-allocated")?.toLongOrNull() ?: 0) - bytes
                    val title = "${if(fixed) "fixed" else "infinity"}-${if(audible) "audio" else "muted"}-${kind.ifEmpty { "regular" }}"
                    reports += "$title frames=$frames callbackMs=${percentiles(callbacks)} drawMs=${percentiles(draws)} totalMs=${percentiles(totals)} bytes=$allocated"
                    File(output, "timings.txt").writeText(reports.joinToString("\n", postfix = "\n"))
                } finally { main { activity.window.removeOnFrameMetricsAvailableListener(listener); activity.finish() } }
            }
        } finally {
            worker.quitSafely()
            val editor = preferences.edit().clear()
            for ((key, value) in saved) when (value) {
                is String -> editor.putString(key, value)
                is Int -> editor.putInt(key, value)
                is Boolean -> editor.putBoolean(key, value)
                is Float -> editor.putFloat(key, value)
                is Long -> editor.putLong(key, value)
                is Set<*> -> @Suppress("UNCHECKED_CAST") editor.putStringSet(key, value as Set<String>)
            }
            editor.commit(); store.setActiveIntent(intent)
        }
    }

    private fun percentiles(values: List<Long>): String {
        val sorted = synchronized(values) { values.sorted() }
        if (sorted.isEmpty()) return "none"
        fun p(f: Double) = sorted[((sorted.size - 1) * f).toInt()] / 1e6
        return "p50=%.3f,p95=%.3f,p99=%.3f,max=%.3f".format(p(.5), p(.95), p(.99), sorted.last()/1e6)
    }
}
