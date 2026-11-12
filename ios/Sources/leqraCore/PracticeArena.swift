import Foundation

/// Native, deterministic Infinity practice. Online damage and scoring always
/// come from the Go server. Practice bots use bounded local pathfinding.
public final class PracticeArena {
    public let maze: InfiniteMaze
    public let localID = 1
    public internal(set) var snapshot = ArenaSnapshot()
    var respawnsEnabled = true
    var respawnDelay = 1.0
    var killScoring = true
    var friendlyFire = false
    var respawnLocation: ((ArenaTank) -> (x: Double, y: Double))?
    var botGoal: ((ArenaTank) -> (x: Double, y: Double)?)?
    private var pickupRate = "normal"
    private var enabledPickups = PracticeArena.pickupKinds
    private var botDifficulty = "normal"
    private var powerDuration = 15.0
    private var starDuration = 8.0
    private var activeRules: RoomRules?
    private var roamingIDs = Set<Int>()
    private var hasConfiguredRules = false
    private var randomState: UInt32
    private var time = 0.0
    private var nextPickup = 0.0
    private var nextID = 1
    private var nextEffect = 0
    private var effectTimes: [Int: Double] = [:]
    private var held: [Int: Bool] = [:]
    private var movementInputs: [Int: GameInput] = [:]
    private var fireBlocked: Set<Int> = []
    private var botCourses: [Int: (x: Double, y: Double)] = [:]
    private var botDecisions: [Int: Double] = [:]
    private var nextBoostEffects: [Int: Double] = [:]
    private let motionPresenter = TankMotionPresenter()
    private struct Projectile {
        var wire: ArenaBullet
        var age = 0.0
        var seekDelay = 0.0
        var boosted = false
        var rangeLeft: Double?
        var radius: Double { PracticeArena.spec(wire.kind).radius }
    }
    private var projectiles: [Projectile] = []
    private static let pickupKinds = ["rapid", "scatter", "shield", "homing", "grenade", "speed", "laser", "cannon", "ghost", "starman"]

    public init(seed: UInt32 = 0x1e9a2026, name: String, colorIndex: Int,
                botCount: Int = 8, difficulty: String = "normal", world: ArenaWorld? = nil) {
        maze = world.map { InfiniteMaze(world: $0) } ?? InfiniteMaze(seed: seed)
        botDifficulty = difficulty
        randomState = seed == 0 ? 1 : seed
        snapshot.tanks = [ArenaTank(id: localID, name: name, x: 42, y: 42,
                                   colorIndex: GamePalette.index(colorIndex), spawnProtected: true,
                                   spawnSerial: 1, invulnerable: 1)]
        for number in 0..<max(0, min(world == nil ? 24 : 7, botCount)) {
            let number = number + 1
            let origin = snapshot.tanks[0], point = spawnPoint(near: origin, minCells: 2, maxCells: 5)
            snapshot.tanks.append(ArenaTank(id: number + 1, name: String(format: "ROVER %02d", number),
                                           x: point.x, y: point.y, angle: unitRandom() * 2 * .pi - .pi,
                                           colorIndex: GamePalette.index(colorIndex + number), bot: true,
                                           spawnProtected: true, spawnSerial: 1, invulnerable: 1, difficulty: difficulty))
            roamingIDs.insert(number + 1)
        }
        snapshot.players = 1
        updateStandings()
    }

    public func configurePilot(id: Int, name: String, colorIndex: Int, team: Int = 0, difficulty: String = "normal") {
        guard let index = snapshot.tanks.firstIndex(where: { $0.id == id }) else { return }
        snapshot.tanks[index].name = String(name.prefix(16))
        let team = activeRules?.teamMode == "ffa" ? 0 : max(0, min(4, team))
        let paint = team > 0 ? activeRules?.teamColors.indices.contains(team - 1) == true ? activeRules!.teamColors[team - 1] : colorIndex : colorIndex
        snapshot.tanks[index].colorIndex = GamePalette.index(paint)
        snapshot.tanks[index].team = team
        snapshot.tanks[index].difficulty = difficulty
        updateStandings()
    }

    public func configure(rules: RoomRules) {
        activeRules = rules
        snapshot.rules = rules
        friendlyFire = rules.friendlyFire
        if let world = maze.world {
            pickupRate = rules.pickupRate
            enabledPickups = rules.weapons.filter { Self.pickupKinds.contains($0) }
            powerDuration = world.cols * world.rows >= 168 ? 15 : 10
            let area = world.cols * world.rows
            starDuration = area >= 336 ? 8 : area >= 224 ? 7 : area >= 168 ? 6 : area >= 120 ? 5 : 4
        } else {
            // Infinity has its own fixed pickup population, independent of the
            // finite-room frequency and arsenal saved in these shared rules.
            if hasConfiguredRules {
                snapshot.tanks.removeAll { roamingIDs.contains($0.id) }
                projectiles.removeAll { roamingIDs.contains($0.wire.owner) }
            }
            hasConfiguredRules = true
            roamingIDs.removeAll()
            for index in snapshot.tanks.indices {
                snapshot.tanks[index].team = rules.teamMode == "teams" ? (snapshot.tanks[index].team > 0 ? snapshot.tanks[index].team : index % 2 + 1) : 0
                if snapshot.tanks[index].team > 0 {
                    let team = snapshot.tanks[index].team - 1
                    if rules.teamColors.indices.contains(team) { snapshot.tanks[index].colorIndex = rules.teamColors[team] }
                }
            }
            if rules.infinityRandomBots {
                let levels = ["easy", "normal", "hard", "godlike"], selected = levels.firstIndex(of: rules.infinityBotDifficulty) ?? 1
                let firstID = (snapshot.tanks.map(\.id).max() ?? 1) + 1
                for offset in 0..<8 {
                    let id = firstID + offset, point = spawnPoint(near: snapshot.tanks[0], minCells: 2, maxCells: 5)
                    let team = rules.teamMode == "teams" ? (snapshot.tanks.count % 2 + 1) : 0
                    let color = team > 0 && rules.teamColors.indices.contains(team - 1) ? rules.teamColors[team - 1] : GamePalette.index(offset + 1)
                    let level = rules.infinityRandomDifficulty ? levels[random(selected + 1)] : levels[selected]
                    snapshot.tanks.append(ArenaTank(id: id, name: "BOT \(offset + 1)", x: point.x, y: point.y,
                        angle: unitRandom() * 2 * .pi - .pi, colorIndex: color, team: team, bot: true,
                        spawnProtected: true, spawnSerial: 1, invulnerable: 1, difficulty: level))
                    roamingIDs.insert(id)
                }
            }
        }
        updateStandings()
    }

    func clearProjectiles() { projectiles.removeAll(); snapshot.bullets.removeAll() }
    func refreshStandings() { updateStandings() }

    public func step(input: GameInput, dt: Double) {
        guard dt.isFinite, dt > 0, dt <= 0.1 else { return }
        guard !snapshot.tanks.isEmpty, snapshot.result == nil else { return }
        time += dt
        snapshot.tick += 1
        snapshot.effects.removeAll { time - (effectTimes[$0.id] ?? 0) >= 0.15 }
        let liveEffects = Set(snapshot.effects.map(\.id))
        effectTimes = effectTimes.filter { liveEffects.contains($0.key) }
        populatePickups(dt: dt)
        for index in snapshot.tanks.indices {
            if snapshot.tanks[index].hp == 0 {
                guard respawnsEnabled else { snapshot.tanks[index].respawnTime = 0; continue }
                snapshot.tanks[index].respawnTime = max(0, snapshot.tanks[index].respawnTime - dt)
                if snapshot.tanks[index].respawnTime <= 1e-9 { respawn(index) }
                continue
            }
            advanceEquipment(index, dt: dt)
        }
        let count = snapshot.tanks.count
        for offset in 0..<count {
            let index = (Int(snapshot.tick % UInt64(count)) + offset) % count
            guard snapshot.tanks[index].hp > 0 else { continue }
            var controls = snapshot.tanks[index].bot ? botInput(index) : input
            if snapshot.tanks[index].bot && fireBlocked.contains(snapshot.tanks[index].id) { controls.fire = false }
            movementInputs[snapshot.tanks[index].id] = controls
            move(tank: &snapshot.tanks[index], input: controls, dt: dt)
            collectPickups(index)
            weaponControl(index, fire: controls.fire)
        }
        starmanContacts()
        if let world = maze.world {
            for a in snapshot.tanks.indices {
                for b in snapshot.tanks.indices where b > a {
                    let first = snapshot.tanks[a], second = snapshot.tanks[b]
                    guard first.hp > 0, second.hp > 0 else { continue }
                    var dx = second.x - first.x, dy = second.y - first.y, distance = hypot(dx, dy)
                    let overlap = 34 - distance
                    guard overlap > 0 else { continue }
                    if first.ghostTime > 0 || second.ghostTime > 0 {
                        if maze.segmentBlocked(x: first.x, y: first.y, dx: dx, dy: dy) { continue }
                    }
                    if distance < 0.001 { dx = 1; dy = 0; distance = 1 }
                    TankMovement.displace(tank: &snapshot.tanks[a], dx: -dx / distance * overlap / 2, dy: -dy / distance * overlap / 2, world: world)
                    TankMovement.displace(tank: &snapshot.tanks[b], dx: dx / distance * overlap / 2, dy: dy / distance * overlap / 2, world: world)
                }
            }
        }
        var survivorCount = 0
        // This array is private to the simulation. Compact it in order rather
        // than allocating and growing a second projectile array every tick.
        for index in projectiles.indices {
            var projectile = projectiles[index]
            let span = min(dt, projectile.wire.life, projectile.rangeLeft.map { $0 / max(1, hypot(projectile.wire.vx, projectile.wire.vy)) } ?? .infinity)
            projectile.wire.life -= span
            projectile.age += span
            if projectile.wire.kind == "homing" || projectile.wire.kind == "grenade" { guide(&projectile, dt: span) }
            if projectile.wire.kind == "grenade" {
                let drag = Self.grenadeDragFactor(lifeBefore: projectile.wire.life + span, lifeAfter: projectile.wire.life)
                projectile.wire.vx *= drag; projectile.wire.vy *= drag
            }
            guard advance(&projectile, dt: span) else { continue }
            if projectile.wire.life > 1e-9 && (projectile.rangeLeft ?? 1) > 1e-7 {
                projectiles[survivorCount] = projectile
                survivorCount += 1
            }
            else if projectile.wire.kind == "grenade" { detonate(projectile.wire) }
            else if projectile.wire.kind == "homing" && maze.world != nil {
                effect("impact", x: projectile.wire.x, y: projectile.wire.y, owner: projectile.wire.owner)
            }
        }
        projectiles.removeLast(projectiles.count - survivorCount)
        snapshot.bullets = projectiles.map(\.wire)
        snapshot.pickups.removeAll { $0.life <= 0 }
        updateStandings()
    }

    /// Smooth presentation between deterministic 60 Hz simulation ticks.
    /// `fraction` is the remaining fraction of one tick, clamped to 0...1.
    /// Prediction changes only this returned copy, never damage or score.
    public func presentationSnapshot(fraction: Double, localInput: GameInput? = nil) -> ArenaSnapshot {
        guard fraction.isFinite, fraction >= 0, snapshot.result == nil else {
            motionPresenter.reset()
            return snapshot
        }
        let fraction = min(fraction, 1), dt = fraction / 60
        var result = snapshot
        for index in result.tanks.indices where result.tanks[index].hp > 0 {
            let id = result.tanks[index].id
            let input = id == localID ? localInput ?? movementInputs[id] ?? GameInput() : movementInputs[id] ?? GameInput()
            result.tanks[index] = present(result.tanks[index], input: input, fraction: fraction, local: id == localID)
        }
        if !result.tanks.contains(where: { $0.id == localID && $0.hp > 0 }) { motionPresenter.reset() }
        guard dt > 0 else { return result }
        result.bullets = projectiles.map { original in
            var projectile = original
            let span = min(dt, projectile.wire.life)
            projectile.wire.life -= span; projectile.age += span
            if projectile.wire.kind == "homing" || projectile.wire.kind == "grenade" { guide(&projectile, dt: span) }
            if projectile.wire.kind == "grenade" {
                let drag = Self.grenadeDragFactor(lifeBefore: projectile.wire.life + span, lifeAfter: projectile.wire.life)
                projectile.wire.vx *= drag; projectile.wire.vy *= drag
            }
            var dx = projectile.wire.vx * span, dy = projectile.wire.vy * span
            for _ in 0..<4 {
                let bullet = projectile.wire
                let wall = maze.projectileHit(kind: bullet.kind, x: bullet.x, y: bullet.y, dx: dx, dy: dy, radius: projectile.radius)
                if let target = targetHit(owner: bullet.owner, x: bullet.x, y: bullet.y, dx: dx, dy: dy,
                                          radius: projectile.radius, limit: wall?.fraction ?? 1.00000001,
                                          contact: bullet.kind == "grenade") {
                    projectile.wire.x += dx * target.fraction; projectile.wire.y += dy * target.fraction
                    break
                }
                guard let wall else { projectile.wire.x += dx; projectile.wire.y += dy; break }
                projectile.wire.x += dx * wall.fraction + wall.nx * 0.12
                projectile.wire.y += dy * wall.fraction + wall.ny * 0.12
                projectile.wire.bounces += 1
                dx *= 1 - wall.fraction; dy *= 1 - wall.fraction
                if wall.nx != 0 { dx = -dx; projectile.wire.vx = -projectile.wire.vx }
                if wall.ny != 0 { dy = -dy; projectile.wire.vy = -projectile.wire.vy }
                if wall.fraction == 1 { break }
            }
            return projectile.wire
        }
        return result
    }

    private func present(_ tank: ArenaTank, input: GameInput, fraction: Double, local: Bool = false) -> ArenaTank {
        let movement: (inout ArenaTank, GameInput, Double) -> Void = { self.move(tank: &$0, input: $1, dt: $2) }
        let clear: (ArenaTank, ArenaTank) -> Bool = { first, second in
            TankMovement.presentationFitsBounds(tank: second, world: self.maze.world)
                && (first.ghostTime > 0 || (!self.maze.blocked(x: second.x, y: second.y, radius: 17)
                && self.maze.rayHit(x: first.x, y: first.y,
                    dx: second.x - first.x, dy: second.y - first.y, radius: 17) == nil))
        }
        if local {
            return motionPresenter.present(tank: tank, input: input, tick: snapshot.tick,
                generation: snapshot.generation, fraction: fraction, move: movement, canInterpolate: clear)
        }
        return TankMovement.presentation(tank: tank, input: input, fraction: fraction,
                                         move: movement, canInterpolate: clear)
    }

    private func move(tank: inout ArenaTank, input: GameInput, dt: Double) {
        if tank.bot, let world = maze.world { TankMovement.stepBot(tank: &tank, input: input, dt: dt, world: world) }
        else { TankMovement.step(tank: &tank, input: input, dt: dt, maze: maze) }
    }

    private func random(_ maximum: Int) -> Int {
        randomState ^= randomState << 13; randomState ^= randomState >> 17; randomState ^= randomState << 5
        return Int(randomState % UInt32(maximum))
    }
    private func unitRandom() -> Double { Double(random(1 << 24)) / Double(1 << 24) }

    private func spawnPoint(near origin: ArenaTank, minCells: Int, maxCells: Int) -> (x: Double, y: Double) {
        let cx = floor(origin.x / 84), cy = floor(origin.y / 84)
        var result = (x: (cx + Double(minCells) + 0.5) * 84, y: (cy + 0.5) * 84)
        var best = -Double.infinity
        for _ in 0..<96 {
            let dx = random(maxCells * 2 + 1) - maxCells, dy = random(maxCells * 2 + 1) - maxCells
            guard dx * dx + dy * dy >= minCells * minCells, dx * dx + dy * dy <= maxCells * maxCells else { continue }
            let point = (x: (cx + Double(dx) + 0.5) * 84, y: (cy + Double(dy) + 0.5) * 84)
            if maze.blocked(x: point.x, y: point.y, radius: 17) { continue }
            let distance = snapshot.tanks.filter { $0.hp > 0 }.map { hypot($0.x - point.x, $0.y - point.y) }.min() ?? .infinity
            if distance > best { result = point; best = distance }
            if distance >= 1.9 * 84 { break }
        }
        if let world = maze.world {
            result.x = min(max(result.x, 42), world.width - 42)
            result.y = min(max(result.y, 42), world.height - 42)
        }
        return result
    }

    private func respawn(_ index: Int) {
        let old = snapshot.tanks[index]
        let origin = old.bot ? snapshot.tanks[0] : old
        let point = respawnLocation?(old) ?? spawnPoint(near: origin, minCells: 2, maxCells: 5)
        snapshot.tanks[index] = ArenaTank(id: old.id, name: old.name, x: point.x, y: point.y,
                                         angle: unitRandom() * 2 * .pi - .pi, colorIndex: old.colorIndex,
                                         score: old.score, team: old.team, bot: old.bot, spawnProtected: true,
                                         spawnSerial: old.spawnSerial + 1, invulnerable: maze.world == nil ? 1 : 1.2,
                                         survivalEnemy: old.survivalEnemy, survivalBoss: old.survivalBoss, difficulty: old.difficulty)
        fireBlocked.remove(old.id)
        botCourses.removeValue(forKey: old.id)
        nextBoostEffects.removeValue(forKey: old.id)
    }

    private func advanceEquipment(_ index: Int, dt: Double) {
        var tank = snapshot.tanks[index]
        tank.invulnerable = max(0, tank.invulnerable - dt)
        if tank.invulnerable < 1e-9 { tank.invulnerable = 0; tank.spawnProtected = false }
        tank.protected = tank.invulnerable > 0
        tank.shield = max(0, tank.shield - dt)
        if tank.shield < 1e-9 { tank.shield = 0; tank.shieldCharges = 0 }
        tank.starmanTime = max(0, tank.starmanTime - dt)
        if tank.starmanTime <= 0 {
            tank.powerTime = max(0, tank.powerTime - dt)
            if tank.powerTime < 1e-9 { tank.powerTime = 0; tank.power = ""; tank.charges = 0; tank.machineRounds = 0 }
        }
        tank.cooldown = max(0, tank.cooldown - dt)
        tank.recoil = max(0, tank.recoil - 9 * dt)
        snapshot.tanks[index] = tank
    }

    private func populatePickups(dt: Double) {
        for index in snapshot.pickups.indices { snapshot.pickups[index].life -= dt; snapshot.pickups[index].age += dt }
        snapshot.pickups.removeAll { $0.life <= 0 }
        if maze.world != nil {
            guard time >= nextPickup, pickupRate != "off" else { return }
            let range: (Double, Double) = pickupRate == "superfast" ? (1, 2) : pickupRate == "fast" ? (2, 3.5) : pickupRate == "slow" ? (7, 10) : (4, 6)
            nextPickup = time + range.0 + unitRandom() * (range.1 - range.0)
            spawnFixedPickup()
            return
        }
        guard pickupRate != "off", !enabledPickups.isEmpty else { return }
        guard time >= nextPickup else { return }
        nextPickup = time + 1.25 + unitRandom() * 1.25
        let pilot = snapshot.tanks[0]
        guard pilot.hp > 0 else { return }
        snapshot.pickups.removeAll { hypot($0.x - pilot.x, $0.y - pilot.y) > 11 * 84 }
        var nearby = snapshot.pickups.filter { hypot($0.x - pilot.x, $0.y - pilot.y) < 5 * 84 }.count
        for _ in 0..<90 {
            guard nearby < 3, snapshot.pickups.count < 6 else { break }
            let dx = random(7) - 3, dy = random(7) - 3
            guard dx * dx + dy * dy <= 12 else { continue }
            let x = (floor(pilot.x / 84) + Double(dx) + 0.5) * 84
            let y = (floor(pilot.y / 84) + Double(dy) + 0.5) * 84
            guard !snapshot.tanks.contains(where: { $0.hp > 0 && hypot($0.x - x, $0.y - y) < 0.85 * 84 }),
                  !snapshot.pickups.contains(where: { hypot($0.x - x, $0.y - y) < 1.1 * 84 }) else { continue }
            let weighted = enabledPickups.flatMap { kind in Array(repeating: kind, count: kind == "shield" || kind == "speed" ? 6 : kind == "starman" ? 1 : 2) }
            nextID += 1
            snapshot.pickups.append(ArenaPickup(id: nextID, x: x, y: y, type: weighted[random(weighted.count)]))
            nearby += 1
        }
    }

    func seedFixedPickups(count: Int) { for _ in 0..<count { spawnFixedPickup() } }

    private func spawnFixedPickup() {
        guard let world = maze.world, pickupRate != "off", !enabledPickups.isEmpty else { return }
        let area = world.cols * world.rows, cap = Int((Double(area) / 9.8).rounded())
        guard snapshot.pickups.count < cap else { return }
        for _ in 0..<60 {
            let x = (Double(random(world.cols)) + 0.5) * 84, y = (Double(random(world.rows)) + 0.5) * 84
            guard !snapshot.tanks.contains(where: { $0.hp > 0 && hypot($0.x - x, $0.y - y) < 0.85 * 84 }),
                  !snapshot.pickups.contains(where: { hypot($0.x - x, $0.y - y) < 1.1 * 84 }) else { continue }
            let weighted = enabledPickups.flatMap { Array(repeating: $0, count: $0 == "shield" || $0 == "speed" ? 6 : $0 == "starman" ? 1 : 2) }
            nextID += 1
            let life = max(area <= 120 ? 30 : 0, cap * 8 / 3)
            snapshot.pickups.append(ArenaPickup(id: nextID, x: x, y: y, type: weighted[random(weighted.count)], life: Double(life)))
            return
        }
    }

    private func collectPickups(_ index: Int) {
        for pickupIndex in snapshot.pickups.indices {
            let pickup = snapshot.pickups[pickupIndex], tank = snapshot.tanks[index]
            guard pickup.life > 0, hypot(pickup.x - tank.x, pickup.y - tank.y) < 30 else { continue }
            snapshot.pickups[pickupIndex].life = 0
            Self.applyPower(tank: &snapshot.tanks[index], kind: pickup.type, duration: powerDuration, starDuration: starDuration)
            // Bots may collect a grenade while holding ordinary Fire. Create
            // a fresh throw edge, as in the Go and browser offline simulation.
            if tank.bot && pickup.type == "grenade" { held[tank.id] = false }
            effect("pickup", x: tank.x, y: tank.y, owner: tank.id)
        }
    }

    static func applyPower(tank: inout ArenaTank, kind: String, duration: Double = 15, starDuration: Double = 8) {
        switch kind {
        case "shield": tank.shieldCharges = min(5, (tank.shield > 0 ? max(1, tank.shieldCharges) : 0) + 1); tank.shield = duration
        case "speed": tank.speedStacks = min(5, (tank.speedTime > 0 ? max(1, tank.speedStacks) : 0) + 1); tank.speedTime = duration
        case "ghost": tank.ghostTime = duration
        case "starman":
            tank.starmanTime = starDuration; tank.spawnProtected = false; tank.invulnerable = max(tank.invulnerable, starDuration)
            tank.ghostTime = max(tank.ghostTime, starDuration); tank.cooldown = 0; tank.cooldownTotal = 0
        case "rapid", "scatter", "homing", "grenade", "laser", "cannon":
            tank.power = kind; tank.powerTime = duration
            tank.charges = kind == "rapid" || kind == "scatter" ? 5 : 3
            tank.machineRounds = kind == "rapid" ? 180 : 0
            if kind == "rapid" { tank.cooldown = 0; tank.cooldownTotal = 0 }
        default: break
        }
    }

    private func effect(_ kind: String, x: Double, y: Double, owner: Int, points: [BeamPoint] = []) {
        nextEffect += 1
        snapshot.effects.append(ArenaEffect(id: nextEffect, kind: kind, x: x, y: y, owner: owner, points: points))
        effectTimes[nextEffect] = time
        if snapshot.effects.count > 48 { snapshot.effects.removeFirst() }
    }

    private func botInput(_ index: Int) -> GameInput {
        let bot = snapshot.tanks[index]
        let targets = maze.world == nil && bot.team == 0 ? [snapshot.tanks[0]] : snapshot.tanks
        guard let pilot = targets.filter({ $0.hp > 0 && opposes(owner: bot.id, target: $0) })
            .min(by: { hypot($0.x - bot.x, $0.y - bot.y) < hypot($1.x - bot.x, $1.y - bot.y) }) else { return GameInput() }
        if maze.world == nil && roamingIDs.contains(bot.id) && hypot(bot.x - pilot.x, bot.y - pilot.y) > 10 * 84 {
            let point = spawnPoint(near: pilot, minCells: 3, maxCells: 5)
            snapshot.tanks[index].x = point.x; snapshot.tanks[index].y = point.y
            botCourses.removeValue(forKey: bot.id)
            return GameInput()
        }
        let level = bot.difficulty.isEmpty ? botDifficulty : bot.difficulty
        let tuning: (range: Double, roam: Double, aim: Double) = level == "easy" ? (0.7, 0.75, 1.65) : level == "hard" ? (1.15, 1.15, 0.7) : level == "godlike" ? (1.3, 1.3, 0.45) : (1, 1, 1)
        let dx = pilot.x - bot.x, dy = pilot.y - bot.y, distance = hypot(dx, dy)
        let seesPilot = distance < 6 * 84 * tuning.range && maze.rayHit(x: bot.x, y: bot.y, dx: dx, dy: dy, radius: 3.5) == nil
        let goal = botGoal?(bot), routingObjective = goal != nil && (!seesPilot || distance > 168)
        if (!seesPilot || routingObjective) && time >= (botDecisions[bot.id] ?? 0) {
            var target = pilot
            if let goal, routingObjective { target.x = goal.x; target.y = goal.y }
            botCourses[bot.id] = botCourse(bot: bot, target: target)
            botDecisions[bot.id] = time + (maze.world == nil ? (0.25 + unitRandom() * 0.25) / tuning.roam : (BotDifficulty(rawValue: level) ?? .normal).think)
        }
        let tx = seesPilot && !routingObjective ? dx : (botCourses[bot.id]?.x ?? goal?.x ?? bot.x) - bot.x
        let ty = seesPilot && !routingObjective ? dy : (botCourses[bot.id]?.y ?? goal?.y ?? bot.y) - bot.y
        let aim = atan2(ty, tx)
        let shotAim = atan2(dy, dx)
        let tilt = maze.world == nil ? tuning.roam : 1
        return GameInput(fire: seesPilot && pilot.invulnerable == 0 && abs(atan2(sin(shotAim - bot.angle), cos(shotAim - bot.angle))) < 0.16 * tuning.aim,
                         stickX: cos(aim) * tilt, stickY: sin(aim) * tilt, touchAim: false,
                         aimOnly: hypot(tx, ty) < 5 || seesPilot && distance < 115)
    }

    private func botCourse(bot: ArenaTank, target: ArenaTank) -> (x: Double, y: Double)? {
        struct Cell: Hashable { var x: Int; var y: Int }
        struct Visit { var cell: Cell; var step: Cell? }
        let start = Cell(x: Int(floor(bot.x / 84)), y: Int(floor(bot.y / 84)))
        let goal = Cell(x: Int(floor(target.x / 84)), y: Int(floor(target.y / 84)))
        var visited: Set<Cell> = [start], queue = [Visit(cell: start, step: nil)]
        var best = Int.max, nearest: Cell?, head = 0
        while head < queue.count {
            let visit = queue[head]; head += 1
            if visit.step != nil {
                let distance = (visit.cell.x - goal.x) * (visit.cell.x - goal.x) + (visit.cell.y - goal.y) * (visit.cell.y - goal.y)
                if distance < best { best = distance; nearest = visit.step }
                if distance == 0 { break }
            }
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let cell = Cell(x: visit.cell.x + dx, y: visit.cell.y + dy)
                let reach = maze.world.map { max($0.cols, $0.rows) } ?? 4
                guard abs(cell.x - start.x) <= reach, abs(cell.y - start.y) <= reach, !visited.contains(cell),
                      !maze.blocked(x: (Double(visit.cell.x) + 0.5 + Double(dx) / 2) * 84,
                                    y: (Double(visit.cell.y) + 0.5 + Double(dy) / 2) * 84, radius: 17) else { continue }
                visited.insert(cell); queue.append(Visit(cell: cell, step: visit.step ?? cell))
            }
        }
        return nearest.map { ((Double($0.x) + 0.5) * 84, (Double($0.y) + 0.5) * 84) }
    }

    private static func spec(_ kind: String) -> (speed: Double, radius: Double, life: Double, cooldown: Double, capacity: Int) {
        switch kind {
        case "rapid": return (846, 3.5 / 3, 18 * 84 / 846, 0, 115)
        case "scatter": return (846, 3.5, 3.9, 0.54, 12)
        case "homing": return (235, 5, 18 * 84 / 235, 0.72, 3)
        case "grenade": return (205, 6, 10, 0.8, 3)
        case "cannon": return (1128, 14, 5.3, 0.85, 3)
        case "laser": return (0, 3, 0, 0.85, 3)
        default: return (282, 3.5, 5.3, 0.34, 5)
        }
    }

    static func grenadeDragFactor(lifeBefore: Double, lifeAfter: Double) -> Double {
        func integral(_ life: Double) -> Double {
            let age = 10 - min(max(life, 0), 10), brakingAge = max(0, age - 7)
            return 0.025 * age + 2 * brakingAge * brakingAge * brakingAge / 27
        }
        return exp(-(integral(lifeAfter) - integral(lifeBefore)))
    }

    private func weaponControl(_ index: Int, fire: Bool) {
        let tank = snapshot.tanks[index], pressed = fire && held[tank.id] != true
        held[tank.id] = fire
        if !fire { fireBlocked.remove(tank.id) }
        guard tank.hp > 0, !(tank.spawnProtected && tank.invulnerable > 1e-9) else { return }
        if pressed {
            let grenades = projectiles.filter { $0.wire.owner == tank.id && $0.wire.kind == "grenade" }
            if !grenades.isEmpty {
                for grenade in grenades { detonate(grenade.wire) }
                projectiles.removeAll { $0.wire.owner == tank.id && $0.wire.kind == "grenade" }
                fireBlocked.insert(tank.id)
                return
            }
            if tank.power == "grenade" { fireBlocked.insert(tank.id); fireShot(index); return }
        }
        if fire && !fireBlocked.contains(tank.id) && tank.power != "grenade" { fireShot(index) }
    }

    private func fireShot(_ index: Int) {
        let tank = snapshot.tanks[index], boosted = tank.starmanTime > 0
        var spec = Self.spec(tank.power)
        if let world = maze.world {
            if tank.power == "rapid" { spec.life = max(0, (world.width + world.height) / 2 - 28) / spec.speed }
            if tank.power == "homing" { spec.life = (world.width + world.height) / spec.speed + 0.5 }
        }
        guard tank.hp > 0, !(tank.spawnProtected && tank.invulnerable > 1e-9),
              boosted || tank.cooldown <= 1e-9 && (tank.power != "rapid" || tank.machineRounds > 0) else { return }
        let offsets: [Double] = tank.power == "scatter" ? [-0.21, 0, 0.21] : [0]
        var ordinary = 0
        for index in projectiles.indices where projectiles[index].wire.owner == tank.id && !projectiles[index].boosted { ordinary += 1 }
        guard boosted || tank.power == "laser" || ordinary + offsets.count <= spec.capacity else { return }
        let cooldown = boosted ? 0 : spec.cooldown
        snapshot.tanks[index].cooldown = cooldown; snapshot.tanks[index].cooldownTotal = cooldown; snapshot.tanks[index].recoil = 1
        if tank.power == "laser" { fireLaser(tank) }
        else {
            for offset in offsets {
                let angle = tank.angle + offset
                guard let launch = maze.launchRay(x: tank.x, y: tank.y, angle: angle, kind: tank.power, radius: spec.radius) else {
                    effect("impact", x: tank.x, y: tank.y, owner: tank.id)
                    continue
                }
                nextID += 1
                var projectile = Projectile(wire: ArenaBullet(id: nextID, x: launch.x, y: launch.y,
                                                             vx: launch.ux * spec.speed, vy: launch.uy * spec.speed,
                                                             owner: tank.id, kind: tank.power, colorIndex: tank.colorIndex, life: spec.life), boosted: boosted)
                if let world = maze.world, tank.power == "homing" { projectile.rangeLeft = world.width + world.height }
                if launch.bounced {
                    projectile.wire.bounces = 1
                    projectile.seekDelay = 0.04
                    if projectile.rangeLeft != nil { projectile.rangeLeft! -= launch.distance }
                }
                let muzzle = max(0, (tank.power == "cannon" ? 32 : 28) - launch.distance)
                if advance(&projectile, dt: muzzle / spec.speed) { projectiles.append(projectile) }
            }
            if !boosted || tank.power == "grenade" || time + 1e-9 >= (nextBoostEffects[tank.id] ?? 0) {
                nextBoostEffects[tank.id] = time + 4 / 60
                effect("shot:" + tank.power, x: tank.x, y: tank.y, owner: tank.id)
            }
            var remaining = max(0, 115 - (boosted ? 0 : ordinary + offsets.count))
            for i in projectiles.indices.reversed() where projectiles[i].wire.owner == tank.id && (boosted || projectiles[i].boosted) {
                if remaining > 0 { remaining -= 1 } else { projectiles[i].wire.life = 0 }
            }
            projectiles.removeAll { $0.wire.life <= 0 }
        }
        guard !boosted, !tank.power.isEmpty else { return }
        if tank.power == "rapid" { snapshot.tanks[index].machineRounds -= 1 }
        else { snapshot.tanks[index].charges -= 1 }
        if tank.power == "rapid" ? snapshot.tanks[index].machineRounds <= 0 : snapshot.tanks[index].charges <= 0 {
            snapshot.tanks[index].power = ""; snapshot.tanks[index].powerTime = 0; snapshot.tanks[index].charges = 0
        }
    }

    private func targetHit(owner: Int, x: Double, y: Double, dx: Double, dy: Double,
                           radius: Double, limit: Double, contact: Bool = false) -> (index: Int, fraction: Double)? {
        var best = limit, target: Int?
        let ownerTeam = team(of: owner)
        for i in snapshot.tanks.indices {
            guard snapshot.tanks[i].hp > 0, snapshot.tanks[i].id != owner,
                  contact || (friendlyFire || ownerTeam == 0 || ownerTeam != snapshot.tanks[i].team) && snapshot.tanks[i].invulnerable <= 0 else { continue }
            if let fraction = Self.circleHit(x: x, y: y, dx: dx, dy: dy,
                                             tx: snapshot.tanks[i].x, ty: snapshot.tanks[i].y, radius: 17 + radius), fraction < best {
                best = fraction; target = i
            }
        }
        return target.map { ($0, best) }
    }

    private static func circleHit(x: Double, y: Double, dx: Double, dy: Double, tx: Double, ty: Double, radius: Double) -> Double? {
        let ox = x - tx, oy = y - ty, c = ox * ox + oy * oy - radius * radius
        if c <= 0 { return 0 }
        let a = dx * dx + dy * dy
        guard a >= 1e-12 else { return nil }
        let b = 2 * (ox * dx + oy * dy), discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return nil }
        let fraction = (-b - sqrt(discriminant)) / (2 * a)
        return fraction >= 0 && fraction <= 1 ? fraction : nil
    }

    private func advance(_ projectile: inout Projectile, dt: Double) -> Bool {
        var dx = projectile.wire.vx * dt, dy = projectile.wire.vy * dt
        for _ in 0..<4 {
            let bullet = projectile.wire
            let wall = maze.projectileHit(kind: bullet.kind, x: bullet.x, y: bullet.y, dx: dx, dy: dy, radius: projectile.radius)
            if let target = targetHit(owner: bullet.owner, x: bullet.x, y: bullet.y, dx: dx, dy: dy,
                                      radius: projectile.radius, limit: wall?.fraction ?? 1.00000001, contact: bullet.kind == "grenade") {
                projectile.wire.x += dx * target.fraction; projectile.wire.y += dy * target.fraction
                if projectile.rangeLeft != nil { projectile.rangeLeft! -= hypot(dx, dy) * target.fraction }
                if bullet.kind == "grenade" { detonate(projectile.wire) }
                else {
                    if bullet.kind == "homing" || bullet.kind == "cannon" {
                        effect("impact", x: projectile.wire.x, y: projectile.wire.y, owner: bullet.owner)
                    }
                    hurt(target.index, owner: bullet.owner)
                }
                return false
            }
            guard let wall else {
                projectile.wire.x += dx; projectile.wire.y += dy
                if projectile.rangeLeft != nil { projectile.rangeLeft! -= hypot(dx, dy) }
                return true
            }
            projectile.wire.bounces += 1
            let limit = ["homing", "rapid", "grenade"].contains(bullet.kind) ? 128 : 22
            if projectile.wire.bounces > limit {
                if bullet.kind == "grenade" { detonate(projectile.wire) }
                return false
            }
            projectile.wire.x += dx * wall.fraction + wall.nx * 0.12
            projectile.wire.y += dy * wall.fraction + wall.ny * 0.12
            if projectile.rangeLeft != nil { projectile.rangeLeft! -= hypot(dx, dy) * wall.fraction }
            dx *= 1 - wall.fraction; dy *= 1 - wall.fraction
            if wall.nx != 0 { dx = -dx; projectile.wire.vx = -projectile.wire.vx }
            if wall.ny != 0 { dy = -dy; projectile.wire.vy = -projectile.wire.vy }
            projectile.wire.target = 0; projectile.seekDelay = 0.04
            if wall.fraction == 1 { return true }
        }
        return true
    }

    private func guide(_ projectile: inout Projectile, dt: Double) {
        projectile.seekDelay = max(0, projectile.seekDelay - dt)
        guard projectile.age >= 0.1, projectile.seekDelay == 0 else { return }
        let bullet = projectile.wire, speed = hypot(bullet.vx, bullet.vy)
        var closest = 10.0 * 84, target: Int?
        let ownerTeam = team(of: bullet.owner)
        for index in snapshot.tanks.indices {
            guard snapshot.tanks[index].id != bullet.owner,
                  ownerTeam == 0 || ownerTeam != snapshot.tanks[index].team,
                  snapshot.tanks[index].hp > 0, snapshot.tanks[index].invulnerable == 0,
                  bullet.target == 0 || bullet.target == snapshot.tanks[index].id else { continue }
            let dx = snapshot.tanks[index].x - bullet.x, dy = snapshot.tanks[index].y - bullet.y, distance = hypot(dx, dy)
            guard distance < closest, dx * bullet.vx + dy * bullet.vy >= -0.75 * distance * speed,
                  maze.rayHit(x: bullet.x, y: bullet.y, dx: dx, dy: dy, radius: projectile.radius) == nil else { continue }
            target = index; closest = distance
        }
        guard let target else {
            if projectile.wire.target != 0 { projectile.seekDelay = 0.06 }
            projectile.wire.target = 0
            return
        }
        projectile.wire.target = snapshot.tanks[target].id
        let angle = atan2(bullet.vy, bullet.vx), desired = atan2(snapshot.tanks[target].y - bullet.y, snapshot.tanks[target].x - bullet.x)
        let turn = min(max(atan2(sin(desired - angle), cos(desired - angle)), -4.8 * dt), 4.8 * dt)
        projectile.wire.vx = cos(angle + turn) * speed; projectile.wire.vy = sin(angle + turn) * speed
    }

    private func fireLaser(_ tank: ArenaTank) {
        guard let launch = maze.launchRay(x: tank.x, y: tank.y, angle: tank.angle, kind: "laser", radius: 3) else {
            effect("impact", x: tank.x, y: tank.y, owner: tank.id)
            return
        }
        var x = launch.x, y = launch.y, ux = launch.ux, uy = launch.uy
        var remaining = max(0, (maze.world.map { 2 * ($0.width + $0.height) } ?? 18 * 84) - launch.distance)
        var points: [BeamPoint] = []
        var hitTarget: Int?
        for index in 0..<128 {
            let dx = ux * remaining, dy = uy * remaining
            let wall = maze.rayHit(x: x, y: y, dx: dx, dy: dy, radius: 3)
            let target = targetHit(owner: tank.id, x: x, y: y, dx: dx, dy: dy, radius: 3, limit: wall?.fraction ?? 1.00000001)
            let length = remaining * (target?.fraction ?? wall?.fraction ?? 1)
            if index == 0 {
                let crop = launch.bounced ? 0 : 28.0
                points.append(BeamPoint(x: x + ux * min(crop, length), y: y + uy * min(crop, length)))
            }
            x += ux * length; y += uy * length; remaining -= length
            points.append(BeamPoint(x: x, y: y))
            if let target { hitTarget = target.index; break }
            guard let wall, remaining > 1e-7 else { break }
            if wall.nx != 0 { ux = -ux }; if wall.ny != 0 { uy = -uy }
            let nudge = min(0.001, remaining)
            x += ux * nudge; y += uy * nudge; remaining -= nudge
        }
        // Damage remains at the physics rate. Sustained misses share the web
        // and server's cosmetic cadence; finite hits still show their beam
        // immediately, before the resulting shield or death effect.
        if tank.starmanTime <= 0 || time + 1e-9 >= (nextBoostEffects[tank.id] ?? 0) || maze.world != nil && hitTarget != nil {
            nextBoostEffects[tank.id] = time + 4 / 60
            effect("laser", x: tank.x, y: tank.y, owner: tank.id, points: points)
        }
        if let hitTarget { hurt(hitTarget, owner: tank.id) }
    }

    private func detonate(_ bullet: ArenaBullet) {
        effect("blast", x: bullet.x, y: bullet.y, owner: bullet.owner)
        for index in snapshot.tanks.indices {
            let tank = snapshot.tanks[index]
            guard tank.id != bullet.owner, tank.hp > 0, tank.invulnerable == 0, hypot(tank.x - bullet.x, tank.y - bullet.y) <= 237,
                  maze.rayHit(x: bullet.x, y: bullet.y, dx: tank.x - bullet.x, dy: tank.y - bullet.y, radius: 0) == nil else { continue }
            hurt(index, owner: bullet.owner)
        }
    }

    private func hurt(_ index: Int, owner: Int, starman: Bool = false) {
        let tank = snapshot.tanks[index]
        guard canDamage(owner: owner, target: tank), tank.hp > 0, starman || tank.invulnerable == 0 else { return }
        if !starman && tank.shield > 0 {
            snapshot.tanks[index].shieldCharges = max(1, tank.shieldCharges) - 1
            if snapshot.tanks[index].shieldCharges == 0 { snapshot.tanks[index].shield = 0 }
            snapshot.tanks[index].invulnerable = 0.35; snapshot.tanks[index].spawnProtected = false
            effect("shield", x: tank.x, y: tank.y, owner: owner)
            return
        }
        snapshot.tanks[index].hp = 0
        if killScoring { snapshot.tanks[index].score -= 1 }
        snapshot.tanks[index].respawnTime = respawnsEnabled ? respawnDelay : 0
        if let shooter = snapshot.tanks.firstIndex(where: { $0.id == owner }) {
            if killScoring { snapshot.tanks[shooter].score += 1 }
            snapshot.tanks[index].killedBy = snapshot.tanks[shooter].name
            snapshot.tanks[index].killedByColor = GamePalette.colors[snapshot.tanks[shooter].colorIndex]
        }
        effect("hit", x: tank.x, y: tank.y, owner: owner)
    }

    private func opposes(owner: Int, target: ArenaTank) -> Bool {
        guard owner != target.id else { return false }
        let team = team(of: owner)
        return team == 0 || team != target.team
    }

    private func team(of id: Int) -> Int {
        for index in snapshot.tanks.indices where snapshot.tanks[index].id == id { return snapshot.tanks[index].team }
        return 0
    }

    private func canDamage(owner: Int, target: ArenaTank) -> Bool { owner != target.id && (friendlyFire || opposes(owner: owner, target: target)) }

    private func starmanContacts() {
        for attacker in snapshot.tanks where attacker.hp > 0 && attacker.starmanTime > 0 {
            for index in snapshot.tanks.indices {
                let tank = snapshot.tanks[index]
                guard tank.hp > 0, tank.id != attacker.id, tank.starmanTime == 0,
                      tank.invulnerable == 0 || tank.spawnProtected,
                      hypot(tank.x - attacker.x, tank.y - attacker.y) <= 34,
                      !maze.segmentBlocked(x: attacker.x, y: attacker.y, dx: tank.x - attacker.x, dy: tank.y - attacker.y) else { continue }
                hurt(index, owner: attacker.id, starman: true)
            }
        }
    }

    private func updateStandings() {
        struct OwnedProjectiles { var ammo = 0; var grenades = 0; var grenadeLife = 0.0; var locked = false }
        var owned = [OwnedProjectiles](repeating: OwnedProjectiles(), count: snapshot.tanks.count)
        var tankIndices: [Int: Int] = [:]
        for index in snapshot.tanks.indices { tankIndices[snapshot.tanks[index].id] = index }
        var boosted: [Int] = []
        boosted.reserveCapacity(projectiles.count)
        // Ammo, fuses, and locks all describe this same projectile population.
        // Preserve projectile order while calculating them in one pass.
        for index in projectiles.indices {
            let owner = projectiles[index].wire.owner
            if projectiles[index].boosted { boosted.append(projectiles[index].wire.id) }
            if let ownerIndex = tankIndices[owner] {
                if !projectiles[index].boosted { owned[ownerIndex].ammo += 1 }
                if projectiles[index].wire.kind == "grenade" {
                    owned[ownerIndex].grenades += 1
                    owned[ownerIndex].grenadeLife = max(owned[ownerIndex].grenadeLife, projectiles[index].wire.life)
                }
            }
            if let target = tankIndices[projectiles[index].wire.target], owner != snapshot.tanks[target].id {
                let ownerTeam = tankIndices[owner].map { snapshot.tanks[$0].team } ?? 0
                if friendlyFire || ownerTeam == 0 || ownerTeam != snapshot.tanks[target].team { owned[target].locked = true }
            }
        }
        snapshot.boostedBulletIds = boosted
        let sorted = snapshot.tanks.sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
        snapshot.leaderboard = sorted.prefix(10).map { LeaderboardEntry(id: $0.id, name: $0.name, score: $0.score, colorIndex: $0.colorIndex, bot: $0.bot, team: $0.team) }
        snapshot.tankCount = snapshot.tanks.count
        snapshot.teamScores = (1...4).map { team in snapshot.tanks.filter { $0.team == team }.map(\.score).reduce(0, +) }
        for index in snapshot.tanks.indices {
            snapshot.tanks[index].rank = (sorted.firstIndex(where: { $0.id == snapshot.tanks[index].id }) ?? 0) + 1
            snapshot.tanks[index].ammoUsed = owned[index].ammo
            snapshot.tanks[index].grenades = owned[index].grenades
            snapshot.tanks[index].grenadeLife = owned[index].grenadeLife
            snapshot.tanks[index].locked = owned[index].locked
        }
        if maze.world == nil, let rules = activeRules, rules.infinityTarget > 0, snapshot.result == nil {
            if rules.teamMode == "teams", let winner = snapshot.teamScores.firstIndex(where: { $0 >= rules.infinityTarget }) {
                snapshot.result = ArenaResult(name: rules.teamNames.indices.contains(winner) ? rules.teamNames[winner] : "Team \(winner + 1)", team: winner + 1, score: snapshot.teamScores[winner])
            } else if rules.teamMode != "teams", let winner = sorted.first(where: { $0.score >= rules.infinityTarget }) {
                snapshot.result = ArenaResult(id: winner.id, name: winner.name, score: winner.score)
            }
        }
    }
}
