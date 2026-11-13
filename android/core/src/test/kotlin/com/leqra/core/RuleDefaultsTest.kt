package com.leqra.core

import org.junit.Assert.*
import org.junit.Test

class RuleDefaultsTest {
    @Test
    fun localDefaultsUseCompactAndMatchWebTargets() {
        assertEquals("large", RoomRules().mapSize)
        for ((mode, target, time, team) in
            listOf(
                listOf("elimination", 5, 75, "ffa"),
                listOf("ctf", 3, 180, "teams"),
                listOf("koth", 30, 180, "ffa"),
                listOf("survival", 15, 75, "teams"),
                listOf("infinity", 5, 75, "ffa"),
            )) {
            val r = RoomRules.localDefaults(mode as String)
            assertEquals("compact", r.mapSize)
            assertEquals(target, r.scoreTarget)
            assertEquals(time, r.timeLimit)
            assertEquals(team, r.teamMode)
            assertEquals(mode == "infinity", r.infinity)
            assertEquals(10, r.weapons.size)
        }
    }

    @Test
    fun finiteModeSwitchKeepsRoomGeometryTeamsAndArsenal() {
        val r =
            RoomRules.localDefaults()
                .copy(
                    mapSize = "ultrawide",
                    portraitMaze = true,
                    teamMode = "teams",
                    weapons = listOf("grenade"),
                    pickupRate = "slow",
                    friendlyFire = true,
                    scoreTarget = 12,
                    timeLimit = 240,
                )
        assertEquals(r, r.selectingMode("elimination"))
        val hill = r.selectingMode("koth")
        assertEquals(30, hill.scoreTarget)
        assertEquals(180, hill.timeLimit)
        assertEquals("ultrawide", hill.mapSize)
        assertTrue(hill.portraitMaze)
        assertEquals("teams", hill.teamMode)
        assertEquals(listOf("grenade"), hill.weapons)
        assertEquals("slow", hill.pickupRate)
        assertTrue(hill.friendlyFire)
        assertEquals("teams", r.copy(teamMode = "ffa").selectingMode("ctf").teamMode)
        assertEquals("teams", r.copy(teamMode = "ffa").selectingMode("survival").teamMode)
    }

    @Test
    fun rememberedProfilesRestoreScoringButNotOldMapGeometry() {
        val finite =
            RoomRules.localDefaults()
                .copy(
                    mapSize = "huge",
                    portraitMaze = true,
                    teamMode = "teams",
                    teamNames = listOf("FOXES", "Team 2", "Team 3", "Team 4"),
                    teamColors = listOf(6, 1, 2, 3),
                    friendlyFire = true,
                    weapons = listOf("laser"),
                    pickupRate = "off",
                )
        val endless = finite.selectingMode("infinity")
        assertTrue(endless.infinity)
        assertEquals("huge", endless.mapSize)
        assertTrue(endless.portraitMaze)
        assertEquals(finite.teamNames, endless.teamNames)
        assertEquals(finite.teamColors, endless.teamColors)
        assertTrue(endless.friendlyFire)
        assertEquals(10, endless.weapons.size)
        assertEquals(endless, endless.selectingMode("infinity"))
        assertEquals("ffa", endless.selectingMode("koth").teamMode)
        val saved =
            RoomRules.modeDefaults("koth")
                .copy(
                    mapSize = "standard",
                    scoreTarget = 45,
                    teamMode = "teams",
                    weapons = listOf("cannon"),
                )
        val restored = endless.selectingMode("koth", saved)
        assertFalse(restored.infinity)
        assertEquals(45, restored.scoreTarget)
        assertEquals(listOf("cannon"), restored.weapons)
        assertEquals("huge", restored.mapSize)
        assertTrue(restored.portraitMaze)
    }

    @Test
    fun restoreDefaultsKeepsRoomMapAndHiddenInfinitySettings() {
        val r =
            RoomRules.localDefaults("koth")
                .copy(
                    mapSize = "giant",
                    portraitMaze = true,
                    teamMode = "teams",
                    scoreTarget = 120,
                    timeLimit = 600,
                    weapons = listOf("ghost"),
                )
        val fixed = r.restoringModeDefaults()
        assertEquals("giant", fixed.mapSize)
        assertTrue(fixed.portraitMaze)
        assertEquals("teams", fixed.teamMode)
        assertEquals(30, fixed.scoreTarget)
        assertEquals(180, fixed.timeLimit)
        assertEquals(10, fixed.weapons.size)
        val endless =
            r.copy(
                    infinity = true,
                    infinityTarget = 200,
                    infinityRandomBots = true,
                    infinityBotDifficulty = "godlike",
                    infinityRandomDifficulty = true,
                    friendlyFire = true,
                )
                .restoringModeDefaults()
        assertTrue(endless.infinity)
        assertEquals(120, endless.scoreTarget)
        assertEquals(600, endless.timeLimit)
        assertEquals(listOf("ghost"), endless.weapons)
        assertEquals(0, endless.infinityTarget)
        assertFalse(endless.infinityRandomBots)
        assertEquals("normal", endless.infinityBotDifficulty)
        assertFalse(endless.infinityRandomDifficulty)
        assertFalse(endless.friendlyFire)
    }

    @Test
    fun localBotLimitsReserveEveryHumanSeatAndSurvivalSquadCapacity() {
        for (mode in listOf("infinity", "elimination", "ctf", "koth", "survival")) {
            val rules = RoomRules.localDefaults(mode)
            assertEquals(if (mode == "survival") 3 else 7, rules.botCapacity(1))
            assertEquals(if (mode == "survival") 2 else 6, rules.botCapacity(2))
        }
    }
}
