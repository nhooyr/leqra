package com.leqra.android

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.leqra.android.render.NativeArenaView
import com.leqra.android.render.NativeArt
import com.leqra.core.ArenaTank
import com.leqra.core.BeamPoint
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ShowcaseTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    private fun <T> main(block: () -> T): T {
        var result: Result<T>? = null
        instrumentation.runOnMainSync { result = runCatching(block) }
        return result!!.getOrThrow()
    }

    private fun segmentDistance(tank: ArenaTank, a: BeamPoint, b: BeamPoint): Double {
        val dx = b.x - a.x
        val dy = b.y - a.y
        val lengthSquared = dx * dx + dy * dy
        val along =
            if (lengthSquared > 0)
                (((tank.x - a.x) * dx + (tank.y - a.y) * dy) / lengthSquared).coerceIn(0.0, 1.0)
            else 0.0
        return kotlin.math.hypot(tank.x - a.x - along * dx, tank.y - a.y - along * dy)
    }

    @Test
    fun aFrozenVictimKeepsItsWreckAndLabelWhileLiveInfinityHidesThem() {
        val normal = main { NativeArenaView(instrumentation.targetContext) }
        val preview = main { NativeArenaView(instrumentation.targetContext) }
        val regular = Bitmap.createBitmap(1000, 1600, Bitmap.Config.ARGB_8888)
        val frozen = Bitmap.createBitmap(1000, 1600, Bitmap.Config.ARGB_8888)
        try {
            main {
                val state =
                    com.leqra.core.ArenaSnapshot(
                        tanks =
                            listOf(
                                com.leqra.core.ArenaTank(id = 0, name = "Hero", x = 42.0, y = 42.0),
                                com.leqra.core.ArenaTank(
                                    id = 7,
                                    name = "Victim",
                                    x = 126.0,
                                    y = 126.0,
                                    hp = 0,
                                ),
                            ),
                    )
                val maze = com.leqra.core.InfiniteMaze(14383)
                for (view in listOf(normal, preview)) {
                    val art = NativeArt().apply { assertTrue(prepare()) }
                    NativeArenaView::class
                        .java
                        .getDeclaredField("art")
                        .apply { isAccessible = true }
                        .set(view, art)
                    view.showControls = false
                    view.controlsLayout = false
                    view.layout(0, 0, 1000, 1600)
                }
                normal.submit(state, 0, maze)
                preview.showFrozenScene(state, maze, 0, 8.42, emptyMap(), emptyMap(), emptyMap())
                normal.draw(Canvas(regular))
                preview.draw(Canvas(frozen))
                fun labels(view: NativeArenaView) =
                    NativeArenaView::class.java.getDeclaredField("labels").run {
                        isAccessible = true
                        get(view) as Map<*, *>
                    }
                assertFalse(
                    "Ordinary Infinity keeps dead identities hidden",
                    labels(normal).containsKey(7),
                )
                assertTrue(
                    "Showcase retains the defeated pilot's identity",
                    labels(preview).containsKey(7),
                )
                val viewport =
                    NativeArenaView::class.java.getDeclaredField("viewport").run {
                        isAccessible = true
                        get(preview) as android.graphics.RectF
                    }
                val zoom =
                    NativeArenaView::class.java.getDeclaredField("zoom").run {
                        isAccessible = true
                        getFloat(preview)
                    }
                val density = preview.resources.displayMetrics.density
                val x = ((viewport.centerX() + 84 * zoom) * density).toInt()
                val y = ((viewport.centerY() + 84 * zoom) * density).toInt()
                var changed = 0
                for (dy in -20..20) for (dx in -20..20) if (
                    regular.getPixel(x + dx, y + dy) != frozen.getPixel(x + dx, y + dy)
                )
                    changed++
                assertTrue("The victim's wreck remains visibly drawn", changed > 20)
            }
        } finally {
            regular.recycle()
            frozen.recycle()
            main {
                normal.release()
                preview.release()
            }
        }
    }

    @Test
    fun frozenCannonUsesTheCompleteAuthoredTrail() {
        val view = main { NativeArenaView(instrumentation.targetContext) }
        val image = Bitmap.createBitmap(1000, 1600, Bitmap.Config.ARGB_8888)
        try {
            main {
                val art = NativeArt().apply { assertTrue(prepare()) }
                NativeArenaView::class
                    .java
                    .getDeclaredField("art")
                    .apply { isAccessible = true }
                    .set(view, art)
                val state =
                    com.leqra.core.ArenaSnapshot(
                        tanks = listOf(com.leqra.core.ArenaTank(id = 0, x = 42.0, y = 42.0)),
                        bullets =
                            listOf(
                                com.leqra.core.ArenaBullet(
                                    id = 1,
                                    kind = "cannon",
                                    owner = 0,
                                    x = 180.0,
                                    y = 42.0,
                                    vx = 1128.0,
                                ),
                            ),
                    )
                val authored = List(10) { com.leqra.core.BeamPoint(-90.0 + it * 30, 42.0) }
                view.showFrozenScene(
                    state,
                    com.leqra.core.InfiniteMaze(14383),
                    0,
                    8.42,
                    emptyMap(),
                    emptyMap(),
                    mapOf(1 to authored),
                )
                view.layout(0, 0, 1000, 1600)
                view.draw(Canvas(image))
                @Suppress("UNCHECKED_CAST")
                val paths =
                    NativeArenaView::class.java.getDeclaredField("trails").run {
                        isAccessible = true
                        get(view) as Array<android.graphics.Path>
                    }
                val bounds = android.graphics.RectF()
                paths[2].computeBounds(bounds, true)
                assertEquals(
                    "Showcase must not truncate authored trails to the live seven-point history",
                    270f,
                    bounds.width(),
                    .001f,
                )
            }
        } finally {
            image.recycle()
            main { view.release() }
        }
    }

    @Test
    fun shortPortraitKeepsTheTopAndBottomPilotsVisibleWithoutChangingTallFraming() {
        val view = main { ShowcaseView(instrumentation.targetContext, true) }
        try {
            for ((widthDp, heightDp) in listOf(320 to 568, 440 to 956, 956 to 440)) {
                main {
                    val density = view.resources.displayMetrics.density
                    val width = (widthDp * density).toInt()
                    val height = (heightDp * density).toInt()
                    view.measure(
                        android.view.View.MeasureSpec.makeMeasureSpec(
                            width,
                            android.view.View.MeasureSpec.EXACTLY,
                        ),
                        android.view.View.MeasureSpec.makeMeasureSpec(
                            height,
                            android.view.View.MeasureSpec.EXACTLY,
                        ),
                    )
                    view.layout(0, 0, width, height)
                    val art = NativeArt().apply { assertTrue(prepare()) }
                    NativeArenaView::class
                        .java
                        .getDeclaredField("art")
                        .apply { isAccessible = true }
                        .set(view.arena, art)
                    val image = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    try {
                        view.draw(Canvas(image))
                    } finally {
                        image.recycle()
                    }
                    val viewport =
                        NativeArenaView::class.java.getDeclaredField("viewport").run {
                            isAccessible = true
                            get(view.arena) as android.graphics.RectF
                        }
                    val zoom =
                        NativeArenaView::class.java.getDeclaredField("zoom").run {
                            isAccessible = true
                            getFloat(view.arena)
                        }
                    val ordinaryZoom =
                        (minOf(viewport.width(), viewport.height()) / 420f).coerceIn(.7f, 1.2f)
                    if (widthDp < heightDp) {
                        val hero = view.scene.snapshot.tanks.single { it.id == view.scene.localID }
                        for (tank in view.scene.snapshot.tanks) {
                            val y = viewport.centerY() + ((tank.y - hero.y) * zoom).toFloat()
                            assertTrue(
                                "${tank.name} has headroom in ${widthDp}x$heightDp",
                                y - 64 * zoom >= viewport.top - .01f,
                            )
                            assertTrue(
                                "${tank.name} stays above the viewport edge in ${widthDp}x$heightDp",
                                y + 64 * zoom <= viewport.bottom + .01f,
                            )
                        }
                        @Suppress("UNCHECKED_CAST")
                        val labels =
                            NativeArenaView::class.java.getDeclaredField("labels").run {
                                isAccessible = true
                                get(view.arena) as Map<Int, Any>
                            }
                        for (label in labels.values) {
                            val size =
                                label.javaClass.getDeclaredField("fontSize").run {
                                    isAccessible = true
                                    getFloat(label)
                                }
                            assertTrue("Fitting never shrinks labels below10dp", size >= 10f)
                        }
                    }
                    if (widthDp == 440 || widthDp > heightDp)
                        assertEquals(
                            "Tall portrait and landscape keep normal zoom",
                            ordinaryZoom,
                            zoom,
                            .001f,
                        )
                }
            }
        } finally {
            main { view.release() }
        }
    }

    @Test
    fun laserAndItsNativeGuideLeaveForwardAndNeverReturnThroughTheHero() {
        for (portrait in listOf(false, true)) {
            val scene = ShowcaseScene.load(instrumentation.targetContext, portrait)
            val hero = scene.snapshot.tanks.single { it.id == scene.localID }
            val victim = scene.snapshot.tanks.single { it.hp <= 0 }
            assertTrue(scene.snapshot.effects.any { it.kind == "hit" && it.owner == victim.id })
            val beam = scene.snapshot.effects.single { it.kind == "laser" }.points
            val guide = scene.maze.laserGuide(hero.x, hero.y, hero.angle)
            for ((name, points) in listOf("beam" to beam, "guide" to guide)) {
                assertTrue("$name has a visible forward leg", points.size >= 2)
                val first = points[0]
                val end = points[1]
                assertTrue(
                    "$name leaves in the turret direction",
                    (end.x - first.x) * kotlin.math.cos(hero.angle) +
                        (end.y - first.y) * kotlin.math.sin(hero.angle) > 0,
                )
                for (index in 1 until points.lastIndex) {
                    val a = points[index]
                    val b = points[index + 1]
                    val distance = segmentDistance(hero, a, b)
                    assertTrue(
                        "$name reflection $index stays clear of P1 (portrait=$portrait, distance=$distance)",
                        distance >= 32 - 1e-5,
                    )
                }
                val touched =
                    scene.snapshot.tanks.filter { tank ->
                        points.zipWithNext().any { (a, b) ->
                            segmentDistance(tank, a, b) <= 20 + 1e-5
                        }
                    }
                assertEquals(
                    "$name intersects exactly the staged victim",
                    listOf(victim.id),
                    touched.map { it.id },
                )
            }
        }
    }

    @Test
    fun portraitAndLandscapeShowRealFrozenChromeAndInertControls() {
        val view = main { ShowcaseView(instrumentation.targetContext, true) }
        try {
            for ((width, height) in
                listOf(1000 to 1600, 1600 to 1000, 1080 to 2400, 2400 to 1080)) {
                val first = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                val later = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                try {
                    main {
                        view.measure(
                            android.view.View.MeasureSpec.makeMeasureSpec(
                                width,
                                android.view.View.MeasureSpec.EXACTLY,
                            ),
                            android.view.View.MeasureSpec.makeMeasureSpec(
                                height,
                                android.view.View.MeasureSpec.EXACTLY,
                            ),
                        )
                        view.layout(0, 0, width, height)
                        val art = NativeArt().apply { assertTrue(prepare()) }
                        NativeArenaView::class
                            .java
                            .getDeclaredField("art")
                            .apply { isAccessible = true }
                            .set(view.arena, art)
                        assertEquals(if (width < height) 10 else 8, view.scene.snapshot.tanks.size)
                        assertEquals(
                            if (width < height) 4 else 10,
                            view.scene.snapshot.pickups.size,
                        )
                        assertEquals(
                            1,
                            view.scene.snapshot.tanks.single { it.id == view.scene.localID }.rank,
                        )
                        assertTrue(view.header.height > 0)
                        assertTrue(view.status.height > 0)
                        assertTrue(view.loadout.height > 0)
                        assertTrue(
                            view.loadout.contentDescription.toString().contains("aqsnow (P1)"),
                        )
                        assertTrue(view.arena.showControls)
                        assertTrue(view.arena.width > 0 && view.arena.height > 0)
                        assertTrue(view.arena.height < height)
                        view.draw(Canvas(first))
                    }
                    val deadline = SystemClock.elapsedRealtime() + 5000
                    while (
                        main { view.arena.terrainPendingRasters > 0 } &&
                            SystemClock.elapsedRealtime() < deadline
                    ) {
                        SystemClock.sleep(30)
                        main { view.draw(Canvas(first)) }
                    }
                    main {
                        first.eraseColor(0)
                        view.draw(Canvas(first))
                    }
                    SystemClock.sleep(400)
                    main {
                        val touch =
                            android.view.MotionEvent.obtain(
                                0,
                                0,
                                android.view.MotionEvent.ACTION_DOWN,
                                width - 40f,
                                20f,
                                0,
                            )
                        try {
                            assertTrue(view.dispatchTouchEvent(touch))
                        } finally {
                            touch.recycle()
                        }
                        view.dispatchKeyEvent(
                            android.view.KeyEvent(
                                android.view.KeyEvent.ACTION_DOWN,
                                android.view.KeyEvent.KEYCODE_SPACE,
                            ),
                        )
                        assertFalse(view.arena.input.fire)
                        view.arena.start()
                        view.draw(Canvas(later))
                    }
                    val output =
                        File(instrumentation.targetContext.cacheDir, "showcase-test").apply {
                            mkdirs()
                        }
                    File(output, "chrome-$width-first.png").outputStream().use {
                        first.compress(Bitmap.CompressFormat.PNG, 100, it)
                    }
                    File(output, "chrome-$width-later.png").outputStream().use {
                        later.compress(Bitmap.CompressFormat.PNG, 100, it)
                    }
                    assertTrue(
                        "Native chrome, control ring, and scene stay frozen",
                        first.sameAs(later),
                    )
                } finally {
                    first.recycle()
                    later.recycle()
                }
            }
        } finally {
            main { view.release() }
        }
    }

    @Test
    fun canonicalSceneStaysFrozenAcrossRedraws() {
        val scene = ShowcaseScene.load(instrumentation.targetContext)
        assertEquals(8, scene.snapshot.tanks.size)
        assertEquals(53, scene.snapshot.bullets.size)
        assertEquals(10, scene.snapshot.pickups.size)
        assertEquals(4, scene.snapshot.effects.size)
        assertEquals(14383, scene.maze.seed)
        assertEquals(.036, scene.effectAges[1]!!, 1e-9)
        assertTrue(
            "Missing homing targets do not target hero ID zero",
            scene.snapshot.bullets.all { it.target == -1 },
        )
        val view = main { NativeArenaView(instrumentation.targetContext) }
        try {
            main {
                val art = NativeArt().apply { assertTrue(prepare()) }
                NativeArenaView::class
                    .java
                    .getDeclaredField("art")
                    .apply { isAccessible = true }
                    .set(view, art)
                view.showFrozenScene(
                    scene.snapshot,
                    scene.maze,
                    scene.localID,
                    scene.time,
                    scene.effectAges,
                    scene.outlines,
                    scene.trails,
                )
            }
            for ((width, height) in listOf(1000 to 1600, 1600 to 1000)) {
                val first = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                val later = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                try {
                    main {
                        view.layout(0, 0, width, height)
                        view.draw(Canvas(first))
                    }
                    val deadline = SystemClock.elapsedRealtime() + 5000
                    while (
                        main { view.terrainPendingRasters > 0 } &&
                            SystemClock.elapsedRealtime() < deadline
                    ) {
                        SystemClock.sleep(30)
                        main { view.draw(Canvas(first)) }
                    }
                    assertEquals(
                        "Terrain raster warming finishes",
                        0,
                        main { view.terrainPendingRasters },
                    )
                    main {
                        first.eraseColor(0)
                        view.draw(Canvas(first))
                    }
                    SystemClock.sleep(450)
                    main {
                        view.start()
                        view.draw(Canvas(later))
                    }
                    val output =
                        File(instrumentation.targetContext.cacheDir, "showcase-test").apply {
                            mkdirs()
                        }
                    File(output, "$width-first.png").outputStream().use {
                        first.compress(Bitmap.CompressFormat.PNG, 100, it)
                    }
                    File(output, "$width-later.png").outputStream().use {
                        later.compress(Bitmap.CompressFormat.PNG, 100, it)
                    }
                    assertTrue("A redraw cannot advance the staged battle", first.sameAs(later))
                    assertEquals(53, scene.snapshot.bullets.size)
                    assertEquals(505L, scene.snapshot.tick)
                    main {
                        val clock =
                            NativeArenaView::class.java.getDeclaredField("frameTime").run {
                                isAccessible = true
                                getDouble(view)
                            }
                        assertEquals(scene.time, clock, 0.0)
                        assertFalse(view.showControls)
                    }
                } finally {
                    first.recycle()
                    later.recycle()
                }
            }
        } finally {
            main { view.release() }
        }
    }
}
