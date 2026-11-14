import Foundation
import XCTest
@testable import leqraCore

final class BotDifficultyTests: XCTestCase {
    func testDumbRetainsInitialReactionAndTriggerDelayWithEveryFrameReady() {
        var brain = DumbBotBrain(spawnedAt: 0)
        var shots: [Int] = []
        for tick in 0...432 {
            let time = Double(tick) / 60
            brain.decide(now: time, visibleAim: 0, targetID: 2, random: { 0.5 })
            // A weapon can be ready every tick, as with boosted Rapid Fire.
            if brain.fire(now: time, facing: 0, targetID: 2, protected: false) { shots.append(tick) }
        }
        XCTAssertEqual(shots, [108, 216, 324, 432])
    }

    func testDumbHesitatesForAnEntireDecisionAndKeepsInaccurateAimStale() {
        var brain = DumbBotBrain(spawnedAt: 0)
        var samples = [0.34, 0.8, 1.0, 0.8, 0.0]
        var consumed = 0
        let random = { () -> Double in consumed += 1; return samples.removeFirst() }
        XCTAssertTrue(brain.decide(now: 0, visibleAim: 0, targetID: 2, random: random))
        XCTAssertFalse(brain.attacks)
        XCTAssertEqual(consumed, 1)
        XCTAssertFalse(brain.decide(now: 0.89, visibleAim: 1, targetID: 2, random: random))
        XCTAssertFalse(brain.attacks)
        XCTAssertEqual(consumed, 1)
        XCTAssertTrue(brain.decide(now: 0.9, visibleAim: 0, targetID: 2, random: random))
        XCTAssertTrue(brain.attacks)
        XCTAssertEqual(brain.aim, 0.6, accuracy: 1e-12)
        XCTAssertFalse(brain.decide(now: 1.79, visibleAim: .pi / 2, targetID: 2, random: random))
        XCTAssertEqual(brain.aim, 0.6, accuracy: 1e-12)
        XCTAssertTrue(brain.decide(now: 1.8, visibleAim: .pi / 2, targetID: 2, random: random))
        XCTAssertEqual(brain.aim, .pi / 2 - 0.6, accuracy: 1e-12)
        XCTAssertFalse(brain.fire(now: 1.8, facing: .pi / 2, targetID: 2, protected: false))
        XCTAssertTrue(brain.fire(now: 1.8, facing: brain.aim, targetID: 2, protected: false))
    }

    func testDumbLosesAttackOnOcclusionAndProtectionDoesNotSpendItsTrigger() {
        var brain = DumbBotBrain(spawnedAt: 10)
        brain.decide(now: 10, visibleAim: 0, targetID: 2, random: { 0.5 })
        XCTAssertFalse(brain.fire(now: 11.79, facing: 0, targetID: 2, protected: false))
        XCTAssertFalse(brain.fire(now: 11.8, facing: 0, targetID: 2, protected: true))
        XCTAssertFalse(brain.fire(now: 11.8, facing: 0, targetID: nil, protected: false))
        XCTAssertFalse(brain.fire(now: 11.8, facing: 0, targetID: 3, protected: false))
        XCTAssertTrue(brain.fire(now: 11.8, facing: 0, targetID: 2, protected: false))
        brain.decide(now: 11.8, visibleAim: nil, targetID: nil, random: { XCTFail("Occlusion does not roll an attack"); return 0.5 })
        XCTAssertFalse(brain.attacks)
        XCTAssertNil(brain.targetID)
        XCTAssertFalse(brain.fire(now: 20, facing: 0, targetID: 2, protected: false))
    }

    func testNativeDumbRapidAndStarmanShotsKeepReactionDelay() {
        let world = ArenaWorld(width: 840, height: 840, cols: 10, rows: 10)
        for boosted in [false, true] {
            let arena = PracticeArena(seed: 42, name: "PILOT", colorIndex: 0, botCount: 0, world: world)
            var rules = RoomRules(); rules.pickupRate = "off"; rules.weapons = []
            arena.configure(rules: rules)
            var bot = ArenaTank(id: 2, name: "DUMB BOT", x: 650, y: 420, angle: .pi,
                                bot: true, spawnSerial: 1, difficulty: "dumb")
            PracticeArena.applyPower(tank: &bot, kind: "rapid")
            if boosted { PracticeArena.applyPower(tank: &bot, kind: "starman") }
            arena.snapshot.tanks = [ArenaTank(id: 1, name: "PILOT", x: 420, y: 420), bot]
            var seen = Set<Int>(), shots: [Int] = []
            for tick in 1...420 {
                // Keep the encounter alive without changing bot decisions or
                // weapon cooldowns, including when a real shot hits the pilot.
                arena.snapshot.tanks[0].hp = 1
                arena.snapshot.tanks[0].invulnerable = 0
                arena.snapshot.tanks[0].x = 420; arena.snapshot.tanks[0].y = 420
                arena.step(input: GameInput(), dt: 1 / 60)
                for event in arena.snapshot.effects where event.owner == 2 && event.kind.hasPrefix("shot") {
                    if seen.insert(event.id).inserted { shots.append(tick) }
                }
            }
            XCTAssertGreaterThanOrEqual(shots.count, 2, "boosted=\(boosted)")
            XCTAssertGreaterThanOrEqual(shots.first ?? 0, 108, "boosted=\(boosted)")
            for (first, second) in zip(shots, shots.dropFirst()) {
                XCTAssertGreaterThanOrEqual(second - first, 108, "boosted=\(boosted)")
            }
        }
    }

    func testDumbRoamingSelectionAndNormalDefaultsSurviveManyLives() {
        XCTAssertEqual(RoomRules().infinityBotDifficulty, "normal")
        XCTAssertEqual(RoomRules.modeDefaults("elimination").infinityBotDifficulty, "normal")
        XCTAssertEqual(NativeSeatSpec(kind: "bot", name: "BOT").difficulty, "normal")
        let normal = PracticeArena(seed: 42, name: "PILOT", colorIndex: 0, botCount: 1)
        for _ in 0..<110 {
            normal.snapshot.tanks[1].hp = 0; normal.snapshot.tanks[1].respawnTime = 0
            normal.step(input: GameInput(), dt: 1 / 60)
            XCTAssertEqual(normal.snapshot.tanks[1].difficulty, "normal")
        }
        let dumb = PracticeArena(seed: 42, name: "PILOT", colorIndex: 0, botCount: 0)
        var rules = RoomRules(); rules.infinity = true; rules.infinityRandomBots = true
        rules.infinityBotDifficulty = "dumb"; rules.infinityRandomDifficulty = true
        dumb.configure(rules: rules)
        XCTAssertEqual(dumb.snapshot.tanks.count, 9)
        XCTAssertTrue(dumb.snapshot.tanks.dropFirst().allSatisfy { $0.difficulty == "dumb" })
        dumb.configurePilot(id: 2, name: "CUSTOM", colorIndex: 1, difficulty: "godlike")
        dumb.snapshot.tanks[1].hp = 0; dumb.snapshot.tanks[1].respawnTime = 0
        dumb.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(dumb.snapshot.tanks[1].difficulty, "godlike")
    }

    func testActualWireTierControlsWarningRegardlessOfCallsign() throws {
        let data = Data(#"{"type":"state","tanks":[{"id":1,"name":"Godlike Bot 1","bot":false,"difficulty":"godlike"},{"id":2,"name":"Godlike Bot 2","bot":true,"difficulty":"normal"},{"id":3,"name":"PLAIN BOT","bot":true,"difficulty":"godlike"},{"id":4,"name":"DUMB BOT","bot":true,"difficulty":"dumb"},{"id":5,"name":"Godlike Bot 5","bot":true}],"bullets":[],"pickups":[],"leaderboard":[]}"#.utf8)
        let normalized = try SnapshotDecoder.normalized(data: data, previousWorld: nil)
        let state = try JSONDecoder().decode(ArenaSnapshot.self, from: normalized.data)
        XCTAssertEqual(state.tanks.map(\.difficulty), ["godlike", "normal", "godlike", "dumb", "normal"])
        XCTAssertEqual(state.tanks.map(\.botWarning), [nil, nil, "GODLIKE", nil, nil])
        XCTAssertEqual(try JSONDecoder().decode(ArenaTank.self, from: JSONEncoder().encode(state.tanks[3])).difficulty, "dumb")
    }

    func testDumbRoomCommandsRetainExplicitDifficulty() {
        let configure = NativeRoomCommand.configure(target: 2, member: 9, difficulty: "dumb").payload
        XCTAssertEqual(configure["difficulty"] as? String, "dumb")
        let preset = NativeRoomCommand.preset(rules: RoomRules(), roster: [NativeSeatSpec(kind: "bot", name: "DUMB BOT", difficulty: "dumb")]).payload
        XCTAssertEqual((preset["roster"] as? [[String: Any]])?.first?["difficulty"] as? String, "dumb")
    }
}
