package com.leqra.android

internal data class LocalBot(
    val id: Int,
    val name: String,
    val colorIndex: Int,
    val difficulty: String = "normal",
    val team: Int = 0,
)

internal object BotNames {
    private val candidates = listOf("Rust", "Vapor", "Ember", "Nova", "Comet", "Onyx", "Blitz")
    fun next(used: Collection<String>, id: Int): String =
        candidates.firstOrNull { candidate -> used.none { it.equals(candidate, ignoreCase = true) } } ?: "Bot $id"
}
