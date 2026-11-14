import Foundation
import XCTest
@testable import leqraCore

final class HitPresentationTests: XCTestCase {
    private let weapons = ["regular", "rapid", "scatter", "homing", "grenade", "cannon"]

    private func radius(_ kind: String) -> Double {
        ["rapid": 3.5 / 3, "homing": 5, "grenade": 6, "cannon": 14][kind] ?? 3.5
    }

    private func events(kind: String, victim: ArenaTank, start: Double = 60, end: Double = 66, shield: Bool = false) -> [ArenaEffect] {
        let flight = CannonFlight(id: 9, owner: 1, colorIndex: 0, startTick: start, endTick: end,
            points: [CannonFlightPoint(x: 100, y: 420, tick: start),
                     CannonFlightPoint(x: victim.x - 17 - radius(kind), y: victim.y, tick: end)], kind: kind, radius: radius(kind))
        return [ArenaEffect(id: 20, kind: kind == "grenade" ? "blast" : "impact", owner: 1, tick: Int(ceil(end)), flight: flight),
                ArenaEffect(id: 21, kind: shield ? "shield" : "hit", x: victim.x, y: victim.y, owner: 1, tick: Int(ceil(end)),
                    contact: ImpactContact(projectileId: 9, kind: kind, tick: end, target: victim.id,
                        spawnSerial: victim.spawnSerial, before: ImpactContactPose(victim)))]
    }

    func testNetworkWeaponsShowExactContactBeforeDeathAndAudioForLocalRemoteAndSpectator() throws {
        for kind in weapons {
            for localID in [1, 2, -1] {
                for rate in [60, 120] {
                    let context = "\(kind) local=\(localID) \(rate)Hz"
                    let timeline = RenderTimeline(localID: localID) { tank, input, dt in
                        if input.forward { tank.x += 500 * dt }
                    }
                    var before = ArenaTank(id: 2, name: "FAST VICTIM", x: 220, y: 420, hp: 1, score: 4,
                        spawnSerial: 7, shield: 0, speedTime: 10, ghostTime: 10, speedStacks: 5)
                    before.vx = 544
                    var oldVictim = before; oldVictim.x = 170
                    let shooter = ArenaTank(id: 1, x: 42, y: 420, spawnSerial: 1, starmanTime: 10)
                    var first = ArenaSnapshot(tick: 60, tanks: [shooter, oldVictim]); first.generation = 1
                    first.spectating = localID == -1; first.following = localID == -1 ? 2 : nil
                    timeline.accept(first, at: 0)
                    var router = AudioEventRouter()
                    _ = router.consume(snapshot: first, localID: localID, infinity: true, online: true, now: 0)
                    var dead = before; dead.hp = 0; dead.score = 3
                    var latest = ArenaSnapshot(tick: 66, tanks: [shooter, dead], effects: events(kind: kind, victim: before))
                    latest.generation = 1; latest.leaderboard = [LeaderboardEntry(id: 2, name: before.name, score: 3)]
                    latest.spectating = first.spectating; latest.following = first.following
                    timeline.accept(latest, at: 0.1)
                    XCTAssertEqual(timeline.authoritativeSnapshot?.tanks[1].hp, 0, context)
                    var endpointFrame: Int?, hitFrame: Int?, cues: [AudioCue] = []
                    for frame in 0..<100 {
                        let now = 0.1 + Double(frame) / Double(rate)
                        let rendered = try XCTUnwrap(timeline.render(dt: 1 / Double(rate), input: GameInput(forward: true), now: now) { _ in })
                        XCTAssertEqual(rendered.tanks[1].score, 3, context)
                        XCTAssertEqual(rendered.leaderboard.first?.score, 3, context)
                        let played = router.consume(snapshot: rendered, localID: localID, infinity: true, online: true, now: now).map(\.cue)
                        cues += played
                        if let bullet = rendered.bullets.first(where: { $0.id == 9 }),
                           abs(bullet.x - (before.x - 17 - radius(kind))) < 1e-7 {
                            endpointFrame = endpointFrame ?? frame
                            XCTAssertEqual(rendered.tanks[1].hp, 1, context)
                            XCTAssertEqual(rendered.tanks[1].x, before.x, accuracy: 1e-7, context)
                            XCTAssertEqual(hypot(bullet.x - rendered.tanks[1].x, bullet.y - rendered.tanks[1].y), 17 + radius(kind), accuracy: 1e-7, context)
                            XCTAssertFalse(rendered.effects.contains { $0.kind == "hit" }, context)
                            XCTAssertFalse(played.contains(.explosion), context)
                        }
                        if rendered.effects.contains(where: { $0.kind == "hit" }) {
                            hitFrame = hitFrame ?? frame
                            XCTAssertNotNil(endpointFrame, context)
                            XCTAssertLessThan(endpointFrame ?? Int.max, frame, context)
                            XCTAssertEqual(rendered.tanks[1].hp, 0, context)
                            break
                        }
                        XCTAssertEqual(rendered.tanks[1].hp, 1, context)
                    }
                    XCTAssertNotNil(endpointFrame, context); XCTAssertNotNil(hitFrame, context)
                    XCTAssertEqual(cues.filter { $0 == (kind == "grenade" ? .grenadeExplosion : .explosion) }.count, 1, context)
                    XCTAssertEqual(timeline.authoritativeSnapshot?.tanks[1].x, before.x, context)
                }
            }
        }
    }

    func testAllBallisticPowerCombinationsKeepShieldUntilExactContactAndEaseSurvivor() throws {
        for kind in weapons {
            for profile in ["ordinary", "speed", "ghost", "starman"] {
                let label = "\(kind), \(profile)"
                let presenter = CannonFlightPresenter()
                var before = ArenaTank(id: 2, x: 220, y: 420, spawnSerial: 1, shield: 10, shieldCharges: 3)
                if profile == "speed" { before.speedTime = 10; before.speedStacks = 5; before.vx = 544 }
                if profile == "ghost" { before.ghostTime = 10 }
                if profile == "starman" { before.starmanTime = 10 }
                var after = before; after.shieldCharges = 2; after.invulnerable = 0.35; after.x += 25
                let effects = events(kind: kind, victim: before, start: 60, end: 61, shield: true)
                presenter.accept(effects, tanks: [after])
                var bullets: [ArenaBullet] = []
                presenter.append(to: &bullets, tick: 66, now: 0)
                var tanks = [after]; presenter.applyContacts(to: &tanks)
                XCTAssertEqual(tanks[0].shieldCharges, 3, label)
                XCTAssertTrue(presenter.effects(effects).isEmpty, label)
                bullets = []; presenter.append(to: &bullets, tick: 66, now: 0.05)
                tanks = [after]; presenter.applyContacts(to: &tanks)
                let endpoint = try XCTUnwrap(bullets.first, label)
                XCTAssertEqual(hypot(endpoint.x - tanks[0].x, endpoint.y - tanks[0].y), 17 + radius(kind), accuracy: 1e-7, label)
                XCTAssertEqual(tanks[0].shieldCharges, 3, label)
                XCTAssertTrue(presenter.effects(effects).isEmpty, label)
                bullets = []; presenter.append(to: &bullets, tick: 66, now: 0.06)
                tanks = [after]; presenter.applyContacts(to: &tanks)
                XCTAssertEqual(tanks[0].shieldCharges, 2, label)
                XCTAssertEqual(tanks[0].x, before.x, accuracy: 1e-7, "No Speed5 position snap on shield release: \(label)")
                XCTAssertEqual(presenter.effects(effects).filter { $0.kind == "shield" }.count, 1, label)
                bullets = []; presenter.append(to: &bullets, tick: 66, now: 0.08)
                tanks = [after]; presenter.applyContacts(to: &tanks)
                XCTAssertGreaterThan(tanks[0].x, before.x, label); XCTAssertLessThan(tanks[0].x, after.x, label)
                bullets = []; presenter.append(to: &bullets, tick: 66, now: 0.11)
                tanks = [after]; presenter.applyContacts(to: &tanks)
                XCTAssertEqual(tanks[0], after, label)
            }
        }
    }

    func testLaserAndStarmanContactDrawForOneFrameBeforeDamageUsingOwnAuthorityClock() {
        for kind in ["laser", "starman"] {
            for localID in [1, -1] {
                let presenter = CannonFlightPresenter(), before = ArenaTank(id: 2, x: 220, y: 420, spawnSerial: 1)
                var dead = before; dead.hp = 0
                let beam = ArenaEffect(id: 20, kind: kind == "laser" ? "laser" : "shot:", owner: 1,
                    points: [BeamPoint(x: 42, y: 420), BeamPoint(x: 200, y: 420)], tick: 66)
                let hit = ArenaEffect(id: 21, kind: "hit", owner: 1, tick: 66, contact: ImpactContact(projectileId: 0,
                    kind: kind, tick: 66, target: 2, spawnSerial: 1, before: ImpactContactPose(before)))
                presenter.accept([beam, hit], tanks: [dead])
                var bullets: [ArenaBullet] = []
                let tick = localID == 1 ? 61.0 : 66.0
                presenter.append(to: &bullets, tick: tick, now: 0, authorityTick: 66, localID: localID)
                var tanks = [dead]; presenter.applyContacts(to: &tanks)
                XCTAssertEqual(tanks[0].hp, 1, kind)
                let firstEffects = presenter.effects([beam, hit])
                XCTAssertFalse(firstEffects.contains { $0.kind == "hit" }, kind)
                if kind == "laser" { XCTAssertTrue(firstEffects.contains { $0.kind == "laser" }) }
                presenter.append(to: &bullets, tick: tick, now: 1 / 120, authorityTick: 66, localID: localID)
                tanks = [dead]; presenter.applyContacts(to: &tanks)
                XCTAssertEqual(tanks[0].hp, 0, kind)
                XCTAssertTrue(presenter.effects([beam, hit]).contains { $0.kind == "hit" }, kind)
            }
        }
    }

    func testFirstSeenCorpseUsesContactPoseButNewLifeCannotBeResurrectedOrExploded() {
        let presenter = CannonFlightPresenter(), before = ArenaTank(id: 2, x: 220, y: 420, spawnSerial: 1)
        var dead = before; dead.hp = 0
        let effects = events(kind: "cannon", victim: before)
        presenter.accept(effects, tanks: [dead])
        var bullets: [ArenaBullet] = []
        presenter.append(to: &bullets, tick: 61, now: 0)
        var tanks = [dead]; presenter.applyContacts(to: &tanks)
        XCTAssertEqual(tanks[0].hp, 1); XCTAssertEqual(tanks[0].x, 220)
        var respawn = before; respawn.spawnSerial = 2; respawn.x = 800
        presenter.accept(effects, tanks: [respawn])
        bullets = []; presenter.append(to: &bullets, tick: 70, now: 0.1)
        tanks = [respawn]; presenter.applyContacts(to: &tanks)
        XCTAssertEqual(tanks, [respawn])
        XCTAssertFalse(presenter.effects(effects).contains { $0.kind == "hit" })
    }

    func testCulledKnownVictimRetainsItsOwnAppearanceOnlyUntilContact() {
        let presenter = CannonFlightPresenter(), before = ArenaTank(id: 2, name: "KNOWN", x: 220, y: 420,
            colorIndex: 5, bot: true, spawnSerial: 1, powerTime: 10, power: "homing", charges: 3)
        presenter.accept([], tanks: [before])
        let effects = events(kind: "cannon", victim: before, start: 60, end: 61)
        presenter.accept(effects, tanks: [])
        var bullets: [ArenaBullet] = [], bodies: [ArenaTank] = []
        presenter.append(to: &bullets, tick: 66, now: 0)
        presenter.applyContacts(to: &bodies)
        XCTAssertEqual(bodies.first?.name, "KNOWN"); XCTAssertEqual(bodies.first?.colorIndex, 5)
        XCTAssertEqual(bodies.first?.power, "homing"); XCTAssertEqual(bodies.first?.hp, 1)
        bodies = []; bullets = []; presenter.append(to: &bullets, tick: 66, now: 0.05); presenter.applyContacts(to: &bodies)
        XCTAssertEqual(bodies.first?.hp, 1)
        bodies = []; bullets = []; presenter.append(to: &bullets, tick: 66, now: 0.06); presenter.applyContacts(to: &bodies)
        XCTAssertTrue(bodies.isEmpty)
        let unknown = CannonFlightPresenter(); unknown.accept(effects, tanks: [])
        bullets = []; unknown.append(to: &bullets, tick: 66, now: 0); unknown.applyContacts(to: &bodies)
        XCTAssertTrue(bodies.isEmpty, "Never invent an unseen identity or color")
    }

    func testPauseAndFollowResetDoNotReplayOrHoldOldHits() throws {
        let timeline = RenderTimeline(localID: -1) { _, _, _ in }
        let before = ArenaTank(id: 2, x: 220, y: 420, spawnSerial: 1)
        var first = ArenaSnapshot(tick: 60, tanks: [before]); first.generation = 1; first.spectating = true; first.following = 2
        timeline.accept(first, at: 0)
        var latest = first; latest.tick = 66; latest.tanks[0].hp = 0; latest.effects = events(kind: "cannon", victim: before)
        timeline.accept(latest, at: 0.1)
        XCTAssertTrue(timeline.hasPendingProjectileFlights)
        timeline.neutralize()
        let resumed = try XCTUnwrap(timeline.render(dt: 0, input: GameInput(), now: 0.1) { _ in })
        XCTAssertEqual(resumed.tanks[0].hp, 0); XCTAssertTrue(resumed.effects.isEmpty); XCTAssertFalse(timeline.hasPendingProjectileFlights)
        latest.tick += 2; latest.following = 3
        timeline.accept(latest, at: 0.2)
        let followed = try XCTUnwrap(timeline.render(dt: 0, input: GameInput(), now: 0.2) { _ in })
        XCTAssertEqual(followed.tanks[0].hp, 0); XCTAssertTrue(followed.effects.isEmpty)
    }

    func testEveryFiniteWinningWeaponFinishesContactBeforeRoundDeath() throws {
        for kind in weapons {
            var rules = RoomRules(); rules.scoreTarget = 1; rules.pickupRate = "off"
            let arena = FixedArena(rules: rules, name: "WINNER", colorIndex: 0, botCount: 1, seed: 42)
            for _ in 0..<180 { arena.step(input: GameInput(), dt: 1 / 60) }
            arena.combat.snapshot.tanks = [
                ArenaTank(id: 1, x: 42, y: 42, powerTime: 10, power: kind == "regular" ? "" : kind, charges: 3, machineRounds: 180),
                ArenaTank(id: 2, x: 78, y: 42, bot: true, cooldown: 999)
            ]
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.phase, "roundOver", kind)
            XCTAssertEqual(arena.snapshot.tanks[1].hp, 0, kind)
            let first = arena.combat.presentationSnapshot(fraction: 0, now: 0)
            XCTAssertEqual(first.tanks[1].hp, 1, kind)
            XCTAssertFalse(first.effects.contains { $0.kind == "hit" }, kind)
            let end = arena.combat.presentationSnapshot(fraction: 0, now: 0.05)
            let flight = try XCTUnwrap(arena.snapshot.effects.first { $0.flight != nil }?.flight, kind)
            let bullet = try XCTUnwrap(end.bullets.first { $0.id == flight.id }, kind)
            XCTAssertEqual(bullet.x, flight.points.last?.x, kind)
            XCTAssertEqual(end.tanks[1].hp, 1, kind)
            let after = arena.combat.presentationSnapshot(fraction: 0, now: 0.06)
            XCTAssertEqual(after.tanks[1].hp, 0, kind)
            XCTAssertTrue(after.effects.contains { $0.kind == "hit" }, kind)
        }
    }

    func testPublishedProjectileContinuesWithoutRewindingAndRoundSoundWaitsForContact() {
        let presenter = CannonFlightPresenter(), before = ArenaTank(id: 2, x: 220, y: 420, spawnSerial: 1)
        var dead = before; dead.hp = 0
        var bullets = [ArenaBullet(id: 9, x: 150, y: 420, vx: 420, owner: 1)]
        presenter.append(to: &bullets, tick: 63, now: 0)
        let events = events(kind: "regular", victim: before) + [ArenaEffect(id: 22, kind: "roundEnd", owner: 1, tick: 66)]
        presenter.accept(events, tanks: [dead])
        bullets = []; presenter.append(to: &bullets, tick: 64, now: 0.01)
        XCTAssertGreaterThan(bullets.first?.x ?? 0, 150, "An already visible flight never restarts at its muzzle")
        XCTAssertFalse(presenter.effects(events).contains { $0.kind == "roundEnd" })
        bullets = []; presenter.append(to: &bullets, tick: 66, now: 0.02)
        XCTAssertEqual(bullets.first?.x, before.x - 20.5)
        XCTAssertTrue(presenter.effects(events).isEmpty)
        bullets = []; presenter.append(to: &bullets, tick: 66, now: 0.03)
        XCTAssertEqual(Set(presenter.effects([]).map(\.kind)), Set(["impact", "hit", "roundEnd"]), "Round audio survives source event expiry")
    }

    func testGrenadeSharedFlightReleasesAllVictimsAfterOneEndpointFrame() {
        let presenter = CannonFlightPresenter(), first = ArenaTank(id: 2, x: 220, y: 420, spawnSerial: 1)
        var second = first; second.id = 3; second.y += 84
        var effects = events(kind: "grenade", victim: first, start: 60, end: 61)
        effects.append(ArenaEffect(id: 22, kind: "hit", owner: 1, tick: 61,
            contact: ImpactContact(projectileId: 9, kind: "grenade", tick: 61, target: second.id, spawnSerial: 1, before: ImpactContactPose(second))))
        var dead = [first, second]; for index in dead.indices { dead[index].hp = 0 }
        presenter.accept(effects, tanks: dead)
        var bullets: [ArenaBullet] = []
        presenter.append(to: &bullets, tick: 66, now: 0)
        var bodies = dead; presenter.applyContacts(to: &bodies)
        XCTAssertEqual(bodies.map(\.hp), [1, 1]); XCTAssertEqual(bullets.count, 1)
        bullets = []; presenter.append(to: &bullets, tick: 66, now: 0.05)
        bodies = dead; presenter.applyContacts(to: &bodies)
        XCTAssertEqual(bodies.map(\.hp), [1, 1]); XCTAssertEqual(bullets.count, 1)
        XCTAssertTrue(presenter.effects(effects).isEmpty)
        bullets = []; presenter.append(to: &bullets, tick: 66, now: 0.06)
        bodies = dead; presenter.applyContacts(to: &bodies)
        XCTAssertEqual(bodies.map(\.hp), [0, 0]); XCTAssertTrue(bullets.isEmpty)
        XCTAssertEqual(presenter.effects(effects).filter { $0.kind == "hit" }.count, 2)
    }

    func testEightBoostedShotgunsRetain864FlightsAndNeverReplayHistory() {
        let presenter = CannonFlightPresenter()
        let victims = (2...9).map { ArenaTank(id: $0, x: 220, y: 420, spawnSerial: 1) }
        var dead = victims; for index in dead.indices { dead[index].hp = 0 }
        let effects = (0..<864).map { index -> ArenaEffect in
            let flight = CannonFlight(id: index + 1, owner: 1, colorIndex: 0, startTick: 60, endTick: 61,
                points: [CannonFlightPoint(x: 100, y: 420, tick: 60), CannonFlightPoint(x: 199.5, y: 420, tick: 61)], kind: "scatter", radius: 3.5)
            return ArenaEffect(id: index + 1, kind: "projectileFlight", owner: 1, flight: flight)
        }
        presenter.accept(effects, tanks: dead)
        var bullets: [ArenaBullet] = []
        presenter.append(to: &bullets, tick: 66, now: 0)
        XCTAssertEqual(bullets.count, 864); XCTAssertTrue(presenter.effects(effects).isEmpty)
        bullets = []; presenter.append(to: &bullets, tick: 66, now: 0.05)
        XCTAssertEqual(bullets.count, 864); XCTAssertTrue(bullets.allSatisfy { $0.x == 199.5 })
        XCTAssertTrue(presenter.effects(effects).isEmpty)
        bullets = []; presenter.append(to: &bullets, tick: 66, now: 0.06)
        XCTAssertEqual(presenter.effects(effects).count, 864)
        for frame in 1...20 {
            presenter.accept(effects, tanks: dead)
            bullets = []; presenter.append(to: &bullets, tick: 66, now: 0.06 + Double(frame) / 120)
            XCTAssertTrue(bullets.isEmpty); XCTAssertTrue(presenter.effects(effects).isEmpty)
        }
    }

    func testAlreadyShownZeroTickRicochetDrawsItsFinalVertexBeforeDamage() {
        let presenter = CannonFlightPresenter()
        var bullets = [ArenaBullet(id: 9, x: 100, y: 420, owner: 1)]
        presenter.append(to: &bullets, tick: 60, now: 0)
        let before = ArenaTank(id: 2, x: 140.5, y: 420, spawnSerial: 1)
        var effects = events(kind: "regular", victim: before, start: 60, end: 60)
        effects[0].flight?.points.insert(CannonFlightPoint(x: 90, y: 420, tick: 60), at: 1)
        var dead = before; dead.hp = 0
        presenter.accept(effects, tanks: [dead])
        bullets = []; presenter.append(to: &bullets, tick: 60, now: 0.01)
        XCTAssertEqual(bullets.first?.x, 120, "Equal-tick muzzle reflections end at the final vertex")
        var bodies = [dead]; presenter.applyContacts(to: &bodies)
        XCTAssertEqual(bodies[0].hp, 1); XCTAssertTrue(presenter.effects(effects).isEmpty)
        bullets = []; presenter.append(to: &bullets, tick: 60, now: 0.02)
        bodies = [dead]; presenter.applyContacts(to: &bodies)
        XCTAssertEqual(bodies[0].hp, 0)
    }

    func testCoalescedShieldThenDeathEachShowsItsOwnMovingVictimContact() throws {
        let presenter = CannonFlightPresenter()
        let shielded = ArenaTank(id: 2, x: 220, y: 420, spawnSerial: 1, shield: 10, shieldCharges: 1)
        var lethal = shielded; lethal.x = 320; lethal.shield = 0; lethal.shieldCharges = 0
        var dead = lethal; dead.hp = 0
        let first = events(kind: "regular", victim: shielded, start: 60, end: 61, shield: true)
        var second = events(kind: "cannon", victim: lethal, start: 80, end: 81)
        second[0].id = 22; second[0].flight?.id = 10; second[1].id = 23; second[1].contact?.projectileId = 10
        let effects = first + second
        presenter.accept(effects, tanks: [dead])
        var bullets: [ArenaBullet] = []
        presenter.append(to: &bullets, tick: 100, now: 0)
        var bodies = [dead]; presenter.applyContacts(to: &bodies)
        bullets = []; presenter.append(to: &bullets, tick: 100, now: 0.05)
        bodies = [dead]; presenter.applyContacts(to: &bodies)
        XCTAssertEqual(bodies[0].x, 220); XCTAssertEqual(bodies[0].shieldCharges, 1)
        XCTAssertEqual(try XCTUnwrap(bullets.first { $0.id == 9 }).x, 199.5)
        XCTAssertTrue(presenter.effects(effects).isEmpty)
        bullets = []; presenter.append(to: &bullets, tick: 100, now: 0.06)
        bodies = [dead]; presenter.applyContacts(to: &bodies)
        XCTAssertEqual(bodies[0].hp, 1); XCTAssertEqual(bodies[0].shieldCharges, 0); XCTAssertEqual(bodies[0].x, 320)
        XCTAssertEqual(try XCTUnwrap(bullets.first { $0.id == 10 }).x, 289)
        XCTAssertEqual(presenter.effects(effects).filter { ["hit", "shield"].contains($0.kind) }.map(\.kind), ["shield"])
        bullets = []; presenter.append(to: &bullets, tick: 100, now: 0.07)
        bodies = [dead]; presenter.applyContacts(to: &bodies)
        XCTAssertEqual(bodies[0].hp, 0)
        XCTAssertEqual(presenter.effects(effects).filter { $0.kind == "hit" }.count, 1)
    }

    func testEveryBoostedLaserHitEmitsABeamEvenBetweenCosmeticFrames() {
        for finite in [false, true] {
            let arena = PracticeArena(seed: 42, name: "STAR", colorIndex: 0, botCount: 0,
                world: finite ? ArenaWorld(width: 840, height: 840, cols: 10, rows: 10) : nil)
            arena.snapshot.tanks = [ArenaTank(id: 1, x: 42, y: 42, powerTime: 10, starmanTime: 10, power: "laser", charges: 3)]
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            let previousID = arena.snapshot.effects.map(\.id).max() ?? 0
            arena.snapshot.tanks.append(ArenaTank(id: 2, x: 78, y: 42, bot: true, cooldown: 999, shield: 10, shieldCharges: 1))
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.effects.filter { $0.id > previousID }.map(\.kind), ["laser", "shield"])
            let rendered = arena.presentationSnapshot(fraction: 0, now: 0)
            XCTAssertTrue(rendered.effects.contains { $0.id > previousID && $0.kind == "laser" })
            XCTAssertFalse(rendered.effects.contains { $0.id > previousID && $0.kind == "shield" })
        }
    }
}
