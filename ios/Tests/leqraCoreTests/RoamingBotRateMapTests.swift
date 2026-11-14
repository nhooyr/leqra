import Foundation
import XCTest
@testable import leqraCore

final class RoamingBotRateMapTests: XCTestCase {
    func testDefaultsAndLegacyMigrationPreserveTotalCadenceAndFractionalChoices() throws {
        let defaults = RoomRules()
        XCTAssertEqual(defaults.effectiveInfinityBotSpawnRates, ["normal": 2])
        XCTAssertEqual(defaults.totalInfinityBotSpawnRate, 2)
        var rules = try JSONDecoder().decode(RoomRules.self, from: Data(#"{"infinityBotSpawnRate":1,"infinityBotDifficulty":"normal","infinityRandomDifficulty":true}"#.utf8))
        XCTAssertNil(rules.infinityBotSpawnRates)
        XCTAssertEqual(rules.effectiveInfinityBotSpawnRates, ["dumb": 1.0 / 3, "easy": 1.0 / 3, "normal": 1.0 / 3])
        XCTAssertEqual(rules.totalInfinityBotSpawnRate, 1, accuracy: 1e-12)
        XCTAssertTrue(rules.infinityBotSpawnRateChoices(for: "normal").contains(1.0 / 3))
        rules.setInfinityBotSpawnRate(4, for: "godlike")
        XCTAssertEqual(rules.infinityBotSpawnRates?["normal"], 1.0 / 3)
        XCTAssertEqual(rules.infinityBotSpawnRates?["godlike"], 4)
        XCTAssertEqual(try JSONDecoder().decode(RoomRules.self, from: JSONEncoder().encode(rules)), rules)
        XCTAssertEqual(rules.restoringModeDefaults().effectiveInfinityBotSpawnRates, ["normal": 2])

        var fixed = RoomRules(); fixed.infinityBotDifficulty = "hard"; fixed.infinityBotSpawnRate = 0.5
        XCTAssertEqual(fixed.effectiveInfinityBotSpawnRates, ["hard": 0.5])
        fixed.infinityRandomBots = false
        XCTAssertEqual(fixed.effectiveInfinityBotSpawnRates, ["hard": 0.5], "The master toggle retains configured rates")
    }

    func testExplicitEmptyOrZeroMapStaysOffAndOverridesLegacyFields() throws {
        for json in [#"{"infinityBotSpawnRates":{}}"#, #"{"infinityBotSpawnRates":{"normal":0},"infinityBotSpawnRate":4,"infinityBotDifficulty":"godlike"}"#] {
            let rules = try JSONDecoder().decode(RoomRules.self, from: Data(json.utf8))
            XCTAssertNotNil(rules.infinityBotSpawnRates)
            XCTAssertEqual(rules.totalInfinityBotSpawnRate, 0)
            XCTAssertNil(rules.infinityRoamingDifficulty(at: 0.5))
            let roundtrip = try JSONDecoder().decode(RoomRules.self, from: JSONEncoder().encode(rules))
            XCTAssertNotNil(roundtrip.infinityBotSpawnRates)
            XCTAssertEqual(roundtrip.totalInfinityBotSpawnRate, 0)
        }
    }

    func testMalformedSavedRatesAreSanitizedBeforeCommandEncoding() throws {
        var rules = RoomRules()
        rules.infinityBotSpawnRates = ["dumb": -1, "easy": .nan, "normal": 0.25, "hard": .infinity, "godlike": 5, "unknown": 2]
        XCTAssertEqual(rules.infinityBotSpawnRates, ["normal": 0.25])
        let payload = try XCTUnwrap(rules.command()["rules"] as? [String: Any])
        let rates = try XCTUnwrap(payload["infinityBotSpawnRates"] as? [String: Double])
        XCTAssertEqual(rates, ["normal": 0.25])
        let decoded = try JSONDecoder().decode(RoomRules.self, from: Data(#"{"infinityBotSpawnRates":{"dumb":-1,"normal":0.25,"hard":4.1,"other":2}}"#.utf8))
        XCTAssertEqual(decoded.infinityBotSpawnRates, ["normal": 0.25])
        rules.setInfinityBotSpawnRate(0, for: "normal")
        XCTAssertEqual(rules.totalInfinityBotSpawnRate, 0)
    }

    func testWeightedSelectionNeverSelectsOffTiersAndUsesSummedRates() {
        var rules = RoomRules(); rules.infinityBotSpawnRates = ["dumb": 0, "easy": 0.5, "normal": 1.5, "hard": 0, "godlike": 2]
        XCTAssertEqual(rules.totalInfinityBotSpawnRate, 4)
        var counts: [String: Int] = [:]
        for sample in 0..<4000 {
            let level = rules.infinityRoamingDifficulty(at: (Double(sample) + 0.5) / 4000)!
            counts[level, default: 0] += 1
        }
        XCTAssertEqual(counts, ["easy": 500, "normal": 1500, "godlike": 2000])
        XCTAssertEqual(rules.infinityRoamingDifficulty(at: 0), "easy")
        XCTAssertEqual(rules.infinityRoamingDifficulty(at: 1), "godlike")
        XCTAssertNil(rules.infinityRoamingDifficulty(at: .nan))
    }

    func testTargetedInfinityRequiresOppositionOrAnEnabledRate() {
        var rules = RoomRules(); rules.infinity = true; rules.infinityTarget = 5; rules.infinityRandomBots = true
        let human = NativeSeatSpec(kind: "human", name: "Human", team: 1)
        rules.infinityBotSpawnRates = [:]
        XCTAssertFalse(rules.infinityStartError(roster: [human]).isEmpty)
        XCTAssertTrue(rules.infinityStartError(roster: [human, NativeSeatSpec(kind: "bot", name: "Rust", team: 2)]).isEmpty)
        rules.teamMode = "teams"
        XCTAssertFalse(rules.infinityStartError(roster: [human, NativeSeatSpec(kind: "bot", name: "Ally", team: 1)]).isEmpty)
        XCTAssertFalse(rules.infinityStartError(roster: [human, NativeSeatSpec(kind: "human", name: "Watcher", team: 2, spectating: true)]).isEmpty)
        rules.infinityBotSpawnRates = ["easy": 0.25]
        XCTAssertTrue(rules.infinityStartError(roster: [human]).isEmpty)
        rules.infinityRandomBots = false
        XCTAssertFalse(rules.infinityStartError(roster: [human]).isEmpty)
        rules.infinityTarget = 0
        XCTAssertTrue(rules.infinityStartError(roster: [human]).isEmpty)
    }

    private func arena(rates: [String: Double], roster: Int = 0, enabled: Bool = true) -> PracticeArena {
        let arena = PracticeArena(seed: 42, name: "Human", colorIndex: 0, botCount: roster, difficulty: "hard")
        var rules = RoomRules(); rules.infinity = true; rules.infinityRandomBots = enabled; rules.infinityBotSpawnRates = rates
        arena.configure(rules: rules)
        return arena
    }
    private func advance(_ arena: PracticeArena, seconds: Double) {
        for _ in 0..<Int(seconds * 60) {
            for index in arena.snapshot.tanks.indices {
                if arena.snapshot.tanks[index].bot { arena.snapshot.tanks[index].cooldown = 999 }
                else { arena.snapshot.tanks[index].invulnerable = 999 }
            }
            arena.step(input: GameInput(), dt: 1 / 60)
        }
    }

    func testActualWaveCadenceUsesTotalRateAndRetainsSharedBudget() {
        let slow = arena(rates: ["dumb": 0.25, "normal": 0.25]), fast = arena(rates: ["dumb": 2, "normal": 2])
        advance(slow, seconds: 2); advance(fast, seconds: 2)
        XCTAssertGreaterThan(fast.snapshot.tanks.filter(\.bot).count, slow.snapshot.tanks.filter(\.bot).count)
        advance(fast, seconds: 12)
        XCTAssertEqual(fast.snapshot.tanks.filter(\.bot).count, 16)
        XCTAssertTrue(fast.snapshot.tanks.filter(\.bot).allSatisfy { ["dumb", "normal"].contains($0.difficulty) })
    }

    func testEachAmbientRespawnReselectsEnabledTierWhileRosterBotsKeepTheirTier() {
        let arena = arena(rates: ["dumb": 4], roster: 1)
        let roster = arena.snapshot.tanks[1].id
        arena.step(input: GameInput(), dt: 1 / 60)
        let ambient = arena.snapshot.tanks.last!.id
        XCTAssertNotEqual(roster, ambient)
        for _ in 0..<30 {
            for index in arena.snapshot.tanks.indices where [roster, ambient].contains(arena.snapshot.tanks[index].id) {
                arena.snapshot.tanks[index].difficulty = "godlike"
                arena.snapshot.tanks[index].hp = 0; arena.snapshot.tanks[index].respawnTime = 0
            }
            arena.step(input: GameInput(), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks.first(where: { $0.id == ambient })?.difficulty, "dumb")
            XCTAssertEqual(arena.snapshot.tanks.first(where: { $0.id == roster })?.difficulty, "godlike")
        }
    }

    func testAllOffAndMasterOffRetireAmbientBotsWithoutRemovingAuthoredRoster() {
        for enabled in [true, false] {
            let arena = arena(rates: ["normal": 4], roster: 1)
            let roster = arena.snapshot.tanks[1].id
            advance(arena, seconds: 1)
            XCTAssertGreaterThan(arena.snapshot.tanks.filter(\.bot).count, 1)
            var rules = RoomRules(); rules.infinity = true; rules.infinityRandomBots = enabled
            rules.infinityBotSpawnRates = enabled ? [:] : ["normal": 4]
            arena.configure(rules: rules)
            advance(arena, seconds: 3)
            XCTAssertEqual(arena.snapshot.tanks.filter(\.bot).map(\.id), [roster])
            XCTAssertEqual(rules.totalInfinityBotSpawnRate, enabled ? 0 : 4)
        }
    }
}
