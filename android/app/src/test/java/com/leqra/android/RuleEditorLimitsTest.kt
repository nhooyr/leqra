package com.leqra.android

import com.leqra.core.BotDifficulty
import com.leqra.core.RoomRules
import org.junit.Assert.*
import org.junit.Test

class RuleEditorLimitsTest {
    @Test
    fun fixedEditorsCannotApplyZeroTargetsOrImmediateTimeouts() {
        for (mode in listOf("elimination", "ctf", "koth", "survival")) {
            val draft =
                RuleEditorLimits.draft(
                    RoomRules.localDefaults(mode)
                        .copy(scoreTarget = 0, timeLimit = 0, respawnSeconds = 0, teamMode = "ffa"),
                )
            assertEquals(1, draft.scoreTarget)
            assertEquals(30, draft.timeLimit)
            assertEquals(1, draft.respawnSeconds)
            if (mode == "ctf" || mode == "survival") assertEquals("teams", draft.teamMode)
        }
    }

    @Test
    fun editorRangesMatchIOSAndPreserveEveryValidValue() {
        for (mode in listOf("elimination", "ctf", "koth", "survival")) {
            val source = RoomRules.localDefaults(mode)
            val maximum = if (mode == "koth") 300 else 20
            assertEquals(
                maximum,
                RuleEditorLimits.draft(
                        source.copy(scoreTarget = 999, timeLimit = 999, respawnSeconds = 99),
                    )
                    .scoreTarget,
            )
            for (score in 1..maximum) assertEquals(
                score,
                RuleEditorLimits.draft(source.copy(scoreTarget = score)).scoreTarget,
            )
            for (seconds in 30..600 step 15) assertEquals(
                seconds,
                RuleEditorLimits.draft(source.copy(timeLimit = seconds)).timeLimit,
            )
            for (respawn in 1..10) assertEquals(
                respawn,
                RuleEditorLimits.draft(source.copy(respawnSeconds = respawn)).respawnSeconds,
            )
        }
    }

    @Test
    fun infinityAllowsEndlessAndAllTargetsWithoutFixedMatchRanges() {
        val source = RoomRules.localDefaults("infinity").copy(timeLimit = 0, scoreTarget = 0)
        for (target in 0..999) assertEquals(
            target,
            RuleEditorLimits.draft(source.copy(infinityTarget = target)).infinityTarget,
        )
        assertEquals(999, RuleEditorLimits.draft(source.copy(infinityTarget = 1000)).infinityTarget)
        assertEquals(0, RuleEditorLimits.draft(source.copy(infinityTarget = -1)).infinityTarget)
        for (difficulty in BotDifficulty.names) assertEquals(
            difficulty,
            RuleEditorLimits.draft(source.copy(infinityBotDifficulty = difficulty))
                .infinityBotDifficulty,
        )
        assertEquals(
            "normal",
            RuleEditorLimits.draft(source.copy(infinityBotDifficulty = "invalid"))
                .infinityBotDifficulty,
        )
        for (rate in listOf(.5, 1.0, 2.0, 4.0)) assertEquals(rate, RuleEditorLimits.draft(source.copy(infinityBotSpawnRate = rate)).infinityBotSpawnRate, 0.0)
        for (rate in listOf(Double.NaN, Double.POSITIVE_INFINITY, 0.0, 3.0)) assertEquals(2.0, RuleEditorLimits.draft(source.copy(infinityBotSpawnRate = rate)).infinityBotSpawnRate, 0.0)
    }
}
