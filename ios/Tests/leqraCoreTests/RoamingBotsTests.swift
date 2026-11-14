import Foundation
import XCTest
@testable import leqraCore

final class RoamingBotsTests: XCTestCase {
    func testSpawnRateWireDefaultsValidationAndRoundTrip() throws {
        for json in ["{}", #"{"infinityBotSpawnRate":0}"#, #"{"infinityBotSpawnRate":3}"#] {
            XCTAssertEqual(try JSONDecoder().decode(RoomRules.self, from: Data(json.utf8)).infinityBotSpawnRate, 2)
        }
        for rate in [0.5, 1.0, 2.0, 4.0] {
            var rules = RoomRules(); rules.infinityBotSpawnRate = rate
            XCTAssertEqual(try JSONDecoder().decode(RoomRules.self, from: JSONEncoder().encode(rules)).infinityBotSpawnRate, rate)
            XCTAssertEqual(rules.restoringModeDefaults().infinityBotSpawnRate, 2)
        }
    }

    private func arena(rate: Double = 2, configured: Int = 0) -> PracticeArena {
        let arena = PracticeArena(seed: 42, name: "Human", colorIndex: 0, botCount: configured)
        var rules = RoomRules(); rules.infinity = true; rules.infinityRandomBots = true
        rules.infinityBotSpawnRate = rate; rules.infinityBotDifficulty = "dumb"
        arena.configure(rules: rules)
        return arena
    }

    private func advance(_ arena: PracticeArena, seconds: Double) {
        for _ in 0..<Int((seconds * 10).rounded()) {
            for i in arena.snapshot.tanks.indices {
                if arena.snapshot.tanks[i].bot { arena.snapshot.tanks[i].cooldown = 100 }
                else { arena.snapshot.tanks[i].invulnerable = 100 }
            }
            arena.step(input: GameInput(), dt: 0.1)
        }
    }

    func testRoamingBotsSpawnGraduallyAtTheSelectedCadenceAndStopAtSixteen() {
        let slow = arena(rate: 0.5), fast = arena(rate: 4)
        XCTAssertEqual(slow.snapshot.tanks.count, 1); XCTAssertEqual(fast.snapshot.tanks.count, 1)
        advance(slow, seconds: 2); advance(fast, seconds: 2)
        XCTAssertLessThan(slow.snapshot.tanks.count, fast.snapshot.tanks.count)
        advance(fast, seconds: 10)
        XCTAssertEqual(fast.snapshot.tanks.filter(\.bot).count, 16)
        XCTAssertEqual(Set(fast.snapshot.tanks.map(\.id)).count, 17)
    }

    func testEightHumanRoomHasAtMost128RoamingBotsWithStableUniqueIdentities() {
        let arena = arena(rate: 4)
        for number in 1..<8 { arena.snapshot.tanks.append(ArenaTank(id: number + 1, name: "Human \(number)", x: Double(number * 100) * 84 + 42, y: 42)) }
        var rules = RoomRules(); rules.infinity = true; rules.infinityRandomBots = true
        rules.infinityBotSpawnRate = 4; rules.infinityBotDifficulty = "dumb"
        arena.configure(rules: rules)
        advance(arena, seconds: 8)
        XCTAssertEqual(arena.snapshot.tanks.filter(\.bot).count, 128)
        XCTAssertEqual(Set(arena.snapshot.tanks.map(\.id)).count, 136)
        for human in arena.snapshot.tanks where !human.bot {
            XCTAssertEqual(arena.snapshot.tanks.filter { $0.bot && hypot($0.x - human.x, $0.y - human.y) < 16 * 84 }.count, 16)
        }
    }

    func testWaveServesEachLivingHumanAndRetiresOnlyStrayRoamersWithoutScoreChanges() {
        let arena = arena(configured: 1)
        let configured = arena.snapshot.tanks[1].id
        arena.snapshot.tanks.append(ArenaTank(id: 50, name: "Other human", x: 84 * 100 + 42, y: 42))
        // Reconfiguration recognizes newly added local controllers without
        // introducing an old roaming population into the configured roster.
        var rules = RoomRules(); rules.infinity = true; rules.infinityRandomBots = true
        arena.configure(rules: rules)
        arena.step(input: GameInput(), dt: 1 / 60)
        let roamers = arena.snapshot.tanks.filter { $0.bot && $0.id != configured }
        XCTAssertEqual(roamers.count, 2)
        for human in arena.snapshot.tanks where !human.bot {
            XCTAssertEqual(roamers.filter { hypot($0.x - human.x, $0.y - human.y) < 6 * 84 }.count, 1,
                "human \(human.id): \(human.x), roamers \(roamers.map { ($0.id, $0.x, $0.y) })")
        }
        let ids = Set(roamers.map(\.id))
        for i in arena.snapshot.tanks.indices where !arena.snapshot.tanks[i].bot {
            arena.snapshot.tanks[i].hp = 0; arena.snapshot.tanks[i].respawnTime = 999
            arena.snapshot.tanks[i].score = 12
        }
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(arena.snapshot.tanks.filter { ids.contains($0.id) }.count, 2, "A nearby human death retains the existing bot lives")
        for i in arena.snapshot.tanks.indices where !arena.snapshot.tanks[i].bot { arena.snapshot.tanks[i].x += 84 * 300 }
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertTrue(arena.snapshot.tanks.contains { $0.id == configured })
        XCTAssertFalse(arena.snapshot.tanks.contains { ids.contains($0.id) })
        XCTAssertTrue(arena.snapshot.tanks.filter { !$0.bot }.allSatisfy { $0.score == 12 })
    }
}
