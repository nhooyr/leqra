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
    fun firePressAimsBeforeTheFirstProjectileInBothLayouts() {
        main {
            for (fixed in listOf(false, true)) {
                for ((width, height) in listOf(1000 to 1600, 1600 to 1000)) {
                    for ((dx, dy) in listOf(32f to 0f, -32f to 0f, 0f to -32f, 0f to 32f)) {
                        val world = if (fixed) ArenaWorld(840.0, 840.0) else null
                        val arena = PracticeArena(42, "Pilot", 0, 0, world = world)
                        arena.configure(
                            RoomRules(
                                infinity = !fixed,
                                infinityRandomBots = false,
                                pickupRate = "off",
                            ),
                        )
                        arena.snapshot.tanks.first().apply {
                            angle = .71
                            spawnProtected = false
                            invulnerable = 0.0
                        }
                        arena.snapshot.world = world
                        val view = NativeArenaView(instrumentation.targetContext)
                        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                        try {
                            view.layout(0, 0, width, height)
                            view.submit(arena.snapshot, arena.localID, arena.maze)
                            view.draw(Canvas(bitmap))
                            val density = view.resources.displayMetrics.density
                            fun coordinate(name: String) =
                                NativeArenaView::class.java.getDeclaredField(name).run {
                                    isAccessible = true
                                    getFloat(view)
                                }
                            var received: GameInput? = null
                            view.onInput = { received = it }
                            val now = SystemClock.uptimeMillis()
                            val event =
                                MotionEvent.obtain(
                                    now,
                                    now,
                                    MotionEvent.ACTION_DOWN,
                                    (coordinate("fireX") + dx) * density,
                                    (coordinate("fireY") + dy) * density,
                                    0,
                                )
                            try {
                                assertTrue(view.onTouchEvent(event))
                            } finally {
                                event.recycle()
                            }
                            val input = requireNotNull(received)
                            assertTrue("The first input already fires", input.fire)
                            assertEquals((dx / 32).toDouble(), input.aimX, 1e-6)
                            assertEquals((dy / 32).toDouble(), input.aimY, 1e-6)
                            arena.step(input, 1.0 / 60)
                            val shot = arena.snapshot.bullets.single()
                            assertEquals(input.aimX * 282, shot.vx, 1e-6)
                            assertEquals(input.aimY * 282, shot.vy, 1e-6)
                        } finally {
                            bitmap.recycle()
                            view.release()
                        }
                    }
                }
            }
        }
    }

    @Test
    fun unlabelledControlsFitBothLayoutsAndLargeText() {
        main {
            val base = instrumentation.targetContext
            for (scale in listOf(1f, 1.5f)) {
                val configuration =
                    android.content.res.Configuration(base.resources.configuration).apply {
                        fontScale = scale
                    }
                val context = base.createConfigurationContext(configuration)
                val view = NativeArenaView(context)
                try {
                    for ((w, h) in listOf(1000 to 1600, 1600 to 1000)) {
                        val image = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                        try {
                            view.layout(0, 0, w, h)
                            view.submit(
                                ArenaSnapshot(
                                    tanks = listOf(ArenaTank(id = 1, x = 200.0, y = 200.0)),
                                    world = ArenaWorld(756.0, 588.0),
                                ),
                                1,
                                InfiniteMaze(ArenaWorld(756.0, 588.0)),
                            )
                            view.draw(Canvas(image))
                            fun field(name: String) =
                                NativeArenaView::class.java.getDeclaredField(name).apply {
                                    isAccessible = true
                                }
                            val stick = field("stickY").getFloat(view)
                            val viewport =
                                field("controlViewport").get(view) as android.graphics.RectF
                            assertEquals(
                                "Caption space is reclaimed at every font scale",
                                63f,
                                viewport.bottom - stick,
                                .01f,
                            )
                            assertTrue(
                                "Fully lowered knob and outline fit",
                                stick + 29 + 22 + .75f <= viewport.bottom - 8,
                            )
                            assertTrue(
                                "Fire ring and outline fit",
                                stick + 53.5f + 1.25f <= viewport.bottom - 8,
                            )
                        } finally {
                            image.recycle()
                        }
                    }
                } finally {
                    view.release()
                }
            }
        }
    }

    @Test
    fun pairedPortraitArenaUsesBothPanesWithoutALoadoutGap() {
        main {
            val view = NativeArenaView(instrumentation.targetContext)
            val image = Bitmap.createBitmap(1000, 1600, Bitmap.Config.ARGB_8888)
            try {
                view.layout(0, 0, 1000, 1600)
                val density = view.resources.displayMetrics.density
                val middle = image.height / density / 2
                view.submit(
                    ArenaSnapshot(
                        tanks =
                            listOf(
                                ArenaTank(id = 1, x = 42.0, y = 42.0),
                                ArenaTank(id = 2, x = 500.0, y = 500.0),
                            ),
                    ),
                    1,
                    InfiniteMaze(137),
                    2,
                )
                view.draw(Canvas(image))
                fun field(name: String) =
                    NativeArenaView::class.java.getDeclaredField(name).apply { isAccessible = true }
                val controls = field("controlViewport").get(view) as android.graphics.RectF
                assertEquals(middle, controls.bottom, .01f)
                val mouseTankY = field("mouseTankY").getFloat(view)
                assertEquals((middle + image.height / density) / 2, mouseTankY, .01f)
            } finally {
                image.recycle()
                view.release()
            }
        }
    }

    @Test
    fun controlCaptionsAreAbsentAndTargetIsCentered() {
        main {
            val view = NativeArenaView(instrumentation.targetContext)
            try {
                for ((width, height) in listOf(1000 to 1600, 1600 to 1000)) for (label in
                    listOf("FIRE", "WAIT", "BOOM")) {
                    val image = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    try {
                        view.layout(0, 0, width, height)
                        view.fireLabel = label
                        view.submit(
                            ArenaSnapshot(tanks = listOf(ArenaTank(id = 1))),
                            1,
                            InfiniteMaze(137),
                        )
                        view.draw(Canvas(image))
                        fun coordinate(name: String) =
                            NativeArenaView::class.java.getDeclaredField(name).run {
                                isAccessible = true
                                getFloat(view)
                            }
                        val density = view.resources.displayMetrics.density
                        val stickX = coordinate("stickX")
                        val fireX = coordinate("fireX")
                        val fireY = coordinate("fireY")
                        fun textBottom(x: Float, color: Int): Int {
                            var bottom = -1
                            for (py in
                                ((fireY + 56) * density).toInt() until image.height) for (px in
                                ((x - 38) * density).toInt()..((x + 38) * density).toInt()) {
                                if (px in 0 until image.width && image.getPixel(px, py) == color)
                                    bottom = maxOf(bottom, py)
                            }
                            return bottom
                        }
                        val steering = textBottom(stickX, 0xff9babbb.toInt())
                        val firing =
                            textBottom(
                                fireX,
                                if (label == "BOOM") 0xffffc46b.toInt() else 0xff40d5ff.toInt(),
                            )
                        assertEquals("No STEER caption", -1, steering)
                        assertEquals("No $label caption", -1, firing)
                        val crossX = ((fireX + 9f) * density).toInt()
                        val crossY = (fireY * density).toInt()
                        assertEquals(
                            "Target's horizontal stroke is centered vertically",
                            0xff32c5ff.toInt(),
                            image.getPixel(crossX, crossY),
                        )
                    } finally {
                        image.recycle()
                    }
                }
            } finally {
                view.release()
            }
        }
    }

    @Test
    fun finitePiercingGuidesContinuePastTheFirstOpponent() {
        main {
            val world = ArenaWorld(756.0, 588.0)
            val maze = InfiniteMaze(world)
            for (kind in listOf("laser", "cannon", "")) {
                val view = NativeArenaView(instrumentation.targetContext)
                val image = Bitmap.createBitmap(1000, 1600, Bitmap.Config.ARGB_8888)
                try {
                    view.layout(0, 0, 1000, 1600)
                    view.showControls = false
                    val state =
                        ArenaSnapshot(
                            tanks =
                                listOf(
                                    ArenaTank(
                                        id = 1,
                                        x = 200.0,
                                        y = 200.0,
                                        power = kind,
                                        powerTime = 10.0,
                                    ),
                                    ArenaTank(id = 2, x = 250.0, y = 200.0),
                                ),
                            world = world,
                        )
                    view.submit(state, 1, maze)
                    view.draw(Canvas(image))
                    val path =
                        NativeArenaView::class.java.getDeclaredField("guidePath").run {
                            isAccessible = true
                            get(view) as android.graphics.Path
                        }
                    val bounds = android.graphics.RectF()
                    path.computeBounds(bounds, true)
                    val zoom =
                        NativeArenaView::class.java.getDeclaredField("zoom").run {
                            isAccessible = true
                            getFloat(view)
                        }
                    assertEquals(
                        "$kind guide reaches beyond victim",
                        kind.isNotEmpty(),
                        bounds.width() > 60 * zoom,
                    )
                } finally {
                    view.release()
                    image.recycle()
                }
            }
        }
    }

    @Test
    fun nearbyCallsignLabelsStayReadableWithoutOverlapping() {
        main {
            val view = NativeArenaView(instrumentation.targetContext)
            try {
                for ((width, height) in listOf(1000 to 1600, 1600 to 1000)) {
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    try {
                        view.layout(0, 0, width, height)
                        view.showControls = false
                        val world = ArenaWorld(504.0, 504.0, 6, 6)
                        val state =
                            ArenaSnapshot(
                                world = world,
                                tanks =
                                    listOf(
                                        ArenaTank(
                                            id = 1,
                                            name = "ALPHA LONG NAME",
                                            x = 250.0,
                                            y = 440.0,
                                        ),
                                        ArenaTank(
                                            id = 2,
                                            name = "BRAVO LONG NAME",
                                            x = 290.0,
                                            y = 440.0,
                                            colorIndex = 1,
                                        ),
                                        ArenaTank(
                                            id = 3,
                                            name = "CHARLIE LONG",
                                            x = 270.0,
                                            y = 420.0,
                                            colorIndex = 2,
                                        ),
                                    ),
                            )
                        view.submit(state, 1, InfiniteMaze(world), 2)
                        view.draw(Canvas(bitmap))
                        val field =
                            NativeArenaView::class.java.getDeclaredField("identityBounds").apply {
                                isAccessible = true
                            }
                        @Suppress("UNCHECKED_CAST")
                        val boxes = field.get(view) as List<android.graphics.RectF>
                        assertEquals(3, boxes.size)
                        for (first in boxes.indices) for (second in 0 until first) {
                            assertFalse(
                                "Callsign labels overlap at ${width}x$height",
                                android.graphics.RectF.intersects(boxes[first], boxes[second]),
                            )
                        }
                    } finally {
                        bitmap.recycle()
                    }
                }
            } finally {
                view.release()
            }
        }
    }

    @Test
    fun nearTankTouchSnapsAimWithoutDrivingInEitherOrientation() {
        main {
            val view = NativeArenaView(instrumentation.targetContext)
            fun field(name: String) =
                NativeArenaView::class.java.getDeclaredField(name).apply { isAccessible = true }
            fun touch(action: Int, x: Float, y: Float) {
                val now = SystemClock.uptimeMillis()
                MotionEvent.obtain(now, now, action, x, y, 0).let {
                    view.onTouchEvent(it)
                    it.recycle()
                }
            }
            try {
                for ((width, height) in listOf(1000 to 1600, 1600 to 1000)) {
                    val image = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    try {
                        val tank = ArenaTank(id = 1, x = 42.0, y = 42.0)
                        view.layout(0, 0, width, height)
                        view.submit(ArenaSnapshot(tanks = listOf(tank)), 1, InfiniteMaze(137))
                        view.draw(Canvas(image))
                        val density = view.resources.displayMetrics.density
                        val x = field("aimTankX").getFloat(view) * density
                        val y = field("aimTankY").getFloat(view) * density
                        touch(MotionEvent.ACTION_DOWN, x + 30 * density, y)
                        assertTrue(view.input.snapAim)
                        assertTrue(view.input.aimOnly)
                        assertEquals(1.0, view.input.stickX, 1e-6)
                        assertEquals(0.0, view.input.stickY, 1e-6)
                        touch(MotionEvent.ACTION_MOVE, x, y - 30 * density)
                        assertEquals(0.0, view.input.stickX, 1e-6)
                        assertEquals(-1.0, view.input.stickY, 1e-6)
                        val startX = tank.x
                        val startY = tank.y
                        TankMovement.step(tank, view.input, 1.0 / 60, InfiniteMaze(137))
                        assertEquals(startX, tank.x, 0.0)
                        assertEquals(startY, tank.y, 0.0)
                        assertEquals(-kotlin.math.PI / 2, tank.angle, 1e-6)
                        touch(MotionEvent.ACTION_UP, x, y - 30 * density)
                        view.clearDirectAim()
                        assertFalse(view.input.snapAim)
                        assertFalse(view.input.aimOnly)
                    } finally {
                        image.recycle()
                    }
                }
            } finally {
                view.release()
            }
        }
    }

    @Test
    fun fastRapidTracersKeepTheirTemporalLengthAndHeadSizeAcrossViewportEdges() {
        main {
            val view = NativeArenaView(instrumentation.targetContext)
            val image = Bitmap.createBitmap(1000, 1600, Bitmap.Config.ARGB_8888)
            val tank = ArenaTank(id = 1, x = 0.0, y = 0.0)
            val bullet =
                ArenaBullet(
                    id = 10,
                    x = 90.0,
                    y = 42.0,
                    vx = 846.0,
                    vy = 0.0,
                    kind = "rapid",
                    colorIndex = 1,
                )
            val state = ArenaSnapshot(tick = 1, tanks = listOf(tank), bullets = listOf(bullet))
            fun field(name: String) =
                NativeArenaView::class.java.getDeclaredField(name).apply { isAccessible = true }
            try {
                view.layout(0, 0, image.width, image.height)
                view.showControls = false
                fun draw() {
                    image.eraseColor(0)
                    view.submit(state, 1, null)
                    view.draw(Canvas(image))
                }
                draw()
                val batch = (field("rapidBatches").get(view) as Array<*>)[1]!!
                fun batchField(name: String) =
                    batch.javaClass.getDeclaredField(name).apply { isAccessible = true }
                val heads = batchField("heads").get(batch) as FloatArray
                val tails = batchField("tails").get(batch) as FloatArray
                val head = heads.copyOf(2)
                assertEquals(
                    8.0,
                    kotlin.math.hypot(
                        (tails[2] - tails[0]).toDouble(),
                        (tails[3] - tails[1]).toDouble(),
                    ),
                    1e-6,
                )
                val scale = field("zoom").getFloat(view) * view.resources.displayMetrics.density
                val centerX = (image.width / 2 + bullet.x * scale).toInt()
                val centerY = (image.height / 2 + bullet.y * scale).toInt()
                fun headPixels() =
                    (centerY - 3..centerY + 3).flatMap { y ->
                        (centerX - 1..centerX + 4).map { x ->
                            image.getPixel(x, y) == ArenaPalette.tank(1)
                        }
                    }
                val ordinaryHead = headPixels()
                bullet.vx = 1692.0
                // Tail appearance follows the projectile's birth velocity even after Star ends.
                assertEquals(0.0, tank.starmanTime, 0.0)
                draw()
                assertSame(
                    "Steady batching reuses its head buffer",
                    heads,
                    batchField("heads").get(batch),
                )
                assertSame(
                    "Steady batching reuses its tail buffer",
                    tails,
                    batchField("tails").get(batch),
                )
                assertArrayEquals(head, heads.copyOf(2), 0f)
                assertEquals(
                    16.0,
                    kotlin.math.hypot(
                        (tails[2] - tails[0]).toDouble(),
                        (tails[3] - tails[1]).toDouble(),
                    ),
                    1e-6,
                )
                assertEquals(
                    "The solid rapid head does not grow when its anti-aliased tail length changes",
                    ordinaryHead,
                    headPixels(),
                )
                val right = field("worldRight").getDouble(view)
                bullet.x = right + 8
                fun edgeInk(speed: Double): Int {
                    bullet.vx = speed
                    draw()
                    var ink = 0
                    for (x in image.width - 25 until image.width) for (y in
                        centerY - 8..centerY + 8) {
                        val color = image.getPixel(x, y)
                        if (
                            android.graphics.Color.red(color) > 100 &&
                                android.graphics.Color.red(color) >
                                    android.graphics.Color.green(color) * 1.4 &&
                                android.graphics.Color.blue(color) > 60
                        )
                            ink++
                    }
                    return ink
                }
                val ordinaryEdge = edgeInk(846.0)
                assertTrue(
                    "A fast tracer whose head is outside the pane remains visible across the edge",
                    edgeInk(1692.0) > ordinaryEdge + 10,
                )
            } finally {
                view.release()
                image.recycle()
            }
        }
    }

    @Test
    fun fastRapidTracersStopAtRicochetWallsWithoutDrawingInTheNextRoom() {
        main {
            val view = NativeArenaView(instrumentation.targetContext)
            val image = Bitmap.createBitmap(1000, 1600, Bitmap.Config.ARGB_8888)
            val world =
                ArenaWorld(336.0, 336.0, 4, 4, listOf(MazeWall(160.0, 0.0, 8.0, 336.0, "v", 164.0)))
            val bullet =
                ArenaBullet(
                    id = 10,
                    x = 154.0,
                    y = 200.0,
                    vx = -846.0,
                    vy = 0.0,
                    kind = "rapid",
                    colorIndex = 1,
                    bounces = 1,
                )
            val state =
                ArenaSnapshot(
                    tick = 1,
                    world = world,
                    tanks = listOf(ArenaTank(id = 1, x = 80.0, y = 84.0)),
                    bullets = listOf(bullet),
                )
            fun field(name: String) =
                NativeArenaView::class.java.getDeclaredField(name).apply { isAccessible = true }
            try {
                view.layout(0, 0, image.width, image.height)
                view.showControls = false
                fun otherRoomInk(speed: Double): Int {
                    bullet.vx = -speed
                    image.eraseColor(0)
                    view.submit(state, 1, InfiniteMaze(world))
                    view.draw(Canvas(image))
                    val viewport = field("viewport").get(view) as android.graphics.RectF
                    val scale = field("zoom").getFloat(view) * view.resources.displayMetrics.density
                    val density = view.resources.displayMetrics.density
                    val cameraX = field("cameraX").getDouble(view)
                    val cameraY = field("cameraY").getDouble(view)
                    fun screenX(x: Double) =
                        (viewport.centerX() * density + (x - cameraX) * scale).toInt()
                    fun screenY(y: Double) =
                        (viewport.centerY() * density + (y - cameraY) * scale).toInt()
                    var ink = 0
                    for (x in screenX(169.0)..screenX(172.0)) for (y in
                        screenY(196.0)..screenY(204.0)) {
                        val color = image.getPixel(x, y)
                        if (
                            android.graphics.Color.red(color) > 100 &&
                                android.graphics.Color.red(color) >
                                    android.graphics.Color.green(color) * 1.4 &&
                                android.graphics.Color.blue(color) > 60
                        )
                            ink++
                    }
                    return ink
                }
                assertEquals(
                    "The existing8px rapid streak does not cross the8px wall",
                    0,
                    otherRoomInk(846.0),
                )
                assertEquals(
                    "The16px fast streak must stop before the ricochet wall",
                    0,
                    otherRoomInk(1692.0),
                )
            } finally {
                view.release()
                image.recycle()
            }
        }
    }

    @Test
    fun separatedInfinityPilotsKeepTheirOwnViewportThroughDeathRespawnAndRotation() {
        main {
            val view = NativeArenaView(instrumentation.targetContext)
            val first = ArenaTank(id = 1, name = "First", x = 33_600_042.125, y = -33_600_042.125)
            val second =
                ArenaTank(
                    id = 2,
                    name = "Second",
                    x = -33_600_070.875,
                    y = 33_600_070.875,
                    colorIndex = 1,
                )
            val state =
                ArenaSnapshot(
                    tick = 1,
                    tanks = listOf(first, second),
                    bullets =
                        listOf(
                            ArenaBullet(
                                id = 10,
                                x = first.x + 35,
                                y = first.y,
                                vx = 100.0,
                                vy = 0.0,
                            ),
                            ArenaBullet(
                                id = 11,
                                x = second.x + 35,
                                y = second.y,
                                vx = 100.0,
                                vy = 0.0,
                                colorIndex = 1,
                            ),
                        ),
                )
            try {
                for ((w, h) in listOf(1000 to 1600, 1600 to 1000)) {
                    val landscape = w > h
                    second.x = -33_600_070.875
                    second.y = 33_600_070.875
                    val image = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                    try {
                        view.layout(0, 0, w, h)
                        view.showControls = false
                        fun draw() {
                            image.eraseColor(0)
                            view.submit(state, 1, InfiniteMaze(137), 2)
                            view.draw(Canvas(image))
                        }
                        fun ink(pilot: Int): Int {
                            val cx = if (landscape) if (pilot == 1) w / 4 else w * 3 / 4 else w / 2
                            val cy = if (!landscape) if (pilot == 1) h / 4 else h * 3 / 4 else h / 2
                            val color = ArenaPalette.tank(pilot - 1)
                            var count = 0
                            for (y in cy - 35..cy + 35) for (x in cx - 35..cx + 35) if (
                                image.getPixel(x, y) == color
                            )
                                count++
                            return count
                        }
                        second.hp = 1
                        draw()
                        assertTrue("P1 is centered in its own pane", ink(1) > 30)
                        assertTrue("P2 is centered in its distant own pane", ink(2) > 30)
                        val history =
                            NativeArenaView::class
                                .java
                                .getDeclaredField("projectileHistory")
                                .apply { isAccessible = true }
                                .get(view) as android.util.SparseArray<*>
                        assertEquals(
                            "The second pane must not prune the first pane's projectile history",
                            2,
                            history.size(),
                        )
                        second.hp = 0
                        draw()
                        assertTrue(ink(1) > 30)
                        assertEquals(
                            "Dead P2 keeps its pane without drawing a living hull",
                            0,
                            ink(2),
                        )
                        second.hp = 1
                        second.spawnSerial++
                        second.x += 12345
                        second.y -= 12345
                        draw()
                        assertTrue("Respawn follows P2's new pose", ink(2) > 30)
                        view.showControls = true
                        view.draw(Canvas(image))
                        val density = view.resources.displayMetrics.density
                        fun touch(action: Int, x: Float, y: Float) {
                            val now = SystemClock.uptimeMillis()
                            MotionEvent.obtain(now, now, action, x, y, 0).let {
                                view.onTouchEvent(it)
                                it.recycle()
                            }
                        }
                        touch(MotionEvent.ACTION_DOWN, w * .8f, h * .8f)
                        assertFalse("P2 pane touches cannot fire P1", view.input.fire)
                        touch(MotionEvent.ACTION_UP, w * .8f, h * .8f)
                        val fireX =
                            NativeArenaView::class
                                .java
                                .getDeclaredField("fireX")
                                .apply { isAccessible = true }
                                .getFloat(view) * density
                        val fireY =
                            NativeArenaView::class
                                .java
                                .getDeclaredField("fireY")
                                .apply { isAccessible = true }
                                .getFloat(view) * density
                        touch(MotionEvent.ACTION_DOWN, fireX, fireY)
                        assertTrue("P1's visible Fire button works after rotation", view.input.fire)
                        touch(MotionEvent.ACTION_UP, fireX, fireY)
                        assertFalse(view.input.fire)
                        view.submit(state, 1, InfiniteMaze(137))
                        view.showControls = false
                        view.draw(Canvas(image))
                        assertTrue(
                            "Removing P2 returns P1 to one full viewport",
                            image.getPixel(w / 2, h / 2) != 0,
                        )
                    } finally {
                        image.recycle()
                    }
                }
            } finally {
                view.release()
            }
        }
    }

    @Test
    fun offscreenEffectSourcesStillRenderLasersAndBlastRingsCrossingTheViewportEdge() {
        main {
            val view = NativeArenaView(instrumentation.targetContext)
            val image = Bitmap.createBitmap(1000, 1600, Bitmap.Config.ARGB_8888)
            val clock =
                NativeArenaView::class.java.getDeclaredField("frameTime").apply {
                    isAccessible = true
                }
            fun coordinate(name: String) =
                NativeArenaView::class
                    .java
                    .getDeclaredField(name)
                    .apply { isAccessible = true }
                    .getDouble(view)
            try {
                view.layout(0, 0, 1000, 1600)
                view.showControls = false
                clock.setDouble(view, 100.0)
                val state =
                    ArenaSnapshot(tick = 1, tanks = listOf(ArenaTank(id = 1, x = 0.0, y = 0.0)))
                view.submit(state, 1, null)
                view.draw(Canvas(image))
                val left = coordinate("worldLeft")
                val baseline = IntArray(image.width * image.height)
                image.getPixels(baseline, 0, image.width, 0, 0, image.width, image.height)
                state.effects =
                    listOf(
                        ArenaEffect(
                            id = 10,
                            kind = "laser",
                            x = left - 100,
                            y = 0.0,
                            points = listOf(BeamPoint(left - 100, 0.0), BeamPoint(left + 150, 0.0)),
                        ),
                        ArenaEffect(id = 11, kind = "blast", x = left - 50, y = 150.0),
                    )
                view.submit(state, 1, null)
                clock.setDouble(view, 100.12)
                image.eraseColor(0)
                view.draw(Canvas(image))
                var laser = 0
                var blast = 0
                val density = view.resources.displayMetrics.density
                val zoom =
                    NativeArenaView::class
                        .java
                        .getDeclaredField("zoom")
                        .apply { isAccessible = true }
                        .getFloat(view)
                val blastCenterY = image.height / 2 + 150 * zoom * density
                for (x in 0..30) for (y in 0 until image.height) if (
                    image.getPixel(x, y) != baseline[y * image.width + x]
                ) {
                    if (kotlin.math.abs(y - image.height / 2) < 30) laser++
                    if (kotlin.math.abs(y - blastCenterY) < 150) blast++
                }
                assertTrue("A laser with an offscreen source crosses the clipped edge", laser > 20)
                assertTrue(
                    "A blast with an offscreen center retains its visible expanding ring",
                    blast > 20,
                )
            } finally {
                view.release()
                image.recycle()
            }
        }
    }

    @Test
    fun pairedInfinityDrawingReportsItsMeasuredCostWithoutDoubleCountingFrames() {
        main {
            val view = NativeArenaView(instrumentation.targetContext)
            val image = Bitmap.createBitmap(1000, 1600, Bitmap.Config.ARGB_8888)
            val state =
                ArenaSnapshot(
                    tick = 1,
                    tanks =
                        (0..25).map { i ->
                            ArenaTank(
                                id = i + 1,
                                name = "Tank$i",
                                x = if (i % 2 == 0) (i % 5) * 44.0 else 10000 + (i % 5) * 44.0,
                                y = (i % 6) * 44.0,
                                colorIndex = i % 8,
                                power = "rapid",
                                powerTime = 10.0,
                                machineRounds = 180,
                            )
                        },
                    bullets =
                        (0..150).map { i ->
                            ArenaBullet(
                                id = i + 100,
                                x = if (i % 2 == 0) i % 300.0 else 10000 + i % 300.0,
                                y = i % 200.0,
                                vx = 500.0,
                                vy = 0.0,
                                kind = "rapid",
                            )
                        },
                )
            try {
                view.layout(0, 0, 1000, 1600)
                view.showControls = false
                val report = ArrayList<String>()
                for (paired in listOf(false, true)) {
                    view.submit(state, 1, InfiniteMaze(137), if (paired) 2 else null)
                    repeat(15) { view.draw(Canvas(image)) }
                    val before = view.renderedFrames
                    val costs =
                        (0 until 80)
                            .map {
                                view.draw(Canvas(image))
                                view.lastRenderNanos
                            }
                            .sorted()
                    assertEquals(80, view.renderedFrames - before)
                    report +=
                        "paired=$paired softwareCanvasMs p50=${costs[40] / 1e6} p95=${costs[76] / 1e6} max=${costs.last() / 1e6}"
                }
                java.io
                    .File(instrumentation.targetContext.cacheDir, "paired-viewport-benchmark.txt")
                    .writeText(report.joinToString("\n"))
            } finally {
                view.release()
                image.recycle()
            }
        }
    }

    @Test
    fun powerCountsKeepTheirBackingWidthAndHaveABlackOutlineAtEveryZoom() {
        main {
            val view = NativeArenaView(instrumentation.targetContext)
            val image = Bitmap.createBitmap(400, 400, Bitmap.Config.ARGB_8888)
            val reference = Bitmap.createBitmap(400, 400, Bitmap.Config.ARGB_8888)
            val draw =
                NativeArenaView::class
                    .java
                    .getDeclaredMethod(
                        "drawBadges",
                        Canvas::class.java,
                        ArenaTank::class.java,
                        Boolean::class.javaPrimitiveType,
                    )
                    .apply { isAccessible = true }
            val zoom =
                NativeArenaView::class.java.getDeclaredField("zoom").apply { isAccessible = true }
            val outline =
                (NativeArenaView::class
                    .java
                    .getDeclaredField("countOutlinePaint")
                    .apply { isAccessible = true }
                    .get(view) as android.graphics.Paint)
            fun assertOutline(tank: ArenaTank, pixels: IntArray) {
                reference.eraseColor(android.graphics.Color.TRANSPARENT)
                outline.style = android.graphics.Paint.Style.FILL
                draw.invoke(view, Canvas(reference), tank, true)
                outline.style = android.graphics.Paint.Style.STROKE
                assertEquals(android.graphics.Color.BLACK, outline.color)
                val plain = IntArray(pixels.size)
                reference.getPixels(plain, 0, 400, 0, 0, 400, 400)
                assertTrue(
                    "Thin black stroke adds dark edges around${tank.power.ifEmpty { "buff" }} count",
                    pixels.indices.any {
                        android.graphics.Color.alpha(pixels[it]) > 200 &&
                            android.graphics.Color.green(pixels[it]) + 3 <
                                android.graphics.Color.green(plain[it])
                    },
                )
            }
            try {
                for (scale in listOf(.7f, 1f, 1.2f, 2f)) {
                    zoom.setFloat(view, scale)
                    var bounds: List<Int>? = null
                    for (rounds in listOf(180, 179, 100, 99, 10, 9)) {
                        image.eraseColor(android.graphics.Color.TRANSPARENT)
                        val tank =
                            ArenaTank(
                                id = 1,
                                x = 100.0,
                                y = 100.0,
                                power = "rapid",
                                powerTime = 10.0,
                                machineRounds = rounds,
                            )
                        draw.invoke(view, Canvas(image), tank, true)
                        val pixels = IntArray(400 * 400)
                        image.getPixels(pixels, 0, 400, 0, 0, 400, 400)
                        val ink =
                            pixels.indices.filter { android.graphics.Color.alpha(pixels[it]) > 0 }
                        val current =
                            listOf(
                                ink.minOf { it % 400 },
                                ink.minOf { it / 400 },
                                ink.maxOf { it % 400 },
                                ink.maxOf { it / 400 },
                            )
                        if (bounds == null) bounds = current
                        else
                            assertEquals(
                                "Ammo width cannot jump when digit count changes",
                                bounds,
                                current,
                            )
                        assertOutline(tank, pixels)
                        assertTrue(
                            "White count fill at zoom$scale",
                            pixels.any {
                                android.graphics.Color.alpha(it) > 240 &&
                                    android.graphics.Color.red(it) > 210 &&
                                    android.graphics.Color.green(it) > 220 &&
                                    android.graphics.Color.blue(it) > 230
                            },
                        )
                    }
                    for (kind in
                        listOf(
                            "scatter",
                            "homing",
                            "grenade",
                            "laser",
                            "cannon",
                            "shield",
                            "speed",
                        )) {
                        image.eraseColor(android.graphics.Color.TRANSPARENT)
                        val tank =
                            ArenaTank(
                                id = 1,
                                x = 100.0,
                                y = 100.0,
                                power = kind,
                                powerTime = 10.0,
                                charges = 3,
                            )
                        if (kind == "shield") {
                            tank.power = ""
                            tank.shield = 10.0
                            tank.shieldCharges = 2
                        }
                        if (kind == "speed") {
                            tank.power = ""
                            tank.speedTime = 10.0
                            tank.speedStacks = 5
                        }
                        draw.invoke(view, Canvas(image), tank, true)
                        val pixels = IntArray(400 * 400)
                        image.getPixels(pixels, 0, 400, 0, 0, 400, 400)
                        assertOutline(tank, pixels)
                    }
                }
            } finally {
                view.release()
                image.recycle()
                reference.recycle()
            }
        }
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
