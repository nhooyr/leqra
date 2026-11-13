package com.leqra.android

internal data class LocalBot(
    val id: Int,
    val name: String,
    val colorIndex: Int,
    val difficulty: String = "normal",
    val team: Int = 0,
)
