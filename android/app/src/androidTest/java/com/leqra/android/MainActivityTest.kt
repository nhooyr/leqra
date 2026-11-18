package com.leqra.android

import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.net.Uri
import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiSelector
import com.leqra.core.ArenaSnapshot
import com.leqra.core.ArenaTank
import com.leqra.core.GameInput
import com.leqra.core.ArenaResult
import com.leqra.core.RoomRules
import android.widget.TextView
import android.view.ViewGroup
import android.app.AlertDialog
import com.leqra.android.render.NativeArenaView
import java.io.File
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MainActivityTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val testServer = InstrumentationRegistry.getArguments().getString("server")
    private val server = testServer ?: "http://10.0.2.2:8080"

    private fun launch(showTour: Boolean = false): MainActivity {
        // Each launch pairs fresh name preferences with fresh keys. Keeping a prior
        // account while clearing only its callsign cannot represent first install.
        val accountFile = File(instrumentation.targetContext.noBackupFilesDir, "accounts.v1")
        accountFile.delete()
        File(accountFile.path + ".bak").delete()
        instrumentation.targetContext
            .getSharedPreferences("leqra-settings", 0)
            .edit()
            .clear()
            .putString("server", server)
            .putBoolean("publicSelected", false)
            .putString("mode", "infinity")
            .putBoolean("muted", true)
            .putBoolean(QUICK_TOUR_SEEN, !showTour)
            .apply {
                if (testServer == null) {
                    putString("callsign", "Local Pilot")
                    putString("localCallsign", "Local Wing")
                    putBoolean("autoPending0", false)
                    putBoolean("autoPending1", false)
                }
            }
            .commit()
        val activity = startActivity()
        val education =
            UiDevice.getInstance(instrumentation).findObject(UiSelector().text("Got it"))
        if (education.waitForExists(500)) education.click()
        await("The expected window handles input") {
            if (showTour) quickTour(activity)?.window?.decorView?.hasWindowFocus() == true
            else activity.hasWindowFocus()
        }
        val namesDeadline = SystemClock.elapsedRealtime() + 15000
        while (main { state(activity).automaticNamePending(0) || state(activity).automaticNamePending(1) } &&
            SystemClock.elapsedRealtime() < namesDeadline) SystemClock.sleep(30)
        assertFalse("Fresh names settle before interacting with the room", main {
            state(activity).automaticNamePending(0) || state(activity).automaticNamePending(1)
        })
        main { activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT }
        val orientationDeadline = SystemClock.elapsedRealtime() + 5000
        while (main { activity.resources.configuration.orientation } != android.content.res.Configuration.ORIENTATION_PORTRAIT &&
            SystemClock.elapsedRealtime() < orientationDeadline) SystemClock.sleep(30)
        return activity
    }

    private fun startActivity(invite: Uri? = null): MainActivity {
        val intent =
            Intent(instrumentation.targetContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        if (invite != null) intent.setAction(Intent.ACTION_VIEW).setData(invite)
        // The arena animates continuously. Watch Activity creation without assuming queue idleness.
        val monitor = instrumentation.addMonitor(MainActivity::class.java.name, null, false)
        return try {
            instrumentation.targetContext.startActivity(intent)
            monitor.waitForActivityWithTimeout(10000) as? MainActivity
                ?: throw AssertionError("MainActivity did not launch")
        } finally { instrumentation.removeMonitor(monitor) }
    }

    private fun quickTour(activity: MainActivity): QuickTour? =
        MainActivity::class.java.getDeclaredField("quickTourDialog").run {
            isAccessible = true
            get(activity) as? QuickTour
        }

    private fun await(message: String, condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 5000
        while (!main(condition) && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(20)
        assertTrue(message, main(condition))
    }

    private fun descendants(view: View): List<View> =
        listOf(view) + if (view is ViewGroup)
            (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) }
        else emptyList()

    @Test
    fun spectatorInvitePrefillsTheConfirmationPanelWithoutJoining() {
        val code = "Friday battle 🎮"
        val invite = Uri.parse("https://leqra.com").buildUpon()
            .appendQueryParameter("room", code).appendQueryParameter("spectate", "1").build()
        val activity = startActivity(invite)
        try {
            await("Invite opens a prefilled Watch confirmation") {
                val dialog = MainActivity::class.java.getDeclaredField("dialog").run {
                    isAccessible = true
                    get(activity) as? AlertDialog
                }
                val window = dialog?.window ?: return@await false
                val texts = descendants(window.decorView).filterIsInstance<TextView>().map { it.text.toString() }
                code in texts && "WATCH →" in texts
            }
            main {
                assertNull(state(activity).roomCode)
                assertFalse(state(activity).network.connected)
            }
        } finally { main { activity.finish() } }
    }

    @Test
    fun quickTourOpensOnceAndCanBeReplayedFromControls() {
        fun texts(root: View) = descendants(root).filterIsInstance<TextView>()
        fun click(root: View, title: String) =
            texts(root).single { it.text.toString() == title }.performClick()
        fun backgroundAnimating(activity: MainActivity): Boolean {
            val view = MainActivity::class.java.getDeclaredField("arena").apply { isAccessible = true }.get(activity)
            return NativeArenaView::class.java.getDeclaredField("running").apply { isAccessible = true }.getBoolean(view)
        }
        fun verifyTour(activity: MainActivity) {
            val window = main { quickTour(activity)!!.window!! }
            val root = main { window.decorView }
            val arena = main { descendants(root).filterIsInstance<NativeArenaView>().single() }
            val hardware = Regex("\\b(keyboard|mouse|gamepad|keys?)\\b", RegexOption.IGNORE_CASE)
            val instructions = listOf(
                "Drag the left stick to drive. Touch near your tank to aim without moving.",
                "Hold the right Fire button to shoot a round.",
                "Destroy the stationary tank to score a point.",
            )
            fun point(name: String): Float = NativeArenaView::class.java.getDeclaredField(name).run {
                isAccessible = true
                getFloat(arena) * arena.resources.displayMetrics.density
            }
            fun touch(action: Int, x: Float, y: Float) {
                val now = SystemClock.uptimeMillis()
                val event = MotionEvent.obtain(now, now, action, x, y, 0)
                try { assertTrue(arena.onTouchEvent(event)) } finally { event.recycle() }
            }
            fun fire() {
                touch(MotionEvent.ACTION_DOWN, point("fireX"), point("fireY"))
                touch(MotionEvent.ACTION_UP, point("fireX"), point("fireY"))
            }
            fun tankImages() = NativeArenaView::class.java.getDeclaredField("snapshot").run {
                isAccessible = true
                (get(arena) as ArenaSnapshot).tanks
            }
            for ((index, page) in listOf("Drive and aim", "Fire", "Score a point").withIndex()) {
                val button = main {
                    val labels = texts(root).map { it.text.toString() }
                    assertTrue(labels.contains("Quick tour"))
                    assertTrue(labels.contains(page))
                    assertTrue(labels.contains("${index + 1} / 3"))
                    assertTrue(labels.contains(instructions[index]))
                    assertFalse("$page is a touch-only tour page", labels.any(hardware::containsMatchIn))
                    texts(root).single { it.text.toString() == if (index == 2) "DONE" else "NEXT" }
                }
                await("The arena renders for $page") { arena.isShown && arena.renderedFrames > 0 }
                main {
                    assertFalse("The covered arena has no running frame loop", backgroundAnimating(activity))
                    assertTrue("The practice dialog requests the gameplay display rate", window.attributes.preferredRefreshRate > 30f)
                    if (android.os.Build.VERSION.SDK_INT >= 35)
                        assertEquals(window.attributes.preferredRefreshRate, arena.requestedFrameRate, 0f)
                    assertFalse(arena.showTankLabels)
                    assertEquals(index > 0, arena.showFireControl)
                    assertFalse("$page needs practice to continue", button.isEnabled)
                    when (index) {
                        0 -> {
                            touch(MotionEvent.ACTION_DOWN, point("stickX"), point("stickY"))
                            touch(MotionEvent.ACTION_MOVE, point("stickX"), point("stickY") + 28f * arena.resources.displayMetrics.density)
                        }
                        1 -> fire()
                        2 -> assertTrue(texts(root).any { it.text == "score: 0" && it.isShown })
                    }
                }
                if (index == 2) {
                    await("The stationary target appears in the practice arena") { tankImages().size == 2 }
                    val desiredAngle = main {
                        val (pilot, target) = tankImages()
                        val angle = atan2(target.y - pilot.y, target.x - pilot.x)
                        val reach = 28 * arena.resources.displayMetrics.density
                        val x = point("aimTankX") + (cos(angle) * reach).toFloat()
                        val y = point("aimTankY") + (sin(angle) * reach).toFloat()
                        touch(MotionEvent.ACTION_DOWN, x, y)
                        touch(MotionEvent.ACTION_UP, x, y)
                        angle
                    }
                    await("Touch aims the tank at the target") {
                        abs(com.leqra.core.TankMovement.angleDelta(tankImages().first().angle, desiredAngle)) < .05
                    }
                    main { fire() }
                }
                await("Actual practice unlocks the button for $page") { button.isEnabled }
                if (index == 0) main { touch(MotionEvent.ACTION_UP, point("stickX"), point("stickY")) }
                if (index == 2) main { assertTrue(texts(root).any { it.text == "score: 1" && it.isShown }) }
                main { assertTrue(button.performClick()) }
            }
        }

        val fresh = launch(showTour = true)
        try {
            verifyTour(fresh)
            await("Completing the tour resumes the room arena cadence") { quickTour(fresh) == null && backgroundAnimating(fresh) }
        } finally { main { fresh.finish() } }

        val returning = startActivity()
        try {
            await("The room is immediately interactive on relaunch") { returning.hasWindowFocus() }
            val controls = main {
                assertNull(quickTour(returning))
                state(returning).selectMode("ctf")
                state(returning).localSelected = true
                MainActivity::class.java.getDeclaredMethod("showControls").apply { isAccessible = true }.invoke(returning)
                val controls = MainActivity::class.java.getDeclaredField("dialog").run {
                    isAccessible = true
                    get(returning) as AlertDialog
                }
                assertTrue(click(controls.window!!.decorView, "QUICK TOUR"))
                controls
            }
            verifyTour(returning)
            await("Completing a replay returns to Controls") { quickTour(returning) == null && controls.isShowing && backgroundAnimating(returning) }
        } finally { main { returning.finish() } }
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

    private fun awaitPlaying(activity: MainActivity) {
        val deadline = SystemClock.elapsedRealtime() + 5000
        while (main { state(activity).screen } != Screen.PLAYING && SystemClock.elapsedRealtime() < deadline)
            SystemClock.sleep(20)
        assertEquals(main { "Play: ${state(activity).status}, name=${state(activity).callsign}" }, Screen.PLAYING, main { state(activity).screen })
    }

    private fun tap(view: androidx.test.uiautomator.UiObject) {
        val bounds = view.visibleBounds
        val now = SystemClock.uptimeMillis()
        for ((action, time) in listOf(android.view.MotionEvent.ACTION_DOWN to now, android.view.MotionEvent.ACTION_UP to now + 70)) {
            val event = android.view.MotionEvent.obtain(now, time, action, bounds.exactCenterX(), bounds.exactCenterY(), 0)
            try { instrumentation.sendPointerSync(event) } finally { event.recycle() }
        }
    }

    @Test
    fun sustainedPairedGameplaySurvivesModesRotationsAndBackgrounds() {
        val requestedSeconds = InstrumentationRegistry.getArguments().getString("soakSeconds")?.toIntOrNull()
        org.junit.Assume.assumeTrue("Set soakSeconds for the extended gameplay audit", requestedSeconds != null && requestedSeconds > 0)
        val seconds = requestedSeconds!!
        val activity = launch()
        val publicSoak = InstrumentationRegistry.getArguments().getString("publicSoak") == "true"
        val online = publicSoak || InstrumentationRegistry.getArguments().getString("onlineSoak") == "true"
        val reports = File(instrumentation.targetContext.cacheDir, "gameplay-soak.txt")
        var iterations = 0
        val until = SystemClock.elapsedRealtime() + seconds * 1000L
        try {
            val session = main { state(activity) }
            main {
                val reportError = session.notifyError
                session.notifyError = { message -> reports.appendText("error cycle=$iterations $message\n"); reportError(message) }
                for ((label, client) in listOf("room" to session.network, "arena" to session.arenaNetwork)) {
                    val eventField = client.javaClass.getDeclaredField("onEvent").apply { isAccessible = true }
                    @Suppress("UNCHECKED_CAST") val receive = eventField.get(client) as (com.leqra.android.network.NetworkEvent) -> Unit
                    var previousPhase = ""
                    eventField.set(client, { event: com.leqra.android.network.NetworkEvent ->
                        val detail = when (event) {
                            is com.leqra.android.network.NetworkEvent.Error -> "error code=${event.code} seat=${event.seat} terminal=${event.terminal} ${event.message}"
                            is com.leqra.android.network.NetworkEvent.Reconnecting -> "retry=${event.attempt}"
                            is com.leqra.android.network.NetworkEvent.Welcome -> "welcome resumed=${event.welcome.resumed} connection=${client.connectionGeneration}"
                            is com.leqra.android.network.NetworkEvent.Packet -> if (event.packet.optString("type") in listOf("room", "error", "room_offline")) "packet type=${event.packet.optString("type")} code=${event.packet.optString("code")} action=${event.packet.optString("action")} seat=${event.packet.optInt("seat", -1)} phase=${event.packet.optString("phase")} active=${event.packet.optBoolean("infinityActive")}" else ""
                            is com.leqra.android.network.NetworkEvent.State -> "${event.snapshot.generation}:${event.snapshot.phase}".let { phase -> if (phase == previousPhase) "" else { previousPhase = phase; "state=$phase" } }
                            else -> ""
                        }
                        if (detail.isNotEmpty()) reports.appendText("event cycle=$iterations $label $detail\n")
                        receive(event)
                    })
                }
            }
            for (mode in (if (publicSoak) listOf("infinity") else GameSession.modes.keys).cycle()) {
                if (SystemClock.elapsedRealtime() >= until) break
                main {
                    session.leave(); session.togglePublic(false)
                    session.localSelected = true; session.botCount = 2
                    session.selectMode(mode); session.togglePublic(publicSoak)
                    if (online && !publicSoak) session.share() else session.play()
                    activity.requestedOrientation = if (iterations % 2 == 0) ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                }
                if (online && !publicSoak) {
                    val deadline = SystemClock.elapsedRealtime() + 15000
                    while (!main { session.network.connected && session.room != null } && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(20)
                    main { assertNotNull(session.room); session.play() }
                }
                awaitPlaying(activity)
                repeat(10) { pass ->
                    if (SystemClock.elapsedRealtime() >= until) return@repeat
                    main {
                        session.input = GameInput(forward = true, right = pass % 2 == 0, fire = true, touchAim = false)
                        session.input2 = GameInput(reverse = true, left = pass % 2 != 0, fire = true, touchAim = false)
                    }
                    SystemClock.sleep(1000)
                    main {
                        assertTrue(session.snapshot.tanks.all { it.x.isFinite() && it.y.isFinite() })
                        if (session.snapshot.phase == "matchOver" || session.snapshot.result != null) {
                            MainActivity::class.java.getDeclaredMethod("dismissDialog").apply { isAccessible = true }.invoke(activity)
                            session.restartMatch()
                        }
                    }
                }
                val tick = main { session.pause(true); session.snapshot.tick }
                SystemClock.sleep(100)
                main {
                    if (!online) assertEquals(tick, session.snapshot.tick)
                    assertFalse(session.input.fire); assertFalse(session.input2.fire)
                }
                val device = UiDevice.getInstance(instrumentation)
                device.executeShellCommand("am start -W -a android.intent.action.MAIN -c android.intent.category.HOME")
                val awayUntil = SystemClock.elapsedRealtime() + 5000
                while (main { activity.hasWindowFocus() } && SystemClock.elapsedRealtime() < awayUntil) SystemClock.sleep(20)
                assertFalse("Home removes the app's focus", main { activity.hasWindowFocus() })
                device.executeShellCommand("am start -W --activity-reorder-to-front -n ${activity.packageName}/${MainActivity::class.java.name}")
                val resumeUntil = SystemClock.elapsedRealtime() + 15000
                while (!main { activity.hasWindowFocus() } && SystemClock.elapsedRealtime() < resumeUntil) {
                    // The online match can finish while Home is showing; its result dialog
                    // owns focus until dismissed, even though the Activity resumed normally.
                    main { MainActivity::class.java.getDeclaredMethod("dismissDialog").apply { isAccessible = true }.invoke(activity) }
                    SystemClock.sleep(20)
                }
                if (!main { activity.hasWindowFocus() }) {
                    reports.appendText("focus-timeout cycle=$iterations visiblePackage=${device.currentPackageName}\n")
                    screenshot("online-soak-focus-failure")
                }
                main { assertTrue("Activity regains focus after Home", activity.hasWindowFocus()); session.pause(false) }
                if (online) {
                    val deadline = SystemClock.elapsedRealtime() + 15000
                    fun connected() = (publicSoak || session.network.connected) && (!session.infinity || session.arenaNetwork.connected)
                    while (!main { connected() } && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(20)
                    val connection = main { "mode=$mode public=$publicSoak online=${session.online} screen=${session.screen} infinity=${session.infinity} room=${session.network.connected} arena=${session.arenaNetwork.connected} phase=${session.snapshot.phase} roomPhase=${session.room?.optString("phase")} status=${session.status}" }
                    reports.appendText("resume $iterations $connection\n")
                    if (!main { connected() }) screenshot("online-soak-reconnect-failure")
                    main { assertTrue("Online sockets reconnect: $connection", connected()) }
                }
                reports.appendText("$iterations $mode tick=$tick frame=${main { (MainActivity::class.java.getDeclaredField("arena").apply { isAccessible = true }.get(activity) as NativeArenaView).renderedFrames }}\n")
                iterations++
            }
        } finally { main { activity.finish() } }
    }

    private fun <T> Collection<T>.cycle() = sequence { while (true) yieldAll(this@cycle) }

    @Test
    fun showcaseOnlyExitsWithEscapeOrAfterLeavingAndReturningToApp() {
        val activity = launch()
        fun preview() = MainActivity::class.java.getDeclaredField("showcaseDialog").run { isAccessible = true; get(activity) as? android.app.Dialog }
        fun showcase(): ShowcaseView? {
            fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
            return preview()?.window?.decorView?.let { descendants(it).filterIsInstance<ShowcaseView>().singleOrNull() }
        }
        fun controls() = MainActivity::class.java.getDeclaredField("dialog").run { isAccessible = true; get(activity) as? AlertDialog }
        fun invoke(name: String) = MainActivity::class.java.getDeclaredMethod(name).apply { isAccessible = true }.invoke(activity)
        fun openShowcase() = main {
            val button = descendants(controls()!!.window!!.decorView).filterIsInstance<android.widget.Button>()
                .single { it.text == "SHOWCASE" }
            assertTrue(button.performClick())
        }
        fun await(message: String, condition: () -> Boolean) {
            val until = SystemClock.elapsedRealtime() + 5000
            while (!main(condition) && SystemClock.elapsedRealtime() < until) SystemClock.sleep(20)
            assertTrue(message, main(condition))
        }
        val device = UiDevice.getInstance(instrumentation)
        try {
            val session = main { state(activity) }
            main { session.localSelected = false; session.botCount = 0; session.play(); invoke("showControls") }
            val tick = main { session.snapshot.tick }
            val key = main { session.store.selected(session.server, 0)?.key }
            openShowcase()
            await("Showcase opens", { preview()?.isShowing == true })
            await("Portrait showcase is drawn", { showcase()?.let { it.height > it.width && it.scene.snapshot.tanks.size == 10 && it.arena.renderedFrames > 0 } == true })
            val immersiveEducation = device.findObject(UiSelector().textMatches("(?i)got it"))
            if (immersiveEducation.waitForExists(2500)) immersiveEducation.click()
            await("Showcase receives keyboard input", { preview()?.window?.decorView?.hasWindowFocus() == true })
            main {
                assertTrue(session.paused); assertEquals(tick, session.snapshot.tick)
                val shown = showcase()!!
                assertEquals(10, shown.scene.snapshot.tanks.size)
                assertEquals(4, shown.scene.snapshot.pickups.size)
                assertTrue(shown.arena.showControls)
                val pauseButton = (0 until shown.header.childCount)
                    .map(shown.header::getChildAt).single { it.contentDescription == "Pause game" }
                assertTrue(pauseButton.isEnabled)
                assertTrue(shown.loadout.contentDescription.toString().contains("aqsnow (P1)"))
            }
            device.pressBack()
            SystemClock.sleep(150)
            assertTrue("System Back cannot dismiss showcase", main { preview()?.isShowing == true })
            device.click(device.displayWidth / 2, device.displayHeight / 2)
            device.swipe(device.displayWidth / 3, device.displayHeight / 2, device.displayWidth * 2 / 3, device.displayHeight / 2, 10)
            assertTrue("Touch cannot dismiss showcase", main { preview()?.isShowing == true })
            screenshot("showcase-portrait")
            instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_ESCAPE)
            await("Escape dismisses showcase", { preview() == null })
            main { assertTrue(controls()?.isShowing == true); assertTrue(session.paused); assertEquals(key, session.store.selected(session.server, 0)?.key) }
            openShowcase()
            await("Showcase reopens", { preview()?.isShowing == true })
            main { activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE }
            await("Landscape showcase fills its rotated window", {
                val shown = showcase()
                val decor = preview()?.window?.decorView
                shown != null && decor != null && decor.width > decor.height && shown.width > shown.height &&
                    shown.scene.snapshot.tanks.size == 8 && shown.arena.renderedFrames > 0
            })
            SystemClock.sleep(100)
            screenshot("showcase-landscape")
            device.executeShellCommand("am start -W -a android.intent.action.MAIN -c android.intent.category.HOME")
            device.executeShellCommand("am start -W --activity-reorder-to-front -n ${activity.packageName}/${MainActivity::class.java.name}")
            await("Returning from another app dismisses showcase", { preview() == null })
            main {
                assertTrue(controls()?.isShowing == true)
                assertTrue(session.paused); assertEquals(tick, session.snapshot.tick)
                assertEquals(key, session.store.selected(session.server, 0)?.key)
                assertFalse(session.online)
            }
        } finally { main { preview()?.dismiss(); invoke("dismissDialog"); activity.finish() } }
    }

    @Test
    fun publicInfinityRoomSettingsHidePrivateGameConfiguration() {
        val activity = launch()
        fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
        fun settings(): List<View> {
            val panel = android.widget.LinearLayout(activity)
            MainActivity::class.java.getDeclaredMethod("roomSettings", android.widget.LinearLayout::class.java).apply { isAccessible = true }.invoke(activity, panel)
            return descendants(panel)
        }
        try {
            main {
                val session = state(activity)
                session.togglePublic(true)
                val public = settings()
                val texts = public.filterIsInstance<TextView>().map { it.text.toString() }
                assertEquals(1, public.filterIsInstance<android.widget.EditText>().size)
                assertTrue(texts.any { it.contains("Turn off Public Infinity") })
                assertTrue(texts.none { it in listOf("CHOOSE YOUR BATTLE", "Rules", "Teams", "Presets") })
                assertTrue(descendants(activity.window.decorView).filterIsInstance<TextView>().any { it.text.toString() == "SHARE ROOM ONLINE ↗" })
                session.togglePublic(false)
                val privateTexts = settings().filterIsInstance<TextView>().map { it.text.toString() }
                assertTrue(privateTexts.contains("CHOOSE YOUR BATTLE"))
                assertTrue(privateTexts.containsAll(listOf("Rules", "Teams", "Presets")))
            }
        } finally { main { activity.finish() } }
    }

    @Test
    fun closingControlsReturnsToThePauseMenuBeforeResumingBattle() {
        val activity = launch()
        fun invoke(name: String) = MainActivity::class.java.getDeclaredMethod(name).apply { isAccessible = true }.invoke(activity)
        fun panel() = MainActivity::class.java.getDeclaredField("dialog").run { isAccessible = true; get(activity) as? AlertDialog }
        fun button(title: String) = panel()?.window?.decorView?.let { root ->
            descendants(root).filterIsInstance<android.widget.Button>().singleOrNull { it.text.toString() == title }
        }
        try {
            main {
                state(activity).play()
                invoke("showMenu")
                assertTrue(button("Controls")?.performClick() == true)
            }
            await("The Controls panel remains the tracked modal") { button("QUICK TOUR") != null }
            main {
                assertTrue("The open Controls panel keeps the match paused", state(activity).paused)
                invoke("handleBack")
            }
            await("Closing Controls returns to the paused battle card") { button("← BACK TO THE BATTLE") != null }
            main {
                assertTrue(state(activity).paused)
                assertTrue(button("← BACK TO THE BATTLE")?.performClick() == true)
            }
            await("Resuming closes the pause menu and unpauses play") { panel() == null && !state(activity).paused }
        } finally { main { activity.finish() } }
    }

    @Test
    fun applyingRulesRefreshesTheExpandedReadyRoom() {
        val activity = launch()
        fun readyViews() = descendants(activity.window.decorView)
        fun summary() = readyViews().filterIsInstance<TextView>()
            .single { it.text.startsWith("FIRST TO ") }.text.toString()
        try {
            main {
                state(activity).changeRules(RoomRules.localDefaults("elimination"))
                assertTrue(readyViews().single { it.contentDescription == "Room settings, Collapsed" }.performClick())
                assertTrue(summary().startsWith("FIRST TO 5 WINS"))
                assertTrue(summary().contains("Friendly fire is off."))
                assertTrue(readyViews().filterIsInstance<TextView>().single { it.text.toString() == "Rules" }.performClick())

                val dialog = MainActivity::class.java.getDeclaredField("dialog").run {
                    isAccessible = true
                    get(activity) as AlertDialog
                }
                val rules = descendants(dialog.window!!.decorView)
                assertTrue(rules.single { it.contentDescription == "Increase Score target" }.performClick())
                val friendlyFire = rules.filterIsInstance<android.widget.Switch>().single { it.text.toString() == "Friendly fire" }
                friendlyFire.performClick()
                assertTrue(friendlyFire.isChecked)
                assertTrue(rules.filterIsInstance<TextView>().single { it.text.toString() == "APPLY RULES" }.performClick())

                assertTrue(summary().startsWith("FIRST TO 6 WINS"))
                assertTrue(summary().contains("Friendly fire is on."))
            }
        } finally { main { activity.finish() } }
    }

    @Test
    fun rulesPowerHelpTracksActiveModeAndEditableDraft() {
        val activity = launch()
        fun invoke(name: String) = MainActivity::class.java.getDeclaredMethod(name).apply { isAccessible = true }.invoke(activity)
        fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
        fun panelViews(): List<View> = MainActivity::class.java.getDeclaredField("dialog").run {
            isAccessible = true
            descendants((get(activity) as AlertDialog).window!!.decorView)
        }
        fun text() = panelViews().filterIsInstance<TextView>().joinToString("\n") { it.text }
        try {
            main {
                val session = state(activity)
                for (mode in listOf("infinity", "elimination", "ctf", "koth", "survival")) {
                    session.selectMode(mode)
                    invoke("showRules")
                    val boxes = panelViews().filterIsInstance<android.widget.CheckBox>().filter { it.text.toString() in PowerupHelp.kinds.map(PowerupHelp::title) }
                    val rate = panelViews().filterIsInstance<android.widget.Spinner>().singleOrNull { it.contentDescription == "POWER-UP FREQUENCY" }
                    if (mode == "infinity") {
                        assertTrue(boxes.isEmpty())
                        assertNull(rate)
                        val labels = panelViews().filterIsInstance<TextView>().map { it.text.toString() }
                        assertTrue(labels.containsAll(PowerupHelp.kinds.map(PowerupHelp::title)))
                        assertTrue(text().contains("always spawns all ten"))
                        assertTrue(text().contains("3 shots or 15 seconds"))
                        assertFalse(text().contains("arena rim"))
                    } else {
                        assertEquals(10, boxes.size)
                        assertTrue(boxes.all { it.isEnabled })
                        assertTrue(rate?.isEnabled == true)
                        assertTrue(text().contains("3 shots or 10 seconds"))
                        assertTrue(text().contains("arena rim"))
                    }
                    invoke("dismissDialog")
                }
                session.selectMode("elimination")
                invoke("showControls")
                assertFalse(text().contains("Power-ups can stack"))
                assertTrue(text().contains("Hold the right Fire button to shoot"))
                invoke("dismissDialog")
                invoke("showRules")
                panelViews().filterIsInstance<android.widget.Spinner>().single { it.contentDescription == "MAP SIZE" }.setSelection(4)
            }
            SystemClock.sleep(150)
            main {
                assertTrue(text().contains("3 shots or 15 seconds"))
                assertTrue(text().contains("no reload for 7 seconds"))
                panelViews().filterIsInstance<android.widget.CheckBox>().single { it.text.toString() == "Laser" }.performClick()
                assertTrue(text().contains("9 power-up types enabled"))
                panelViews().filterIsInstance<android.widget.Spinner>().single { it.contentDescription == "POWER-UP FREQUENCY" }.setSelection(0)
            }
            SystemClock.sleep(150)
            main { assertTrue(text().contains("Power-up spawning is off")) }
        } finally { main { invoke("dismissDialog"); activity.finish() } }
    }

    @Test
    fun onlineRoomsHaveNoChatControlsInLobbyOrGame() {
        org.junit.Assume.assumeNotNull(testServer)
        val activity = launch()
        fun show(method: String) = MainActivity::class.java.getDeclaredMethod(method).apply { isAccessible = true }.invoke(activity)
        fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
        fun checkControls(label: String) {
            main {
                val views = descendants(activity.window.decorView).toMutableList()
                (MainActivity::class.java.getDeclaredField("dialog").apply { isAccessible = true }.get(activity) as? AlertDialog)?.window?.decorView?.let { views += descendants(it) }
                assertFalse("$label has no chat entry point", views.any {
                    it.contentDescription?.toString()?.contains("chat", true) == true ||
                        it is TextView && it.text.toString().contains("chat", true)
                })
            }
        }
        try {
            val session = main { state(activity) }
            val configurations = GameSession.modes.keys.map { it to false } + ("infinity" to true)
            for ((mode, public) in configurations) {
                main {
                    show("dismissDialog"); session.leave(); session.localSelected = true
                    session.botCount = 2; session.selectMode(mode); session.togglePublic(public)
                    if (public) session.play() else session.share()
                }
                if (!public) {
                    val deadline = SystemClock.elapsedRealtime() + 15000
                    while (!main { session.network.connected && session.room != null } && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(30)
                    main { assertNotNull("$mode room", session.room); show("showMenu") }
                    checkControls("$mode lobby")
                    main { show("dismissDialog"); session.play() }
                }
                awaitPlaying(activity)
                checkControls("$mode public=$public game")
                if (public) { SystemClock.sleep(250); screenshot("native-online-without-chat") }
                main { show("showMenu") }
                checkControls("$mode public=$public pause")
                if (public) { SystemClock.sleep(250); screenshot("native-online-menu-without-chat") }
                main { show("dismissDialog"); session.leave() }
            }
            main { show("showControls") }
            main {
                val dialog = MainActivity::class.java.getDeclaredField("dialog").apply { isAccessible = true }.get(activity) as AlertDialog
                assertTrue("Hold-to-fire instructions remain in Controls", descendants(dialog.window!!.decorView).filterIsInstance<TextView>().any { it.text.contains("Hold the right Fire button") })
            }
        } finally { main { show("dismissDialog"); activity.finish() } }
    }

    @Test
    fun unlabelledNativeControlsStayClearWithFullyLoweredStick() {
        val activity=launch()
        try {
            val session=main{state(activity)}
            for(mode in listOf("infinity","elimination")) for(landscape in listOf(false,true)) {
                main {
                    session.leave();session.togglePublic(false);session.localSelected=false;session.botCount=0
                    session.selectMode(mode);session.play()
                    activity.requestedOrientation=if(landscape)ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                }
                val orientationDeadline=SystemClock.elapsedRealtime()+5000
                while(main{activity.window.decorView.width>activity.window.decorView.height}!=landscape&&SystemClock.elapsedRealtime()<orientationDeadline)SystemClock.sleep(20)
                SystemClock.sleep(500)
                main {
                    val header = MainActivity::class.java.getDeclaredField("header").run { isAccessible = true; get(activity) as ViewGroup }
                    val version = (0 until header.childCount).map { header.getChildAt(it) }.filterIsInstance<TextView>().single { it.text.toString() == "v${BuildConfig.VERSION_NAME}" }
                    val visible = android.graphics.Rect()
                    assertTrue("Header version stays visible in both orientations", version.isShown && version.getGlobalVisibleRect(visible))
                    assertEquals("Version is not clipped", version.width, visible.width())
                    val view=MainActivity::class.java.getDeclaredField("arena").run{isAccessible=true;get(activity) as NativeArenaView}
                    fun coordinate(name:String)=NativeArenaView::class.java.getDeclaredField(name).run{isAccessible=true;getFloat(view)}*view.resources.displayMetrics.density
                    val x=coordinate("stickX");val y=coordinate("stickY");val now=SystemClock.uptimeMillis()
                    for((action,dy)in listOf(android.view.MotionEvent.ACTION_DOWN to 0f,android.view.MotionEvent.ACTION_MOVE to 200f)) {
                        val event=android.view.MotionEvent.obtain(now,now,action,x,y+dy,0)
                        try{view.onTouchEvent(event)}finally{event.recycle()}
                    }
                    val knob=NativeArenaView::class.java.getDeclaredField("knobY").run{isAccessible=true;getFloat(view)}
                    assertEquals("Fully lowered stick",29f,knob,.1f)
                }
                SystemClock.sleep(150)
                screenshot("controls-$mode-${if(landscape)"landscape"else"portrait"}-held")
            }
        }finally{main{activity.finish()}}
    }

    @Test
    fun twoRegisteredGamepadsRouteAxesTriggersAndButtonsToSeparateTanks() {
        val pads = android.view.InputDevice.getDeviceIds().toList().mapNotNull(android.view.InputDevice::getDevice)
            .filter { it.name.startsWith("leqra Audit Pad") && it.sources and android.view.InputDevice.SOURCE_GAMEPAD == android.view.InputDevice.SOURCE_GAMEPAD }
            .sortedBy { it.id }
        org.junit.Assume.assumeTrue("Two virtual audit gamepads are required", pads.size == 2)
        val activity = launch()
        try {
            main {
                val session = state(activity)
                assertFalse("Connecting hardware does not automatically add P2", session.localSelected)
                session.localSelected = true; session.botCount = 0; session.play()
                fun axis(id: Int, x: Float, y: Float, trigger: Float) {
                    val pointer = android.view.MotionEvent.PointerProperties().apply { this.id = 0 }
                    val coordinates = android.view.MotionEvent.PointerCoords().apply {
                        setAxisValue(android.view.MotionEvent.AXIS_X, x); setAxisValue(android.view.MotionEvent.AXIS_Y, y)
                        setAxisValue(android.view.MotionEvent.AXIS_RTRIGGER, trigger)
                    }
                    val now = SystemClock.uptimeMillis()
                    val event = android.view.MotionEvent.obtain(now, now, android.view.MotionEvent.ACTION_MOVE, 1,
                        arrayOf(pointer), arrayOf(coordinates), 0, 0, 1f, 1f, id, 0, android.view.InputDevice.SOURCE_JOYSTICK, 0)
                    try { activity.dispatchGenericMotionEvent(event) } finally { event.recycle() }
                }
                axis(pads[0].id, .75f, -.5f, 1f)
                assertEquals(.75, session.input.stickX, 1e-6); assertEquals(-.5, session.input.stickY, 1e-6)
                assertTrue(session.input.fire); assertFalse(session.input2.fire)
                axis(pads[1].id, -.5f, .75f, 1f)
                assertEquals(-.5, session.input2.stickX, 1e-6); assertEquals(.75, session.input2.stickY, 1e-6)
                assertTrue(session.input2.fire); assertTrue(session.input.fire)
                axis(pads[0].id, 0f, 0f, 0f); axis(pads[1].id, 0f, 0f, 0f)
                val now = SystemClock.uptimeMillis()
                activity.dispatchKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BUTTON_A, 0, 0, pads[1].id, 0, 0, android.view.InputDevice.SOURCE_GAMEPAD))
                assertFalse(session.input.fire); assertTrue(session.input2.fire)
                activity.dispatchKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BUTTON_A, 0, 0, pads[1].id, 0, 0, android.view.InputDevice.SOURCE_GAMEPAD))
                assertFalse(session.input2.fire)
                activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_Q))
                assertFalse(session.input.fire); assertTrue("Keyboard still belongs to P2 beside gamepads", session.input2.fire)
                activity.dispatchKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BUTTON_A, 0, 0, pads[0].id, 0, 0, android.view.InputDevice.SOURCE_GAMEPAD))
                assertTrue("First gamepad retains P1", session.input.fire); assertTrue(session.input2.fire)
                activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_Q))
                assertTrue(session.input.fire); assertFalse(session.input2.fire)
                activity.dispatchKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BUTTON_A, 0, 0, pads[0].id, 0, 0, android.view.InputDevice.SOURCE_GAMEPAD))
                activity.onWindowFocusChanged(false)
                assertEquals(0.0, session.input.stickX, 0.0); assertEquals(0.0, session.input2.stickX, 0.0)
            }
        } finally { main { activity.finish() } }
    }

    @Test
    fun unpluggingHeldGamepadsNeutralizesBothSeatsWithoutTransferringInputs() {
        org.junit.Assume.assumeTrue("Set unplugGamepads for external uinput removal", InstrumentationRegistry.getArguments().getString("unplugGamepads") == "true")
        val pads = android.view.InputDevice.getDeviceIds().toList().mapNotNull(android.view.InputDevice::getDevice)
            .filter { it.name.startsWith("leqra Audit Pad") }.sortedBy { it.id }
        assertEquals(2, pads.size)
        val activity = launch()
        try {
            main {
                val session = state(activity)
                session.localSelected = true; session.botCount = 0; session.play()
                for (pad in pads) {
                    val pointer = android.view.MotionEvent.PointerProperties().apply { id = 0 }
                    val coordinates = android.view.MotionEvent.PointerCoords().apply {
                        setAxisValue(android.view.MotionEvent.AXIS_X, .8f); setAxisValue(android.view.MotionEvent.AXIS_RTRIGGER, 1f)
                    }
                    val now = SystemClock.uptimeMillis()
                    val event = android.view.MotionEvent.obtain(now, now, android.view.MotionEvent.ACTION_MOVE, 1,
                        arrayOf(pointer), arrayOf(coordinates), 0, 0, 1f, 1f, pad.id, 0, android.view.InputDevice.SOURCE_JOYSTICK, 0)
                    try { activity.dispatchGenericMotionEvent(event) } finally { event.recycle() }
                }
                assertTrue(session.input.fire); assertTrue(session.input2.fire)
            }
            File(instrumentation.targetContext.cacheDir, "unplug-ready").writeText("ready")
            val deadline = SystemClock.elapsedRealtime() + 30000
            while (pads.any { android.view.InputDevice.getDevice(it.id) != null } && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(20)
            assertTrue("External virtual gamepad removal occurred", pads.none { android.view.InputDevice.getDevice(it.id) != null })
            SystemClock.sleep(100)
            main {
                val session = state(activity)
                assertFalse("Removed P1 controller cannot keep firing", session.input.fire)
                assertFalse("Removed P2 controller cannot keep firing", session.input2.fire)
                assertEquals(0.0, session.input.stickX, 0.0); assertEquals(0.0, session.input2.stickX, 0.0)
            }
        } finally { main { activity.finish() } }
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
                    UiDevice.getInstance(instrumentation).findObject(UiSelector().text("PLAY"))
                assertTrue("Native Play button is present for $mode", play.waitForExists(2000))
                tap(play)
                awaitPlaying(activity)
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
    fun pairedTouchKeyboardAndMouseControlIndependentTanks() {
        val activity = launch()
        try {
            val session = main { state(activity) }
            main { session.callsign = "ABCDEFGHIJKLMNOP"; session.localCallsign = "Wide界界界界界界界界界界界界" }
            for (mode in GameSession.modes.keys) for (landscape in listOf(false, true)) {
                main {
                    session.leave(); session.localSelected = true; session.botCount = 0
                    session.selectMode(mode); session.play()
                    activity.requestedOrientation = if (landscape) ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                }
                awaitPlaying(activity)
                SystemClock.sleep(600)
                main {
                    val view = MainActivity::class.java.getDeclaredField("arena").run { isAccessible = true; get(activity) as NativeArenaView }
                    fun point(name: String) = NativeArenaView::class.java.getDeclaredField(name).run { isAccessible = true; getFloat(view) } * view.resources.displayMetrics.density
                    fun key(code: Int, down: Boolean) {
                        val now = SystemClock.uptimeMillis()
                        activity.dispatchKeyEvent(KeyEvent(now, now, if (down) KeyEvent.ACTION_DOWN else KeyEvent.ACTION_UP,
                            code, 0, 0, 0, 0, 0, android.view.InputDevice.SOURCE_KEYBOARD))
                    }
                    fun touch(action: Int) {
                        val now = SystemClock.uptimeMillis()
                        android.view.MotionEvent.obtain(now, now, action, point("fireX"), point("fireY"), 0).let { view.onTouchEvent(it); it.recycle() }
                    }
                    var mouseDirection = 1.0
                    fun mouse(action: Int, buttons: Int = 0) {
                        val properties = android.view.MotionEvent.PointerProperties().apply { id = 0; toolType = android.view.MotionEvent.TOOL_TYPE_MOUSE }
                        val location = IntArray(2).also(view::getLocationInWindow)
                        val distance = 35 * view.resources.displayMetrics.density
                        mouseDirection = if (point("mouseTankX") + distance < view.width) 1.0 else -1.0
                        val coordinates = android.view.MotionEvent.PointerCoords().apply { x = location[0] + point("mouseTankX") + (distance * mouseDirection).toFloat(); y = location[1] + point("mouseTankY") }
                        val now = SystemClock.uptimeMillis()
                        val event = android.view.MotionEvent.obtain(now, now, action, 1, arrayOf(properties), arrayOf(coordinates), 0, buttons, 1f, 1f, 0, 0, android.view.InputDevice.SOURCE_MOUSE, 0)
                        try {
                            if (action == android.view.MotionEvent.ACTION_HOVER_MOVE) activity.dispatchGenericMotionEvent(event) else activity.dispatchTouchEvent(event)
                        } finally { event.recycle() }
                    }
                    touch(android.view.MotionEvent.ACTION_DOWN)
                    assertTrue("Touch belongs to P1", session.input.fire); assertFalse(session.input2.fire)
                    key(KeyEvent.KEYCODE_W, true); key(KeyEvent.KEYCODE_Q, true)
                    assertFalse(session.input.forward); assertTrue(session.input2.forward); assertTrue(session.input2.fire)
                    key(KeyEvent.KEYCODE_Q, false)
                    mouse(android.view.MotionEvent.ACTION_HOVER_MOVE)
                    assertTrue(session.input2.aimOnly); assertFalse("Mouse aim preserves held keyboard throttle", session.input2.snapAim)
                    assertTrue(session.input2.forward); assertEquals(mouseDirection, session.input2.stickX, .001)
                    key(KeyEvent.KEYCODE_W, false)
                    mouse(android.view.MotionEvent.ACTION_DOWN, android.view.MotionEvent.BUTTON_PRIMARY)
                    assertTrue("Stationary mouse aim is exact", session.input2.snapAim)
                    assertTrue("Mouse fire belongs to P2", session.input2.fire); assertTrue("Mouse cannot release P1 touch", session.input.fire)
                    mouse(android.view.MotionEvent.ACTION_UP)
                    assertFalse(session.input2.fire); assertTrue(session.input.fire)
                    touch(android.view.MotionEvent.ACTION_UP)
                    assertFalse(session.input.fire)
                    mouse(android.view.MotionEvent.ACTION_DOWN, android.view.MotionEvent.BUTTON_PRIMARY)
                    touch(android.view.MotionEvent.ACTION_DOWN)
                    key(KeyEvent.KEYCODE_W, true)
                    val devices = MainActivity::class.java.getDeclaredField("controllerDevices").run { isAccessible = true; get(activity) as android.hardware.input.InputManager.InputDeviceListener }
                    devices.onInputDeviceRemoved(-1)
                    assertTrue("Disconnecting external input keeps P1 touch held", session.input.fire)
                    assertFalse("Disconnected keyboard cannot keep P2 moving", session.input2.forward)
                    assertFalse("Disconnected mouse cannot keep P2 firing", session.input2.fire)
                    touch(android.view.MotionEvent.ACTION_UP)
                    mouse(android.view.MotionEvent.ACTION_DOWN, android.view.MotionEvent.BUTTON_PRIMARY)
                    activity.onWindowFocusChanged(false)
                    assertFalse(session.input.fire); assertFalse(session.input2.fire)
                    activity.onWindowFocusChanged(true)
                    for ((id, power) in listOf(session.localID to "rapid", session.localID2 to "cannon")) {
                        session.authoritativeSnapshot.tanks.firstOrNull { it.id == id }?.let { tank ->
                            com.leqra.core.PracticeArena.applyPower(tank, power)
                            com.leqra.core.PracticeArena.applyPower(tank, "shield")
                            com.leqra.core.PracticeArena.applyPower(tank, "speed")
                            com.leqra.core.PracticeArena.applyPower(tank, if (id == session.localID2) "starman" else "ghost")
                            tank.spawnProtected = false; tank.invulnerable = 0.0
                        }
                    }
                }
                SystemClock.sleep(200)
                screenshot("p2-input-$mode-${if (landscape) "landscape" else "portrait"}")
            }
        } finally { main { activity.finish() } }
    }

    @Test
    fun hardwareKeyboardMatchesWebAndSeatChangesNeverTransferAHeldShortcut() {
        val activity = launch()
        try {
            main {
                val session = state(activity)
                session.publicSelected = false
                session.botCount = 0
                session.localSelected = false
                session.selectMode("infinity")
                session.play()
                fun key(code: Int, down: Boolean, repeat: Int = 0) {
                    val now = SystemClock.uptimeMillis()
                    activity.dispatchKeyEvent(KeyEvent(now, now,
                        if (down) KeyEvent.ACTION_DOWN else KeyEvent.ACTION_UP, code, repeat))
                }
                fun seat(id: Int?) = GameSession::class.java.getDeclaredField("localID2").run {
                    isAccessible = true; set(session, id)
                }
                for (code in listOf(KeyEvent.KEYCODE_Q, KeyEvent.KEYCODE_C, KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_ENTER)) {
                    key(code, true); assertTrue("Solo $code fires P1", session.input.fire)
                    key(code, false); assertFalse(session.input.fire)
                }
                key(KeyEvent.KEYCODE_SPACE, true)
                seat(2)
                key(KeyEvent.KEYCODE_W, true)
                assertFalse(session.input.forward)
                assertTrue(session.input2.forward)
                assertFalse("Old solo Space cannot transfer to P2", session.input2.fire)
                assertFalse(session.input.fire)
                key(KeyEvent.KEYCODE_SPACE, true, repeat = 1)
                assertFalse("A held key repeat cannot rearm after a seat change", session.input2.fire)
                key(KeyEvent.KEYCODE_SPACE, false)
                for (code in listOf(KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_ENTER)) {
                    key(code, true); assertTrue("Paired $code belongs to P2", session.input2.fire)
                    assertFalse(session.input.fire)
                    key(code, false); assertFalse(session.input2.fire)
                }
                for (code in listOf(KeyEvent.KEYCODE_Q, KeyEvent.KEYCODE_C)) {
                    key(code, true); assertFalse(session.input.fire); assertTrue(session.input2.fire)
                    key(code, false)
                }
                key(KeyEvent.KEYCODE_DPAD_UP, true)
                assertTrue(session.input2.forward)
                assertFalse(session.input.forward)
                key(KeyEvent.KEYCODE_DPAD_UP, false)
                key(KeyEvent.KEYCODE_SPACE, true)
                seat(null)
                key(KeyEvent.KEYCODE_A, true)
                assertFalse("Removing P2 cannot turn its Space hold into P1 fire", session.input.fire)
                key(KeyEvent.KEYCODE_SPACE, true, repeat = 1)
                assertFalse(session.input.fire)
                key(KeyEvent.KEYCODE_SPACE, false)
                key(KeyEvent.KEYCODE_SPACE, true)
                assertTrue(session.input.fire)
                activity.onWindowFocusChanged(false)
                assertFalse(session.input.fire)
                activity.onWindowFocusChanged(true)
                key(KeyEvent.KEYCODE_SPACE, true, repeat = 1)
                assertFalse("Focus restoration requires a new down edge", session.input.fire)
                key(KeyEvent.KEYCODE_SPACE, false)
                key(KeyEvent.KEYCODE_ENTER, true)
                assertTrue(session.input.fire)
                key(KeyEvent.KEYCODE_ENTER, false)
            }
        } finally { main { activity.finish() } }
    }

    @Test
    fun touchAndKeyboardFireRemainHeldUntilBothSourcesRelease() {
        val activity = launch()
        try {
            main {
                val session = state(activity)
                session.publicSelected = false; session.botCount = 0; session.selectMode("infinity"); session.play()
            }
            SystemClock.sleep(200)
            main {
                val session = state(activity)
                val view = MainActivity::class.java.getDeclaredField("arena").run { isAccessible = true; get(activity) as NativeArenaView }
                val density = view.resources.displayMetrics.density
                val x = NativeArenaView::class.java.getDeclaredField("fireX").apply { isAccessible = true }.getFloat(view) * density
                val y = NativeArenaView::class.java.getDeclaredField("fireY").apply { isAccessible = true }.getFloat(view) * density
                fun touch(action: Int) {
                    val now = SystemClock.uptimeMillis()
                    android.view.MotionEvent.obtain(now, now, action, x, y, 0).let { view.onTouchEvent(it); it.recycle() }
                }
                fun key(down: Boolean) { activity.dispatchKeyEvent(KeyEvent(if (down) KeyEvent.ACTION_DOWN else KeyEvent.ACTION_UP, KeyEvent.KEYCODE_Q)) }
                key(true); touch(android.view.MotionEvent.ACTION_DOWN)
                assertTrue(session.input.fire)
                touch(android.view.MotionEvent.ACTION_UP)
                assertTrue("Releasing touch cannot release the held keyboard Fire", session.input.fire)
                key(false); assertFalse(session.input.fire)
                touch(android.view.MotionEvent.ACTION_DOWN); key(true); key(false)
                assertTrue("Releasing keyboard cannot release held touch Fire", session.input.fire)
                touch(android.view.MotionEvent.ACTION_UP); assertFalse(session.input.fire)
                // An independent touch joystick must also survive keyboard button changes.
                view.input.stickX = .8; view.input.stickY = -.4
                view.onInput?.invoke(view.input.copy())
                key(true)
                assertEquals(.8, session.input.stickX, 0.0); assertEquals(-.4, session.input.stickY, 0.0)
                assertTrue(session.input.touchAim)
                key(false)
                view.resetControls()
                assertFalse(session.input.fire)
            }
        } finally { main { activity.finish() } }
    }

    @Test
    fun remappedKeyboardKeyReplacesItsDefaultInTheArena() {
        val activity = launch()
        try {
            main {
                val session = state(activity)
                session.keyboardBindings = session.keyboardBindings.assign(0, NativeControlAction.FORWARD, KeyEvent.KEYCODE_I)
                session.localSelected = true
                session.botCount = 0
                session.play()
                assertNotNull(session.localID2)
                fun key(down: Boolean, code: Int) {
                    activity.dispatchKeyEvent(KeyEvent(if (down) KeyEvent.ACTION_DOWN else KeyEvent.ACTION_UP, code))
                }
                key(true, KeyEvent.KEYCODE_W)
                assertFalse(session.input.forward)
                assertFalse(session.input2.forward)
                key(false, KeyEvent.KEYCODE_W)
                key(true, KeyEvent.KEYCODE_I)
                assertFalse(session.input.forward)
                assertTrue(session.input2.forward)
                key(false, KeyEvent.KEYCODE_I)
                assertFalse(session.input2.forward)
            }
        } finally { main { activity.finish() } }
    }

    @Test
    fun readyRoomShowsNativeAccountControlsAndCombinedSettings() {
        val activity = launch()
        val device = UiDevice.getInstance(instrumentation)
        fun activeDialog() = MainActivity::class.java.getDeclaredField("dialog").run {
            isAccessible = true
            get(activity) as? AlertDialog
        }
        try {
            val education = device.findObject(UiSelector().text("Got it"))
            if (education.waitForExists(500)) education.click()
            main { state(activity).selectMode("elimination") }
            assertTrue(device.findObject(UiSelector().description("P1 callsign")).waitForExists(5000))
            assertFalse(device.findObject(UiSelector().text("READY ROOM.")).exists())
            assertFalse(device.findObject(UiSelector().text("● READY ROOM")).exists())
            assertTrue(device.findObject(UiSelector().description("P1 account key")).exists())
            main {
                val controlsIcon = descendants(activity.window.decorView).filterIsInstance<android.widget.ImageButton>()
                    .single { it.isShown && it.contentDescription == "Controls" }
                assertTrue(controlsIcon.performClick())
            }
            await("The Controls button opens Controls") { activeDialog()?.isShowing == true }
            main {
                val controls = activeDialog()!!
                val root = controls.window!!.decorView
                val views = descendants(root)
                fun visibleTitles() = descendants(root).filterIsInstance<TextView>().filter { it.isShown }.map { it.text.toString() }
                val titles = visibleTitles()
                assertTrue(titles.containsAll(listOf("QUICK TOUR", "SHOWCASE", "Show FPS and ping", "Sound volume", "ONLINE SERVER", "SAVE SERVER", "RESET ALL SETTINGS", "BACK")))
                assertEquals("QUICK TOUR", titles[titles.indexOf("SHOWCASE") - 1])
                assertEquals(listOf("RESET ALL SETTINGS", "BACK"), titles.takeLast(2))
                val reset = views.filterIsInstance<android.widget.Button>().single { it.text == "RESET ALL SETTINGS" }
                assertEquals(NativeStyle.danger, reset.currentTextColor)
                val devices = InputDevice.getDeviceIds().asList().mapNotNull { InputDevice.getDevice(it) }.filterNot { it.isVirtual }
                val keyboard = devices.any { it.keyboardType == InputDevice.KEYBOARD_TYPE_ALPHABETIC }
                val mouse = devices.any { it.supportsSource(InputDevice.SOURCE_MOUSE) }
                val binds = views.singleOrNull { it.isShown && it.contentDescription == "Binds, Collapsed" }
                assertEquals(keyboard || mouse, binds != null)
                assertFalse(titles.any { it.startsWith("Keyboard defaults") })
                assertTrue(titles.none { it in listOf("KEYBOARD LAYOUT 1", "RESET DEFAULT KEYS", "Mouse aim", "Mouse fire") })
                if (binds != null) {
                    assertTrue(binds.performClick())
                    assertEquals("Binds, Expanded", binds.contentDescription)
                    val expanded = visibleTitles()
                    assertEquals(keyboard, expanded.any { it.startsWith("Keyboard defaults") })
                    assertEquals(keyboard, "KEYBOARD LAYOUT 1" in expanded)
                    assertEquals(keyboard, "RESET DEFAULT KEYS" in expanded)
                    assertEquals(mouse, "Mouse aim" in expanded)
                    assertEquals(mouse, "Mouse fire" in expanded)
                    assertTrue(binds.performClick())
                    assertEquals("Binds, Collapsed", binds.contentDescription)
                    assertEquals(titles, visibleTitles())
                }
                assertEquals("Online server", views.filterIsInstance<android.widget.EditText>().single().contentDescription)
                assertTrue(views.any { it.contentDescription == "Close Controls" })
                val sound = views.filterIsInstance<android.widget.Switch>().single { it.text == "Sound and haptics" }
                val session = state(activity)
                val muted = session.muted
                sound.performClick()
                assertEquals(!muted, session.muted)
                val account = views.filterIsInstance<android.widget.Button>().single { it.text == "P2 ACCOUNT KEY" }
                assertTrue(account.performClick())
            }
            await("The P2 account menu opens from Controls") {
                activeDialog()?.window?.decorView?.let { root ->
                    descendants(root).filterIsInstance<TextView>().any { it.text == "IMPORT FROM ANOTHER DEVICE" }
                } == true
            }
            device.pressBack()
            assertTrue(device.findObject(UiSelector().description("Close Controls")).waitForExists(2000))
        } finally {
            main { activity.finish() }
        }
    }

    @Test
    fun onlineServerEditorValidatesSavesAndRestoresTheConfiguredOrigin() {
        val settings = instrumentation.targetContext.getSharedPreferences("leqra-settings", 0)
        val expectedOrigin = "https://leqra.test"
        fun showControls(activity: MainActivity) =
            MainActivity::class.java.getDeclaredMethod("showControls").apply { isAccessible = true }.invoke(activity)
        fun controls(activity: MainActivity): List<View> = MainActivity::class.java.getDeclaredField("dialog").run {
            isAccessible = true
            descendants((get(activity) as AlertDialog).window!!.decorView)
        }
        fun editor(views: List<View>) = views.filterIsInstance<android.widget.EditText>().single { it.contentDescription == "Online server" }
        fun save(views: List<View>) = views.filterIsInstance<android.widget.Button>().single { it.text == "SAVE SERVER" }.performClick()

        val activity = launch()
        try {
            main {
                val session = state(activity)
                val initialOrigin = session.server
                val initialPreference = settings.getString("server", null)
                showControls(activity)
                val views = controls(activity)
                val field = editor(views)
                assertEquals(initialOrigin, field.text.toString())
                field.setText("not a server")
                assertTrue(save(views))
                assertEquals(initialOrigin, session.server)
                assertEquals(initialPreference, settings.getString("server", null))
                val error = "Enter an HTTP or HTTPS server address."
                assertTrue(field.error?.toString() == error || views.filterIsInstance<TextView>().any { it.text == error && it.isShown })

                field.setText("  https://LEQRA.test:443/room?name=test#fragment  ")
                assertTrue(save(views))
                assertEquals(expectedOrigin, session.server)
                assertEquals(expectedOrigin, settings.getString("server", null))
                assertEquals(expectedOrigin, editor(controls(activity)).text.toString())
                assertTrue(controls(activity).filterIsInstance<TextView>().any { it.text == "Server saved." && it.isShown })
            }
        } finally { main { activity.finish() } }

        val returning = startActivity()
        try {
            await("The room reopens with the saved server") { returning.hasWindowFocus() }
            main {
                assertEquals(expectedOrigin, state(returning).server)
                showControls(returning)
                assertEquals(expectedOrigin, editor(controls(returning)).text.toString())
            }
        } finally { main { returning.finish() } }
    }

    @Test
    fun savedAccountMenuShowsIndependentScoresAndGreysCurrentUse() {
        org.junit.Assume.assumeNotNull(testServer)
        val activity = launch()
        val device = UiDevice.getInstance(instrumentation)
        try {
            val session = main { state(activity) }
            val suffix = (System.nanoTime() % 1_000_000_000).toString()
            val first = "A$suffix"
            val second = "B$suffix"
            fun eventually(message: String, condition: () -> Boolean) {
                val deadline = SystemClock.elapsedRealtime() + 15000
                while (SystemClock.elapsedRealtime() < deadline) {
                    if (main(condition)) return
                    SystemClock.sleep(30)
                }
                fail(message)
            }
            main { session.renameCallsign(first, 0, validate = true) }
            eventually("First account wasn't selected") {
                session.callsign == first && session.store.selected(server, 0)?.registrationPending == false &&
                    !(GameSession::class.java.getDeclaredField("switchingCallsign").apply { isAccessible = true }.getBoolean(session))
            }
            main { session.renameCallsign(second, 0, validate = true) }
            eventually("Second account wasn't selected") {
                session.callsign == second && session.store.selected(server, 0)?.registrationPending == false &&
                    !(GameSession::class.java.getDeclaredField("switchingCallsign").apply { isAccessible = true }.getBoolean(session))
            }
            main {
                activity.javaClass.getDeclaredMethod("showAccount", Int::class.javaPrimitiveType).apply { isAccessible = true }.invoke(activity, 0)
            }
            eventually("Saved scores did not load") {
                val dialog = activity.javaClass.getDeclaredField("dialog").apply { isAccessible = true }.get(activity) as? AlertDialog
                val root = dialog?.window?.decorView ?: return@eventually false
                fun children(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { children(view.getChildAt(it)) } else emptyList()
                val text = children(root).filterIsInstance<TextView>()
                text.any { it.text.toString() == "$first: 0 points" } && text.any { it.text.toString() == "$second: 0 points" }
            }
            main {
                val dialog = activity.javaClass.getDeclaredField("dialog").apply { isAccessible = true }.get(activity) as AlertDialog
                fun children(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { children(view.getChildAt(it)) } else emptyList()
                val buttons = children(dialog.window!!.decorView).filterIsInstance<android.widget.Button>()
                val active = buttons.single { it.text.toString() == "USE $second" }
                assertFalse(active.isEnabled)
                assertTrue("Active USE must be visibly dimmed", active.alpha < .6f)
                assertTrue(buttons.single { it.text.toString() == "USE $first" }.isEnabled)
                assertTrue(buttons.single { it.text.toString() == "RELEASE $second" }.isEnabled)
            }
            screenshot("saved-callsign-scores")
            device.pressBack()
        } finally { main { activity.finish() } }
    }

    @Test
    fun rejectedSurvivalModeKeepsReadyRoomGeometryAndShowsTheReservedNotice() {
        val activity = launch()
        try {
            main {
                val session = state(activity)
                session.publicSelected = false
                session.selectMode("elimination")
                session.botCount = 6
                session.changed(true)
            }
            SystemClock.sleep(150)
            val before = main {
                val play = MainActivity::class.java.getDeclaredField("readyPlay").run { isAccessible = true; get(activity) as View }
                val error = MainActivity::class.java.getDeclaredField("readyStartError").run { isAccessible = true; get(activity) as TextView }
                val location = IntArray(2); play.getLocationOnScreen(location)
                listOf(location[0], location[1], play.width, play.height, error.height)
            }
            main { state(activity).selectMode("survival") }
            SystemClock.sleep(150)
            main {
                val session = state(activity)
                assertEquals("elimination", session.mode)
                assertEquals(6, session.botCount)
                val play = MainActivity::class.java.getDeclaredField("readyPlay").run { isAccessible = true; get(activity) as View }
                val error = MainActivity::class.java.getDeclaredField("readyStartError").run { isAccessible = true; get(activity) as TextView }
                val location = IntArray(2); play.getLocationOnScreen(location)
                assertEquals(before, listOf(location[0], location[1], play.width, play.height, error.height))
                assertEquals(View.VISIBLE, error.visibility)
                assertTrue(error.text.contains("four squad tanks"))
                assertTrue(play.isEnabled)
            }
        } finally { main { activity.finish() } }
    }

    @Test
    fun resultDialogKeepsLocalSeatBotIdentityAndCustomTeamNames() {
        val activity = launch()
        fun texts(view: View): List<TextView> =
            (if (view is TextView) listOf(view) else emptyList()) +
                if (view is ViewGroup) (0 until view.childCount).flatMap { texts(view.getChildAt(it)) } else emptyList()
        try {
            main {
                val session = state(activity)
                session.publicSelected = false; session.botCount = 0
                session.localSelected = true; session.selectMode("infinity"); session.play()
                (MainActivity::class.java.getDeclaredField("arena").run { isAccessible = true; get(activity) } as NativeArenaView).onFrame = null
                val show = MainActivity::class.java.getDeclaredMethod("showResult").apply { isAccessible = true }
                val dismiss = MainActivity::class.java.getDeclaredMethod("dismissDialog").apply { isAccessible = true }
                for (kind in listOf("local", "bot", "team")) {
                    session.rules = RoomRules.localDefaults().copy(teamMode = if (kind == "team") "teams" else "ffa",
                        teamNames = listOf("Blue Comets", "Jade Squad", "Third", "Fourth"), teamColors = listOf(4, 5, 6, 7))
                    val tank = ArenaTank(id = 2, name = if (kind == "bot") "RUST" else "Wing", bot = kind == "bot", colorIndex = 1,
                        score = 5, team = if (kind == "team") 2 else 0)
                    val snapshot = ArenaSnapshot(tanks = listOf(tank), winner = if (kind == "local") -1 else 2,
                        result = if (kind == "local") ArenaResult(id = 2, name = "Wing", score = 5) else null)
                    GameSession::class.java.getDeclaredField("snapshot").run { isAccessible = true; set(session, snapshot) }
                    show.invoke(activity)
                    val dialog = MainActivity::class.java.getDeclaredField("dialog").run { isAccessible = true; get(activity) as AlertDialog }
                    val label = texts(dialog.window!!.decorView).single { it.text.endsWith("WINS") }
                    val expected = when (kind) { "local" -> "Wing (P2)"; "bot" -> "Bot Rust"; else -> "Jade Squad" }
                    assertEquals("$expected WINS", label.text.toString())
                    assertEquals(NativeStyle.paint(if (kind == "team") 5 else 1), label.currentTextColor)
                    assertEquals(kind != "bot", label.typeface.isBold)
                    dismiss.invoke(activity)
                }
            }
        } finally { main { activity.finish() } }
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
            tap(device.findObject(UiSelector().text("PLAY")))
            awaitPlaying(activity)
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
            assertTrue(device.findObject(UiSelector().text("← BACK TO THE BATTLE")).waitForExists(2000))
            device.findObject(UiSelector().text("← BACK TO THE BATTLE")).click()
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
            tap(UiDevice.getInstance(instrumentation).findObject(UiSelector().text("PLAY")))
            awaitPlaying(activity)
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
        org.junit.Assume.assumeNotNull(testServer)
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
            }
            eventually("Generate repair must complete without a stale blur overwriting it") {
                !session.automaticNamePending(0) && !com.leqra.core.Callsigns.botReserved(session.callsign)
            }
            main {
                assertTrue(errors.isEmpty())
                assertEquals(layoutBefore.first, y(names()[1]!!))
                names()[1]!!.requestFocus(); names()[1]!!.setText("bOt WING")
                val spans = (feedback()[1]!!.text as android.text.Spanned).getSpans(0, feedback()[1]!!.length(), android.text.style.ClickableSpan::class.java)
                spans.single().onClick(feedback()[1]!!)
            }
            eventually("P2 gets an independent repaired name") {
                !session.automaticNamePending(1) && !com.leqra.core.Callsigns.botReserved(session.localCallsign)
            }
            main {
                assertNotEquals("Generating P2's callsign creates a separate account", secondKey, session.store.selected(session.server, 1)!!.key)
                assertNotEquals(session.store.selected(session.server, 0)!!.key, session.store.selected(session.server, 1)!!.key)
                assertFalse(session.store.selected(session.server, 1)!!.registrationPending)
                assertTrue(session.accounts.savedCallsigns(session.server).any { it.name == initial.second && it.key == secondKey })
                session.publicSelected = true
                session.play()
            }
            eventually("Public entry with both generated accounts must succeed") { session.screen == Screen.PLAYING && session.localID2 != null && session.snapshot.tanks.any { it.id == session.localID2 } }
            main {
                assertFalse(session.store.selected(session.server, 1)!!.registrationPending)
                assertTrue(session.store.pending(session.server, 1).none {
                    it.purpose == "registration" && it.key == session.store.selected(session.server, 1)!!.key
                })
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
        org.junit.Assume.assumeNotNull(testServer)
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
            eventually("Room layout did not settle") {
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
