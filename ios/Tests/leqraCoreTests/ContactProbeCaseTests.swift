import XCTest

@testable import leqraCore

final class ContactProbeCaseTests: XCTestCase {
    private func fixture() -> (ArenaSnapshot, ArenaSnapshot, ArenaSnapshot) {
        let tank = ArenaTank(id: 2, x: 140, y: 42, spawnSerial: 1)
        let flight = CannonFlight(
            id: 9, owner: 1, colorIndex: 0, startTick: 0, endTick: 1,
            points: [CannonFlightPoint(x: 100, y: 42, tick: 0), CannonFlightPoint(x: 119.5, y: 42, tick: 1)],
            kind: "regular", radius: 3.5)
        let hit = ArenaEffect(
            id: 21, kind: "hit", owner: 1,
            contact: ImpactContact(
                projectileId: 9, kind: "regular", tick: 1, target: 2, spawnSerial: 1,
                before: ImpactContactPose(tank)))
        var dead = tank
        dead.hp = 0
        let authority = ArenaSnapshot(tanks: [dead], effects: [ArenaEffect(id: 20, flight: flight), hit])
        let endpoint = ArenaSnapshot(tanks: [tank], bullets: [ArenaBullet(id: 9, x: 119.5, y: 42)])
        let released = ArenaSnapshot(tanks: [dead], effects: [hit])
        return (authority, endpoint, released)
    }

    func testColdGapCannotDiscardTheCaseAndExpiredSourceEventsCannotHideCompletion() {
        let (authority, endpoint, released) = fixture()
        var probe = ContactProbeCase()
        probe.observe(authoritative: authority, visible: ArenaSnapshot(tanks: endpoint.tanks), dt: 1)
        XCTAssertEqual(probe.creditedSeconds, 0.1)
        XCTAssertFalse(probe.canAdvance)
        probe.observe(authoritative: ArenaSnapshot(tanks: authority.tanks), visible: endpoint, dt: 0.1)
        XCTAssertNil(probe.result)
        XCTAssertFalse(probe.canAdvance)
        probe.observe(authoritative: ArenaSnapshot(tanks: authority.tanks), visible: released, dt: 0.1)
        XCTAssertEqual(probe.result, .passed)
        XCTAssertTrue(probe.canAdvance)
    }

    func testGenuineEarlyDamageStillFailsAndMissingContactHasABoundedTimeout() {
        let (authority, endpoint, released) = fixture()
        var early = ContactProbeCase()
        early.observe(authoritative: authority, visible: released, dt: 1 / 120)
        XCTAssertEqual(early.result, .damageBeforeEndpoint)
        var sameFrame = ContactProbeCase()
        var invalid = endpoint
        invalid.effects = released.effects
        sameFrame.observe(authoritative: authority, visible: invalid, dt: 1 / 120)
        XCTAssertEqual(sameFrame.result, .damageBeforeEndpoint)
        var missing = ContactProbeCase()
        for _ in 0..<11 { missing.observe(authoritative: ArenaSnapshot(), visible: ArenaSnapshot(), dt: 1) }
        XCTAssertNil(missing.result)
        XCTAssertTrue(missing.canAdvance)
    }

    func testIsolatedCasesUseDistinctRendererIDsWithoutBreakingContactReferences() {
        let (authority, endpoint, _) = fixture()
        var combined = endpoint
        combined.effects = authority.effects
        combined.boostedBulletIds = [9]
        let first = ContactProbeCase.renderSnapshot(combined, episode: 0)
        let second = ContactProbeCase.renderSnapshot(combined, episode: 1)
        XCTAssertNotEqual(first.effects[0].id, second.effects[0].id)
        XCTAssertNotEqual(first.bullets[0].id, second.bullets[0].id)
        XCTAssertEqual(first.effects[0].flight?.id, first.bullets[0].id)
        XCTAssertEqual(first.effects[1].contact?.projectileId, first.bullets[0].id)
        XCTAssertEqual(first.boostedBulletIds, first.bullets.map(\.id))
        XCTAssertEqual(first.tanks.map(\.id), combined.tanks.map(\.id))
        XCTAssertEqual(combined.bullets[0].id, 9)
    }

    func testLaserAndStarmanRequireASeparateLivingContactFrameAndKeepZeroProjectileSentinel() {
        for kind in ["laser", "starman", "cannon"] {
            let attacker = ArenaTank(id: 1, x: 107, y: 42, starmanTime: kind == "starman" ? 10 : 0)
            let target = ArenaTank(id: 2, x: 140, y: 42, spawnSerial: 1)
            var dead = target
            dead.hp = 0
            let hit = ArenaEffect(
                id: 21, kind: "hit", owner: 1,
                contact: ImpactContact(
                    projectileId: 0, kind: kind, tick: 1, target: 2, spawnSerial: 1,
                    before: ImpactContactPose(target)))
            let beam = ArenaEffect(
                id: 20, kind: "laser", owner: 1,
                points: [BeamPoint(x: 107, y: 42), BeamPoint(x: 123, y: 42)])
            let authority = ArenaSnapshot(tanks: [attacker, dead], effects: [hit])
            let endpoint = ArenaSnapshot(
                tanks: [attacker, target],
                bullets: kind == "cannon"
                    ? [ArenaBullet(id: 30, x: 115, y: 42, owner: 1, kind: "cannon")] : [],
                effects: kind == "laser" ? [beam] : [])
            let released = ArenaSnapshot(tanks: [attacker, dead], effects: [hit])
            var probe = ContactProbeCase()
            probe.observe(authoritative: authority, visible: endpoint, dt: 1 / 120)
            XCTAssertNil(probe.result)
            probe.observe(
                authoritative: ArenaSnapshot(tanks: authority.tanks), visible: released, dt: 1 / 120)
            XCTAssertEqual(probe.result, .passed, kind)
            XCTAssertEqual(
                ContactProbeCase.renderSnapshot(released, episode: 2).effects[0].contact?.projectileId, 0)
        }
    }
}
