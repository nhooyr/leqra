import XCTest

@testable import leqraCore

final class ShotgunTuningTests: XCTestCase {
    private func arena(finite: Bool, boosted: Bool = false) -> PracticeArena {
        let world = finite ? ArenaWorld(width: 1000, height: 1000) : nil
        let arena = PracticeArena(seed: 42, name: "RELOAD", colorIndex: 0, botCount: 0, world: world)
        arena.snapshot.tanks = [ArenaTank(id: 1, x: 42, y: 42, powerTime: 15, power: "scatter", charges: 5)]
        if boosted {
            PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "starman", starDuration: 8)
        }
        return arena
    }

    func testFixedAndInfinityShotgunReloadInSeventeenTicksWithoutChangingPellets() {
        for finite in [false, true] {
            let arena = arena(finite: finite)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks[0].cooldownTotal, 0.27, accuracy: 1e-12)
            XCTAssertEqual(arena.snapshot.tanks[0].charges, 4)
            XCTAssertEqual(arena.snapshot.bullets.count, 3)
            for pellet in arena.snapshot.bullets {
                XCTAssertEqual(pellet.kind, "scatter")
                XCTAssertEqual(hypot(pellet.vx, pellet.vy), 846, accuracy: 1e-8)
                XCTAssertEqual(pellet.life, 3.9 - 1 / 60, accuracy: 1e-8)
            }
            for _ in 0..<16 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
            XCTAssertEqual(
                arena.snapshot.tanks[0].charges, 4,
                "The next volley cannot fire before the new reload expires")
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks[0].charges, 3)
            XCTAssertTrue(arena.snapshot.effects.contains { $0.kind == "shot:scatter" })
        }
    }

    func testShotgunReadinessUsesTheNewFallbackAndRetainsItsAmmoCapacity() {
        for infinity in [false, true] {
            let tank = ArenaTank(id: 1, cooldown: 0.135, powerTime: 15, power: "scatter", charges: 5)
            let readout = PilotReadout(tank: tank, snapshot: ArenaSnapshot(tanks: [tank]), infinity: infinity)
            XCTAssertEqual(readout.progress, 0.5, accuracy: 1e-12)
            XCTAssertEqual(readout.capacity, 12)
        }
    }

    func testStarmanShotgunKeepsItsZeroReloadAndFreeCharges() {
        for finite in [false, true] {
            let arena = arena(finite: finite, boosted: true)
            var pellets = Set<Int>()
            for _ in 0..<8 {
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                pellets.formUnion(arena.snapshot.bullets.map(\.id))
            }
            let tank = arena.snapshot.tanks[0]
            XCTAssertEqual(tank.cooldown, 0)
            XCTAssertEqual(tank.cooldownTotal, 0)
            XCTAssertEqual(tank.charges, 5)
            XCTAssertEqual(pellets.count, 24)
            XCTAssertEqual(PilotReadout(tank: tank, snapshot: arena.snapshot, infinity: !finite).progress, 1)
        }
    }
}
