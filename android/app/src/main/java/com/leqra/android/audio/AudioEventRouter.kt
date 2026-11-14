package com.leqra.android.audio

import com.leqra.core.*
import kotlin.math.*

data class AudioCueRequest(val cue: AudioCue, val local: Boolean = true)

/** Baselines retained snapshots, deduplicates events, and bounds rapid-fire audio. */
class AudioEventRouter {
    private var generation: Int? = null
    private var baselineEffectID = 0
    private val seenEffectIDs = LinkedHashSet<Int>()
    private var bounceCounts = BounceHistory()
    private var nextBounceCounts = BounceHistory()
    private var previousTick: Long? = null
    private var previousLocalID: Int? = null
    private var previousInfinity: Boolean? = null
    private var previousOnline: Boolean? = null
    private var previousPhase: String? = null
    private var countdownNumber: Int? = null
    private var lastExplosion = Double.NEGATIVE_INFINITY
    private var lastGrenade = Double.NEGATIVE_INFINITY
    private var lastRicochet = Double.NEGATIVE_INFINITY
    private var lastMachineShot = Double.NEGATIVE_INFINITY
    private var homingLocked = false
    private var lastHomingWarning = Double.NEGATIVE_INFINITY

    fun reset() {
        generation = null
        baselineEffectID = 0
        seenEffectIDs.clear()
        bounceCounts.clear()
        nextBounceCounts.clear()
        previousTick = null
        previousLocalID = null
        previousInfinity = null
        previousOnline = null
        previousPhase = null
        countdownNumber = null
        lastExplosion = Double.NEGATIVE_INFINITY
        lastGrenade = lastExplosion
        lastRicochet = lastExplosion
        lastMachineShot = lastExplosion
        homingLocked = false
        lastHomingWarning = lastExplosion
    }

    fun consume(
        snapshot: ArenaSnapshot,
        localID: Int,
        infinity: Boolean,
        online: Boolean,
        now: Double,
    ): List<AudioCueRequest> {
        if (!now.isFinite()) return emptyList()
        val requests = mutableListOf<AudioCueRequest>()
        val localTank = snapshot.tanks.firstOrNull { it.id == localID }
        val focusTank = if (snapshot.spectating) snapshot.tanks.firstOrNull { it.id == snapshot.following } else localTank
        val restarted = previousTick?.let { snapshot.tick < it } == true
        if (
            generation != snapshot.generation ||
                previousLocalID != localID ||
                previousInfinity != infinity ||
                previousOnline != online ||
                restarted
        ) {
            reset()
            generation = snapshot.generation
            previousTick = snapshot.tick
            previousLocalID = localID
            previousInfinity = infinity
            previousOnline = online
            baselineEffectID = snapshot.effects.maxOfOrNull { it.id } ?: 0
            snapshot.bullets.forEach { bounceCounts.put(it.id, it.bounces) }
            appendPhase(snapshot, infinity, online, requests)
            appendWarning(snapshot, localTank, now, requests)
            return requests
        }
        previousTick = snapshot.tick
        appendPhase(snapshot, infinity, online, requests)
        appendWarning(snapshot, localTank, now, requests)
        var bounced = false
        val live = nextBounceCounts
        live.clear()
        for (bullet in snapshot.bullets) {
            val packed = bounceCounts.read(bullet.id)
            val previous = packed.toInt()
            live.put(bullet.id, if (packed == 0L) bullet.bounces else max(previous, bullet.bounces))
            if (
                packed != 0L &&
                    bullet.bounces > previous &&
                    (!infinity || near(bullet.x, bullet.y, focusTank, 588.0))
            )
                bounced = true
        }
        nextBounceCounts = bounceCounts
        bounceCounts = live
        if (bounced && now - lastRicochet >= AudioSynthesis.ricochetInterval) {
            lastRicochet = now
            requests += AudioCueRequest(AudioCue.RICOCHET)
        }
        // Simulation/network effects are already monotonic; sorting handles batch reordering.
        var ordered = true
        var previousID = Int.MIN_VALUE
        for (effect in snapshot.effects) {
            if (effect.id < previousID) {
                ordered = false
                break
            }
            previousID = effect.id
        }
        val effects = if (ordered) snapshot.effects else snapshot.effects.sortedBy { it.id }
        for (effect in effects) {
            if (effect.id <= 0 || effect.id <= baselineEffectID || !seenEffectIDs.add(effect.id)) continue
            if (seenEffectIDs.size > 512) seenEffectIDs.iterator().let { it.next(); it.remove() }
            val own = (effect.player ?: effect.owner) == localID
            if (infinity && effect.owner != localID && !near(effect.x, effect.y, focusTank, 504.0))
                continue
            val shot =
                when (effect.kind) {
                    "shot",
                    "shot:",
                    "shot:regular" -> AudioCue.REGULAR
                    "shot:rapid" -> AudioCue.RAPID
                    "shot:scatter" -> AudioCue.SCATTER
                    "shot:laser" -> AudioCue.LASER
                    "shot:homing" -> AudioCue.HOMING
                    "shot:grenade" -> AudioCue.GRENADE
                    "shot:cannon" -> AudioCue.CANNON
                    "laser" -> if (online && !infinity) null else AudioCue.LASER
                    else -> null
                }
            if (shot != null) {
                val shooter =
                    snapshot.tanks.firstOrNull { it.id == (effect.player ?: effect.owner) }
                if (
                    shot == AudioCue.RAPID ||
                        (shooter?.starmanTime ?: 0.0) > 0 && shot != AudioCue.GRENADE
                ) {
                    if (now - lastMachineShot < AudioSynthesis.repeatedShotInterval) continue
                    lastMachineShot = now
                }
                requests += AudioCueRequest(shot, own)
                continue
            }
            when (effect.kind) {
                "pickup" ->
                    if (infinity || !online || own)
                        requests += AudioCueRequest(AudioCue.PICKUP, own)
                "objective" -> if (!infinity) requests += AudioCueRequest(AudioCue.PICKUP, own)
                "shield" -> requests += AudioCueRequest(AudioCue.SHIELD)
                "impact" -> requests += AudioCueRequest(AudioCue.IMPACT)
                "blast" ->
                    if (now - lastGrenade >= AudioSynthesis.explosionInterval) {
                        lastGrenade = now
                        lastExplosion = now
                        requests += AudioCueRequest(AudioCue.GRENADE_EXPLOSION)
                    }
                "hit" ->
                    if (now - lastExplosion >= AudioSynthesis.explosionInterval) {
                        lastExplosion = now
                        requests += AudioCueRequest(AudioCue.EXPLOSION)
                    }
                "roundEnd" ->
                    if (online && !infinity)
                        requests +=
                            AudioCueRequest(AudioCue.ONLINE_ROUND_END, effect.owner == localID)
            }
        }
        return requests
    }

    private fun appendPhase(
        snapshot: ArenaSnapshot,
        infinity: Boolean,
        online: Boolean,
        requests: MutableList<AudioCueRequest>,
    ) {
        if (!infinity) {
            if (
                snapshot.phase == "countdown" &&
                    snapshot.phaseTime.isFinite() &&
                    snapshot.phaseTime > 0 &&
                    snapshot.phaseTime < Int.MAX_VALUE
            ) {
                val number = ceil(snapshot.phaseTime).toInt()
                if (countdownNumber != number) requests += AudioCueRequest(AudioCue.COUNTDOWN)
                countdownNumber = number
            } else countdownNumber = null
            if (!online && previousPhase == "countdown" && snapshot.phase == "playing")
                requests += AudioCueRequest(AudioCue.GO)
            if (!online && previousPhase == "playing" && snapshot.phase == "roundOver")
                requests +=
                    AudioCueRequest(
                        if (snapshot.winner < 0) AudioCue.ROUND_DRAW else AudioCue.ROUND_WIN,
                    )
        } else countdownNumber = null
        previousPhase = snapshot.phase
    }

    private fun appendWarning(
        snapshot: ArenaSnapshot,
        tank: ArenaTank?,
        now: Double,
        requests: MutableList<AudioCueRequest>,
    ) {
        var locked = false
        if (
            snapshot.phase == "playing" &&
                snapshot.result == null &&
                tank != null &&
                tank.hp > 0 &&
                snapshot.objectives?.survival?.status != "break"
        ) {
            locked =
                tank.locked ||
                    snapshot.bullets.any { bullet ->
                        if (
                            (bullet.kind != "homing" && bullet.kind != "grenade") ||
                                bullet.target != tank.id ||
                                bullet.owner == tank.id
                        )
                            false
                        else {
                            val owner = snapshot.tanks.firstOrNull { it.id == bullet.owner }
                            snapshot.rules?.friendlyFire == true ||
                                owner == null ||
                                owner.team == 0 ||
                                owner.team != tank.team
                        }
                    }
        }
        if (
            locked &&
                !homingLocked &&
                now - lastHomingWarning > AudioSynthesis.homingWarningInterval
        ) {
            requests += AudioCueRequest(AudioCue.HOMING_WARNING)
            lastHomingWarning = now
        }
        homingLocked = locked
    }

    private fun near(x: Double, y: Double, tank: ArenaTank?, radius: Double) =
        tank != null && hypot(x - tank.x, y - tank.y) <= radius
}

/** Reusable primitive counter table; no boxed IDs, entry nodes or sorting per display frame. */
private class BounceHistory {
    private var keys = IntArray(256)
    private var values = IntArray(256)
    private var stamps = IntArray(256)
    private var stamp = 1
    private var size = 0

    fun clear() {
        size = 0
        stamp++
        if (stamp == 0) {
            stamps.fill(0)
            stamp = 1
        }
    }

    fun read(key: Int): Long {
        var index = (key * -1640531527) and (keys.size - 1)
        while (stamps[index] == stamp) {
            if (keys[index] == key) return (values[index].toLong() and 0xffffffffL) or 0x100000000L
            index = (index + 1) and (keys.size - 1)
        }
        return 0L
    }

    fun put(key: Int, value: Int) {
        if ((size + 1) * 2 >= keys.size) grow()
        var index = (key * -1640531527) and (keys.size - 1)
        while (stamps[index] == stamp && keys[index] != key) index = (index + 1) and (keys.size - 1)
        if (stamps[index] != stamp) {
            stamps[index] = stamp
            keys[index] = key
            size++
        }
        values[index] = value
    }

    private fun grow() {
        val oldKeys = keys
        val oldValues = values
        val oldStamps = stamps
        keys = IntArray(oldKeys.size * 2)
        values = IntArray(keys.size)
        stamps = IntArray(keys.size)
        size = 0
        for (index in oldKeys.indices) if (oldStamps[index] == stamp)
            put(oldKeys[index], oldValues[index])
    }
}
