package com.leqra.core

/** The protocol limits callsigns by Unicode code points, never UTF-16 halves. */
object Callsigns {
    const val botNamespaceMessage = "'Bot' and callsigns starting with 'Bot ' are reserved for bots. Generate a random callsign."
    fun botReserved(value: String): Boolean {
        val cleaned = StringBuilder()
        value.codePoints().forEach { if (Character.isLetterOrDigit(it) || it == 32 || it == 35 || it == 95 || it == 45) cleaned.appendCodePoint(it) }
        val name = limit(cleaned.toString().trim().replace(Regex(" +"), " "))
        return name.equals("bot", ignoreCase = true) || name.startsWith("bot ", ignoreCase = true)
    }
    fun limit(value: String, maximum: Int = 16): String {
        if (maximum <= 0) return ""
        return if (value.codePointCount(0, value.length) <= maximum) value
        else value.substring(0, value.offsetByCodePoints(0, maximum))
    }
}
