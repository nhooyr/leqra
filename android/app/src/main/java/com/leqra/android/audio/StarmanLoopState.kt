package com.leqra.android.audio

import com.leqra.core.ArenaSnapshot

object StarmanLoopState {
    /** Only the current live local seats can start the single continuous power-up voice. */
    fun active(
        snapshot: ArenaSnapshot,
        primary: Int,
        secondary: Int?,
        gameplayActive: Boolean,
    ): Boolean {
        if (!gameplayActive || snapshot.phase != "playing" || snapshot.result != null) return false
        var index = 0
        while (index < snapshot.tanks.size) {
            val tank = snapshot.tanks[index++]
            if (
                (tank.id == primary || secondary != null && tank.id == secondary) &&
                    !tank.bot &&
                    tank.hp > 0 &&
                    tank.starmanTime > 0
            )
                return true
        }
        return false
    }
}
