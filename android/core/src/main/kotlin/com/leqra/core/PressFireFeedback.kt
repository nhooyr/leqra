package com.leqra.core

import kotlin.math.max

/** Local button feedback only; never changes a tank, ammunition or projectile state. */
class PressFireFeedback {
    private var held = false
    private var generation = Int.MIN_VALUE
    private var owner = Int.MIN_VALUE
    private var life = Int.MIN_VALUE
    private var until = Double.NEGATIVE_INFINITY
    private var lastPress = Double.NEGATIVE_INFINITY

    fun controls(fire: Boolean, tank: ArenaTank?, generation: Int, playing: Boolean, now: Double, authorityAge: Double = 0.0) {
        val pressed = fire && !held
        held = fire
        synchronize(tank, generation, playing)
        if (!pressed || !playing || tank == null || tank.hp <= 0 || !now.isFinite()) return
        val age = if (authorityAge.isFinite()) max(0.0, authorityAge) else 0.0
        val boosted = tank.starmanTime > age
        if (tank.spawnProtected && tank.invulnerable > age || !boosted && tank.cooldown > age || tank.power == "grenade" || tank.grenades > 0) return
        val cooldown = PracticeArena.spec(tank.power).cooldown
        val cadence = if (boosted) .065 else if (cooldown > 0) cooldown else .15
        if (now - lastPress + 1e-9 < cadence) return
        lastPress = now
        until = now + .1
    }

    fun pulse(tank: ArenaTank?, generation: Int, playing: Boolean, now: Double): Double {
        synchronize(tank, generation, playing)
        return if (playing && tank != null && tank.hp > 0 && now.isFinite()) ((until - now) / .1).coerceIn(0.0, 1.0) else 0.0
    }

    fun reset(fire: Boolean = false) {
        held = fire
        generation = Int.MIN_VALUE
        owner = Int.MIN_VALUE
        life = Int.MIN_VALUE
        until = Double.NEGATIVE_INFINITY
        lastPress = Double.NEGATIVE_INFINITY
    }

    private fun synchronize(tank: ArenaTank?, generation: Int, playing: Boolean) {
        if (!playing || tank == null || tank.hp <= 0 || this.generation != generation || owner != tank.id || life != tank.spawnSerial) {
            until = Double.NEGATIVE_INFINITY
            lastPress = Double.NEGATIVE_INFINITY
        }
        this.generation = generation
        owner = tank?.id ?: Int.MIN_VALUE
        life = tank?.spawnSerial ?: Int.MIN_VALUE
    }
}
