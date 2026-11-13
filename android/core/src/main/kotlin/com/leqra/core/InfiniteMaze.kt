package com.leqra.core

import kotlin.math.*

/**
 * Deterministic procedural maze shared with Go, Swift and the browser. Single simulation thread.
 */
class InfiniteMaze private constructor(val seed: Int, val world: ArenaWorld?) {
    constructor(seed: Int) : this(seed, null)

    constructor(world: ArenaWorld) : this(0, world)

    companion object {
        const val cellSize = 84.0
        const val wallSize = 8.0
    }

    private data class Coordinate(val x: Int, val y: Int)

    private val chunks = LinkedHashMap<Coordinate, IntArray>()
    private val fixedBins: Array<MutableList<Int>> =
        Array((world?.cols ?: 0) * (world?.rows ?: 0)) { mutableListOf() }
    private val queryMarks = IntArray(world?.walls?.size ?: 0)
    private val queryIndices = IntArray(world?.walls?.size ?: 0)
    private var queryStamp = 0
    private val hotChunkX = IntArray(4)
    private val hotChunkY = IntArray(4)
    private val hotChunks = arrayOfNulls<IntArray>(4)
    private var hotChunkSlot = 0
    val cachedChunkCount
        get() = chunks.size

    init {
        if (world != null && fixedBins.isNotEmpty())
            world.walls.forEachIndexed { index, wall ->
                val x0 = floor(wall.x / 84).toInt().coerceIn(0, world.cols - 1)
                val x1 = floor((wall.x + wall.w) / 84).toInt().coerceIn(0, world.cols - 1)
                val y0 = floor(wall.y / 84).toInt().coerceIn(0, world.rows - 1)
                val y1 = floor((wall.y + wall.h) / 84).toInt().coerceIn(0, world.rows - 1)
                for (y in y0..y1) for (x in x0..x1) fixedBins[y * world.cols + x].add(index)
            }
    }

    private fun hash(c: Coordinate, salt: Int): Int {
        var n = seed xor (c.x * 0x9e3779b1.toInt()) xor (c.y * 0x85ebca77.toInt()) xor salt
        n = (n xor (n ushr 16)) * 0x7feb352d
        n = (n xor (n ushr 15)) * 0x846ca68b.toInt()
        return n xor (n ushr 16)
    }

    private fun rememberChunk(x: Int, y: Int, cells: IntArray): IntArray {
        hotChunkX[hotChunkSlot] = x
        hotChunkY[hotChunkSlot] = y
        hotChunks[hotChunkSlot] = cells
        hotChunkSlot = (hotChunkSlot + 1) % hotChunks.size
        return cells
    }

    private fun chunk(x: Int, y: Int): IntArray {
        for (index in hotChunks.indices) {
            val cells = hotChunks[index]
            if (cells != null && hotChunkX[index] == x && hotChunkY[index] == y) return cells
        }
        val c = Coordinate(x, y)
        chunks[c]?.let {
            return rememberChunk(x, y, it)
        }
        val cells = IntArray(64) { 3 }
        var state = hash(c, 0x243f6a88).let { if (it == 0) 1 else it }
        fun random(): Int {
            state = state xor (state shl 13)
            state = state xor (state ushr 17)
            state = state xor (state shl 5)
            return state
        }
        fun next(n: Int) = Integer.remainderUnsigned(random(), n)
        val start = next(64)
        val visited = BooleanArray(64)
        visited[start] = true
        val stack = mutableListOf(start)
        while (stack.isNotEmpty()) {
            val cell = stack.last()
            val x = cell % 8
            val y = cell / 8
            val neighbors = ArrayList<Int>(4)
            if (y > 0 && !visited[cell - 8]) neighbors.add(cell - 8)
            if (x < 7 && !visited[cell + 1]) neighbors.add(cell + 1)
            if (y < 7 && !visited[cell + 8]) neighbors.add(cell + 8)
            if (x > 0 && !visited[cell - 1]) neighbors.add(cell - 1)
            if (neighbors.isEmpty()) {
                stack.removeAt(stack.lastIndex)
                continue
            }
            val neighbor = neighbors[next(neighbors.size)]
            when (neighbor - cell) {
                -8 -> cells[cell] = cells[cell] and 1.inv()
                1 -> cells[neighbor] = cells[neighbor] and 2.inv()
                8 -> cells[neighbor] = cells[neighbor] and 1.inv()
                else -> cells[cell] = cells[cell] and 2.inv()
            }
            visited[neighbor] = true
            stack.add(neighbor)
        }
        for (i in cells.indices) {
            if (i >= 8 && cells[i] and 1 != 0 && next(5) == 0) cells[i] = cells[i] and 1.inv()
            if (i % 8 != 0 && cells[i] and 2 != 0 && next(5) == 0) cells[i] = cells[i] and 2.inv()
        }
        val north = hash(c, 0xb7e15162.toInt())
        val west = hash(c, 0x8aed2a6b.toInt())
        cells[1 + Integer.remainderUnsigned(north, 3)] =
            cells[1 + Integer.remainderUnsigned(north, 3)] and 1.inv()
        cells[4 + (north ushr 16) % 3] = cells[4 + (north ushr 16) % 3] and 1.inv()
        cells[(1 + Integer.remainderUnsigned(west, 3)) * 8] =
            cells[(1 + Integer.remainderUnsigned(west, 3)) * 8] and 2.inv()
        cells[(4 + (west ushr 16) % 3) * 8] = cells[(4 + (west ushr 16) % 3) * 8] and 2.inv()
        if (chunks.size == 128) {
            val removed = chunks.remove(chunks.keys.first())
            for (index in hotChunks.indices) if (hotChunks[index] === removed)
                hotChunks[index] = null
        }
        chunks[c] = cells
        return rememberChunk(x, y, cells)
    }

    fun walls(x0: Double, y0: Double, x1: Double, y1: Double): List<MazeWall> {
        val result = ArrayList<MazeWall>()
        visitWalls(x0, y0, x1, y1) { x, y, w, h, axis, line ->
            result.add(MazeWall(x, y, w, h, axis, line))
            false
        }
        return result
    }

    /**
     * The private collision path uses primitives; public geometry is materialized only for artwork.
     */
    private inline fun visitWalls(
        x0: Double,
        y0: Double,
        x1: Double,
        y1: Double,
        visit: (Double, Double, Double, Double, String, Double) -> Boolean,
    ): Boolean {
        if (
            !x0.isFinite() ||
                !y0.isFinite() ||
                !x1.isFinite() ||
                !y1.isFinite() ||
                abs(x0) >= 1e14 ||
                abs(y0) >= 1e14 ||
                abs(x1) >= 1e14 ||
                abs(y1) >= 1e14 ||
                x0 > x1 ||
                y0 > y1 ||
                x1 - x0 >= 84 * 256 ||
                y1 - y0 >= 84 * 256
        )
            return false
        if (world != null) {
            if (fixedBins.isEmpty()) {
                for (w in world.walls) if (
                    w.x <= x1 &&
                        w.x + w.w >= x0 &&
                        w.y <= y1 &&
                        w.y + w.h >= y0 &&
                        visit(w.x, w.y, w.w, w.h, w.axis, w.line)
                )
                    return true
                return false
            }
            val ax = floor(x0 / 84).toInt().coerceIn(0, world.cols - 1)
            val bx = floor(x1 / 84).toInt().coerceIn(0, world.cols - 1)
            val ay = floor(y0 / 84).toInt().coerceIn(0, world.rows - 1)
            val by = floor(y1 / 84).toInt().coerceIn(0, world.rows - 1)
            if (ax == bx && ay == by) {
                val bin = fixedBins[ay * world.cols + ax]
                var slot = 0
                while (slot < bin.size) {
                    val w = world.walls[bin[slot++]]
                    if (
                        w.x <= x1 &&
                            w.x + w.w >= x0 &&
                            w.y <= y1 &&
                            w.y + w.h >= y0 &&
                            visit(w.x, w.y, w.w, w.h, w.axis, w.line)
                    )
                        return true
                }
                return false
            }
            if ((bx - ax + 1) * (by - ay + 1) > world.cols * world.rows / 3) {
                for (w in world.walls) if (
                    w.x <= x1 &&
                        w.x + w.w >= x0 &&
                        w.y <= y1 &&
                        w.y + w.h >= y0 &&
                        visit(w.x, w.y, w.w, w.h, w.axis, w.line)
                )
                    return true
                return false
            }
            // Keep world order, including exact corner-hit ties, without boxed sets or query lists.
            if (queryStamp == Int.MAX_VALUE) {
                queryMarks.fill(0)
                queryStamp = 0
            }
            val stamp = ++queryStamp
            var count = 0
            for (y in ay..by) for (x in ax..bx) for (index in fixedBins[y * world.cols + x]) {
                if (queryMarks[index] != stamp) {
                    queryMarks[index] = stamp
                    queryIndices[count++] = index
                }
            }
            java.util.Arrays.sort(queryIndices, 0, count)
            for (offset in 0 until count) {
                val w = world.walls[queryIndices[offset]]
                if (
                    w.x <= x1 &&
                        w.x + w.w >= x0 &&
                        w.y <= y1 &&
                        w.y + w.h >= y0 &&
                        visit(w.x, w.y, w.w, w.h, w.axis, w.line)
                )
                    return true
            }
            return false
        }
        val ax = ceil((x0 - 4) / 84).toInt() - 1
        val ay = ceil((y0 - 4) / 84).toInt() - 1
        val bx = floor((x1 + 4) / 84).toInt()
        val by = floor((y1 + 4) / 84).toInt()
        for (cy in Math.floorDiv(ay, 8)..Math.floorDiv(by, 8)) for (cx in
            Math.floorDiv(ax, 8)..Math.floorDiv(bx, 8)) {
            val cells = chunk(cx, cy)
            val baseX = cx * 8
            val baseY = cy * 8
            for (y in max(ay, baseY)..min(by, baseY + 7)) for (x in
                max(ax, baseX)..min(bx, baseX + 7)) {
                val bits = cells[(y - baseY) * 8 + x - baseX]
                val wx = x * 84.0
                val wy = y * 84.0
                if (
                    bits and 1 != 0 &&
                        wx - 4 <= x1 &&
                        wx + 88 >= x0 &&
                        wy - 4 <= y1 &&
                        wy + 4 >= y0 &&
                        visit(wx - 4, wy - 4, 92.0, 8.0, "h", wy)
                )
                    return true
                if (
                    bits and 2 != 0 &&
                        wx - 4 <= x1 &&
                        wx + 4 >= x0 &&
                        wy - 4 <= y1 &&
                        wy + 88 >= y0 &&
                        visit(wx - 4, wy - 4, 8.0, 92.0, "v", wx)
                )
                    return true
            }
        }
        return false
    }

    fun blocked(x: Double, y: Double, radius: Double): Boolean {
        if (!x.isFinite() || !y.isFinite() || !radius.isFinite() || radius < 0) return true
        if (
            world != null &&
                (x < 4 + radius ||
                    x > world.width - 4 - radius ||
                    y < 4 + radius ||
                    y > world.height - 4 - radius)
        )
            return true
        return visitWalls(x - radius, y - radius, x + radius, y + radius) { wx, wy, ww, wh, _, _ ->
            val dx = x - x.coerceIn(wx, wx + ww)
            val dy = y - y.coerceIn(wy, wy + wh)
            dx * dx + dy * dy < radius * radius
        }
    }

    fun phaseExit(x: Double, y: Double, radius: Double = 17.0): BeamPoint {
        if (!blocked(x, y, radius)) return BeamPoint(x, y)
        val cx = floor(x / 84).toInt()
        val cy = floor(y / 84).toInt()
        val margin = 4 + radius + .01
        var best = Double.POSITIVE_INFINITY
        var result = BeamPoint(x, y)
        for (row in cy - 1..cy + 1) for (col in cx - 1..cx + 1) {
            val xx = x.coerceIn(col * 84 + margin, (col + 1) * 84 - margin)
            val yy = y.coerceIn(row * 84 + margin, (row + 1) * 84 - margin)
            val d = hypot(xx - x, yy - y)
            if (d < best - 1e-8) {
                best = d
                result = BeamPoint(xx, yy)
            }
        }
        return result
    }

    data class RayHit(var fraction: Double, var nx: Double, var ny: Double)

    data class LaunchRay(
        var x: Double,
        var y: Double,
        var ux: Double,
        var uy: Double,
        var distance: Double = 0.0,
        var bounced: Boolean = false,
    )

    fun isMuzzleBlocked(x: Double, y: Double, kind: String, radius: Double): Boolean {
        if (kind == "cannon") return false
        if (!x.isFinite() || !y.isFinite() || !radius.isFinite() || radius < 0) return true
        if (
            world != null &&
                (x < 4 + radius ||
                    x > world.width - 4 - radius ||
                    y < 4 + radius ||
                    y > world.height - 4 - radius)
        )
            return true
        return visitWalls(x - radius, y - radius, x + radius, y + radius) { wx, wy, ww, wh, _, _ ->
            x >= wx - radius && x <= wx + ww + radius && y >= wy - radius && y <= wy + wh + radius
        }
    }

    fun launchRay(x: Double, y: Double, angle: Double, kind: String, radius: Double): LaunchRay? {
        if (!listOf(x, y, angle, radius).all { it.isFinite() } || radius < 0) return null
        val ux = cos(angle)
        val uy = sin(angle)
        val original = LaunchRay(x, y, ux, uy)
        if (kind == "cannon") return original
        val overlap =
            walls(x - radius, y - radius, x + radius, y + radius).filter {
                x >= it.x - radius &&
                    x <= it.x + it.w + radius &&
                    y >= it.y - radius &&
                    y <= it.y + it.h + radius
            }
        if (overlap.isEmpty() && !isMuzzleBlocked(x, y, kind, radius)) return original
        val xs = mutableListOf(x)
        val ys = mutableListOf(y)
        for (w in overlap) {
            xs.add(w.x - radius - .12)
            xs.add(w.x + w.w + radius + .12)
            ys.add(w.y - radius - .12)
            ys.add(w.y + w.h + radius + .12)
        }
        xs.sort()
        ys.sort()
        var best: LaunchRay? = null
        var squaredBest = Double.POSITIVE_INFINITY
        for (ax in xs) for (ay in ys) {
            val dx = ax - x
            val dy = ay - y
            val squared = dx * dx + dy * dy
            if (
                squared > 1024 + 1e-7 ||
                    dx * ux + dy * uy > 1e-7 ||
                    isMuzzleBlocked(ax, ay, kind, radius)
            )
                continue
            val old = best
            if (
                old != null &&
                    (squared > squaredBest + 1e-7 ||
                        abs(squared - squaredBest) <= 1e-7 &&
                            (ax > old.x || ax == old.x && ay >= old.y))
            )
                continue
            val nx = sign(dx)
            val ny = sign(dy)
            best =
                LaunchRay(
                    ax,
                    ay,
                    if (ux * nx < -1e-9) -ux else ux,
                    if (uy * ny < -1e-9) -uy else uy,
                    sqrt(squared),
                    true,
                )
            squaredBest = squared
        }
        return best
    }

    fun rayHit(x: Double, y: Double, dx: Double, dy: Double, radius: Double): RayHit? {
        var nearest: RayHit? = null
        visitWalls(
            min(x, x + dx) - radius,
            min(y, y + dy) - radius,
            max(x, x + dx) + radius,
            max(y, y + dy) + radius,
        ) { wx, wy, ww, wh, _, _ ->
            val minX = wx - radius
            val maxX = wx + ww + radius
            val minY = wy - radius
            val maxY = wy + wh + radius
            var tx1 = Double.NEGATIVE_INFINITY
            var tx2 = Double.POSITIVE_INFINITY
            var ty1 = Double.NEGATIVE_INFINITY
            var ty2 = Double.POSITIVE_INFINITY
            if (abs(dx) < 1e-9) {
                if (x < minX || x > maxX) return@visitWalls false
            } else {
                tx1 = min((minX - x) / dx, (maxX - x) / dx)
                tx2 = max((minX - x) / dx, (maxX - x) / dx)
            }
            if (abs(dy) < 1e-9) {
                if (y < minY || y > maxY) return@visitWalls false
            } else {
                ty1 = min((minY - y) / dy, (maxY - y) / dy)
                ty2 = max((minY - y) / dy, (maxY - y) / dy)
            }
            val enter = max(tx1, ty1)
            val exit = min(tx2, ty2)
            if (enter > exit || exit < 0 || enter > 1 || enter < -.0001) return@visitWalls false
            val nx = if (abs(tx1 - ty1) < 1e-7 || tx1 > ty1) if (dx > 0) -1.0 else 1.0 else 0.0
            val ny = if (abs(tx1 - ty1) < 1e-7 || ty1 > tx1) if (dy > 0) -1.0 else 1.0 else 0.0
            val old = nearest
            if (old == null || enter < old.fraction - 1e-7)
                nearest = RayHit(max(0.0, enter), nx, ny)
            else if (abs(enter - old.fraction) < 1e-7) {
                if (nx != 0.0) old.nx = nx
                if (ny != 0.0) old.ny = ny
            }
            false
        }
        return nearest
    }

    fun projectileHit(
        kind: String,
        x: Double,
        y: Double,
        dx: Double,
        dy: Double,
        radius: Double,
    ): RayHit? {
        if (kind != "cannon") return rayHit(x, y, dx, dy, radius)
        val w = world ?: return null
        var best: RayHit? = null
        fun consider(at: Double, nx: Double, ny: Double) {
            if (at < -1e-7 || at > 1 + 1e-7) return
            val t = at.coerceIn(0.0, 1.0)
            val old = best
            if (old == null || t < old.fraction - 1e-7) best = RayHit(t, nx, ny)
            else if (abs(t - old.fraction) < 1e-7) {
                if (nx != 0.0) old.nx = nx
                if (ny != 0.0) old.ny = ny
            }
        }
        val margin = 4 + radius
        if (dx > 1e-9) consider((w.width - margin - x) / dx, -1.0, 0.0)
        else if (dx < -1e-9) consider((margin - x) / dx, 1.0, 0.0)
        if (dy > 1e-9) consider((w.height - margin - y) / dy, 0.0, -1.0)
        else if (dy < -1e-9) consider((margin - y) / dy, 0.0, 1.0)
        return best
    }

    fun segmentBlocked(x: Double, y: Double, dx: Double, dy: Double): Boolean =
        visitWalls(min(x, x + dx), min(y, y + dy), max(x, x + dx), max(y, y + dy)) {
            wx,
            wy,
            ww,
            wh,
            _,
            _ ->
            var enter = Double.NEGATIVE_INFINITY
            var exit = Double.POSITIVE_INFINITY
            if (abs(dx) < 1e-9) {
                if (x < wx || x > wx + ww) return@visitWalls false
            } else {
                val a = (wx - x) / dx
                val b = (wx + ww - x) / dx
                enter = max(enter, min(a, b))
                exit = min(exit, max(a, b))
            }
            if (abs(dy) < 1e-9) {
                if (y < wy || y > wy + wh) return@visitWalls false
            } else {
                val a = (wy - y) / dy
                val b = (wy + wh - y) / dy
                enter = max(enter, min(a, b))
                exit = min(exit, max(a, b))
            }
            enter <= exit && exit >= 0 && enter <= 1
        }

    fun laserGuide(
        x: Double,
        y: Double,
        angle: Double,
        range: Double = 18 * 84.0,
        radius: Double = 3.0,
        maxSegments: Int = 128,
    ) = projectileGuide(x, y, angle, "laser", range, radius, maxSegments)

    fun projectileGuide(
        x: Double,
        y: Double,
        angle: Double,
        kind: String,
        range: Double,
        radius: Double,
        maxSegments: Int = 128,
    ): List<BeamPoint> {
        if (!listOf(x, y, angle, range, radius).all { it.isFinite() } || range <= 0 || radius < 0)
            return emptyList()
        val launch = launchRay(x, y, angle, kind, radius) ?: return emptyList()
        var xx = launch.x
        var yy = launch.y
        var ux = launch.ux
        var uy = launch.uy
        var remaining = max(0.0, min(range, 20000.0) - launch.distance)
        val points = mutableListOf<BeamPoint>()
        for (i in 0 until maxSegments.coerceIn(0, 128)) {
            val wall = projectileHit(kind, xx, yy, ux * remaining, uy * remaining, radius)
            val length = remaining * (wall?.fraction ?: 1.0)
            if (i == 0) {
                val crop = if (launch.bounced) 0.0 else 28.0
                points.add(BeamPoint(xx + ux * min(crop, length), yy + uy * min(crop, length)))
            }
            xx += ux * length
            yy += uy * length
            remaining -= length
            points.add(BeamPoint(xx, yy))
            if (wall == null || remaining <= 1e-7) break
            if (wall.nx != 0.0) ux = -ux
            if (wall.ny != 0.0) uy = -uy
            val nudge = min(.001, remaining)
            xx += ux * nudge
            yy += uy * nudge
            remaining -= nudge
        }
        return points
    }
}
