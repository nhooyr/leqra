package com.leqra.android

import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.KeyEvent
import android.view.View
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiSelector
import com.leqra.core.ArenaSnapshot
import com.leqra.core.ArenaTank
import com.leqra.core.GameInput
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MainActivityTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val server =
        InstrumentationRegistry.getArguments().getString("server") ?: "http://10.0.2.2:8080"

    private fun launch(): MainActivity {
        instrumentation.targetContext
            .getSharedPreferences("leqra-settings", 0)
            .edit()
            .clear()
            .putString("server", server)
            .putBoolean("publicSelected", false)
            .putBoolean("muted", true)
            .commit()
        val intent =
            Intent(instrumentation.targetContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        val activity = instrumentation.startActivitySync(intent) as MainActivity
        val education =
            UiDevice.getInstance(instrumentation).findObject(UiSelector().text("Got it"))
        if (education.waitForExists(500)) education.click()
        val deadline = SystemClock.elapsedRealtime() + 5000
        while (
            !main { activity.hasWindowFocus() } && SystemClock.elapsedRealtime() < deadline
        ) SystemClock.sleep(20)
        assertTrue(
            "Main window has focus before injecting hardware controls",
            main { activity.hasWindowFocus() },
        )
        return activity
    }

    private fun state(activity: MainActivity): GameSession =
        MainActivity::class.java.getDeclaredField("session").run {
            isAccessible = true
            get(activity) as GameSession
        }

    private fun <T> main(block: () -> T): T {
        var result: Result<T>? = null
        instrumentation.runOnMainSync { result = runCatching(block) }
        return result!!.getOrThrow()
    }

    @Test
    fun allFiveModesRenderMoveFirePauseAndRotate() {
        val activity = launch()
        try {
            val session = main { state(activity) }
            for (mode in GameSession.modes.keys) {
                main {
                    session.leave()
                    session.publicSelected = false
                    session.botCount = 0
                    session.localSelected = true
                    session.selectMode(mode)
                }
                val play =
                    UiDevice.getInstance(instrumentation).findObject(UiSelector().text("PLAY  →"))
                assertTrue("Native Play button is present for $mode", play.waitForExists(2000))
                play.click()
                main {
                    assertEquals(Screen.PLAYING, session.screen)
                    session.input = GameInput(stickX = 1.0, fire = true)
                }
                SystemClock.sleep(150)
                if (mode == "infinity") {
                    instrumentation.sendKeySync(
                        KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_LEFT),
                    )
                    main {
                        assertTrue(
                            "P2 keyboard route: screen=${session.screen}, id=${session.localID2}, input=${session.input}, second=${session.input2}",
                            session.input2.left,
                        )
                        assertFalse(session.input.left)
                    }
                    instrumentation.sendKeySync(
                        KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DPAD_LEFT),
                    )
                    main { assertFalse(session.input2.left) }
                }
                SystemClock.sleep(900)
                main {
                    assertEquals(Screen.PLAYING, session.screen)
                    val stage =
                        MainActivity::class.java.getDeclaredField("stage").run {
                            isAccessible = true
                            get(activity) as View
                        }
                    val header =
                        MainActivity::class.java.getDeclaredField("header").run {
                            isAccessible = true
                            get(activity) as View
                        }
                    assertTrue(
                        "$mode arena keeps usable height below native chrome",
                        stage.height > 0,
                    )
                    assertTrue(
                        "Horizontal header spacers cannot consume the window height",
                        header.height < 100 * activity.resources.displayMetrics.density,
                    )
                    assertTrue("$mode simulation advances", session.snapshot.tick > 10)
                    assertEquals(2, session.localID2)
                    assertTrue(session.snapshot.tanks.any { it.id == session.localID2 && !it.bot })
                    assertTrue(session.snapshot.tanks.all { it.x.isFinite() && it.y.isFinite() })
                    assertEquals(mode == "infinity", session.snapshot.world == null)
                    session.pause(true)
                }
                screenshot("$mode-portrait")
                val tick = main { session.snapshot.tick }
                SystemClock.sleep(120)
                main {
                    assertEquals("Pause freezes local physics", tick, session.snapshot.tick)
                    session.pause(false)
                }
                main { activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE }
                SystemClock.sleep(
                    500,
                ) // Let the system rotation animation finish before visual evidence.
                screenshot("$mode-landscape")
                main {
                    assertEquals(Screen.PLAYING, session.screen)
                    assertTrue(activity.window.decorView.width > activity.window.decorView.height)
                    assertNotNull(activity.findViewById<View>(android.R.id.content))
                    activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                }
                SystemClock.sleep(200)
            }
        } finally {
            main { activity.finish() }
        }
    }

    @Test
    fun readyRoomShowsNativeAccountControlsAndSupportsMenu() {
        val activity = launch()
        val device = UiDevice.getInstance(instrumentation)
        try {
            val education = device.findObject(UiSelector().text("Got it"))
            if (education.waitForExists(500)) education.click()
            assertTrue(device.findObject(UiSelector().text("READY ROOM.")).waitForExists(5000))
            assertTrue(device.findObject(UiSelector().description("P1 callsign")).exists())
            assertTrue(device.findObject(UiSelector().description("P1 account key")).exists())
            device.findObject(UiSelector().description("Open menu")).click()
            assertTrue(device.findObject(UiSelector().text("P2 ACCOUNT KEY")).waitForExists(2000))
            device.findObject(UiSelector().text("P2 ACCOUNT KEY")).click()
            assertTrue(
                device
                    .findObject(UiSelector().text("IMPORT FROM ANOTHER DEVICE"))
                    .waitForExists(2000),
            )
            device.pressBack()
        } finally {
            main { activity.finish() }
        }
    }

    @Test
    fun unchangedHudAndStandingsDoNotRebuildAndModalReleasesHeldKeys() {
        val activity = launch()
        val device = UiDevice.getInstance(instrumentation)
        try {
            val session = main { state(activity) }
            main {
                session.publicSelected = false
                session.botCount = 0
                session.selectMode("infinity")
            }
            device.findObject(UiSelector().text("PLAY  →")).click()
            main { session.pause(true) }
            device.findObject(UiSelector().description("Leaderboard")).click()
            main {
                val hud =
                    MainActivity::class.java.getDeclaredField("loadout").run {
                        isAccessible = true
                        get(activity) as NativeHudView
                    }
                val status =
                    MainActivity::class.java.getDeclaredField("statusLine").run {
                        isAccessible = true
                        get(activity) as NativeStatusView
                    }
                val builds = activity.scorePanelBuilds
                val content = hud.contentUpdates
                val labels = status.textUpdates
                val refresh =
                    MainActivity::class
                        .java
                        .getDeclaredMethod("refresh", Boolean::class.javaPrimitiveType)
                        .apply { isAccessible = true }
                repeat(60) { refresh.invoke(activity, false) }
                assertEquals(
                    "An unchanged leaderboard keeps its native views",
                    builds,
                    activity.scorePanelBuilds,
                )
                assertEquals(
                    "An unchanged loadout keeps its text layouts",
                    content,
                    hud.contentUpdates,
                )
                assertEquals(
                    "An unchanged status avoids TextView relayout",
                    labels,
                    status.textUpdates,
                )
                session.pause(false)
                activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_W))
                assertTrue(session.input.forward)
                MainActivity::class
                    .java
                    .getDeclaredMethod("showMenu")
                    .apply { isAccessible = true }
                    .invoke(activity)
            }
            assertTrue(device.findObject(UiSelector().text("RESUME →")).waitForExists(2000))
            device.findObject(UiSelector().text("RESUME →")).click()
            val deadline = SystemClock.elapsedRealtime() + 2000
            while (
                !main { activity.hasWindowFocus() } && SystemClock.elapsedRealtime() < deadline
            ) SystemClock.sleep(20)
            main {
                activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_SPACE))
                assertFalse(
                    "A missed W release behind a modal cannot restart movement",
                    session.input.forward,
                )
                assertTrue(session.input.fire)
                activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_SPACE))
                assertFalse(session.input.fire)
            }
        } finally {
            main { activity.finish() }
        }
    }

    @Test
    fun nativeHudCooldownProgressUsesDisplayCadenceWithoutTextUpdates() {
        main {
            val hud = NativeHudView(instrumentation.targetContext)
            val snapshot =
                ArenaSnapshot(
                    tanks =
                        listOf(
                            ArenaTank(
                                id = 1,
                                name = "Rocket 🚀",
                                hp = 1,
                                cooldown = .3,
                                cooldownTotal = .34,
                                ammoUsed = 3,
                            ),
                        ),
                )
            for (rate in listOf(60, 120, 144)) {
                hud.update(snapshot, 1, null, true, false, false)
                val updates = hud.contentUpdates
                val began = System.nanoTime()
                val samples =
                    (0..rate / 10).map { hud.advance(began + (it * 1_000_000_000L / rate)) }
                assertTrue(samples.zipWithNext().all { (a, b) -> b >= a })
                assertTrue(samples.last() > samples.first())
                assertEquals(
                    "Only progress changes at the display cadence",
                    updates,
                    hud.contentUpdates,
                )
                assertTrue(hud.contentDescription.toString().contains("Rocket 🚀 (P1)"))
                assertTrue(hud.contentDescription.toString().contains("2 of 5 ammunition slots"))
            }
            hud.update(snapshot, 1, null, true, true, false)
            val began = System.nanoTime()
            assertEquals(
                "Paused progress does not drift",
                hud.advance(began),
                hud.advance(began + 1_000_000_000),
                0.0,
            )
        }
    }

    @Test
    fun transientFocusLossPausesPhysicsAndDoesNotOverrideExplicitPause() {
        val activity = launch()
        try {
            val session = main { state(activity) }
            main {
                session.publicSelected = false
                session.botCount = 0
                session.selectMode("infinity")
            }
            UiDevice.getInstance(instrumentation).findObject(UiSelector().text("PLAY  →")).click()
            main {
                activity.onWindowFocusChanged(false)
                assertTrue(session.paused)
            }
            val tick = main { session.snapshot.tick }
            SystemClock.sleep(150)
            main {
                assertEquals(
                    "A notification shade cannot leave offline combat running",
                    tick,
                    session.snapshot.tick,
                )
                activity.onWindowFocusChanged(true)
                assertFalse(session.paused)
                session.pause(true)
                activity.onWindowFocusChanged(false)
                activity.onWindowFocusChanged(true)
                assertTrue("An explicit pause remains paused after focus returns", session.paused)
            }
        } finally {
            main { activity.finish() }
        }
    }

    private fun screenshot(name: String) {
        val output = File(instrumentation.targetContext.cacheDir, "ui-polish").apply { mkdirs() }
        val bitmap = instrumentation.uiAutomation.takeScreenshot() ?: return
        File(output, "$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        bitmap.recycle()
    }
    @Test
    fun freshNamesReservedRepairP2AndPassiveNoticeRemainStable() {
        val activity = launch()
        val device = UiDevice.getInstance(instrumentation)
        fun field(instance: Any, name: String): Any? = instance.javaClass.getDeclaredField(name).run { isAccessible = true; get(instance) }
        fun eventually(message: String, condition: () -> Boolean) {
            val deadline = SystemClock.elapsedRealtime() + 20000
            while (SystemClock.elapsedRealtime() < deadline) {
                if (main(condition)) return
                SystemClock.sleep(30)
            }
            fail(message)
        }
        @Suppress("UNCHECKED_CAST")
        fun names() = field(activity, "callsignFields") as Array<android.widget.EditText?>
        @Suppress("UNCHECKED_CAST")
        fun feedback() = field(activity, "feedback") as Array<android.widget.TextView?>
        fun y(view: View): Int { val point = IntArray(2); view.getLocationOnScreen(point); return point[1] }
        val errors = mutableListOf<String>()
        try {
            val session = main { state(activity) }
            main { session.notifyError = { errors.add(it) } }
            eventually("Both fresh seats must receive claimed server defaults") { !session.automaticNamePending(0) && !session.automaticNamePending(1) }
            val initial = main { session.callsign to session.localCallsign }
            assertTrue(Regex("pilot#[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}").matches(initial.first))
            assertTrue(Regex("pilot#[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}").matches(initial.second))
            assertNotEquals(initial.first, initial.second)
            main {
                session.localSelected = true
                session.save()
                session.changed(true)
            }
            instrumentation.waitForIdleSync()
            val secondKey = main { session.store.selected(session.server, 1)!!.key }
            val secondWasPending = main { session.store.selected(session.server, 1)!!.registrationPending }
            val layoutBefore = main { y(names()[1]!!) to feedback()[0]!!.height }
            main { names()[0]!!.requestFocus(); names()[0]!!.setText("Bot RUST") }
            instrumentation.waitForIdleSync()
            SystemClock.sleep(150)
            assertTrue(device.takeScreenshot(File(instrumentation.targetContext.getExternalFilesDir(null), "identity-native-reserved.png")))
            main {
                assertTrue(feedback()[0]!!.text.toString().contains("reserved"))
                assertFalse(feedback()[0]!!.text.toString().contains("Import"))
                assertEquals(layoutBefore.first, y(names()[1]!!))
                assertEquals(layoutBefore.second, feedback()[0]!!.height)
                val spans = (feedback()[0]!!.text as android.text.Spanned).getSpans(0, feedback()[0]!!.length(), android.text.style.ClickableSpan::class.java)
                assertEquals(1, spans.size)
                spans.single().onClick(feedback()[0]!!)
                assertFalse(com.leqra.core.Callsigns.botReserved(session.callsign))
            }
            eventually("Generate repair must complete without a stale blur overwriting it") { !session.automaticNamePending(0) }
            main {
                assertTrue(errors.isEmpty())
                assertEquals(layoutBefore.first, y(names()[1]!!))
                names()[1]!!.requestFocus(); names()[1]!!.setText("bOt WING")
                val spans = (feedback()[1]!!.text as android.text.Spanned).getSpans(0, feedback()[1]!!.length(), android.text.style.ClickableSpan::class.java)
                spans.single().onClick(feedback()[1]!!)
            }
            eventually("P2 gets an independent repaired name") { !session.automaticNamePending(1) }
            main {
                assertEquals(secondKey, session.store.selected(session.server, 1)!!.key)
                assertNotEquals(session.store.selected(session.server, 0)!!.key, secondKey)
                assertEquals(secondWasPending, session.store.selected(session.server, 1)!!.registrationPending)
                session.publicSelected = true
                session.play()
            }
            eventually("Public entry with both generated accounts must succeed") { session.screen == Screen.PLAYING && session.localID2 != null && session.snapshot.tanks.any { it.id == session.localID2 } }
            main {
                assertFalse(session.store.selected(session.server, 1)!!.registrationPending)
                assertTrue(session.store.pending(session.server, 1).none { it.purpose == "registration" })
                val status = session.status
                val packet = session.snapshot.copy(tick = session.snapshot.tick + 2, godlikeSpawns = listOf(com.leqra.core.GodlikeSpawn(2000000, 1, "Bot 999 - Godlike")))
                GameSession::class.java.getDeclaredMethod("networkEvent", com.leqra.android.network.NetworkEvent::class.java, Boolean::class.javaPrimitiveType).run {
                    isAccessible = true
                    invoke(session, com.leqra.android.network.NetworkEvent.State(packet), true)
                }
                assertEquals(status, session.status)
                assertFalse(session.paused)
                assertEquals("Bot 999 - Godlike spawned nearby. Watch out!", session.encounterNotice)
                assertTrue(errors.isEmpty())
            }
            eventually("The passive notice reaches Canvas without opening an error") {
                (field(activity, "arena") as com.leqra.android.render.NativeArenaView).encounterNotice != null
            }
            SystemClock.sleep(250)
            val image = File(instrumentation.targetContext.getExternalFilesDir(null), "identity-native-warning.png")
            assertTrue(device.takeScreenshot(image))
            main { session.leave() }
        } finally { main { activity.finish() } }
    }

    @Test
    fun roomModeSwitchKeepsReadyCardPlayAndSharedControlsFixedInBothOrientations() {
        val activity = launch()
        val device = UiDevice.getInstance(instrumentation)
        fun field(name: String): Any? = MainActivity::class.java.getDeclaredField(name).run { isAccessible = true; get(activity) }
        fun eventually(message: String, condition: () -> Boolean) {
            val deadline = SystemClock.elapsedRealtime() + 20000
            while (SystemClock.elapsedRealtime() < deadline) {
                if (main(condition)) return
                SystemClock.sleep(30)
            }
            fail(message)
        }
        data class Bounds(val x: Int, val y: Int, val width: Int, val height: Int)
        data class Layout(val card: Bounds, val play: Bounds, val shared: Set<String>)
        fun bounds(view: View): Bounds { val point = IntArray(2); view.getLocationOnScreen(point); return Bounds(point[0], point[1], view.width, view.height) }
        fun buttons(view: View): List<android.widget.Button> = if (view is android.widget.Button) listOf(view)
            else if (view is android.view.ViewGroup) (0 until view.childCount).flatMap { buttons(view.getChildAt(it)) } else emptyList()
        val report = StringBuilder()
        val shared = setOf("COPY INVITE LINK ↗", "Join another room ↗", "LEAVE ROOM", "FIND ONLINE BATTLE")
        fun capture(label: String): Layout {
            eventually("Ready-room layout did not settle") {
                val scroll = field("readyScroll") as? android.widget.ScrollView
                scroll != null && scroll.isLaidOut && !scroll.isLayoutRequested
            }
            SystemClock.sleep(180)
            val layout = main {
                val scroll = field("readyScroll") as android.widget.ScrollView
                scroll.scrollTo(0, 0)
                val holder = scroll.getChildAt(0) as android.view.ViewGroup
                val card = holder.getChildAt(0)
                Layout(bounds(card), bounds(field("readyPlay") as View), buttons(card).filter { it.visibility == View.VISIBLE && it.text.toString() in shared }.map { it.text.toString() }.toSet())
            }
            report.appendLine("$label $layout")
            device.takeScreenshot(File(instrumentation.targetContext.getExternalFilesDir(null), "android-room-$label.png"))
            return layout
        }
        try {
            val session = main { state(activity) }
            main {
                session.publicSelected = false
                session.localSelected = false
                session.botCount = 0
                session.selectMode("elimination")
                session.share()
            }
            eventually("Published native room did not reach its lobby") { session.room != null && session.network.connected && session.screen == Screen.READY }
            for (orientation in listOf(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE)) {
                val name = if (orientation == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) "portrait" else "landscape"
                main { activity.requestedOrientation = orientation; session.changeRules(com.leqra.core.RoomRules.localDefaults("elimination")) }
                eventually("Elimination lobby orientation did not settle") { activity.resources.configuration.orientation == if (orientation == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) android.content.res.Configuration.ORIENTATION_PORTRAIT else android.content.res.Configuration.ORIENTATION_LANDSCAPE }
                SystemClock.sleep(500) // Let the system's rotation surface animation finish before screenshots.
                eventually("Room did not select Elimination") { session.room?.optJSONObject("rules")?.optBoolean("infinity") == false }
                val before = capture("$name-elimination")
                main { session.changeRules(com.leqra.core.RoomRules.localDefaults("infinity")) }
                eventually("Room did not select room Infinity") { session.room?.optJSONObject("rules")?.optBoolean("infinity") == true && !session.publicSelected }
                val infinity = capture("$name-infinity")
                main { session.changeRules(com.leqra.core.RoomRules.localDefaults("elimination")) }
                eventually("Room did not return to Elimination") { session.room?.optJSONObject("rules")?.optBoolean("infinity") == false }
                val restored = capture("$name-restored")
                assertEquals("$name common room actions", shared, before.shared)
                assertEquals("$name Infinity must keep every common action", shared, infinity.shared)
                assertEquals("$name restored must keep every common action", shared, restored.shared)
                assertEquals("$name ready card moved/resized on room-mode switch: $report", before.card, infinity.card)
                assertEquals("$name Play moved/resized on room-mode switch: $report", before.play, infinity.play)
                assertEquals(before.card, restored.card)
                assertEquals(before.play, restored.play)
            }
            main { session.leave() }
        } finally {
            File(instrumentation.targetContext.getExternalFilesDir(null), "android-room-bounds.txt").writeText(report.toString())
            main { activity.finish() }
        }
    }

}
