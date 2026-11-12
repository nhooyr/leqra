import XCTest
@testable import leqraCore

final class WallLaunchTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Wall: Decodable { var x, y, w, h: Double }
        struct Expected: Decodable { var x, y, ux, uy, distance: Double; var bounced, valid: Bool }
        var name: String
        var x, y, ux, uy, radius: Double
        var walls: [Wall]
        var bounds: [Double]?
        var expected: Expected
    }

    func testSharedLaunchGeometryMatchesWebAndServerRegardlessOfWallOrder() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("src/tests/fixtures/wall_launch.json")))
        for fixture in fixtures {
            for reverse in [false, true] {
                let walls = (reverse ? Array(fixture.walls.reversed()) : fixture.walls).map { MazeWall(x: $0.x, y: $0.y, w: $0.w, h: $0.h) }
                // cols/rows 0 selects unbounded fixture walls without a spatial
                // index. Offset non-rim fixtures to leave finite bounds distant.
                let world = ArenaWorld(width: fixture.bounds == nil ? 20000 : 504,
                                       height: fixture.bounds == nil ? 20000 : 420,
                                       cols: 0, rows: 0, walls: walls)
                let maze = InfiniteMaze(world: world)
                let launch = maze.launchRay(x: fixture.x, y: fixture.y, angle: atan2(fixture.uy, fixture.ux), kind: "laser", radius: fixture.radius)
                XCTAssertEqual(launch != nil, fixture.expected.valid, fixture.name)
                guard let launch else { continue }
                XCTAssertEqual(launch.x, fixture.expected.x, accuracy: 1e-7, fixture.name)
                XCTAssertEqual(launch.y, fixture.expected.y, accuracy: 1e-7, fixture.name)
                XCTAssertEqual(launch.ux, fixture.expected.ux, accuracy: 1e-7, fixture.name)
                XCTAssertEqual(launch.uy, fixture.expected.uy, accuracy: 1e-7, fixture.name)
                XCTAssertEqual(launch.distance, fixture.expected.distance, accuracy: 1e-7, fixture.name)
                XCTAssertEqual(launch.bounced, fixture.expected.bounced, fixture.name)
            }
        }
    }

    func testEveryPhasedWeaponFiresAtWallFaceAndEmbeddedOrigin() throws {
        let fixedWall = MazeWall(x: 248, y: 248, w: 8, h: 92, axis: "v", line: 252)
        for fixed in [false, true] {
            let geometry = fixed ? InfiniteMaze(world: ArenaWorld(width: 1680, height: 1680, cols: 20, rows: 20, walls: [fixedWall])) : InfiniteMaze(seed: 42)
            let wall = try XCTUnwrap(geometry.walls(x0: 200, y0: 200, x1: 400, y1: 400).first { $0.axis == "v" })
            for phase in ["ghost", "starman"] {
                for weapon in ["", "rapid", "scatter", "homing", "grenade", "laser", "cannon"] {
                    for embedded in [false, true] {
                        let context = "fixed=\(fixed) \(phase)/\(weapon) embedded=\(embedded)"
                        let arena = PracticeArena(seed: 42, name: "Pilot", colorIndex: 0, botCount: 0, world: geometry.world)
                        var pilot = ArenaTank(id: 1, name: "Pilot", x: embedded ? wall.x + wall.w / 2 : wall.x - 1, y: wall.y + wall.h / 2)
                        PracticeArena.applyPower(tank: &pilot, kind: phase)
                        if !weapon.isEmpty { PracticeArena.applyPower(tank: &pilot, kind: weapon) }
                        arena.snapshot.tanks = [pilot]
                        arena.step(input: GameInput(fire: true), dt: 1 / 120)
                        let fired = arena.snapshot.tanks[0]
                        XCTAssertGreaterThan(fired.recoil, 0, context)
                        if phase == "starman" {
                            XCTAssertEqual(fired.charges, pilot.charges, context)
                            XCTAssertEqual(fired.machineRounds, pilot.machineRounds, context)
                        } else if weapon == "rapid" {
                            XCTAssertEqual(fired.machineRounds, pilot.machineRounds - 1, context)
                        } else if pilot.charges > 0 {
                            XCTAssertEqual(fired.charges, pilot.charges - 1, context)
                        }
                        if weapon == "laser" {
                            let guide = geometry.laserGuide(x: pilot.x, y: pilot.y, angle: 0)
                            XCTAssertGreaterThanOrEqual(guide.count, 2, context)
                            if guide.count >= 2 { XCTAssertLessThan(guide[1].x, guide[0].x, context) }
                        } else {
                            XCTAssertEqual(arena.snapshot.bullets.count, weapon == "scatter" ? 3 : 1, context)
                            for bullet in arena.snapshot.bullets {
                                if weapon == "cannon" { XCTAssertGreaterThan(bullet.vx, 0, context) }
                                else { XCTAssertLessThan(bullet.vx, 0, context); XCTAssertGreaterThanOrEqual(bullet.bounces, 1, context) }
                            }
                        }
                    }
                }
            }
        }
    }
}
