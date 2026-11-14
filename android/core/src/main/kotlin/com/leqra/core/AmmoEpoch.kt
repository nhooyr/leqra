package com.leqra.core

/** Quota banks change without deleting projectiles that are still flying. */
object AmmoEpoch {
    const val maximum = 9_007_199_254_740_991L

    fun next(current: Long) = if (current in 0 until maximum) current + 1 else 1L

    fun refill(tank: ArenaTank) {
        tank.ammoEpoch = next(tank.ammoEpoch)
        tank.cooldown = 0.0
        tank.cooldownTotal = 0.0
        tank.ammoUsed = 0
        tank.grenades = 0
        tank.grenadeLife = 0.0
        tank.charges = when (tank.power) {
            "scatter" -> 5
            "homing", "grenade", "laser", "cannon" -> 3
            else -> 0
        }
        tank.machineRounds = if (tank.power == "rapid") 180 else 0
    }
}
