package com.leqra.core

import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/** Keep the drawn barrel on the incoming side of cover without changing hitboxes. */
object MuzzlePresentation {
    fun retraction(tank: ArenaTank, maze: InfiniteMaze?, recoil: Double = tank.recoil): Double {
        val radius = when (tank.power) {
            "rapid" -> 3.5 / 3
            "homing" -> 5.0
            "grenade" -> 6.0
            "laser" -> 3.0
            else -> 3.5
        }
        var hit = maze?.projectileHit("", tank.x, tank.y,
            cos(tank.angle) * 30, sin(tank.angle) * 30, radius)
        var clearance = radius
        if (hit == null && tank.ghostTime > 0) {
            hit = maze?.projectileHit("", tank.x, tank.y, cos(tank.angle) * 30, sin(tank.angle) * 30, 0.0)
            clearance = .5
        }
        val fraction = hit?.fraction ?: 1.0
        val obstruction = 30 * (1 - fraction.coerceIn(0.0, 1.0)) - minOf(2.0, max(0.0, clearance - .5))
        return max(recoil.coerceIn(0.0, 1.0) * 4, obstruction)
    }
}
