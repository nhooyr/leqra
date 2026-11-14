package com.leqra.android

import com.leqra.android.network.SnapshotDecoder
import com.leqra.core.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class RulePersistenceTest {
    @Test
    fun allCustomRuleFieldsSurviveJsonPreferenceRoundTrip() {
        val rules =
            RoomRules.localDefaults("koth")
                .copy(
                    infinityTarget = 51,
                    infinityRandomBots = true,
                    infinityBotDifficulty = "godlike",
                    infinityRandomDifficulty = true,
                    infinityBotSpawnRate = .5,
                    teamMode = "teams",
                    mapSize = "ultrawide",
                    portraitMaze = true,
                    scoreTarget = 120,
                    timeLimit = 600,
                    respawnSeconds = 9,
                    pickupRate = "slow",
                    weapons = listOf("laser", "speed", "starman"),
                    friendlyFire = true,
                    teamNames = listOf("FOXES", "DOGS", "OWLS", "CATS"),
                    teamColors = listOf(7, 5, 4, 3),
                )
        val encoded = GameSession.rulesJson(rules).toString()
        assertEquals(rules, SnapshotDecoder.rules(JSONObject(encoded)))
    }

    @Test
    fun savedModeProfilesRetainIndependentTargetsAndUseCurrentGeometry() {
        val elimination =
            RoomRules.localDefaults()
                .copy(
                    mapSize = "giant",
                    portraitMaze = true,
                    scoreTarget = 12,
                    weapons = listOf("grenade"),
                )
        val hill = elimination.selectingMode("koth").copy(scoreTarget = 90)
        val saved =
            JSONObject()
                .put("elimination", GameSession.rulesJson(elimination))
                .put("koth", GameSession.rulesJson(hill))
        val reloaded = JSONObject(saved.toString())
        val current = hill.copy(mapSize = "ultrawide")
        val restored =
            current.selectingMode(
                "elimination",
                SnapshotDecoder.rules(reloaded.getJSONObject("elimination")),
            )
        assertEquals(12, restored.scoreTarget)
        assertEquals(listOf("grenade"), restored.weapons)
        assertEquals("ultrawide", restored.mapSize)
        assertTrue(restored.portraitMaze)
        assertEquals(90, SnapshotDecoder.rules(reloaded.getJSONObject("koth")).scoreTarget)
    }
}
