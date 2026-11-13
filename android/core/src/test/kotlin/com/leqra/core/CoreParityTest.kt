package com.leqra.core

import java.io.File
import java.security.MessageDigest
import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

/** Reads the shared Go/browser fixtures without an Android or JSON runtime dependency. */
private class FixtureJson(private val text: String) {
    private var at = 0

    private fun whitespace() {
        while (at < text.length && text[at].isWhitespace()) at++
    }

    fun value(): Any? {
        whitespace()
        return when (text[at]) {
            '{' -> {
                at++
                val map = linkedMapOf<String, Any?>()
                whitespace()
                if (text[at] == '}') {
                    at++
                    map
                } else {
                    while (true) {
                        val k = value() as String
                        whitespace()
                        check(text[at++] == ':')
                        map[k] = value()
                        whitespace()
                        val c = text[at++]
                        if (c == '}') break
                        check(c == ',')
                    }
                    map
                }
            }
            '[' -> {
                at++
                val list = mutableListOf<Any?>()
                whitespace()
                if (text[at] == ']') {
                    at++
                    list
                } else {
                    while (true) {
                        list.add(value())
                        whitespace()
                        val c = text[at++]
                        if (c == ']') break
                        check(c == ',')
                    }
                    list
                }
            }
            '"' -> {
                at++
                val start = at
                while (text[at] != '"') at++
                text.substring(start, at++)
            }
            't' -> {
                at += 4
                true
            }
            'f' -> {
                at += 5
                false
            }
            'n' -> {
                at += 4
                null
            }
            else -> {
                val start = at
                while (at < text.length && text[at] in "0123456789+-.eE") at++
                text.substring(start, at).toDouble()
            }
        }
    }
}

@Suppress("UNCHECKED_CAST")
private fun fixtures(name: String): List<Map<String, Any?>> {
    val file =
        generateSequence(File(".").absoluteFile) { it.parentFile }
            .map { File(it, "src/tests/fixtures/$name") }
            .first { it.exists() }
    return FixtureJson(file.readText()).value() as List<Map<String, Any?>>
}

private fun Map<String, Any?>.number(name: String, default: Double = 0.0) =
    (get(name) as? Double) ?: default

private fun Map<String, Any?>.bool(name: String) = (get(name) as? Boolean) ?: false

class CoreParityTest {
    private val tick = 1.0 / 60

    @Test
    fun seededMazeMatchesAllGoBrowserHashes() {
        for (f in fixtures("infinite-maze.json")) {
            val bounds = (f["bounds"] as List<*>).map { it as Double }
            val maze = InfiniteMaze(f.number("seed").toLong().toInt())
            val walls = maze.walls(bounds[0], bounds[1], bounds[2], bounds[3])
            assertEquals(f.number("count").toInt(), walls.size)
            val records =
                walls.joinToString(",", "[", "]") {
                    "{\"x\":${it.x.toLong()},\"y\":${it.y.toLong()},\"w\":${it.w.toLong()},\"h\":${it.h.toLong()},\"axis\":\"${it.axis}\",\"line\":${it.line.toLong()}}"
                }
            val hash =
                MessageDigest.getInstance("SHA-256").digest(records.toByteArray()).joinToString(
                    "",
                ) {
                    "%02x".format(it)
                }
            assertEquals("seed=${f["seed"]}", f["sha256"], hash)
        }
    }

    @Test
    fun cacheEvictionAndMalformedBoundsStayBounded() {
        val m = InfiniteMaze(42)
        val original = m.walls(-100.0, -100.0, 100.0, 100.0)
        repeat(150) {
            val x = it * 672.0
            m.walls(x, 0.0, x + 100, 100.0)
        }
        assertEquals(128, m.cachedChunkCount)
        assertEquals(original, m.walls(-100.0, -100.0, 100.0, 100.0))
        assertTrue(m.walls(Double.NaN, 0.0, 1.0, 1.0).isEmpty())
        assertTrue(m.walls(0.0, 0.0, 1e30, 1.0).isEmpty())
    }

    @Test
    fun touchSteeringMatchesSharedFixtures() {
        for (f in fixtures("touch-steering.json")) {
            @Suppress("UNCHECKED_CAST") val i = f["input"] as Map<String, Any?>
            val input =
                GameInput(
                    stickX = i.number("stickX"),
                    stickY = i.number("stickY"),
                    forward = i.bool("forward"),
                    reverse = i.bool("reverse"),
                    left = i.bool("left"),
                    right = i.bool("right"),
                    touchAim = i.bool("touchAim"),
                    aimOnly = i.bool("aimOnly"),
                )
            val result = TankMovement.steer(f.number("angle"), input, f.number("turnScale"), tick)
            assertEquals(f["name"].toString(), f.number("angleAfter"), result.angle, 1e-12)
            assertEquals(f["name"].toString(), f.number("throttle"), result.throttle, 1e-12)
        }
    }

    @Test
    fun launchGeometryMatchesSharedFixturesRegardlessOfWallOrder() {
        for (f in fixtures("wall_launch.json")) for (reverse in listOf(false, true)) {
            @Suppress("UNCHECKED_CAST") val raw = f["walls"] as List<Map<String, Any?>>
            val walls =
                (if (reverse) raw.reversed() else raw).map {
                    MazeWall(it.number("x"), it.number("y"), it.number("w"), it.number("h"))
                }
            val world =
                ArenaWorld(
                    width = if (f["bounds"] == null) 20000.0 else 504.0,
                    height = if (f["bounds"] == null) 20000.0 else 420.0,
                    walls = walls,
                )
            val actual =
                InfiniteMaze(world)
                    .launchRay(
                        f.number("x"),
                        f.number("y"),
                        atan2(f.number("uy"), f.number("ux")),
                        "laser",
                        f.number("radius"),
                    )
            @Suppress("UNCHECKED_CAST") val e = f["expected"] as Map<String, Any?>
            assertEquals(f["name"].toString(), e.bool("valid"), actual != null)
            if (actual != null) {
                assertEquals(e.number("x"), actual.x, 1e-7)
                assertEquals(e.number("y"), actual.y, 1e-7)
                assertEquals(e.number("ux"), actual.ux, 1e-7)
                assertEquals(e.number("uy"), actual.uy, 1e-7)
                assertEquals(e.number("distance"), actual.distance, 1e-7)
                assertEquals(e.bool("bounced"), actual.bounced)
            }
        }
    }

    private fun arena(map: String, bots: Int = 0): PracticeArena {
        val rules =
            RoomRules.localDefaults().apply {
                mapSize = map
                pickupRate = "off"
                weapons = emptyList()
            }
        val world =
            if (map == "infinity") null else FixedArena(rules, "MATRIX", 0, 0, seed = 42).world
        return PracticeArena(42, "MATRIX", 0, bots, world = world).also {
            it.configure(rules)
            it.snapshot.tanks.forEach { t ->
                t.spawnProtected = false
                t.invulnerable = 0.0
            }
        }
    }

    private fun advance(a: PracticeArena, input: GameInput = GameInput(), ticks: Int = 1) {
        repeat(ticks) {
            a.snapshot.pickups = emptyList()
            a.step(input, tick)
        }
    }

    @Test
    fun allTenPickupsCollectAndExpireOnEveryMap() {
        var cases = 0
        for (map in
            listOf(
                "infinity",
                "compact",
                "standard",
                "large",
                "huge",
                "giant",
                "ultrawide",
            )) for (kind in PracticeArena.pickupKinds) {
            val a = arena(map)
            val world = a.maze.world
            val area = world?.let { it.cols * it.rows } ?: 10000
            val power = if (world == null || area >= 168) 15.0 else 10.0
            val star =
                if (world == null || area >= 336) 8.0
                else if (area >= 224) 7.0
                else if (area >= 168) 6.0 else if (area >= 120) 5.0 else 4.0
            val t = a.snapshot.tanks[0]
            PracticeArena.applyPower(t, "cannon", power)
            a.snapshot.pickups = listOf(ArenaPickup(id = 999, x = t.x, y = t.y, type = kind))
            a.step(GameInput(), tick)
            assertTrue(a.snapshot.effects.any { it.kind == "pickup" })
            assertFalse(a.snapshot.pickups.any { it.id == 999 })
            assertEquals(
                if (kind in listOf("shield", "speed", "ghost", "starman")) "cannon" else kind,
                t.power,
            )
            advance(a, ticks = ((if (kind == "starman") star else power) * 60).toInt() + 2)
            when (kind) {
                "shield" -> {
                    assertEquals(0.0, t.shield, 0.0)
                    assertEquals(0, t.shieldCharges)
                }
                "speed" -> {
                    assertEquals(0.0, t.speedTime, 0.0)
                    assertEquals(0, t.speedStacks)
                }
                "ghost" -> assertEquals(0.0, t.ghostTime, 0.0)
                "starman" -> {
                    assertEquals(0.0, t.starmanTime, 0.0)
                    assertEquals("cannon", t.power)
                    assertTrue(t.powerTime > power - .1)
                }
                else -> {
                    assertEquals("", t.power)
                    assertEquals(0, t.charges)
                }
            }
            assertEquals(1, t.hp)
            cases++
        }
        assertEquals(70, cases)
    }

    private fun equip(t: ArenaTank, weapon: String, profile: String) {
        if (weapon.isNotEmpty()) PracticeArena.applyPower(t, weapon)
        if (profile in listOf("shield5", "all")) repeat(7) { PracticeArena.applyPower(t, "shield") }
        if (profile in listOf("speed5", "all")) repeat(7) { PracticeArena.applyPower(t, "speed") }
        if (profile in listOf("ghost", "ghost-starman", "all")) PracticeArena.applyPower(t, "ghost")
        if (profile in listOf("starman", "ghost-starman", "all"))
            PracticeArena.applyPower(t, "starman")
    }

    @Test
    fun everyWeaponWithEveryBuffFiresWithoutMutatingDuringPresentation() {
        var cases = 0
        for (map in listOf("infinity", "compact")) for (weapon in
            listOf("", "rapid", "scatter", "homing", "grenade", "laser", "cannon")) for (profile in
            listOf("shield5", "speed5", "ghost", "starman", "ghost-starman", "all")) {
            val a = arena(map)
            val t = a.snapshot.tanks[0]
            equip(t, weapon, profile)
            val start = t.copy()
            val boosted = t.starmanTime > 0
            val input = GameInput(forward = true, fire = true, touchAim = false)
            advance(a, input)
            assertEquals(weapon, t.power)
            assertEquals(
                128 * (if (start.speedStacks == 5) 4.25 else 1.0) / 60,
                t.x - start.x,
                1e-8,
            )
            assertEquals(
                start.charges - if (!boosted && weapon.isNotEmpty() && weapon != "rapid") 1 else 0,
                t.charges,
            )
            assertEquals(
                start.machineRounds - if (!boosted && weapon == "rapid") 1 else 0,
                t.machineRounds,
            )
            assertEquals(
                if (boosted || weapon == "laser") 0 else if (weapon == "scatter") 3 else 1,
                t.ammoUsed,
            )
            val tanks = a.snapshot.tanks.map { it.copy() }
            val bullets = a.snapshot.bullets.map { it.copy() }
            val effects = a.snapshot.effects.toList()
            a.presentationSnapshot(.5, input)
            assertEquals(tanks, a.snapshot.tanks)
            assertEquals(bullets, a.snapshot.bullets)
            assertEquals(effects, a.snapshot.effects)
            cases++
        }
        assertEquals(84, cases)
    }

    @Test
    fun allWeaponsFireAndRicochetWhenPhasedInsideWalls() {
        val wall = MazeWall(248.0, 248.0, 8.0, 92.0, "v", 252.0)
        val world = ArenaWorld(1680.0, 1680.0, 20, 20, listOf(wall))
        for (phase in listOf("ghost", "starman")) for (weapon in
            listOf("", "rapid", "scatter", "homing", "grenade", "laser", "cannon")) for (embedded in
            listOf(false, true)) {
            val a = PracticeArena(42, "PILOT", 0, 0, world = world)
            val t = ArenaTank(id = 1, x = if (embedded) 252.0 else 247.0, y = 294.0)
            PracticeArena.applyPower(t, phase)
            if (weapon.isNotEmpty()) PracticeArena.applyPower(t, weapon)
            a.snapshot.tanks = listOf(t)
            a.step(GameInput(fire = true), tick)
            assertTrue("$phase $weapon $embedded", t.recoil > 0)
            if (weapon == "laser")
                assertTrue(
                    a.snapshot.effects.any {
                        it.kind == "laser" && it.points.size >= 2 && it.points[1].x < it.points[0].x
                    },
                )
            else {
                assertEquals(if (weapon == "scatter") 3 else 1, a.snapshot.bullets.size)
                for (b in a.snapshot.bullets) if (weapon == "cannon") assertTrue(b.vx > 0)
                else {
                    assertTrue(b.vx < 0)
                    assertTrue(b.bounces >= 1)
                }
            }
        }
    }

    @Test
    fun grenadeNeedsReleaseThenPressAndNeverDamagesItsOwner() {
        for (boosted in listOf(false, true)) {
            val a = arena("compact")
            val t = a.snapshot.tanks[0]
            equip(t, "grenade", if (boosted) "starman" else "ghost")
            advance(a, GameInput(fire = true), 30)
            assertEquals(1, a.snapshot.bullets.count { it.kind == "grenade" })
            assertFalse(a.snapshot.effects.any { it.kind == "blast" })
            advance(a)
            advance(a, GameInput(fire = true))
            assertFalse(a.snapshot.bullets.any { it.kind == "grenade" })
            assertTrue(a.snapshot.effects.any { it.kind == "blast" })
            assertEquals(1, t.hp)
            assertEquals(if (boosted) 3 else 2, t.charges)
        }
    }

    @Test
    fun starmanStressIsDeterministicAndProjectilesAreBounded() {
        for (map in listOf("infinity", "compact")) for (weapon in
            listOf("", "rapid", "scatter", "homing", "grenade", "laser", "cannon")) {
            val a = arena(map, if (map == "infinity") 8 else 7)
            val b = arena(map, if (map == "infinity") 8 else 7)
            equip(a.snapshot.tanks[0], weapon, "all")
            equip(b.snapshot.tanks[0], weapon, "all")
            repeat(180) { i ->
                val input =
                    GameInput(
                        seq = i.toLong(),
                        forward = i % 120 < 90,
                        right = i % 90 >= 60,
                        fire = weapon != "grenade" || i % 60 < 40,
                        touchAim = false,
                    )
                advance(a, input)
                advance(b, input)
                assertEquals(a.snapshot, b.snapshot)
                assertTrue(a.snapshot.bullets.count { it.owner == 1 } <= 115)
                assertEquals(1, a.snapshot.tanks[0].hp)
                assertTrue(a.snapshot.effects.size <= 48)
            }
        }
    }

    @Test
    fun allFiveModesAndIndependentSeatsPersistAcrossRounds() {
        for (mode in listOf("elimination", "ctf", "koth", "survival")) {
            val rules = RoomRules.localDefaults(mode)
            val a = FixedArena(rules, "P1", 0, botCount = 3, seed = 42)
            val count = a.snapshot.tanks.size
            assertEquals(2, a.configureLocal("P2", 1))
            assertEquals(count + 1, a.snapshot.tanks.size)
            assertEquals(2, a.snapshot.tanks.count { !it.bot })
            repeat(181) { a.step(mapOf(1 to GameInput(), 2 to GameInput()), tick) }
            assertEquals("playing", a.snapshot.phase)
            assertEquals(mode, if (mode == "elimination") mode else a.snapshot.objectives?.mode)
            a.restart()
            assertEquals(count + 1, a.snapshot.tanks.size)
            assertEquals(2, a.snapshot.tanks.count { !it.bot })
            assertEquals(a.snapshot.tanks.size, a.snapshot.tanks.map { it.id }.toSet().size)
        }
        val a = PracticeArena(42, "P1", 0, 8)
        a.configure(RoomRules.localDefaults("infinity"))
        a.configureLocal("P2", 1)
        assertEquals(10, a.snapshot.tanks.size)
        assertEquals(2, a.snapshot.players)
    }

    @Test
    fun highSpeedTurningPresentationIsContinuousAndCollisionSafe() {
        val a = arena("infinity")
        val t = a.snapshot.tanks[0]
        repeat(5) { PracticeArena.applyPower(t, "speed") }
        PracticeArena.applyPower(t, "ghost")
        val input = GameInput(forward = true, right = true, touchAim = false)
        repeat(240) {
            advance(a, input)
            val p = a.presentationSnapshot(.999999, input).tanks[0]
            val predicted = t.copy()
            TankMovement.step(predicted, input, tick, a.maze)
            assertEquals(predicted.x, p.x, 1e-4)
            assertEquals(predicted.y, p.y, 1e-4)
            assertTrue(abs(TankMovement.angleDelta(p.angle, predicted.angle)) < 1e-4)
        }
    }

    @Test
    fun everyFiniteMazeSizeAndOrientationIsConnected() {
        for (size in
            listOf("compact", "standard", "large", "huge", "giant", "ultrawide")) for (portrait in
            listOf(false, true)) {
            val rules =
                RoomRules.localDefaults().apply {
                    mapSize = size
                    portraitMaze = portrait
                }
            val a = FixedArena(rules, "PILOT", 0, 0, seed = 42)
            val w = a.world
            val queue = mutableListOf(0)
            val visited = mutableSetOf(0)
            var head = 0
            while (head < queue.size) {
                val cell = queue[head++]
                val col = cell % w.cols
                val row = cell / w.cols
                for ((dx, dy) in listOf(1 to 0, -1 to 0, 0 to 1, 0 to -1)) {
                    val x = col + dx
                    val y = row + dy
                    val next = y * w.cols + x
                    if (
                        x !in 0 until w.cols ||
                            y !in 0 until w.rows ||
                            next in visited ||
                            a.maze.blocked(
                                (col + .5 + dx / 2.0) * 84,
                                (row + .5 + dy / 2.0) * 84,
                                17.0,
                            )
                    )
                        continue
                    visited.add(next)
                    queue.add(next)
                }
            }
            assertEquals(w.cols * w.rows, visited.size)
            assertTrue(a.maze.blocked(-10.0, 42.0, 17.0))
            assertTrue(a.maze.blocked(w.width + 10, 42.0, 17.0))
        }
    }

    @Test
    fun eliminationAwardsRoundChangesMazeAndFinishesAtTarget() {
        val rules =
            RoomRules.localDefaults().apply {
                scoreTarget = 2
                pickupRate = "off"
            }
        val a = FixedArena(rules, "PILOT", 0, 1, seed = 42)
        val original = a.world
        repeat(180) { a.step(GameInput(), tick) }
        repeat(2) { round ->
            a.combat.snapshot.tanks.filter { it.id != 1 }.forEach { it.hp = 0 }
            a.step(GameInput(), tick)
            assertEquals("roundOver", a.snapshot.phase)
            assertEquals(round + 1, a.snapshot.scores[1])
            repeat(120) { a.step(GameInput(), tick) }
            if (round == 0) {
                assertEquals("countdown", a.snapshot.phase)
                assertNotEquals(original.walls, a.world.walls)
                repeat(180) { a.step(GameInput(), tick) }
            }
        }
        assertEquals("matchOver", a.snapshot.phase)
    }

    @Test
    fun captureOnlyScoresOnceTheOwnFlagIsHome() {
        val rules =
            RoomRules.localDefaults("ctf").apply {
                scoreTarget = 1
                pickupRate = "off"
            }
        val a = FixedArena(rules, "PILOT", 0, 1, seed = 42)
        repeat(180) { a.step(GameInput(), tick) }
        a.combat.snapshot.tanks.forEach {
            it.bot = false
            it.invulnerable = 0.0
            it.spawnProtected = false
        }
        val t = a.combat.snapshot.tanks.first { it.id == 1 }
        val enemy = a.objectives!!.flags.first { it.team == 2 }
        val own = a.objectives!!.flags.first { it.team == 1 }
        t.x = enemy.homeX
        t.y = enemy.homeY
        a.step(GameInput(), tick)
        assertEquals(1, enemy.carrier)
        own.home = false
        own.carrier = 2
        t.x = own.homeX
        t.y = own.homeY
        a.step(GameInput(), tick)
        assertEquals(0, a.snapshot.scores[1])
        own.home = true
        own.carrier = -1
        own.x = own.homeX
        own.y = own.homeY
        a.step(GameInput(), tick)
        assertEquals(1, a.snapshot.scores[1])
        assertEquals("matchOver", a.snapshot.phase)
        assertTrue(enemy.home)
    }

    @Test
    fun hillContestedThenScoresExactlyOncePerSecond() {
        val rules =
            RoomRules.localDefaults("koth").apply {
                scoreTarget = 2
                pickupRate = "off"
            }
        val a = FixedArena(rules, "PILOT", 0, 1, seed = 42)
        repeat(180) { a.step(GameInput(), tick) }
        val hill = a.objectives!!
        a.combat.snapshot.tanks.forEachIndexed { i, t ->
            t.bot = false
            t.invulnerable = 0.0
            t.x = hill.hillX + if (i == 0) -20 else 20
            t.y = hill.hillY
        }
        repeat(60) { a.step(GameInput(), tick) }
        assertTrue(hill.contested)
        assertEquals(0, a.snapshot.scores[1])
        a.combat.snapshot.tanks[1].hp = 0
        a.combat.snapshot.tanks[1].respawnTime = 999.0
        repeat(59) { a.step(GameInput(), tick) }
        assertEquals(0, a.snapshot.scores[1])
        a.step(GameInput(), tick)
        assertEquals(1, a.snapshot.scores[1])
        repeat(60) { a.step(GameInput(), tick) }
        assertEquals("matchOver", a.snapshot.phase)
    }

    @Test
    fun survivalRevivesSquadNextWaveAndCanRestartLostWave() {
        val rules =
            RoomRules.localDefaults("survival").apply {
                scoreTarget = 2
                pickupRate = "off"
            }
        val a = FixedArena(rules, "PILOT", 0, 1, seed = 42)
        repeat(180) { a.step(GameInput(), tick) }
        a.combat.snapshot.tanks[0].hp = 0
        a.combat.snapshot.tanks.filter { it.survivalEnemy }.forEach { it.hp = 0 }
        a.step(GameInput(), tick)
        assertEquals("break", a.objectives!!.survival!!.status)
        repeat(120) { a.step(GameInput(), tick) }
        assertEquals(1, a.combat.snapshot.tanks[0].hp)
        assertEquals(2, a.objectives!!.survival!!.wave)
        repeat(180) { a.step(GameInput(), tick) }
        a.combat.snapshot.tanks.forEach { it.hp = 0 }
        a.step(GameInput(), tick)
        assertEquals("lost", a.objectives!!.survival!!.status)
        val world = a.world
        a.restartWave()
        assertEquals(world, a.world)
        assertEquals(2, a.objectives!!.survival!!.wave)
        assertEquals(1, a.objectives!!.survival!!.wavesCleared)
        repeat(180) { a.step(GameInput(), tick) }
        a.combat.snapshot.tanks.filter { it.survivalEnemy }.forEach { it.hp = 0 }
        a.step(GameInput(), tick)
        assertEquals("won", a.objectives!!.survival!!.status)
        assertEquals("matchOver", a.snapshot.phase)
        assertEquals(2, a.snapshot.scores[1])
    }

    @Test
    fun cannonPassesInteriorWallsAndExpiresAfterExactlyFivePointThreeSeconds() {
        val world =
            ArenaWorld(4200.0, 840.0, 50, 10, listOf(MazeWall(80.0, -4.0, 8.0, 848.0, "v", 84.0)))
        val a = PracticeArena(42, "PILOT", 0, 0, world = world)
        val t = a.snapshot.tanks[0]
        t.spawnProtected = false
        t.invulnerable = 0.0
        PracticeArena.applyPower(t, "cannon")
        advance(a, GameInput(fire = true))
        val first = a.snapshot.bullets.first()
        assertTrue(first.x > 88)
        advance(a, ticks = 119)
        assertTrue(a.snapshot.bullets.first { it.id == first.id }.x - 42 > 18 * 84)
        advance(a, ticks = 197)
        assertTrue(a.snapshot.bullets.any { it.id == first.id })
        advance(a)
        assertFalse(a.snapshot.bullets.any { it.id == first.id })
    }

    @Test
    fun independentLocalControlsNeverDriveTheOtherSeat() {
        val a = PracticeArena(42, "P1", 0, 0, world = ArenaWorld(840.0, 840.0, 10, 10))
        a.configureLocal("P2", 1)
        val p1 = a.snapshot.tanks.first { it.id == 1 }
        val p2 = a.snapshot.tanks.first { it.id == 2 }
        val first = p1.copy()
        val second = p2.copy()
        a.step(mapOf(1 to GameInput(), 2 to GameInput(forward = true)), tick)
        assertEquals(first.x, p1.x, 0.0)
        assertEquals(first.y, p1.y, 0.0)
        assertTrue(hypot(p2.x - second.x, p2.y - second.y) > 0)
    }

    @Test
    fun benchmarkFullStackRapidFireWithBots() {
        for (map in listOf("infinity", "compact")) {
            val a = arena(map, if (map == "infinity") 8 else 7)
            equip(a.snapshot.tanks[0], "scatter", "all")
            val input = GameInput(forward = true, right = true, fire = true, touchAim = false)
            repeat(120) {
                advance(a, input)
                a.presentationSnapshot(.5, input)
            }
            val samples = LongArray(600)
            repeat(600) { i ->
                a.snapshot.tanks[0].starmanTime = 8.0
                a.snapshot.tanks[0].invulnerable = 8.0
                val start = System.nanoTime()
                advance(a, input)
                a.presentationSnapshot(.5, input)
                samples[i] = System.nanoTime() - start
            }
            samples.sort()
            println(
                "native core $map ${a.snapshot.tanks.size} tanks Starman scatter + presentation: p50=${samples[300]/1e6}ms p95=${samples[570]/1e6}ms p99=${samples[594]/1e6}ms",
            )
            assertTrue(a.snapshot.bullets.size <= 8 * 115)
        }
    }

    @Test
    fun boostedTurnVelocityIsContinuousAcrossPhysicsTicks() {
        val world = ArenaWorld(8400.0, 8400.0, 100, 100)
        val input = GameInput(forward = true, right = true)
        val epsilon = .0001
        val move: (ArenaTank, GameInput, Double) -> Unit = { t, c, dt ->
            TankMovement.step(t, c, dt, world.walls, world.width, world.height)
        }
        for (stacks in listOf(0, 1, 5)) {
            var tank =
                ArenaTank(
                    x = 4200.0,
                    y = 4200.0,
                    speedTime = if (stacks == 0) 0.0 else 100.0,
                    ghostTime = 100.0,
                    speedStacks = stacks,
                )
            repeat(240) {
                val end = TankMovement.presentation(tank, input, 1.0, move = move)
                val before = TankMovement.presentation(tank, input, 1 - epsilon, move = move)
                val next = tank.copy()
                move(next, input, tick)
                val after = TankMovement.presentation(next, input, epsilon, tank, move)
                assertEquals(next.x, end.x, 1e-10)
                assertEquals(next.y, end.y, 1e-10)
                val scale = 60 / epsilon
                val jump =
                    hypot(
                        (after.x - next.x - end.x + before.x) * scale,
                        (after.y - next.y - end.y + before.y) * scale,
                    )
                assertTrue("stacks=$stacks jump=$jump", jump < .02)
                tank = next
            }
        }
    }

    @Test
    fun analogChangesRemainSmoothAt90Through144HzWithoutChangingAuthority() {
        data class Measurement(val jerk: Double, val acceleration: Double, val authority: ArenaTank)
        val world = ArenaWorld(8400.0, 8400.0, 100, 100)
        val move: (ArenaTank, GameInput, Double) -> Unit = { t, c, dt ->
            TankMovement.step(t, c, dt, world.walls, world.width, world.height)
        }
        fun measure(touch: Boolean, refresh: Double, smooth: Boolean): Measurement {
            val tank =
                ArenaTank(
                    id = 1,
                    x = 4200.0,
                    y = 4200.0,
                    speedTime = 120.0,
                    ghostTime = 120.0,
                    speedStacks = 5,
                )
            var remainder = 0.0
            var time = 0.0
            var previous = tank.copy()
            var ticks = 0L
            var velocity: BeamPoint? = null
            var acceleration: BeamPoint? = null
            val jerks = mutableListOf<Double>()
            val accelerations = mutableListOf<Double>()
            val presenter = TankMotionPresenter()
            val dt = 1 / refresh
            repeat((refresh * 8).toInt()) {
                time += dt
                remainder += dt
                val input =
                    if (touch)
                        GameInput(stickX = cos(time * 6), stickY = sin(time * 6), touchAim = true)
                    else GameInput(forward = true, right = true, touchAim = false)
                while (remainder + 1e-9 >= tick) {
                    move(tank, input, tick)
                    remainder = max(0.0, remainder - tick)
                    ticks++
                }
                val image =
                    if (smooth)
                        presenter.present(
                            tank,
                            input,
                            ticks,
                            fraction = remainder * 60,
                            move = move,
                        )
                    else tank.copy().also { if (remainder > 0) move(it, input, remainder) }
                val nextVelocity =
                    BeamPoint((image.x - previous.x) / dt, (image.y - previous.y) / dt)
                velocity?.let { v ->
                    val nextAcceleration =
                        BeamPoint((nextVelocity.x - v.x) / dt, (nextVelocity.y - v.y) / dt)
                    if (time > 3) {
                        accelerations.add(hypot(nextAcceleration.x, nextAcceleration.y))
                        acceleration?.let { a ->
                            jerks.add(
                                hypot(nextAcceleration.x - a.x, nextAcceleration.y - a.y) / dt,
                            )
                        }
                    }
                    acceleration = nextAcceleration
                }
                velocity = nextVelocity
                previous = image
            }
            fun p95(values: List<Double>) = values.sorted()[((values.size - 1) * .95).toInt()]
            return Measurement(p95(jerks), p95(accelerations), tank)
        }
        for (refresh in listOf(90.0, 119.9892, 120.0, 144.0)) for (touch in listOf(false, true)) {
            val before = measure(touch, refresh, false)
            val after = measure(touch, refresh, true)
            assertTrue(
                "$refresh Hz touch=$touch jerk ${after.jerk}/${before.jerk}",
                after.jerk < before.jerk * .2,
            )
            assertTrue(after.acceleration < before.acceleration)
            assertEquals(before.authority, after.authority)
        }
    }
}
