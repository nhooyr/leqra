package com.leqra.core

import kotlin.math.abs

/** Deliberately hesitant decisions. The biased aim stays fixed until the next think. */
internal class DumbBotBrain(bornAt: Double) {
    var aim = 0.0
        private set

    private var nextThink = bornAt
    private var nextShot = bornAt + 1.8
    private var target = -1

    fun reconsider(
        now: Double,
        targetID: Int,
        targetAngle: Double,
        visible: Boolean,
        random: () -> Double,
    ): Boolean {
        if (now + 1e-9 < nextThink) return false
        nextThink = now + .9
        target = -1
        if (visible && random() >= .35) {
            target = targetID
            aim = targetAngle + (random() * 2 - 1) * .6
        }
        return true
    }

    fun tracks(targetID: Int, visible: Boolean) = visible && target == targetID

    /** Pulses remain slow even with rapid fire, which normally repeats while held. */
    fun trigger(now: Double, angle: Double, allowed: Boolean): Boolean {
        if (
            target < 0 || !allowed || now + 1e-9 < nextShot ||
                abs(TankMovement.angleDelta(aim, angle)) >= .36
        )
            return false
        nextShot = now + 1.8
        return true
    }
}
