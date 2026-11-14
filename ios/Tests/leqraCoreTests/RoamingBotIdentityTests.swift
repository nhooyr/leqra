import Foundation
import XCTest
@testable import leqraCore

final class RoamingBotIdentityTests: XCTestCase {
    private func rules(_ rates: [String: Double], teams: Bool = false) -> RoomRules {
        var rules = RoomRules(); rules.infinity = true; rules.infinityRandomBots = true
        rules.infinityBotSpawnRates = rates; rules.teamMode = teams ? "teams" : "ffa"
        return rules
    }

    private func arena(_ rates: [String: Double] = ["dumb": 4], teams: Bool = false) -> PracticeArena {
        let arena = PracticeArena(seed: 42, name: "Human", colorIndex: 0, botCount: 0)
        arena.configure(rules: rules(rates, teams: teams))
        arena.step(input: GameInput(), dt: 1 / 60)
        return arena
    }

    private func advance(_ arena: PracticeArena, seconds: Double) {
        for _ in 0..<Int((seconds * 60).rounded()) {
            for index in arena.snapshot.tanks.indices {
                if arena.snapshot.tanks[index].bot { arena.snapshot.tanks[index].cooldown = 999 }
                else { arena.snapshot.tanks[index].invulnerable = 999 }
            }
            arena.step(input: GameInput(), dt: 1 / 60)
        }
    }

    func testDifferentTierAllocatesANewIdentityAndMatchingTierReusesItsScoreAndSerial() throws {
        let arena = arena()
        let original = try XCTUnwrap(arena.snapshot.tanks.first { $0.bot })
        let index = try XCTUnwrap(arena.snapshot.tanks.firstIndex { $0.id == original.id })
        arena.snapshot.tanks[index].score = 17
        arena.configure(rules: rules(["normal": 4]))
        arena.step(input: GameInput(), dt: 1 / 60)
        let normal = try XCTUnwrap(arena.snapshot.tanks.first { $0.bot })
        XCTAssertNotEqual(normal.id, original.id); XCTAssertNotEqual(normal.name, original.name)
        XCTAssertEqual(normal.difficulty, "normal")
        XCTAssertEqual(arena.snapshot.leaderboard.first { $0.id == original.id }?.score, 17)
        arena.configure(rules: rules(["dumb": 4]))
        arena.step(input: GameInput(), dt: 1 / 60)
        let reused = try XCTUnwrap(arena.snapshot.tanks.first { $0.bot })
        XCTAssertEqual(reused.id, original.id); XCTAssertEqual(reused.name, original.name)
        XCTAssertEqual(reused.difficulty, "dumb"); XCTAssertEqual(reused.score, 17)
        XCTAssertEqual(reused.spawnSerial, original.spawnSerial + 1)
        XCTAssertEqual(Set(arena.snapshot.leaderboard.map(\.id)).count, 3)
        XCTAssertEqual(arena.snapshot.tankCount, 3)
    }

    func testDeathRetainsTheCorpseForOneSecondThenWaitsForItsTierOpportunity() throws {
        let arena = arena(["dumb": 0.25])
        let index = try XCTUnwrap(arena.snapshot.tanks.firstIndex { $0.bot })
        let original = arena.snapshot.tanks[index]
        arena.snapshot.tanks[index].hp = 0; arena.snapshot.tanks[index].respawnTime = 1
        arena.snapshot.tanks[index].score = 8
        advance(arena, seconds: 0.9)
        XCTAssertEqual(arena.snapshot.tanks.first { $0.id == original.id }?.hp, 0)
        advance(arena, seconds: 0.2)
        XCTAssertFalse(arena.snapshot.tanks.contains { $0.id == original.id })
        XCTAssertEqual(arena.snapshot.leaderboard.first { $0.id == original.id }?.score, 8)
        advance(arena, seconds: 7.1)
        XCTAssertEqual(arena.snapshot.tanks.first { $0.id == original.id }?.spawnSerial, original.spawnSerial + 1)
        XCTAssertEqual(arena.snapshot.tanks.first { $0.id == original.id }?.score, 8)
    }

    func testDistanceAndAllOffParkInsteadOfForgettingStandingsAndTeamScores() throws {
        let arena = arena(teams: true)
        let index = try XCTUnwrap(arena.snapshot.tanks.firstIndex { $0.bot })
        let original = arena.snapshot.tanks[index]
        arena.snapshot.tanks[index].score = 13
        arena.snapshot.tanks[index].x += 100 * 84
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertFalse(arena.snapshot.tanks.contains { $0.id == original.id })
        XCTAssertEqual(arena.snapshot.leaderboard.first { $0.id == original.id }?.score, 13)
        XCTAssertEqual(arena.snapshot.teamScores[original.team - 1], 13)
        arena.configure(rules: rules([:], teams: true))
        advance(arena, seconds: 1)
        XCTAssertEqual(arena.snapshot.tanks.filter(\.bot).count, 0)
        XCTAssertEqual(arena.snapshot.leaderboard.first { $0.id == original.id }?.difficulty, "dumb")
        arena.configure(rules: rules(["dumb": 4], teams: true))
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(arena.snapshot.tanks.first { $0.id == original.id }?.score, 13)
    }

    func testFiveTierPoolsReuseNumbersWithoutGrowingBeyondTheirActiveBudgets() {
        let arena = arena()
        for _ in 0..<2 {
            for tier in ["dumb", "easy", "normal", "hard", "godlike"] {
                arena.configure(rules: rules([tier: 4]))
                advance(arena, seconds: 12)
                XCTAssertEqual(arena.snapshot.tanks.filter(\.bot).count, 16)
                XCTAssertTrue(arena.snapshot.tanks.filter(\.bot).allSatisfy { $0.difficulty == tier })
            }
        }
        let bots = arena.snapshot.leaderboard.filter(\.bot)
        XCTAssertEqual(bots.count, 80)
        XCTAssertEqual(Set(bots.map(\.id)).count, 80); XCTAssertEqual(Set(bots.map(\.name)).count, 80)
    }

    func testEarlyCorpseRetirementRetainsItsDeadlineAndDoesNotOverflowAFullTier() {
        let arena = PracticeArena(seed: 42, name: "Human", colorIndex: 0, botCount: 0)
        for id in 2...8 { arena.snapshot.tanks.append(ArenaTank(id: id, name: "Human \(id)", x: Double(id * 100) * 84 + 42, y: 42)) }
        arena.configure(rules: rules(["dumb": 4]))
        advance(arena, seconds: 12)
        let original = Set(arena.snapshot.tanks.filter(\.bot).map(\.id))
        XCTAssertEqual(original.count, 128)
        for index in arena.snapshot.tanks.indices where arena.snapshot.tanks[index].bot {
            arena.snapshot.tanks[index].hp = 0; arena.snapshot.tanks[index].respawnTime = 1
            arena.snapshot.tanks[index].score = 7
        }
        arena.configure(rules: rules(["dumb": 4]))
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertTrue(arena.snapshot.tanks.filter(\.bot).isEmpty, "A new wave cannot bypass parked corpses' deadlines or allocate a129th same-tier identity")
        advance(arena, seconds: 0.9)
        XCTAssertTrue(arena.snapshot.tanks.filter(\.bot).isEmpty)
        advance(arena, seconds: 1)
        XCTAssertFalse(arena.snapshot.tanks.filter(\.bot).isEmpty)
        XCTAssertEqual(Set(arena.snapshot.leaderboard.filter(\.bot).map(\.id)), original)
        XCTAssertTrue(arena.snapshot.leaderboard.filter(\.bot).allSatisfy { $0.score == 7 })
    }

    func testAlreadyFiredProjectileCreditsItsParkedBotIdentity() throws {
        let arena = arena(["normal": 4])
        let botIndex = try XCTUnwrap(arena.snapshot.tanks.firstIndex { $0.bot })
        let original = arena.snapshot.tanks[botIndex]
        var corridor: (x: Double, y: Double, dx: Double, dy: Double)?
        for y in 0..<8 { for x in 0..<8 { for (dx, dy) in [(168.0, 0.0), (0.0, 168.0)] {
            let px = Double(x) * 84 + 42, py = Double(y) * 84 + 42
            if arena.maze.rayHit(x: px, y: py, dx: dx, dy: dy, radius: 3.5) == nil { corridor = (px, py, dx, dy) }
        } } }
        let path = try XCTUnwrap(corridor)
        arena.snapshot.tanks[0].x = path.x + path.dx; arena.snapshot.tanks[0].y = path.y + path.dy
        arena.snapshot.tanks[0].invulnerable = 0; arena.snapshot.tanks[0].spawnProtected = false
        arena.snapshot.tanks[botIndex].x = path.x; arena.snapshot.tanks[botIndex].y = path.y
        arena.snapshot.tanks[botIndex].angle = atan2(path.dy, path.dx)
        arena.snapshot.tanks[botIndex].invulnerable = 0; arena.snapshot.tanks[botIndex].spawnProtected = false
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertTrue(arena.snapshot.bullets.contains { $0.owner == original.id })
        arena.configure(rules: rules([:]))
        for _ in 0..<60 { arena.step(input: GameInput(), dt: 1 / 60) }
        XCTAssertEqual(arena.snapshot.leaderboard.first { $0.id == original.id }?.score, 1)
        XCTAssertEqual(arena.snapshot.tanks[0].score, -1)
        XCTAssertEqual(arena.snapshot.tanks[0].killedBy, original.name)
    }
}
