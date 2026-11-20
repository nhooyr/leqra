package com.leqra.android

import com.leqra.core.ArenaWorld
import com.leqra.core.RoomRules
import kotlin.math.roundToInt

internal object PowerupHelp {
    val kinds =
        listOf(
            "cannon",
            "ghost",
            "laser",
            "homing",
            "grenade",
            "speed",
            "rapid",
            "scatter",
            "shield",
            "starman",
        )
    private val mapAreas =
        mapOf(
            "compact" to 49,
            "standard" to 72,
            "large" to 120,
            "huge" to 168,
            "giant" to 224,
            "ultrawide" to 336,
        )

    fun title(kind: String): String =
        when (kind) {
            "rapid" -> "Machine gun"
            "scatter" -> "Shotgun"
            "homing" -> "Homing missile"
            "speed" -> "Super speed"
            else -> kind.replaceFirstChar(Char::uppercase)
        }

    private fun mapArea(rules: RoomRules, world: ArenaWorld?): Int =
        world?.let { it.cols * it.rows }?.takeIf { it > 0 } ?: mapAreas[rules.mapSize] ?: 72

    fun duration(rules: RoomRules, world: ArenaWorld? = null): Int =
        if (rules.infinity || mapArea(rules, world) >= 168) 15 else 10

    fun starDuration(rules: RoomRules, world: ArenaWorld? = null): Int {
        if (rules.infinity) return 8
        val area = mapArea(rules, world)
        return when {
            area >= 336 -> 8
            area >= 224 -> 7
            area >= 168 -> 6
            area >= 120 -> 5
            else -> 4
        }
    }

    fun groundLifetime(rules: RoomRules, world: ArenaWorld? = null): Int {
        if (rules.infinity) return 30
        val area = mapArea(rules, world)
        val cap = (area / 9.8).roundToInt()
        return maxOf(if (area <= 120) 30 else 0, cap * 8 / 3)
    }

    fun summary(rules: RoomRules, world: ArenaWorld? = null): String {
        val enabled = rules.weapons.distinct().count { it in kinds }
        val types = if (enabled == 1) "power-up type" else "power-up types"
        val interval =
            when (rules.pickupRate) {
                "superfast" -> "1–2"
                "fast" -> "2–3.5"
                "slow" -> "7–10"
                else -> "4–6"
            }
        val spawning =
            when {
                rules.infinity ->
                    "Infinity always spawns all ten power-ups near active pilots. Pickup rate and type settings apply to fixed mazes."
                rules.pickupRate == "off" || enabled == 0 ->
                    "Power-up spawning is off for these rules."
                else ->
                    "$enabled $types enabled, ${rules.pickupRate} pickup rate. New pickups spawn every $interval seconds while there is space."
            }
        val timing =
            "Most effects last ${duration(rules, world)} seconds. Starman lasts ${starDuration(rules, world)} seconds. Uncollected pickups expire after ${groundLifetime(rules, world)} seconds."
        return "$spawning $timing Weapons replace the equipped weapon. Shield, Super speed, Ghost, and Starman can stack with it."
    }

    fun description(
        kind: String,
        rules: RoomRules,
        world: ArenaWorld? = null,
        includeGrenadeControls: Boolean = false,
    ): String {
        val duration = duration(rules, world)
        val effect =
            when (kind) {
                "rapid" ->
                    "Hold Fire for small ricocheting rounds. 3 seconds of firing within $duration seconds. Range ${if (rules.infinity) "18 maze cells" else "a quarter of the maze perimeter"}."
                "scatter" -> "Three ricocheting pellets per volley. 5 volleys or $duration seconds."
                "shield" ->
                    "Absorbs one damaging hit per charge. Up to 5 charges with a shared $duration-second timer."
                "homing" ->
                    "Tracks visible opponents and bounces off walls. 3 missiles or $duration seconds. Range ${if (rules.infinity) "18 maze cells" else "half the maze perimeter"}."
                "grenade" -> {
                    val facts =
                        "Homes toward opponents. Detonates on contact or after a 10-second fuse. Walls block the blast. 3 throws or $duration seconds."
                    if (includeGrenadeControls)
                        "$facts Tap or hold Fire to throw. Release, then press Fire again to detonate early. Release Fire after detonation to shoot again."
                    else facts
                }
                "speed" ->
                    "+65% movement and +25% turn speed per stack. Up to 5 stacks with a shared $duration-second timer."
                "laser" ->
                    "Instant ricocheting beam hits every eligible tank along its path. 3 shots or $duration seconds. Range ${if (rules.infinity) "36 maze cells" else "twice the maze perimeter"}."
                "cannon" ->
                    "Rounds pass through internal walls and every eligible tank, then expire after 5.3 seconds. ${if (rules.infinity) "" else "Bounce off the arena rim. "}3 shots or $duration seconds."
                "ghost" ->
                    "Drive through internal walls for $duration seconds.${if (rules.infinity) "" else " The arena rim stays solid."}"
                "starman" ->
                    "Invulnerability, wall phasing, contact kills, and unlimited ammunition with no reload for ${starDuration(rules, world)} seconds. Pauses the equipped weapon’s timer.${if (rules.infinity) "" else " Objective interaction pauses while active."}"
                else -> return ""
            }
        return if (!rules.infinity && (rules.pickupRate == "off" || kind !in rules.weapons))
            "Disabled in this room. $effect"
        else effect
    }
}
