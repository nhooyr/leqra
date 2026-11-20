import XCTest

@testable import leqraCore

final class CannonPiercingTests: XCTestCase {
    func testStationaryGestureFixtureKillsItsThreeTargets() {
        let arena = PracticeArena(
            seed: 42, name: "AIM TEST", colorIndex: 0, botCount: 0,
            initialTanks: [
                ArenaTank(
                    id: 1, name: "AIM TEST", x: 420, y: 420, invulnerable: 60, powerTime: 60, power: "cannon",
                    charges: 3)
            ]
                + (2...4).map {
                    ArenaTank(
                        id: $0, name: "TARGET \($0)", x: 420 + Double($0 - 1) * 60, y: 420, bot: true,
                        cooldown: 999)
                })
        var rules = RoomRules()
        rules.infinity = true
        rules.infinityRandomBots = false
        arena.configure(rules: rules)
        arena.botsStationary = true
        for _ in 0..<180 { arena.step(input: GameInput(), dt: 1 / 60) }
        arena.step(input: GameInput(fire: true), dt: 1 / 60)
        for _ in 0..<20 { arena.step(input: GameInput(), dt: 1 / 60) }
        XCTAssertEqual(arena.snapshot.tanks.dropFirst().map(\.hp), [0, 0, 0])
    }
    private func arena(fixed: Bool) -> PracticeArena {
        let arena = PracticeArena(
            seed: 42, name: "CANNON", colorIndex: 0, botCount: 0,
            world: fixed
                ? ArenaWorld(
                    width: 1000, height: 1000,
                    walls: [MazeWall(x: 115, y: 0, w: 10, h: 200, axis: "v", line: 120)]) : nil)
        var rules = RoomRules()
        rules.pickupRate = "off"
        rules.infinityRandomBots = false
        arena.configure(rules: rules)
        arena.respawnsEnabled = false
        arena.snapshot.tanks = [ArenaTank(id: 1, x: 42, y: 42, powerTime: 15, power: "cannon", charges: 1)]
        return arena
    }

    func testCannonPiercesEveryVictimAndWallWithoutEndingItsFlight() throws {
        for fixed in [false, true] {
            let arena = arena(fixed: fixed)
            for id in 2...4 {
                arena.snapshot.tanks.append(
                    ArenaTank(id: id, x: Double(id) * 75, y: 42, bot: true, cooldown: 999))
            }
            arena.step(input: GameInput(fire: true), dt: 0.1)
            let shot = try XCTUnwrap(arena.snapshot.bullets.first { $0.kind == "cannon" })
            for _ in 0..<3 { arena.step(input: GameInput(), dt: 0.1) }
            XCTAssertTrue(arena.snapshot.tanks.dropFirst().allSatisfy { $0.hp == 0 })
            XCTAssertTrue(arena.snapshot.bullets.contains { $0.id == shot.id })
            XCTAssertEqual(arena.snapshot.tanks[0].score, 3)
            XCTAssertEqual(arena.snapshot.tanks[0].hp, 1)
        }
    }

    func testCannonHitsAShieldOnlyOncePerLifeAndPreservesAlliesAndInvulnerableTanks() throws {
        for fixed in [false, true] {
            let arena = arena(fixed: fixed)
            arena.snapshot.tanks[0].team = 1
            arena.snapshot.tanks += [
                ArenaTank(id: 2, x: 100, y: 42, team: 1, bot: true, cooldown: 999),
                ArenaTank(id: 3, x: 165, y: 42, bot: true, cooldown: 999, invulnerable: 10),
                ArenaTank(
                    id: 4, x: 230, y: 42, bot: true, spawnSerial: 1, cooldown: 999, shield: 15,
                    shieldCharges: 3),
                ArenaTank(id: 5, x: 295, y: 42, bot: true, cooldown: 999),
            ]
            arena.step(input: GameInput(fire: true), dt: 0.1)
            for _ in 0..<16 { arena.step(input: GameInput(), dt: 1 / 60) }
            XCTAssertEqual(arena.snapshot.tanks[1].hp, 1)
            XCTAssertEqual(arena.snapshot.tanks[2].hp, 1)
            XCTAssertEqual(arena.snapshot.tanks[3].hp, 1)
            XCTAssertEqual(arena.snapshot.tanks[3].shieldCharges, 2)
            XCTAssertEqual(arena.snapshot.tanks[4].hp, 0)
            let shot = try XCTUnwrap(arena.snapshot.bullets.first { $0.kind == "cannon" })
            arena.snapshot.tanks[3].x = shot.x + 35
            arena.step(input: GameInput(), dt: 1 / 60)
            XCTAssertEqual(
                arena.snapshot.tanks[3].shieldCharges, 2,
                "The same shell cannot strip another charge from the same life")
            arena.snapshot.tanks[3].spawnSerial += 1
            arena.snapshot.tanks[3].x = arena.snapshot.bullets.first!.x + 35
            arena.snapshot.tanks[3].invulnerable = 0
            arena.step(input: GameInput(), dt: 1 / 60)
            XCTAssertEqual(
                arena.snapshot.tanks[3].shieldCharges, 1, "A new life can be hit by a surviving shell")
        }
    }

    func testWinningCannonResolvesWholeSweptSegmentBeforeScoreTargetFreezesMovement() {
        let arena = arena(fixed: false)
        var rules = RoomRules()
        rules.infinity = true
        rules.infinityTarget = 1
        rules.infinityRandomBots = false
        arena.configure(rules: rules)
        for id in 2...4 {
            arena.snapshot.tanks.append(
                ArenaTank(id: id, x: 75 + Double(id) * 20, y: 42, bot: true, cooldown: 999))
        }
        arena.step(input: GameInput(fire: true), dt: 0.1)
        XCTAssertTrue(arena.snapshot.tanks.dropFirst().allSatisfy { $0.hp == 0 })
        XCTAssertEqual(arena.snapshot.result?.score, 3)
        let stopped = arena.snapshot
        arena.step(input: GameInput(), dt: 0.1)
        XCTAssertEqual(arena.snapshot, stopped)
    }
}
