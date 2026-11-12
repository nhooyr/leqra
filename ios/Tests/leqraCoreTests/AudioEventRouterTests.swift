import XCTest
@testable import leqraCore

final class AudioEventRouterTests: XCTestCase {
    private func snapshot(_ effects: [ArenaEffect] = [], bullets: [ArenaBullet] = [],
                          phase: String = "playing", phaseTime: Double = 0,
                          generation: Int = 1, tanks: [ArenaTank]? = nil) -> ArenaSnapshot {
        var state = ArenaSnapshot(tanks: tanks ?? [ArenaTank(id: 1, x: 0, y: 0), ArenaTank(id: 2, x: 100, y: 0)],
                                  bullets: bullets, effects: effects, phase: phase, phaseTime: phaseTime)
        state.generation = generation
        return state
    }

    private func effect(_ id: Int, _ kind: String, owner: Int = 1, x: Double = 0, player: Int? = nil) -> ArenaEffect {
        ArenaEffect(id: id, kind: kind, x: x, owner: owner, player: player)
    }

    func testJoiningAndNewGenerationsBaselineEffectsAndBouncesWithoutHistory() {
        var router = AudioEventRouter()
        let old = snapshot([effect(9, "hit"), effect(10, "shot:")], bullets: [ArenaBullet(id: 1, bounces: 5)])
        XCTAssertEqual(router.consume(snapshot: old, localID: 1, infinity: true, online: true, now: 1), [])
        var fresh = old
        fresh.effects.append(effect(11, "shot:"))
        XCTAssertEqual(router.consume(snapshot: fresh, localID: 1, infinity: true, online: true, now: 2), [.init(cue: .regular)])
        fresh.generation = 2
        fresh.effects = [effect(1, "blast")]
        fresh.bullets[0].bounces = 10
        XCTAssertEqual(router.consume(snapshot: fresh, localID: 1, infinity: true, online: true, now: 3), [])
        router.reset()
        XCTAssertEqual(router.consume(snapshot: old, localID: 1, infinity: true, online: true, now: 4), [])
    }

    func testUnsortedEffectIDsPlayOnceAndDoNotReplayOnPresentationRewind() {
        var router = AudioEventRouter()
        _ = router.consume(snapshot: snapshot(), localID: 1, infinity: true, online: true, now: 0)
        let state = snapshot([effect(3, "shot:scatter"), effect(1, "pickup"), effect(2, "shot:")])
        XCTAssertEqual(router.consume(snapshot: state, localID: 1, infinity: true, online: true, now: 1).map(\.cue), [.pickup, .regular, .scatter])
        XCTAssertEqual(router.consume(snapshot: state, localID: 1, infinity: true, online: true, now: 2), [])
        XCTAssertEqual(router.consume(snapshot: snapshot([effect(2, "hit")]), localID: 1, infinity: true, online: true, now: 3), [])
    }

    func testFixedOnlineLaserBeamAndShotUseOneSoundWhileLocalAndInfinityBeamsSound() {
        for (infinity, online) in [(false, true), (false, false), (true, true), (true, false)] {
            var router = AudioEventRouter()
            _ = router.consume(snapshot: snapshot(), localID: 1, infinity: infinity, online: online, now: 0)
            let effects = online && !infinity ? [effect(1, "laser"), effect(2, "shot:laser")] : [effect(1, "laser")]
            XCTAssertEqual(router.consume(snapshot: snapshot(effects), localID: 1, infinity: infinity, online: online, now: 1), [.init(cue: .laser)])
        }
    }

    func testFixedShotLocalityUsesPlayerMetadataAndOnlyShotsUseRemoteRecipe() {
        var router = AudioEventRouter()
        _ = router.consume(snapshot: snapshot(), localID: 1, infinity: false, online: true, now: 0)
        let cues = router.consume(snapshot: snapshot([effect(1, "shot:cannon", owner: 1, player: 2), effect(2, "shield", owner: 2, player: 1)]), localID: 1, infinity: false, online: true, now: 1)
        XCTAssertEqual(cues, [.init(cue: .cannon, local: false), .init(cue: .shield)])
    }

    func testRapidAndStarmanShotsUseShared65MillisecondGateButGrenadeIsNotThrottled() {
        var router = AudioEventRouter()
        var boosted = ArenaTank(id: 1); boosted.starmanTime = 3
        _ = router.consume(snapshot: snapshot(tanks: [boosted]), localID: 1, infinity: true, online: false, now: 0)
        let burst = snapshot([effect(1, "shot:"), effect(2, "laser"), effect(3, "shot:grenade")], tanks: [boosted])
        XCTAssertEqual(router.consume(snapshot: burst, localID: 1, infinity: true, online: false, now: 1).map(\.cue), [.regular, .grenade])
        XCTAssertEqual(router.consume(snapshot: snapshot([effect(4, "shot:rapid")]), localID: 1, infinity: true, online: false, now: 1.064), [])
        XCTAssertEqual(router.consume(snapshot: snapshot([effect(5, "shot:rapid")]), localID: 1, infinity: true, online: false, now: 1.066).map(\.cue), [.rapid])
    }

    func testGrenadeVictimsShareDeathGateButRecentDeathCannotSuppressGrenade() {
        var router = AudioEventRouter()
        _ = router.consume(snapshot: snapshot(), localID: 1, infinity: true, online: false, now: 0)
        XCTAssertEqual(router.consume(snapshot: snapshot([effect(1, "blast"), effect(2, "hit"), effect(3, "hit"), effect(4, "blast")]), localID: 1, infinity: true, online: false, now: 1).map(\.cue), [.grenadeExplosion])
        XCTAssertEqual(router.consume(snapshot: snapshot([effect(5, "hit")]), localID: 1, infinity: true, online: false, now: 1.069), [])
        XCTAssertEqual(router.consume(snapshot: snapshot([effect(6, "hit")]), localID: 1, infinity: true, online: false, now: 1.071).map(\.cue), [.explosion])
        XCTAssertEqual(router.consume(snapshot: snapshot([effect(7, "blast"), effect(8, "hit")]), localID: 1, infinity: true, online: false, now: 1.072).map(\.cue), [.grenadeExplosion])
    }

    func testRicochetsBaselineHighWaterAndShare70MillisecondGate() {
        var router = AudioEventRouter()
        func state(_ count: Int) -> ArenaSnapshot { snapshot(bullets: [ArenaBullet(id: 1, bounces: count)]) }
        _ = router.consume(snapshot: state(3), localID: 1, infinity: true, online: true, now: 0)
        XCTAssertEqual(router.consume(snapshot: state(4), localID: 1, infinity: true, online: true, now: 1).map(\.cue), [.ricochet])
        for count in [3, 4] { XCTAssertEqual(router.consume(snapshot: state(count), localID: 1, infinity: true, online: true, now: 1.1), []) }
        XCTAssertEqual(router.consume(snapshot: state(5), localID: 1, infinity: true, online: true, now: 1.2).map(\.cue), [.ricochet])
        XCTAssertEqual(router.consume(snapshot: state(6), localID: 1, infinity: true, online: true, now: 1.21), [])
        _ = router.consume(snapshot: snapshot(), localID: 1, infinity: true, online: true, now: 2)
        XCTAssertEqual(router.consume(snapshot: state(10), localID: 1, infinity: true, online: true, now: 3), [])
    }

    func testInfinityEffectsAndBounceProximityDifferWhileFixedHasNoDistanceLimit() {
        var infinity = AudioEventRouter(), fixed = AudioEventRouter()
        let baseline = snapshot(bullets: [ArenaBullet(id: 1, x: 588, bounces: 0), ArenaBullet(id: 2, x: 589, bounces: 0)])
        _ = infinity.consume(snapshot: baseline, localID: 1, infinity: true, online: true, now: 0)
        _ = fixed.consume(snapshot: baseline, localID: 1, infinity: false, online: true, now: 0)
        let effects = [effect(1, "shot:", owner: 2, x: 504), effect(2, "shot:", owner: 2, x: 505), effect(3, "shot:", x: 5000)]
        var fresh = snapshot(effects, bullets: baseline.bullets)
        fresh.bullets[0].bounces = 1
        fresh.bullets[1].bounces = 1
        XCTAssertEqual(infinity.consume(snapshot: fresh, localID: 1, infinity: true, online: true, now: 1), [.init(cue: .ricochet), .init(cue: .regular, local: false), .init(cue: .regular)])
        XCTAssertEqual(fixed.consume(snapshot: fresh, localID: 1, infinity: false, online: true, now: 1).map(\.cue), [.ricochet, .regular, .regular, .regular])
    }

    func testPickupAudienceMatchesInfinityFixedLocalAndFixedOnlineAndObjectives() {
        for (infinity, online, expected) in [(true, true, [AudioCue.pickup, .pickup]), (false, false, [.pickup, .pickup, .pickup]), (false, true, [.pickup, .pickup])] {
            var router = AudioEventRouter()
            _ = router.consume(snapshot: snapshot(), localID: 1, infinity: infinity, online: online, now: 0)
            let effects = [effect(1, "pickup", owner: 2, player: 2), effect(2, "pickup"), effect(3, "objective")]
            let requests = router.consume(snapshot: snapshot(effects), localID: 1, infinity: infinity, online: online, now: 1)
            XCTAssertEqual(requests.map(\.cue), expected)
            if infinity || !online { XCTAssertFalse(requests[0].local, "A remote pickup must not trigger local haptics.") }
        }
    }

    func testCountdownTracksDisplayedNumberAndOnlyLocalFixedTransitionHasGo() {
        for online in [false, true] {
            var router = AudioEventRouter()
            XCTAssertEqual(router.consume(snapshot: snapshot(phase: "countdown", phaseTime: 3), localID: 1, infinity: false, online: online, now: 0).map(\.cue), [.countdown])
            XCTAssertEqual(router.consume(snapshot: snapshot(phase: "countdown", phaseTime: 2.9), localID: 1, infinity: false, online: online, now: 0.1), [])
            XCTAssertEqual(router.consume(snapshot: snapshot(phase: "countdown", phaseTime: 2), localID: 1, infinity: false, online: online, now: 1).map(\.cue), [.countdown])
            XCTAssertEqual(router.consume(snapshot: snapshot(), localID: 1, infinity: false, online: online, now: 3).map(\.cue), online ? [] : [.go])
            XCTAssertEqual(router.consume(snapshot: snapshot(), localID: 1, infinity: false, online: online, now: 4), [])
        }
    }

    func testRoundResultLocalChordDrawAndAuthoritativeOnlineOwnership() {
        for winner in [-1, 1, 2] {
            var router = AudioEventRouter()
            _ = router.consume(snapshot: snapshot(), localID: 1, infinity: false, online: false, now: 0)
            var state = snapshot(phase: "roundOver"); state.winner = winner
            XCTAssertEqual(router.consume(snapshot: state, localID: 1, infinity: false, online: false, now: 1).map(\.cue), [winner < 0 ? .roundDraw : .roundWin])
            XCTAssertEqual(router.consume(snapshot: state, localID: 1, infinity: false, online: false, now: 2), [])
        }
        var router = AudioEventRouter()
        _ = router.consume(snapshot: snapshot(), localID: 1, infinity: false, online: true, now: 0)
        XCTAssertEqual(router.consume(snapshot: snapshot([effect(1, "roundEnd", owner: 2)]), localID: 1, infinity: false, online: true, now: 1), [.init(cue: .onlineRoundEnd, local: false)])
    }

    func testCurrentHomingLockWarnsOnJoinAndNeverRepeatsWhileHeld() {
        for infinity in [false, true] {
            for online in [false, true] {
                var router = AudioEventRouter()
                let state = snapshot([effect(10, "hit")], tanks: [ArenaTank(id: 1, locked: true)])
                XCTAssertEqual(router.consume(snapshot: state, localID: 1, infinity: infinity, online: online, now: 0), [.init(cue: .homingWarning)])
                for now in [0.1, 1.6, 10.0] {
                    XCTAssertEqual(router.consume(snapshot: state, localID: 1, infinity: infinity, online: online, now: now), [])
                }
            }
        }
    }

    func testHomingRelockRequiresNewEdgeAndStrictlyMoreThanOnePointFiveSeconds() {
        var router = AudioEventRouter()
        let clear = snapshot(tanks: [ArenaTank(id: 1)])
        let locked = snapshot(tanks: [ArenaTank(id: 1, locked: true)])
        _ = router.consume(snapshot: clear, localID: 1, infinity: true, online: false, now: 0)
        XCTAssertEqual(router.consume(snapshot: locked, localID: 1, infinity: true, online: false, now: 1), [.init(cue: .homingWarning)])
        XCTAssertEqual(router.consume(snapshot: clear, localID: 1, infinity: true, online: false, now: 1.1), [])
        XCTAssertEqual(router.consume(snapshot: locked, localID: 1, infinity: true, online: false, now: 2.5), [])
        XCTAssertEqual(router.consume(snapshot: locked, localID: 1, infinity: true, online: false, now: 3), [])
        XCTAssertEqual(router.consume(snapshot: clear, localID: 1, infinity: true, online: false, now: 3.1), [])
        XCTAssertEqual(router.consume(snapshot: locked, localID: 1, infinity: true, online: false, now: 3.2), [.init(cue: .homingWarning)])
    }

    func testHomingWarningUsesHostileProjectilesAndSuppressesInactivePilots() {
        for kind in ["homing", "grenade"] {
            for condition in ["hostile", "friendly-fire", "dead", "paused", "break", "unlocked", "friendly", "self", "spectator"] {
                let local = ArenaTank(id: 1, hp: condition == "dead" ? 0 : 1, team: 1)
                let owner = ArenaTank(id: 2, team: ["friendly", "friendly-fire"].contains(condition) ? 1 : 2)
                let bullet = ArenaBullet(id: 1, owner: condition == "self" ? 1 : 2, kind: kind, target: condition == "unlocked" ? 0 : 1)
                var state = snapshot(bullets: [bullet], phase: condition == "paused" ? "paused" : "playing", tanks: condition == "spectator" ? [owner] : [local, owner])
                var rules = RoomRules(); rules.teamMode = "teams"; rules.friendlyFire = condition == "friendly-fire"
                state.rules = rules
                if condition == "break" { state.objectives = ArenaObjectives(mode: "survival", survival: ArenaSurvival(status: "break")) }
                var router = AudioEventRouter()
                let expected: [AudioCueRequest] = ["hostile", "friendly-fire"].contains(condition) ? [.init(cue: .homingWarning)] : []
                XCTAssertEqual(router.consume(snapshot: state, localID: 1, infinity: false, online: false, now: 1), expected, "\(kind), \(condition)")
            }
        }
    }
}
