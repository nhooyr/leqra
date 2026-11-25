package com.leqra.android

import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import com.leqra.core.GameInput
import kotlin.math.abs
import kotlin.math.hypot

internal fun InputDevice.isGamepad() =
    !isVirtual &&
        (supportsSource(InputDevice.SOURCE_GAMEPAD) || supportsSource(InputDevice.SOURCE_JOYSTICK))

internal fun KeyEvent.isGamepad() =
    isFromSource(InputDevice.SOURCE_GAMEPAD) ||
        isFromSource(InputDevice.SOURCE_JOYSTICK) ||
        (isFromSource(InputDevice.SOURCE_DPAD) && device?.isGamepad() == true)

internal fun MotionEvent.isGamepadMotion() =
    actionMasked == MotionEvent.ACTION_MOVE && isFromSource(InputDevice.SOURCE_JOYSTICK)

internal class GamepadControls {
    private class Pad(val id: Int) {
        val input = GamepadInput()
    }

    private val pads = arrayOfNulls<Pad>(2)
    var enabled = true
        set(value) {
            if (field == value) return
            field = value
            clear()
        }

    fun updateDevices(ids: List<Int>, primary: Boolean, secondary: Boolean, changed: Int? = null) {
        val previousPrimary = pad(0, primary, secondary)
        val previousSecondary = pad(1, primary, secondary)
        for (index in pads.indices) {
            val current = pads[index] ?: continue
            if (current.id !in ids) pads[index] = null
            else if (current.id == changed) current.input.clear()
        }
        for (id in ids) {
            if (pads.any { it?.id == id }) continue
            val index = pads.indexOfFirst { it == null }
            if (index == -1) break
            pads[index] = Pad(id)
        }
        discardTransferredInput(previousPrimary, pad(0, primary, secondary))
        discardTransferredInput(previousSecondary, pad(1, primary, secondary))
    }

    private fun discardTransferredInput(previous: Pad?, current: Pad?) {
        if (previous !== current) {
            previous?.input?.clear()
            current?.input?.clear()
        }
    }

    private fun pad(seat: Int, primary: Boolean, secondary: Boolean): Pad? {
        if (!(if (seat == 0) primary else secondary)) return null
        return pads[seat] ?: if (primary != secondary) pads[1 - seat] else null
    }

    fun inputForSeat(seat: Int, primary: Boolean, secondary: Boolean) =
        if (enabled) pad(seat, primary, secondary)?.input else null

    fun inputForDevice(id: Int, primary: Boolean, secondary: Boolean): GamepadInput? {
        if (!enabled) return null
        return (pad(0, primary, secondary)?.takeIf { it.id == id }
                ?: pad(1, primary, secondary)?.takeIf { it.id == id })
            ?.input
    }

    fun clear() = pads.forEach { it?.input?.clear() }
}

internal class GamepadInput {
    private val held = mutableSetOf<Int>()
    private var driveX = 0.0
    private var driveY = 0.0
    private var aimX = 0.0
    private var aimY = 0.0
    private var hatX = 0.0
    private var hatY = 0.0
    private var trigger = false
    private var driveNeedsNeutral = false
    private var aimNeedsNeutral = false
    private var hatNeedsNeutral = false
    private var triggerNeedsRelease = false

    val firing: Boolean
        get() = trigger || fireKeys.any(held::contains)

    val left: Boolean
        get() = !hatNeedsNeutral && hatX < -.5 || leftKeys.any(held::contains)

    val right: Boolean
        get() = !hatNeedsNeutral && hatX > .5 || rightKeys.any(held::contains)

    fun key(code: Int, down: Boolean, repeat: Boolean) {
        if (!down) held.remove(code) else if (!repeat) held.add(code)
    }

    fun motion(event: MotionEvent) {
        val device = event.device
        // Android's standard mapping uses Z/RZ for the right stick.
        fun hasAxis(code: Int) = device?.getMotionRange(code, event.source) != null
        val useRotations =
            !(hasAxis(MotionEvent.AXIS_Z) && hasAxis(MotionEvent.AXIS_RZ)) &&
                hasAxis(MotionEvent.AXIS_RX) &&
                hasAxis(MotionEvent.AXIS_RY)
        fun axis(code: Int) = event.getAxisValue(code).toDouble()
        motion(
            axis(MotionEvent.AXIS_X),
            axis(MotionEvent.AXIS_Y),
            axis(if (useRotations) MotionEvent.AXIS_RX else MotionEvent.AXIS_Z),
            axis(if (useRotations) MotionEvent.AXIS_RY else MotionEvent.AXIS_RZ),
            axis(MotionEvent.AXIS_HAT_X),
            axis(MotionEvent.AXIS_HAT_Y),
            maxOf(axis(MotionEvent.AXIS_RTRIGGER), axis(MotionEvent.AXIS_GAS)),
        )
    }

    fun motion(
        x: Double,
        y: Double,
        rightX: Double,
        rightY: Double,
        dpadX: Double,
        dpadY: Double,
        rightTrigger: Double,
    ) {
        driveX = cleanAxis(x)
        driveY = cleanAxis(y)
        aimX = cleanAxis(rightX)
        aimY = cleanAxis(rightY)
        hatX = cleanAxis(dpadX)
        hatY = cleanAxis(dpadY)
        val pressure = cleanAxis(rightTrigger)
        if (driveNeedsNeutral && hypot(driveX, driveY) <= DEAD_ZONE) driveNeedsNeutral = false
        if (aimNeedsNeutral && hypot(aimX, aimY) <= DEAD_ZONE) aimNeedsNeutral = false
        if (hatNeedsNeutral && maxOf(abs(hatX), abs(hatY)) <= .5) hatNeedsNeutral = false
        if (triggerNeedsRelease && pressure <= .25) triggerNeedsRelease = false
        trigger = !triggerNeedsRelease && pressure > (if (trigger) .25 else .35)
    }

    fun merge(input: GameInput, steer: Boolean = true) {
        input.fire = input.fire || firing
        input.forward =
            input.forward || !hatNeedsNeutral && hatY < -.5 || forwardKeys.any(held::contains)
        input.reverse =
            input.reverse || !hatNeedsNeutral && hatY > .5 || reverseKeys.any(held::contains)
        input.left = input.left || left
        input.right = input.right || right
        if (!steer) return
        val driving = !driveNeedsNeutral && hypot(driveX, driveY) > DEAD_ZONE
        if (!aimNeedsNeutral && hypot(aimX, aimY) > DEAD_ZONE) {
            input.stickX = aimX
            input.stickY = aimY
            input.touchAim = false
            input.aimOnly = true
            input.snapAim = false
            if (input.reverse) input.forward = false else if (driving) input.forward = true
        } else if (driving) {
            input.stickX = driveX
            input.stickY = driveY
            input.touchAim = true
            input.aimOnly = false
            input.snapAim = false
        }
    }

    fun clear() {
        // An axis can still be held when focus returns. Wait for its next neutral event.
        driveNeedsNeutral = driveNeedsNeutral || hypot(driveX, driveY) > DEAD_ZONE
        aimNeedsNeutral = aimNeedsNeutral || hypot(aimX, aimY) > DEAD_ZONE
        hatNeedsNeutral = hatNeedsNeutral || maxOf(abs(hatX), abs(hatY)) > .5
        triggerNeedsRelease = triggerNeedsRelease || trigger
        held.clear()
        driveX = 0.0
        driveY = 0.0
        aimX = 0.0
        aimY = 0.0
        hatX = 0.0
        hatY = 0.0
        trigger = false
    }

    companion object {
        private const val DEAD_ZONE = .18

        private fun cleanAxis(value: Double) =
            if (value.isFinite()) value.coerceIn(-1.0, 1.0) else 0.0

        private val fireKeys =
            setOf(KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_BUTTON_R1, KeyEvent.KEYCODE_BUTTON_R2)
        private val forwardKeys =
            setOf(
                KeyEvent.KEYCODE_DPAD_UP,
                KeyEvent.KEYCODE_DPAD_UP_LEFT,
                KeyEvent.KEYCODE_DPAD_UP_RIGHT,
            )
        private val reverseKeys =
            setOf(
                KeyEvent.KEYCODE_DPAD_DOWN,
                KeyEvent.KEYCODE_DPAD_DOWN_LEFT,
                KeyEvent.KEYCODE_DPAD_DOWN_RIGHT,
            )
        private val leftKeys =
            setOf(
                KeyEvent.KEYCODE_DPAD_LEFT,
                KeyEvent.KEYCODE_DPAD_UP_LEFT,
                KeyEvent.KEYCODE_DPAD_DOWN_LEFT,
            )
        private val rightKeys =
            setOf(
                KeyEvent.KEYCODE_DPAD_RIGHT,
                KeyEvent.KEYCODE_DPAD_UP_RIGHT,
                KeyEvent.KEYCODE_DPAD_DOWN_RIGHT,
            )
        val keys = fireKeys + forwardKeys + reverseKeys + leftKeys + rightKeys
    }
}
