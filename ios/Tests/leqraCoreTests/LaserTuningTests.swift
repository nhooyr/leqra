import Foundation
import XCTest
@testable import leqraCore

final class LaserTuningTests: XCTestCase {
    private func length(_ points: [BeamPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    func testInfinityDefaultLaserRangeIsThirtySixCells() {
        let maze = InfiniteMaze(seed: 42)
        let guide = maze.laserGuide(x: 42, y: 42, angle: 0)
        XCTAssertEqual(length(guide) + 28, 36 * 84, accuracy: 0.3)
        let arena = PracticeArena(seed: 42, name: "LASER", colorIndex: 0, botCount: 0)
        arena.snapshot.tanks = [ArenaTank(id: 1, x: 42, y: 42, powerTime: 10, power: "laser", charges: 3)]
        arena.step(input: GameInput(fire: true), dt: 1 / 60)
        XCTAssertEqual(length(arena.snapshot.effects.first { $0.kind == "laser" }?.points ?? []) + 28, 36 * 84, accuracy: 0.3)
    }

    func testUltrawideLaserUsesFullDoubledRangeBeyond128Ricochets() throws {
        // A short corridor forces more than128 reflections on the widest map.
        let world = ArenaWorld(width: 24 * 84, height: 14 * 84, cols: 24, rows: 14, walls: [
            MazeWall(x: -4, y: -4, w: 8, h: 1184, axis: "v", line: 0),
            MazeWall(x: 80, y: -4, w: 8, h: 1184, axis: "v", line: 84)
        ])
        let range = 4 * (world.width + world.height)
        let maze = InfiniteMaze(world: world)
        let guide = maze.laserGuide(x: 42, y: 42, angle: 0, range: range)
        XCTAssertGreaterThan(guide.count, 128); XCTAssertLessThanOrEqual(guide.count, 257)
        XCTAssertEqual(length(guide) + 28, range, accuracy: 0.3)
        let arena = PracticeArena(seed: 42, name: "LASER", colorIndex: 0, botCount: 0, world: world)
        arena.snapshot.tanks = [ArenaTank(id: 1, x: 42, y: 42, powerTime: 10, power: "laser", charges: 3)]
        arena.step(input: GameInput(fire: true), dt: 1 / 60)
        let beam = try XCTUnwrap(arena.snapshot.effects.first { $0.kind == "laser" })
        XCTAssertEqual(beam.points, guide)
        let encoded = try JSONEncoder().encode(ArenaSnapshot(tanks: arena.snapshot.tanks, effects: Array(repeating: beam, count: 64)))
        XCTAssertLessThan(encoded.count, 2 * 1024 * 1024, "Eight boosted lasers with retained beam history fit the native frame limit")
        XCTAssertEqual(try JSONDecoder().decode(ArenaSnapshot.self, from: encoded).effects.count, 64)
    }

    func testLaserAndCannonReloadInThirtyFourTicksWithMatchingHUDFallback() {
        for weapon in ["laser", "cannon"] {
            let arena = PracticeArena(seed: 42, name: "RELOAD", colorIndex: 0, botCount: 0)
            arena.snapshot.tanks = [ArenaTank(id: 1, x: 42, y: 42, powerTime: 10, power: weapon, charges: 3)]
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks[0].cooldownTotal, 0.85 * 2 / 3, accuracy: 1e-12, weapon)
            for _ in 0..<33 { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
            XCTAssertEqual(arena.snapshot.tanks[0].charges, 2, weapon)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks[0].charges, 1, weapon)
            let tank = ArenaTank(id: 1, cooldown: 0.85 / 3, powerTime: 10, power: weapon, charges: 3)
            XCTAssertEqual(PilotReadout(tank: tank, snapshot: ArenaSnapshot(tanks: [tank]), infinity: true).progress, 0.5, accuracy: 1e-12, weapon)
        }
    }
}
