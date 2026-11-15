package com.leqra.android.render

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.core.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PressFeedbackRenderTest {
    @Test fun emptyPressDrawsTheSameBarrelAsRealRecoilWithoutChangingAuthorityOrOtherSeats() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val view = NativeArenaView(instrumentation.targetContext)
            val actual = Bitmap.createBitmap(400, 400, Bitmap.Config.ARGB_8888)
            val reference = Bitmap.createBitmap(400, 400, Bitmap.Config.ARGB_8888)
            val initial = Bitmap.createBitmap(400, 400, Bitmap.Config.ARGB_8888)
            val draw = NativeArenaView::class.java.getDeclaredMethod("drawTank", Canvas::class.java, ArenaTank::class.java).apply { isAccessible = true }
            val tank = ArenaTank(id = 1, x = 100.0, y = 100.0, ammoUsed = 5, spawnSerial = 1)
            val before = tank.copy()
            view.submit(ArenaSnapshot(tanks = listOf(tank)), 1, InfiniteMaze(42), 2)
            val feedback = PressFireFeedback()
            feedback.controls(true, tank, 0, true, 0.0)
            try {
                draw.invoke(view, Canvas(initial), tank)
                for (time in listOf(0.0, .05, .1)) {
                    val pulse = feedback.pulse(tank, 0, true, time)
                    actual.eraseColor(0); reference.eraseColor(0)
                    view.previewRecoil = pulse
                    draw.invoke(view, Canvas(actual), tank)
                    view.previewRecoil = 0.0
                    draw.invoke(view, Canvas(reference), tank.copy(recoil = pulse))
                    assertTrue("Cosmetic and actual recoil pixels match at $time", actual.sameAs(reference))
                    if (time == 0.0) assertFalse("An empty press visibly kicks the barrel", actual.sameAs(initial))
                    if (time == .1) assertTrue("The barrel rests after 100ms", actual.sameAs(initial))
                }
                view.previewRecoil = .5
                actual.eraseColor(0); reference.eraseColor(0)
                draw.invoke(view, Canvas(actual), tank.copy(recoil = .75))
                view.previewRecoil = 0.0
                draw.invoke(view, Canvas(reference), tank.copy(recoil = .75))
                assertTrue("Feedback takes max rather than adding to real recoil", actual.sameAs(reference))
                view.localPreviewRecoil = .5
                for (id in listOf(1, 2, 3)) {
                    actual.eraseColor(0); reference.eraseColor(0)
                    draw.invoke(view, Canvas(actual), tank.copy(id = id))
                    view.localPreviewRecoil = 0.0
                    draw.invoke(view, Canvas(reference), tank.copy(id = id, recoil = if (id == 2) .5 else 0.0))
                    assertTrue("Only P2 gets its pulse: $id", actual.sameAs(reference))
                    view.localPreviewRecoil = .5
                }
                assertEquals(before, tank)
            } finally { view.release(); actual.recycle(); reference.recycle(); initial.recycle() }
        }
    }
}
