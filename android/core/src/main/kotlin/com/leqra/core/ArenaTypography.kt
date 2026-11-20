package com.leqra.core

import kotlin.math.max

object ArenaTypography {
    /** Screen-space size shared by tank identities and their death notices. */
    fun labelSize(zoom: Double, infinity: Boolean, fontScale: Double = 1.0): Double =
        max(10 * max(1.0, fontScale), (if (infinity) 11 else 10) * zoom)
}

data class DeathNotice(val killer: String, val color: String) {
    val text: String
        get() = "Killed by $killer"

    companion object {
        fun from(tank: ArenaTank?): DeathNotice? =
            tank
                ?.takeIf { it.hp <= 0 && it.killedBy.isNotEmpty() }
                ?.let { DeathNotice(it.killedBy, it.killedByColor) }
    }
}
