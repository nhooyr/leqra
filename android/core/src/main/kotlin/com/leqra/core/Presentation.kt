package com.leqra.core

import java.util.Locale
import kotlin.math.*

/** A finite match winner represents every tank on its positive team. */
fun ArenaSnapshot.isWinningSide(localID: Int): Boolean? {
    if (winner < 0) return null
    val local = tanks.firstOrNull { it.id == localID } ?: return null
    val winning = tanks.firstOrNull { it.id == winner } ?: return null
    return winner == localID || local.team > 0 && local.team == winning.team
}

/** Web-compatible equipment and readiness. Each gameplay state appears once. */
class PilotReadout(
    tank: ArenaTank,
    snapshot: ArenaSnapshot,
    infinity: Boolean,
    paused: Boolean = false,
    online: Boolean = true,
) {
    var weapon = "STANDARD"
        private set

    var buffs = ""
        private set

    var readiness = "READY"
        private set

    var fireLabel = "FIRE"
        private set

    var fireHint = "HOLD TO FIRE"
        private set

    var progress = 1.0
        private set

    var capacity = 5
        private set

    var available = 5
        private set

    var firingSeconds: Double? = null
        private set

    var locked = false
        private set

    var unlimited = false
        private set

    private data class Unavailable(
        val text: String,
        val label: String,
        val progress: Double,
        val hint: String? = null,
    )

    init {
        val alive = tank.hp > 0
        unlimited = alive && tank.starmanTime > 0
        capacity =
            when (tank.power) {
                "rapid" -> 115
                "scatter" -> 12
                "homing",
                "grenade",
                "laser",
                "cannon" -> 3
                else -> 5
            }
        val boosted =
            if (infinity || snapshot.boostedBulletIds.isEmpty()) emptySet()
            else snapshot.boostedBulletIds.toHashSet()
        var ordinary = 0
        var ownedGrenades = 0
        var ownedGrenadeLife = 0.0
        var projectileLocked = tank.locked
        if (!infinity || !projectileLocked)
            for (bullet in snapshot.bullets) {
                if (!infinity && bullet.owner == tank.id) {
                    if (bullet.ammoEpoch == tank.ammoEpoch && bullet.id !in boosted) ordinary++
                    if (
                        bullet.kind == "grenade" &&
                            bullet.ammoEpoch == (tank.grenadeEpoch ?: tank.ammoEpoch)
                    ) {
                        ownedGrenades++
                        ownedGrenadeLife = max(ownedGrenadeLife, bullet.life)
                    }
                }
                if (
                    !projectileLocked &&
                        (bullet.kind == "homing" || bullet.kind == "grenade") &&
                        bullet.target == tank.id &&
                        bullet.owner != tank.id
                ) {
                    val owner = snapshot.tanks.firstOrNull { it.id == bullet.owner }
                    projectileLocked =
                        snapshot.rules?.friendlyFire == true ||
                            owner == null ||
                            owner.team == 0 ||
                            owner.team != tank.team
                }
            }
        val used =
            if (tank.power == "laser") max(0, 3 - tank.charges)
            else if (infinity) tank.ammoUsed else max(tank.ammoUsed, ordinary)
        available = if (alive) max(0, capacity - used) else 0
        val grenadeLife =
            if (infinity) tank.grenadeLife else max(tank.grenadeLife, ownedGrenadeLife)
        val grenades =
            if (infinity) if (grenadeLife > 0) tank.grenades else 0
            else max(tank.grenades, ownedGrenades)
        val base =
            when (tank.power) {
                "rapid" -> "MACHINE GUN"
                "scatter" -> "SHOTGUN"
                "homing" -> "HOMING"
                "grenade" -> "GRENADE"
                "laser" -> "LASER"
                "cannon" -> "CANNON"
                else -> "STANDARD"
            }
        if (alive) {
            weapon =
                when {
                    grenades > 0 -> "GRENADE, ${decimal(grenadeLife)}s"
                    unlimited -> "$base, ∞ AMMO"
                    tank.power.isEmpty() -> base
                    else ->
                        base +
                            (if (
                                tank.power in
                                    listOf("scatter", "homing", "grenade", "laser", "cannon")
                            )
                                " ×${tank.charges}"
                            else "") +
                            ", " +
                            (if (tank.power == "rapid") "EXPIRES " else "") +
                            "${ceil(tank.powerTime).toInt()}s"
                }
            if (tank.power == "rapid" && !unlimited)
                firingSeconds = tank.machineRounds.coerceIn(0, 180) / 60.0
            val lines = mutableListOf<String>()
            if (tank.shield > 0)
                lines.add("SHD×${tank.shieldCharges.coerceIn(1,5)} ${ceil(tank.shield).toInt()}s")
            if (tank.speedTime > 0)
                lines.add("SPD×${tank.speedStacks.coerceIn(1,5)} ${ceil(tank.speedTime).toInt()}s")
            if (tank.starmanTime > 0) lines.add("STAR ${ceil(tank.starmanTime).toInt()}s")
            else if (tank.ghostTime > 0) lines.add("GHO ${ceil(tank.ghostTime).toInt()}s")
            buffs =
                if (lines.size > 2)
                    lines
                        .map {
                            if (it.startsWith("SHD")) it.substringBefore(' ')
                            else it.replace(compactBuffTime, "$1")
                        }
                        .joinToString(" ")
                else lines.joinToString(", ")
        } else weapon = ""
        var unavailable: Unavailable? = null
        if (snapshot.result != null || snapshot.phase == "matchOver")
            unavailable = Unavailable("MATCH COMPLETE", "DONE", 1.0)
        else if (infinity) {
            if (!alive)
                unavailable =
                    Unavailable(
                        if (paused && online) "RESPAWN HELD"
                        else "RESPAWN ${decimal(tank.respawnTime)}s",
                        "OUT",
                        0.0,
                    )
            else if (paused) unavailable = Unavailable("PAUSED", "PAUSED", 1.0)
        } else if (snapshot.phase == "roundOver")
            unavailable = Unavailable("ROUND COMPLETE", "DONE", 1.0)
        else if (paused || snapshot.phase == "paused")
            unavailable = Unavailable("PAUSED", "PAUSED", 1.0)
        else if (snapshot.phase == "countdown") unavailable = Unavailable("GET READY", "FIRE", 0.0)
        else if (snapshot.phase != "playing") unavailable = Unavailable("READY", "FIRE", 1.0)
        else if (snapshot.objectives?.survival?.status == "break")
            unavailable =
                Unavailable(
                    "NEXT WAVE ${ceil(snapshot.objectives!!.survival!!.breakTime).toInt()}s",
                    "WAIT",
                    0.0,
                    "NEXT WAVE",
                )
        else if (!alive) {
            val mode = snapshot.objectives?.mode ?: snapshot.rules?.mode ?: "elimination"
            val text =
                if (mode == "survival") "BACK NEXT WAVE"
                else if (mode in listOf("ctf", "koth") && snapshot.objectives?.suddenDeath != true)
                    "RESPAWN ${decimal(tank.respawnTime)}s"
                else "OUT"
            unavailable = Unavailable(text, "OUT", 0.0)
        }
        if (unavailable == null && tank.spawnProtected && tank.invulnerable > 0)
            unavailable = Unavailable("SPAWN PROTECTION", "WAIT", 0.0, "WAIT TO FIRE")
        locked = unavailable == null && projectileLocked
        fireHint = if (tank.power == "grenade") "HOLD TO THROW" else "HOLD TO FIRE"
        if (unavailable != null) {
            readiness = unavailable.text
            fireLabel = unavailable.label
            progress = unavailable.progress
            fireHint = unavailable.hint ?: fireHint
        } else if (grenades > 0) {
            readiness = "DETONATE READY"
            fireLabel = "BOOM"
            fireHint =
                if (tank.power == "grenade") "HOLD TO THROW, TAP TO DETONATE"
                else "TAP TO DETONATE, HOLD TO FIRE"
        } else {
            val cooldown = if (unlimited) 0.0 else tank.cooldown
            val free =
                if (unlimited) Int.MAX_VALUE
                else if (tank.power == "laser") tank.charges else available
            val need = if (tank.power == "scatter") 3 else 1
            val fallback =
                when (tank.power) {
                    "cannon" -> .85 / 3
                    "laser" -> .85 / 3
                    "rapid" -> 0.0
                    "scatter" -> .27
                    "homing" -> .36
                    "grenade" -> .8
                    else -> .34
                }
            val total = if (tank.cooldownTotal > 0) tank.cooldownTotal else fallback
            progress =
                if (cooldown > 0) (1 - cooldown / max(.001, total)).coerceIn(0.0, 1.0)
                else if (free < need) 0.0 else 1.0
            if (cooldown > 0) {
                val tenths = max(1, (cooldown * 10).roundToInt())
                val time = cooldownTimes.getOrNull(tenths) ?: decimal(tenths / 10.0)
                readiness = "COOLDOWN ${time}s"
                fireLabel = "${time}s"
            } else if (free < need) {
                readiness = "WAITING FOR AMMO"
                fireLabel = "WAIT"
            }
        }
    }

    companion object {
        private val compactBuffTime = Regex(" ([0-9]+)s$")
        private val cooldownTimes =
            arrayOf("0.0", "0.1", "0.2", "0.3", "0.4", "0.5", "0.6", "0.7", "0.8", "0.9", "1.0")

        private fun decimal(value: Double) = String.format(Locale.ROOT, "%.1f", value)
    }
}
