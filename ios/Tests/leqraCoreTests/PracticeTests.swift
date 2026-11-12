import XCTest
@testable import leqraCore

final class PracticeTests: XCTestCase {
    private func solitary(_ power: String = "") -> PracticeArena {
        let arena = PracticeArena(seed: 42, name: "SNOW FOX", colorIndex: 0)
        var tank = ArenaTank(id: 1, name: "SNOW FOX", x: 42, y: 42, spawnSerial: 1)
        if !power.isEmpty { PracticeArena.applyPower(tank: &tank, kind: power) }
        arena.snapshot.tanks = [tank]
        return arena
    }

    func testSeededPracticeIsDeterministicAndPlayable() {
        let first = PracticeArena(seed: 42, name: "SNOW FOX", colorIndex: 2)
        let second = PracticeArena(seed: 42, name: "SNOW FOX", colorIndex: 2)
        for tick in 0..<600 {
            let input = GameInput(seq: UInt64(tick), forward: tick % 180 < 90, right: tick % 120 > 60, fire: tick % 10 < 5, touchAim: false)
            first.step(input: input, dt: 1 / 60); second.step(input: input, dt: 1 / 60)
        }
        XCTAssertEqual(first.snapshot, second.snapshot)
        XCTAssertEqual(first.snapshot.tanks.count, 9)
        XCTAssertEqual(first.snapshot.tanks[0].name, "SNOW FOX")
        XCTAssertLessThanOrEqual(first.snapshot.pickups.count, 6)
        XCTAssertEqual(first.snapshot.leaderboard.count, 9)
    }

    func testCannonPenetratesWallsBeyondEighteenCellsThenExpiresAtFivePointThreeSeconds() throws {
        let arena = solitary("cannon")
        arena.step(input: GameInput(fire: true), dt: 1 / 60)
        let bulletID = try XCTUnwrap(arena.snapshot.bullets.first).id
        for _ in 0..<119 { arena.step(input: GameInput(), dt: 1 / 60) }
        let travelled = try XCTUnwrap(arena.snapshot.bullets.first { $0.id == bulletID })
        XCTAssertGreaterThan(travelled.x - 42, 18 * 84)
        XCTAssertEqual(travelled.bounces, 0)
        for _ in 0..<198 { arena.step(input: GameInput(), dt: 1 / 60) }
        XCTAssertFalse(arena.snapshot.bullets.contains { $0.id == bulletID })
        XCTAssertEqual(arena.snapshot.tanks[0].hp, 1)
    }

    func testHomingAndCannonContactEmitImpactBeforeDamageInBothArenas() {
        let world = ArenaWorld(width: 588, height: 588, cols: 7, rows: 7)
        for fixed in [false, true] {
            for power in ["homing", "cannon"] {
                let arena = PracticeArena(seed: 42, name: "SNOW FOX", colorIndex: 0, botCount: 0, world: fixed ? world : nil)
                var shooter = ArenaTank(id: 1, x: 42, y: 42)
                PracticeArena.applyPower(tank: &shooter, kind: power)
                arena.snapshot.tanks = [shooter, ArenaTank(id: 2, x: 80, y: 42)]
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                let contact = arena.snapshot.effects.filter { $0.owner == 1 && ["impact", "hit"].contains($0.kind) }
                XCTAssertEqual(contact.map(\.kind), ["impact", "hit"], "\(power), finite=\(fixed)")
                XCTAssertEqual(arena.snapshot.tanks[1].hp, 0)
            }
        }
    }

    func testFiniteHomingExpiryEmitsImpactWithoutChangingInfinityExpiry() {
        let world = ArenaWorld(width: 168, height: 168, cols: 2, rows: 2)
        for fixed in [false, true] {
            let arena = PracticeArena(seed: 42, name: "SNOW FOX", colorIndex: 0, botCount: 0, world: fixed ? world : nil)
            var shooter = ArenaTank(id: 1, x: 42, y: 42)
            PracticeArena.applyPower(tank: &shooter, kind: "homing")
            arena.snapshot.tanks = [shooter]
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            var impacts = 0
            for _ in 0..<420 {
                arena.step(input: GameInput(), dt: 1 / 60)
                impacts = max(impacts, arena.snapshot.effects.filter { $0.kind == "impact" }.count)
            }
            XCTAssertEqual(impacts, fixed ? 1 : 0)
            XCTAssertTrue(arena.snapshot.bullets.isEmpty)
            XCTAssertEqual(arena.snapshot.tanks[0].hp, 1)
        }
    }

    func testStarmanPreservesAmmoWeaponLifetimeAndIgnoresCooldown() {
        let arena = solitary("cannon")
        PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "starman")
        for _ in 0..<10 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
        XCTAssertEqual(arena.snapshot.bullets.count, 10)
        XCTAssertEqual(arena.snapshot.tanks[0].charges, 3)
        XCTAssertEqual(arena.snapshot.tanks[0].powerTime, 15)
        XCTAssertEqual(arena.snapshot.tanks[0].cooldown, 0)
        XCTAssertEqual(arena.snapshot.tanks[0].ammoUsed, 0)
    }

    func testGrenadeHoldDoesNotDetonateUntilNextPress() {
        let arena = solitary("grenade")
        for _ in 0..<6 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
        XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind == "grenade" }.count, 1)
        arena.step(input: GameInput(), dt: 1 / 60)
        arena.step(input: GameInput(fire: true), dt: 1 / 60)
        XCTAssertTrue(arena.snapshot.bullets.isEmpty)
        XCTAssertTrue(arena.snapshot.effects.contains { $0.kind == "blast" })
        XCTAssertEqual(arena.snapshot.tanks[0].hp, 1)
    }

    func testRespawnWaitsOneSecondAndPreservesIdentityScore() {
        let arena = solitary()
        arena.snapshot.tanks[0].hp = 0
        arena.snapshot.tanks[0].score = 12
        arena.snapshot.tanks[0].respawnTime = 1
        for _ in 0..<59 { arena.step(input: GameInput(), dt: 1 / 60) }
        XCTAssertEqual(arena.snapshot.tanks[0].hp, 0)
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(arena.snapshot.tanks[0].hp, 1)
        XCTAssertEqual(arena.snapshot.tanks[0].name, "SNOW FOX")
        XCTAssertEqual(arena.snapshot.tanks[0].score, 12)
        XCTAssertEqual(arena.snapshot.tanks[0].spawnSerial, 2)
        XCTAssertTrue(arena.snapshot.tanks[0].spawnProtected)
    }

    func testPowerupsStackToFiveAndStarmanDoesNotShortenGhost() {
        var tank = ArenaTank()
        for _ in 0..<10 { PracticeArena.applyPower(tank: &tank, kind: "shield"); PracticeArena.applyPower(tank: &tank, kind: "speed") }
        XCTAssertEqual(tank.shieldCharges, 5); XCTAssertEqual(tank.speedStacks, 5)
        PracticeArena.applyPower(tank: &tank, kind: "ghost")
        PracticeArena.applyPower(tank: &tank, kind: "starman")
        XCTAssertEqual(tank.ghostTime, 15)
        XCTAssertEqual(tank.starmanTime, 8)
        XCTAssertFalse(tank.spawnProtected)
    }

    func testStarmanContactBypassesShieldAndSpawnProtection() {
        let arena = solitary()
        PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "starman")
        arena.snapshot.tanks.append(ArenaTank(id: 2, name: "CORAL", x: 68, y: 42, colorIndex: 1,
                                             spawnProtected: true, invulnerable: 1, shield: 15, shieldCharges: 3))
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(arena.snapshot.tanks[1].hp, 0)
        XCTAssertEqual(arena.snapshot.tanks[0].score, 1)
        XCTAssertEqual(arena.snapshot.tanks[1].score, -1)
        XCTAssertEqual(arena.snapshot.tanks[1].killedBy, "SNOW FOX")
    }

    func testStarmanContactCannotCrossWallFromPhasedAttacker() throws {
        let arena = solitary()
        let wall = try XCTUnwrap(arena.maze.walls(x0: 0, y0: 0, x1: 100, y1: 100).first { $0.axis == "h" })
        let x = wall.x + wall.w / 2, y = wall.line
        arena.snapshot.tanks[0].x = x; arena.snapshot.tanks[0].y = y
        PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "starman")
        arena.snapshot.tanks.append(ArenaTank(id: 2, name: "CORAL", x: x, y: y + 24, colorIndex: 1))
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(arena.snapshot.tanks[1].hp, 1)
    }

    func testGrenadeDragMatchesIntegratedCurveAcrossStepSizes() {
        let whole = PracticeArena.grenadeDragFactor(lifeBefore: 10, lifeAfter: 0)
        var split = 1.0
        for tick in 0..<600 {
            split *= PracticeArena.grenadeDragFactor(lifeBefore: 10 - Double(tick) / 60,
                                                     lifeAfter: 10 - Double(tick + 1) / 60)
        }
        XCTAssertEqual(whole, exp(-0.25 - 2), accuracy: 1e-12)
        XCTAssertEqual(split, whole, accuracy: 1e-12)
        XCTAssertGreaterThan(PracticeArena.grenadeDragFactor(lifeBefore: 4, lifeAfter: 3), 0.97)
        XCTAssertLessThan(PracticeArena.grenadeDragFactor(lifeBefore: 1, lifeAfter: 0), 0.3)
    }

    func testBotCollectingGrenadeWhileHoldingFireGetsFreshThrowEdge() {
        let arena = solitary()
        arena.snapshot.tanks[0].x = 22; arena.snapshot.tanks[0].y = 22
        arena.snapshot.tanks.append(ArenaTank(id: 2, name: "ROVER", x: 62, y: 62, angle: -3 * .pi / 4, bot: true))
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertTrue(arena.snapshot.bullets.contains { $0.owner == 2 && $0.kind.isEmpty })
        // Isolate the held-button transition with a ready weapon; collection
        // itself preserves any still-active cooldown, as on the server.
        arena.snapshot.tanks[1].cooldown = 0
        arena.snapshot.pickups = [ArenaPickup(id: 999, x: 62, y: 62, type: "grenade")]
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(arena.snapshot.tanks[1].power, "grenade")
        XCTAssertEqual(arena.snapshot.tanks[1].charges, 2)
        XCTAssertTrue(arena.snapshot.bullets.contains { $0.owner == 2 && $0.kind == "grenade" })
    }

    func testInfinityConfiguredRosterRandomBotsAndFiniteArsenalIndependence() {
        let arena = PracticeArena(seed: 42, name: "SNOW FOX", colorIndex: 0, botCount: 3)
        var rules = RoomRules(); rules.infinity = true; rules.infinityRandomBots = true
        rules.infinityBotDifficulty = "hard"; rules.infinityRandomDifficulty = true; rules.pickupRate = "off"; rules.weapons = []
        arena.configure(rules: rules)
        XCTAssertEqual(arena.snapshot.tanks.count, 12)
        arena.configure(rules: rules)
        XCTAssertEqual(arena.snapshot.tanks.count, 12)
        XCTAssertTrue(arena.snapshot.tanks.dropFirst(4).allSatisfy { ["easy", "normal", "hard"].contains($0.difficulty) })
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertFalse(arena.snapshot.pickups.isEmpty)
    }

    func testInfinityTeamScoreTargetUsesSumAndFreezesCompletedArena() {
        let arena = PracticeArena(seed: 42, name: "SNOW FOX", colorIndex: 0, botCount: 2)
        var rules = RoomRules(); rules.infinity = true; rules.infinityTarget = 5; rules.teamMode = "teams"
        rules.teamNames = ["BLUE FOXES", "CORAL FOXES", "TEAM 3", "TEAM 4"]
        arena.configure(rules: rules)
        arena.snapshot.tanks[0].score = 3
        arena.snapshot.tanks[2].score = 2
        arena.refreshStandings()
        XCTAssertEqual(arena.snapshot.result?.team, 1)
        XCTAssertEqual(arena.snapshot.result?.name, "BLUE FOXES")
        XCTAssertEqual(arena.snapshot.result?.score, 5)
        let finished = arena.snapshot
        for _ in 0..<120 { arena.step(input: GameInput(forward: true, fire: true), dt: 1 / 60) }
        XCTAssertEqual(arena.snapshot, finished)
        XCTAssertEqual(arena.presentationSnapshot(fraction: 0.5, localInput: GameInput(forward: true)), finished)
    }
}
