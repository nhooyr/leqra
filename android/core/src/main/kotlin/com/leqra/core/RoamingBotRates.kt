package com.leqra.core

/** Canonical rates retain the exact total and mixture from older room presets. */
fun RoomRules.roamingBotSpawnRates(): Map<String, Double> {
    infinityBotSpawnRates?.let { source ->
        return BotDifficulty.names.associateWith { level ->
            source[level]?.takeIf { it.isFinite() && it in 0.0..4.0 } ?: 0.0
        }
    }
    val legacyRate = infinityBotSpawnRate.takeIf { it in listOf(.5, 1.0, 2.0, 4.0) } ?: 2.0
    val selected = BotDifficulty.index(infinityBotDifficulty)
    val levels = if (infinityRandomDifficulty) selected + 1 else 1
    return BotDifficulty.names
        .mapIndexed { index, level ->
            level to
                if (index == selected || infinityRandomDifficulty && index < selected)
                    legacyRate / levels
                else 0.0
        }
        .toMap()
}

/** A zero rate cannot be selected, including at exact weighted boundaries. */
fun RoomRules.roamingBotDifficulty(unit: Double): String? {
    val rates = roamingBotSpawnRates()
    val total = rates.values.sum()
    if (!infinityRandomBots || total <= 0) return null
    var remaining =
        unit.takeIf { it.isFinite() }?.coerceIn(0.0, Math.nextDown(1.0))?.times(total) ?: 0.0
    for (level in BotDifficulty.names) {
        val rate = rates.getValue(level)
        if (rate > 0 && remaining < rate) return level
        remaining -= rate
    }
    return BotDifficulty.names.lastOrNull { rates.getValue(it) > 0 }
}

fun RoomRules.infinityStartError(teams: List<Int>): String? {
    if (
        !infinity ||
            infinityTarget <= 0 ||
            infinityRandomBots && roamingBotSpawnRates().values.any { it > 0 }
    )
        return null
    val sides =
        if (teamMode == "teams") teams.map { it.coerceIn(1, 4) }.distinct().size else teams.size
    return if (sides < 2)
        "Add an opposing tank or enable a roaming bot spawn rate to play to a score target."
    else null
}
