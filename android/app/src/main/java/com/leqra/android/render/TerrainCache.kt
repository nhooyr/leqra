package com.leqra.android.render

import android.graphics.*
import com.leqra.core.*
import java.util.concurrent.Executors
import kotlin.math.*

/** World-space artwork stays immutable while camera movement changes only a GPU transform. */
internal class TerrainCache(
    private val beforeRaster: (() -> Unit)? = null,
    private val invalidate: () -> Unit,
) {
    private data class Key(val x: Int, val y: Int)

    private val executor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "leqra-map").apply { isDaemon = true }
    }
    private val images = LinkedHashMap<Key, Bitmap>(32, .75f, true)
    private val pending = HashSet<Key>()
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val fallbackPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val destination = RectF()
    private var maze: InfiniteMaze? = null
    private var workerMaze: InfiniteMaze? = null
    private var world: ArenaWorld? = null
    private var fixedImage: Bitmap? = null
    private var fixedPending = false
    private var epoch = 0
    private var visibleLeft = 0
    private var visibleRight = -1
    private var visibleTop = 0
    private var visibleBottom = -1
    @Volatile
    var tilesBuilt: Long = 0
        private set

    @Volatile
    var fallbackDraws: Long = 0
        private set

    val cachedBytes: Long
        get() =
            synchronized(this) {
                (fixedImage?.allocationByteCount?.toLong() ?: 0L) +
                    images.values.sumOf { it.allocationByteCount.toLong() }
            }

    val pendingRasters: Int
        get() = synchronized(this) { pending.size + if (fixedPending) 1 else 0 }

    private var closed = false

    fun configure(geometry: InfiniteMaze?, fixedWorld: ArenaWorld?) {
        if (maze?.seed == geometry?.seed && maze?.world == geometry?.world && world == fixedWorld)
            return
        synchronized(this) {
            maze = geometry
            world = fixedWorld
            // Procedural chunk caches are mutable and belong to one thread.
            workerMaze = if (fixedWorld == null) geometry?.let { InfiniteMaze(it.seed) } else null
            epoch++
            images.clear()
            pending.clear()
            fixedImage = null
            fixedPending = false
        }
        if (fixedWorld != null) requestFixed(fixedWorld)
    }

    fun draw(canvas: Canvas, left: Float, top: Float, right: Float, bottom: Float) =
        draw(canvas, left.toDouble(), top.toDouble(), right.toDouble(), bottom.toDouble())

    fun draw(
        canvas: Canvas,
        left: Double,
        top: Double,
        right: Double,
        bottom: Double,
        originX: Double = 0.0,
        originY: Double = 0.0,
    ) {
        val fixed = world
        if (fixed != null) {
            val image = synchronized(this) { fixedImage }
            if (image != null) {
                destination.set(
                    (-originX).toFloat(),
                    (-originY).toFloat(),
                    (fixed.width - originX).toFloat(),
                    (fixed.height - originY).toFloat(),
                )
                canvas.drawBitmap(image, null, destination, paint)
            } else {
                fallbackDraws++
                // Never show a blank arena during a round change or texture upload.
                drawRegion(
                    canvas,
                    0.0,
                    0.0,
                    fixed.width.toFloat(),
                    fixed.height.toFloat(),
                    fixed.walls,
                    true,
                    fallbackPaint,
                    originX,
                    originY,
                )
                requestFixed(fixed)
            }
            return
        }
        val x0 = floor(left / TILE).toInt()
        val x1 = floor(right / TILE).toInt()
        val y0 = floor(top / TILE).toInt()
        val y1 = floor(bottom / TILE).toInt()
        synchronized(this) {
            visibleLeft = x0
            visibleRight = x1
            visibleTop = y0
            visibleBottom = y1
        }
        for (y in y0..y1) for (x in x0..x1) {
            val key = Key(x, y)
            val image = synchronized(this) { images[key] }
            if (image != null) {
                destination.set(
                    (x * TILE.toDouble() - originX).toFloat(),
                    (y * TILE.toDouble() - originY).toFloat(),
                    ((x + 1) * TILE.toDouble() - originX).toFloat(),
                    ((y + 1) * TILE.toDouble() - originY).toFloat(),
                )
                canvas.drawBitmap(image, null, destination, paint)
            } else {
                fallbackDraws++
                val wx = x * TILE.toDouble()
                val wy = y * TILE.toDouble()
                val walls =
                    maze?.walls(
                        wx.toDouble() - 8,
                        wy.toDouble() - 8,
                        wx.toDouble() + TILE + 8,
                        wy.toDouble() + TILE + 8,
                    ) ?: emptyList()
                canvas.save()
                canvas.clipRect(
                    (wx - originX).toFloat(),
                    (wy - originY).toFloat(),
                    (wx + TILE - originX).toFloat(),
                    (wy + TILE - originY).toFloat(),
                )
                drawRegion(
                    canvas,
                    wx,
                    wy,
                    TILE,
                    TILE,
                    walls,
                    false,
                    fallbackPaint,
                    originX,
                    originY,
                )
                canvas.restore()
                request(key)
            }
        }
        // One cell of lookahead exceeds the distance covered by Speed x5 during raster work.
        for (x in x0..x1) {
            request(Key(x, y0 - 1))
            request(Key(x, y1 + 1))
        }
        for (y in y0..y1) {
            request(Key(x0 - 1, y))
            request(Key(x1 + 1, y))
        }
    }

    private fun awaitRaster(): Boolean =
        try {
            beforeRaster?.invoke()
            !Thread.currentThread().isInterrupted
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        }

    private fun requestFixed(fixed: ArenaWorld) {
        val version: Int
        synchronized(this) {
            if (closed || fixedPending || fixedImage != null || world !== fixed) return
            fixedPending = true
            version = epoch
        }
        executor.execute {
            if (!awaitRaster()) return@execute
            // Match iOS's finite map cap: all six map sizes fit one <=20 MB raster.
            val ratio =
                min(1.5, sqrt(MAX_FIXED_PIXELS / (fixed.width * fixed.height).coerceAtLeast(1.0)))
            val image =
                rasterize(
                    0.0,
                    0.0,
                    fixed.width.toFloat(),
                    fixed.height.toFloat(),
                    fixed.walls,
                    true,
                    ratio,
                )
            val installed =
                synchronized(this) {
                    if (version == epoch && !closed) {
                        fixedImage = image
                        fixedPending = false
                        tilesBuilt++
                        true
                    } else false
                }
            if (installed) invalidate() else image.recycle()
        }
    }

    private fun request(key: Key) {
        val version: Int
        val geometry: InfiniteMaze?
        synchronized(this) {
            if (
                closed ||
                    world != null ||
                    images.containsKey(key) ||
                    pending.contains(key) ||
                    pending.size >= 24
            )
                return
            // Prefetch must not displace a visible map tile on a wide display.
            if (images.size >= MAX_TILES && !isVisible(key) && images.keys.all(::isVisible)) return
            pending += key
            version = epoch
            geometry = workerMaze
        }
        executor.execute {
            if (!awaitRaster()) return@execute
            val x = key.x * TILE.toDouble()
            val y = key.y * TILE.toDouble()
            val walls =
                geometry?.walls(
                    x.toDouble() - 8,
                    y.toDouble() - 8,
                    x.toDouble() + TILE + 8,
                    y.toDouble() + TILE + 8,
                ) ?: emptyList()
            val image = rasterize(x, y, TILE, TILE, walls, false, 1.5)
            val installed =
                synchronized(this) {
                    if (version == epoch && !closed) {
                        pending -= key
                        while (images.size >= MAX_TILES) {
                            val eviction = images.keys.firstOrNull { !isVisible(it) }
                            if (eviction == null && !isVisible(key)) break
                            images.remove(eviction ?: images.keys.first())
                        }
                        if (images.size < MAX_TILES) {
                            images[key] = image
                            tilesBuilt++
                            true
                        } else false
                    } else false
                }
            if (installed) invalidate() else image.recycle()
        }
    }

    private fun isVisible(key: Key) =
        key.x in visibleLeft..visibleRight && key.y in visibleTop..visibleBottom

    private fun rasterize(
        x: Double,
        y: Double,
        width: Float,
        height: Float,
        walls: List<MazeWall>,
        fixed: Boolean,
        ratio: Double,
    ): Bitmap {
        val image =
            Bitmap.createBitmap(
                ceil(width * ratio).toInt().coerceAtLeast(1),
                ceil(height * ratio).toInt().coerceAtLeast(1),
                Bitmap.Config.ARGB_8888,
            )
        val canvas = Canvas(image)
        canvas.scale(ratio.toFloat(), ratio.toFloat())
        drawRegion(canvas, x, y, width, height, walls, fixed, Paint(Paint.ANTI_ALIAS_FLAG), x, y)
        return image
    }

    private fun drawRegion(
        c: Canvas,
        x: Double,
        y: Double,
        width: Float,
        height: Float,
        walls: List<MazeWall>,
        fixed: Boolean,
        p: Paint,
        originX: Double,
        originY: Double,
    ) {
        p.style = Paint.Style.FILL
        p.color = 0xff151f25.toInt()
        c.drawRect(
            (x - originX).toFloat(),
            (y - originY).toFloat(),
            (x + width - originX).toFloat(),
            (y + height - originY).toFloat(),
            p,
        )
        for (row in floor(y / 84).toInt() until ceil((y + height) / 84).toInt()) for (col in
            floor(x / 84).toInt() until ceil((x + width) / 84).toInt()) {
            val cx = (col * 84.0 - originX).toFloat()
            val cy = (row * 84.0 - originY).toFloat()
            p.style = Paint.Style.FILL
            p.color = if ((col + row) % 2 == 0) 0xff172128.toInt() else 0xff182229.toInt()
            c.drawRect(cx + 4, cy + 4, cx + 80, cy + 80, p)
            p.style = Paint.Style.STROKE
            p.strokeWidth = 1f
            p.color = 0x09d9e6e8
            c.drawRect(cx + 10, cy + 10, cx + 74, cy + 74, p)
            p.style = Paint.Style.FILL
            p.color = 0x23a5b9b4
            for (dx in DOTS) for (dy in DOTS) c.drawRect(
                cx + dx,
                cy + dy,
                cx + dx + 1.5f,
                cy + dy + 1.5f,
                p,
            )
            p.color = 0x0dc8d9cd
            c.drawRect(cx + 40, cy + 41.5f, cx + 44, cy + 42.5f, p)
            c.drawRect(cx + 41.5f, cy + 40, cx + 42.5f, cy + 44, p)
        }
        for (wall in walls) {
            val wx = (wall.x - originX).toFloat()
            val wy = (wall.y - originY).toFloat()
            val w = wall.w.toFloat()
            val h = wall.h.toFloat()
            p.color = 0xff080e13.toInt()
            c.drawRect(wx + 1, wy + 4, wx + w + 1, wy + h + 6, p)
            p.color = 0xff35434b.toInt()
            c.drawRoundRect(wx, wy, wx + w, wy + h, 2f, 2f, p)
            p.color = 0xff667773.toInt()
            if (wall.axis == "h") c.drawRect(wx + 1, wy + .8f, wx + w - 1, wy + 2f, p)
            else c.drawRect(wx + .8f, wy + 1, wx + 2f, wy + h - 1, p)
        }
        if (fixed) {
            p.color = 0x5c00c8ff
            p.strokeWidth = 2f
            for (index in walls.indices step 17) {
                val wall = walls[index]
                if (wall.axis == "h" && wall.line > 0 && wall.line < y + height)
                    for (mark in 0..2) c.drawLine(
                        (wall.x - originX + 31 + mark * 6).toFloat(),
                        (wall.y - originY + 1).toFloat(),
                        (wall.x - originX + 35 + mark * 6).toFloat(),
                        (wall.y - originY + 6).toFloat(),
                        p,
                    )
            }
        }
    }

    fun clear() {
        synchronized(this) {
            epoch++
            images.clear()
            pending.clear()
            fixedImage = null
            fixedPending = false
        }
    }

    fun release() {
        synchronized(this) {
            closed = true
            epoch++
            images.clear()
            pending.clear()
            fixedImage = null
            fixedPending = false
        }
        executor.shutdownNow()
    }

    companion object {
        private const val TILE = 336f
        private const val MAX_TILES = 32
        private const val MAX_FIXED_PIXELS = 5_000_000.0
        private val DOTS = floatArrayOf(19f, 65f)
    }
}
