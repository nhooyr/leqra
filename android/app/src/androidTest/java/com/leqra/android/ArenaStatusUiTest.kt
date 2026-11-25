package com.leqra.android

import android.content.ContextWrapper
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.android.accounts.isolatedAccountContext
import com.leqra.core.ArenaSnapshot
import com.leqra.core.ArenaTank
import com.leqra.core.LeaderboardEntry
import java.io.File
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ArenaStatusUiTest {
    @Test
    fun tabletLoadoutUsesCompactRowsAndWrapsLongNames() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            val hud = NativeHudView(context).apply { inline = true }
            val state =
                ArenaSnapshot(
                    tanks =
                        listOf(ArenaTank(id = 1, name = "Pilot"), ArenaTank(id = 2, name = "Wing")),
                )
            fun measure(width: Int) {
                hud.measure(
                    View.MeasureSpec.makeMeasureSpec(
                        (width * context.resources.displayMetrics.density).toInt(),
                        View.MeasureSpec.EXACTLY,
                    ),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
                )
                hud.layout(0, 0, hud.measuredWidth, hud.measuredHeight)
            }
            hud.update(state, 1, null, true, false, false)
            measure(600)
            assertTrue(
                "A normal tablet pilot fits one short line",
                hud.height / context.resources.displayMetrics.density <= 40f,
            )
            hud.stacked = true
            hud.update(state, 1, 2, true, false, false)
            measure(600)
            val shortHeight = hud.height
            assertTrue(
                "Paired portrait uses two short lines",
                shortHeight / context.resources.displayMetrics.density <= 80f,
            )
            state.tanks.first().name = "界".repeat(16)
            hud.update(state, 1, 2, true, false, false)
            measure(600)
            assertTrue("Long identities wrap instead of clipping", hud.height > shortHeight)
            assertTrue(hud.contentDescription.contains("界".repeat(16)))
            val image = Bitmap.createBitmap(hud.width, hud.height, Bitmap.Config.ARGB_8888)
            hud.draw(Canvas(image))
            val directory = File(context.cacheDir, "ui-polish").apply { mkdirs() }
            File(directory, "tablet-loadout-wrapping.png").outputStream().use {
                image.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
            image.recycle()
            state.tanks.first().name = "Pilot"
            hud.stacked = false
            hud.update(state, 1, 2, true, false, false)
            measure(1080)
            assertTrue(
                "Wide paired pilots share one short row",
                hud.height / context.resources.displayMetrics.density <= 40f,
            )
            val normalHeight = hud.height
            state.tanks.first().locked = true
            hud.update(state, 1, 2, true, false, false)
            assertTrue("A new lock warning can grow its row", hud.isLayoutRequested)
            measure(1080)
            assertTrue(hud.height > normalHeight)
        }
    }

    @Test
    fun compactTabletHeaderFitsRoomActionsAndCompleteArenaStatus() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val context = isolatedAccountContext()
            val session = GameSession(context)
            fun set(name: String, value: Any) =
                GameSession::class
                    .java
                    .getDeclaredField(name)
                    .apply { isAccessible = true }
                    .set(session, value)
            try {
                session.publicSelected = false
                session.showFPS = true
                set("screen", Screen.PLAYING)
                set("online", true)
                set("latency", 84.0)
                set("localID", 1)
                val snapshot =
                    ArenaSnapshot(
                        phase = "playing",
                        players = 83,
                        tanks = listOf(ArenaTank(id = 1, score = 819, rank = 1)),
                        leaderboard =
                            (1..8).map {
                                LeaderboardEntry(id = it, colorIndex = it - 1, score = 100 + it)
                            },
                    )
                for (width in listOf(600, 720, 800)) for (infinity in listOf(false, true)) {
                    session.selectMode(if (infinity) "infinity" else "elimination")
                    set("screen", Screen.PLAYING)
                    set("online", true)
                    set("infinity", infinity)
                    set("snapshot", snapshot)
                    val root = NativeStyle.column(context)
                    val header = NativeGameHeader(context, {}, {}, {}, openSidebar = {})
                    val status = NativeStatusView(context, {})
                    root.addView(header)
                    root.addView(status)
                    header.placeStatus(status, true)
                    assertEquals(
                        android.graphics.Color.TRANSPARENT,
                        (status.background as android.graphics.drawable.ColorDrawable).color,
                    )
                    status.setPadding(8, 12, 8, 12)
                    status.update(session, 120)
                    header.display(false, width.toFloat(), false, true, roomCode = "ABCDEF")
                    assertSame(
                        "Leaderboard remains with fixed header controls",
                        header,
                        status.leaderboardButton.parent,
                    )
                    val density = context.resources.displayMetrics.density
                    header.measure(
                        View.MeasureSpec.makeMeasureSpec(
                            (width * density).toInt(),
                            View.MeasureSpec.EXACTLY,
                        ),
                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
                    )
                    header.layout(0, 0, header.measuredWidth, header.measuredHeight)
                    fun verify(view: View) {
                        if (view.visibility != View.VISIBLE) return
                        if (view is TextView && view.text.isNotEmpty()) {
                            assertTrue(
                                "Text has usable width at $width dp",
                                view.width > view.paddingLeft + view.paddingRight,
                            )
                            assertTrue(
                                "Text has usable height at $width dp",
                                view.layout.height <=
                                    view.height - view.paddingTop - view.paddingBottom,
                            )
                            for (line in 0 until view.layout.lineCount) assertEquals(
                                0,
                                view.layout.getEllipsisCount(line),
                            )
                        }
                        for (child in children(view)) {
                            if (child.visibility != View.VISIBLE) continue
                            assertTrue("Control fits left at $width dp", child.left >= 0)
                            if (view !is android.widget.HorizontalScrollView)
                                assertTrue(
                                    "Control fits right at $width dp",
                                    child.right <= view.width,
                                )
                            assertTrue(
                                "Control fits vertically at $width dp",
                                child.bottom <= view.height,
                            )
                            verify(child)
                        }
                    }
                    verify(header)
                    assertTrue("Tablet header stays one row", header.height / density <= 60f)
                    fun singleLine(view: View) {
                        if (view.visibility != View.VISIBLE) return
                        if (view is TextView && view.text.isNotEmpty())
                            assertEquals(1, view.lineCount)
                        children(view).forEach(::singleLine)
                    }
                    singleLine(status)
                    assertTrue(visibleTexts(status).any { it == "fps: 120, 84 ms" })
                    val row = visibleTexts(status)
                    val scorePosition = row.indexOfFirst {
                        if (infinity) it.startsWith("score:") else it.contains("101")
                    }
                    assertTrue(
                        "Performance precedes score data",
                        row.indexOf("fps: 120, 84 ms") < scorePosition,
                    )
                    assertTrue(
                        visibleTexts(status).any {
                            if (infinity) it == "score: 819, #1"
                            else it.contains("101") && it.contains("108")
                        },
                    )
                    assertTrue(visibleTexts(header).contains("ROOM"))
                    val image =
                        Bitmap.createBitmap(header.width, header.height, Bitmap.Config.ARGB_8888)
                    header.draw(Canvas(image))
                    val directory =
                        File(instrumentation.targetContext.cacheDir, "ui-polish").apply { mkdirs() }
                    File(
                            directory,
                            "tablet-header-$width-${if (infinity) "infinity" else "finite"}.png",
                        )
                        .outputStream()
                        .use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
                    image.recycle()
                    header.placeStatus(status, false)
                    assertSame(status, status.leaderboardButton.parent)
                    assertEquals(
                        NativeStyle.surface,
                        (status.background as android.graphics.drawable.ColorDrawable).color,
                    )
                }
            } finally {
                session.release()
                context.noBackupFilesDir.deleteRecursively()
            }
        }
    }

    @Test
    fun performanceSettingShowsOneCombinedReadoutAcrossModes() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            val accountContext = isolatedAccountContext()
            val prefix = "arena-status-${UUID.randomUUID()}-"
            val context =
                object : ContextWrapper(accountContext) {
                    override fun getSharedPreferences(name: String, mode: Int) =
                        super.getSharedPreferences(prefix + name, mode)
                }
            val prefs = context.getSharedPreferences("leqra-settings", 0)
            prefs.edit().putBoolean("showFPS", false).commit()
            val session = GameSession(context)
            try {
                assertTrue(session.showFPS)
                val status = NativeStatusView(context, openScores = {})
                session.publicSelected = true
                status.update(session, fps = 120)
                assertTrue("fps: —, ping: —" in visibleTexts(status))
                assertFalse(
                    children(status).any {
                        it.visibility == View.VISIBLE && it.contentDescription == "Open sidebar"
                    },
                )

                session.publicSelected = false
                session.selectMode("elimination")
                status.update(session, fps = 120)
                assertTrue("fps: —, ping: —" in visibleTexts(status))
                assertFalse(children(status).any { it.contentDescription == "Open sidebar" })

                session.showFPS = false
                session.save()
                status.update(session, fps = 120)
                assertFalse(visibleTexts(status).any { "fps:" in it || "ping:" in it })
                assertFalse(prefs.getBoolean("showPerformanceReadout", true))
            } finally {
                session.release()
                context.noBackupFilesDir.deleteRecursively()
            }
        }
    }

    private fun children(view: View) =
        if (view is ViewGroup) (0 until view.childCount).map(view::getChildAt) else emptyList()

    private fun visibleTexts(view: View): List<String> =
        when {
            view.visibility != View.VISIBLE -> emptyList()
            view is TextView -> listOf(view.text.toString())
            else -> children(view).flatMap(::visibleTexts)
        }
}
