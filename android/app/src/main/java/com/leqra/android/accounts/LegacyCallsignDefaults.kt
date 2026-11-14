package com.leqra.android.accounts

import java.util.Locale

/** Only defaults shipped by earlier clients are upgraded, and only before creating a key. */
internal object LegacyCallsignDefaults {
    private val spaces = Regex("\\s+")
    private val numbered = Regex("PILOT [1-9][0-9]{2}")
    private val names = setOf("PILOT", "PLAYER 1", "PLAYER 2", "CO-PILOT", "YOU", "SNOW FOX")

    fun shouldGenerate(name: String?, credentialPresent: Boolean): Boolean {
        if (credentialPresent || name == null) return false
        val canonical = name.trim().replace(spaces, " ").uppercase(Locale.ROOT)
        return canonical in names || numbered.matches(canonical)
    }
}
