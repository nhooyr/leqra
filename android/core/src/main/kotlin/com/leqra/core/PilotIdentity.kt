package com.leqra.core

import java.util.Locale

object PilotIdentity {
    private val botPrefix = Regex("^bot(?:\\s+|$)", RegexOption.IGNORE_CASE)
    private val publicName = Regex("^Bot ([0-9]+)(?: - (Dumb|Easy|Medium|Normal|Hard|Godlike))?$", RegexOption.IGNORE_CASE)
    private val wordSpace = Regex("\\s+")

    fun botName(name: String): String =
        publicName.matchEntire(name)?.let { match ->
            "Bot " + match.groupValues[1] + match.groupValues[2].takeIf { it.isNotEmpty() }?.let { " - " + BotDifficulty.title(publicDifficulty(it)) }.orEmpty()
        } ?: name.trim().replace(botPrefix, "").lowercase(Locale.ROOT).split(wordSpace).joinToString(" ") { it.replaceFirstChar { letter -> letter.titlecase(Locale.ROOT) } }

    fun label(name: String, bot: Boolean, seat: Int = 0): String =
        if (bot) if (publicName.matches(name)) botName(name) else ("Bot " + botName(name)).trimEnd()
        else name + if (seat in 1..2) " (P$seat)" else ""

    fun leaderboardLabel(name: String, bot: Boolean, seat: Int = 0): String =
        if (bot) publicName.matchEntire(name)?.let { "Bot " + it.groupValues[1] } ?: label(name, true)
        else label(name, false, seat)

    /** A callsign never assigns a difficulty to a human or invents a missing room tier. */
    fun leaderboardDifficulty(name: String, bot: Boolean, difficulty: String = ""): String? {
        if (!bot) return null
        val actual = difficulty.lowercase(Locale.ROOT)
        if (actual in BotDifficulty.names) return actual
        return publicName.matchEntire(name)?.groupValues?.get(2)?.let(::publicDifficulty)?.takeIf { it in BotDifficulty.names }
    }

    private fun publicDifficulty(title: String) = title.lowercase(Locale.ROOT).let { if (it == "medium") "normal" else it }
}

data class GodlikeSpawn(val id: Int, val spawnSerial: Int, val name: String)

/** Repeated snapshots and transport reconnects never repeat a life announcement. */
class GodlikeSpawnNotices {
    private val seen = LinkedHashMap<Pair<Int, Int>, Double>()
    private var message: String? = null
    private var until = 0.0

    val rememberedLives: Int
        get() = seen.size

    fun accept(events: List<GodlikeSpawn>, now: Double) {
        seen.entries.removeAll { now - it.value > 60 }
        for (event in events) {
            val key = event.id to event.spawnSerial
            if (seen.containsKey(key)) continue
            seen[key] = now
            while (seen.size > 128) seen.remove(seen.keys.first())
            message = "${event.name} spawned nearby. Watch out!"
            until = now + 6
        }
    }

    fun current(now: Double): String? = message.takeIf { now < until }

    fun clear() {
        seen.clear()
        message = null
        until = 0.0
    }
}
