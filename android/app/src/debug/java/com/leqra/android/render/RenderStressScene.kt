package com.leqra.android.render

import com.leqra.core.*
import kotlin.math.*

/** Repeatable high-motion rendering fixture. Every power is visible in the same scene. */
internal class RenderStressScene(fixed: Boolean) {
    val maze = InfiniteMaze(137)
    private val kinds =
        listOf(
            "rapid",
            "scatter",
            "shield",
            "homing",
            "grenade",
            "speed",
            "laser",
            "cannon",
            "ghost",
            "starman",
        )
    private val tanks =
        List(12) { index ->
            ArenaTank(
                id = index + 1,
                name = if (index == 0) "Long callsign wrap" else "Pilot ${index + 1}",
                colorIndex = index % 8,
                power = kinds[index % 10],
                powerTime = 10.0,
                charges = 3,
                machineRounds = 99,
                shield = 10.0,
                shieldCharges = 5,
                speedTime = 10.0,
                speedStacks = 5,
                ghostTime = if (index % 2 == 0) 10.0 else 0.0,
                starmanTime = if (index % 3 == 0) 10.0 else 0.0,
                team = index % 2 + 1,
            )
        }
    private val bullets =
        List(768) { index ->
            ArenaBullet(
                id = index + 1,
                owner = index % 12 + 1,
                kind =
                    when (index % 16) {
                        0 -> "homing"
                        1 -> "grenade"
                        2 -> "cannon"
                        else -> "rapid"
                    },
                colorIndex = index % 8,
                life = 2.0,
            )
        }
    private val pickups =
        List(10) { index ->
            ArenaPickup(
                id = index + 1,
                x = 130.0 + index % 5 * 120,
                y = 205.0 + index / 5 * 178,
                type = kinds[index],
            )
        }
    private val state =
        ArenaSnapshot(
            generation = 1,
            tanks = tanks,
            bullets = bullets,
            pickups = pickups,
            players = 12,
            tankCount = 12,
            world =
                if (fixed) ArenaWorld(756.0, 588.0, 9, 7, maze.walls(0.0, 0.0, 756.0, 588.0))
                else null,
            objectives =
                ArenaObjectives(
                    mode = "ctf",
                    flags =
                        listOf(
                            ArenaFlag(team = 1, homeX = 42.0, homeY = 42.0, x = 42.0, y = 42.0),
                            ArenaFlag(team = 2, homeX = 714.0, homeY = 546.0, x = 714.0, y = 546.0),
                        ),
                ),
        )

    fun update(seconds: Double): ArenaSnapshot {
        state.tick = (seconds * 60).toLong()
        for ((index, tank) in tanks.withIndex()) {
            tank.x = 378 + cos(seconds * 1.7 + index * PI / 6) * (if (index == 0) 160 else 245)
            tank.y = 294 + sin(seconds * 2.1 + index * PI / 6) * 195
            tank.angle = seconds * 3.7 + index
            tank.track = seconds * 650
            tank.recoil = .3 + .3 * sin(seconds * 60)
            tank.cooldownTotal = .065
            tank.cooldown = (seconds % .065)
        }
        for ((index, bullet) in bullets.withIndex()) {
            val angle = index * 2.399963229728653 + seconds * .7
            val radius = 35 + ((index * 17 + seconds * 460) % 360)
            bullet.x = 378 + cos(angle) * radius
            bullet.y = 294 + sin(angle) * radius * .75
            bullet.vx = cos(angle) * 460
            bullet.vy = sin(angle) * 460
            bullet.life = 3 - seconds % 3
            bullet.bounces = (seconds * 2).toInt()
            bullet.target = if (index % 16 == 0) 1 else 0
        }
        val id = state.tick.toInt() * 4 + 1
        state.effects =
            listOf(
                ArenaEffect(
                    id = id,
                    kind = "laser",
                    points =
                        listOf(
                            BeamPoint(70.0, 140.0),
                            BeamPoint(650.0, 380.0),
                            BeamPoint(580.0, 500.0),
                        ),
                ),
                ArenaEffect(id = id + 1, kind = "blast", x = 560.0, y = 140.0),
                ArenaEffect(id = id + 2, kind = "pickup", x = 185.0, y = 390.0),
                ArenaEffect(id = id + 3, kind = "hit", x = 350.0, y = 310.0),
            )
        return state
    }
}
