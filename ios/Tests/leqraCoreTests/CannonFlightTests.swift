import Foundation
import XCTest
@testable import leqraCore

final class CannonFlightTests: XCTestCase {
    private func flight(kind: String = "cannon", id: Int = 8, start: Double = 60, end: Double = 61) -> CannonFlight {
        CannonFlight(id: id, owner: 0, colorIndex: 2, startTick: start, endTick: end,
            points: [CannonFlightPoint(x: 100, y: 100, tick: start), CannonFlightPoint(x: 110, y: 100, tick: end)], kind: kind, radius: 14)
    }

    func testEveryUnseenTerminalProjectileHasABoundedVisibleTraversalAndOneImpact() {
        for kind in ["regular", "rapid", "scatter", "homing", "grenade", "cannon"] {
            let presenter = CannonFlightPresenter(), record = flight(kind: kind)
            let effect = ArenaEffect(id: 20, kind: kind == "grenade" ? "blast" : "impact", flight: record)
            presenter.accept([effect])
            var bullets = [ArenaBullet(id: 8, x: 999, kind: kind)]
            presenter.append(to: &bullets, tick: 64, now: 0)
            XCTAssertEqual(bullets.count, 1, "No duplicate authoritative/visual projectile")
            XCTAssertEqual(bullets[0].x, 100); XCTAssertEqual(bullets[0].kind, kind == "regular" ? "" : kind)
            XCTAssertTrue(presenter.effects([effect]).isEmpty)
            for frame in 1...7 {
                bullets = []
                presenter.append(to: &bullets, tick: 64, now: Double(frame) / 120)
                XCTAssertTrue(bullets.allSatisfy { $0.x >= 100 && $0.x <= 110 })
                if frame <= 6 { XCTAssertFalse(bullets.isEmpty) }
            }
            XCTAssertTrue(bullets.isEmpty)
            XCTAssertEqual(presenter.effects([]), [effect], "Terminal effects survive wire event expiry")
            presenter.accept([effect]); presenter.append(to: &bullets, tick: 70, now: 1)
            XCTAssertTrue(bullets.isEmpty); XCTAssertTrue(presenter.effects([]).isEmpty)
        }
    }

    func testNormalCannonPathUsesAuthoritativeBounceVerticesAndNeverOvershoots() {
        let record = CannonFlight(id: 8, owner: 1, colorIndex: 0, startTick: 60, endTick: 66,
            points: [CannonFlightPoint(x: 100, y: 100, tick: 60), CannonFlightPoint(x: 120, y: 100, tick: 63),
                     CannonFlightPoint(x: 100, y: 100, tick: 66)])
        let presenter = CannonFlightPresenter(), effect = ArenaEffect(id: 20, kind: "impact", flight: record)
        presenter.accept([effect])
        var bullets: [ArenaBullet] = []
        presenter.append(to: &bullets, tick: 62, now: 0)
        XCTAssertEqual(bullets.first?.x ?? 0, 100 + 40.0 / 3, accuracy: 1e-10)
        bullets = []; presenter.append(to: &bullets, tick: 65, now: 0.01)
        XCTAssertEqual(bullets.first?.x ?? 0, 100 + 20.0 / 3, accuracy: 1e-10)
        bullets = []; presenter.append(to: &bullets, tick: 67, now: 0.02)
        XCTAssertTrue(bullets.isEmpty); XCTAssertEqual(presenter.effects([]), [effect])
    }

    func testBaselineMalformedAndZeroLengthFlightSafety() throws {
        let presenter = CannonFlightPresenter(), old = ArenaEffect(id: 20, kind: "impact", flight: flight())
        presenter.accept([old], baseline: true); presenter.accept([old])
        var bullets: [ArenaBullet] = []
        presenter.append(to: &bullets, tick: 65, now: 0); XCTAssertTrue(bullets.isEmpty)
        var invalid = flight(id: 9); invalid.points[0].x = .nan
        presenter.accept([ArenaEffect(id: 21, flight: invalid)])
        presenter.append(to: &bullets, tick: 65, now: 0); XCTAssertTrue(bullets.isEmpty)
        var zero = flight(id: 10, start: 65, end: 65); zero.points[1].x = 100
        presenter.accept([ArenaEffect(id: 22, kind: "impact", flight: zero)])
        presenter.append(to: &bullets, tick: 65, now: 0)
        XCTAssertEqual(bullets.first?.x, 100); XCTAssertEqual(bullets.first?.vx, 0)
        XCTAssertEqual(try JSONDecoder().decode(ArenaEffect.self, from: JSONEncoder().encode(old)), old)
    }

    func testAudioAcceptsDelayedImpactAfterNewerShotWithoutReplayingEither() {
        var router = AudioEventRouter(), snapshot = ArenaSnapshot(tanks: [ArenaTank(id: 1)])
        _ = router.consume(snapshot: snapshot, localID: 1, infinity: false, online: true, now: 0)
        snapshot.effects = [ArenaEffect(id: 22, kind: "shot:", owner: 1)]
        XCTAssertEqual(router.consume(snapshot: snapshot, localID: 1, infinity: false, online: true, now: 0.1).map(\.cue), [.regular])
        snapshot.effects.append(ArenaEffect(id: 20, kind: "impact"))
        XCTAssertEqual(router.consume(snapshot: snapshot, localID: 1, infinity: false, online: true, now: 0.2).map(\.cue), [.impact])
        XCTAssertTrue(router.consume(snapshot: snapshot, localID: 1, infinity: false, online: true, now: 0.3).isEmpty)
    }

    func testPointBlankPracticeKillRendersItsProjectileAfterAuthoritativeDeath() throws {
        for kind in ["", "rapid", "scatter", "homing", "grenade", "cannon"] {
            let world = ArenaWorld(width: 840, height: 840, cols: 10, rows: 10)
            let arena = PracticeArena(seed: 42, name: "Human", colorIndex: 0, botCount: 0, world: world)
            arena.snapshot.tanks[0] = ArenaTank(id: 1, x: 420, y: 420, powerTime: 10, power: kind, charges: 10, machineRounds: 100)
            arena.snapshot.tanks.append(ArenaTank(id: 2, x: 456, y: 420, bot: true, cooldown: 999))
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks[1].hp, 0, kind)
            XCTAssertTrue(arena.snapshot.bullets.isEmpty || kind == "scatter", kind)
            let presented = arena.presentationSnapshot(fraction: 0, now: 0)
            XCTAssertTrue(presented.bullets.contains { $0.owner == 1 && $0.kind == kind }, kind)
            XCTAssertEqual(presented.tanks[1].hp, 0, kind)
            XCTAssertFalse(presented.effects.contains { $0.flight != nil && ["impact", "blast"].contains($0.kind) }, kind)
            XCTAssertEqual(arena.snapshot.tanks[1].hp, 0)
        }
    }

    func testWinningPracticeCannonFlightFinishesAfterTheSimulationStops() {
        let arena = PracticeArena(seed: 42, name: "Human", colorIndex: 0, botCount: 0)
        var rules = RoomRules(); rules.infinity = true; rules.infinityTarget = 1
        arena.configure(rules: rules)
        arena.snapshot.tanks[0] = ArenaTank(id: 1, x: 42, y: 42, powerTime: 10, power: "cannon", charges: 10)
        arena.snapshot.tanks.append(ArenaTank(id: 2, x: 78, y: 42, bot: true, cooldown: 999))
        arena.step(input: GameInput(fire: true), dt: 1 / 60)
        XCTAssertNotNil(arena.snapshot.result)
        let authority = arena.snapshot
        XCTAssertFalse(arena.presentationSnapshot(fraction: 0, now: 0).bullets.isEmpty)
        XCTAssertTrue(arena.hasPendingProjectileFlights)
        arena.step(input: GameInput(forward: true, fire: true), dt: 1 / 60)
        XCTAssertEqual(arena.snapshot, authority)
        XCTAssertTrue(arena.presentationSnapshot(fraction: 0, now: 0.1).bullets.isEmpty)
        XCTAssertFalse(arena.hasPendingProjectileFlights)
        XCTAssertEqual(arena.snapshot, authority)
    }
}
