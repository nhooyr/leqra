package com.leqra.core

/** Mode profiles own their scoring and arsenal; geometry belongs to the room. */
fun RoomRules.selectingMode(mode: String, remembered: RoomRules? = null): RoomRules {
    if (mode == "infinity") {
        if (infinity) return copy()
        var profile = remembered?.copy() ?: RoomRules.modeDefaults("elimination")
        if (remembered == null)
            profile =
                profile.copy(
                    teamMode = teamMode,
                    teamNames = teamNames.toList(),
                    teamColors = teamColors.toList(),
                    friendlyFire = friendlyFire,
                )
        return profile.copy(infinity = true, mapSize = mapSize, portraitMaze = portraitMaze)
    }
    if (this.mode == mode && !infinity) return copy()
    val defaults = RoomRules.modeDefaults(mode)
    var base =
        if (infinity) defaults
        else copy(scoreTarget = defaults.scoreTarget, timeLimit = defaults.timeLimit)
    if (remembered != null) base = remembered.copy()
    return base.copy(
        infinity = false,
        mode = mode,
        mapSize = mapSize,
        portraitMaze = portraitMaze,
        teamMode =
            if (mode in listOf("ctf", "survival")) "teams"
            else if (infinity) remembered?.teamMode ?: defaults.teamMode else teamMode,
    )
}

fun RoomRules.restoringModeDefaults(): RoomRules {
    val defaults = RoomRules.modeDefaults(mode)
    if (infinity)
        return copy(
            infinityTarget = defaults.infinityTarget,
            infinityRandomBots = defaults.infinityRandomBots,
            infinityBotDifficulty = defaults.infinityBotDifficulty,
            infinityRandomDifficulty = defaults.infinityRandomDifficulty,
            infinityBotSpawnRate = defaults.infinityBotSpawnRate,
            teamNames = defaults.teamNames,
            teamColors = defaults.teamColors,
            friendlyFire = false,
        )
    return defaults.copy(
        mapSize = mapSize,
        portraitMaze = portraitMaze,
        teamMode = if (mode in listOf("ctf", "survival")) "teams" else teamMode,
    )
}

/** Published and offline rosters share the server's total-seat limits. */
fun RoomRules.botCapacity(localSeats: Int = 1): Int =
    ((if (!infinity && mode == "survival") 4 else 8) - localSeats.coerceIn(1, 2)).coerceAtLeast(0)
