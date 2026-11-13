package com.leqra.core

/** The protocol limits callsigns by Unicode code points, never UTF-16 halves. */
object Callsigns {
    fun limit(value: String, maximum: Int = 16): String {
        if (maximum <= 0) return ""
        return if (value.codePointCount(0, value.length) <= maximum) value
        else value.substring(0, value.offsetByCodePoints(0, maximum))
    }
}
