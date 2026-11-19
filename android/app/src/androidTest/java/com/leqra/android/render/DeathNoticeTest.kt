package com.leqra.android.render

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.core.*
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DeathNoticeTest {
    @Test
    fun noticesMatchLiveTankLabelsWrapAndClearOnRespawnAcrossLayouts() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            for (fixed in listOf(false, true)) for (landscape in listOf(false, true)) for (paired in listOf(false, true)) {
                val view = NativeArenaView(context)
                view.showControls = false; view.controlsLayout = false
                val density = context.resources.displayMetrics.density
                val width = ((if (landscape) 844 else 390) * density).toInt()
                val height = ((if (landscape) 390 else 844) * density).toInt()
                view.layout(0, 0, width, height)
                val world = if (fixed) ArenaWorld(width = 840.0, height = 840.0, cols = 10, rows = 10) else null
                val dead = ArenaTank(id = 1, name = "Victim", x = 420.0, y = 420.0, hp = 0,
                    killedBy = "A very long killer callsign with 雪 and <literal> text", killedByColor = "#ff83bd")
                val state = ArenaSnapshot(world = world, tanks = listOf(dead,
                    ArenaTank(id = 2, name = "Witness", x = 450.0, y = 420.0), dead.copy(id = 3, x = 420.0, y = 450.0)))
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                try {
                    view.submit(state, 1, InfiniteMaze(42), if (paired) 3 else null)
                    view.draw(Canvas(bitmap))
                    @Suppress("UNCHECKED_CAST")
                    val notices = NativeArenaView::class.java.getDeclaredField("deathNotices").run { isAccessible = true; get(view) as Array<NativeDeathNotice> }
                    val paint = NativeArenaView::class.java.getDeclaredField("textPaint").run { isAccessible = true; get(view) as Paint }
                    for (notice in notices.take(if (paired) 2 else 1)) {
                        assertTrue(notice.visible)
                        assertEquals(paint.textSize, notice.fontSize, .001f)
                        assertTrue(notice.layout!!.lineCount > 1)
                        assertTrue(notice.bounds.left >= 0 && notice.bounds.right <= width / density)
                        assertEquals(dead.killedBy.let { "Killed by $it" }, notice.layout!!.text.toString())
                    }
                    val image = File(context.cacheDir, "death-notice-${if (fixed) "fixed" else "infinity"}-${if (landscape) "landscape" else "portrait"}-${if (paired) "two" else "one"}.png")
                    image.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                    view.submit(state.copy(tanks = state.tanks.map { it.copy(hp = 1) }), 1, InfiniteMaze(42), if (paired) 3 else null)
                    view.draw(Canvas(bitmap))
                    assertTrue(notices.none { it.visible })
                } finally { bitmap.recycle(); view.release() }
            }
        }
    }
}
