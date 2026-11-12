import XCTest
@testable import leqraCore

/// Expected strings and priorities follow renderPilotLoadout,
/// renderPilotReadiness, and renderInfinityLoadout in the owning web client.
final class ReadoutTests: XCTestCase {
    func testEveryWeaponUsesItsOwnCapacityAndLaserCharges() {
        for (power, capacity) in [("", 5), ("rapid", 115), ("scatter", 12), ("homing", 3),
                                  ("grenade", 3), ("laser", 3), ("cannon", 3)] {
            let tank = ArenaTank(id: 1, powerTime: 5, power: power, charges: 3, machineRounds: 180)
            let readout = PilotReadout(tank: tank, snapshot: ArenaSnapshot(tanks: [tank]), infinity: false)
            XCTAssertEqual(readout.capacity, capacity, power)
            XCTAssertEqual(readout.available, capacity, power)
        }
        let laser = ArenaTank(id: 1, powerTime: 4.01, power: "laser", charges: 2)
        let readout = PilotReadout(tank: laser, snapshot: ArenaSnapshot(tanks: [laser]), infinity: false)
        XCTAssertEqual(readout.available, 2)
        XCTAssertEqual(readout.weapon, "LASER ×2, 5s")
    }

    func testOrdinaryAmmoExcludesOtherOwnersAndBoostedShotsAfterStarmanEnds() {
        let tank = ArenaTank(id: 1)
        var snapshot = ArenaSnapshot(tanks: [tank], bullets: [
            ArenaBullet(id: 1, owner: 1), ArenaBullet(id: 2, owner: 1),
            ArenaBullet(id: 3, owner: 1), ArenaBullet(id: 4, owner: 2)
        ])
        snapshot.boostedBulletIds = [2, 3]
        let readout = PilotReadout(tank: tank, snapshot: snapshot, infinity: false)
        XCTAssertEqual(readout.available, 4)
        XCTAssertEqual(readout.weapon, "STANDARD")
        XCTAssertEqual(readout.readiness, "READY")
    }

    func testAuthoritativeAmmoCountSurvivesDelayedProjectilePresentation() {
        let tank = ArenaTank(id: 1, ammoUsed: 5)
        let readout = PilotReadout(tank: tank, snapshot: ArenaSnapshot(tanks: [tank]), infinity: false)
        XCTAssertEqual(readout.available, 0)
        XCTAssertEqual(readout.readiness, "WAITING FOR AMMO")
        XCTAssertEqual(readout.fireLabel, "WAIT")
    }

    func testMachineGunBudgetIsThreeSecondsAndIndependentOfHoldTimer() {
        let tank = ArenaTank(id: 1, powerTime: 15, power: "rapid", machineRounds: 180)
        let readout = PilotReadout(tank: tank, snapshot: ArenaSnapshot(tanks: [tank]), infinity: false)
        XCTAssertEqual(readout.capacity, 115)
        XCTAssertEqual(readout.firingSeconds, 3)
        XCTAssertEqual(readout.weapon, "MACHINE GUN, EXPIRES 15s")
        var partiallySpent = tank; partiallySpent.machineRounds = 114; partiallySpent.powerTime = 13
        XCTAssertEqual(PilotReadout(tank: partiallySpent, snapshot: ArenaSnapshot(), infinity: false).firingSeconds, 1.9)
    }

    func testStarmanOverridesCooldownAndAmmoAndHidesMachineBudget() {
        let tank = ArenaTank(id: 1, cooldown: 1, cooldownTotal: 1, powerTime: 15, starmanTime: 3.1,
                             power: "rapid", machineRounds: 12, ammoUsed: 115)
        let readout = PilotReadout(tank: tank, snapshot: ArenaSnapshot(tanks: [tank]), infinity: true)
        XCTAssertTrue(readout.unlimited)
        XCTAssertNil(readout.firingSeconds)
        XCTAssertEqual(readout.weapon, "MACHINE GUN, ∞ AMMO")
        XCTAssertEqual(readout.buffs, "STAR 4s")
        XCTAssertEqual(readout.readiness, "READY")
        XCTAssertEqual(readout.progress, 1)
    }

    func testBoostedGrenadesStillShowRemoteDetonationWithoutUsingAmmoSlot() {
        let tank = ArenaTank(id: 1, powerTime: 15, power: "grenade", charges: 3)
        var snapshot = ArenaSnapshot(tanks: [tank], bullets: [ArenaBullet(id: 9, owner: 1, kind: "grenade", life: 7.24)])
        snapshot.boostedBulletIds = [9]
        let readout = PilotReadout(tank: tank, snapshot: snapshot, infinity: false)
        XCTAssertEqual(readout.available, 3)
        XCTAssertEqual(readout.weapon, "GRENADE, 7.2s")
        XCTAssertEqual(readout.readiness, "DETONATE READY")
        XCTAssertEqual(readout.fireLabel, "BOOM")
        XCTAssertEqual(readout.fireHint, "TAP TO DETONATE")
    }

    func testInfinityUsesFullArenaGrenadeAndAmmoMetadataOutsideVisibleSnapshot() {
        var tank = ArenaTank(id: 1, grenadeLife: 4.5, power: "grenade", charges: 2, ammoUsed: 3, grenades: 1)
        let ready = PilotReadout(tank: tank, snapshot: ArenaSnapshot(tanks: [tank]), infinity: true)
        XCTAssertEqual(ready.available, 0)
        XCTAssertEqual(ready.readiness, "DETONATE READY")
        XCTAssertEqual(ready.weapon, "GRENADE, 4.5s")
        tank.grenadeLife = 0
        let expired = PilotReadout(tank: tank, snapshot: ArenaSnapshot(tanks: [tank]), infinity: true)
        XCTAssertEqual(expired.readiness, "WAITING FOR AMMO")
    }

    func testCooldownUsesWeaponFallbackProgressAndWebDecimalRounding() {
        var tank = ArenaTank(id: 1, cooldown: 0.17)
        let half = PilotReadout(tank: tank, snapshot: ArenaSnapshot(tanks: [tank]), infinity: false)
        XCTAssertEqual(half.progress, 0.5, accuracy: 1e-12)
        XCTAssertEqual(half.readiness, "COOLDOWN 0.2s")
        tank.cooldown = 0.25
        XCTAssertEqual(PilotReadout(tank: tank, snapshot: ArenaSnapshot(), infinity: false).readiness, "COOLDOWN 0.3s")
        tank.cooldown = 0; tank.ghostTime = 5
        let phased = PilotReadout(tank: tank, snapshot: ArenaSnapshot(), infinity: false)
        XCTAssertEqual(phased.readiness, "READY")
        XCTAssertEqual(phased.fireLabel, "FIRE")
        XCTAssertEqual(phased.progress, 1)
    }

    func testSpawnProtectionBlocksFiringAndSuppressesLockWarning() {
        let tank = ArenaTank(id: 1, spawnProtected: true, invulnerable: 0.5, locked: true)
        let readout = PilotReadout(tank: tank, snapshot: ArenaSnapshot(tanks: [tank]), infinity: true)
        XCTAssertEqual(readout.readiness, "SPAWN PROTECTION")
        XCTAssertEqual(readout.fireLabel, "WAIT")
        XCTAssertEqual(readout.fireHint, "WAIT TO FIRE")
        XCTAssertEqual(readout.progress, 0)
        XCTAssertFalse(readout.locked)
    }

    func testFixedPhasesTakePriorityOverOldLifeState() {
        let dead = ArenaTank(id: 1, hp: 0, respawnTime: 1)
        for (phase, text, label, progress) in [("countdown", "GET READY", "FIRE", 0.0),
            ("roundOver", "ROUND COMPLETE", "DONE", 1), ("matchOver", "MATCH COMPLETE", "DONE", 1)] {
            let readout = PilotReadout(tank: dead, snapshot: ArenaSnapshot(tanks: [dead], phase: phase), infinity: false)
            XCTAssertEqual(readout.readiness, text)
            XCTAssertEqual(readout.fireLabel, label)
            XCTAssertEqual(readout.progress, progress)
            XCTAssertTrue(readout.weapon.isEmpty)
            XCTAssertEqual(readout.available, 0)
        }
    }

    func testFixedDeathReadinessDistinguishesEliminationObjectivesAndSurvival() {
        let dead = ArenaTank(id: 1, hp: 0, respawnTime: 2.4)
        for (mode, text) in [("elimination", "OUT"), ("ctf", "RESPAWN 2.4s"),
                             ("koth", "RESPAWN 2.4s"), ("survival", "BACK NEXT WAVE")] {
            var snapshot = ArenaSnapshot(tanks: [dead]); snapshot.objectives = ArenaObjectives(mode: mode)
            let readout = PilotReadout(tank: dead, snapshot: snapshot, infinity: false)
            XCTAssertEqual(readout.readiness, text)
            XCTAssertEqual(readout.fireLabel, "OUT")
            XCTAssertEqual(readout.progress, 0)
        }
        var suddenDeath = ArenaSnapshot(tanks: [dead]); suddenDeath.objectives = ArenaObjectives(mode: "ctf", suddenDeath: true)
        XCTAssertEqual(PilotReadout(tank: dead, snapshot: suddenDeath, infinity: false).readiness, "OUT")
    }

    func testSurvivalBreakShowsOneNextWaveStatusEvenForFallenTank() {
        let dead = ArenaTank(id: 1, hp: 0)
        var snapshot = ArenaSnapshot(tanks: [dead])
        snapshot.objectives = ArenaObjectives(mode: "survival", survival: ArenaSurvival(wave: 2, breakTime: 1.2, status: "break"))
        let readout = PilotReadout(tank: dead, snapshot: snapshot, infinity: false)
        XCTAssertEqual(readout.readiness, "NEXT WAVE 2s")
        XCTAssertEqual(readout.fireLabel, "WAIT")
        XCTAssertEqual(readout.fireHint, "NEXT WAVE")
    }

    func testInfinityPauseDistinguishesHeldOnlineRespawnAndOfflinePause() {
        let dead = ArenaTank(id: 1, hp: 0, respawnTime: 0.8)
        let state = ArenaSnapshot(tanks: [dead])
        XCTAssertEqual(PilotReadout(tank: dead, snapshot: state, infinity: true, paused: true, online: true).readiness, "RESPAWN HELD")
        XCTAssertEqual(PilotReadout(tank: dead, snapshot: state, infinity: true, paused: true, online: false).readiness, "RESPAWN 0.8s")
        let alive = ArenaTank(id: 1, locked: true)
        let paused = PilotReadout(tank: alive, snapshot: ArenaSnapshot(tanks: [alive]), infinity: true, paused: true)
        XCTAssertEqual(paused.readiness, "PAUSED"); XCTAssertEqual(paused.fireLabel, "PAUSED"); XCTAssertEqual(paused.progress, 1)
        XCTAssertFalse(paused.locked)
    }

    func testBuffCompatibilityAndCompactLabelsMatchWeb() {
        let tank = ArenaTank(id: 1, shield: 2.1, speedTime: 4.1, ghostTime: 1.1)
        let readout = PilotReadout(tank: tank, snapshot: ArenaSnapshot(), infinity: false)
        XCTAssertEqual(readout.buffs, "SHD×1 SPD×15 GHO2")
        var staleShield = ArenaTank(id: 1, shieldCharges: 4)
        XCTAssertTrue(PilotReadout(tank: staleShield, snapshot: ArenaSnapshot(), infinity: false).buffs.isEmpty)
        staleShield.shield = 2
        XCTAssertEqual(PilotReadout(tank: staleShield, snapshot: ArenaSnapshot(), infinity: false).buffs, "SHD×4 2s")
    }

    func testFriendlyHomingLockRespectsNormalizedRulesAndFriendlyFire() throws {
        let payload = ##"{"type":"state","phase":"playing","tanks":[{"id":1,"alive":true,"team":1},{"id":2,"alive":true,"team":1}],"bullets":[{"id":9,"owner":2,"kind":"homing","target":1,"life":2}],"rules":{"friendlyFire":false},"pickups":[]}"##
        let normalized = try SnapshotDecoder.normalized(data: Data(payload.utf8), previousWorld: nil)
        var state = try JSONDecoder().decode(ArenaSnapshot.self, from: normalized.data)
        XCTAssertFalse(state.tanks[0].locked)
        XCTAssertFalse(PilotReadout(tank: state.tanks[0], snapshot: state, infinity: false).locked)
        state.rules?.friendlyFire = true
        XCTAssertTrue(PilotReadout(tank: state.tanks[0], snapshot: state, infinity: false).locked)
        state.rules?.friendlyFire = false; state.tanks[1].team = 2
        XCTAssertTrue(PilotReadout(tank: state.tanks[0], snapshot: state, infinity: false).locked)
    }
}
