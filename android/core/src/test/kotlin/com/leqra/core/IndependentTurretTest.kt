package com.leqra.core

import kotlin.math.PI
import org.junit.Assert.*
import org.junit.Test

class IndependentTurretTest {
    @Test
    fun joystickDrivesEastWhileTurretAimsNorth() {
        val tank = ArenaTank(x = 200.0, y = 200.0)
        val input = GameInput(stickX = 1.0, aimY = -1.0)
        repeat(30) { TankMovement.step(tank, input, 1.0 / 60, emptyList(), 1000.0, 1000.0) }
        assertEquals(264.0, tank.x, 1e-7)
        assertEquals(200.0, tank.y, 1e-7)
        assertEquals(0.0, tank.movementAngle, 1e-7)
        assertEquals(-PI / 2, tank.angle, 1e-7)
        assertTrue(tank.independentAim)
        TankMovement.step(tank, input.copy(stickX = 0.0), 1.0 / 60, emptyList(), 1000.0, 1000.0)
        assertEquals(264.0, tank.x, 1e-7)
        assertEquals(200.0, tank.y, 1e-7)
        assertEquals(-PI / 2, tank.angle, 1e-7)
    }
}
