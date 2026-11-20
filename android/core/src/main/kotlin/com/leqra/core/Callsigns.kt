package com.leqra.core

/** The protocol limits callsigns by Unicode code points, never UTF-16 halves. */
object Callsigns {
    const val botNamespaceMessage =
        "'Bot' and callsigns starting with 'Bot ' are reserved for bots. Generate a random callsign."

    fun canonical(value: String): String {
        val clean = StringBuilder()
        var count = 0
        value.trim().codePoints().forEach { point ->
            if (
                count < 16 &&
                    (Character.isLetterOrDigit(point) ||
                        point == 32 ||
                        point == 35 ||
                        point == 95 ||
                        point == 45)
            ) {
                clean.appendCodePoint(point)
                count++
            }
        }
        return CallsignCaseFold.fold(clean.toString().trim().replace(Regex(" +"), " "))
    }

    fun botReserved(value: String): Boolean {
        val cleaned = StringBuilder()
        value.codePoints().forEach {
            if (Character.isLetterOrDigit(it) || it == 32 || it == 35 || it == 95 || it == 45)
                cleaned.appendCodePoint(it)
        }
        val name = limit(cleaned.toString().trim().replace(Regex(" +"), " "))
        return name.equals("bot", ignoreCase = true) || name.startsWith("bot ", ignoreCase = true)
    }

    fun limit(value: String, maximum: Int = 16): String {
        if (maximum <= 0) return ""
        return if (value.codePointCount(0, value.length) <= maximum) value
        else value.substring(0, value.offsetByCodePoints(0, maximum))
    }
}
