package com.leqra.android

import com.leqra.core.ArenaFlag
import com.leqra.core.ArenaObjectives
import com.leqra.core.ArenaSurvival
import com.leqra.core.RoomRules
import org.junit.Assert.assertEquals
import org.junit.Test

class NativeObjectiveViewTest {
    @Test
    fun objectiveReadoutUsesTeamPaintAndShowsSuddenDeath() {
        val rules = RoomRules(teamColors = listOf(3, 5, 2, 0))
        val captureTheFlag =
            ArenaObjectives(
                mode = "ctf",
                flags =
                    listOf(
                        ArenaFlag(team = 1, home = false, carrier = 0),
                        ArenaFlag(team = 2, home = false),
                    ),
            )
        assertEquals(
            listOf(
                ObjectiveMessage("TEAM 1: FLAG CARRIED", 3),
                ObjectiveMessage("TEAM 2: FLAG DROPPED", 5),
            ),
            objectiveMessages(captureTheFlag, rules),
        )
        val hill = ArenaObjectives(mode = "koth", owner = -1, suddenDeath = true)
        assertEquals(
            listOf(
                ObjectiveMessage("HILL CONTROLLED"),
                ObjectiveMessage("SUDDEN DEATH", urgent = true),
            ),
            objectiveMessages(hill, rules),
        )
        assertEquals(
            listOf(ObjectiveMessage("WAVE 5"), ObjectiveMessage("4 ENEMIES")),
            objectiveMessages(
                ArenaObjectives(
                    mode = "survival",
                    survival = ArenaSurvival(wave = 5, enemiesRemaining = 4),
                ),
                rules,
            ),
        )
    }
}
