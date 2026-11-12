import XCTest
@testable import leqraCore

final class FixedArenaTests: XCTestCase {
    private func arena(_ mode: String = "elimination", target: Int = 5, bots: Int = 3) -> FixedArena {
        var rules = RoomRules(); rules.mode = mode; rules.scoreTarget = target; rules.pickupRate = "off"
        return FixedArena(rules: rules, name: "SNOW FOX", colorIndex: 0, botCount: bots, seed: 42)
    }
    private func advance(_ arena: FixedArena, ticks: Int) {
        for _ in 0..<ticks { arena.step(input: GameInput(), dt: 1 / 60) }
    }
    private func begin(_ arena: FixedArena) { advance(arena, ticks: 180); XCTAssertEqual(arena.snapshot.phase, "playing") }
    private func eliminateOpponents(_ arena: FixedArena) {
        for i in arena.combat.snapshot.tanks.indices where arena.combat.snapshot.tanks[i].id != 1 {
            arena.combat.snapshot.tanks[i].hp = 0
        }
    }

    func testEveryFiniteSizeAndPortraitMazeIsConnectedAndBounded() {
        for (size, expected) in [("compact", (7, 7)), ("standard", (9, 8)), ("large", (12, 10)),
                                 ("huge", (14, 12)), ("giant", (16, 14)), ("ultrawide", (24, 14))] {
            for portrait in [false, true] {
                var rules = RoomRules(); rules.mapSize = size; rules.portraitMaze = portrait
                let arena = FixedArena(rules: rules, name: "SNOW FOX", colorIndex: 0, seed: 42), world = arena.world
                XCTAssertEqual(world.cols, portrait ? expected.1 : expected.0)
                XCTAssertEqual(world.rows, portrait ? expected.0 : expected.1)
                let maze = InfiniteMaze(world: world)
                var queue = [0], visited = Set([0]), head = 0
                while head < queue.count {
                    let cell = queue[head]; head += 1
                    let col = cell % world.cols, row = cell / world.cols
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let x = col + dx, y = row + dy, next = y * world.cols + x
                        guard x >= 0, x < world.cols, y >= 0, y < world.rows, !visited.contains(next),
                              !maze.blocked(x: (Double(col) + 0.5 + Double(dx) / 2) * 84,
                                            y: (Double(row) + 0.5 + Double(dy) / 2) * 84, radius: 17) else { continue }
                        visited.insert(next); queue.append(next)
                    }
                }
                XCTAssertEqual(visited.count, world.cols * world.rows)
                XCTAssertTrue(maze.blocked(x: -10, y: 42, radius: 17))
                XCTAssertTrue(maze.blocked(x: world.width + 10, y: 42, radius: 17))
            }
        }
    }

    func testUnknownMapFallsBackToStandardAndFiniteWallsKeepWebScale() {
        var rules = RoomRules(); rules.mapSize = "unknown"
        let world = FixedArena(rules: rules, name: "SNOW FOX", colorIndex: 0, botCount: 0, seed: 42).world
        XCTAssertEqual(world.cols, 9); XCTAssertEqual(world.rows, 8)
        XCTAssertEqual(world.width, 9 * 84); XCTAssertEqual(world.height, 8 * 84)
        for wall in world.walls {
            XCTAssertEqual(wall.axis == "h" ? wall.h : wall.w, 8)
            XCTAssertEqual(wall.axis == "h" ? wall.w : wall.h, 92)
            XCTAssertEqual(wall.line.truncatingRemainder(dividingBy: 84), 0)
        }
    }

    func testFiniteMazeOpensOneQuarterOfRemainingInteriorWalls() {
        var rules = RoomRules(); rules.mapSize = "large"; rules.pickupRate = "off"
        var opened = 0, candidates = 0
        // A spanning tree leaves (columns-1)*(rows-1) closed interior edges.
        // Sample deterministic seeds so a 20% opening rule cannot pass as 25%.
        for seed in 1...128 {
            let world = FixedArena(rules: rules, name: "SNOW FOX", colorIndex: 0, botCount: 0, seed: UInt32(seed)).world
            let closedAfterTree = (world.cols - 1) * (world.rows - 1)
            let interiorWalls = world.walls.count - 2 * world.cols - 2 * world.rows
            opened += closedAfterTree - interiorWalls
            candidates += closedAfterTree
        }
        XCTAssertEqual(Double(opened) / Double(candidates), 0.25, accuracy: 0.02)
    }

    func testEliminationCountsRoundsChangesMazeAndFinishesAtTarget() {
        let arena = arena(target: 2, bots: 1), originalWorld = arena.world
        let initial = arena.snapshot.tanks[0]
        advance(arena, ticks: 60)
        XCTAssertEqual(arena.snapshot.tanks[0].x, initial.x)
        XCTAssertEqual(arena.snapshot.phase, "countdown")
        advance(arena, ticks: 120)
        eliminateOpponents(arena); advance(arena, ticks: 1)
        XCTAssertEqual(arena.snapshot.phase, "roundOver")
        XCTAssertEqual(arena.snapshot.winner, 1)
        XCTAssertEqual(arena.snapshot.scores[1], 1)
        advance(arena, ticks: 120)
        XCTAssertEqual(arena.snapshot.phase, "countdown")
        XCTAssertEqual(arena.snapshot.round, 2)
        XCTAssertEqual(arena.snapshot.generation, 2)
        XCTAssertNotEqual(arena.world.walls, originalWorld.walls)
        begin(arena); eliminateOpponents(arena); advance(arena, ticks: 1)
        advance(arena, ticks: 120)
        XCTAssertEqual(arena.snapshot.phase, "matchOver")
        XCTAssertEqual(arena.snapshot.scores[1], 2)
    }

    func testFiniteCannonIgnoresInteriorWallsButReflectsAtRim() throws {
        let arena = arena(bots: 1)
        let practice = PracticeArena(seed: 42, name: "SNOW FOX", colorIndex: 0, botCount: 0, world: arena.world)
        var tank = ArenaTank(id: 1, name: "SNOW FOX", x: arena.world.width - 50, y: 42)
        PracticeArena.applyPower(tank: &tank, kind: "cannon")
        practice.snapshot.tanks = [tank]
        practice.step(input: GameInput(fire: true), dt: 1 / 60)
        let bullet = try XCTUnwrap(practice.snapshot.bullets.first)
        XCTAssertGreaterThanOrEqual(bullet.bounces, 1)
        XCTAssertLessThan(bullet.vx, 0)
        XCTAssertLessThanOrEqual(bullet.x, arena.world.width - 18)
    }

    func testCaptureRequiresOwnFlagHomeAndAwardsTeamPoint() throws {
        let arena = arena("ctf", target: 1, bots: 1)
        begin(arena)
        XCTAssertEqual(arena.snapshot.tanks[0].team, 1)
        let enemy = try XCTUnwrap(arena.objectives?.flags.first { $0.team == 2 })
        arena.combat.snapshot.tanks[0].x = enemy.homeX; arena.combat.snapshot.tanks[0].y = enemy.homeY
        arena.combat.snapshot.tanks[0].invulnerable = 0; arena.combat.snapshot.tanks[0].spawnProtected = false
        advance(arena, ticks: 1)
        XCTAssertEqual(arena.objectives?.flags.first { $0.team == 2 }?.carrier, 1)
        let own = try XCTUnwrap(arena.objectives?.flags.first { $0.team == 1 })
        arena.objectives?.flags[0].home = false
        arena.objectives?.flags[0].carrier = 2
        arena.combat.snapshot.tanks[0].x = own.homeX; arena.combat.snapshot.tanks[0].y = own.homeY
        advance(arena, ticks: 1)
        XCTAssertEqual(arena.snapshot.scores[1], 0)
        arena.objectives?.flags[0].home = true; arena.objectives?.flags[0].carrier = -1
        arena.objectives?.flags[0].x = own.homeX; arena.objectives?.flags[0].y = own.homeY
        advance(arena, ticks: 1)
        XCTAssertEqual(arena.snapshot.scores[1], 1)
        XCTAssertEqual(arena.snapshot.phase, "matchOver")
        XCTAssertEqual(arena.objectives?.flags.first { $0.team == 2 }?.home, true)
    }

    func testHillContestingResetsProgressAndSoloHoldScoresOncePerSecond() throws {
        let arena = arena("koth", target: 2, bots: 1)
        begin(arena)
        let hill = try XCTUnwrap(arena.objectives)
        for i in arena.combat.snapshot.tanks.indices {
            arena.combat.snapshot.tanks[i].bot = false
            arena.combat.snapshot.tanks[i].invulnerable = 0
            arena.combat.snapshot.tanks[i].x = hill.hillX + (i == 0 ? -20 : 20)
            arena.combat.snapshot.tanks[i].y = hill.hillY
        }
        advance(arena, ticks: 60)
        XCTAssertEqual(arena.objectives?.contested, true)
        XCTAssertEqual(arena.snapshot.scores[1], 0)
        arena.combat.snapshot.tanks[1].hp = 0; arena.combat.snapshot.tanks[1].respawnTime = 999
        advance(arena, ticks: 59)
        XCTAssertEqual(arena.snapshot.scores[1], 0)
        advance(arena, ticks: 1)
        XCTAssertEqual(arena.snapshot.scores[1], 1)
        advance(arena, ticks: 60)
        XCTAssertEqual(arena.snapshot.phase, "matchOver")
    }

    func testObjectiveTieStartsSuddenDeathAndLastSideWins() {
        var rules = RoomRules(); rules.mode = "koth"; rules.timeLimit = 1; rules.pickupRate = "off"
        let arena = FixedArena(rules: rules, name: "SNOW FOX", colorIndex: 0, botCount: 1, seed: 42)
        begin(arena)
        for i in arena.combat.snapshot.tanks.indices { arena.combat.snapshot.tanks[i].invulnerable = 100 }
        advance(arena, ticks: 60)
        XCTAssertEqual(arena.objectives?.suddenDeath, true)
        XCTAssertFalse(arena.combat.respawnsEnabled)
        eliminateOpponents(arena); advance(arena, ticks: 1)
        XCTAssertEqual(arena.snapshot.phase, "matchOver")
        XCTAssertEqual(arena.snapshot.winner, 1)
    }

    func testSurvivalClearedWavesReviveSquadAndFinishAtTarget() {
        let arena = arena("survival", target: 2, bots: 1)
        begin(arena)
        XCTAssertEqual(arena.snapshot.tanks.filter(\.survivalEnemy).count, 2)
        arena.combat.snapshot.tanks[0].hp = 0
        for i in arena.combat.snapshot.tanks.indices where arena.combat.snapshot.tanks[i].survivalEnemy { arena.combat.snapshot.tanks[i].hp = 0 }
        advance(arena, ticks: 1)
        XCTAssertEqual(arena.objectives?.survival?.status, "break")
        XCTAssertEqual(arena.objectives?.survival?.wavesCleared, 1)
        XCTAssertEqual(arena.snapshot.tanks[0].hp, 0)
        advance(arena, ticks: 120)
        XCTAssertEqual(arena.snapshot.phase, "countdown")
        XCTAssertEqual(arena.objectives?.survival?.wave, 2)
        XCTAssertEqual(arena.snapshot.tanks[0].hp, 1)
        begin(arena)
        for i in arena.combat.snapshot.tanks.indices where arena.combat.snapshot.tanks[i].survivalEnemy { arena.combat.snapshot.tanks[i].hp = 0 }
        advance(arena, ticks: 1)
        XCTAssertEqual(arena.snapshot.phase, "matchOver")
        XCTAssertEqual(arena.objectives?.survival?.status, "won")
        XCTAssertEqual(arena.snapshot.scores[1], 2)
    }

    func testSurvivalMutualDestructionIsLossAndRestartResetsScores() {
        let arena = arena("survival", bots: 1)
        begin(arena)
        for i in arena.combat.snapshot.tanks.indices { arena.combat.snapshot.tanks[i].hp = 0 }
        advance(arena, ticks: 1)
        XCTAssertEqual(arena.snapshot.phase, "matchOver")
        XCTAssertEqual(arena.objectives?.survival?.status, "lost")
        XCTAssertEqual(arena.objectives?.survival?.wavesCleared, 0)
        let oldWorld = arena.world
        arena.restart()
        XCTAssertEqual(arena.snapshot.phase, "countdown")
        XCTAssertEqual(arena.snapshot.round, 1)
        XCTAssertEqual(arena.snapshot.scores[1], 0)
        XCTAssertNotEqual(arena.world.walls, oldWorld.walls)
    }

    func testFixedPresentationCannotAdvanceCountdownOrAwardPoints() {
        let arena = arena("ctf", bots: 1), state = self.arena("ctf", bots: 1)
        let original = arena.snapshot
        for _ in 0..<120 { _ = arena.presentationSnapshot(fraction: 0.5, localInput: GameInput(forward: true, fire: true)) }
        XCTAssertEqual(arena.snapshot, original)
        XCTAssertEqual(arena.snapshot, state.snapshot)
    }

    func testPilotConfigurationPersistsAcrossNewMazeAndRestart() throws {
        let arena = arena(target: 2, bots: 1)
        arena.configurePilot(id: 2, name: "VIPER", colorIndex: 5, difficulty: "godlike")
        begin(arena); eliminateOpponents(arena); advance(arena, ticks: 1); advance(arena, ticks: 120)
        let second = try XCTUnwrap(arena.snapshot.tanks.first { $0.id == 2 })
        XCTAssertEqual(second.name, "VIPER"); XCTAssertEqual(second.colorIndex, 5); XCTAssertEqual(second.difficulty, "godlike")
        arena.restart()
        XCTAssertEqual(arena.snapshot.tanks.first { $0.id == 2 }?.name, "VIPER")
    }

    func testSurvivalEnemiesStartClearOfEverySquadTankAndBossDebutsOnWaveFive() {
        let arena = arena("survival", target: 10, bots: 3)
        for wave in 1...5 {
            for enemy in arena.snapshot.tanks where enemy.survivalEnemy {
                for other in arena.snapshot.tanks where other.id != enemy.id {
                    XCTAssertGreaterThan(hypot(enemy.x - other.x, enemy.y - other.y), 34)
                }
            }
            if wave == 5 {
                let bosses = arena.snapshot.tanks.filter(\.survivalBoss)
                XCTAssertEqual(bosses.count, 1)
                XCTAssertEqual(bosses[0].name, "NORMAL BOSS")
                XCTAssertEqual(bosses[0].difficulty, "normal")
                XCTAssertEqual(arena.objectives?.survival?.wave, 5)
                break
            }
            begin(arena)
            for i in arena.combat.snapshot.tanks.indices where arena.combat.snapshot.tanks[i].survivalEnemy { arena.combat.snapshot.tanks[i].hp = 0 }
            advance(arena, ticks: 1); advance(arena, ticks: 120)
        }
    }

    func testFinitePowerDurationsAndMachineFiringBudgetMatchMapArea() {
        let arena = arena(bots: 0)
        begin(arena)
        arena.combat.snapshot.tanks[0].invulnerable = 0
        arena.combat.snapshot.pickups = [ArenaPickup(id: 99, x: arena.snapshot.tanks[0].x, y: arena.snapshot.tanks[0].y, type: "rapid")]
        arena.combat.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(arena.combat.snapshot.tanks[0].machineRounds, 180)
        XCTAssertEqual(arena.combat.snapshot.tanks[0].powerTime, 10)
    }

    func testSurvivalClearOnLastTimerTickCountsAsWin() {
        var rules = RoomRules(); rules.mode = "survival"; rules.scoreTarget = 1; rules.timeLimit = 1; rules.pickupRate = "off"
        let arena = FixedArena(rules: rules, name: "SNOW FOX", colorIndex: 0, botCount: 0, seed: 42)
        begin(arena)
        for index in arena.combat.snapshot.tanks.indices { arena.combat.snapshot.tanks[index].invulnerable = 100 }
        advance(arena, ticks: 59)
        for index in arena.combat.snapshot.tanks.indices where arena.combat.snapshot.tanks[index].survivalEnemy { arena.combat.snapshot.tanks[index].hp = 0 }
        advance(arena, ticks: 1)
        XCTAssertEqual(arena.snapshot.phase, "matchOver")
        XCTAssertEqual(arena.objectives?.survival?.status, "won")
        XCTAssertEqual(arena.objectives?.survival?.wavesCleared, 1)
    }

    func testFiniteSpatialQueriesPreserveLinearWallOrderAndBoundaryContacts() {
        let arena = arena(), world = arena.world, maze = InfiniteMaze(world: world)
        for x in stride(from: -42.0, through: world.width + 42, by: 83) {
            for y in stride(from: -42.0, through: world.height + 42, by: 83) {
                let expected = world.walls.filter { $0.x <= x + 42 && $0.x + $0.w >= x && $0.y <= y + 42 && $0.y + $0.h >= y }
                XCTAssertEqual(maze.walls(x0: x, y0: y, x1: x + 42, y1: y + 42), expected)
            }
        }
        XCTAssertEqual(maze.walls(x0: -10, y0: -10, x1: world.width + 10, y1: world.height + 10), world.walls)
    }

    func testRestartSurvivalWaveRetainsMazeAndPreviouslyClearedWaves() {
        let arena = arena("survival", target: 5, bots: 1)
        begin(arena)
        for i in arena.combat.snapshot.tanks.indices where arena.combat.snapshot.tanks[i].survivalEnemy { arena.combat.snapshot.tanks[i].hp = 0 }
        advance(arena, ticks: 1); advance(arena, ticks: 120); begin(arena)
        for i in arena.combat.snapshot.tanks.indices where !arena.combat.snapshot.tanks[i].survivalEnemy { arena.combat.snapshot.tanks[i].hp = 0 }
        advance(arena, ticks: 1)
        XCTAssertEqual(arena.objectives?.survival?.status, "lost")
        XCTAssertTrue(arena.canRestartWave)
        let world = arena.world, generation = arena.snapshot.generation
        arena.restartWave()
        XCTAssertEqual(arena.world, world)
        XCTAssertEqual(arena.snapshot.generation, generation + 1)
        XCTAssertEqual(arena.snapshot.phase, "countdown")
        XCTAssertEqual(arena.objectives?.survival?.wave, 2)
        XCTAssertEqual(arena.objectives?.survival?.wavesCleared, 1)
        XCTAssertEqual(arena.snapshot.scores[1], 1)
        XCTAssertTrue(arena.snapshot.tanks.allSatisfy { $0.hp > 0 })
    }
}
