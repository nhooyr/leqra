import Foundation
import XCTest
@testable import leqraCore

final class HeldFireTests: XCTestCase {
    private func arena(fixed: Bool) -> PracticeArena {
        let arena = PracticeArena(seed: 42, name: "HOLD", colorIndex: 0, botCount: 0,
            world: fixed ? ArenaWorld(width: 1000, height: 1000) : nil)
        var rules = RoomRules(); rules.pickupRate = "off"; rules.infinityRandomBots = false
        arena.configure(rules: rules)
        arena.snapshot.tanks = [ArenaTank(id: 1, x: 42, y: 42)]
        return arena
    }

    func testHeldFireRetriesSpawnProtectionCooldownAndFullAmmoWithoutInventingPresses() {
        for fixed in [false, true] { for blocker in ["spawn", "cooldown", "full"] {
            let arena = arena(fixed: fixed)
            if blocker == "spawn" {
                arena.snapshot.tanks[0].spawnProtected = true; arena.snapshot.tanks[0].invulnerable = 0.1
            } else if blocker == "cooldown" { arena.snapshot.tanks[0].cooldown = 0.1 }
            else {
                // Populate the real authoritative quota, rather than mutating HUD counts.
                for _ in 0..<85 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
                XCTAssertEqual(arena.snapshot.tanks[0].ammoUsed, 5)
                arena.snapshot.tanks[0].cooldown = 0
            }
            let first = arena.snapshot.bullets.map(\.id)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.bullets.map(\.id), first, blocker)
            if blocker == "full" { arena.clearProjectiles() }
            for _ in 0..<7 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
            XCTAssertTrue(arena.snapshot.bullets.contains { !first.contains($0.id) }, "Held trigger must retry \(blocker), fixed=\(fixed)")
        } }
    }

    func testEveryPickupImmediatelyFiresItsNewWeaponDuringTheSameHold() {
        for fixed in [false, true] { for pickup in ["rapid", "scatter", "shield", "homing", "grenade", "speed", "laser", "cannon", "ghost", "starman"] {
            let arena = arena(fixed: fixed)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            let before = arena.snapshot.tanks[0], previous = arena.snapshot.bullets.map(\.id)
            arena.snapshot.pickups = [ArenaPickup(id: 9999, x: before.x, y: before.y, type: pickup)]
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            let after = arena.snapshot.tanks[0]
            XCTAssertEqual(after.ammoEpoch, 1, pickup)
            XCTAssertEqual(after.recoil, 1, accuracy: 1e-9, pickup)
            if pickup == "laser" { XCTAssertTrue(arena.snapshot.effects.contains { $0.kind == "laser" }) }
            else { XCTAssertTrue(arena.snapshot.bullets.contains { !previous.contains($0.id) && $0.ammoEpoch == 1 }, pickup) }
        } }
    }

    func testGrenadeAutoThrowKeepsReloadAndDetonatesOnlyOnAFreshPress() {
        for fixed in [false, true] { for star in [false, true] {
            let arena = arena(fixed: fixed)
            PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "grenade")
            if star { PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "starman") }
            for _ in 0..<48 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
            XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind == "grenade" }.count, star ? 48 : 1)
            XCTAssertFalse(arena.snapshot.effects.contains { $0.kind == "blast" })
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind == "grenade" }.count, star ? 49 : 2)
            arena.step(input: GameInput(), dt: 1 / 60)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertFalse(arena.snapshot.bullets.contains { $0.kind == "grenade" }, "Fresh press only pops, never also throws")
            XCTAssertTrue(arena.snapshot.effects.contains { $0.kind == "blast" })
            if !star { arena.snapshot.tanks[0].cooldown = 0 }
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind == "grenade" }.count, 1, "Hold retries on the next ready tick")
        } }
    }
}
