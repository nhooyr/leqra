package com.leqra.core

import java.util.Locale

object PilotIdentity {
    private val botPrefix = Regex("^bot(?:\\s+|$)", RegexOption.IGNORE_CASE)
    private val publicName = Regex("^Bot [0-9]+(?: - Godlike)?$")
    private val wordSpace = Regex("\\s+")

    fun botName(name: String): String =
        if (publicName.matches(name)) name
        else name.trim().replace(botPrefix, "").lowercase(Locale.ROOT).split(wordSpace).joinToString(" ") { it.replaceFirstChar { letter -> letter.titlecase(Locale.ROOT) } }

    fun label(name: String, bot: Boolean, seat: Int = 0): String =
        if (bot) if (publicName.matches(name)) name else ("Bot " + botName(name)).trimEnd()
        else name + if (seat in 1..2) " (P$seat)" else ""

    fun leaderboardLabel(name: String, bot: Boolean, seat: Int = 0): String =
        label(name, bot, seat) + if (bot && publicName.matches(name)) " · BOT" else ""
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
