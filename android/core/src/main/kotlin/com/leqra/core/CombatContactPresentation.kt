package com.leqra.core

import kotlin.math.*

internal fun combatPresentationCapacity(actors: Int) = max(1024, actors.coerceIn(1, 256) * 128)

/** Keeps a victim and its hit effects on the projectile's visual contact clock. */
internal class CombatContactPresentation {
    private data class Pending(
        val effect: ArenaEffect,
        val contact: CombatContact,
        val from: ArenaTank?,
        val start: Double,
        val contactTime: Double,
        var endpointShown: Boolean = false,
    )
    data class Image(val tanks: List<ArenaTank>, val effects: List<ArenaEffect>)
    private val contacts = LinkedHashMap<Int, Pending>()
    private val awaitingContact = HashSet<Int>()
    private val discarded = LinkedHashSet<Int>()
    private var lastTanks = emptyMap<Int, ArenaTank>()
    private var highestEffect = 0
    private var capacity = 1024
    private data class Known(var tank: ArenaTank, var time: Double)
    private val knownTanks = LinkedHashMap<Int, Known>()
    private var lastPrune = Double.NEGATIVE_INFINITY
    private data class Correction(val life: Int, var x: Double, var y: Double, var angle: Double)
    private val corrections = HashMap<Int, Correction>()
    private var lastTime: Double? = null
    val hasPending get() = contacts.isNotEmpty()
    fun canCompleteProjectile(id: Int) = id !in awaitingContact

    fun reset(effects: List<ArenaEffect> = emptyList()) {
        contacts.clear(); awaitingContact.clear(); discarded.clear(); lastTanks = emptyMap(); knownTanks.clear(); corrections.clear(); lastTime = null; lastPrune = Double.NEGATIVE_INFINITY; capacity = 1024
        highestEffect = effects.maxOfOrNull { it.id } ?: 0
        effects.filter { it.kind in combatKinds }.forEach { discard(it.id) }
    }

    fun accept(effects: List<ArenaEffect>, tanks: List<ArenaTank>, playhead: Double, tick: Double, immediateOwners: Set<Int> = emptySet()) {
        capacity = max(capacity, (combatPresentationCapacity(tanks.size) * 2).coerceAtMost(32768))
        val currentTanks = tanks.associateBy { it.id }
        val baseline = highestEffect
        for (effect in effects) {
            highestEffect = max(highestEffect, effect.id)
            if (effect.id <= baseline) continue
            val c = effect.contact ?: continue
            if (!valid(c) || c.tick > tick) continue
            val current = currentTanks[c.target]
                ?: knownTanks[c.target]?.takeIf { playhead - it.time <= 1 }?.tank
            if (current != null && current.spawnSerial != c.spawnSerial) { discard(effect.id); continue }
            val prior = lastTanks[c.target]?.takeIf { it.spawnSerial == c.spawnSerial && it.hp > 0 }
                ?: current?.let { before(it, c.before) }
            val contactTime = if (c.kind == "starman" && effect.owner in immediateOwners) playhead else c.tick / 60
            contacts[effect.id] = Pending(effect, c, prior?.copy(), playhead, contactTime)
            if (c.projectileId > 0) awaitingContact += c.projectileId
            while (contacts.size > capacity) contacts.entries.iterator().let { discard(it.next().key); it.remove() }
        }
    }

    fun render(tanks: List<ArenaTank>, effects: List<ArenaEffect>, playhead: Double, flights: ProjectileFlightPresentation, poseAllowed: (ArenaTank, ArenaTank) -> Boolean = { _, _ -> true }): Image {
        val held = HashMap<Int, Pair<Pending, Boolean>>()
        val currentTanks = if (contacts.isEmpty()) emptyMap() else tanks.associateBy { it.id }
        val released = ArrayList<ArenaEffect>()
        val iterator = contacts.entries.iterator()
        while (iterator.hasNext()) {
            val (id, p) = iterator.next()
            val c = p.contact
            val current = currentTanks[c.target]
            if (current != null && current.spawnSerial != c.spawnSerial) { discard(id); iterator.remove(); continue }
            val linked = c.projectileId > 0 && flights.pending(c.projectileId)
            val atContact = if (linked) flights.endpointShown(c.projectileId) else playhead >= p.contactTime
            val finished = !linked && p.endpointShown && (c.projectileId > 0 && flights.completed(c.projectileId) || atContact)
            if (finished) {
                if (current != null && current.hp > 0) lastTanks[c.target]?.takeIf { it.spawnSerial == current.spawnSerial }?.let {
                    corrections[c.target] = Correction(current.spawnSerial, it.x - current.x, it.y - current.y, TankMovement.angleDelta(it.angle, current.angle))
                }
                released += p.effect; iterator.remove(); continue
            }
            if (current != null || p.from != null) {
                if (held.putIfAbsent(c.target, p to atContact) == null && atContact) p.endpointShown = true
            } else if (atContact) p.endpointShown = true
        }
        awaitingContact.clear()
        for (p in contacts.values) if (!p.endpointShown && p.contact.projectileId > 0) awaitingContact += p.contact.projectileId
        val missing = held.filterKeys { id -> id !in currentTanks }.values.mapNotNull { it.first.from }
        var output = if (held.isEmpty()) tanks else (tanks + missing).map { current ->
            val (p, endpoint) = held[current.id] ?: return@map current
            val c = p.contact
            val visual = before(current, c.before)
            val from = p.from
            if (!endpoint && from != null) {
                val end = flights.endTime(c.projectileId) ?: p.contactTime
                val f = if (end > p.start) ((playhead - p.start) / (end - p.start)).coerceIn(0.0, 1.0) else 0.0
                visual.x = from.x + (c.before.x - from.x) * f
                visual.y = from.y + (c.before.y - from.y) * f
                visual.angle = from.angle + TankMovement.angleDelta(c.before.angle, from.angle) * f
                if (!poseAllowed(from, visual)) { visual.x = from.x; visual.y = from.y; visual.angle = from.angle }
            }
            visual
        }
        val dt = lastTime?.let { (playhead - it).coerceIn(0.0, .1) } ?: 0.0
        lastTime = playhead
        if (corrections.isNotEmpty()) output = output.map { tank ->
            val correction = corrections[tank.id] ?: return@map tank
            if (tank.hp <= 0 || tank.spawnSerial != correction.life || tank.id in held) { corrections.remove(tank.id); return@map tank }
            val candidate = tank.copy(x = tank.x + correction.x, y = tank.y + correction.y, angle = tank.angle + correction.angle)
            if (!poseAllowed(tank, candidate)) { corrections.remove(tank.id); return@map tank }
            val decay = exp(-dt / .04); correction.x *= decay; correction.y *= decay; correction.angle *= decay
            if (hypot(correction.x, correction.y) < .01 && abs(correction.angle) < .001) corrections.remove(tank.id)
            candidate
        }
        lastTanks = output.associateBy { it.id }
        for (tank in output) knownTanks[tank.id]?.let { it.tank = tank; it.time = playhead } ?: run { knownTanks[tank.id] = Known(tank, playhead) }
        if (playhead - lastPrune > .25) {
            knownTanks.entries.removeAll { playhead - it.value.time > 1 }
            lastPrune = playhead
        }
        while (knownTanks.size > capacity) knownTanks.entries.iterator().let { it.next(); it.remove() }
        val visible = effects.filter { effect ->
            effect.id !in contacts && effect.id !in discarded &&
                (effect.kind != "roundEnd" || contacts.isEmpty() && !flights.hasPending) &&
                (effect.kind !in combatKinds || (effect.flight?.endTick ?: effect.tick?.toDouble())?.let { playhead + 1e-9 >= it / 60 } != false)
        }
        return Image(output, if (released.isEmpty()) visible else (visible + released).distinctBy { it.id })
    }

    private fun before(current: ArenaTank, b: ContactTankState) = current.copy(
        x = b.x, y = b.y, angle = b.angle, hp = b.hp,
        shield = b.shield, shieldCharges = b.shieldCharges, invulnerable = b.invulnerable,
        spawnProtected = b.spawnProtected, protectedState = b.invulnerable > 0,
    )

    private fun discard(id: Int) { discarded += id; if (discarded.size > capacity) discarded.iterator().let { it.next(); it.remove() } }
    private fun valid(c: CombatContact): Boolean = c.projectileId >= 0 && c.target >= 0 && c.spawnSerial >= 0 && c.tick.isFinite() && c.tick >= 0 &&
        c.kind in listOf("regular", "rapid", "scatter", "homing", "grenade", "cannon", "laser", "starman") &&
        c.before.hp > 0 && c.before.shield >= 0 && c.before.shieldCharges in 0..5 && c.before.invulnerable >= 0 &&
        listOf(c.before.x, c.before.y, c.before.angle, c.before.vx, c.before.vy, c.before.shield, c.before.invulnerable).all { it.isFinite() }
    private val combatKinds = setOf("hit", "shield", "impact", "blast", "laser", "projectileFlight", "roundEnd")
}
