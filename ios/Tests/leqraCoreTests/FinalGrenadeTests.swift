import Foundation
import XCTest
@testable import leqraCore

final class FinalGrenadeTests: XCTestCase {
    private func arena(fixed: Bool, epoch: UInt64 = 0) -> PracticeArena {
        let arena = PracticeArena(seed: 42, name: "GRENADE", colorIndex: 0, botCount: 0,
            world: fixed ? ArenaWorld(width: 1000, height: 1000) : nil)
        var rules = RoomRules(); rules.pickupRate = "off"; arena.configure(rules: rules)
        arena.snapshot.tanks = [ArenaTank(id: 1, x: 42, y: 42, powerTime: 15, power: "grenade", charges: 1, ammoEpoch: epoch)]
        return arena
    }

    func testFinalGrenadeStaysRemotelyControllableWithoutUsingStandardAmmo() throws {
        for fixed in [false, true] { for epoch: UInt64 in [0, 9, ArenaTank.maximumAmmoEpoch] {
            let arena = arena(fixed: fixed, epoch: epoch)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            let grenade = try XCTUnwrap(arena.snapshot.bullets.first)
            let tank = arena.snapshot.tanks[0]
            XCTAssertEqual(tank.power, ""); XCTAssertEqual(tank.grenadeEpoch, epoch)
            XCTAssertEqual(tank.ammoEpoch, ArenaTank.nextAmmoEpoch(epoch))
            XCTAssertEqual(tank.ammoUsed, 0); XCTAssertEqual(tank.grenades, 1)
            let readout = PilotReadout(tank: tank, snapshot: arena.snapshot, infinity: !fixed)
            XCTAssertEqual(readout.available, 5); XCTAssertEqual(readout.readiness, "DETONATE READY")
            XCTAssertEqual(readout.fireHint, "TAP TO DETONATE, HOLD TO FIRE")
            for _ in 0..<4 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
            XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind == "grenade" }.map(\.id), [grenade.id])
            XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind.isEmpty }.count, 1, "The following held tick fires standard ammunition")
            arena.step(input: GameInput(), dt: 1 / 60)
            let standardIDs = arena.snapshot.bullets.filter { $0.kind.isEmpty }.map(\.id)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertFalse(arena.snapshot.bullets.contains { $0.kind == "grenade" })
            XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind.isEmpty }.map(\.id), standardIDs, "Detonation cannot also fire a shot in the same tick")
            XCTAssertNil(arena.snapshot.tanks[0].grenadeEpoch)
            XCTAssertTrue(arena.snapshot.effects.contains { $0.kind == "blast" })
            for _ in 0..<30 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
            XCTAssertGreaterThan(arena.snapshot.bullets.filter { $0.kind.isEmpty }.count, 1, "Held fire resumes after the existing standard cooldown")
        } }
    }

    func testActualPickupOrTimerRefillStartsAFreshCycleWithoutChangingOldFuse() throws {
        for fixed in [false, true] { for refill in ["shield", "speed", "ghost", "starman", "grenade", "shieldExpiry"] {
            let arena = arena(fixed: fixed)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            let grenade = try XCTUnwrap(arena.snapshot.bullets.first)
            if refill == "shieldExpiry" { arena.snapshot.tanks[0].shield = 0.001 }
            else { PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: refill) }
            arena.step(input: GameInput(), dt: 1 / 60)
            XCTAssertNil(arena.snapshot.tanks[0].grenadeEpoch)
            let old = try XCTUnwrap(arena.snapshot.bullets.first { $0.id == grenade.id })
            XCTAssertEqual(old.ammoEpoch, grenade.ammoEpoch)
            XCTAssertEqual(old.life, grenade.life - 1 / 60, accuracy: 1e-9)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertTrue(arena.snapshot.bullets.contains { $0.id == grenade.id }, refill)
            XCTAssertTrue(arena.snapshot.bullets.contains { $0.id != grenade.id }, refill)
        } }
    }

    func testOptionalGrenadeEpochDecodesZeroAndKeepsLegacyPacketsCompatible() throws {
        for value in ["", ",\"grenadeEpoch\":null", ",\"grenadeEpoch\":0", ",\"grenadeEpoch\":9"] {
            let tank = try JSONDecoder().decode(ArenaTank.self, from: Data(("{\"id\":1,\"ammoEpoch\":5" + value + "}").utf8))
            XCTAssertEqual(tank.grenadeEpoch, value.contains(":0") ? 0 : value.contains(":9") ? 9 : nil)
        }
    }
}
