package com.leqra.android

import android.view.KeyEvent
import android.view.KeyEvent.*
import com.leqra.core.GameInput

internal enum class NativeControlAction(val label: String) {
    FORWARD("Forward"),
    REVERSE("Reverse"),
    LEFT("Turn left"),
    RIGHT("Turn right"),
    FIRE("Fire"),
    FIRE_ALT("Fire (alternate)"),
}

/** Both keyboard layouts control the same pilot, including when hardware controls P2. */
internal class NativeControlBindings private constructor(private val keys: List<Int>) {
    operator fun get(layout: Int, action: NativeControlAction) = keys[index(layout, action)]

    operator fun contains(key: Int) = key in keys

    fun isTurn(key: Int) =
        (0 until layoutCount).any {
            key == get(it, NativeControlAction.LEFT) || key == get(it, NativeControlAction.RIGHT)
        }

    fun assign(layout: Int, action: NativeControlAction, key: Int): NativeControlBindings {
        require(validKey(key)) {
            "That key is reserved. Escape, P, M, F, Tab and system shortcuts cannot be assigned."
        }
        val index = index(layout, action)
        require(key == keys[index] || key !in keys) {
            "That key is already assigned. Change the other binding first."
        }
        return NativeControlBindings(keys.toMutableList().apply { this[index] = key })
    }

    fun input(pressed: Set<Int>): GameInput {
        fun held(action: NativeControlAction) =
            get(0, action) in pressed || get(1, action) in pressed
        return GameInput(
            forward = held(NativeControlAction.FORWARD),
            reverse = held(NativeControlAction.REVERSE),
            left = held(NativeControlAction.LEFT),
            right = held(NativeControlAction.RIGHT),
            fire = held(NativeControlAction.FIRE) || held(NativeControlAction.FIRE_ALT),
            touchAim = false,
        )
    }

    fun encode() = keys.joinToString(",")

    companion object {
        const val storageKey = "nativeHardwareControls.v1"
        const val layoutCount = 2
        val defaults =
            NativeControlBindings(
                listOf(
                    KEYCODE_W,
                    KEYCODE_S,
                    KEYCODE_A,
                    KEYCODE_D,
                    KEYCODE_Q,
                    KEYCODE_C,
                    KEYCODE_DPAD_UP,
                    KEYCODE_DPAD_DOWN,
                    KEYCODE_DPAD_LEFT,
                    KEYCODE_DPAD_RIGHT,
                    KEYCODE_SPACE,
                    KEYCODE_ENTER,
                ),
            )

        private val punctuation =
            setOf(
                KEYCODE_COMMA,
                KEYCODE_PERIOD,
                KEYCODE_MINUS,
                KEYCODE_EQUALS,
                KEYCODE_LEFT_BRACKET,
                KEYCODE_RIGHT_BRACKET,
                KEYCODE_BACKSLASH,
                KEYCODE_SEMICOLON,
                KEYCODE_APOSTROPHE,
                KEYCODE_SLASH,
            )

        private fun index(layout: Int, action: NativeControlAction) =
            layout * NativeControlAction.entries.size + action.ordinal

        private fun validKey(key: Int) =
            when (key) {
                KEYCODE_F,
                KEYCODE_M,
                KEYCODE_P -> false
                in KEYCODE_A..KEYCODE_Z,
                in KEYCODE_0..KEYCODE_9,
                in KEYCODE_DPAD_UP..KEYCODE_DPAD_RIGHT,
                in KEYCODE_NUMPAD_0..KEYCODE_NUMPAD_RIGHT_PAREN,
                in punctuation,
                KEYCODE_SPACE,
                KEYCODE_ENTER,
                KEYCODE_SHIFT_LEFT,
                KEYCODE_SHIFT_RIGHT -> true
                else -> false
            }

        fun decode(saved: String?): NativeControlBindings {
            val parsed =
                saved?.split(',')?.map { it.toIntOrNull() ?: return defaults } ?: return defaults
            val count = layoutCount * NativeControlAction.entries.size
            return if (
                parsed.size == count && parsed.toSet().size == count && parsed.all(::validKey)
            )
                NativeControlBindings(parsed)
            else defaults
        }

        fun label(key: Int): String =
            when (key) {
                KEYCODE_DPAD_UP -> "↑"
                KEYCODE_DPAD_DOWN -> "↓"
                KEYCODE_DPAD_LEFT -> "←"
                KEYCODE_DPAD_RIGHT -> "→"
                KEYCODE_COMMA -> ","
                KEYCODE_PERIOD -> "."
                KEYCODE_MINUS -> "-"
                KEYCODE_EQUALS -> "="
                KEYCODE_LEFT_BRACKET -> "["
                KEYCODE_RIGHT_BRACKET -> "]"
                KEYCODE_BACKSLASH -> "\\"
                KEYCODE_SEMICOLON -> ";"
                KEYCODE_APOSTROPHE -> "'"
                KEYCODE_SLASH -> "/"
                else ->
                    KeyEvent.keyCodeToString(key)
                        .removePrefix("KEYCODE_")
                        .replace("NUMPAD_", "NUM ")
                        .replace('_', ' ')
            }
    }
}
