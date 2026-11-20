import XCTest

@testable import leqraCore

final class MissileTuningTests: XCTestCase {
    private func arena(finite: Bool, boosted: Bool = false) -> PracticeArena {
        let world = finite ? ArenaWorld(width: 1000, height: 1000) : nil
        let arena = PracticeArena(seed: 42, name: "RELOAD", colorIndex: 0, botCount: 0, world: world)
        arena.snapshot.tanks = [ArenaTank(id: 1, x: 42, y: 42, powerTime: 15, power: "homing", charges: 3)]
        if boosted {
            PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "starman", starDuration: 8)
        }
        return arena
    }

    func testFixedAndInfinityMissilesReloadInTwentyTwoTicksWithUnchangedSpeedAndLifetime() throws {
        for finite in [false, true] {
            let arena = arena(finite: finite)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks[0].cooldownTotal, 0.36, accuracy: 1e-12)
            XCTAssertEqual(arena.snapshot.tanks[0].charges, 2)
            let missile = try XCTUnwrap(arena.snapshot.bullets.first)
            XCTAssertEqual(missile.kind, "homing")
            XCTAssertEqual(hypot(missile.vx, missile.vy), 235, accuracy: 1e-8)
            let lifetime: Double = finite ? 2000.0 / 235 + 0.5 : 18.0 * 84 / 235
            XCTAssertEqual(missile.life, lifetime - 1.0 / 60, accuracy: 1e-8)
            for _ in 0..<21 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
            XCTAssertEqual(
                arena.snapshot.tanks[0].charges, 2, "A missile cannot fire before the new reload expires")
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks[0].charges, 1)
            XCTAssertTrue(arena.snapshot.effects.contains { $0.kind == "shot:homing" })
        }
    }

    func testMissileReadinessFallbackMatchesTheNewReloadAndKeepsThreeSlots() {
        for infinity in [false, true] {
            let tank = ArenaTank(id: 1, cooldown: 0.18, powerTime: 15, power: "homing", charges: 3)
            let readout = PilotReadout(tank: tank, snapshot: ArenaSnapshot(tanks: [tank]), infinity: infinity)
            XCTAssertEqual(readout.progress, 0.5, accuracy: 1e-12)
            XCTAssertEqual(readout.capacity, 3)
            XCTAssertEqual(readout.available, 3)
        }
    }

    func testStarmanMissilesKeepZeroReloadAndFreeCharges() {
        for finite in [false, true] {
            let arena = arena(finite: finite, boosted: true)
            var missiles = Set<Int>()
            for _ in 0..<8 {
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                missiles.formUnion(arena.snapshot.bullets.map(\.id))
            }
            let tank = arena.snapshot.tanks[0]
            XCTAssertEqual(tank.cooldown, 0)
            XCTAssertEqual(tank.cooldownTotal, 0)
            XCTAssertEqual(tank.charges, 3)
            XCTAssertEqual(missiles.count, 8)
            XCTAssertEqual(PilotReadout(tank: tank, snapshot: arena.snapshot, infinity: !finite).progress, 1)
        }
    }
}
