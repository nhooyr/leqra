package com.leqra.android

import android.view.KeyEvent
import com.leqra.core.GameInput
import org.junit.Assert.*
import org.junit.Test

class GamepadControlsTest {
    @Test
    fun controllerAssignmentDoesNotMoveAHeldInputBetweenSeats() {
        val pads = GamepadControls()
        pads.updateDevices(listOf(1, 2, 3), primary = true, secondary = true)
        val p1 = pads.inputForSeat(0, primary = true, secondary = true)!!
        val p2 = pads.inputForSeat(1, primary = true, secondary = true)!!
        assertNull(pads.inputForDevice(3, primary = true, secondary = true))
        p1.key(KeyEvent.KEYCODE_BUTTON_A, down = true, repeat = false)
        p2.key(KeyEvent.KEYCODE_BUTTON_R1, down = true, repeat = false)
        pads.updateDevices(listOf(2, 3), primary = true, secondary = true)
        assertFalse(pads.inputForSeat(0, primary = true, secondary = true)!!.firing)
        assertSame(p2, pads.inputForDevice(2, primary = true, secondary = true))
        assertTrue(p2.firing)
        pads.clear()
        assertFalse(p2.firing)
        assertSame(p2, pads.inputForSeat(1, primary = true, secondary = true))
    }

    @Test
    fun soleControllerCanSteerTheRemainingLocalPilot() {
        val pads = GamepadControls()
        pads.updateDevices(listOf(1), primary = false, secondary = true)
        val fallback = pads.inputForDevice(1, primary = false, secondary = true)!!
        assertSame(fallback, pads.inputForSeat(1, primary = false, secondary = true))
        fallback.key(KeyEvent.KEYCODE_BUTTON_A, down = true, repeat = false)
        pads.updateDevices(listOf(1, 3), primary = false, secondary = true)
        assertFalse(fallback.firing)
        assertNull(pads.inputForDevice(1, primary = false, secondary = true))
        assertNotNull(pads.inputForDevice(3, primary = false, secondary = true))
        pads.updateDevices(listOf(1), primary = false, secondary = true)
        assertFalse(pads.inputForSeat(1, primary = false, secondary = true)!!.firing)
    }

    @Test
    fun sticksAndDpadProduceDriveAndAimForTheTankSimulation() {
        val pad = GamepadInput()
        fun read() = GameInput(touchAim = false).also { pad.merge(it) }
        pad.motion(.08, .08, 0.0, 0.0, 0.0, 0.0, 0.0)
        assertEquals(0.0, read().stickX, 0.0)
        pad.motion(.7, -.4, 0.0, 0.0, 0.0, 0.0, 0.0)
        assertEquals(.7, read().stickX, 0.0)
        assertTrue(read().touchAim)
        assertFalse(read().aimOnly)
        pad.motion(.7, -.4, 0.0, 1.0, 0.0, 0.0, 0.0)
        assertEquals(1.0, read().stickY, 0.0)
        assertTrue(read().aimOnly)
        assertTrue(read().forward)
        pad.key(KeyEvent.KEYCODE_DPAD_DOWN_LEFT, down = true, repeat = false)
        assertTrue(read().reverse)
        assertTrue(read().left)
        assertTrue(pad.left)
        assertFalse(pad.right)
        assertFalse(read().forward)
        pad.key(KeyEvent.KEYCODE_DPAD_DOWN_LEFT, down = false, repeat = false)
        pad.motion(0.0, 0.0, -1.0, 0.0, 1.0, -1.0, 0.0)
        assertTrue(read().forward)
        assertTrue(read().right)
        assertTrue(pad.right)
        assertFalse(pad.left)
        pad.motion(0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0)
        assertTrue(read().aimOnly)
        assertFalse(read().forward)
    }

    @Test
    fun releasingOneFireAliasPreservesTheOther() {
        val pad = GamepadInput()
        pad.motion(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, .5)
        pad.key(KeyEvent.KEYCODE_BUTTON_A, down = true, repeat = false)
        pad.key(KeyEvent.KEYCODE_BUTTON_A, down = false, repeat = false)
        assertTrue(pad.firing)
        pad.motion(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, .3)
        assertTrue(pad.firing)
        pad.motion(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, .2)
        assertFalse(pad.firing)
        pad.key(KeyEvent.KEYCODE_BUTTON_A, down = true, repeat = true)
        assertFalse("Held key repeats after pausing cannot start firing", pad.firing)
    }

    @Test
    fun reenablingControlsWaitsForHeldAxesToReturnToNeutral() {
        val pads = GamepadControls()
        pads.updateDevices(listOf(1), primary = true, secondary = false)
        val pad = pads.inputForSeat(0, primary = true, secondary = false)!!
        fun motion(value: Double) = pad.motion(value, 0.0, 0.0, value, value, 0.0, value)
        fun read() = GameInput(touchAim = false).also { pad.merge(it) }
        motion(.75)
        assertTrue(read().fire)
        pads.enabled = false
        assertNull(pads.inputForDevice(1, primary = true, secondary = false))
        assertFalse(read().fire)
        pads.enabled = true
        motion(.75)
        assertEquals(0.0, read().stickX, 0.0)
        assertEquals(0.0, read().stickY, 0.0)
        assertFalse(read().right)
        assertFalse(read().fire)
        motion(0.0)
        motion(.75)
        assertEquals(.75, read().stickY, 0.0)
        assertTrue(read().right)
        assertTrue(read().fire)
    }
}
