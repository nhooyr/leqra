package com.leqra.android

import com.leqra.core.RoomRules

internal object PowerupHelp {
    val kinds = listOf("rapid", "scatter", "shield", "homing", "grenade", "speed", "laser", "cannon", "ghost", "starman")

    fun title(kind: String): String = when (kind) {
        "rapid" -> "Machine gun"
        "scatter" -> "Shotgun"
        "homing" -> "Homing missile"
        "speed" -> "Super Speed"
        else -> kind.replaceFirstChar(Char::uppercase)
    }

    fun duration(rules: RoomRules): Int =
        if (rules.infinity || rules.mapSize in setOf("huge", "giant", "ultrawide")) 15 else 10

    fun starDuration(rules: RoomRules): Int = if (rules.infinity) 8 else when (rules.mapSize) {
        "large" -> 5
        "huge" -> 6
        "giant" -> 7
        "ultrawide" -> 8
        else -> 4
    }

    fun summary(rules: RoomRules): String {
        val spawning = when {
            rules.infinity -> "Infinity always spawns all ten power-ups near active pilots. Pickup rate and type settings apply to fixed mazes."
            rules.pickupRate == "off" || rules.weapons.none { it in kinds } -> "Power-up spawning is off for these rules."
            else -> "${rules.weapons.count { it in kinds }} power-up types enabled, ${rules.pickupRate} pickup rate."
        }
        return "$spawning Weapons replace the equipped weapon; Shield, Super Speed, Ghost, and Starman can stack with it."
    }

    fun description(kind: String, rules: RoomRules): String {
        val duration = duration(rules)
        return when (kind) {
            "rapid" -> "Hold Fire for small ricocheting rounds: 3 seconds of firing within $duration seconds."
            "scatter" -> "Three ricocheting pellets per volley. 5 volleys or $duration seconds."
            "shield" -> "Absorbs one damaging hit per charge. Up to 5 charges with a shared $duration-second timer."
            "homing" -> "Tracks visible opponents and bounces off walls. 3 missiles or $duration seconds."
            "grenade" -> "Homes toward opponents. Contact, the next Fire press, or its 10-second fuse detonates it; walls block the blast. Release Fire after detonation to shoot again. 3 throws or $duration seconds."
            "speed" -> "+65% movement and +25% turn speed per stack. Up to 5 stacks with a shared $duration-second timer."
            "laser" -> "Instant ricocheting beam hits every eligible tank along its path. 3 shots or $duration seconds."
            "cannon" -> "Rounds pass through internal walls and every eligible tank, then expire after 5.3 seconds. ${if (rules.infinity) "" else "Bounce off the arena rim. "}3 shots or $duration seconds."
            "ghost" -> "Drive through internal walls for $duration seconds.${if (rules.infinity) "" else " The arena rim stays solid."}"
            "starman" -> "Invulnerability, wall phasing, contact kills, and unlimited ammunition with no reload for ${starDuration(rules)} seconds.${if (rules.infinity) "" else " Objective interaction pauses while active."}"
            else -> ""
        }
    }
}
