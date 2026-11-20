package com.leqra.android

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.RectF
import android.view.View
import android.widget.ImageButton
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.android.NativeStyle.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NativeChromeTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test
    fun compactHeaderVersionBadgeCombinesTheGitHubMarkAndReleaseNumber() {
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            var openedGitHub = false
            val header = NativeGameHeader(context, { openedGitHub = true }, {}, {})
            header.display(false, 320f, false, false, roomCode = "PARITY")
            layout(header, context.dp(320), context.dp(54))

            val badge =
                (0 until header.childCount)
                    .map(header::getChildAt)
                    .filterIsInstance<TextView>()
                    .single { it.contentDescription == "View leqra on GitHub" }
            val mark = requireNotNull(badge.compoundDrawablesRelative[0])
            assertEquals(BuildConfig.VERSION_NAME, badge.text.toString())
            assertEquals(context.dp(17), mark.intrinsicWidth)
            assertTrue(badge.performClick())
            assertTrue(openedGitHub)
        }
    }

    @Test
    fun compactRoomHeaderFitsSidebarBesideControlsAndKeepsTheVersion() {
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            var openedSidebar = false
            val header =
                NativeGameHeader(context, {}, {}, {}, openSidebar = { openedSidebar = true })
            header.display(false, 375f, false, false, roomCode = "PARITY")
            layout(header, context.dp(375), context.dp(54))
            val views = (0 until header.childCount).map(header::getChildAt)
            val sidebar = views.single { it.contentDescription == "Open sidebar" }
            val controls = views.single { it.contentDescription == "Controls" }
            val badge =
                views.filterIsInstance<TextView>().single {
                    it.contentDescription == "View leqra on GitHub"
                }
            assertEquals(header, sidebar.parent)
            assertEquals(controls.left, sidebar.right)
            assertTrue(
                "Controls stays within the compact header",
                controls.right <= header.width - header.paddingRight,
            )
            assertEquals(BuildConfig.VERSION_NAME, badge.text.toString())
            assertTrue(sidebar.performClick())
            assertTrue(openedSidebar)
        }
    }

    @Test
    fun headerSoundIconStaysCenteredWhenMuted() {
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            val header = NativeGameHeader(context, {}, {}, {})
            for (muted in listOf(false, true)) {
                header.display(false, 390f, muted, false)
                layout(header, context.dp(390), context.dp(54))
                val button =
                    (0 until header.childCount)
                        .map(header::getChildAt)
                        .filterIsInstance<ImageButton>()
                        .single {
                            it.contentDescription == if (muted) "Unmute sound" else "Mute sound"
                        }
                val glyph = RectF(button.drawable.bounds)
                button.imageMatrix.mapRect(glyph)
                glyph.offset(button.paddingLeft.toFloat(), button.paddingTop.toFloat())
                assertEquals(button.width / 2f, glyph.centerX(), .5f)
                assertEquals(button.height / 2f, glyph.centerY(), .5f)
                assertEquals(if (muted) "Unmute sound" else "Mute sound", button.contentDescription)
            }
        }
    }

    @Test
    fun switchPaintsSolidCyanOnlyWhenEnabledAndOn() {
        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            val toggle = NativeStyle.toggle(context)
            layout(toggle, context.dp(44), context.dp(44))
            val bitmap = Bitmap.createBitmap(toggle.width, toggle.height, Bitmap.Config.ARGB_8888)
            val pixels = IntArray(bitmap.width * bitmap.height)
            fun hasCyan(): Boolean {
                bitmap.eraseColor(NativeStyle.page)
                toggle.jumpDrawablesToCurrentState()
                toggle.draw(Canvas(bitmap))
                bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
                return 0xff00c8ff.toInt() in pixels
            }
            try {
                assertFalse(hasCyan())
                toggle.performClick()
                assertTrue(toggle.isChecked)
                assertTrue(hasCyan())
                toggle.isEnabled = false
                assertFalse(hasCyan())
            } finally {
                bitmap.recycle()
            }
        }
    }

    private fun layout(view: View, width: Int, height: Int) {
        view.measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY),
        )
        view.layout(0, 0, width, height)
    }
}
