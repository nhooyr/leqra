package com.leqra.android

import android.content.ContextWrapper
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.ScrollView
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.android.accounts.isolatedAccountContext
import com.leqra.android.network.NetworkWelcome
import com.leqra.android.render.NativeArenaView
import com.leqra.core.ArenaSnapshot
import com.leqra.core.ArenaTank
import com.leqra.core.GameInput
import com.leqra.core.LeaderboardEntry
import java.io.File
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SpectatorUiTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    private fun <T> main(block: () -> T): T {
        var result: Result<T>? = null
        instrumentation.runOnMainSync { result = runCatching(block) }
        return result!!.getOrThrow()
    }

    private fun get(owner: Any, name: String): Any? =
        owner.javaClass.getDeclaredField(name).run {
            isAccessible = true
            get(owner)
        }

    private fun set(owner: Any, name: String, value: Any?) =
        owner.javaClass.getDeclaredField(name).run {
            isAccessible = true
            set(owner, value)
        }

    private fun eventually(message: String, check: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 20000
        while (SystemClock.elapsedRealtime() < deadline) {
            if (main(check)) return
            SystemClock.sleep(30)
        }
        fail(message)
    }

    private fun descendants(view: View): List<View> =
        listOf(view) +
            if (view is ViewGroup)
                (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) }
            else emptyList()

    @Test
    fun fullRankingBeyondTenWrapsNamesAndRetainsScrollPositionAcrossUpdates() {
        val server = InstrumentationRegistry.getArguments().getString("server")
        assumeTrue("A local test origin is required", server != null)
        instrumentation.targetContext
            .getSharedPreferences("leqra-settings", 0)
            .edit()
            .clear()
            .putString("server", server)
            .putBoolean("publicSelected", false)
            .putBoolean("muted", true)
            .commit()
        val activity =
            instrumentation.startActivitySync(
                Intent(instrumentation.targetContext, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            ) as MainActivity
        try {
            main {
                val session = get(activity, "session") as GameSession
                val arena = get(activity, "arena") as NativeArenaView
                arena.onFrame = null
                set(session, "online", true)
                set(session, "arenaActive", true)
                set(session, "screen", Screen.PLAYING)
                set(session, "localID", 0)
                set(session, "localID2", null)
                set(session, "followingID", 24)
                set(
                    session.arenaNetwork,
                    "welcome",
                    NetworkWelcome.parse(
                        JSONObject().put("id", 0).put("spectating", true).put("following", 24)
                    ),
                )
                set(
                    session,
                    "snapshot",
                    ArenaSnapshot(
                        spectating = true,
                        following = 24,
                        tanks =
                            listOf(ArenaTank(id = 24, name = "Bot 1234567890 - Godlike", hp = 0)),
                        leaderboard =
                            (1..24).map {
                                LeaderboardEntry(
                                    it,
                                    if (it == 24) "Bot 1234567890 - Godlike" else "Tank $it",
                                    25 - it,
                                    bot = it > 2,
                                )
                            },
                    ),
                )
                session.changed(true)
            }
            eventually("Full leaderboard did not lay out") {
                (get(activity, "scores") as? ScrollView)?.height?.let { it > 0 } == true
            }
            var oldPosition = 0
            main {
                val scroll = get(activity, "scores") as ScrollView
                val rows =
                    descendants(scroll).filter {
                        it.contentDescription?.startsWith("Follow ") == true
                    }
                assertEquals(24, rows.size)
                assertTrue(rows.all { it.isClickable })
                val last = rows.last() as TextView
                assertTrue(last.text.toString().contains("Bot 1234567890 - Godlike"))
                assertTrue(last.text.toString().contains("FOLLOWING"))
                assertNull(last.ellipsize)
                scroll.scrollTo(0, scroll.getChildAt(0).height)
                oldPosition = scroll.scrollY
                assertTrue(oldPosition > 0)
                val session = get(activity, "session") as GameSession
                set(
                    session,
                    "snapshot",
                    session.snapshot.copy(
                        leaderboard =
                            session.snapshot.leaderboard.map { it.copy(score = it.score + 1) }
                    ),
                )
                session.changed(false)
            }
            eventually("Score refresh lost the observer's scroll position") {
                (get(activity, "scores") as ScrollView).scrollY == oldPosition
            }
        } finally {
            main { activity.finish() }
        }
    }

    @Test
    fun roomInfinityViewerHasScrollableFollowRowsWithoutLocalControlsInBothOrientations() {
        val server = InstrumentationRegistry.getArguments().getString("server")
        assumeTrue("A local spectator-capable Go backend is required", server != null)
        val base = isolatedAccountContext()
        val prefix = "watch-host-${UUID.randomUUID()}-"
        val context =
            object : ContextWrapper(base) {
                override fun getNoBackupFilesDir(): File = base.noBackupFilesDir

                override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                    super.getSharedPreferences(prefix + name, mode)
            }
        var activity: MainActivity? = null
        var host: GameSession? = null
        try {
            val suffix = (System.nanoTime() % 1000000000).toString()
            main {
                host = GameSession(context)
                host!!.setServer(server!!)
                host!!.callsign = "Host$suffix"
                host!!.publicSelected = false
                host!!.localSelected = false
                host!!.selectMode("infinity")
                host!!.botCount = 6
                host!!.share()
            }
            eventually("Host did not publish") {
                host!!.network.connected && host!!.roomCode != null
            }
            instrumentation.targetContext
                .getSharedPreferences("leqra-settings", 0)
                .edit()
                .clear()
                .putString("server", server)
                .putBoolean("publicSelected", false)
                .putBoolean("muted", true)
                .commit()
            activity =
                instrumentation.startActivitySync(
                    Intent(instrumentation.targetContext, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                ) as MainActivity
            val shown = activity
            val viewer = main { get(shown, "session") as GameSession }
            main {
                viewer.callsign = "View$suffix"
                viewer.join(host!!.roomCode!!, spectator = true)
            }
            eventually("Viewer did not join the ready room") {
                viewer.roomSpectating && viewer.room != null
            }
            main { host!!.play() }
            eventually("Room start did not automatically enter the observer arena") {
                viewer.screen == Screen.PLAYING &&
                    viewer.arenaNetwork.connected &&
                    viewer.snapshot.spectating &&
                    viewer.snapshot.leaderboard.size >= 7
            }
            val initialSequence = main { viewer.arenaNetwork.lastInputSequence }
            main { viewer.input = GameInput(forward = true, fire = true) }
            SystemClock.sleep(200)
            main {
                assertEquals(0, viewer.localID)
                assertNull(viewer.localID2)
                assertFalse(viewer.audioGameplayActive)
                assertTrue(viewer.audioSceneActive)
                assertEquals(initialSequence, viewer.arenaNetwork.lastInputSequence)
                assertFalse((get(shown, "arena") as NativeArenaView).showControls)
                assertEquals(View.GONE, (get(shown, "loadout") as View).visibility)
            }
            var selected = 0
            for ((orientation, label) in
                listOf(
                    ActivityInfo.SCREEN_ORIENTATION_PORTRAIT to "portrait",
                    ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE to "landscape",
                )) {
                main {
                    shown.requestedOrientation = orientation
                    set(shown, "showScores", true)
                    viewer.changed(false)
                }
                eventually("Leaderboard layout did not settle in $label") {
                    val expected =
                        if (label == "portrait")
                            android.content.res.Configuration.ORIENTATION_PORTRAIT
                        else android.content.res.Configuration.ORIENTATION_LANDSCAPE
                    shown.resources.configuration.orientation == expected &&
                        (get(shown, "scores") as? ScrollView)?.let {
                            it.isLaidOut && !it.isLayoutRequested
                        } == true
                }
                SystemClock.sleep(600)
                main {
                    val scroll = get(shown, "scores") as ScrollView
                    val rows =
                        descendants(scroll).filter {
                            it.contentDescription?.startsWith("Follow ") == true
                        }
                    assertEquals(viewer.snapshot.leaderboard.size, rows.size)
                    assertTrue(rows.any { (it as TextView).text.contains("Bot ") })
                    assertTrue(
                        rows.all {
                            (it as TextView).textSize / it.resources.displayMetrics.scaledDensity >=
                                10f
                        }
                    )
                    assertTrue(scroll.height <= (get(shown, "stage") as View).height)
                    scroll.scrollTo(0, scroll.getChildAt(0).height)
                    if (label == "landscape")
                        assertTrue(
                            "Landscape list scrolls to all tanks",
                            scroll.canScrollVertically(-1),
                        )
                    val target = viewer.snapshot.leaderboard.last()
                    selected = target.id
                    rows.first { it.contentDescription == "Follow ${target.name}" }.performClick()
                }
                eventually(
                    "Tapping a tank did not receive its authoritative follow acknowledgement"
                ) {
                    viewer.followingID == selected &&
                        viewer.snapshot.following == selected &&
                        viewer.snapshot.tanks.any { it.id == selected }
                }
                main {
                    assertEquals(selected, (get(shown, "arena") as NativeArenaView).followingID)
                    if (label == "portrait")
                        assertNull(
                            "Selecting a portrait row reveals the followed arena",
                            get(shown, "scores"),
                        )
                }
                val image = instrumentation.uiAutomation.takeScreenshot()!!
                File(
                        instrumentation.targetContext.getExternalFilesDir(null),
                        "android-spectator-$label.png",
                    )
                    .outputStream()
                    .use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
                image.recycle()
            }
            main {
                viewer.background()
                viewer.foreground()
            }
            eventually("Viewer did not resume the selected target") {
                viewer.arenaNetwork.connected && viewer.snapshot.following == selected
            }
            main {
                viewer.command(
                    "spectate",
                    "target" to viewer.network.welcome!!.id,
                    "member" to viewer.network.welcome!!.member,
                    "spectating" to false,
                )
            }
            eventually("Promotion did not update the room role without losing its control socket") {
                !viewer.roomSpectating && viewer.network.connected
            }
            main { viewer.play() }
            eventually("Promoted viewer could not join as a pilot") {
                viewer.arenaNetwork.connected && !viewer.spectating && viewer.localID > 0
            }
            main {
                viewer.command(
                    "spectate",
                    "target" to viewer.network.welcome!!.id,
                    "member" to viewer.network.welcome!!.member,
                    "spectating" to true,
                )
            }
            eventually(
                "Demotion did not retire local controls and automatically enter the observer arena"
            ) {
                viewer.arenaNetwork.connected &&
                    viewer.spectating &&
                    viewer.localID == 0 &&
                    viewer.snapshot.spectating &&
                    viewer.network.connected
            }
            main {
                viewer.lobby()
                assertTrue(host!!.room?.optBoolean("infinityActive") == true)
                assertEquals(Screen.READY, viewer.screen)
                assertFalse(viewer.arenaNetwork.connected)
                assertTrue(viewer.network.connected)
                viewer.play()
            }
            eventually("Watch Infinity did not reenter the running arena") {
                viewer.arenaNetwork.connected && viewer.screen == Screen.PLAYING
            }
            main { host!!.lobby() }
            eventually("Host returning to lobby did not close the observer arena") {
                viewer.room?.optBoolean("infinityActive") != true &&
                    viewer.screen == Screen.READY &&
                    !viewer.arenaNetwork.connected &&
                    viewer.network.connected
            }
            val errors = mutableListOf<String>()
            main {
                viewer.notifyError = { errors.add(it) }
                viewer.leave()
                host!!.play()
            }
            eventually("Host did not start a new Infinity run") { host!!.arenaNetwork.connected }
            main { viewer.join(host!!.roomCode!!, spectator = true) }
            eventually("Late room spectator did not automatically enter the live arena") {
                viewer.spectating &&
                    viewer.arenaNetwork.connected &&
                    viewer.screen == Screen.PLAYING
            }
            main {
                host!!.command(
                    "kick",
                    "target" to viewer.network.welcome!!.id,
                    "member" to viewer.network.welcome!!.member,
                )
            }
            eventually("Kicked viewer retained an arena or room connection") {
                !viewer.online &&
                    !viewer.network.connected &&
                    !viewer.arenaNetwork.connected &&
                    viewer.screen == Screen.READY
            }
            main {
                assertTrue(errors.isNotEmpty())
                errors.clear()
                viewer.join(host!!.roomCode!!, spectator = true)
            }
            eventually("Viewer could not rejoin after removal") {
                viewer.arenaNetwork.connected && viewer.spectating
            }
            main { host!!.lobby() }
            eventually("Final ready room did not settle") {
                viewer.screen == Screen.READY && viewer.room?.optBoolean("infinityActive") != true
            }
            main { host!!.command("unshare") }
            eventually("Unsharing did not explicitly detach the spectator") {
                !viewer.online && !viewer.network.connected && !viewer.arenaNetwork.connected
            }
            main { assertTrue(errors.any { it.contains("offline", ignoreCase = true) }) }
        } finally {
            main {
                host?.leave()
                host?.release()
                activity?.finish()
            }
            context.noBackupFilesDir.deleteRecursively()
        }
    }
}
