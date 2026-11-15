import Foundation
import XCTest
@testable import leqraCore

final class AmmoMagazineTests: XCTestCase {
    private func arena(finite: Bool) -> PracticeArena {
        let arena = PracticeArena(seed: 42, name: "REFILL", colorIndex: 0, botCount: 0,
            world: finite ? ArenaWorld(width: 1000, height: 1000) : nil)
        var rules = RoomRules(); rules.infinity = !finite; rules.pickupRate = "off"; rules.infinityRandomBots = false
        arena.configure(rules: rules)
        arena.snapshot.tanks[0] = ArenaTank(id: 1, name: "REFILL", x: 42, y: 42)
        return arena
    }

    func testEveryPickupRefillsTheCurrentWeaponAndClearsItsReadiness() {
        for kind in ["rapid", "scatter", "shield", "homing", "grenade", "speed", "laser", "cannon", "ghost", "starman"] {
            var tank = ArenaTank(id: 1, cooldown: 0.5, cooldownTotal: 0.8, powerTime: 15,
                power: "cannon", charges: 1, ammoUsed: 3, grenades: 1, ammoEpoch: 9)
            PracticeArena.applyPower(tank: &tank, kind: kind)
            XCTAssertEqual(tank.ammoEpoch, 10, kind)
            XCTAssertEqual(tank.cooldown, 0, kind); XCTAssertEqual(tank.cooldownTotal, 0, kind)
            XCTAssertEqual(tank.ammoUsed, 0, kind); XCTAssertEqual(tank.grenades, 0, kind)
            XCTAssertEqual(tank.charges, tank.power == "rapid" ? 0 : tank.power == "scatter" ? 5 : 3, kind)
            XCTAssertEqual(tank.machineRounds, kind == "rapid" ? 180 : 0, kind)
        }
        var standard = ArenaTank(cooldown: 0.3, ammoUsed: 5)
        PracticeArena.applyPower(tank: &standard, kind: "speed")
        XCTAssertEqual(PilotReadout(tank: standard, snapshot: ArenaSnapshot(tanks: [standard]), infinity: true).available, 5)
    }

    func testCollectingABuffFiresImmediatelyFromTheNewMagazineWhileOldShotsRemain() throws {
        for finite in [false, true] {
            let arena = arena(finite: finite)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            let old = try XCTUnwrap(arena.snapshot.bullets.first)
            let tank = arena.snapshot.tanks[0]
            arena.snapshot.pickups = [ArenaPickup(id: 9999, x: tank.x, y: tank.y, type: "shield")]
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks[0].ammoEpoch, 1)
            XCTAssertTrue(arena.snapshot.bullets.contains { $0.id == old.id && $0.ammoEpoch == 0 })
            XCTAssertTrue(arena.snapshot.bullets.contains { $0.id != old.id && $0.ammoEpoch == 1 })
            XCTAssertEqual(arena.snapshot.tanks[0].ammoUsed, 1)
        }
    }

    func testSimultaneousExpiryRefillsOnceAfterAllTimersAdvance() {
        for finite in [false, true] { for weaponExpires in [false, true] {
            let arena = arena(finite: finite)
            arena.snapshot.tanks[0] = ArenaTank(id: 1, x: 42, y: 42, cooldown: 0.8, cooldownTotal: 0.8,
                powerTime: weaponExpires ? 0.001 : 15, shield: 0.001, speedTime: 0.001,
                ghostTime: 0.001, starmanTime: 0.001, power: "cannon", charges: 1,
                shieldCharges: 1, speedStacks: 5, ammoUsed: 3, ammoEpoch: 7)
            arena.step(input: GameInput(), dt: 1 / 60)
            let tank = arena.snapshot.tanks[0]
            XCTAssertEqual(tank.ammoEpoch, 8); XCTAssertEqual(tank.cooldown, 0)
            XCTAssertEqual(tank.power, weaponExpires ? "" : "cannon")
            XCTAssertEqual(tank.charges, weaponExpires ? 0 : 3)
            XCTAssertEqual(tank.shield, 0); XCTAssertEqual(tank.speedTime, 0); XCTAssertEqual(tank.ghostTime, 0)
            XCTAssertEqual(tank.starmanTime, 0); XCTAssertEqual(tank.ammoUsed, 0)
        } }
    }

    func testEachIndependentTimerExpiryRefillsItsCurrentWeapon() {
        for finite in [false, true] { for timer in ["weapon", "shield", "speed", "ghost", "starman"] {
            let arena = arena(finite: finite)
            var tank = ArenaTank(id: 1, x: 42, y: 42, cooldown: 0.8, powerTime: 15, power: "cannon", charges: 1, ammoEpoch: 7)
            switch timer {
            case "weapon": tank.powerTime = 0.001
            case "shield": tank.shield = 0.001; tank.shieldCharges = 1
            case "speed": tank.speedTime = 0.001; tank.speedStacks = 5
            case "ghost": tank.ghostTime = 0.001
            default: tank.starmanTime = 0.001
            }
            arena.snapshot.tanks[0] = tank
            arena.step(input: GameInput(), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks[0].ammoEpoch, 8, timer)
            XCTAssertEqual(arena.snapshot.tanks[0].cooldown, 0, timer)
            XCTAssertEqual(arena.snapshot.tanks[0].charges, timer == "weapon" ? 0 : 3, timer)
        } }
    }

    func testEveryWeaponDepletionImmediatelyRestoresTheStandardMagazine() {
        for finite in [false, true] { for weapon in ["rapid", "scatter", "homing", "grenade", "laser", "cannon"] {
            let arena = arena(finite: finite)
            arena.snapshot.tanks[0] = ArenaTank(id: 1, x: 42, y: 42, powerTime: 15,
                power: weapon, charges: 1, machineRounds: weapon == "rapid" ? 1 : 0, ammoEpoch: 4)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            let tank = arena.snapshot.tanks[0]
            XCTAssertEqual(tank.power, "", weapon); XCTAssertEqual(tank.ammoEpoch, 5, weapon)
            XCTAssertEqual(tank.cooldown, 0, weapon); XCTAssertEqual(tank.cooldownTotal, 0, weapon)
            XCTAssertEqual(tank.ammoUsed, 0, weapon); XCTAssertEqual(tank.grenades, weapon == "grenade" ? 1 : 0, weapon)
            XCTAssertEqual(PilotReadout(tank: tank, snapshot: arena.snapshot, infinity: !finite).available, 5, weapon)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertFalse(arena.snapshot.bullets.contains { $0.kind.isEmpty && $0.ammoEpoch == 5 }, weapon)
            arena.step(input: GameInput(), dt: 1 / 60)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            if weapon == "grenade" {
                XCTAssertFalse(arena.snapshot.bullets.contains { $0.kind.isEmpty }, "The first new press pops the final grenade")
                arena.step(input: GameInput(), dt: 1 / 60)
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
            }
            XCTAssertTrue(arena.snapshot.bullets.contains { $0.kind.isEmpty && $0.ammoEpoch == 5 }, weapon)
        } }
    }

    func testEveryWeaponConsumesItsHoldOnDepletionOrExpiryEvenAcrossPassiveRefills() {
        for finite in [false, true] { for weapon in ["rapid", "scatter", "homing", "grenade", "laser", "cannon"] {
            for expires in [false, true] {
                let arena = arena(finite: finite)
                arena.snapshot.tanks[0] = ArenaTank(id: 1, x: 42, y: 42,
                    cooldown: expires ? 999 : 0, powerTime: expires ? 0.025 : 15,
                    power: weapon, charges: expires ? 3 : 1,
                    machineRounds: weapon == "rapid" ? (expires ? 100 : 1) : 0, ammoEpoch: 4)
                var feedback = LocalFireFeedback()
                _ = feedback.setFire(true, tank: arena.snapshot.tanks[0], generation: 1, now: 1)
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                let restored = arena.snapshot.tanks[0]
                let label = "\(weapon), finite=\(finite), expires=\(expires)"
                XCTAssertEqual(restored.power, "", label)
                XCTAssertEqual(restored.ammoEpoch, 5, label)
                XCTAssertEqual(restored.cooldown, 0, label)
                XCTAssertEqual(restored.ammoUsed, 0, label)
                XCTAssertFalse(LocalFireFeedback.ammoUnavailable(for: restored), label)
                XCTAssertFalse(feedback.setFire(true, tank: restored, generation: 1, now: 2), label)
                let tank = arena.snapshot.tanks[0]
                arena.snapshot.pickups = [ArenaPickup(id: 9999, x: tank.x, y: tank.y, type: "shield")]
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                arena.snapshot.tanks[0].shield = 0.001
                for _ in 0..<5 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
                XCTAssertEqual(arena.snapshot.tanks[0].ammoEpoch, 7, label)
                XCTAssertFalse(arena.snapshot.bullets.contains { $0.kind.isEmpty }, label)
                XCTAssertFalse(arena.snapshot.effects.contains { $0.kind == "shot:" }, label)
                arena.step(input: GameInput(), dt: 1 / 60)
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                XCTAssertTrue(arena.snapshot.bullets.contains { $0.kind.isEmpty && $0.ammoEpoch == 7 }, label)
                XCTAssertEqual(arena.snapshot.tanks[0].ammoUsed, 1, label)
            }
        } }
    }

    func testPassiveBuffExpiryKeepsTheCurrentWeaponFiringWhileHeld() {
        for finite in [false, true] { for weapon in ["rapid", "scatter", "homing", "grenade", "laser", "cannon"] {
            for buff in ["shield", "speed", "ghost", "starman"] {
                let arena = arena(finite: finite)
                arena.snapshot.tanks[0] = ArenaTank(id: 1, x: 42, y: 42, powerTime: 15,
                    power: weapon, charges: 3, machineRounds: weapon == "rapid" ? 100 : 0, ammoEpoch: 4)
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                switch buff {
                case "shield": arena.snapshot.tanks[0].shield = 0.001; arena.snapshot.tanks[0].shieldCharges = 1
                case "speed": arena.snapshot.tanks[0].speedTime = 0.001; arena.snapshot.tanks[0].speedStacks = 1
                case "ghost": arena.snapshot.tanks[0].ghostTime = 0.001
                default: arena.snapshot.tanks[0].starmanTime = 0.001
                }
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                XCTAssertEqual(arena.snapshot.tanks[0].power, weapon)
                XCTAssertEqual(arena.snapshot.tanks[0].ammoEpoch, 5)
                if weapon == "grenade" {
                    XCTAssertEqual(arena.snapshot.tanks[0].grenades, 0)
                    XCTAssertFalse(arena.snapshot.bullets.contains { $0.ammoEpoch == 5 })
                } else {
                    XCTAssertGreaterThan(arena.snapshot.tanks[0].recoil, 0.99)
                    XCTAssertEqual(arena.snapshot.tanks[0].ammoUsed, weapon == "laser" ? 0 : weapon == "scatter" ? 3 : 1)
                }
        } } }
    }

    func testFreshPressOnTheWeaponExpiryTickStillFiresStandardAmmo() {
        for finite in [false, true] { for weapon in ["rapid", "scatter", "homing", "grenade", "laser", "cannon"] {
            let arena = arena(finite: finite)
            arena.snapshot.tanks[0] = ArenaTank(id: 1, x: 42, y: 42,
                powerTime: 0.001, power: weapon, charges: 3, ammoEpoch: 4)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks[0].power, "")
            XCTAssertEqual(arena.snapshot.tanks[0].ammoEpoch, 5)
            XCTAssertTrue(arena.snapshot.bullets.contains { $0.kind.isEmpty && $0.ammoEpoch == 5 }, weapon)
        } }
    }

    func testCapturedReleaseAndRepressBetweenTicksUnlocksEveryDepletedWeapon() {
        for finite in [false, true] { for weapon in ["rapid", "scatter", "homing", "grenade", "laser", "cannon"] {
            for endsReleased in [false, true] {
                let arena = arena(finite: finite)
                arena.snapshot.tanks[0] = ArenaTank(id: 1, x: 42, y: 42, powerTime: 15,
                    power: weapon, charges: 1, machineRounds: weapon == "rapid" ? 1 : 0, ammoEpoch: 4)
                arena.captureFire(true, player: 1)
                arena.step(input: GameInput(fire: true), dt: 1 / 60)
                XCTAssertEqual(arena.snapshot.tanks[0].power, "")
                arena.captureFire(false, player: 1)
                arena.captureFire(true, player: 1)
                if endsReleased { arena.captureFire(false, player: 1) }
                arena.step(input: GameInput(fire: !endsReleased), dt: 1 / 60)
                if weapon == "grenade" {
                    XCTAssertFalse(arena.snapshot.bullets.contains { $0.kind.isEmpty }, "A quick press pops the final grenade instead")
                    arena.captureFire(false, player: 1)
                    arena.captureFire(true, player: 1)
                    if endsReleased { arena.captureFire(false, player: 1) }
                    arena.step(input: GameInput(fire: !endsReleased), dt: 1 / 60)
                }
                XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind.isEmpty && $0.ammoEpoch == 5 }.count, 1, weapon)
                for _ in 0..<5 { arena.step(input: GameInput(fire: !endsReleased), dt: 1 / 60) }
                XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind.isEmpty && $0.ammoEpoch == 5 }.count, 1, weapon)
            }
        } }
    }

    func testCapturedQuickTapIsConsumedOnceAndResetDoesNotDeferIt() {
        for finite in [false, true] {
            let arena = arena(finite: finite)
            arena.snapshot.tanks[0].power = "grenade"; arena.snapshot.tanks[0].powerTime = 15; arena.snapshot.tanks[0].charges = 3
            arena.captureFire(true, player: 1); arena.captureFire(false, player: 1)
            arena.step(input: GameInput(), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind == "grenade" }.count, 1)
            arena.step(input: GameInput(), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind == "grenade" }.count, 1)
            arena.captureFire(true, player: 1)
            arena.resetFireInput(player: 1)
            arena.step(input: GameInput(), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind == "grenade" }.count, 1)
            arena.snapshot.tanks[0].hp = 0
            arena.captureFire(true, player: 1)
            arena.snapshot.tanks[0].hp = 1
            arena.step(input: GameInput(), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind == "grenade" }.count, 1)
        }
    }

    func testFixedArenaForwardsRealPressEdgesOnlyDuringGameplay() {
        var rules = RoomRules(); rules.pickupRate = "off"
        let fixed = FixedArena(rules: rules, name: "EDGE", colorIndex: 0, botCount: 1, seed: 42)
        fixed.captureFire(true, player: 1)
        fixed.captureFire(false, player: 1)
        for _ in 0..<180 { fixed.step(input: GameInput(), dt: 1 / 60) }
        XCTAssertTrue(fixed.snapshot.bullets.isEmpty)
        fixed.combat.snapshot.tanks[0] = ArenaTank(id: 1, x: 42, y: 42, powerTime: 15, power: "grenade", charges: 3)
        fixed.combat.snapshot.tanks[1].cooldown = 999
        fixed.captureFire(true, player: 1)
        fixed.captureFire(false, player: 1)
        fixed.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(fixed.snapshot.bullets.filter { $0.kind == "grenade" }.count, 1)
        fixed.captureFire(true, player: 1)
        fixed.resetFireInput(player: 1)
        fixed.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(fixed.snapshot.bullets.filter { $0.kind == "grenade" }.count, 1)
    }

    func testLastGrenadeConsumesTheHoldAcrossRefillsUntilRelease() throws {
        for finite in [false, true] {
            let arena = arena(finite: finite)
            arena.snapshot.tanks[0] = ArenaTank(id: 1, x: 42, y: 42,
                powerTime: 15, power: "grenade", charges: 1, ammoEpoch: 4)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            let grenade = try XCTUnwrap(arena.snapshot.bullets.first { $0.kind == "grenade" })
            XCTAssertEqual(grenade.ammoEpoch, 4)
            XCTAssertEqual(arena.snapshot.tanks[0].power, "")
            XCTAssertEqual(arena.snapshot.tanks[0].ammoEpoch, 5)
            for _ in 0..<5 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
            XCTAssertFalse(arena.snapshot.bullets.contains { $0.kind.isEmpty })
            let tank = arena.snapshot.tanks[0]
            arena.snapshot.pickups = [ArenaPickup(id: 9999, x: tank.x, y: tank.y, type: "shield")]
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks[0].ammoEpoch, 6)
            arena.snapshot.tanks[0].shield = 0.001
            for _ in 0..<5 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
            XCTAssertEqual(arena.snapshot.tanks[0].ammoEpoch, 7)
            XCTAssertFalse(arena.snapshot.bullets.contains { $0.kind.isEmpty })
            XCTAssertTrue(arena.snapshot.bullets.contains { $0.id == grenade.id && $0.life > 0 })
            arena.step(input: GameInput(), dt: 1 / 60)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertTrue(arena.snapshot.bullets.contains { $0.kind.isEmpty && $0.ammoEpoch == 7 })
            XCTAssertEqual(arena.snapshot.tanks[0].ammoUsed, 1)
        }
    }

    func testOldProjectileStillHitsAfterRefillAndRespawnAdvancesTheEpoch() throws {
        let arena = arena(finite: true)
        arena.snapshot.tanks.append(ArenaTank(id: 2, name: "TARGET", x: 210, y: 42, cooldown: 999))
        arena.step(input: GameInput(fire: true), dt: 1 / 60)
        XCTAssertEqual(arena.snapshot.bullets.first?.ammoEpoch, 0)
        PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "shield")
        for _ in 0..<40 { arena.step(input: GameInput(), dt: 1 / 60) }
        XCTAssertEqual(arena.snapshot.tanks[1].hp, 0)
        XCTAssertEqual(arena.snapshot.tanks[0].score, 1)
        arena.snapshot.tanks[0].hp = 0; arena.snapshot.tanks[0].respawnTime = 0
        arena.snapshot.tanks[0].ammoEpoch = ArenaTank.maximumAmmoEpoch
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(arena.snapshot.tanks[0].ammoEpoch, 1)
        XCTAssertEqual(arena.snapshot.tanks[0].ammoUsed, 0)
    }

    func testBreakingTheLastShieldChargeRefillsWithoutChangingTheHitGeometry() {
        let arena = arena(finite: true)
        arena.snapshot.tanks.append(ArenaTank(id: 2, name: "TARGET", x: 210, y: 42,
            cooldown: 999, powerTime: 15, shield: 15, power: "cannon", charges: 1, shieldCharges: 1, ammoEpoch: 5))
        arena.step(input: GameInput(fire: true), dt: 1 / 60)
        for _ in 0..<40 { arena.step(input: GameInput(), dt: 1 / 60) }
        let target = arena.snapshot.tanks[1]
        XCTAssertEqual(target.hp, 1); XCTAssertEqual(target.shieldCharges, 0)
        XCTAssertEqual(target.ammoEpoch, 6); XCTAssertEqual(target.charges, 3); XCTAssertEqual(target.cooldown, 0)
        XCTAssertEqual(target.x, 210); XCTAssertEqual(target.y, 42)
    }

    func testStarmanRecyclingOnlyTrimsTheCurrentMagazineAndLeavesOldShotsAlive() {
        let arena = arena(finite: true)
        PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "cannon")
        PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "starman")
        for _ in 0..<116 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
        let previous = Set(arena.snapshot.bullets.map(\.id)), epoch = arena.snapshot.tanks[0].ammoEpoch
        XCTAssertEqual(previous.count, 115)
        PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "shield")
        for _ in 0..<130 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
        XCTAssertTrue(previous.isSubset(of: Set(arena.snapshot.bullets.map(\.id))))
        XCTAssertEqual(arena.snapshot.bullets.filter { $0.ammoEpoch != epoch }.count, 115)
        XCTAssertEqual(arena.snapshot.tanks[0].ammoUsed, 0)
    }

    func testRefillStartsAFreshGrenadeCycleAndLeavesOldGrenadesOnTheirFuse() throws {
        for finite in [false, true] {
            let arena = arena(finite: finite)
            PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "grenade")
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            let old = try XCTUnwrap(arena.snapshot.bullets.first { $0.kind == "grenade" })
            // Refill while holding Fire must not invent a new press edge.
            PracticeArena.applyPower(tank: &arena.snapshot.tanks[0], kind: "shield")
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.bullets.count, 1)
            XCTAssertEqual(arena.snapshot.tanks[0].grenades, 0)
            arena.step(input: GameInput(), dt: 1 / 60)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind == "grenade" }.count, 2)
            XCTAssertEqual(arena.snapshot.tanks[0].grenades, 1)
            arena.step(input: GameInput(), dt: 1 / 60)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.bullets.filter { $0.kind == "grenade" }.map(\.id), [old.id])
            XCTAssertEqual(arena.snapshot.tanks[0].grenades, 0)
            let previousEffect = arena.snapshot.effects.map(\.id).max() ?? 0
            var naturalBlast = false
            for _ in 0..<105 {
                arena.step(input: GameInput(), dt: 0.1)
                naturalBlast = naturalBlast || arena.snapshot.effects.contains { $0.id > previousEffect && $0.kind == "blast" }
            }
            XCTAssertFalse(arena.snapshot.bullets.contains { $0.id == old.id })
            XCTAssertTrue(naturalBlast)
        }
    }

    func testReadoutCountsOnlyCurrentMagazineBulletsAndGrenades() {
        let tank = ArenaTank(id: 1, powerTime: 15, power: "grenade", charges: 3, ammoEpoch: 3)
        let old = ArenaBullet(id: 1, owner: 1, kind: "grenade", life: 8, ammoEpoch: 2)
        let current = ArenaBullet(id: 2, owner: 1, kind: "grenade", life: 4, ammoEpoch: 3)
        for infinity in [false, true] {
            let stale = PilotReadout(tank: tank, snapshot: ArenaSnapshot(tanks: [tank], bullets: [old]), infinity: infinity)
            XCTAssertEqual(stale.available, 3); XCTAssertEqual(stale.fireHint, "TAP TO THROW")
            if !infinity {
                let active = PilotReadout(tank: tank, snapshot: ArenaSnapshot(tanks: [tank], bullets: [old, current]), infinity: false)
                XCTAssertEqual(active.available, 2); XCTAssertEqual(active.fireHint, "TAP TO DETONATE")
            }
        }
    }
}
