package com.leqra.android

import android.view.KeyEvent.*
import org.junit.Assert.*
import org.junit.Test

class NativeControlBindingsTest {
    @Test
    fun bothLayoutsSupplyIndependentKeysForTheSameActions() {
        val bindings = NativeControlBindings.defaults
        assertTrue(bindings.input(setOf(KEYCODE_W, KEYCODE_DPAD_LEFT, KEYCODE_ENTER)).let {
            it.forward && it.left && it.fire && !it.reverse && !it.right && !it.touchAim
        })
        assertTrue(bindings.input(setOf(KEYCODE_C)).fire)
        assertTrue(bindings.input(setOf(KEYCODE_SPACE)).fire)
        assertFalse(bindings.input(emptySet()).fire)
    }

    @Test
    fun remapPersistsAndReplacesOnlyTheChosenBinding() {
        val bindings = NativeControlBindings.defaults.assign(0, NativeControlAction.FORWARD, KEYCODE_I)
        val decoded = NativeControlBindings.decode(bindings.encode())
        assertEquals(KEYCODE_I, decoded[0, NativeControlAction.FORWARD])
        assertFalse(KEYCODE_W in decoded)
        assertFalse(decoded.input(setOf(KEYCODE_W)).forward)
        assertTrue(decoded.input(setOf(KEYCODE_I)).forward)
        assertTrue(decoded.input(setOf(KEYCODE_DPAD_UP)).forward)
    }

    @Test
    fun invalidAndDuplicateKeysDoNotReplaceAWorkingLayout() {
        val bindings = NativeControlBindings.defaults
        for (key in listOf(KEYCODE_ESCAPE, KEYCODE_M, KEYCODE_TAB, KEYCODE_DPAD_UP, KEYCODE_Q)) {
            assertThrows(IllegalArgumentException::class.java) {
                bindings.assign(0, NativeControlAction.FORWARD, key)
            }
        }
        assertEquals(bindings.encode(), NativeControlBindings.decode("1,2,invalid").encode())
        assertEquals(bindings.encode(), NativeControlBindings.decode(bindings.encode().replaceFirst("$KEYCODE_W,", "$KEYCODE_S,")).encode())
    }
}
