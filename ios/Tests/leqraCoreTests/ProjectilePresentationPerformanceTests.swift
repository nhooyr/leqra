import Foundation
import XCTest
@testable import leqraCore

final class ProjectilePresentationPerformanceTests: XCTestCase {
    private func fixture(count: Int = 864) -> (tanks: [ArenaTank], effects: [ArenaEffect]) {
        let tanks = (1...8).map { ArenaTank(id: $0, x: 140, y: 42, hp: 0, spawnSerial: 2) }
        let effects = (1...count).flatMap { id -> [ArenaEffect] in
            let flight = CannonFlight(id: id, owner: 0, colorIndex: 0, startTick: 0, endTick: 6,
                points: [CannonFlightPoint(x: 40, y: 42, tick: 0), CannonFlightPoint(x: 119.5, y: 42, tick: 6)], kind: "scatter", radius: 3.5)
            let path = ArenaEffect(id: id * 2, kind: "projectileFlight", tick: 6, flight: flight)
            guard id > count - 8 else { return [path] }
            let victim = ArenaTank(id: 1 + id % 8, x: 140, y: 42, spawnSerial: 2)
            return [path, ArenaEffect(id: id * 2 + 1, kind: "hit", tick: 6,
                contact: ImpactContact(projectileId: id, kind: "scatter", tick: 6, target: victim.id, spawnSerial: 2, before: ImpactContactPose(victim)))]
        }
        return (tanks, effects)
    }

    func testRetainedShotgunBatchDisplaysEveryExactEndpointBeforeItsContacts() {
        let fixture = fixture(), presenter = CannonFlightPresenter()
        presenter.accept(fixture.effects, throughTick: 6, tanks: fixture.tanks)
        var bullets: [ArenaBullet] = []
        presenter.append(to: &bullets, tick: 6, now: 0.05)
        var tanks = fixture.tanks; presenter.applyContacts(to: &tanks)
        XCTAssertEqual(bullets.count, 864)
        XCTAssertTrue(bullets.allSatisfy { $0.x == 119.5 && $0.y == 42 })
        XCTAssertTrue(tanks.allSatisfy { $0.hp == 1 })
        XCTAssertFalse(presenter.effects(fixture.effects).contains { $0.contact != nil })
        bullets = []; presenter.append(to: &bullets, tick: 6, now: 0.11)
        tanks = fixture.tanks; presenter.applyContacts(to: &tanks)
        XCTAssertTrue(bullets.isEmpty); XCTAssertTrue(tanks.allSatisfy { $0.hp == 0 })
        XCTAssertEqual(presenter.effects(fixture.effects).filter { $0.contact != nil }.count, 8)
    }

    func testReportRetainedShotgunBatchCPU() throws {
        guard ProcessInfo.processInfo.environment["LEQRA_PROFILE_PRESENTATION"] == "1" else { throw XCTSkip("Opt in to the retained projectile/contact CPU benchmark.") }
        let fixture = fixture(), presenter = CannonFlightPresenter()
        func run() {
            presenter.reset(); presenter.accept(fixture.effects, throughTick: 6, tanks: fixture.tanks)
            for time in [0.05, 0.11, 0.12] {
                var bullets: [ArenaBullet] = []
                presenter.append(to: &bullets, tick: 6, now: time)
                var tanks = fixture.tanks; presenter.applyContacts(to: &tanks)
                _ = presenter.effects(fixture.effects)
            }
        }
        for _ in 0..<30 { run() }
        var samples: [Double] = []
        for _ in 0..<150 {
            let start = ProcessInfo.processInfo.systemUptime; run()
            samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        samples.sort()
        print("864 retained shotgun flights +8 contacts, accept+3frames CPU ms: p50=\(samples[75]) p95=\(samples[142]) p99=\(samples[148]) max=\(samples[149])")
    }
}
