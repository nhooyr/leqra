package com.leqra.android

import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.ScrollView
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.android.accounts.PublicLeader
import com.leqra.android.accounts.PublicStatus
import com.leqra.android.render.NativeArenaView
import com.leqra.core.ArenaSnapshot
import com.leqra.core.LeaderboardEntry
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BotStandingsUiTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private fun <T> main(block: () -> T): T {
        var result: Result<T>? = null
        instrumentation.runOnMainSync { result = runCatching(block) }
        return result!!.getOrThrow()
    }
    private fun get(owner: Any, name: String): Any? = owner.javaClass.getDeclaredField(name).run { isAccessible = true; get(owner) }
    private fun set(owner: Any, name: String, value: Any?) = owner.javaClass.getDeclaredField(name).run { isAccessible = true; set(owner, value) }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()

    @Test
    fun previewAndPlayingRowsSeparateDifficultyAndWrapNamesInBothOrientations() {
        instrumentation.targetContext.getSharedPreferences("leqra-settings", 0).edit().clear()
            .putString("server", "http://127.0.0.1:1").putBoolean("publicSelected", false).putBoolean("muted", true).commit()
        val activity = instrumentation.startActivitySync(Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)) as MainActivity
        val leaders = listOf(
            LeaderboardEntry(1, "pilot#ABC234", 100, 0),
            LeaderboardEntry(2, "Bot 2 - Dumb", 12, 1, true, difficulty = "dumb"),
            LeaderboardEntry(3, "Bot 3 - Normal", 11, 2, true, difficulty = "normal"),
            LeaderboardEntry(4, "Bot 4 - Godlike", 10, 3, true, difficulty = "godlike"),
            LeaderboardEntry(5, "RUST", 9, 4, true, difficulty = "hard"),
            LeaderboardEntry(6, "Godlike Bot 99", 8, 5),
        )
        try {
            val session = main { get(activity, "session") as GameSession }
            main { (get(activity, "arena") as NativeArenaView).onFrame = null }
            for ((mode, screen) in listOf("preview" to Screen.READY, "playing" to Screen.PLAYING)) {
                if (screen == Screen.PLAYING) main {
                    session.publicSelected = false; session.botCount = 0
                    session.selectMode("infinity"); session.play()
                    (get(activity, "arena") as NativeArenaView).onFrame = null
                }
                for ((orientation, suffix) in listOf(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT to "portrait", ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE to "landscape")) {
                    main {
                        activity.requestedOrientation = orientation
                        set(session, "screen", screen)
                        set(session, "localID", 1)
                        set(session, "localID2", if (screen == Screen.PLAYING) 6 else null)
                        set(session, "publicStatus", PublicStatus(2, leaders.size, 32, leaders.mapIndexed { index, p -> PublicLeader(p.id, p.name, p.score, p.colorIndex, index + 1, p.bot, p.difficulty) }, 4.0))
                        set(session, "snapshot", ArenaSnapshot(leaderboard = leaders))
                        set(activity, "showScores", true)
                        session.changed(true)
                    }
                    val deadline = SystemClock.elapsedRealtime() + 5000
                    val expectedOrientation = if (suffix == "portrait") android.content.res.Configuration.ORIENTATION_PORTRAIT else android.content.res.Configuration.ORIENTATION_LANDSCAPE
                    while (SystemClock.elapsedRealtime() < deadline && !main {
                        activity.resources.configuration.orientation == expectedOrientation &&
                            (get(activity, "scores") as? ScrollView)?.let { it.isLaidOut && !it.isLayoutRequested } == true
                    }) SystemClock.sleep(25)
                    SystemClock.sleep(500)
                    main {
                        val scroll = get(activity, "scores") as ScrollView
                        val labels = descendants(scroll).filterIsInstance<TextView>()
                        for ((rank, number) in listOf(2 to 2, 3 to 3, 4 to 4)) assertTrue(labels.any { it.text.toString() == "$rank. Bot $number" })
                        for (difficulty in listOf("DUMB", "MEDIUM", "GODLIKE", "HARD")) {
                            val badge = labels.single { it.text.toString() == difficulty }
                            assertTrue(badge.textSize / badge.resources.displayMetrics.scaledDensity >= 10)
                        }
                        assertTrue(labels.any { it.text.toString() == "5. Bot Rust" })
                        val secondary = labels.single { it.text.toString().startsWith("6. Godlike Bot 99") }
                        assertEquals(screen == Screen.PLAYING, secondary.typeface.isBold)
                        assertEquals("6. Godlike Bot 99" + if (screen == Screen.PLAYING) " (P2)" else "", secondary.text.toString())
                        assertFalse(labels.any { it.text.toString() == "BOT" || it.text.contains(" - Dumb") || it.text.contains(" - Normal") || it.text.contains(" - Medium") || it.text.contains(" - Godlike") })
                        assertTrue(labels.all { it.ellipsize == null })
                        val identity = labels.single { it.text.toString().startsWith("1. pilot#ABC234") }
                        assertEquals(screen == Screen.PLAYING, identity.typeface.isBold)
                        if (screen == Screen.PLAYING) assertTrue(identity.text.endsWith(" (P1)"))
                        val bitmap = Bitmap.createBitmap(scroll.width, scroll.height, Bitmap.Config.ARGB_8888)
                        scroll.draw(android.graphics.Canvas(bitmap))
                        File(instrumentation.targetContext.cacheDir, "bot-standings-$mode-$suffix.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                        bitmap.recycle()
                    }
                }
            }
        } finally { main { activity.finish() } }
    }
}
