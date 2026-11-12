import Foundation

/// Offline finite-maze matches. Combat uses the same native engine as Infinity;
/// this owner applies rounds, objectives, team points, and Survival boundaries.
public final class FixedArena {
    public let localID = 1
    public private(set) var world: ArenaWorld
    public private(set) var rules: RoomRules
    var combat: PracticeArena
    private let name: String
    private let colorIndex: Int
    private let botCount: Int
    private let difficulty: String
    private let botNames: [String]
    private let botColors: [Int]
    private let botDifficulties: [String]
    private let botTeams: [Int]
    private let localTeam: Int
    private struct PilotConfiguration { var name: String; var colorIndex: Int; var team: Int; var difficulty: String }
    private var pilotConfigurations: [Int: PilotConfiguration] = [:]
    private var randomState: UInt32
    private var tick: UInt64 = 0
    private var generation = 0
    private var phase = "countdown"
    private var phaseTime = 3.0
    private var round = 1
    private var clock = 75.0
    private var winner = -1
    private var scores: [Int: Int] = [:]
    var objectives: ArenaObjectives?

    public init(rules: RoomRules, name: String, colorIndex: Int, botCount: Int = 3,
                difficulty: String = "normal", seed: UInt32,
                botNames: [String] = [], botColors: [Int] = [], botDifficulties: [String] = [],
                botTeams: [Int] = [], localTeam: Int = 0) {
        self.rules = rules; self.rules.infinity = false
        if rules.mode == "ctf" || rules.mode == "survival" { self.rules.teamMode = "teams" }
        self.name = name; self.colorIndex = GamePalette.index(colorIndex)
        self.botCount = max(0, min(rules.mode == "survival" ? 3 : 7, botCount))
        self.difficulty = difficulty
        self.botNames = botNames; self.botColors = botColors; self.botDifficulties = botDifficulties
        self.botTeams = botTeams; self.localTeam = localTeam
        randomState = seed == 0 ? 1 : seed
        world = ArenaWorld()
        combat = PracticeArena(seed: seed, name: name, colorIndex: colorIndex, botCount: 0)
        startRound(wave: 1, cleared: 0)
    }

    public var snapshot: ArenaSnapshot { compose(combat.snapshot) }

    public func restart() {
        tick = 0; round = 1; winner = -1; scores.removeAll()
        startRound(wave: 1, cleared: 0)
    }

    public var canRestartWave: Bool {
        guard let survival = objectives?.survival else { return false }
        return survival.status == "wave" && (phase == "playing" || phase == "countdown")
            || survival.status == "lost" && phase == "matchOver"
    }

    /// Restarting an active or failed Survival wave retains its maze and all
    /// previously cleared waves, matching the server's restart_wave command.
    public func restartWave() {
        guard canRestartWave, let survival = objectives?.survival else { return }
        round = survival.wave; winner = -1
        startRound(wave: survival.wave, cleared: survival.wavesCleared, preserveWorld: true)
    }

    public func step(input: GameInput, dt: Double) {
        guard dt.isFinite, dt > 0, dt <= 0.1 else { return }
        tick += 1
        if phase == "matchOver" { return }
        if phase == "countdown" {
            phaseTime = max(0, phaseTime - dt)
            if phaseTime <= 1e-9 { phaseTime = 0; phase = "playing" }
            return
        }
        if phase == "roundOver" {
            phaseTime = max(0, phaseTime - dt)
            if phaseTime <= 1e-9 {
                if winner >= 0 && (scores[winner] ?? 0) >= rules.scoreTarget { phase = "matchOver" }
                else { round += 1; startRound(wave: 1, cleared: 0) }
            }
            return
        }
        if var survival = objectives?.survival, survival.status == "break" {
            survival.breakTime = max(0, survival.breakTime - dt)
            objectives?.survival = survival
            if survival.breakTime <= 1e-9 { round += 1; startRound(wave: survival.wave + 1, cleared: survival.wavesCleared) }
            return
        }
        clock = max(0, clock - dt)
        combat.step(input: input, dt: dt)
        // Combat kills do not award points in finite modes.
        restoreScores()
        if rules.mode == "survival" { stepSurvival() }
        else if rules.mode == "ctf" || rules.mode == "koth" { stepObjectives(dt: dt) }
        else { stepElimination() }
        combat.refreshStandings()
    }

    public func presentationSnapshot(fraction: Double, localInput: GameInput? = nil) -> ArenaSnapshot {
        let active = phase == "playing" && objectives?.survival?.status != "break"
        return compose(active ? combat.presentationSnapshot(fraction: fraction, localInput: localInput) : combat.snapshot)
    }

    public func configurePilot(id: Int, name: String, colorIndex: Int, team: Int = 0, difficulty: String = "normal") {
        let current = combat.snapshot.tanks.first { $0.id == id }
        let team = rules.mode == "survival" ? 1 : rules.teamMode == "teams" ? (team > 0 ? team : current?.team ?? 1) : 0
        let paint = team > 0 ? rules.teamColors[safe: team - 1] ?? team - 1 : colorIndex
        pilotConfigurations[id] = PilotConfiguration(name: name, colorIndex: colorIndex, team: team, difficulty: difficulty)
        combat.configurePilot(id: id, name: name, colorIndex: paint, team: team, difficulty: difficulty)
    }

    private func compose(_ original: ArenaSnapshot) -> ArenaSnapshot {
        var value = original
        value.tick = tick; value.generation = generation; value.world = world
        value.phase = phase; value.phaseTime = phaseTime; value.round = round; value.roundClock = clock
        value.winner = winner; value.objectives = objectives
        value.rules = rules
        let count = max(9, (value.tanks.map(\.id).max() ?? 0) + 1)
        value.scores = (0..<count).map { scores[$0] ?? 0 }
        for index in value.tanks.indices { value.tanks[index].score = scores[value.tanks[index].id] ?? 0 }
        value.leaderboard = value.tanks.filter { !$0.survivalEnemy }.sorted {
            $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score
        }.map { LeaderboardEntry(id: $0.id, name: $0.name, score: $0.score, colorIndex: $0.colorIndex, bot: $0.bot, team: $0.team) }
        value.teamScores = (1...4).map { team in value.tanks.filter { $0.team == team }.map(\.score).max() ?? 0 }
        return value
    }

    private func random(_ max: Int) -> Int {
        randomState ^= randomState << 13; randomState ^= randomState >> 17; randomState ^= randomState << 5
        return Int(randomState % UInt32(max))
    }

    private func startRound(wave: Int, cleared: Int, preserveWorld: Bool = false) {
        generation += 1; winner = -1; phase = "countdown"; phaseTime = 3; clock = Double(rules.timeLimit)
        if !preserveWorld { world = makeWorld() }
        combat = PracticeArena(seed: randomState, name: name, colorIndex: colorIndex, botCount: botCount,
                               difficulty: difficulty, world: world)
        combat.configure(rules: rules)
        combat.killScoring = false
        combat.respawnsEnabled = rules.mode == "ctf" || rules.mode == "koth"
        combat.respawnDelay = Double(rules.respawnSeconds)
        let cols = world.cols, rows = world.rows
        let cells = [(0, rows - 1), (cols - 1, 0), (cols - 1, rows - 1), (0, 0),
                     (cols / 2, 0), (cols - 1, rows / 2), (cols / 2, rows - 1), (0, rows / 2)]
        var spots = combat.snapshot.tanks.count <= 4 ? Array(cells.prefix(4)) : cells
        for index in spots.indices.reversed() where index > 0 { spots.swapAt(index, random(index + 1)) }
        for index in combat.snapshot.tanks.indices {
            let id = index + 1, team = rules.mode == "survival" ? 1 : rules.teamMode == "teams"
                ? (index == 0 ? (localTeam > 0 ? localTeam : 1) : (botTeams.indices.contains(index - 1) && botTeams[index - 1] > 0 ? botTeams[index - 1] : index % 2 + 1)) : 0
            let paint = team > 0 ? rules.teamColors[safe: team - 1] ?? (team - 1) : index == 0 ? colorIndex : botColors[safe: index - 1] ?? GamePalette.index(colorIndex + index)
            combat.configurePilot(id: id, name: index == 0 ? name : botNames[safe: index - 1] ?? "BOT \(index)", colorIndex: paint, team: team,
                                  difficulty: index == 0 ? difficulty : botDifficulties[safe: index - 1] ?? difficulty)
            if let configured = pilotConfigurations[id] {
                let team = rules.mode == "survival" ? 1 : configured.team
                let paint = team > 0 ? rules.teamColors[safe: team - 1] ?? team - 1 : configured.colorIndex
                combat.configurePilot(id: id, name: configured.name, colorIndex: paint, team: team, difficulty: configured.difficulty)
            }
            combat.snapshot.tanks[index].x = (Double(spots[index].0) + 0.5) * 84
            combat.snapshot.tanks[index].y = (Double(spots[index].1) + 0.5) * 84
            combat.snapshot.tanks[index].angle = -.pi / 2
            combat.snapshot.tanks[index].spawnSerial = generation
            combat.snapshot.tanks[index].invulnerable = 0.75
        }
        objectives = nil
        if rules.mode == "ctf" {
            let flags = [ArenaFlag(team: 1, homeX: 126, homeY: world.height - 126, x: 126, y: world.height - 126),
                         ArenaFlag(team: 2, homeX: world.width - 126, homeY: 126, x: world.width - 126, y: 126)]
            objectives = ArenaObjectives(mode: "ctf", flags: flags)
        } else if rules.mode == "koth" {
            objectives = ArenaObjectives(mode: "koth", hillX: (Double(cols / 2) + 0.5) * 84,
                                         hillY: (Double(rows / 2) + 0.5) * 84, radius: 32)
        } else if rules.mode == "survival" {
            let count = min(4, 2 + (wave - 1) / 2), boss = wave.isMultiple(of: 5)
            objectives = ArenaObjectives(mode: "survival", survival: ArenaSurvival(wave: wave, wavesCleared: cleared,
                                         waveTarget: rules.scoreTarget, enemiesRemaining: count, boss: boss, status: "wave"))
            for enemy in 0..<count {
                let id = 5 + enemy, point = (x: (Double(cols - 1 - enemy % 2) + 0.5) * 84, y: (Double(enemy / 2) + 0.5) * 84)
                let level = wave <= 5 ? "easy" : wave <= 10 ? "normal" : wave <= 15 ? "hard" : "godlike"
                let isBoss = boss && enemy == 0
                let bossLevel = wave < 10 ? "normal" : wave < 15 ? "hard" : "godlike"
                combat.snapshot.tanks.append(ArenaTank(id: id, name: isBoss ? bossName(wave) : "RAIDER \(enemy + 1)",
                    x: point.x, y: point.y, angle: .pi / 2, colorIndex: rules.teamColors[safe: 1] ?? 1, team: 2, bot: true,
                    spawnProtected: true, spawnSerial: wave, invulnerable: 1.2,
                    survivalEnemy: true, survivalBoss: isBoss, difficulty: isBoss ? bossLevel : level))
                let enemyIndex = combat.snapshot.tanks.count - 1
                let spawn = survivalEnemySpawn(id: id)
                combat.snapshot.tanks[enemyIndex].x = spawn.x; combat.snapshot.tanks[enemyIndex].y = spawn.y
                if isBoss && rules.pickupRate != "off" {
                    let index = combat.snapshot.tanks.count - 1, strength = min(3, max(1, wave / 5))
                    if rules.weapons.contains("shield") { for _ in 0..<strength { PracticeArena.applyPower(tank: &combat.snapshot.tanks[index], kind: "shield", duration: powerDuration) } }
                    if strength >= 2 && rules.weapons.contains("speed") { PracticeArena.applyPower(tank: &combat.snapshot.tanks[index], kind: "speed", duration: powerDuration) }
                    let choices = ["homing", "cannon", "laser"]
                    if let weapon = (0..<3).map({ choices[(wave / 5 - 1 + $0) % 3] }).first(where: { rules.weapons.contains($0) }) {
                        PracticeArena.applyPower(tank: &combat.snapshot.tanks[index], kind: weapon, duration: powerDuration)
                    }
                }
            }
            if boss && rules.weapons.contains("shield") {
                for index in combat.snapshot.tanks.indices where !combat.snapshot.tanks[index].survivalEnemy {
                    PracticeArena.applyPower(tank: &combat.snapshot.tanks[index], kind: "shield", duration: powerDuration)
                }
            }
        }
        combat.respawnLocation = { [weak self] tank in self?.respawnPoint(for: tank) ?? (42, 42) }
        combat.botGoal = { [weak self] tank in self?.objectiveGoal(for: tank) }
        if rules.mode == "ctf" {
            for index in combat.snapshot.tanks.indices {
                let point = respawnPoint(for: combat.snapshot.tanks[index])
                combat.snapshot.tanks[index].x = point.x; combat.snapshot.tanks[index].y = point.y
            }
        }
        let area = cols * rows
        combat.seedFixedPickups(count: 2 + [49, 72, 120, 168, 224].filter { area > $0 }.count)
        restoreScores(); combat.refreshStandings()
    }

    private var powerDuration: Double { world.cols * world.rows >= 168 ? 15 : 10 }

    private func restoreScores() {
        for index in combat.snapshot.tanks.indices { combat.snapshot.tanks[index].score = scores[combat.snapshot.tanks[index].id] ?? 0 }
    }

    private func side(_ tank: ArenaTank) -> Int { tank.team > 0 ? tank.team : -tank.id }

    private func awardPoint(to tank: ArenaTank) {
        let next = (scores[tank.id] ?? 0) + 1
        for pilot in combat.snapshot.tanks where side(pilot) == side(tank) { scores[pilot.id] = next }
        if next >= rules.scoreTarget { winner = tank.id; phase = "matchOver"; combat.clearProjectiles() }
    }

    private func stepElimination() {
        let living = combat.snapshot.tanks.filter { $0.hp > 0 }
        let sides = Set(living.map(side))
        guard sides.count <= 1 || clock <= 0 else { return }
        winner = sides.count == 1 ? living.first!.id : -1
        if winner >= 0, let tank = living.first {
            let next = (scores[tank.id] ?? 0) + 1
            for pilot in combat.snapshot.tanks where side(pilot) == side(tank) { scores[pilot.id] = next }
        }
        phase = "roundOver"; phaseTime = 2; combat.clearProjectiles(); restoreScores()
    }

    private func leader() -> Int {
        let representatives = Dictionary(grouping: combat.snapshot.tanks.filter { !$0.survivalEnemy }, by: side).values.compactMap(\.first)
        let sorted = representatives.sorted { (scores[$0.id] ?? 0) > (scores[$1.id] ?? 0) }
        guard let first = sorted.first else { return -1 }
        if sorted.count > 1 && (scores[first.id] ?? 0) == (scores[sorted[1].id] ?? 0) { return -1 }
        return first.id
    }

    private func stepObjectives(dt: Double) {
        guard var objective = objectives else { return }
        if objective.suddenDeath {
            let living = combat.snapshot.tanks.filter { $0.hp > 0 }, sides = Set(combat.snapshot.tanks.filter { $0.hp > 0 }.map(side))
            if sides.count == 1 { winner = living.first!.id; phase = "matchOver"; combat.clearProjectiles() }
            else if sides.isEmpty { beginSuddenDeath() }
            return
        }
        if objective.mode == "ctf" {
            for i in objective.flags.indices {
                if objective.flags[i].carrier >= 0 {
                    if let tank = combat.snapshot.tanks.first(where: { $0.id == objective.flags[i].carrier }), tank.hp > 0 {
                        objective.flags[i].x = tank.x; objective.flags[i].y = tank.y
                    } else {
                        let fallen = combat.snapshot.tanks.first { $0.id == objective.flags[i].carrier }
                        let point = combat.maze.phaseExit(x: fallen?.x ?? objective.flags[i].x, y: fallen?.y ?? objective.flags[i].y)
                        objective.flags[i].x = point.x; objective.flags[i].y = point.y
                        objective.flags[i].carrier = -1; objective.flags[i].home = false; objective.flags[i].returnIn = 12
                    }
                }
                if !objective.flags[i].home && objective.flags[i].carrier < 0 {
                    objective.flags[i].returnIn -= dt
                    if objective.flags[i].returnIn <= 0 { resetFlag(&objective.flags[i]) }
                }
            }
            let living = combat.snapshot.tanks.filter { $0.hp > 0 && $0.invulnerable <= 0 }
            func touches(_ tank: ArenaTank, _ flag: ArenaFlag, radius: Double = 31) -> Bool {
                hypot(tank.x - flag.x, tank.y - flag.y) < radius && !combat.maze.segmentBlocked(x: tank.x, y: tank.y, dx: flag.x - tank.x, dy: flag.y - tank.y)
            }
            for tank in living {
                for i in objective.flags.indices where objective.flags[i].team == tank.team && !objective.flags[i].home && objective.flags[i].carrier < 0 {
                    if touches(tank, objective.flags[i]) { resetFlag(&objective.flags[i]) }
                }
            }
            for tank in living {
                guard let own = objective.flags.firstIndex(where: { $0.team == tank.team }) else { continue }
                var carried = objective.flags.firstIndex(where: { $0.carrier == tank.id })
                if carried == nil, let enemy = objective.flags.firstIndex(where: { $0.team != tank.team && $0.carrier < 0 && touches(tank, $0) }) {
                    objective.flags[enemy].carrier = tank.id; objective.flags[enemy].home = false; objective.flags[enemy].returnIn = 0
                    objective.flags[enemy].x = tank.x; objective.flags[enemy].y = tank.y; carried = enemy
                }
                if let carried, objective.flags[own].home {
                    let home = objective.flags[own]
                    if hypot(tank.x - home.homeX, tank.y - home.homeY) < 34 && !combat.maze.segmentBlocked(x: tank.x, y: tank.y, dx: home.homeX - tank.x, dy: home.homeY - tank.y) {
                        resetFlag(&objective.flags[carried]); awardPoint(to: tank)
                    }
                }
            }
        } else {
            let occupiers = combat.snapshot.tanks.filter {
                $0.hp > 0 && $0.invulnerable <= 0 && hypot($0.x - objective.hillX, $0.y - objective.hillY) <= objective.radius
                && !combat.maze.segmentBlocked(x: objective.hillX, y: objective.hillY, dx: $0.x - objective.hillX, dy: $0.y - objective.hillY)
            }
            let sides = Set(occupiers.map(side))
            objective.contested = sides.count > 1
            if sides.count == 1, let owner = occupiers.first {
                let code = owner.team > 0 ? owner.team : -owner.id - 1
                if objective.owner != code { objective.hold = 0 }
                objective.owner = code; objective.hold += dt
                while objective.hold >= 1 - 1e-9 {
                    objective.hold = max(0, objective.hold - 1); awardPoint(to: owner)
                }
            } else { objective.owner = 0; objective.hold = 0 }
        }
        objectives = objective
        if phase == "playing", clock <= 0 {
            winner = leader()
            if winner >= 0 { phase = "matchOver"; combat.clearProjectiles() }
            else { beginSuddenDeath() }
        }
        restoreScores()
    }

    private func resetFlag(_ flag: inout ArenaFlag) {
        flag.x = flag.homeX; flag.y = flag.homeY; flag.carrier = -1; flag.home = true; flag.returnIn = 0
    }

    private func beginSuddenDeath() {
        objectives?.suddenDeath = true; objectives?.owner = 0; objectives?.hold = 0
        combat.respawnsEnabled = false; combat.clearProjectiles()
        combat.snapshot.pickups.removeAll()
        if var flags = objectives?.flags {
            for index in flags.indices { resetFlag(&flags[index]) }
            objectives?.flags = flags
        }
        for index in combat.snapshot.tanks.indices { combat.snapshot.tanks[index].hp = 0 }
        for index in combat.snapshot.tanks.indices {
            let old = combat.snapshot.tanks[index], point = respawnPoint(for: old)
            combat.snapshot.tanks[index] = ArenaTank(id: old.id, name: old.name, x: point.x, y: point.y, angle: -.pi / 2,
                colorIndex: old.colorIndex, score: scores[old.id] ?? 0, team: old.team, bot: old.bot,
                spawnProtected: true, spawnSerial: old.spawnSerial + 1, invulnerable: 1.2, difficulty: old.difficulty)
        }
    }

    private func stepSurvival() {
        guard var survival = objectives?.survival else { return }
        let living = combat.snapshot.tanks.filter { $0.hp > 0 }
        survival.enemiesRemaining = living.filter(\.survivalEnemy).count
        survival.boss = living.contains { $0.survivalBoss }
        if !living.contains(where: { !$0.survivalEnemy }) {
            survival.status = "lost"; phase = "matchOver"; winner = -1; combat.clearProjectiles()
        } else if survival.enemiesRemaining == 0 {
            survival.wavesCleared += 1
            for tank in combat.snapshot.tanks where !tank.survivalEnemy { scores[tank.id] = survival.wavesCleared }
            if survival.wavesCleared >= survival.waveTarget {
                survival.status = "won"; phase = "matchOver"; winner = localID
            } else { survival.status = "break"; survival.breakTime = 2 }
            combat.clearProjectiles()
        } else if clock <= 0 {
            survival.status = "lost"; phase = "matchOver"; winner = -1; combat.clearProjectiles()
        }
        objectives?.survival = survival; restoreScores()
    }

    private func bossName(_ wave: Int) -> String { wave < 10 ? "NORMAL BOSS" : wave < 15 ? "FIERCE BOSS" : "GODLIKE BOSS" }

    private func survivalEnemySpawn(id: Int) -> (x: Double, y: Double) {
        var best = -Double.infinity, result = (x: 42.0, y: 42.0)
        for row in 0..<world.rows {
            for col in 0..<world.cols {
                let point = (x: (Double(col) + 0.5) * 84, y: (Double(row) + 0.5) * 84)
                let clearance = combat.snapshot.tanks.filter { $0.id != id && $0.hp > 0 }
                    .map { hypot($0.x - point.x, $0.y - point.y) - 34 }.min() ?? .infinity
                if clearance > best { best = clearance; result = point }
            }
        }
        return result
    }

    private func objectiveGoal(for tank: ArenaTank) -> (x: Double, y: Double)? {
        guard let objective = objectives, !objective.suddenDeath else { return nil }
        if objective.mode == "koth" { return (objective.hillX, objective.hillY) }
        guard objective.mode == "ctf", let own = objective.flags.first(where: { $0.team == tank.team }),
              let enemy = objective.flags.first(where: { $0.team != tank.team }) else { return nil }
        if !own.home && (tank.id.isMultiple(of: 2) || enemy.carrier == tank.id) { return (own.x, own.y) }
        if enemy.carrier == tank.id { return (own.homeX, own.homeY) }
        return (enemy.x, enemy.y)
    }

    private func respawnPoint(for tank: ArenaTank) -> (x: Double, y: Double) {
        let home = objectives?.flags.first(where: { $0.team == tank.team })
        let baseX = home?.homeX ?? (tank.id.isMultiple(of: 2) ? world.width - 42 : 42)
        let baseY = home?.homeY ?? (tank.id.isMultiple(of: 2) ? 42 : world.height - 42)
        let start = (x: Int(baseX / 84), y: Int(baseY / 84))
        var queue = [start], seen = Set([start.y * world.cols + start.x]), head = 0
        var best = -Double.infinity, point = (x: baseX, y: baseY)
        while head < queue.count {
            let cell = queue[head]; head += 1
            let x = (Double(cell.x) + 0.5) * 84, y = (Double(cell.y) + 0.5) * 84
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let next = (x: cell.x + dx, y: cell.y + dy), key = (cell.y + dy) * world.cols + cell.x + dx
                guard next.x >= 0, next.x < world.cols, next.y >= 0, next.y < world.rows, !seen.contains(key),
                      !combat.maze.blocked(x: x + Double(dx) * 42, y: y + Double(dy) * 42, radius: 17) else { continue }
                queue.append(next); seen.insert(key)
            }
            if let home, (cell.x == Int(home.homeX / 84) && cell.y == Int(home.homeY / 84) || hypot(x - home.x, y - home.y) < 49) { continue }
            let clearance = combat.snapshot.tanks.filter { $0.id != tank.id && $0.hp > 0 }.map { hypot($0.x - x, $0.y - y) - 34 }.min() ?? 500
            if clearance > best { best = clearance; point = (x, y) }
            if clearance > 70 { return point }
        }
        return point
    }

    private func makeWorld() -> ArenaWorld {
        let sizes = ["compact": (7, 7), "standard": (9, 8), "large": (12, 10), "huge": (14, 12), "giant": (16, 14), "ultrawide": (24, 14)]
        let size = sizes[rules.mapSize] ?? (9, 8), cols = rules.portraitMaze ? size.1 : size.0, rows = rules.portraitMaze ? size.0 : size.1
        var cells = [UInt8](repeating: 3, count: cols * rows), visited = [Bool](repeating: false, count: cols * rows)
        let start = random(cells.count); visited[start] = true; var stack = [start]
        while let cell = stack.last {
            let x = cell % cols, y = cell / cols
            var neighbors: [Int] = []
            if y > 0 && !visited[cell - cols] { neighbors.append(cell - cols) }
            if x + 1 < cols && !visited[cell + 1] { neighbors.append(cell + 1) }
            if y + 1 < rows && !visited[cell + cols] { neighbors.append(cell + cols) }
            if x > 0 && !visited[cell - 1] { neighbors.append(cell - 1) }
            if neighbors.isEmpty { stack.removeLast(); continue }
            let neighbor = neighbors[random(neighbors.count)]
            switch neighbor - cell {
            case -cols: cells[cell] &= ~1
            case 1: cells[neighbor] &= ~2
            case cols: cells[neighbor] &= ~1
            default: cells[cell] &= ~2
            }
            visited[neighbor] = true; stack.append(neighbor)
        }
        // Finite Go/browser mazes consider east then south edges in row order
        // and open each remaining interior wall with probability 25%.
        for row in 0..<rows {
            for col in 0..<cols {
                let cell = row * cols + col
                if col + 1 < cols && cells[cell + 1] & 2 != 0 && random(4) == 0 { cells[cell + 1] &= ~2 }
                if row + 1 < rows && cells[cell + cols] & 1 != 0 && random(4) == 0 { cells[cell + cols] &= ~1 }
            }
        }
        var walls: [MazeWall] = []
        for y in 0..<rows {
            for x in 0..<cols {
                let wx = Double(x) * 84, wy = Double(y) * 84, bits = cells[y * cols + x]
                if bits & 1 != 0 { walls.append(MazeWall(x: wx - 4, y: wy - 4, w: 92, h: 8, axis: "h", line: wy)) }
                if bits & 2 != 0 { walls.append(MazeWall(x: wx - 4, y: wy - 4, w: 8, h: 92, axis: "v", line: wx)) }
                if y == rows - 1 { walls.append(MazeWall(x: wx - 4, y: Double(rows) * 84 - 4, w: 92, h: 8, axis: "h", line: Double(rows) * 84)) }
                if x == cols - 1 { walls.append(MazeWall(x: Double(cols) * 84 - 4, y: wy - 4, w: 8, h: 92, axis: "v", line: Double(cols) * 84)) }
            }
        }
        return ArenaWorld(width: Double(cols) * 84, height: Double(rows) * 84, cols: cols, rows: rows, walls: walls)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
