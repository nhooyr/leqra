import XCTest
@testable import leqraCore

final class ProjectileRicochetTests: XCTestCase {
    private let span = 1.0 / 30
    private var world: ArenaWorld { ArenaWorld(width: 168, height: 168, cols: 2, rows: 2,
        walls: [MazeWall(x: 80, y: 0, w: 8, h: 168, axis: "v", line: 84)]) }

    func testValidatedRicochetMovesBeforeAndAfterWallWithoutCrossingIt() throws {
        for kind in ["", "rapid", "scatter"] {
            let radius = kind == "rapid" ? 3.5 / 3 : 3.5, speed = kind == "rapid" ? 846.0 : 282.0
            let first = ArenaBullet(id: 1, x: 70, y: 42, vx: speed, owner: 1, kind: kind, life: 5)
            let contact = 80 - radius
            var second = first; second.x = 2 * contact - first.x - speed * span - 0.08
            second.vx = -speed; second.bounces = 1; second.life -= span
            let path = try XCTUnwrap(ProjectileRicochetPath(from: first, to: second, span: span, maze: InfiniteMaze(world: world)))
            let before = path.sample(fraction: (contact - first.x) / speed / span * 0.5)
            let after = path.sample(fraction: 0.95)
            XCTAssertGreaterThan(before.x, first.x)
            XCTAssertGreaterThan(before.vx, 0); XCTAssertLessThan(after.vx, 0)
            XCTAssertGreaterThan(after.x, second.x)
            for fraction in stride(from: 0.0, through: 1, by: 0.025) {
                let bullet = path.sample(fraction: fraction)
                XCTAssertLessThanOrEqual(bullet.x + radius, 80 + 1e-8)
            }
            var invalid = second; invalid.x += 2
            XCTAssertNil(ProjectileRicochetPath(from: first, to: invalid, span: span, maze: InfiniteMaze(world: world)))
            invalid = second; invalid.bounces = 2
            XCTAssertNil(ProjectileRicochetPath(from: first, to: invalid, span: span, maze: InfiniteMaze(world: world)))
        }
    }

    func testTimelineUsesValidatedPathInsteadOfFreezingTheWholeSnapshotPair() throws {
        let timeline = RenderTimeline(localID: 99) { _, _, _ in }
        var first = ArenaSnapshot(tick: 60, world: world)
        first.bullets = [ArenaBullet(id: 1, x: 70, y: 42, vx: 282, owner: 1, life: 5)]
        timeline.accept(first, at: 0)
        var second = first; second.tick = 62
        second.bullets[0].x = 73.52; second.bullets[0].vx = -282
        second.bullets[0].bounces = 1; second.bullets[0].life -= span
        timeline.accept(second, at: span)
        let shown = try XCTUnwrap(timeline.render(dt: 0.1, input: GameInput(), now: 0.1) { _ in }?.bullets.first)
        XCTAssertGreaterThan(shown.x, 73)
        XCTAssertLessThanOrEqual(shown.x, 76.5)
    }
}
