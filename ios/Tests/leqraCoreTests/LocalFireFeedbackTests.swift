import XCTest

@testable import leqraCore

final class LocalFireFeedbackTests: XCTestCase {
    func testEarlyRepressAgainstOldWeaponAuthorityCannotSuppressTheRealStandardShot() throws {
        for infinity in [false, true] {
            for power in ["rapid", "scatter", "homing", "grenade", "laser", "cannon"] {
                var feedback = LocalFireFeedback()
                var router = AudioEventRouter()
                let timeline = RenderTimeline(localID: 1) { _, _, _ in }
                var old = ArenaTank(
                    id: 1, powerTime: 15, power: power, charges: 1, machineRounds: 1, ammoEpoch: 4)
                let before = ArenaSnapshot(tanks: [old])
                timeline.accept(before, at: 1)
                _ = router.consume(snapshot: before, localID: 1, infinity: infinity, online: true, now: 1)
                XCTAssertEqual(feedback.setFire(true, tank: old, generation: 0, now: 1), power != "grenade")
                _ = timeline.inputEdgePacket(GameInput(fire: true), now: 1)
                feedback.setFire(false, tank: old, generation: 0, now: 1.01)
                let up = try XCTUnwrap(timeline.inputEdgePacket(GameInput(), now: 1.01))
                old.cooldown = 0.5
                let down = try XCTUnwrap(timeline.inputEdgePacket(GameInput(fire: true), now: 1.02))
                XCTAssertFalse(feedback.setFire(true, tank: old, generation: 0, now: 1.02))
                XCTAssertEqual([up.fire, down.fire], [false, true])
                XCTAssertEqual([up.seq, down.seq], [2, 3])
                let standard = ArenaTank(id: 1, recoil: 1, ammoUsed: 1, ammoEpoch: 5)
                let fired = ArenaSnapshot(
                    tick: 1, tanks: [standard],
                    bullets: [ArenaBullet(id: 1, owner: 1, life: 5, ammoEpoch: 5)],
                    effects: [ArenaEffect(id: 1, kind: "shot:", owner: 1)])
                let unchanged = fired
                XCTAssertEqual(
                    feedback.recoil(real: standard.recoil, tank: standard, generation: 0, now: 1.03), 1)
                XCTAssertEqual(
                    router.consume(snapshot: fired, localID: 1, infinity: infinity, online: true, now: 1.03),
                    [.init(cue: .regular)])
                XCTAssertEqual(
                    router.consume(snapshot: fired, localID: 1, infinity: infinity, online: true, now: 1.04),
                    [])
                XCTAssertEqual(fired, unchanged)
            }
        }
    }

    func testDryFireClassifiesCurrentMagazineBoundariesWithoutChangingAuthority() {
        let cases: [(String, Int, Int, Int, Bool)] = [
            ("", 4, 0, 0, false), ("", 5, 0, 0, true),
            ("scatter", 9, 1, 0, false), ("scatter", 10, 1, 0, true), ("scatter", 0, 0, 0, true),
            ("rapid", 114, 0, 1, false), ("rapid", 115, 0, 1, true), ("rapid", 0, 0, 0, true),
            ("homing", 2, 1, 0, false), ("homing", 3, 1, 0, true), ("homing", 0, 0, 0, true),
            ("cannon", 2, 1, 0, false), ("cannon", 3, 1, 0, true), ("cannon", 0, 0, 0, true),
            ("laser", 3, 1, 0, false), ("laser", 0, 0, 0, true),
            ("grenade", 2, 1, 0, false), ("grenade", 3, 1, 0, true), ("grenade", 0, 0, 0, true),
        ]
        for (power, used, charges, rounds, expected) in cases {
            let tank = ArenaTank(
                id: 1, power: power, charges: charges, machineRounds: rounds,
                ammoUsed: used, ammoEpoch: 9)
            let before = tank
            XCTAssertEqual(
                LocalFireFeedback.ammoUnavailable(for: tank), expected,
                "\(power), used=\(used), charges=\(charges), rounds=\(rounds)")
            XCTAssertEqual(tank, before)
            var boosted = tank
            boosted.starmanTime = 1
            XCTAssertFalse(LocalFireFeedback.ammoUnavailable(for: boosted, stateAge: 0.5), power)
            XCTAssertEqual(LocalFireFeedback.ammoUnavailable(for: boosted, stateAge: 1), expected, power)
        }
        // A newly refilled epoch has empty occupancy even while older shots
        // remain in the renderer; do not reconstruct quota from those shots.
        XCTAssertFalse(
            LocalFireFeedback.ammoUnavailable(for: ArenaTank(ammoUsed: 0, ammoEpoch: 10), stateAge: 10))
        XCTAssertTrue(LocalFireFeedback.ammoUnavailable(for: ArenaTank(ammoUsed: 5), stateAge: 10))
    }

    func testDryFireRequiresAnAcceptedFreshEmptyPressAndNeverDuplicatesARealShot() {
        var feedback = LocalFireFeedback()
        let empty = ArenaTank(id: 1, ammoUsed: 5)
        func press(_ down: Bool, _ tank: ArenaTank, _ now: Double, active: Bool = true, age: Double = 0)
            -> Bool
        {
            feedback.setFire(down, tank: tank, generation: 1, now: now, stateAge: age, active: active)
                && LocalFireFeedback.ammoUnavailable(for: tank, stateAge: age)
        }
        XCTAssertTrue(press(true, empty, 1))
        XCTAssertFalse(press(true, empty, 2))
        XCTAssertFalse(press(false, empty, 2))
        XCTAssertTrue(press(true, empty, 2))
        XCTAssertFalse(press(false, empty, 2.01))
        XCTAssertFalse(press(true, empty, 2.2))
        feedback.reset()
        XCTAssertFalse(press(true, ArenaTank(id: 1, ammoUsed: 4), 3))
        feedback.reset()
        var boosted = empty
        boosted.starmanTime = 1
        XCTAssertFalse(press(true, boosted, 4))
        for reason in ["dead", "inactive", "spawn", "cooldown", "grenade", "detonate"] {
            feedback.reset()
            var tank = empty
            switch reason {
            case "dead": tank.hp = 0
            case "spawn":
                tank.spawnProtected = true
                tank.invulnerable = 1
            case "cooldown": tank.cooldown = 0.2
            case "grenade": tank.power = "grenade"
            case "detonate": tank.grenades = 1
            default: break
            }
            XCTAssertFalse(press(true, tank, 5, active: reason != "inactive"), reason)
            XCTAssertFalse(press(true, empty, 6), reason)  // No deferred click from a consumed press.
        }
        feedback.reset()
        var cooling = empty
        cooling.cooldown = 0.2
        XCTAssertTrue(press(true, cooling, 7, age: 0.2))
    }

    func testRejectedPacketsCannotReplaceTheAuthorityOrRefreshItsCooldownClock() {
        let timeline = RenderTimeline(localID: 1) { _, _, _ in }
        let current = ArenaSnapshot(tick: 60, tanks: [ArenaTank(id: 1, cooldown: 0.2)])
        timeline.accept(current, at: 1)
        timeline.accept(ArenaSnapshot(tick: 59, tanks: [ArenaTank(id: 1, hp: 0)]), at: 1.1)
        XCTAssertEqual(timeline.authoritativeSnapshot, current)
        XCTAssertEqual(timeline.authoritativeSnapshotTime, 1)
    }

    func testEmptyMagazinePressHasExactlyOneHundredMillisecondsOfCosmeticRecoil() {
        var cue = LocalFireFeedback()
        let tank = ArenaTank(id: 1, spawnSerial: 2, ammoUsed: 5)
        let unchanged = tank
        XCTAssertTrue(cue.setFire(true, tank: tank, generation: 1, now: 1))
        cue.setFire(false, tank: tank, generation: 1, now: 1.001)  // A down/up between render frames is retained.
        XCTAssertEqual(cue.recoil(real: 0, tank: tank, generation: 1, now: 1), 1, accuracy: 1e-12)
        XCTAssertEqual(cue.recoil(real: 0, tank: tank, generation: 1, now: 1.05), 0.5, accuracy: 1e-12)
        XCTAssertEqual(cue.recoil(real: 0, tank: tank, generation: 1, now: 1.1), 0, accuracy: 1e-12)
        XCTAssertEqual(cue.recoil(real: 0.8, tank: tank, generation: 1, now: 1.05), 0.8)
        XCTAssertEqual(tank, unchanged)
    }

    func testHoldingAndEarlyRepressDoNotRepeatWhileTheNextEligiblePressDoes() {
        var cue = LocalFireFeedback()
        let tank = ArenaTank(id: 1, ammoUsed: 5)
        XCTAssertTrue(cue.setFire(true, tank: tank, generation: 1, now: 1))
        XCTAssertFalse(cue.setFire(true, tank: tank, generation: 1, now: 2))
        XCTAssertEqual(cue.recoil(real: 0, tank: tank, generation: 1, now: 2), 0)
        cue.setFire(false, tank: tank, generation: 1, now: 2)
        XCTAssertTrue(cue.setFire(true, tank: tank, generation: 1, now: 2))
        cue.setFire(false, tank: tank, generation: 1, now: 2.01)
        XCTAssertFalse(cue.setFire(true, tank: tank, generation: 1, now: 2.2))
        cue.setFire(false, tank: tank, generation: 1, now: 2.3)
        XCTAssertTrue(cue.setFire(true, tank: tank, generation: 1, now: 2.34))
    }

    func testCadenceMatchesEveryWeaponAndStarmanWithoutCheckingAmmo() {
        for (power, cadence) in [
            ("", 0.34), ("rapid", 0.15), ("scatter", 0.27), ("homing", 0.36), ("cannon", 0.85 / 3),
            ("laser", 0.85 / 3),
        ] {
            for boosted in [false, true] {
                var cue = LocalFireFeedback()
                let tank = ArenaTank(
                    id: 1, starmanTime: boosted ? 8 : 0, power: power, charges: 0, machineRounds: 0,
                    ammoUsed: 999)
                let interval = boosted ? 0.065 : cadence
                XCTAssertTrue(cue.setFire(true, tank: tank, generation: 1, now: 1), power)
                cue.setFire(false, tank: tank, generation: 1, now: 1.001)
                XCTAssertFalse(cue.setFire(true, tank: tank, generation: 1, now: 1 + interval - 0.001), power)
                cue.setFire(false, tank: tank, generation: 1, now: 1 + interval - 0.0005)
                XCTAssertTrue(cue.setFire(true, tank: tank, generation: 1, now: 1 + interval), power)
            }
        }
    }

    func testBlockedPressesAreConsumedAndAuthorityTimeAgesCooldownAndProtection() {
        let normal = ArenaTank(id: 1, ammoUsed: 5)
        for reason in ["dead", "inactive", "spawn", "cooldown", "grenade", "detonate", "muzzle"] {
            var cue = LocalFireFeedback()
            var blocked = normal
            switch reason {
            case "dead": blocked.hp = 0
            case "spawn":
                blocked.spawnProtected = true
                blocked.invulnerable = 1
            case "cooldown": blocked.cooldown = 0.2
            case "grenade": blocked.power = "grenade"
            case "detonate": blocked.grenades = 1
            default: break
            }
            XCTAssertFalse(
                cue.setFire(
                    true, tank: blocked, generation: 1, now: 1,
                    active: reason != "inactive", muzzleBlocked: reason == "muzzle"), reason)
            XCTAssertFalse(cue.setFire(true, tank: normal, generation: 1, now: 2), reason)
            XCTAssertEqual(cue.recoil(real: 0, tank: normal, generation: 1, now: 2), 0, reason)
            cue.setFire(false, tank: normal, generation: 1, now: 2)
            XCTAssertTrue(cue.setFire(true, tank: normal, generation: 1, now: 2), reason)
        }
        var cue = LocalFireFeedback()
        let aged = ArenaTank(id: 1, spawnProtected: true, cooldown: 0.2, invulnerable: 0.1, ammoUsed: 5)
        XCTAssertTrue(cue.setFire(true, tank: aged, generation: 1, now: 1, stateAge: 0.2))
    }

    func testLifeGenerationOwnershipAndControlResetClearOnlyTheLocalCue() {
        let tank = ArenaTank(id: 1, spawnSerial: 2, ammoUsed: 5)
        for change in ["death", "spawn", "generation", "owner", "inactive", "controls"] {
            var cue = LocalFireFeedback()
            var changed = tank
            cue.setFire(true, tank: tank, generation: 1, now: 1)
            if change == "death" { changed.hp = 0 }
            if change == "spawn" { changed.spawnSerial += 1 }
            if change == "owner" { changed.id = 2 }
            if change == "controls" { cue.reset() }
            XCTAssertEqual(
                cue.recoil(
                    real: 0.25, tank: changed, generation: change == "generation" ? 2 : 1,
                    now: 1.05, active: change != "inactive"), 0.25, change)
        }
        var first = LocalFireFeedback()
        var second = LocalFireFeedback()
        first.setFire(true, tank: tank, generation: 1, now: 1)
        XCTAssertEqual(second.recoil(real: 0, tank: ArenaTank(id: 2), generation: 1, now: 1), 0)
    }
}
