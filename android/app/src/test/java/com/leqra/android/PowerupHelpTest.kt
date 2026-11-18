package com.leqra.android

import com.leqra.core.ArenaWorld
import com.leqra.core.RoomRules
import org.junit.Assert.*
import org.junit.Test

class PowerupHelpTest {
    @Test fun fixedMazeHelpFollowsSizeAndPickupRules() {
        for (mode in listOf("elimination", "ctf", "koth", "survival")) {
            val rules = RoomRules.modeDefaults(mode)
            for ((size, seconds) in listOf("compact" to 10, "standard" to 10, "large" to 10, "huge" to 15, "giant" to 15, "ultrawide" to 15)) {
                rules.mapSize = size
                assertEquals(seconds, PowerupHelp.duration(rules))
                assertTrue(PowerupHelp.description("laser", rules).contains("$seconds seconds"))
                assertTrue(PowerupHelp.description("cannon", rules).contains("arena rim"))
            }
            rules.pickupRate = "off"
            assertTrue(PowerupHelp.summary(rules).contains("spawning is off"))
            rules.pickupRate = "fast"
            rules.weapons = listOf("laser", "shield")
            assertTrue(PowerupHelp.summary(rules).contains("2 power-up types enabled, fast"))
            rules.weapons = emptyList()
            assertTrue(PowerupHelp.summary(rules).contains("spawning is off"))
        }
    }

    @Test fun infinityHelpNeverDescribesIgnoredFixedMazeRules() {
        val rules = RoomRules.modeDefaults("infinity").apply { pickupRate = "off"; weapons = emptyList(); mapSize = "compact" }
        assertTrue(PowerupHelp.summary(rules).contains("always spawns all ten"))
        assertEquals(15, PowerupHelp.duration(rules))
        assertEquals(8, PowerupHelp.starDuration(rules))
        assertFalse(PowerupHelp.description("cannon", rules).contains("rim"))
        assertFalse(PowerupHelp.description("starman", rules).contains("Objective"))
        PowerupHelp.kinds.forEach { assertTrue(PowerupHelp.title(it).isNotBlank()); assertTrue(PowerupHelp.description(it, rules).isNotBlank()) }
        assertEquals("Machine gun", PowerupHelp.title("rapid"))
        assertEquals("Shotgun", PowerupHelp.title("scatter"))
        assertEquals("Homing missile", PowerupHelp.title("homing"))
    }

    @Test fun fixedStarmanDurationMatchesEachMapSize() {
        val rules = RoomRules()
        listOf("compact" to 4, "standard" to 4, "large" to 5, "huge" to 6, "giant" to 7, "ultrawide" to 8).forEach { (size, seconds) ->
            rules.mapSize = size
            assertEquals(seconds, PowerupHelp.starDuration(rules))
            assertTrue(PowerupHelp.description("starman", rules).contains("$seconds seconds"))
        }
    }

    @Test fun grenadeControlInstructionsAreOnlyInTheSidebar() {
        val rules = RoomRules.modeDefaults("elimination").apply { mapSize = "standard" }
        val rulesDescription = PowerupHelp.description("grenade", rules)
        assertTrue(rulesDescription.contains("contact or after a 10-second fuse"))
        assertTrue(rulesDescription.contains("Walls block the blast"))
        assertTrue(rulesDescription.contains("3 throws or 10 seconds"))
        assertFalse(rulesDescription.contains("Fire"))

        val sidebarDescription = PowerupHelp.description("grenade", rules, includeGrenadeControls = true)
        assertTrue(sidebarDescription.startsWith(rulesDescription))
        assertTrue(sidebarDescription.contains("Tap or hold Fire to throw"))
        assertTrue(sidebarDescription.contains("press Fire again to detonate early"))
        assertTrue(sidebarDescription.contains("Release Fire after detonation to shoot again"))
    }

    @Test fun manualUsesTheActiveMazeAndListsDisabledWeapons() {
        val rules = RoomRules.modeDefaults("ctf").apply {
            mapSize = "compact"
            pickupRate = "fast"
            weapons = listOf("laser", "laser")
        }
        val world = ArenaWorld(cols = 16, rows = 14)
        val summary = PowerupHelp.summary(rules, world)
        assertTrue(summary.contains("1 power-up type enabled"))
        assertTrue(summary.contains("every 2–3.5 seconds"))
        assertTrue(summary.contains("Most effects last 15 seconds"))
        assertTrue(summary.contains("Starman lasts 7 seconds"))
        assertTrue(summary.contains("expire after 61 seconds"))
        assertTrue(PowerupHelp.description("laser", rules, world).contains("twice the maze perimeter"))
        assertFalse(PowerupHelp.description("laser", rules, world).startsWith("Disabled"))
        assertTrue(PowerupHelp.description("homing", rules, world).startsWith("Disabled"))
        assertTrue(PowerupHelp.description("laser", rules.copy(pickupRate = "off"), world).startsWith("Disabled"))

        val infinity = rules.copy(infinity = true, pickupRate = "off")
        assertEquals(30, PowerupHelp.groundLifetime(infinity, world))
        assertTrue(PowerupHelp.description("laser", infinity, world).contains("36 maze cells"))
        assertTrue(PowerupHelp.description("homing", infinity, world).contains("18 maze cells"))
        assertFalse(PowerupHelp.description("homing", infinity, world).startsWith("Disabled"))
    }
}
