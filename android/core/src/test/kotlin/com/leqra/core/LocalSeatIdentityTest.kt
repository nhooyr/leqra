package com.leqra.core

import kotlin.math.PI
import org.junit.Assert.*
import org.junit.Test

class LocalSeatIdentityTest {
    private val tick = 1.0 / 60

    private fun pilot(arena: FixedArena, id: Int) = arena.snapshot.tanks.first { it.id == id }

    @Test
    fun pairedSurvivalStartsBothPilotsInTheSquadFormationOnEveryWave() {
        val arena =
            FixedArena(
                RoomRules.localDefaults("survival"),
                "Pilot",
                0,
                botCount = 7,
                seed = 42,
                botNames = listOf("Guard", "Sentinel"),
                botDifficulties = listOf("hard", "easy"),
                secondaryPlayer = LocalPilot("Wing", 7, team = 2),
            )
        repeat(3) {
            val squad = arena.snapshot.tanks.filterNot { it.survivalEnemy }
            assertEquals(2, arena.secondaryLocalID)
            assertEquals(listOf(1, 2, 3, 4), squad.map { it.id })
            assertEquals(listOf("Pilot", "Wing", "Guard", "Sentinel"), squad.map { it.name })
            assertEquals(listOf("hard", "easy"), squad.filter { it.bot }.map { it.difficulty })
            assertEquals(4, squad.map { it.x to it.y }.distinct().size)
            assertTrue(
                squad.all { it.team == 1 && it.colorIndex == arena.rules.teamColors.first() },
            )
            assertTrue(
                squad.all {
                    it.angle == -PI / 2 &&
                        it.invulnerable == .75 &&
                        it.spawnSerial == arena.snapshot.generation
                },
            )
            arena.restartWave()
        }
    }

    @Test
    fun pairedInfinityReservesTheSecondIdBeforeCreatingTheRoster() {
        val arena = PracticeArena(42, "Pilot", 0, 2, secondaryPlayer = LocalPilot("Wing", 4))
        arena.configure(RoomRules.localDefaults("infinity"))
        arena.configurePilot(3, "Guard", 3, difficulty = "hard")
        arena.configurePilot(4, "Sentinel", 7, difficulty = "easy")
        assertEquals(2, arena.secondaryLocalID)
        assertEquals(2, arena.snapshot.players)
        assertEquals(listOf(1, 2, 3, 4), arena.snapshot.tanks.map { it.id })
        assertEquals(
            listOf("Pilot", "Wing", "Guard", "Sentinel"),
            arena.snapshot.tanks.map { it.name },
        )
        assertEquals(listOf(0, 4, 3, 7), arena.snapshot.tanks.map { it.colorIndex })
    }

    @Test
    fun pairedCaptureTheFlagSuddenDeathSpawnsEachTankSeparatelyAndRefillsAmmo() {
        val arena =
            FixedArena(
                RoomRules.localDefaults("ctf").copy(timeLimit = 1, pickupRate = "off"),
                "Pilot",
                0,
                botCount = 2,
                seed = 42,
                botTeams = listOf(2, 2),
                localTeam = 1,
                secondaryPlayer = LocalPilot("Wing", 1, team = 1),
            )
        val previousAmmo =
            arena.combat.snapshot.tanks.associate { tank ->
                tank.ammoEpoch = 40L + tank.id
                tank.id to tank.ammoEpoch
            }
        repeat(240) { arena.step(GameInput(), tick) }
        assertTrue(arena.snapshot.objectives!!.suddenDeath)
        val tanks = arena.snapshot.tanks
        assertEquals(tanks.size, tanks.map { it.x to it.y }.distinct().size)
        tanks.forEach { assertEquals(AmmoEpoch.next(previousAmmo.getValue(it.id)), it.ammoEpoch) }
    }

    @Test
    fun renamedP2AndDisplacedBotKeepSeparateProfilesAcrossRounds() {
        val arena =
            FixedArena(
                RoomRules.localDefaults().apply {
                    scoreTarget = 50
                    timeLimit = 75
                },
                "Pilot",
                0,
                2,
                seed = 42,
            )
        val originalBot = arena.combat.snapshot.tanks.first { it.id == 2 }
        arena.configurePilot(2, "Sentinel", 4, difficulty = "hard")
        arena.configureLocal("Wing", 1)
        val botID = originalBot.id
        assertTrue(botID != 2)
        arena.configurePilot(botID, "Medic", 5, difficulty = "godlike")
        arena.configurePilot(2, "Renamed wing", 6, difficulty = "hard")
        repeat(3) {
            assertFalse(pilot(arena, 2).bot)
            assertEquals("Renamed wing", pilot(arena, 2).name)
            assertEquals(6, pilot(arena, 2).colorIndex)
            assertEquals("hard", pilot(arena, 2).difficulty)
            assertTrue(pilot(arena, botID).bot)
            assertEquals("Medic", pilot(arena, botID).name)
            assertEquals("godlike", pilot(arena, botID).difficulty)
            val round = arena.snapshot.round
            repeat(181) { arena.step(GameInput(), tick) }
            arena.combat.snapshot.tanks.filter { it.id != 1 }.forEach { it.hp = 0 }
            var steps = 0
            while (arena.snapshot.round == round && steps++ < 500) arena.step(GameInput(), tick)
            assertTrue(arena.snapshot.round > round)
        }
    }

    @Test
    fun survivalDisplacedBotIdsAndProfilesSurviveWaveRestartsWithNewEnemies() {
        val arena = FixedArena(RoomRules.localDefaults("survival"), "Pilot", 0, 2, seed = 42)
        val originalBot = arena.combat.snapshot.tanks.first { it.id == 2 }
        arena.configureLocal("Wing", 1)
        val botID = originalBot.id
        arena.configurePilot(botID, "Medic", 4, difficulty = "hard")
        arena.configurePilot(2, "Renamed wing", 6)
        val world = arena.world
        repeat(3) {
            arena.restartWave()
            assertEquals(world, arena.world)
            assertEquals("Medic", pilot(arena, botID).name)
            assertTrue(pilot(arena, botID).bot)
            assertFalse(pilot(arena, botID).survivalEnemy)
            assertEquals("Renamed wing", pilot(arena, 2).name)
            assertFalse(pilot(arena, 2).bot)
            assertEquals(arena.snapshot.tanks.size, arena.snapshot.tanks.map { it.id }.toSet().size)
            assertTrue(arena.snapshot.tanks.filter { it.survivalEnemy }.none { it.id == botID })
        }
    }

    @Test
    fun addingP2CannotStealTheDisplacedBotsProjectilesOrHeldGrenade() {
        val arena = PracticeArena(42, "Pilot", 0, 1, world = ArenaWorld(840.0, 840.0, 10, 10))
        val originalBot = arena.snapshot.tanks.first { it.id == 2 }
        arena.snapshot.tanks.forEach {
            it.spawnProtected = false
            it.invulnerable = 0.0
        }
        originalBot.x = 210.0
        originalBot.y = 42.0
        originalBot.angle = PI
        PracticeArena.applyPower(originalBot, "grenade")
        arena.step(GameInput(), tick)
        val grenade = arena.snapshot.bullets.first { it.owner == 2 && it.kind == "grenade" }.id
        arena.configureLocal("Wing", 1)
        val botID = originalBot.id
        assertEquals(botID, arena.snapshot.bullets.first { it.id == grenade }.owner)
        val local = arena.snapshot.tanks.first { it.id == 2 }
        local.spawnProtected = false
        local.invulnerable = 0.0
        arena.step(mapOf(1 to GameInput(), 2 to GameInput(fire = true)), tick)
        assertTrue(arena.snapshot.bullets.any { it.id == grenade && it.owner == botID })
        assertTrue(arena.snapshot.bullets.any { it.kind.isEmpty() && it.owner == 2 })
    }

    @Test
    fun displacedBotKeepsRoundScoreAndWinnerInsteadOfGivingThemToNewP2() {
        val arena =
            FixedArena(
                RoomRules.localDefaults().apply {
                    scoreTarget = 50
                    timeLimit = 75
                },
                "Pilot",
                0,
                1,
                seed = 42,
            )
        repeat(181) { arena.step(GameInput(), tick) }
        val originalBot = arena.combat.snapshot.tanks.first { it.id == 2 }
        arena.combat.snapshot.tanks.first { it.id == 1 }.hp = 0
        arena.step(GameInput(), tick)
        assertEquals(2, arena.snapshot.winner)
        assertEquals(1, pilot(arena, 2).score)
        arena.configureLocal("Wing", 1)
        val botID = originalBot.id
        assertEquals(botID, arena.snapshot.winner)
        assertEquals(1, pilot(arena, botID).score)
        assertEquals(0, pilot(arena, 2).score)
        var steps = 0
        while (arena.snapshot.round == 1 && steps++ < 500) arena.step(GameInput(), tick)
        assertEquals(1, pilot(arena, botID).score)
        assertEquals(0, pilot(arena, 2).score)
    }
}
