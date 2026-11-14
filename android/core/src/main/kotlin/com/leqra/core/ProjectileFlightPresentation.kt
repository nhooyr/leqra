package com.leqra.core

import kotlin.math.*

/** Completed server paths fill flights that began and ended between wire snapshots. */
internal class ProjectileFlightPresentation {
    private data class Flight(
        val effect: ArenaEffect,
        val path: ProjectileFlight,
        val start: Double,
        val end: Double,
        var shown: Boolean = false,
    )

    data class Image(val bullets: List<ArenaBullet>, val effects: List<ArenaEffect>)

    private val flights = LinkedHashMap<Int, Flight>()
    private val shown = LinkedHashSet<Int>()
    private val completedIDs = LinkedHashSet<Int>()
    private var highestEffect = 0
    val hasPending: Boolean get() = flights.isNotEmpty()

    fun reset(effects: List<ArenaEffect> = emptyList()) {
        flights.clear()
        shown.clear()
        completedIDs.clear()
        highestEffect = effects.maxOfOrNull { it.id } ?: 0
    }

    fun accept(effects: List<ArenaEffect>, playhead: Double) {
        val baseline = highestEffect
        for (effect in effects) {
            highestEffect = max(highestEffect, effect.id)
            if (effect.id <= baseline) continue
            val path = effect.flight ?: continue
            if (!valid(path) || flights.containsKey(path.id)) continue
            val start = path.startTick / 60
            val end = path.endTick / 60
            if (path.id in shown && playhead >= end) continue
            val grace = path.id !in shown && (end - start < .05 || playhead >= end)
            val visualStart = if (grace) max(start, playhead) else start
            flights[path.id] =
                Flight(effect, path, visualStart, if (grace) visualStart + .05 else end)
            if (flights.size > 128)
                flights.entries.iterator().let {
                    it.next()
                    it.remove()
                }
        }
    }

    fun render(bullets: List<ArenaBullet>, effects: List<ArenaEffect>, playhead: Double): Image {
        if (flights.isEmpty()) {
            for (bullet in bullets) if (bullet.kind == "cannon") remember(bullet.id)
            return Image(
                if (completedIDs.isEmpty()) bullets else bullets.filter { it.id !in completedIDs },
                effects,
            )
        }
        val output = ArrayList<ArenaBullet>(bullets.size + flights.size)
        val completed = ArrayList<ArenaEffect>()
        val supplied = HashSet<Int>()
        val iterator = flights.entries.iterator()
        val poses = HashMap<Int, ArenaBullet>()
        while (iterator.hasNext()) {
            val (_, flight) = iterator.next()
            if (playhead < flight.start) continue
            if (playhead >= flight.end && flight.shown) {
                completed += flight.effect
                completedIDs += flight.path.id
                if (completedIDs.size > 1024)
                    completedIDs.iterator().let {
                        it.next()
                        it.remove()
                    }
                iterator.remove()
                continue
            }
            val alpha =
                if (flight.end > flight.start)
                    ((playhead - flight.start) / (flight.end - flight.start)).coerceIn(0.0, 1.0)
                else 1.0
            val tick = flight.path.startTick + (flight.path.endTick - flight.path.startTick) * alpha
            val points = flight.path.points
            val zeroDuration = flight.path.endTick - flight.path.startTick <= 1e-9
            var index =
                if (zeroDuration) min(points.lastIndex - 1, (alpha * points.lastIndex).toInt())
                else 0
            while (
                !zeroDuration && index < points.lastIndex - 1 && tick > points[index + 1].tick
            ) index++
            val a = points[index]
            val b = points[index + 1]
            val dt = b.tick - a.tick
            val fraction =
                if (zeroDuration) (alpha * points.lastIndex - index).coerceIn(0.0, 1.0)
                else if (dt > 1e-9) ((tick - a.tick) / dt).coerceIn(0.0, 1.0) else 1.0
            poses[flight.path.id] =
                ArenaBullet(
                    id = flight.path.id,
                    owner = flight.path.owner,
                    colorIndex = flight.path.colorIndex,
                    kind = flight.path.kind,
                    x = a.x + (b.x - a.x) * fraction,
                    y = a.y + (b.y - a.y) * fraction,
                    vx = if (dt > 1e-9) (b.x - a.x) * 60 / dt else 0.0,
                    vy = if (dt > 1e-9) (b.y - a.y) * 60 / dt else 0.0,
                    life = max(1.0 / 60, (flight.path.endTick - tick) / 60),
                    bounces = index,
                )
            flight.shown = true
        }
        for (bullet in bullets) {
            if (bullet.id in completedIDs) continue
            if (flights.containsKey(bullet.id)) {
                poses[bullet.id]?.let {
                    output += it
                    supplied += bullet.id
                }
            } else output += bullet
        }
        for ((id, bullet) in poses) if (id !in supplied) output += bullet
        for (bullet in output) if (bullet.kind == "cannon") remember(bullet.id)
        val visibleEffects =
            effects.filter { effect -> effect.flight?.id?.let { it !in flights } ?: true }
        return Image(
            output,
            if (completed.isEmpty()) visibleEffects
            else (visibleEffects + completed).distinctBy { it.id },
        )
    }

    private fun remember(id: Int) {
        shown += id
        if (shown.size > 1024)
            shown.iterator().let {
                it.next()
                it.remove()
            }
    }

    private fun valid(path: ProjectileFlight): Boolean {
        if (
            path.id <= 0 ||
                path.colorIndex !in 0..7 ||
                path.kind !in
                    listOf("regular", "rapid", "scatter", "homing", "grenade", "cannon") ||
                !path.radius.isFinite() ||
                path.radius <= 0 ||
                path.radius > 32 ||
                !path.startTick.isFinite() ||
                !path.endTick.isFinite() ||
                path.startTick < 0 ||
                path.endTick < path.startTick ||
                path.endTick - path.startTick > 600 ||
                path.points.size !in 2..32
        )
            return false
        if (
            abs(path.points.first().tick - path.startTick) > 1e-6 ||
                abs(path.points.last().tick - path.endTick) > 1e-6
        )
            return false
        var previous = path.startTick
        for (point in path.points) {
            if (
                !point.x.isFinite() ||
                    !point.y.isFinite() ||
                    !point.tick.isFinite() ||
                    point.tick < previous ||
                    point.tick > path.endTick
            )
                return false
            previous = point.tick
        }
        return true
    }
}
