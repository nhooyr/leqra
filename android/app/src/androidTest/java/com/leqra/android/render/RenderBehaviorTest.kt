package com.leqra.android.render

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.SystemClock
import android.view.MotionEvent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.core.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RenderBehaviorTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    private fun <T> main(block: () -> T): T {
        var result: Result<T>? = null
        instrumentation.runOnMainSync { result = runCatching(block) }
        return result!!.getOrThrow()
    }

    @Test
    fun distantInfinityCoordinatesRetainSubpixelTankPositions() {
        main {
            fun centroid(base: Double): Double {
                val image = Bitmap.createBitmap(1000, 1600, Bitmap.Config.ARGB_8888)
                val view = NativeArenaView(instrumentation.targetContext)
                try {
                    view.layout(0, 0, 1000, 1600)
                    view.showControls = false
                    val state =
                        ArenaSnapshot(
                            tick = 1,
                            tanks =
                                listOf(
                                    ArenaTank(
                                        id = 1,
                                        name = "Focus",
                                        x = base + 42.125,
                                        y = base + 42.125,
                                    ),
                                    ArenaTank(
                                        id = 2,
                                        name = "Remote",
                                        x = base + 70.875,
                                        y = base + 42.125,
                                        colorIndex = 1,
                                    ),
                                ),
                        )
                    view.submit(state, 1, InfiniteMaze(137))
                    view.draw(Canvas(image))
                    val pixels = IntArray(image.width * image.height)
                    image.getPixels(pixels, 0, image.width, 0, 0, image.width, image.height)
                    var count = 0
                    var sum = 0L
                    pixels.forEachIndexed { index, color ->
                        if (color == 0xffff758f.toInt()) {
                            sum += index % image.width
                            count++
                        }
                    }
                    assertTrue("The coral remote tank is visible", count > 100)
                    return sum.toDouble() / count
                } finally {
                    view.release()
                    image.recycle()
                }
            }
            val near = centroid(0.0)
            assertEquals(
                "Positive distant worlds must preserve the same fractional pose",
                near,
                centroid(33_600_000.0),
                .05,
            )
            assertEquals(
                "Negative distant worlds must preserve the same fractional pose",
                near,
                centroid(-33_600_000.0),
                .05,
            )
        }
    }

    @Test
    fun pausingDoesNotZoomOrMoveTheFiniteArena() {
        main {
            val view = NativeArenaView(instrumentation.targetContext)
            val image = Bitmap.createBitmap(1000, 1600, Bitmap.Config.ARGB_8888)
            fun centroidY(): Double {
                view.draw(Canvas(image))
                val pixels = IntArray(image.width * image.height)
                image.getPixels(pixels, 0, image.width, 0, 0, image.width, image.height)
                var count = 0
                var sum = 0L
                pixels.forEachIndexed { index, color ->
                    if (color == 0xffff758f.toInt()) {
                        count++
                        sum += index / image.width
                    }
                }
                assertTrue(count > 100)
                return sum.toDouble() / count
            }
            try {
                view.layout(0, 0, 1000, 1600)
                view.controlsLayout = true
                view.overlayHudHeightDp = 97f
                val world = ArenaWorld(336.0, 336.0, 4, 4)
                view.submit(
                    ArenaSnapshot(
                        world = world,
                        tanks =
                            listOf(
                                ArenaTank(id = 1, x = 100.0, y = 100.0),
                                ArenaTank(
                                    id = 2,
                                    name = "Remote",
                                    x = 210.0,
                                    y = 200.0,
                                    colorIndex = 1,
                                ),
                            ),
                    ),
                    1,
                    InfiniteMaze(world),
                )
                val playing = centroidY()
                view.showControls = false
                assertEquals(
                    "Opening a modal must preserve the world viewport",
                    playing,
                    centroidY(),
                    .05,
                )
                view.showControls = true
                assertEquals("Resuming must not reframe the world", playing, centroidY(), .05)
            } finally {
                view.release()
                image.recycle()
            }
        }
    }

    @Test
    fun discontinuousProjectileSnapshotsDoNotDrawPhantomTrails() {
        main {
            val view = NativeArenaView(instrumentation.targetContext)
            val image = Bitmap.createBitmap(1000, 1600, Bitmap.Config.ARGB_8888)
            try {
                view.layout(0, 0, 1000, 1600)
                view.showControls = false
                val tank = ArenaTank(id = 1, name = "Focus", x = 42.0, y = 42.0)
                view.submit(
                    ArenaSnapshot(
                        tick = 1,
                        tanks = listOf(tank),
                        bullets =
                            listOf(
                                ArenaBullet(
                                    id = 2,
                                    colorIndex = 1,
                                    x = 100.0,
                                    y = 42.0,
                                    vx = 400.0,
                                ),
                            ),
                    ),
                    1,
                    null,
                )
                view.draw(Canvas(image))
                view.submit(
                    ArenaSnapshot(
                        tick = 2,
                        tanks = listOf(tank),
                        bullets =
                            listOf(
                                ArenaBullet(
                                    id = 2,
                                    colorIndex = 1,
                                    x = 200.0,
                                    y = 142.0,
                                    vx = 400.0,
                                ),
                            ),
                    ),
                    1,
                    null,
                )
                view.draw(Canvas(image))
                val density = view.resources.displayMetrics.density
                val zoom = (minOf(1000 / density, 1600 / density) / 420f).coerceIn(.7f, 1.2f)
                val x = (500 + (152 - 42) * zoom * density).toInt()
                val y = (800 + (94 - 42) * zoom * density).toInt()
                assertTrue(
                    "A snapshot discontinuity must not join old and new projectile positions",
                    android.graphics.Color.red(image.getPixel(x, y)) < 55,
                )
            } finally {
                view.release()
                image.recycle()
            }
        }
    }

    @Test
    fun disablingControlsAndLosingFocusNeutralizeHeldTouch() {
        main {
            val view = NativeArenaView(instrumentation.targetContext)
            val image = Bitmap.createBitmap(1000, 1600, Bitmap.Config.ARGB_8888)
            try {
                view.layout(0, 0, 1000, 1600)
                view.submit(ArenaSnapshot(tanks = listOf(ArenaTank(id = 1))), 1, InfiniteMaze(137))
                view.draw(Canvas(image))
                val now = SystemClock.uptimeMillis()
                val touch = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, 900f, 1450f, 0)
                try {
                    assertTrue(view.onTouchEvent(touch))
                    assertTrue(view.input.fire)
                } finally {
                    touch.recycle()
                }
                view.showControls = false
                view.showControls = true
                assertFalse("A modal cannot leave fire latched", view.input.fire)
                val next =
                    MotionEvent.obtain(now + 1, now + 1, MotionEvent.ACTION_DOWN, 900f, 1450f, 0)
                try {
                    view.onTouchEvent(next)
                } finally {
                    next.recycle()
                }
                assertTrue(view.input.fire)
                view.onWindowFocusChanged(false)
                assertFalse("Focus loss clears held fire", view.input.fire)
                assertEquals(0.0, view.input.stickX, 0.0)
            } finally {
                view.release()
                image.recycle()
            }
        }
    }

    @Test
    fun restartingLocalArenaResetsEffectIdsEvenWithSameGeneration() {
        main {
            val view = NativeArenaView(instrumentation.targetContext)
            val image = Bitmap.createBitmap(1000, 1600, Bitmap.Config.ARGB_8888)
            try {
                view.layout(0, 0, 1000, 1600)
                view.showControls = false
                val tank = ArenaTank(id = 1, name = "Focus", x = 42.0, y = 42.0)
                val maze = InfiniteMaze(137)
                fun state(tick: Long, id: Int, y: Double) =
                    ArenaSnapshot(
                        tick = tick,
                        generation = 0,
                        tanks = listOf(tank),
                        effects =
                            listOf(
                                ArenaEffect(
                                    id = id,
                                    kind = "laser",
                                    points = listOf(BeamPoint(42.0, y), BeamPoint(100.0, y)),
                                ),
                            ),
                    )
                view.submit(state(100, 100, 42.0), 1, maze)
                view.draw(Canvas(image))
                view.submit(state(0, 1, 84.0), 1, maze)
                view.draw(Canvas(image))
                val density = view.resources.displayMetrics.density
                val zoom = (minOf(1000 / density, 1600 / density) / 420f).coerceIn(.7f, 1.2f)
                val x = (500 + (95 - 42) * zoom * density).toInt()
                val y = (800 + (84 - 42) * zoom * density).toInt()
                val color = image.getPixel(x, y)
                assertTrue(
                    "The new arena's first laser is visible after IDs restart",
                    android.graphics.Color.red(color) > 240 &&
                        android.graphics.Color.blue(color) > 240,
                )
                val old = image.getPixel(x, 800)
                assertFalse(
                    "The old arena's laser is removed",
                    android.graphics.Color.red(old) > 240 && android.graphics.Color.blue(old) > 240,
                )
            } finally {
                view.release()
                image.recycle()
            }
        }
    }
}
