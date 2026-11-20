import Foundation
import XCTest

@testable import leqraCore

final class FinalGrenadeTests: XCTestCase {
    func testGrenadeResolvesEveryVictimBeforeInfinityScoreTarget() throws {
        let arena = PracticeArena(seed: 42, name: "BOMBER", colorIndex: 0, botCount: 0)
        var rules = RoomRules()
        rules.infinity = true
        rules.infinityTarget = 1
        rules.infinityRandomBots = false
        arena.configure(rules: rules)
        arena.snapshot.tanks = [
            ArenaTank(id: 1, name: "BOMBER", x: 42, y: 42, powerTime: 15, power: "grenade", charges: 3)
        ]
        arena.step(input: GameInput(fire: true), dt: 1 / 60)
        arena.step(input: GameInput(), dt: 1 / 60)
        let grenade = try XCTUnwrap(arena.snapshot.bullets.first { $0.kind == "grenade" })
        arena.snapshot.tanks[0].invulnerable = 1
        for index in 2...4 {
            arena.snapshot.tanks.append(
                ArenaTank(
                    id: index, name: "TARGET \(index)", x: grenade.x, y: grenade.y + Double(index) * 5,
                    bot: true, cooldown: 999))
        }
        arena.step(input: GameInput(fire: true), dt: 1 / 60)
        XCTAssertTrue(arena.snapshot.tanks.dropFirst().allSatisfy { $0.hp == 0 })
        XCTAssertEqual(arena.snapshot.tanks[0].score, 3)
        XCTAssertEqual(arena.snapshot.result?.id, 1)
        XCTAssertEqual(arena.snapshot.result?.score, 3)
    }

    private func arena(fixed: Bool, epoch: UInt64 = 0) -> PracticeArena {
        let arena = PracticeArena(
            seed: 42, name: "GRENADE", colorIndex: 0, botCount: 0,
            world: fixed ? ArenaWorld(width: 1000, height: 1000) : nil)
        var rules = RoomRules()
        rules.pickupRate = "off"
        arena.configure(rules: rules)
        arena.snapshot.tanks = [
            ArenaTank(id: 1, x: 42, y: 42, powerTime: 15, power: "grenade", charges: 1, ammoEpoch: epoch)
        ]
        return arena
    }

    func testFinalGrenadeStaysRemotelyControllableWithoutUsingStandardAmmo() throws {
        for fixed in [false, true] {
            for epoch: UInt64 in [0, 9, ArenaTank.maximumAmmoEpoch] {
                let arena = arena(fixed: fixed, epoch: epoch)
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                let grenade = try XCTUnwrap(arena.snapshot.bullets.first)
                let tank = arena.snapshot.tanks[0]
                XCTAssertEqual(tank.power, "")
                XCTAssertEqual(tank.grenadeEpoch, epoch)
                XCTAssertEqual(tank.ammoEpoch, ArenaTank.nextAmmoEpoch(epoch))
                XCTAssertEqual(tank.ammoUsed, 0)
                XCTAssertEqual(tank.grenades, 1)
                let readout = PilotReadout(tank: tank, snapshot: arena.snapshot, infinity: !fixed)
                XCTAssertEqual(readout.available, 5)
                XCTAssertEqual(readout.readiness, "DETONATE READY")
                XCTAssertEqual(readout.fireHint, "TAP TO DETONATE, HOLD TO FIRE")
                for _ in 0..<48 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
                XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind == "grenade" }.map(\.id), [grenade.id])
                XCTAssertEqual(
                    arena.snapshot.bullets.filter { $0.kind.isEmpty }.count, 1,
                    "Held fire resumes standard ammunition after reload")
                arena.step(input: GameInput(), dt: 1 / 60)
                let standardIDs = arena.snapshot.bullets.filter { $0.kind.isEmpty }.map(\.id)
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                XCTAssertFalse(arena.snapshot.bullets.contains { $0.kind == "grenade" })
                XCTAssertEqual(
                    arena.snapshot.bullets.filter { $0.kind.isEmpty }.map(\.id), standardIDs,
                    "Detonation cannot also fire a shot in the same tick")
                XCTAssertNil(arena.snapshot.tanks[0].grenadeEpoch)
                XCTAssertTrue(arena.snapshot.effects.contains { $0.kind == "blast" })
                for _ in 0..<30 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
                XCTAssertEqual(
                    arena.snapshot.bullets.filter { $0.kind.isEmpty }.map(\.id), standardIDs,
                    "Detonation consumes its whole held activation")
                arena.step(input: GameInput(), dt: 1 / 60)
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                XCTAssertGreaterThan(
                    arena.snapshot.bullets.filter { $0.kind.isEmpty }.count, standardIDs.count)
            }
        }
    }

    func testActualPickupOrTimerRefillStartsAFreshCycleWithoutChangingOldFuse() throws {
        for fixed in [false, true] {
            for refill in ["shield", "speed", "ghost", "starman", "grenade", "shieldExpiry"] {
                let arena = arena(fixed: fixed)
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                let grenade = try XCTUnwrap(arena.snapshot.bullets.first)
                if refill == "shieldExpiry" {
                    arena.snapshot.tanks[0].shield = 0.001
                } else {
                    PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: refill)
                }
                arena.step(input: GameInput(), dt: 1 / 60)
                XCTAssertNil(arena.snapshot.tanks[0].grenadeEpoch)
                let old = try XCTUnwrap(arena.snapshot.bullets.first { $0.id == grenade.id })
                XCTAssertEqual(old.ammoEpoch, grenade.ammoEpoch)
                XCTAssertEqual(old.life, grenade.life - 1 / 60, accuracy: 1e-9)
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                XCTAssertTrue(arena.snapshot.bullets.contains { $0.id == grenade.id }, refill)
                XCTAssertTrue(arena.snapshot.bullets.contains { $0.id != grenade.id }, refill)
            }
        }
    }

    func testOptionalGrenadeEpochDecodesZeroAndKeepsLegacyPacketsCompatible() throws {
        for value in ["", ",\"grenadeEpoch\":null", ",\"grenadeEpoch\":0", ",\"grenadeEpoch\":9"] {
            let tank = try JSONDecoder().decode(
                ArenaTank.self, from: Data(("{\"id\":1,\"ammoEpoch\":5" + value + "}").utf8))
            XCTAssertEqual(tank.grenadeEpoch, value.contains(":0") ? 0 : value.contains(":9") ? 9 : nil)
        }
    }
}
