package com.leqra.core

import kotlin.math.*

/** Native deterministic offline simulation. Network damage and score are always server-owned. */
class PracticeArena(
    seed: Int = 0x1e9a2026,
    name: String,
    colorIndex: Int,
    botCount: Int = 8,
    difficulty: String = "normal",
    world: ArenaWorld? = null,
) {
    val maze = if (world == null) InfiniteMaze(seed) else InfiniteMaze(world)
    val localID = 1
    var snapshot = ArenaSnapshot()
        internal set

    var respawnsEnabled = true
    var respawnDelay = 1.0
    var killScoring = true
    var friendlyFire = false
    var respawnLocation: ((ArenaTank) -> BeamPoint)? = null
    var botGoal: ((ArenaTank) -> BeamPoint?)? = null
    private var pickupRate = "normal"
    private var enabledPickups = pickupKinds
    private var botDifficulty = difficulty
    private var powerDuration = 15.0
    private var starDuration = 8.0
    private var activeRules: RoomRules? = null
    private val roamingIDs = mutableSetOf<Int>()
    private val roamingHomes = mutableMapOf<Int, Int>()
    private var nextRoamingID = 2
    private var nextRoamingSpawn = 0.0
    private var configured = false
    private var randomState = if (seed == 0) 1 else seed
    private var time = 0.0
    private var stepStarted = 0.0
    private var visualTime = 0.0
    private var lastVisualWallTime: Double? = null
    private val terminalFlights = ProjectileFlightPresentation()
    private val contacts = CombatContactPresentation()
    val hasPendingProjectileFlights: Boolean get() = terminalFlights.hasPending || contacts.hasPending
    private var nextPickup = 0.0
    private var nextID = 1
    private var nextEffect = 0
    private val effectTimes = mutableMapOf<Int, Double>()
    private val held = mutableMapOf<Int, Boolean>()
    private val movementInputs = mutableMapOf<Int, GameInput>()
    private val fireBlocked = mutableSetOf<Int>()
    private val botCourses = mutableMapOf<Int, BeamPoint>()
    private val botDecisions = mutableMapOf<Int, Double>()
    private val dumbBrains = mutableMapOf<Int, Pair<Int, DumbBotBrain>>()
    private val nextBoostEffects = mutableMapOf<Int, Double>()
    private val motionPresenters = mutableMapOf<Int, TankMotionPresenter>()
    private var routeMarks = IntArray(0)
    private var routeQueue = IntArray(0)
    private var routeSteps = IntArray(0)
    private var routeStamp = 0

    private data class Projectile(
        val wire: ArenaBullet,
        var age: Double = 0.0,
        var seekDelay: Double = 0.0,
        val boosted: Boolean = false,
        var rangeLeft: Double? = null,
        var published: Boolean = false,
        var pathTick: Double = 0.0,
        val birthX: Double = wire.x,
        val birthY: Double = wire.y,
        val birthTick: Double = pathTick,
        var flightPoints: MutableList<ProjectileFlightPoint>? = null,
        var segmentX: Double = birthX,
        var segmentY: Double = birthY,
        var segmentTick: Double = birthTick,
    ) {
        val radius
            get() = spec(wire.kind).radius

        fun deepCopy() = copy(wire = wire.copy())
    }

    private val projectiles = ArrayList<Projectile>()

    init {
        snapshot.tanks =
            listOf(
                ArenaTank(
                    id = 1,
                    name = Callsigns.limit(name),
                    x = 42.0,
                    y = 42.0,
                    colorIndex = GamePalette.index(colorIndex),
                    spawnProtected = true,
                    spawnSerial = 1,
                    invulnerable = 1.0,
                ),
            )
        repeat(botCount.coerceIn(0, if (world == null) 24 else 7)) { offset ->
            val n = offset + 1
            val p = spawnPoint(snapshot.tanks[0], 2, 5)
            snapshot.tanks +=
                ArenaTank(
                    id = n + 1,
                    name = "ROVER %02d".format(n),
                    x = p.x,
                    y = p.y,
                    angle = unitRandom() * 2 * PI - PI,
                    colorIndex = GamePalette.index(colorIndex + n),
                    bot = true,
                    spawnProtected = true,
                    spawnSerial = 1,
                    invulnerable = 1.0,
                    difficulty = difficulty,
                )
            roamingIDs.add(n + 1)
        }
        snapshot.players = 1
        updateStandings()
    }

    fun configurePilot(
        id: Int,
        name: String,
        colorIndex: Int,
        team: Int = 0,
        difficulty: String = "normal",
    ) {
        val t = snapshot.tanks.firstOrNull { it.id == id } ?: return
        t.name = Callsigns.limit(name)
        val side = if (activeRules?.teamMode == "ffa") 0 else team.coerceIn(0, 4)
        t.team = side
        t.colorIndex =
            GamePalette.index(
                if (side > 0) activeRules?.teamColors?.getOrNull(side - 1) ?: colorIndex
                else colorIndex,
            )
        if (t.difficulty != difficulty) dumbBrains.remove(id)
        t.difficulty = difficulty
        updateStandings()
    }

    /** Adds an independent local seat without replacing a configured bot. */
    fun configureLocal(
        name: String,
        colorIndex: Int,
        team: Int = 0,
        displacedBotID: Int? = null,
    ): Int {
        val existing = snapshot.tanks.firstOrNull { it.id == 2 && !it.bot }
        if (existing != null) {
            configurePilot(2, name, colorIndex, team)
            return 2
        }
        snapshot.tanks
            .firstOrNull { it.id == 2 }
            ?.let { bot ->
                val replacement =
                    displacedBotID?.takeIf { id -> id > 2 && snapshot.tanks.none { it.id == id } }
                        ?: (snapshot.tanks.maxOfOrNull { it.id } ?: 1) + 1
                if (roamingIDs.remove(2)) roamingIDs.add(replacement)
                held.remove(2)?.let { held[replacement] = it }
                movementInputs.remove(2)?.let { movementInputs[replacement] = it }
                if (fireBlocked.remove(2)) fireBlocked.add(replacement)
                botCourses.remove(2)?.let { botCourses[replacement] = it }
                botDecisions.remove(2)?.let { botDecisions[replacement] = it }
                dumbBrains.remove(2)?.let { dumbBrains[replacement] = it }
                nextBoostEffects.remove(2)?.let { nextBoostEffects[replacement] = it }
                motionPresenters.remove(2)
                for (projectile in projectiles) {
                    if (projectile.wire.owner == 2) projectile.wire.owner = replacement
                    if (projectile.wire.target == 2) projectile.wire.target = replacement
                }
                snapshot.bullets =
                    snapshot.bullets.map { b ->
                        b.copy(
                            owner = if (b.owner == 2) replacement else b.owner,
                            target = if (b.target == 2) replacement else b.target,
                        )
                    }
                snapshot.effects =
                    snapshot.effects.map { effect ->
                        if (effect.owner == 2) effect.copy(owner = replacement) else effect
                    }
                bot.id = replacement
            }
        val p = spawnPoint(snapshot.tanks[0], 1, 3)
        snapshot.tanks +=
            ArenaTank(
                id = 2,
                name = Callsigns.limit(name),
                x = p.x,
                y = p.y,
                colorIndex = GamePalette.index(colorIndex),
                team = team,
                spawnProtected = true,
                spawnSerial = 1,
                invulnerable = 1.0,
            )
        snapshot.players = 2
        configurePilot(2, name, colorIndex, team)
        return 2
    }

    fun configure(rules: RoomRules) {
        activeRules = rules.copy()
        snapshot.rules = rules.copy()
        friendlyFire = rules.friendlyFire
        val world = maze.world
        if (world != null) {
            pickupRate = rules.pickupRate
            enabledPickups = rules.weapons.filter { it in pickupKinds }
            val area = world.cols * world.rows
            powerDuration = if (area >= 168) 15.0 else 10.0
            starDuration =
                when {
                    area >= 336 -> 8.0
                    area >= 224 -> 7.0
                    area >= 168 -> 6.0
                    area >= 120 -> 5.0
                    else -> 4.0
                }
        } else {
            if (configured) {
                roamingIDs.forEach { dumbBrains.remove(it) }
                snapshot.tanks = snapshot.tanks.filter { it.id !in roamingIDs }
                projectiles.removeAll { it.wire.owner in roamingIDs }
            }
            configured = true
            roamingIDs.clear()
            roamingHomes.clear()
            nextRoamingID = max(nextRoamingID, (snapshot.tanks.maxOfOrNull { it.id } ?: 1) + 1)
            nextRoamingSpawn = time
            snapshot.tanks.forEachIndexed { i, t ->
                t.team = if (rules.teamMode == "teams") if (t.team > 0) t.team else i % 2 + 1 else 0
                if (t.team > 0)
                    t.colorIndex = rules.teamColors.getOrNull(t.team - 1) ?: t.colorIndex
            }
        }
        updateStandings()
    }

    fun clearProjectiles() {
        projectiles.clear()
        snapshot.bullets = emptyList()
    }

    fun refreshStandings() = updateStandings()

    fun step(input: GameInput, dt: Double) = step(mapOf(localID to input), dt)

    fun step(inputs: Map<Int, GameInput>, dt: Double) {
        if (
            !dt.isFinite() ||
                dt <= 0 ||
                dt > .1 ||
                snapshot.tanks.isEmpty() ||
                snapshot.result != null
        )
            return
        stepStarted = time
        time += dt
        snapshot.tick++
        snapshot.effects = snapshot.effects.filter { time - (effectTimes[it.id] ?: 0.0) < .15 }
        val live = snapshot.effects.map { it.id }.toSet()
        effectTimes.keys.retainAll(live)
        populateRoamingBots()
        populatePickups(dt)
        for (i in snapshot.tanks.indices) {
            val t = snapshot.tanks[i]
            if (t.hp == 0) {
                if (!respawnsEnabled) {
                    t.respawnTime = 0.0
                    continue
                }
                t.respawnTime = max(0.0, t.respawnTime - dt)
                if (t.respawnTime <= 1e-9) respawn(i)
                continue
            }
            advanceEquipment(t, dt)
        }
        val count = snapshot.tanks.size
        repeat(count) { offset ->
            val i = ((snapshot.tick % count).toInt() + offset) % count
            val t = snapshot.tanks[i]
            if (t.hp > 0) {
                val controls = if (t.bot) botInput(i, dt) else inputs[t.id] ?: GameInput()
                if (t.bot && t.id in fireBlocked) controls.fire = false
                movementInputs[t.id] = controls.copy()
                move(t, controls, dt, ageStarman = false)
                collectPickups(i)
                weaponControl(i, controls.fire)
            }
        }
        starmanContacts()
        maze.world?.let { world ->
            for (a in snapshot.tanks.indices) for (b in a + 1 until snapshot.tanks.size) {
                val first = snapshot.tanks[a]
                val second = snapshot.tanks[b]
                if (first.hp <= 0 || second.hp <= 0) continue
                var dx = second.x - first.x
                var dy = second.y - first.y
                var distance = hypot(dx, dy)
                val overlap = 34 - distance
                if (overlap <= 0) continue
                if (
                    (first.ghostTime > 0 || second.ghostTime > 0) &&
                        maze.segmentBlocked(first.x, first.y, dx, dy)
                )
                    continue
                if (distance < .001) {
                    dx = 1.0
                    dy = 0.0
                    distance = 1.0
                }
                TankMovement.displace(
                    first,
                    -dx / distance * overlap / 2,
                    -dy / distance * overlap / 2,
                    world,
                )
                TankMovement.displace(
                    second,
                    dx / distance * overlap / 2,
                    dy / distance * overlap / 2,
                    world,
                )
            }
        }
        var survivors = 0
        for (i in projectiles.indices) {
            val p = projectiles[i]
            if (p.wire.kind != "cannon") {
                p.segmentX = p.wire.x; p.segmentY = p.wire.y; p.segmentTick = p.pathTick; p.flightPoints = null
            }
            val span =
                min(
                    dt,
                    min(
                        p.wire.life,
                        p.rangeLeft?.let { it / max(1.0, hypot(p.wire.vx, p.wire.vy)) }
                            ?: Double.POSITIVE_INFINITY,
                    ),
                )
            p.wire.life -= span
            p.age += span
            if (p.wire.kind == "homing" || p.wire.kind == "grenade") guide(p, span)
            if (p.wire.kind == "grenade") {
                val drag = grenadeDragFactor(p.wire.life + span, p.wire.life)
                p.wire.vx *= drag
                p.wire.vy *= drag
            }
            if (!advance(p, span)) continue
            if (p.wire.life > 1e-9 && (p.rangeLeft ?: 1.0) > 1e-7) {
                projectiles[survivors++] = p
            } else if (p.wire.kind == "grenade") detonate(p.wire, completedFlight(p))
            else if (p.wire.kind == "homing" && maze.world != null)
                effect("impact", p.wire.x, p.wire.y, p.wire.owner, flight = completedFlight(p))
        }
        while (projectiles.size > survivors) projectiles.removeAt(projectiles.lastIndex)
        snapshot.bullets = projectiles.map { it.wire.copy() }
        snapshot.pickups = snapshot.pickups.filter { it.life > 0 }
        updateStandings()
    }

    private fun populateRoamingBots() {
        val rules = activeRules ?: return
        if (maze.world != null || !configured) return
        val humans = snapshot.tanks.filter { !it.bot }
        val living = humans.filter { it.hp > 0 }
        val budget = if (rules.infinityRandomBots) min(128, humans.size * 16) else 0
        val retired = snapshot.tanks.filter { bot -> bot.id in roamingIDs &&
            (budget == 0 || humans.none { abs(it.x - bot.x) <= 16 * 84 && abs(it.y - bot.y) <= 16 * 84 }) }.map { it.id }.toMutableSet()
        val excess = (roamingIDs.size - retired.size - budget).coerceAtLeast(0)
        if (excess > 0) retired += roamingIDs.filter { it !in retired }.sortedDescending().take(excess)
        if (retired.isNotEmpty()) {
            snapshot.tanks = snapshot.tanks.filter { it.id !in retired }
            projectiles.removeAll { it.wire.owner in retired }
            snapshot.bullets = snapshot.bullets.filter { it.owner !in retired }
            for (id in retired) {
                roamingIDs.remove(id); roamingHomes.remove(id); held.remove(id); movementInputs.remove(id)
                fireBlocked.remove(id); botCourses.remove(id); botDecisions.remove(id); dumbBrains.remove(id)
                nextBoostEffects.remove(id); motionPresenters.remove(id)
            }
        }
        if (time < nextRoamingSpawn || living.isEmpty() || roamingIDs.size >= budget) return
        val rate = rules.infinityBotSpawnRate.takeIf { it in listOf(.5, 1.0, 2.0, 4.0) } ?: 2.0
        nextRoamingSpawn = time + (1 + unitRandom()) / rate
        repeat(min(living.size, budget - roamingIDs.size)) {
            val anchor = living.minWith(compareBy<ArenaTank> { human -> roamingHomes.values.count { it == human.id } }.thenBy { it.id })
            val id = max(nextRoamingID, (snapshot.tanks.maxOfOrNull { it.id } ?: 1) + 1)
            nextRoamingID = id + 1
            val p = spawnPoint(anchor, 2, 5)
            val selected = BotDifficulty.index(rules.infinityBotDifficulty)
            val level = if (rules.infinityRandomDifficulty) BotDifficulty.names[random(selected + 1)] else BotDifficulty.names[selected]
            val team = if (rules.teamMode == "teams") snapshot.tanks.size % 2 + 1 else 0
            snapshot.tanks += ArenaTank(id = id, name = "Bot ${id - 1}", x = p.x, y = p.y, angle = unitRandom() * 2 * PI - PI,
                colorIndex = if (team > 0) rules.teamColors.getOrNull(team - 1) ?: 0 else GamePalette.index(id - 1), team = team,
                bot = true, spawnProtected = true, spawnSerial = 1, invulnerable = 1.0, difficulty = level)
            roamingIDs += id
            roamingHomes[id] = anchor.id
        }
    }

    fun presentationSnapshot(
        fraction: Double,
        localInput: GameInput? = null,
        localInput2: GameInput? = null,
        nowSeconds: Double = System.nanoTime() / 1e9,
    ): ArenaSnapshot {
        if (!fraction.isFinite() || fraction < 0 || snapshot.result != null) {
            motionPresenters.values.forEach { it.reset() }
            return withTerminalFlights(snapshot, nowSeconds)
        }
        val f = min(fraction, 1.0)
        val dt = f / 60
        val result =
            snapshot.copy(
                tanks =
                    snapshot.tanks.map { t ->
                        if (t.hp <= 0) t.copy()
                        else
                            present(
                                t,
                                if (t.id == localID)
                                    localInput ?: movementInputs[t.id] ?: GameInput()
                                else if (t.id == 2 && !t.bot)
                                    localInput2 ?: movementInputs[t.id] ?: GameInput()
                                else movementInputs[t.id] ?: GameInput(),
                                f,
                                !t.bot,
                            )
                    },
            )
        val liveLocals = result.tanks.filter { !it.bot && it.hp > 0 }.map { it.id }.toSet()
        motionPresenters.keys.retainAll(liveLocals)
        if (dt <= 0) {
            projectiles.forEach { it.published = true }
            return withTerminalFlights(result, nowSeconds)
        }
        result.bullets = projectiles.map { original ->
            original.published = true
            val p = original.deepCopy()
            val span = min(dt, p.wire.life)
            p.wire.life -= span
            p.age += span
            if ((p.wire.kind == "homing" || p.wire.kind == "grenade")) guide(p, span)
            if (p.wire.kind == "grenade") {
                val drag = grenadeDragFactor(p.wire.life + span, p.wire.life)
                p.wire.vx *= drag
                p.wire.vy *= drag
            }
            advance(p, span, visualOnly = true)
            p.wire
        }
        return withTerminalFlights(result, nowSeconds)
    }

    private fun withTerminalFlights(result: ArenaSnapshot, now: Double): ArenaSnapshot {
        val elapsed = lastVisualWallTime?.let { (now - it).coerceIn(0.0, .1) } ?: 0.0
        if (now.isFinite()) lastVisualWallTime = now
        visualTime = max(time, visualTime + elapsed)
        terminalFlights.accept(snapshot.effects, visualTime, snapshot.tanks.size)
        contacts.accept(snapshot.effects, snapshot.tanks, visualTime, snapshot.tick.toDouble(), snapshot.tanks.filter { !it.bot }.map { it.id }.toSet())
        val image = terminalFlights.render(result.bullets, result.effects, visualTime, contacts::canCompleteProjectile)
        val contactImage = contacts.render(result.tanks, image.effects, visualTime, terminalFlights) { from, to ->
            TankMovement.presentationFitsBounds(to, maze.world) && (from.ghostTime > 0 || maze.rayHit(from.x, from.y, to.x-from.x, to.y-from.y, 17.0) == null)
        }
        return result.copy(tanks = contactImage.tanks, bullets = image.bullets, effects = contactImage.effects,
            result = if (hasPendingProjectileFlights) null else result.result)
    }

    private fun present(
        t: ArenaTank,
        input: GameInput,
        fraction: Double,
        local: Boolean,
    ): ArenaTank {
        val movement: (ArenaTank, GameInput, Double) -> Unit = { tank, controls, dt ->
            move(tank, controls, dt)
        }
        val clear: (ArenaTank, ArenaTank) -> Boolean = { a, b ->
            TankMovement.presentationFitsBounds(b, maze.world) &&
                (a.ghostTime > 0 ||
                    (!maze.blocked(b.x, b.y, 17.0) &&
                        maze.rayHit(a.x, a.y, b.x - a.x, b.y - a.y, 17.0) == null))
        }
        return if (local)
            motionPresenters
                .getOrPut(t.id) { TankMotionPresenter() }
                .present(
                    t,
                    input,
                    snapshot.tick,
                    snapshot.generation,
                    fraction,
                    movement,
                    clear,
                )
        else TankMovement.presentation(t, input, fraction, move = movement, canInterpolate = clear)
    }

    private fun move(t: ArenaTank, input: GameInput, dt: Double, ageStarman: Boolean = true) {
        val world = maze.world
        if (t.bot && world != null) TankMovement.stepBot(t, input, dt, world, ageStarman)
        else TankMovement.step(t, input, dt, maze, ageStarman)
    }

    private fun random(maximum: Int): Int {
        randomState = randomState xor (randomState shl 13)
        randomState = randomState xor (randomState ushr 17)
        randomState = randomState xor (randomState shl 5)
        return Integer.remainderUnsigned(randomState, maximum)
    }

    private fun unitRandom() = random(1 shl 24).toDouble() / (1 shl 24)

    private fun spawnPoint(origin: ArenaTank, minCells: Int, maxCells: Int): BeamPoint {
        val cx = floor(origin.x / 84)
        val cy = floor(origin.y / 84)
        var result = BeamPoint((cx + minCells + .5) * 84, (cy + .5) * 84)
        var best = Double.NEGATIVE_INFINITY
        repeat(96) {
            val dx = random(maxCells * 2 + 1) - maxCells
            val dy = random(maxCells * 2 + 1) - maxCells
            if (dx * dx + dy * dy !in minCells * minCells..maxCells * maxCells) return@repeat
            val p = BeamPoint((cx + dx + .5) * 84, (cy + dy + .5) * 84)
            if (maze.blocked(p.x, p.y, 17.0)) return@repeat
            val distance =
                snapshot.tanks.filter { it.hp > 0 }.minOfOrNull { hypot(it.x - p.x, it.y - p.y) }
                    ?: Double.POSITIVE_INFINITY
            if (distance > best) {
                result = p
                best = distance
            }
            if (distance >= 1.9 * 84) return result
        }
        maze.world?.let {
            result.x = result.x.coerceIn(42.0, it.width - 42)
            result.y = result.y.coerceIn(42.0, it.height - 42)
        }
        return result
    }

    private fun respawn(index: Int) {
        val old = snapshot.tanks[index]
        val p =
            respawnLocation?.invoke(old)
                ?: spawnPoint(if (old.id in roamingIDs) snapshot.tanks.filter { !it.bot && it.hp > 0 }.minByOrNull { hypot(it.x - old.x, it.y - old.y) } ?: old else if (old.bot) snapshot.tanks[0] else old, 2, 5)
        val replacement =
            ArenaTank(
                id = old.id,
                name = old.name,
                x = p.x,
                y = p.y,
                angle = unitRandom() * 2 * PI - PI,
                colorIndex = old.colorIndex,
                score = old.score,
                team = old.team,
                bot = old.bot,
                spawnProtected = true,
                spawnSerial = old.spawnSerial + 1,
                invulnerable = if (maze.world == null) 1.0 else 1.2,
                survivalEnemy = old.survivalEnemy,
                survivalBoss = old.survivalBoss,
                difficulty = old.difficulty,
            )
        snapshot.tanks = snapshot.tanks.toMutableList().also { it[index] = replacement }
        fireBlocked.remove(old.id)
        botCourses.remove(old.id)
        dumbBrains.remove(old.id)
        nextBoostEffects.remove(old.id)
    }

    private fun advanceEquipment(t: ArenaTank, dt: Double) {
        t.invulnerable = max(0.0, t.invulnerable - dt)
        if (t.invulnerable < 1e-9) {
            t.invulnerable = 0.0
            t.spawnProtected = false
        }
        t.protectedState = t.invulnerable > 0
        t.shield = max(0.0, t.shield - dt)
        if (t.shield < 1e-9) {
            t.shield = 0.0
            t.shieldCharges = 0
        }
        t.starmanTime = max(0.0, t.starmanTime - dt)
        if (t.starmanTime <= 0) {
            t.powerTime = max(0.0, t.powerTime - dt)
            if (t.powerTime < 1e-9) {
                t.powerTime = 0.0
                t.power = ""
                t.charges = 0
                t.machineRounds = 0
            }
        }
        t.cooldown = max(0.0, t.cooldown - dt)
        t.recoil = max(0.0, t.recoil - 9 * dt)
    }

    private fun populatePickups(dt: Double) {
        snapshot.pickups.forEach {
            it.life -= dt
            it.age += dt
        }
        snapshot.pickups = snapshot.pickups.filter { it.life > 0 }
        if (maze.world != null) {
            if (time < nextPickup || pickupRate == "off") return
            val range =
                when (pickupRate) {
                    "superfast" -> 1.0 to 2.0
                    "fast" -> 2.0 to 3.5
                    "slow" -> 7.0 to 10.0
                    else -> 4.0 to 6.0
                }
            nextPickup = time + range.first + unitRandom() * (range.second - range.first)
            spawnFixedPickup()
            return
        }
        if (pickupRate == "off" || enabledPickups.isEmpty() || time < nextPickup) return
        nextPickup = time + 1.25 + unitRandom() * 1.25
        val pilot = snapshot.tanks[0]
        if (pilot.hp <= 0) return
        snapshot.pickups =
            snapshot.pickups.filter { hypot(it.x - pilot.x, it.y - pilot.y) <= 11 * 84 }
        var nearby = snapshot.pickups.count { hypot(it.x - pilot.x, it.y - pilot.y) < 5 * 84 }
        repeat(90) {
            if (nearby >= 3 || snapshot.pickups.size >= 6) return
            val dx = random(7) - 3
            val dy = random(7) - 3
            if (dx * dx + dy * dy > 12) return@repeat
            val x = (floor(pilot.x / 84) + dx + .5) * 84
            val y = (floor(pilot.y / 84) + dy + .5) * 84
            if (
                snapshot.tanks.any { it.hp > 0 && hypot(it.x - x, it.y - y) < .85 * 84 } ||
                    snapshot.pickups.any { hypot(it.x - x, it.y - y) < 1.1 * 84 }
            )
                return@repeat
            snapshot.pickups += ArenaPickup(id = ++nextID, x = x, y = y, type = weightedPickup())
            nearby++
        }
    }

    private fun weightedPickup(): String {
        val weighted = enabledPickups.flatMap { kind ->
            List(if (kind in listOf("shield", "speed")) 6 else if (kind == "starman") 1 else 2) {
                kind
            }
        }
        return weighted[random(weighted.size)]
    }

    fun seedFixedPickups(count: Int) {
        repeat(count) { spawnFixedPickup() }
    }

    private fun spawnFixedPickup() {
        val world = maze.world ?: return
        if (pickupRate == "off" || enabledPickups.isEmpty()) return
        val area = world.cols * world.rows
        val cap = (area / 9.8).roundToInt()
        if (snapshot.pickups.size >= cap) return
        repeat(60) {
            val x = (random(world.cols) + .5) * 84
            val y = (random(world.rows) + .5) * 84
            if (
                snapshot.tanks.any { it.hp > 0 && hypot(it.x - x, it.y - y) < .85 * 84 } ||
                    snapshot.pickups.any { hypot(it.x - x, it.y - y) < 1.1 * 84 }
            )
                return@repeat
            val life = max(if (area <= 120) 30 else 0, cap * 8 / 3)
            snapshot.pickups +=
                ArenaPickup(
                    id = ++nextID,
                    x = x,
                    y = y,
                    type = weightedPickup(),
                    life = life.toDouble(),
                )
            return
        }
    }

    private fun collectPickups(index: Int) {
        for (p in snapshot.pickups) {
            val t = snapshot.tanks[index]
            if (p.life <= 0 || hypot(p.x - t.x, p.y - t.y) >= 30) continue
            p.life = 0.0
            applyPower(t, p.type, powerDuration, starDuration)
            if (t.bot && p.type == "grenade") held[t.id] = false
            effect("pickup", t.x, t.y, t.id)
        }
    }

    private fun effect(
        kind: String,
        x: Double,
        y: Double,
        owner: Int,
        points: List<BeamPoint> = emptyList(),
        flight: ProjectileFlight? = null,
        contact: CombatContact? = null,
    ) {
        snapshot.effects =
            (snapshot.effects +
                    ArenaEffect(
                        id = ++nextEffect,
                        kind = kind,
                        x = x,
                        y = y,
                        owner = owner,
                        points = points,
                        flight = flight,
                        contact = contact,
                        tick = snapshot.tick.toInt(),
                    ))
                .takeLast(48)
        effectTimes[nextEffect] = time
    }

    private fun botInput(index: Int, dt: Double): GameInput {
        val bot = snapshot.tanks[index]
        val targets =
            if (maze.world == null && bot.id in roamingIDs && bot.team == 0) snapshot.tanks.filter { !it.bot } else snapshot.tanks
        val pilot =
            targets
                .filter { it.hp > 0 && opposes(bot.id, it) }
                .minByOrNull { hypot(it.x - bot.x, it.y - bot.y) } ?: return GameInput()
        val level = bot.difficulty.ifEmpty { botDifficulty }
        val tuning =
            when (level) {
                "dumb" -> Triple(.35, .4, 3.0)
                "easy" -> Triple(.7, .75, 1.65)
                "hard" -> Triple(1.15, 1.15, .7)
                "godlike" -> Triple(1.3, 1.3, .45)
                else -> Triple(1.0, 1.0, 1.0)
            }
        val dx = pilot.x - bot.x
        val dy = pilot.y - bot.y
        val distance = hypot(dx, dy)
        val sight =
            if (level == "dumb") {
                if (maze.world == null) 8 * 84 * tuning.first else 6 * 84.0
            } else 6 * 84 * tuning.first
        val sees = distance < sight && maze.rayHit(bot.x, bot.y, dx, dy, 3.5) == null
        val goal = botGoal?.invoke(bot)
        val routing = goal != null && (!sees || distance > 168)
        if (level == "dumb") {
            val previous = dumbBrains[bot.id]
            val brain =
                if (previous?.first == bot.spawnSerial) previous.second
                else DumbBotBrain(max(0.0, time - dt)).also {
                    dumbBrains[bot.id] = bot.spawnSerial to it
                }
            val decided =
                brain.reconsider(time, pilot.id, atan2(dy, dx), sees && !routing, ::unitRandom)
            if (brain.tracks(pilot.id, sees && !routing)) {
                return GameInput(
                    fire =
                        brain.trigger(
                            time,
                            bot.angle,
                            pilot.invulnerable == 0.0 &&
                                pilot.starmanTime == 0.0 && bot.id !in fireBlocked,
                        ),
                    stickX = cos(brain.aim),
                    stickY = sin(brain.aim),
                    touchAim = false,
                    aimOnly = true,
                )
            }
            if (decided) {
                val target = if (routing) pilot.copy(x = goal!!.x, y = goal.y) else pilot
                botCourse(bot, target)?.let { botCourses[bot.id] = it }
            }
            val tx = (botCourses[bot.id]?.x ?: goal?.x ?: bot.x) - bot.x
            val ty = (botCourses[bot.id]?.y ?: goal?.y ?: bot.y) - bot.y
            val aim = atan2(ty, tx)
            val tilt = if (maze.world == null) .72 * tuning.second else 1.0
            return GameInput(
                stickX = cos(aim) * tilt,
                stickY = sin(aim) * tilt,
                touchAim = false,
                aimOnly = hypot(tx, ty) < 5,
            )
        }
        if ((!sees || routing) && time >= (botDecisions[bot.id] ?: 0.0)) {
            val target = if (routing) pilot.copy(x = goal!!.x, y = goal.y) else pilot
            botCourse(bot, target)?.let { botCourses[bot.id] = it }
            botDecisions[bot.id] =
                time +
                    if (maze.world == null) (.25 + unitRandom() * .25) / tuning.second
                    else BotDifficulty.from(level).think
        }
        val tx = if (sees && !routing) dx else (botCourses[bot.id]?.x ?: goal?.x ?: bot.x) - bot.x
        val ty = if (sees && !routing) dy else (botCourses[bot.id]?.y ?: goal?.y ?: bot.y) - bot.y
        val aim = atan2(ty, tx)
        val shotAim = atan2(dy, dx)
        val tilt = if (maze.world == null) tuning.second else 1.0
        return GameInput(
            fire =
                sees &&
                    pilot.invulnerable == 0.0 &&
                    abs(TankMovement.angleDelta(shotAim, bot.angle)) < .16 * tuning.third,
            stickX = cos(aim) * tilt,
            stickY = sin(aim) * tilt,
            touchAim = false,
            aimOnly = hypot(tx, ty) < 5 || sees && distance < 115,
        )
    }

    private fun botCourse(bot: ArenaTank, target: ArenaTank): BeamPoint? {
        val startX = floor(bot.x / 84).toInt()
        val startY = floor(bot.y / 84).toInt()
        val goalX = floor(target.x / 84).toInt()
        val goalY = floor(target.y / 84).toInt()
        val reach = maze.world?.let { max(it.cols, it.rows) } ?: 4
        val side = reach * 2 + 1
        val capacity = side * side
        if (routeMarks.size < capacity) {
            routeMarks = IntArray(capacity)
            routeQueue = IntArray(capacity)
            routeSteps = IntArray(capacity)
            routeStamp = 0
        }
        if (routeStamp == Int.MAX_VALUE) {
            routeMarks.fill(0)
            routeStamp = 0
        }
        val stamp = ++routeStamp
        val start = reach * side + reach
        var head = 0
        var tail = 1
        routeQueue[0] = start
        routeSteps[0] = -1
        routeMarks[start] = stamp
        var best = Int.MAX_VALUE
        var nearest = -1
        while (head < tail) {
            val cell = routeQueue[head]
            val firstStep = routeSteps[head++]
            val localX = cell % side - reach
            val localY = cell / side - reach
            val x = startX + localX
            val y = startY + localY
            if (firstStep >= 0) {
                val dx = x - goalX
                val dy = y - goalY
                val distance = dx * dx + dy * dy
                if (distance < best) {
                    best = distance
                    nearest = firstStep
                }
                if (distance == 0) break
            }
            // Match Swift's east, west, south, north search and first-step tie order exactly.
            for (direction in 0..3) {
                val dx = if (direction == 0) 1 else if (direction == 1) -1 else 0
                val dy = if (direction == 2) 1 else if (direction == 3) -1 else 0
                if (abs(localX + dx) > reach || abs(localY + dy) > reach) continue
                val next = cell + dx + dy * side
                if (
                    routeMarks[next] == stamp ||
                        maze.blocked((x + .5 + dx / 2.0) * 84, (y + .5 + dy / 2.0) * 84, 17.0)
                )
                    continue
                routeMarks[next] = stamp
                routeQueue[tail] = next
                routeSteps[tail++] = if (firstStep < 0) next else firstStep
            }
        }
        return if (nearest < 0) null
        else
            BeamPoint(
                (startX + nearest % side - reach + .5) * 84,
                (startY + nearest / side - reach + .5) * 84,
            )
    }

    private fun weaponControl(index: Int, fire: Boolean) {
        val t = snapshot.tanks[index]
        val pressed = fire && held[t.id] != true
        held[t.id] = fire
        if (!fire) fireBlocked.remove(t.id)
        if (t.hp <= 0 || t.spawnProtected && t.invulnerable > 1e-9) return
        if (pressed) {
            val grenades = projectiles.filter { it.wire.owner == t.id && it.wire.kind == "grenade" }
            if (grenades.isNotEmpty()) {
                grenades.forEach { detonate(it.wire, completedFlight(it)) }
                projectiles.removeAll { it.wire.owner == t.id && it.wire.kind == "grenade" }
                fireBlocked.add(t.id)
                return
            }
            if (t.power == "grenade") {
                fireBlocked.add(t.id)
                fireShot(index)
                return
            }
        }
        if (fire && t.id !in fireBlocked && t.power != "grenade") fireShot(index)
    }

    private fun fireShot(index: Int) {
        val t = snapshot.tanks[index]
        val kind = t.power
        val boosted = t.starmanTime > 0
        var spec = spec(kind)
        val world = maze.world
        if (world != null) {
            if (kind == "rapid")
                spec =
                    spec.copy(life = max(0.0, (world.width + world.height) / 2 - 28) / spec.speed)
            if (kind == "homing")
                spec = spec.copy(life = (world.width + world.height) / spec.speed + .5)
        }
        if (
            t.hp <= 0 ||
                t.spawnProtected && t.invulnerable > 1e-9 ||
                !boosted && (t.cooldown > 1e-9 || kind == "rapid" && t.machineRounds <= 0)
        )
            return
        val offsets = if (kind == "scatter") listOf(-.21, 0.0, .21) else listOf(0.0)
        val ordinary = projectiles.count { it.wire.owner == t.id && !it.boosted }
        if (!boosted && kind != "laser" && ordinary + offsets.size > spec.capacity) return
        val cooldown = if (boosted) 0.0 else spec.cooldown
        t.cooldown = cooldown
        t.cooldownTotal = cooldown
        t.recoil = 1.0
        if (kind == "laser") fireLaser(t)
        else {
            for (offset in offsets) {
                val launch = maze.launchRay(t.x, t.y, t.angle + offset, kind, spec.radius)
                if (launch == null) {
                    effect("impact", t.x, t.y, t.id)
                    continue
                }
                val p =
                    Projectile(
                        ArenaBullet(
                            id = ++nextID,
                            x = launch.x,
                            y = launch.y,
                            vx = launch.ux * spec.speed,
                            vy = launch.uy * spec.speed,
                            owner = t.id,
                            kind = kind,
                            colorIndex = t.colorIndex,
                            life = spec.life,
                        ),
                        boosted = boosted,
                        rangeLeft =
                            if (world != null && kind == "homing") world.width + world.height
                            else null,
                        pathTick = stepStarted * 60,
                    )
                if (launch.bounced) {
                    p.wire.bounces = 1
                    p.seekDelay = .04
                    p.rangeLeft = p.rangeLeft?.minus(launch.distance)
                }
                val muzzle = max(0.0, (if (kind == "cannon") 32.0 else 28.0) - launch.distance)
                if (advance(p, muzzle / spec.speed, recordTime = false)) projectiles.add(p)
            }
            if (!boosted || kind == "grenade" || time + 1e-9 >= (nextBoostEffects[t.id] ?: 0.0)) {
                nextBoostEffects[t.id] = time + 4.0 / 60
                effect("shot:$kind", t.x, t.y, t.id)
            }
            var remaining = max(0, 115 - if (boosted) 0 else ordinary + offsets.size)
            for (i in projectiles.indices.reversed()) {
                val p = projectiles[i]
                if (p.wire.owner == t.id && (boosted || p.boosted)) {
                    if (remaining > 0) remaining-- else p.wire.life = 0.0
                }
            }
            projectiles.removeAll { it.wire.life <= 0 }
        }
        if (boosted || kind.isEmpty()) return
        if (kind == "rapid") t.machineRounds-- else t.charges--
        if (if (kind == "rapid") t.machineRounds <= 0 else t.charges <= 0) {
            t.power = ""
            t.powerTime = 0.0
            t.charges = 0
        }
    }

    private data class TargetHit(val index: Int, val fraction: Double)

    private fun targetHit(
        owner: Int,
        x: Double,
        y: Double,
        dx: Double,
        dy: Double,
        radius: Double,
        limit: Double,
        contact: Boolean = false,
    ): TargetHit? {
        var best = limit
        var target: Int? = null
        val ownerTeam = team(owner)
        for (i in snapshot.tanks.indices) {
            val t = snapshot.tanks[i]
            if (
                t.hp <= 0 ||
                    t.id == owner ||
                    !contact &&
                        (!(friendlyFire || ownerTeam == 0 || ownerTeam != t.team) ||
                            t.invulnerable > 0)
            )
                continue
            val f = circleHit(x, y, dx, dy, t.x, t.y, 17 + radius)
            if (f != null && f < best) {
                best = f
                target = i
            }
        }
        return target?.let { TargetHit(it, best) }
    }

    private fun recordFlightPoint(p: Projectile) {
        val points = p.flightPoints ?: ArrayList<ProjectileFlightPoint>(4).also {
            it += if (p.wire.kind == "cannon") ProjectileFlightPoint(p.birthX, p.birthY, p.birthTick) else ProjectileFlightPoint(p.segmentX, p.segmentY, p.segmentTick)
            p.flightPoints = it
        }
        val point = ProjectileFlightPoint(p.wire.x, p.wire.y, p.pathTick)
        if (points.lastOrNull() == point) return
        if (points.size >= 32) points.removeAt(1)
        points += point
    }

    private fun completedFlight(p: Projectile): ProjectileFlight? {
        recordFlightPoint(p)
        val recorded = p.flightPoints ?: return null
        val points = if (recorded.size == 1) recorded + recorded.single() else recorded.toList()
        if (points.size < 2) return null
        return ProjectileFlight(p.wire.id, p.wire.owner, p.wire.colorIndex, points.first().tick, points.last().tick,
            points, p.wire.kind.ifEmpty { "regular" }, p.radius)
    }

    private fun advance(p: Projectile, dt: Double, visualOnly: Boolean = false, recordTime: Boolean = true): Boolean {
        var dx = p.wire.vx * dt
        var dy = p.wire.vy * dt
        var remaining = dt
        repeat(4) {
            val b = p.wire
            val wall = maze.projectileHit(b.kind, b.x, b.y, dx, dy, p.radius)
            val target =
                targetHit(
                    b.owner,
                    b.x,
                    b.y,
                    dx,
                    dy,
                    p.radius,
                    wall?.fraction ?: 1.00000001,
                    b.kind == "grenade",
                )
            if (target != null) {
                b.x += dx * target.fraction
                b.y += dy * target.fraction
                p.rangeLeft = p.rangeLeft?.minus(hypot(dx, dy) * target.fraction)
                if (!visualOnly) {
                    if (recordTime) p.pathTick += remaining * target.fraction * 60
                    val flight = completedFlight(p)
                    if (b.kind == "grenade") detonate(b, flight)
                    else {
                        if ((b.kind == "homing" || b.kind == "cannon"))
                            effect("impact", b.x, b.y, b.owner, flight = flight)
                        else if (flight != null) effect("projectileFlight", b.x, b.y, b.owner, flight = flight)
                        hurt(target.index, b.owner, projectileId = b.id, kind = b.kind.ifEmpty { "regular" }, contactTick = p.pathTick)
                    }
                }
                return false
            }
            if (wall == null) {
                b.x += dx
                b.y += dy
                p.rangeLeft = p.rangeLeft?.minus(hypot(dx, dy))
                if (!visualOnly && recordTime) p.pathTick += remaining * 60
                return true
            }
            b.bounces++
            val limit =
                if ((b.kind == "homing" || b.kind == "rapid" || b.kind == "grenade")) 128 else 22
            if (!visualOnly && b.bounces > limit) {
                val flight = completedFlight(p)
                if (b.kind == "grenade") detonate(b, flight)
                else if (flight != null) effect("projectileFlight", b.x, b.y, b.owner, flight = flight)
                return false
            }
            b.x += dx * wall.fraction + wall.nx * .12
            b.y += dy * wall.fraction + wall.ny * .12
            if (!visualOnly) {
                if (recordTime) p.pathTick += remaining * wall.fraction * 60
                recordFlightPoint(p)
            }
            remaining *= 1 - wall.fraction
            p.rangeLeft = p.rangeLeft?.minus(hypot(dx, dy) * wall.fraction)
            dx *= 1 - wall.fraction
            dy *= 1 - wall.fraction
            if (wall.nx != 0.0) {
                dx = -dx
                b.vx = -b.vx
            }
            if (wall.ny != 0.0) {
                dy = -dy
                b.vy = -b.vy
            }
            b.target = 0
            p.seekDelay = .04
            if (wall.fraction == 1.0) return true
        }
        return true
    }

    private fun guide(p: Projectile, dt: Double) {
        p.seekDelay = max(0.0, p.seekDelay - dt)
        if (p.age < .1 || p.seekDelay != 0.0) return
        val b = p.wire
        val speed = hypot(b.vx, b.vy)
        var closest = 10 * 84.0
        var target: ArenaTank? = null
        val ownerTeam = team(b.owner)
        for (t in snapshot.tanks) {
            if (
                t.id == b.owner ||
                    ownerTeam != 0 && ownerTeam == t.team ||
                    t.hp <= 0 ||
                    t.invulnerable != 0.0 ||
                    b.target != 0 && b.target != t.id
            )
                continue
            val dx = t.x - b.x
            val dy = t.y - b.y
            val distance = hypot(dx, dy)
            if (
                distance >= closest ||
                    dx * b.vx + dy * b.vy < -.75 * distance * speed ||
                    maze.rayHit(b.x, b.y, dx, dy, p.radius) != null
            )
                continue
            target = t
            closest = distance
        }
        if (target == null) {
            if (b.target != 0) p.seekDelay = .06
            b.target = 0
            return
        }
        b.target = target.id
        val angle = atan2(b.vy, b.vx)
        val desired = atan2(target.y - b.y, target.x - b.x)
        val turn = TankMovement.angleDelta(desired, angle).coerceIn(-4.8 * dt, 4.8 * dt)
        b.vx = cos(angle + turn) * speed
        b.vy = sin(angle + turn) * speed
    }

    private fun fireLaser(t: ArenaTank) {
        val launch = maze.launchRay(t.x, t.y, t.angle, "laser", 3.0)
        if (launch == null) {
            effect("impact", t.x, t.y, t.id)
            return
        }
        var x = launch.x
        var y = launch.y
        var ux = launch.ux
        var uy = launch.uy
        var remaining =
            max(
                0.0,
                (maze.world?.let { 4 * (it.width + it.height) } ?: 36 * 84.0) - launch.distance,
            )
        val points = mutableListOf<BeamPoint>()
        var hit: Int? = null
        for (i in 0 until 256) {
            val dx = ux * remaining
            val dy = uy * remaining
            val wall = maze.rayHit(x, y, dx, dy, 3.0)
            val target = targetHit(t.id, x, y, dx, dy, 3.0, wall?.fraction ?: 1.00000001)
            val length = remaining * (target?.fraction ?: wall?.fraction ?: 1.0)
            if (i == 0) {
                val crop = if (launch.bounced) 0.0 else 28.0
                points.add(BeamPoint(x + ux * min(crop, length), y + uy * min(crop, length)))
            }
            x += ux * length
            y += uy * length
            remaining -= length
            points.add(BeamPoint(x, y))
            if (target != null) {
                hit = target.index
                break
            }
            if (wall == null || remaining <= 1e-7) break
            if (wall.nx != 0.0) ux = -ux
            if (wall.ny != 0.0) uy = -uy
            val nudge = min(.001, remaining)
            x += ux * nudge
            y += uy * nudge
            remaining -= nudge
        }
        if (
            t.starmanTime <= 0 ||
                time + 1e-9 >= (nextBoostEffects[t.id] ?: 0.0) ||
                hit != null
        ) {
            nextBoostEffects[t.id] = time + 4.0 / 60
            effect("laser", t.x, t.y, t.id, points)
        }
        hit?.let { hurt(it, t.id, kind = "laser") }
    }

    private fun detonate(b: ArenaBullet, flight: ProjectileFlight? = null) {
        effect("blast", b.x, b.y, b.owner, flight = flight)
        for (i in snapshot.tanks.indices) {
            val t = snapshot.tanks[i]
            if (
                t.id == b.owner ||
                    t.hp <= 0 ||
                    t.invulnerable != 0.0 ||
                    hypot(t.x - b.x, t.y - b.y) > 237 ||
                    maze.rayHit(b.x, b.y, t.x - b.x, t.y - b.y, 0.0) != null
            )
                continue
            hurt(i, b.owner, projectileId = b.id, kind = "grenade", contactTick = flight?.endTick ?: snapshot.tick.toDouble())
        }
    }

    private fun hurt(index: Int, owner: Int, starman: Boolean = false, projectileId: Int = 0, kind: String = if (starman) "starman" else "laser", contactTick: Double = snapshot.tick.toDouble()) {
        val t = snapshot.tanks[index]
        if (
            owner == t.id ||
                !friendlyFire && !opposes(owner, t) ||
                t.hp <= 0 ||
                !starman && t.invulnerable != 0.0
        )
            return
        val contact = CombatContact(projectileId, kind, contactTick, t.id, t.spawnSerial,
            ContactTankState(t.x, t.y, t.angle, hp = t.hp, shield = t.shield, shieldCharges = t.shieldCharges, invulnerable = t.invulnerable, spawnProtected = t.spawnProtected))
        if (!starman && t.shield > 0) {
            t.shieldCharges = max(1, t.shieldCharges) - 1
            if (t.shieldCharges == 0) t.shield = 0.0
            t.invulnerable = .35
            t.spawnProtected = false
            effect("shield", t.x, t.y, owner, contact = contact)
            return
        }
        t.hp = 0
        if (killScoring) t.score--
        t.respawnTime = if (respawnsEnabled) respawnDelay else 0.0
        snapshot.tanks
            .firstOrNull { it.id == owner }
            ?.let {
                if (killScoring) it.score++
                t.killedBy = it.name
                t.killedByColor = GamePalette.colors[GamePalette.index(it.colorIndex)]
            }
        effect("hit", t.x, t.y, owner, contact = contact)
    }

    private fun team(id: Int) = snapshot.tanks.firstOrNull { it.id == id }?.team ?: 0

    private fun opposes(owner: Int, target: ArenaTank) =
        owner != target.id && (team(owner) == 0 || team(owner) != target.team)

    private fun starmanContacts() {
        for (attacker in snapshot.tanks.filter { it.hp > 0 && it.starmanTime > 0 }) for (i in
            snapshot.tanks.indices) {
            val t = snapshot.tanks[i]
            if (
                t.hp > 0 &&
                    t.id != attacker.id &&
                    t.starmanTime == 0.0 &&
                    (t.invulnerable == 0.0 || t.spawnProtected) &&
                    hypot(t.x - attacker.x, t.y - attacker.y) <= 34 &&
                    !maze.segmentBlocked(attacker.x, attacker.y, t.x - attacker.x, t.y - attacker.y)
            )
                hurt(i, attacker.id, true)
        }
    }

    private fun updateStandings() {
        data class Owned(
            var ammo: Int = 0,
            var grenades: Int = 0,
            var grenadeLife: Double = 0.0,
            var locked: Boolean = false,
        )
        val owned = Array(snapshot.tanks.size) { Owned() }
        val indices = snapshot.tanks.mapIndexed { i, t -> t.id to i }.toMap()
        val boosted = mutableListOf<Int>()
        for (p in projectiles) {
            val b = p.wire
            if (p.boosted) boosted.add(b.id)
            indices[b.owner]?.let { i ->
                if (!p.boosted) owned[i].ammo++
                if (b.kind == "grenade") {
                    owned[i].grenades++
                    owned[i].grenadeLife = max(owned[i].grenadeLife, b.life)
                }
            }
            indices[b.target]?.let { i ->
                if (
                    b.owner != snapshot.tanks[i].id &&
                        (friendlyFire ||
                            team(b.owner) == 0 ||
                            team(b.owner) != snapshot.tanks[i].team)
                )
                    owned[i].locked = true
            }
        }
        snapshot.boostedBulletIds = boosted
        val sorted =
            snapshot.tanks.sortedWith(compareByDescending<ArenaTank> { it.score }.thenBy { it.id })
        snapshot.leaderboard =
            sorted.take(10).map {
                LeaderboardEntry(it.id, it.name, it.score, it.colorIndex, it.bot, it.team)
            }
        snapshot.tankCount = snapshot.tanks.size
        snapshot.teamScores =
            (1..4).map { team -> snapshot.tanks.filter { it.team == team }.sumOf { it.score } }
        snapshot.tanks.forEachIndexed { i, t ->
            t.rank = sorted.indexOfFirst { it.id == t.id } + 1
            t.ammoUsed = owned[i].ammo
            t.grenades = owned[i].grenades
            t.grenadeLife = owned[i].grenadeLife
            t.locked = owned[i].locked
        }
        val rules = activeRules
        if (
            maze.world == null &&
                rules != null &&
                rules.infinityTarget > 0 &&
                snapshot.result == null
        ) {
            if (rules.teamMode == "teams") {
                val winner = snapshot.teamScores.indexOfFirst { it >= rules.infinityTarget }
                if (winner >= 0)
                    snapshot.result =
                        ArenaResult(
                            name = rules.teamNames.getOrNull(winner) ?: "Team ${winner+1}",
                            team = winner + 1,
                            score = snapshot.teamScores[winner],
                        )
            } else
                sorted
                    .firstOrNull { it.score >= rules.infinityTarget }
                    ?.let { snapshot.result = ArenaResult(it.id, it.name, score = it.score) }
        }
    }

    companion object {
        val pickupKinds =
            listOf(
                "rapid",
                "scatter",
                "shield",
                "homing",
                "grenade",
                "speed",
                "laser",
                "cannon",
                "ghost",
                "starman",
            )

        data class WeaponSpec(
            val speed: Double,
            val radius: Double,
            val life: Double,
            val cooldown: Double,
            val capacity: Int,
        )

        private val rapidSpec = WeaponSpec(846.0, 3.5 / 3, 18 * 84.0 / 846, 0.0, 115)
        private val scatterSpec = WeaponSpec(846.0, 3.5, 3.9, .54, 12)
        private val homingSpec = WeaponSpec(235.0, 5.0, 18 * 84.0 / 235, .72, 3)
        private val grenadeSpec = WeaponSpec(205.0, 6.0, 10.0, .8, 3)
        private val cannonSpec = WeaponSpec(1128.0, 14.0, 5.3, .85 * 2 / 3, 3)
        private val laserSpec = WeaponSpec(0.0, 3.0, 0.0, .85 * 2 / 3, 3)
        private val standardSpec = WeaponSpec(282.0, 3.5, 5.3, .34, 5)

        fun spec(kind: String) =
            when (kind) {
                "rapid" -> rapidSpec
                "scatter" -> scatterSpec
                "homing" -> homingSpec
                "grenade" -> grenadeSpec
                "cannon" -> cannonSpec
                "laser" -> laserSpec
                else -> standardSpec
            }

        fun applyPower(
            tank: ArenaTank,
            kind: String,
            duration: Double = 15.0,
            starDuration: Double = 8.0,
        ) {
            with(tank) {
                when (kind) {
                    "shield" -> {
                        shieldCharges = min(5, (if (shield > 0) max(1, shieldCharges) else 0) + 1)
                        shield = duration
                    }
                    "speed" -> {
                        speedStacks = min(5, (if (speedTime > 0) max(1, speedStacks) else 0) + 1)
                        speedTime = duration
                    }
                    "ghost" -> ghostTime = duration
                    "starman" -> {
                        starmanTime = starDuration
                        spawnProtected = false
                        invulnerable = max(invulnerable, starDuration)
                        ghostTime = max(ghostTime, starDuration)
                        cooldown = 0.0
                        cooldownTotal = 0.0
                    }
                    "rapid",
                    "scatter",
                    "homing",
                    "grenade",
                    "laser",
                    "cannon" -> {
                        power = kind
                        powerTime = duration
                        charges = if (kind in listOf("rapid", "scatter")) 5 else 3
                        machineRounds = if (kind == "rapid") 180 else 0
                        if (kind == "rapid") {
                            cooldown = 0.0
                            cooldownTotal = 0.0
                        }
                    }
                }
            }
        }

        fun grenadeDragFactor(lifeBefore: Double, lifeAfter: Double): Double {
            fun integral(life: Double): Double {
                val age = 10 - life.coerceIn(0.0, 10.0)
                val braking = max(0.0, age - 7)
                return .025 * age + 2 * braking * braking * braking / 27
            }
            return exp(-(integral(lifeAfter) - integral(lifeBefore)))
        }

        fun circleHit(
            x: Double,
            y: Double,
            dx: Double,
            dy: Double,
            tx: Double,
            ty: Double,
            radius: Double,
        ): Double? {
            val ox = x - tx
            val oy = y - ty
            val c = ox * ox + oy * oy - radius * radius
            if (c <= 0) return 0.0
            val a = dx * dx + dy * dy
            if (a < 1e-12) return null
            val b = 2 * (ox * dx + oy * dy)
            val disc = b * b - 4 * a * c
            if (disc < 0) return null
            val f = (-b - sqrt(disc)) / (2 * a)
            return f.takeIf { it in 0.0..1.0 }
        }
    }
}
