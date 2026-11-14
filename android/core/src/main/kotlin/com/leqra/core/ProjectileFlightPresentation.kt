package com.leqra.core

import kotlin.math.*

/** Completed server paths fill flights that began and ended between wire snapshots. */
internal class ProjectileFlightPresentation {
    private data class Flight(
        val effect: ArenaEffect,
        val path: ProjectileFlight,
        val start: Double,
        val end: Double,
        val sampleStartTick: Double = path.startTick,
        var shown: Boolean = false,
        var endpointShown: Boolean = false,
    )

    data class Image(val bullets: List<ArenaBullet>, val effects: List<ArenaEffect>)

    private val flights = LinkedHashMap<Int, Flight>()
    private val shown = LinkedHashSet<Int>()
    private val lastPoses = HashMap<Int, ArenaBullet>()
    private val completedIDs = LinkedHashSet<Int>()
    private var highestEffect = 0
    private var capacity = 1024
    private var observationCapacity = 1024
    val hasPending: Boolean get() = flights.isNotEmpty()
    fun pending(id: Int) = flights.containsKey(id)
    fun completed(id: Int) = id in completedIDs
    fun endpointShown(id: Int) = flights[id]?.endpointShown == true
    fun endTime(id: Int): Double? = flights[id]?.end

    fun reset(effects: List<ArenaEffect> = emptyList()) {
        flights.clear()
        shown.clear()
        lastPoses.clear()
        completedIDs.clear()
        highestEffect = effects.maxOfOrNull { it.id } ?: 0
        capacity = 1024; observationCapacity = 1024
    }

    fun accept(effects: List<ArenaEffect>, playhead: Double, actors: Int = 1) {
        capacity = max(capacity, combatPresentationCapacity(actors))
        observationCapacity = max(observationCapacity, actors.coerceIn(1, 256) * 128).coerceAtMost(32768)
        val baseline = highestEffect
        for (effect in effects) {
            highestEffect = max(highestEffect, effect.id)
            if (effect.id <= baseline) continue
            val path = effect.flight ?: continue
            if (!valid(path) || flights.containsKey(path.id)) continue
            val start = path.startTick / 60
            val end = path.endTick / 60
            val observed = path.id in shown
            val grace = !observed && (end - start < .05 || playhead >= end)
            val visualStart = if (grace) max(start, playhead) else start
            // A published projectile can already be ahead of its final wire segment.
            // Keep its visual clock moving forward, then draw the exact contact once.
            val resumeTick = lastPoses[path.id]?.let { last ->
                var nearest = Double.POSITIVE_INFINITY
                var tick = path.startTick
                for ((a, b) in path.points.zipWithNext()) {
                    val dx = b.x - a.x; val dy = b.y - a.y
                    val f = if (dx * dx + dy * dy > 1e-9) (((last.x - a.x) * dx + (last.y - a.y) * dy) / (dx * dx + dy * dy)).coerceIn(0.0, 1.0) else 1.0
                    val distance = hypot(last.x - a.x - dx * f, last.y - a.y - dy * f)
                    if (distance <= nearest) { nearest = distance; tick = a.tick + (b.tick - a.tick) * f }
                }
                max(tick, (playhead * 60).coerceIn(path.startTick, path.endTick))
            } ?: path.startTick
            flights[path.id] = if (observed) Flight(effect, path, playhead, max(playhead, end), resumeTick)
                else Flight(effect, path, visualStart, if (grace) visualStart + .05 else end)
            if (flights.size > capacity)
                flights.entries.iterator().let {
                    it.next()
                    it.remove()
                }
        }
    }

    fun render(bullets: List<ArenaBullet>, effects: List<ArenaEffect>, playhead: Double, canComplete: (Int) -> Boolean = { true }): Image {
        if (flights.isEmpty()) {
            for (bullet in bullets) remember(bullet)
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
            if (playhead >= flight.end && flight.endpointShown && canComplete(flight.path.id)) {
                completed += flight.effect
                completedIDs += flight.path.id
                if (completedIDs.size > capacity)
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
            val tick = flight.sampleStartTick + (flight.path.endTick - flight.sampleStartTick) * alpha
            val points = flight.path.points
            val zeroDuration = flight.path.endTick - flight.path.startTick <= 1e-9
            val endpoint = alpha >= 1 || !zeroDuration && tick >= flight.path.endTick
            var index =
                if (endpoint) points.lastIndex - 1
                else if (zeroDuration) min(points.lastIndex - 1, (alpha * points.lastIndex).toInt())
                else 0
            while (
                !zeroDuration && index < points.lastIndex - 1 && tick > points[index + 1].tick
            ) index++
            val a = points[index]
            val b = points[index + 1]
            val dt = b.tick - a.tick
            val fraction =
                if (endpoint) 1.0
                else if (zeroDuration) (alpha * points.lastIndex - index).coerceIn(0.0, 1.0)
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
            if (playhead >= flight.end) flight.endpointShown = true
        }
        for (bullet in bullets) {
            if (bullet.id in completedIDs) continue
            if (flights.containsKey(bullet.id)) {
                poses[bullet.id]?.let {
                    output += it
                    supplied += bullet.id
                } ?: run { if (playhead < flights.getValue(bullet.id).start) output += bullet }
            } else output += bullet
        }
        for ((id, bullet) in poses) if (id !in supplied) output += bullet
        for (bullet in output) remember(bullet)
        val visibleEffects =
            effects.filter { effect -> effect.flight?.id?.let { it !in flights } ?: true }
        return Image(
            output,
            if (completed.isEmpty()) visibleEffects
            else (visibleEffects + completed).distinctBy { it.id },
        )
    }

    private fun remember(bullet: ArenaBullet) {
        shown += bullet.id
        lastPoses[bullet.id] = bullet
        if (shown.size > observationCapacity)
            shown.iterator().let {
                lastPoses.remove(it.next())
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
