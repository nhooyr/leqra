import XCTest
@testable import leqraCore

final class LocalFireFeedbackTests: XCTestCase {
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
        cue.setFire(false, tank: tank, generation: 1, now: 1.001) // A down/up between render frames is retained.
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
        for (power, cadence) in [("", 0.34), ("rapid", 0.15), ("scatter", 0.27), ("homing", 0.36), ("cannon", 0.85 * 2 / 3), ("laser", 0.85 * 2 / 3)] {
            for boosted in [false, true] {
                var cue = LocalFireFeedback()
                let tank = ArenaTank(id: 1, starmanTime: boosted ? 8 : 0, power: power, charges: 0, machineRounds: 0, ammoUsed: 999)
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
            var cue = LocalFireFeedback(), blocked = normal
            switch reason {
            case "dead": blocked.hp = 0
            case "spawn": blocked.spawnProtected = true; blocked.invulnerable = 1
            case "cooldown": blocked.cooldown = 0.2
            case "grenade": blocked.power = "grenade"
            case "detonate": blocked.grenades = 1
            default: break
            }
            XCTAssertFalse(cue.setFire(true, tank: blocked, generation: 1, now: 1,
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
            var cue = LocalFireFeedback(), changed = tank
            cue.setFire(true, tank: tank, generation: 1, now: 1)
            if change == "death" { changed.hp = 0 }
            if change == "spawn" { changed.spawnSerial += 1 }
            if change == "owner" { changed.id = 2 }
            if change == "controls" { cue.reset() }
            XCTAssertEqual(cue.recoil(real: 0.25, tank: changed, generation: change == "generation" ? 2 : 1,
                now: 1.05, active: change != "inactive"), 0.25, change)
        }
        var first = LocalFireFeedback(), second = LocalFireFeedback()
        first.setFire(true, tank: tank, generation: 1, now: 1)
        XCTAssertEqual(second.recoil(real: 0, tank: ArenaTank(id: 2), generation: 1, now: 1), 0)
    }
}
