package com.leqra.core

import kotlin.math.*

/** Finite matches use the same combat engine, with native rounds and objectives. */
class FixedArena(
    rules: RoomRules,
    private val name: String,
    private val colorIndex: Int,
    private val botCount: Int = 3,
    private val difficulty: String = "normal",
    seed: Int,
    private val botNames: List<String> = emptyList(),
    private val botColors: List<Int> = emptyList(),
    private val botDifficulties: List<String> = emptyList(),
    private val botTeams: List<Int> = emptyList(),
    private val localTeam: Int = 0,
) {
    val localID = 1
    var rules =
        rules.copy(
            infinity = false,
            teamMode = if (rules.mode in listOf("ctf", "survival")) "teams" else rules.teamMode,
        )
        private set

    var world = ArenaWorld()
        private set

    var combat = PracticeArena(seed = seed, name = name, colorIndex = colorIndex, botCount = 0)
        private set

    val maze
        get() = combat.maze

    val snapshot
        get() = compose(combat.snapshot)

    private data class PilotConfiguration(
        val name: String,
        val colorIndex: Int,
        val team: Int,
        val difficulty: String,
    )

    private val pilotConfigurations = mutableMapOf<Int, PilotConfiguration>()
    private var randomState = if (seed == 0) 1 else seed
    private var secondLocal: PilotConfiguration? = null
    private var displacedBotID: Int? = null
    private var tick = 0L
    private var generation = 0
    private var phase = "countdown"
    private var phaseTime = 3.0
    private var round = 1
    private var clock = 75.0
    private var winner = -1
    private val scores = mutableMapOf<Int, Int>()
    var objectives: ArenaObjectives? = null
        private set

    private val powerDuration
        get() = if (world.cols * world.rows >= 168) 15.0 else 10.0

    init {
        startRound(1, 0)
    }

    fun restart() {
        tick = 0
        round = 1
        winner = -1
        scores.clear()
        startRound(1, 0)
    }

    val canRestartWave
        get() =
            objectives?.survival?.let {
                it.status == "wave" && (phase == "playing" || phase == "countdown") ||
                    it.status == "lost" && phase == "matchOver"
            } ?: false

    fun restartWave() {
        val s = objectives?.survival ?: return
        if (!canRestartWave) return
        round = s.wave
        winner = -1
        startRound(s.wave, s.wavesCleared, true)
    }

    fun step(input: GameInput, dt: Double) = step(mapOf(localID to input), dt)

    fun step(inputs: Map<Int, GameInput>, dt: Double) {
        if (!dt.isFinite() || dt <= 0 || dt > .1) return
        tick++
        if (phase == "matchOver") return
        if (phase == "countdown") {
            phaseTime = max(0.0, phaseTime - dt)
            if (phaseTime <= 1e-9) {
                phaseTime = 0.0
                phase = "playing"
            }
            return
        }
        if (phase == "roundOver") {
            phaseTime = max(0.0, phaseTime - dt)
            if (phaseTime <= 1e-9) {
                if (winner >= 0 && (scores[winner] ?: 0) >= rules.scoreTarget) phase = "matchOver"
                else {
                    round++
                    startRound(1, 0)
                }
            }
            return
        }
        val s = objectives?.survival
        if (s?.status == "break") {
            s.breakTime = max(0.0, s.breakTime - dt)
            if (s.breakTime <= 1e-9) {
                round++
                startRound(s.wave + 1, s.wavesCleared)
            }
            return
        }
        clock = max(0.0, clock - dt)
        combat.step(inputs, dt)
        restoreScores()
        when (rules.mode) {
            "survival" -> stepSurvival()
            "ctf",
            "koth" -> stepObjectives(dt)
            else -> stepElimination()
        }
        combat.refreshStandings()
    }

    fun presentationSnapshot(
        fraction: Double,
        localInput: GameInput? = null,
        localInput2: GameInput? = null,
    ) =
        compose(
            if (phase == "playing" && objectives?.survival?.status != "break")
                combat.presentationSnapshot(fraction, localInput, localInput2)
            else combat.snapshot,
        )

    fun configurePilot(
        id: Int,
        name: String,
        colorIndex: Int,
        team: Int = 0,
        difficulty: String = "normal",
    ) {
        val current = combat.snapshot.tanks.firstOrNull { it.id == id }
        val side =
            if (rules.mode == "survival") 1
            else if (rules.teamMode == "teams") if (team > 0) team else current?.team ?: 1 else 0
        val paint = if (side > 0) rules.teamColors.getOrNull(side - 1) ?: side - 1 else colorIndex
        val configuration = PilotConfiguration(name, colorIndex, side, difficulty)
        if (id == 2 && secondLocal != null && current?.bot == false) {
            secondLocal = configuration
            pilotConfigurations.remove(id)
        } else pilotConfigurations[id] = configuration
        combat.configurePilot(id, name, paint, side, difficulty)
    }

    fun configureLocal(name: String, colorIndex: Int, team: Int = 0): Int {
        val side =
            if (rules.mode == "survival") 1
            else if (rules.teamMode == "teams") if (team > 0) team else 2 else 0
        val displaced = combat.snapshot.tanks.firstOrNull { it.id == 2 && it.bot }
        secondLocal = PilotConfiguration(name, colorIndex, side, "normal")
        val id = combat.configureLocal(name, colorIndex, side, displacedBotID)
        if (displaced != null) {
            val replacement = displaced.id
            displacedBotID = replacement
            pilotConfigurations.remove(2)?.let { pilotConfigurations[replacement] = it }
            scores.remove(2)?.let { scores[replacement] = it }
            if (winner == 2) winner = replacement
            objectives?.let { objective ->
                if (objective.owner == -3) objective.owner = -replacement - 1
                objective.flags.forEach { if (it.carrier == 2) it.carrier = replacement }
            }
        }
        return id
    }

    private fun compose(original: ArenaSnapshot): ArenaSnapshot {
        val tanks = original.tanks.map { it.copy(score = scores[it.id] ?: 0) }
        return original.copy(
            tick = tick,
            generation = generation,
            world = world,
            phase = phase,
            phaseTime = phaseTime,
            round = round,
            roundClock = clock,
            winner = winner,
            objectives = objectives,
            rules = rules,
            scores = List(max(9, (tanks.maxOfOrNull { it.id } ?: 0) + 1)) { scores[it] ?: 0 },
            tanks = tanks,
            leaderboard =
                tanks
                    .filter { !it.survivalEnemy }
                    .sortedWith(compareByDescending<ArenaTank> { it.score }.thenBy { it.id })
                    .map {
                        LeaderboardEntry(it.id, it.name, it.score, it.colorIndex, it.bot, it.team)
                    },
            teamScores =
                (1..4).map { team ->
                    tanks.filter { it.team == team }.maxOfOrNull { it.score } ?: 0
                },
        )
    }

    private fun random(maximum: Int): Int {
        randomState = randomState xor (randomState shl 13)
        randomState = randomState xor (randomState ushr 17)
        randomState = randomState xor (randomState shl 5)
        return Integer.remainderUnsigned(randomState, maximum)
    }

    private fun startRound(wave: Int, cleared: Int, preserveWorld: Boolean = false) {
        generation++
        winner = -1
        phase = "countdown"
        phaseTime = 3.0
        clock = rules.timeLimit.toDouble()
        if (!preserveWorld) world = makeWorld()
        combat =
            PracticeArena(
                seed = randomState,
                name = name,
                colorIndex = colorIndex,
                botCount = botCount.coerceIn(0, if (rules.mode == "survival") 3 else 7),
                difficulty = difficulty,
                world = world,
            )
        combat.configure(rules)
        combat.killScoring = false
        combat.respawnsEnabled = rules.mode in listOf("ctf", "koth")
        combat.respawnDelay = rules.respawnSeconds.toDouble()
        val cols = world.cols
        val rows = world.rows
        val cells =
            listOf(
                0 to rows - 1,
                cols - 1 to 0,
                cols - 1 to rows - 1,
                0 to 0,
                cols / 2 to 0,
                cols - 1 to rows / 2,
                cols / 2 to rows - 1,
                0 to rows / 2,
            )
        val spots = (if (combat.snapshot.tanks.size <= 4) cells.take(4) else cells).toMutableList()
        for (i in spots.indices.reversed()) {
            if (i > 0) {
                val j = random(i + 1)
                val v = spots[i]
                spots[i] = spots[j]
                spots[j] = v
            }
        }
        combat.snapshot.tanks.forEachIndexed { i, t ->
            val team =
                if (rules.mode == "survival") 1
                else if (rules.teamMode == "teams")
                    if (i == 0) if (localTeam > 0) localTeam else 1
                    else botTeams.getOrNull(i - 1)?.takeIf { it > 0 } ?: (i % 2 + 1)
                else 0
            val paint =
                if (team > 0) rules.teamColors.getOrNull(team - 1) ?: team - 1
                else if (i == 0) colorIndex
                else botColors.getOrNull(i - 1) ?: GamePalette.index(colorIndex + i)
            combat.configurePilot(
                t.id,
                if (i == 0) name else botNames.getOrNull(i - 1) ?: "BOT $i",
                paint,
                team,
                if (i == 0) difficulty else botDifficulties.getOrNull(i - 1) ?: difficulty,
            )
            t.x = (spots[i].first + .5) * 84
            t.y = (spots[i].second + .5) * 84
            t.angle = -PI / 2
            t.spawnSerial = generation
            t.invulnerable = .75
        }
        secondLocal?.let { combat.configureLocal(it.name, it.colorIndex, it.team, displacedBotID) }
        for (tank in combat.snapshot.tanks) {
            val p = if (tank.id == 2 && !tank.bot) secondLocal else pilotConfigurations[tank.id]
            if (p != null) {
                val side = if (rules.mode == "survival") 1 else p.team
                val color =
                    if (side > 0) rules.teamColors.getOrNull(side - 1) ?: side - 1 else p.colorIndex
                combat.configurePilot(tank.id, p.name, color, side, p.difficulty)
            }
        }
        objectives =
            when (rules.mode) {
                "ctf" ->
                    ArenaObjectives(
                        mode = "ctf",
                        flags =
                            listOf(
                                ArenaFlag(
                                    team = 1,
                                    homeX = 126.0,
                                    homeY = world.height - 126,
                                    x = 126.0,
                                    y = world.height - 126,
                                ),
                                ArenaFlag(
                                    team = 2,
                                    homeX = world.width - 126,
                                    homeY = 126.0,
                                    x = world.width - 126,
                                    y = 126.0,
                                ),
                            ),
                    )
                "koth" ->
                    ArenaObjectives(
                        mode = "koth",
                        hillX = (cols / 2 + .5) * 84,
                        hillY = (rows / 2 + .5) * 84,
                        radius = 32.0,
                    )
                "survival" ->
                    ArenaObjectives(
                        mode = "survival",
                        survival =
                            ArenaSurvival(
                                wave = wave,
                                wavesCleared = cleared,
                                waveTarget = rules.scoreTarget,
                                enemiesRemaining = min(4, 2 + (wave - 1) / 2),
                                boss = wave % 5 == 0,
                                status = "wave",
                            ),
                    )
                else -> null
            }
        if (rules.mode == "survival") {
            val count = min(4, 2 + (wave - 1) / 2)
            val boss = wave % 5 == 0
            val firstEnemy = max(5, (combat.snapshot.tanks.maxOfOrNull { it.id } ?: 0) + 1)
            repeat(count) { enemy ->
                val id = firstEnemy + enemy
                val level =
                    when {
                        wave <= 5 -> "easy"
                        wave <= 10 -> "normal"
                        wave <= 15 -> "hard"
                        else -> "godlike"
                    }
                val isBoss = boss && enemy == 0
                val bossLevel =
                    when {
                        wave < 10 -> "normal"
                        wave < 15 -> "hard"
                        else -> "godlike"
                    }
                val t =
                    ArenaTank(
                        id = id,
                        name = if (isBoss) bossName(wave) else "RAIDER ${enemy+1}",
                        x = (cols - 1 - enemy % 2 + .5) * 84,
                        y = (enemy / 2 + .5) * 84,
                        angle = PI / 2,
                        colorIndex = rules.teamColors.getOrNull(1) ?: 1,
                        team = 2,
                        bot = true,
                        spawnProtected = true,
                        spawnSerial = wave,
                        invulnerable = 1.2,
                        survivalEnemy = true,
                        survivalBoss = isBoss,
                        difficulty = if (isBoss) bossLevel else level,
                    )
                combat.snapshot.tanks += t
                val p = survivalEnemySpawn(id)
                t.x = p.x
                t.y = p.y
                if (isBoss && rules.pickupRate != "off") {
                    val strength = (wave / 5).coerceIn(1, 3)
                    if ("shield" in rules.weapons)
                        repeat(strength) { PracticeArena.applyPower(t, "shield", powerDuration) }
                    if (strength >= 2 && "speed" in rules.weapons)
                        PracticeArena.applyPower(t, "speed", powerDuration)
                    val choices = listOf("homing", "cannon", "laser")
                    (0..2)
                        .map { choices[(wave / 5 - 1 + it) % 3] }
                        .firstOrNull { it in rules.weapons }
                        ?.let { PracticeArena.applyPower(t, it, powerDuration) }
                }
            }
            if (boss && "shield" in rules.weapons)
                combat.snapshot.tanks
                    .filter { !it.survivalEnemy }
                    .forEach { PracticeArena.applyPower(it, "shield", powerDuration) }
        }
        combat.respawnLocation = { respawnPoint(it) }
        combat.botGoal = { objectiveGoal(it) }
        if (rules.mode == "ctf")
            combat.snapshot.tanks.forEach {
                val p = respawnPoint(it)
                it.x = p.x
                it.y = p.y
            }
        val area = cols * rows
        combat.seedFixedPickups(2 + listOf(49, 72, 120, 168, 224).count { area > it })
        restoreScores()
        combat.refreshStandings()
    }

    private fun restoreScores() {
        combat.snapshot.tanks.forEach { it.score = scores[it.id] ?: 0 }
    }

    private fun side(t: ArenaTank) = if (t.team > 0) t.team else -t.id

    private fun awardPoint(t: ArenaTank) {
        val next = (scores[t.id] ?: 0) + 1
        combat.snapshot.tanks.filter { side(it) == side(t) }.forEach { scores[it.id] = next }
        if (next >= rules.scoreTarget) {
            winner = t.id
            phase = "matchOver"
            combat.clearProjectiles()
        }
    }

    private fun stepElimination() {
        val living = combat.snapshot.tanks.filter { it.hp > 0 }
        val sides = living.map { side(it) }.toSet()
        if (sides.size > 1 && clock > 0) return
        winner = if (sides.size == 1) living.first().id else -1
        if (winner >= 0) {
            val tank = living.first()
            val next = (scores[tank.id] ?: 0) + 1
            combat.snapshot.tanks.filter { side(it) == side(tank) }.forEach { scores[it.id] = next }
        }
        phase = "roundOver"
        phaseTime = 2.0
        combat.clearProjectiles()
        restoreScores()
    }

    private fun leader(): Int {
        val sorted =
            combat.snapshot.tanks
                .filter { !it.survivalEnemy }
                .distinctBy { side(it) }
                .sortedByDescending { scores[it.id] ?: 0 }
        val first = sorted.firstOrNull() ?: return -1
        if (sorted.size > 1 && (scores[first.id] ?: 0) == (scores[sorted[1].id] ?: 0)) return -1
        return first.id
    }

    private fun stepObjectives(dt: Double) {
        val o = objectives ?: return
        if (o.suddenDeath) {
            val living = combat.snapshot.tanks.filter { it.hp > 0 }
            val sides = living.map { side(it) }.toSet()
            if (sides.size == 1) {
                winner = living.first().id
                phase = "matchOver"
                combat.clearProjectiles()
            } else if (sides.isEmpty()) beginSuddenDeath()
            return
        }
        if (o.mode == "ctf") {
            for (flag in o.flags) {
                if (flag.carrier >= 0) {
                    val tank = combat.snapshot.tanks.firstOrNull { it.id == flag.carrier }
                    if (tank != null && tank.hp > 0) {
                        flag.x = tank.x
                        flag.y = tank.y
                    } else {
                        val p = combat.maze.phaseExit(tank?.x ?: flag.x, tank?.y ?: flag.y)
                        flag.x = p.x
                        flag.y = p.y
                        flag.carrier = -1
                        flag.home = false
                        flag.returnIn = 12.0
                    }
                }
                if (!flag.home && flag.carrier < 0) {
                    flag.returnIn -= dt
                    if (flag.returnIn <= 0) resetFlag(flag)
                }
            }
            val living = combat.snapshot.tanks.filter { it.hp > 0 && it.invulnerable <= 0 }
            fun touches(t: ArenaTank, f: ArenaFlag) =
                hypot(t.x - f.x, t.y - f.y) < 31 &&
                    !maze.segmentBlocked(t.x, t.y, f.x - t.x, f.y - t.y)
            for (t in living) for (f in
                o.flags.filter { it.team == t.team && !it.home && it.carrier < 0 }) if (
                touches(t, f)
            )
                resetFlag(f)
            for (t in living) {
                val own = o.flags.firstOrNull { it.team == t.team } ?: continue
                var carried = o.flags.firstOrNull { it.carrier == t.id }
                if (carried == null) {
                    val enemy =
                        o.flags.firstOrNull {
                            it.team != t.team && it.carrier < 0 && touches(t, it)
                        }
                    if (enemy != null) {
                        enemy.carrier = t.id
                        enemy.home = false
                        enemy.returnIn = 0.0
                        enemy.x = t.x
                        enemy.y = t.y
                        carried = enemy
                    }
                }
                if (
                    carried != null &&
                        own.home &&
                        hypot(t.x - own.homeX, t.y - own.homeY) < 34 &&
                        !maze.segmentBlocked(t.x, t.y, own.homeX - t.x, own.homeY - t.y)
                ) {
                    resetFlag(carried)
                    awardPoint(t)
                }
            }
        } else {
            val occupiers =
                combat.snapshot.tanks.filter {
                    it.hp > 0 &&
                        it.invulnerable <= 0 &&
                        hypot(it.x - o.hillX, it.y - o.hillY) <= o.radius &&
                        !maze.segmentBlocked(o.hillX, o.hillY, it.x - o.hillX, it.y - o.hillY)
                }
            val sides = occupiers.map { side(it) }.toSet()
            o.contested = sides.size > 1
            if (sides.size == 1) {
                val owner = occupiers.first()
                val code = if (owner.team > 0) owner.team else -owner.id - 1
                if (o.owner != code) o.hold = 0.0
                o.owner = code
                o.hold += dt
                while (o.hold >= 1 - 1e-9) {
                    o.hold = max(0.0, o.hold - 1)
                    awardPoint(owner)
                }
            } else {
                o.owner = 0
                o.hold = 0.0
            }
        }
        if (phase == "playing" && clock <= 0) {
            winner = leader()
            if (winner >= 0) {
                phase = "matchOver"
                combat.clearProjectiles()
            } else beginSuddenDeath()
        }
        restoreScores()
    }

    private fun resetFlag(f: ArenaFlag) {
        f.x = f.homeX
        f.y = f.homeY
        f.carrier = -1
        f.home = true
        f.returnIn = 0.0
    }

    private fun beginSuddenDeath() {
        objectives?.let {
            it.suddenDeath = true
            it.owner = 0
            it.hold = 0.0
            it.flags.forEach { f -> resetFlag(f) }
        }
        combat.respawnsEnabled = false
        combat.clearProjectiles()
        combat.snapshot.pickups = emptyList()
        combat.snapshot.tanks.forEach { it.hp = 0 }
        combat.snapshot.tanks =
            combat.snapshot.tanks.map { old ->
                val p = respawnPoint(old)
                ArenaTank(
                    id = old.id,
                    name = old.name,
                    x = p.x,
                    y = p.y,
                    angle = -PI / 2,
                    colorIndex = old.colorIndex,
                    score = scores[old.id] ?: 0,
                    team = old.team,
                    bot = old.bot,
                    spawnProtected = true,
                    spawnSerial = old.spawnSerial + 1,
                    invulnerable = 1.2,
                    difficulty = old.difficulty,
                )
            }
    }

    private fun stepSurvival() {
        val s = objectives?.survival ?: return
        val living = combat.snapshot.tanks.filter { it.hp > 0 }
        s.enemiesRemaining = living.count { it.survivalEnemy }
        s.boss = living.any { it.survivalBoss }
        if (living.none { !it.survivalEnemy }) {
            s.status = "lost"
            phase = "matchOver"
            winner = -1
            combat.clearProjectiles()
        } else if (s.enemiesRemaining == 0) {
            s.wavesCleared++
            combat.snapshot.tanks
                .filter { !it.survivalEnemy }
                .forEach { scores[it.id] = s.wavesCleared }
            if (s.wavesCleared >= s.waveTarget) {
                s.status = "won"
                phase = "matchOver"
                winner = localID
            } else {
                s.status = "break"
                s.breakTime = 2.0
            }
            combat.clearProjectiles()
        } else if (clock <= 0) {
            s.status = "lost"
            phase = "matchOver"
            winner = -1
            combat.clearProjectiles()
        }
        restoreScores()
    }

    private fun bossName(wave: Int) =
        if (wave < 10) "NORMAL BOSS" else if (wave < 15) "FIERCE BOSS" else "GODLIKE BOSS"

    private fun survivalEnemySpawn(id: Int): BeamPoint {
        var best = Double.NEGATIVE_INFINITY
        var result = BeamPoint(42.0, 42.0)
        for (row in 0 until world.rows) for (col in 0 until world.cols) {
            val p = BeamPoint((col + .5) * 84, (row + .5) * 84)
            val clearance =
                combat.snapshot.tanks
                    .filter { it.id != id && it.hp > 0 }
                    .minOfOrNull { hypot(it.x - p.x, it.y - p.y) - 34 } ?: Double.POSITIVE_INFINITY
            if (clearance > best) {
                best = clearance
                result = p
            }
        }
        return result
    }

    private fun objectiveGoal(t: ArenaTank): BeamPoint? {
        val o = objectives ?: return null
        if (o.suddenDeath) return null
        if (o.mode == "koth") return BeamPoint(o.hillX, o.hillY)
        if (o.mode != "ctf") return null
        val own = o.flags.firstOrNull { it.team == t.team } ?: return null
        val enemy = o.flags.firstOrNull { it.team != t.team } ?: return null
        if (!own.home && (t.id % 2 == 0 || enemy.carrier == t.id)) return BeamPoint(own.x, own.y)
        if (enemy.carrier == t.id) return BeamPoint(own.homeX, own.homeY)
        return BeamPoint(enemy.x, enemy.y)
    }

    private fun respawnPoint(t: ArenaTank): BeamPoint {
        val home = objectives?.flags?.firstOrNull { it.team == t.team }
        val baseX = home?.homeX ?: if (t.id % 2 == 0) world.width - 42 else 42.0
        val baseY = home?.homeY ?: if (t.id % 2 == 0) 42.0 else world.height - 42
        val start = (baseX / 84).toInt() to (baseY / 84).toInt()
        val queue = mutableListOf(start)
        val seen = mutableSetOf(start.second * world.cols + start.first)
        var head = 0
        var best = Double.NEGATIVE_INFINITY
        var point = BeamPoint(baseX, baseY)
        while (head < queue.size) {
            val cell = queue[head++]
            val x = (cell.first + .5) * 84
            val y = (cell.second + .5) * 84
            for ((dx, dy) in listOf(1 to 0, -1 to 0, 0 to 1, 0 to -1)) {
                val next = cell.first + dx to cell.second + dy
                val key = next.second * world.cols + next.first
                if (
                    next.first !in 0 until world.cols ||
                        next.second !in 0 until world.rows ||
                        key in seen ||
                        maze.blocked(x + dx * 42, y + dy * 42, 17.0)
                )
                    continue
                queue.add(next)
                seen.add(key)
            }
            if (
                home != null &&
                    (cell.first == (home.homeX / 84).toInt() &&
                        cell.second == (home.homeY / 84).toInt() ||
                        hypot(x - home.x, y - home.y) < 49)
            )
                continue
            val clearance =
                combat.snapshot.tanks
                    .filter { it.id != t.id && it.hp > 0 }
                    .minOfOrNull { hypot(it.x - x, it.y - y) - 34 } ?: 500.0
            if (clearance > best) {
                best = clearance
                point = BeamPoint(x, y)
            }
            if (clearance > 70) return point
        }
        return point
    }

    private fun makeWorld(): ArenaWorld {
        val sizes =
            mapOf(
                "compact" to (7 to 7),
                "standard" to (9 to 8),
                "large" to (12 to 10),
                "huge" to (14 to 12),
                "giant" to (16 to 14),
                "ultrawide" to (24 to 14),
            )
        val size = sizes[rules.mapSize] ?: (9 to 8)
        val cols = if (rules.portraitMaze) size.second else size.first
        val rows = if (rules.portraitMaze) size.first else size.second
        val cells = IntArray(cols * rows) { 3 }
        val visited = BooleanArray(cells.size)
        val start = random(cells.size)
        visited[start] = true
        val stack = mutableListOf(start)
        while (stack.isNotEmpty()) {
            val cell = stack.last()
            val x = cell % cols
            val y = cell / cols
            val neighbors = mutableListOf<Int>()
            if (y > 0 && !visited[cell - cols]) neighbors.add(cell - cols)
            if (x + 1 < cols && !visited[cell + 1]) neighbors.add(cell + 1)
            if (y + 1 < rows && !visited[cell + cols]) neighbors.add(cell + cols)
            if (x > 0 && !visited[cell - 1]) neighbors.add(cell - 1)
            if (neighbors.isEmpty()) {
                stack.removeAt(stack.lastIndex)
                continue
            }
            val neighbor = neighbors[random(neighbors.size)]
            when (neighbor - cell) {
                -cols -> cells[cell] = cells[cell] and 1.inv()
                1 -> cells[neighbor] = cells[neighbor] and 2.inv()
                cols -> cells[neighbor] = cells[neighbor] and 1.inv()
                else -> cells[cell] = cells[cell] and 2.inv()
            }
            visited[neighbor] = true
            stack.add(neighbor)
        }
        for (row in 0 until rows) for (col in 0 until cols) {
            val cell = row * cols + col
            if (col + 1 < cols && cells[cell + 1] and 2 != 0 && random(4) == 0)
                cells[cell + 1] = cells[cell + 1] and 2.inv()
            if (row + 1 < rows && cells[cell + cols] and 1 != 0 && random(4) == 0)
                cells[cell + cols] = cells[cell + cols] and 1.inv()
        }
        val walls = mutableListOf<MazeWall>()
        for (y in 0 until rows) for (x in 0 until cols) {
            val wx = x * 84.0
            val wy = y * 84.0
            val bits = cells[y * cols + x]
            if (bits and 1 != 0) walls.add(MazeWall(wx - 4, wy - 4, 92.0, 8.0, "h", wy))
            if (bits and 2 != 0) walls.add(MazeWall(wx - 4, wy - 4, 8.0, 92.0, "v", wx))
            if (y == rows - 1)
                walls.add(MazeWall(wx - 4, rows * 84.0 - 4, 92.0, 8.0, "h", rows * 84.0))
            if (x == cols - 1)
                walls.add(MazeWall(cols * 84.0 - 4, wy - 4, 8.0, 92.0, "v", cols * 84.0))
        }
        return ArenaWorld(cols * 84.0, rows * 84.0, cols, rows, walls)
    }
}
