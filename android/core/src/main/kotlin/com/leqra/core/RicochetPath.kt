package com.leqra.core

import kotlin.math.abs
import kotlin.math.hypot

/** Read-only visual path, accepted only when real wall queries reproduce both snapshots. */
internal class RicochetPath
private constructor(private val segments: List<Segment>, private val duration: Double) {
    private data class Segment(
        val time: Double,
        val duration: Double,
        val x: Double,
        val y: Double,
        val vx: Double,
        val vy: Double,
        val bounces: Int,
    )

    fun sample(template: ArenaBullet, first: ArenaBullet, alpha: Double): ArenaBullet {
        if (alpha >= 1) return template.copy()
        val time = duration * alpha.coerceIn(0.0, 1.0)
        val segment =
            segments.firstOrNull { time <= it.time + it.duration + 1e-9 } ?: segments.last()
        val elapsed = (time - segment.time).coerceIn(0.0, segment.duration)
        return template.copy(
            x = segment.x + segment.vx * elapsed,
            y = segment.y + segment.vy * elapsed,
            vx = segment.vx,
            vy = segment.vy,
            bounces = segment.bounces,
            life = first.life - time,
        )
    }

    companion object {
        fun between(
            first: ArenaBullet,
            second: ArenaBullet,
            duration: Double,
            maze: InfiniteMaze?,
        ): RicochetPath? {
            if (
                maze == null ||
                    duration <= 0 ||
                    duration > .1 ||
                    first.id != second.id ||
                    first.kind != second.kind ||
                    first.owner != second.owner ||
                    second.bounces - first.bounces !in 1..4 ||
                    first.kind in listOf("homing", "grenade", "laser") ||
                    first.life < duration ||
                    abs(first.life - second.life - duration) > .025
            )
                return null
            val segments = ArrayList<Segment>(5)
            val radius = PracticeArena.spec(first.kind).radius
            val nudge = if (maze.world == null) .12 else .08
            var x = first.x
            var y = first.y
            var vx = first.vx
            var vy = first.vy
            var elapsed = 0.0
            var remaining = duration
            var bounces = first.bounces
            var reflections = 0
            while (remaining > 1e-9 && reflections < 4) {
                val wall =
                    maze.projectileHit(first.kind, x, y, vx * remaining, vy * remaining, radius)
                val span = remaining * (wall?.fraction ?: 1.0)
                segments.add(Segment(elapsed, span, x, y, vx, vy, bounces))
                x += vx * span
                y += vy * span
                remaining -= span
                elapsed += span
                if (wall == null) break
                x += wall.nx * nudge
                y += wall.ny * nudge
                if (wall.nx != 0.0) vx = -vx
                if (wall.ny != 0.0) vy = -vy
                bounces++
                reflections++
            }
            if (
                remaining > 1e-9 ||
                    bounces != second.bounces ||
                    hypot(x - second.x, y - second.y) > .5 ||
                    hypot(vx - second.vx, vy - second.vy) > .5
            )
                return null
            return RicochetPath(segments, duration)
        }
    }
}
