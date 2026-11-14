package com.leqra.core

import kotlin.math.*

/** Fixed 60 Hz movement, with a continuous Hermite display path between ticks. */
object TankMovement {
    fun angleDelta(a: Double, b: Double) = atan2(sin(a - b), cos(a - b))

    private fun smoothStep(value: Double): Double {
        val x = value.coerceIn(0.0, 1.0)
        return x * x * (3 - 2 * x)
    }

    data class Steering(val angle: Double, val throttle: Double)

    fun steer(angle: Double, input: GameInput, turnScale: Double = 1.0, dt: Double): Steering {
        var a = angle
        var throttle = (if (input.forward) 1.0 else 0.0) - (if (input.reverse) .72 else 0.0)
        val magnitude = hypot(input.stickX, input.stickY)
        if (magnitude > .1) {
            val desired = atan2(input.stickY, input.stickX)
            val difference = angleDelta(desired, a)
            var rate = 5.8
            if (input.touchAim && !input.aimOnly)
                rate +=
                    3.2 *
                        smoothStep((min(magnitude, 1.0) - .35) / .65) *
                        smoothStep((abs(difference) - PI / 12) / (PI / 2 - PI / 12))
            val limit = rate * turnScale * dt
            a += difference.coerceIn(-limit, limit)
            if (!input.aimOnly) throttle = min(1.0, magnitude) * max(0.0, cos(difference))
        } else
            a +=
                ((if (input.right) 1.0 else 0.0) - (if (input.left) 1.0 else 0.0)) *
                    3.65 *
                    turnScale *
                    dt
        return Steering(atan2(sin(a), cos(a)), throttle)
    }

    fun step(tank: ArenaTank, input: GameInput, dt: Double, maze: InfiniteMaze) {
        if (maze.world != null) {
            step(tank, input, dt, maze.world.walls, maze.world.width, maze.world.height)
            return
        }
        if (!dt.isFinite() || dt <= 0 || dt > .1 || tank.hp <= 0) return
        equipment(tank, dt) {
            val p = maze.phaseExit(tank.x, tank.y)
            tank.x = p.x
            tank.y = p.y
        }
        val stacks = if (tank.speedTime > 0) tank.speedStacks.coerceIn(1, 5) else 0
        val steering = steer(tank.angle, input, 1 + .25 * stacks, dt)
        tank.angle = steering.angle
        val speed = 128 * (1 + .65 * stacks)
        val oldX = tank.x
        val oldY = tank.y
        val dx = cos(tank.angle) * speed * steering.throttle * dt
        val dy = sin(tank.angle) * speed * steering.throttle * dt
        if (tank.ghostTime > 0 || !maze.blocked(tank.x + dx, tank.y, 17.0)) tank.x += dx
        if (tank.ghostTime > 0 || !maze.blocked(tank.x, tank.y + dy, 17.0)) tank.y += dy
        tank.track += hypot(tank.x - oldX, tank.y - oldY)
    }

    private inline fun equipment(t: ArenaTank, dt: Double, finishGhost: () -> Unit) {
        t.speedTime = max(0.0, t.speedTime - dt)
        if (t.speedTime <= 0) t.speedStacks = 0
        val ghost = t.ghostTime > 0
        t.ghostTime = max(0.0, t.ghostTime - dt)
        if (ghost && t.ghostTime == 0.0) finishGhost()
    }

    fun step(
        tank: ArenaTank,
        input: GameInput,
        dt: Double,
        walls: List<MazeWall>,
        width: Double,
        height: Double,
    ) {
        if (!dt.isFinite() || dt <= 0 || dt > .1 || tank.hp <= 0 || width < 42 || height < 42)
            return
        equipment(tank, dt) { finishGhost(tank, walls, width, height) }
        val stacks = if (tank.speedTime > 0) tank.speedStacks.coerceIn(1, 5) else 0
        val steering = steer(tank.angle, input, 1 + .25 * stacks, dt)
        tank.angle = steering.angle
        val speed = 128 * (1 + .65 * stacks)
        val x = tank.x
        val y = tank.y
        tank.x += cos(tank.angle) * speed * steering.throttle * dt
        if (tank.ghostTime == 0.0) resolveWalls(tank, walls)
        tank.y += sin(tank.angle) * speed * steering.throttle * dt
        if (tank.ghostTime == 0.0) resolveWalls(tank, walls)
        tank.x = tank.x.coerceIn(21.0, width - 21)
        tank.y = tank.y.coerceIn(21.0, height - 21)
        tank.track += hypot(tank.x - x, tank.y - y)
    }

    private fun resolveWalls(t: ArenaTank, walls: List<MazeWall>) {
        repeat(2) {
            for (w in walls) {
                val dx = t.x - t.x.coerceIn(w.x, w.x + w.w)
                val dy = t.y - t.y.coerceIn(w.y, w.y + w.h)
                val d2 = dx * dx + dy * dy
                if (d2 >= 289) continue
                if (d2 > .000001) {
                    val d = sqrt(d2)
                    val push = 17 - d + .002
                    t.x += dx / d * push
                    t.y += dy / d * push
                } else {
                    val edges = listOf(t.x - w.x, w.x + w.w - t.x, t.y - w.y, w.y + w.h - t.y)
                    val edge = edges.indices.minBy { edges[it] }
                    val push = edges[edge] + 17 + .002
                    when (edge) {
                        0 -> t.x -= push
                        1 -> t.x += push
                        2 -> t.y -= push
                        else -> t.y += push
                    }
                }
            }
        }
    }

    fun displace(tank: ArenaTank, dx: Double, dy: Double, world: ArenaWorld) {
        tank.x += dx
        if (tank.ghostTime <= 0) resolveWalls(tank, world.walls)
        tank.y += dy
        if (tank.ghostTime <= 0) resolveWalls(tank, world.walls)
        tank.x = tank.x.coerceIn(21.0, world.width - 21)
        tank.y = tank.y.coerceIn(21.0, world.height - 21)
    }

    fun stepBot(tank: ArenaTank, input: GameInput, dt: Double, world: ArenaWorld) {
        if (dt <= 0 || dt > .1 || tank.hp <= 0) return
        equipment(tank, dt) { finishGhost(tank, world.walls, world.width, world.height) }
        val tuning = BotDifficulty.from(tank.difficulty)
        val stacks = if (tank.speedTime > 0) tank.speedStacks.coerceIn(1, 5) else 0
        var throttle = 0.0
        val magnitude = hypot(input.stickX, input.stickY)
        if (magnitude > .1) {
            val difference = angleDelta(atan2(input.stickY, input.stickX), tank.angle)
            val limit = tuning.turn * (1 + .25 * stacks) * dt
            tank.angle += difference.coerceIn(-limit, limit)
            if (!input.aimOnly) throttle = min(1.0, magnitude) * max(0.0, cos(difference))
        }
        tank.angle = atan2(sin(tank.angle), cos(tank.angle))
        val speed = tuning.speed * (1 + .65 * stacks)
        val x = tank.x
        val y = tank.y
        displace(
            tank,
            cos(tank.angle) * speed * throttle * dt,
            sin(tank.angle) * speed * throttle * dt,
            world,
        )
        tank.track += hypot(tank.x - x, tank.y - y)
    }

    private fun finishGhost(t: ArenaTank, walls: List<MazeWall>, width: Double, height: Double) {
        fun clear(x: Double, y: Double) =
            x >= 21 &&
                x <= width - 21 &&
                y >= 21 &&
                y <= height - 21 &&
                !walls.any {
                    hypot(x - x.coerceIn(it.x, it.x + it.w), y - y.coerceIn(it.y, it.y + it.h)) <
                        17.0001
                }
        if (clear(t.x, t.y)) return
        var best = Double.POSITIVE_INFINITY
        var px = t.x
        var py = t.y
        for (row in 0 until (height / 84).toInt()) for (col in 0 until (width / 84).toInt()) {
            val x = t.x.coerceIn(col * 84 + 21.01, (col + 1) * 84 - 21.01)
            val y = t.y.coerceIn(row * 84 + 21.01, (row + 1) * 84 - 21.01)
            val distance = (x - t.x).pow(2) + (y - t.y).pow(2)
            if (distance < best - 1e-8 && clear(x, y)) {
                best = distance
                px = x
                py = y
            }
        }
        if (best.isFinite()) {
            t.x = px
            t.y = py
        } else resolveWalls(t, walls)
    }

    fun presentationFitsBounds(tank: ArenaTank, world: ArenaWorld?) =
        tank.x.isFinite() &&
            tank.y.isFinite() &&
            (world == null ||
                (tank.x >= 21 &&
                    tank.x <= world.width - 21 &&
                    tank.y >= 21 &&
                    tank.y <= world.height - 21))

    fun presentation(
        tank: ArenaTank,
        input: GameInput,
        fraction: Double,
        previous: ArenaTank? = null,
        move: (ArenaTank, GameInput, Double) -> Unit,
        canInterpolate: (ArenaTank, ArenaTank) -> Boolean = { _, _ -> true },
    ): ArenaTank {
        if (!fraction.isFinite() || fraction <= 0 || tank.hp <= 0) return tank.copy()
        val alpha = min(1.0, fraction)
        val tick = 1.0 / 60
        val next = tank.copy()
        move(next, input, tick)
        if (
            tank.spawnSerial != next.spawnSerial ||
                tank.hp != next.hp ||
                (tank.ghostTime > 0) != (next.ghostTime > 0) ||
                hypot(next.x - tank.x, next.y - tank.y) > 84 ||
                !canInterpolate(tank, next)
        )
            return tank.copy().also { move(it, input, alpha * tick) }
        if (tank.speedStacks != next.speedStacks || (tank.speedTime > 0) != (next.speedTime > 0))
            return tank.copy(
                x = tank.x + (next.x - tank.x) * alpha,
                y = tank.y + (next.y - tank.y) * alpha,
                angle = tank.angle + angleDelta(next.angle, tank.angle) * alpha,
                track = tank.track + (next.track - tank.track) * alpha,
            )
        var future = next.copy()
        move(future, input, tick)
        if (
            future.spawnSerial != next.spawnSerial ||
                future.hp != next.hp ||
                (future.ghostTime > 0) != (next.ghostTime > 0) ||
                hypot(future.x - next.x, future.y - next.y) > 84
        )
            future =
                next.copy(
                    x = next.x * 2 - tank.x,
                    y = next.y * 2 - tank.y,
                    angle = next.angle + angleDelta(next.angle, tank.angle),
                )
        val prior = previous?.takeIf {
            it.spawnSerial == tank.spawnSerial &&
                it.hp == tank.hp &&
                (it.ghostTime > 0) == (tank.ghostTime > 0) &&
                it.speedStacks == tank.speedStacks &&
                hypot(it.x - tank.x, it.y - tank.y) <= 84 &&
                canInterpolate(it, tank)
        }
        fun curve(
            first: Double,
            last: Double,
            start: Double,
            end: Double,
            monotone: Boolean = false,
        ): Double {
            val delta = last - first
            var a = start
            var b = end
            if (monotone) {
                if (abs(delta) <= 1e-12) return first
                a = max(0.0, a / delta)
                b = max(0.0, b / delta)
                val magnitude = hypot(a, b)
                if (magnitude > 3) {
                    a *= 3 / magnitude
                    b *= 3 / magnitude
                }
                a *= delta
                b *= delta
            }
            val t2 = alpha * alpha
            val t3 = t2 * alpha
            return first + delta * (-2 * t3 + 3 * t2) + (t3 - 2 * t2 + alpha) * a + (t3 - t2) * b
        }
        val result = tank.copy()
        if (hypot(next.x - tank.x, next.y - tank.y) > 1e-10) {
            val ax = prior?.let { (next.x - it.x) / 2 } ?: (4 * next.x - 3 * tank.x - future.x) / 2
            val ay = prior?.let { (next.y - it.y) / 2 } ?: (4 * next.y - 3 * tank.y - future.y) / 2
            if (abs(next.x - tank.x) > 1e-10 || abs(future.x - next.x) > 1e-10)
                result.x = curve(tank.x, next.x, ax, (future.x - tank.x) / 2)
            if (abs(next.y - tank.y) > 1e-10 || abs(future.y - next.y) > 1e-10)
                result.y = curve(tank.y, next.y, ay, (future.y - tank.y) / 2)
        }
        val angle = angleDelta(next.angle, tank.angle)
        val futureAngle = angleDelta(future.angle, next.angle)
        val angleStart =
            prior?.let { (angleDelta(tank.angle, it.angle) + angle) / 2 }
                ?: (3 * angle - futureAngle) / 2
        result.angle = tank.angle + curve(0.0, angle, angleStart, (angle + futureAngle) / 2, true)
        result.track = tank.track + (next.track - tank.track) * alpha
        if (!canInterpolate(tank, result)) {
            result.x = tank.x + (next.x - tank.x) * alpha
            result.y = tank.y + (next.y - tank.y) * alpha
        }
        return result
    }
}

enum class BotDifficulty(val speed: Double, val turn: Double, val think: Double) {
    DUMB(60.0, 1.8, .9),
    EASY(89.0, 2.8, .30),
    NORMAL(108.0, 3.4, .19),
    HARD(123.0, 4.3, .13),
    GODLIKE(123.0, 4.3, .075);

    companion object {
        val names = listOf("dumb", "easy", "normal", "hard", "godlike")

        fun from(value: String) = entries.firstOrNull { it.name.equals(value, true) } ?: NORMAL

        fun index(value: String) = names.indexOf(value).takeIf { it >= 0 } ?: names.indexOf("normal")
    }
}

/** Bounded visual corrections keep analog control changes continuous at 120 Hz. */
class TankMotionPresenter {
    private data class State(
        var source: ArenaTank,
        var previous: ArenaTank?,
        val input: GameInput,
        val tick: Long,
        val generation: Int,
        val fraction: Double,
        var x: Double = 0.0,
        var y: Double = 0.0,
        var angle: Double = 0.0,
    )

    private var state: State? = null

    fun reset() {
        state = null
    }

    fun rebase(dx: Double, dy: Double, angle: Double) {
        state?.let {
            it.source =
                it.source.copy(
                    x = it.source.x + dx,
                    y = it.source.y + dy,
                    angle = it.source.angle + angle,
                )
            it.previous =
                it.previous?.let { p ->
                    p.copy(x = p.x + dx, y = p.y + dy, angle = p.angle + angle)
                }
        }
    }

    fun present(
        tank: ArenaTank,
        input: GameInput,
        tick: Long,
        generation: Int = 0,
        fraction: Double,
        move: (ArenaTank, GameInput, Double) -> Unit,
        canInterpolate: (ArenaTank, ArenaTank) -> Boolean = { _, _ -> true },
    ): ArenaTank {
        if (!fraction.isFinite() || fraction < 0 || tank.hp <= 0) {
            reset()
            return tank.copy()
        }
        val f = min(1.0, fraction)
        val old = state
        val preceding =
            old?.takeIf {
                    generation == it.generation &&
                        tank.spawnSerial == it.source.spawnSerial &&
                        tank.hp == it.source.hp
                }
                ?.let {
                    if (tick == it.tick) it.previous
                    else if (tick == it.tick + 1) it.source else null
                }
        val raw = TankMovement.presentation(tank, input, f, preceding, move, canInterpolate)
        val controls = input.copy(seq = 0, fire = false)
        val next = State(tank.copy(), preceding?.copy(), controls, tick, generation, f)
        if (old != null) {
            val ticks = tick - old.tick
            val elapsed = (ticks + f - old.fraction) / 60
            val same =
                generation == old.generation &&
                    tank.spawnSerial == old.source.spawnSerial &&
                    tank.hp == old.source.hp &&
                    (tank.ghostTime > 0) == (old.source.ghostTime > 0) &&
                    (raw.ghostTime > 0) == (tank.ghostTime > 0)
            if (same && elapsed >= 0 && elapsed <= .1 && ticks in 0..6) {
                val fade = exp(-elapsed / .04)
                next.x = old.x * fade
                next.y = old.y * fade
                next.angle = old.angle * fade
                if (ticks > 0 || controls != old.input) {
                    var expected = old.source.copy()
                    var before = old.previous
                    repeat(ticks.toInt()) {
                        before = expected.copy()
                        move(expected, old.input, 1.0 / 60)
                    }
                    if (hypot(expected.x - tank.x, expected.y - tank.y) <= 42) {
                        expected =
                            TankMovement.presentation(
                                expected,
                                old.input,
                                f,
                                before,
                                move,
                                canInterpolate,
                            )
                        next.x += expected.x - raw.x
                        next.y += expected.y - raw.y
                        next.angle += TankMovement.angleDelta(expected.angle, raw.angle)
                    } else {
                        next.x = 0.0
                        next.y = 0.0
                        next.angle = 0.0
                    }
                }
                val limit = 128 * (1 + .65 * 5) / 60
                val length = hypot(next.x, next.y)
                if (length > limit) {
                    next.x *= limit / length
                    next.y *= limit / length
                }
                next.angle = next.angle.coerceIn(-.3375, .3375)
            }
        }
        var result =
            raw.copy(x = raw.x + next.x, y = raw.y + next.y, angle = raw.angle + next.angle)
        if (!canInterpolate(tank, result)) {
            next.x = 0.0
            next.y = 0.0
            next.angle = 0.0
            result = raw
        }
        state = next
        return result
    }
}
