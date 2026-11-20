import Foundation
import XCTest

@testable import leqraCore

final class LaserTuningTests: XCTestCase {
    private func length(_ points: [BeamPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    func testLaserPiercesEveryOpponentOnceAndKeepsDefenses() throws {
        let world = ArenaWorld(
            width: 672, height: 420, cols: 8, rows: 5,
            walls: [
                MazeWall(x: -4, y: -4, w: 680, h: 8, axis: "h", line: 0),
                MazeWall(x: -4, y: 416, w: 680, h: 8, axis: "h", line: 420),
                MazeWall(x: -4, y: -4, w: 8, h: 428, axis: "v", line: 0),
                MazeWall(x: 668, y: -4, w: 8, h: 428, axis: "v", line: 672),
            ])
        let arena = PracticeArena(seed: 42, name: "LASER", colorIndex: 0, botCount: 0, world: world)
        var rules = RoomRules()
        rules.pickupRate = "off"
        arena.configure(rules: rules)
        arena.snapshot.tanks = [
            ArenaTank(id: 1, x: 90, y: 210, team: 1, powerTime: 10, power: "laser", charges: 3),
            ArenaTank(id: 2, x: 190, y: 210, team: 2, shield: 10, shieldCharges: 3),
            ArenaTank(id: 3, x: 290, y: 210, team: 2),
            ArenaTank(id: 4, x: 390, y: 210, team: 2, spawnProtected: true, invulnerable: 1),
            ArenaTank(id: 5, x: 490, y: 210, team: 1),
            ArenaTank(id: 6, x: 590, y: 210, team: 2),
        ]
        arena.step(input: GameInput(fire: true), dt: 1 / 60)
        XCTAssertEqual(arena.snapshot.tanks.map(\.hp), [1, 1, 0, 1, 1, 0])
        XCTAssertEqual(arena.snapshot.tanks[1].shieldCharges, 2)
        XCTAssertEqual(arena.snapshot.tanks[0].charges, 2)
        let beam = try XCTUnwrap(arena.snapshot.effects.first { $0.kind == "laser" })
        XCTAssertEqual(length(beam.points), 4 * (world.width + world.height) - 28, accuracy: 0.1)
    }

    func testInfinityDefaultLaserRangeIsThirtySixCells() {
        let maze = InfiniteMaze(seed: 42)
        let guide = maze.laserGuide(x: 42, y: 42, angle: 0)
        XCTAssertEqual(length(guide) + 28, 36 * 84, accuracy: 0.3)
        let arena = PracticeArena(seed: 42, name: "LASER", colorIndex: 0, botCount: 0)
        arena.snapshot.tanks = [ArenaTank(id: 1, x: 42, y: 42, powerTime: 10, power: "laser", charges: 3)]
        arena.step(input: GameInput(fire: true), dt: 1 / 60)
        XCTAssertEqual(
            length(arena.snapshot.effects.first { $0.kind == "laser" }?.points ?? []) + 28, 36 * 84,
            accuracy: 0.3)
    }

    func testUltrawideLaserUsesFullDoubledRangeBeyond128Ricochets() throws {
        // A short corridor forces more than128 reflections on the widest map.
        let world = ArenaWorld(
            width: 24 * 84, height: 14 * 84, cols: 24, rows: 14,
            walls: [
                MazeWall(x: -4, y: -4, w: 8, h: 1184, axis: "v", line: 0),
                MazeWall(x: 80, y: -4, w: 8, h: 1184, axis: "v", line: 84),
            ])
        let range = 4 * (world.width + world.height)
        let maze = InfiniteMaze(world: world)
        let guide = maze.laserGuide(x: 42, y: 42, angle: 0, range: range)
        XCTAssertGreaterThan(guide.count, 128)
        XCTAssertLessThanOrEqual(guide.count, 257)
        XCTAssertEqual(length(guide) + 28, range, accuracy: 0.3)
        let arena = PracticeArena(seed: 42, name: "LASER", colorIndex: 0, botCount: 0, world: world)
        arena.snapshot.tanks = [ArenaTank(id: 1, x: 42, y: 42, powerTime: 10, power: "laser", charges: 3)]
        arena.step(input: GameInput(fire: true), dt: 1 / 60)
        let beam = try XCTUnwrap(arena.snapshot.effects.first { $0.kind == "laser" })
        XCTAssertEqual(beam.points, guide)
        let encoded = try JSONEncoder().encode(
            ArenaSnapshot(tanks: arena.snapshot.tanks, effects: Array(repeating: beam, count: 64)))
        XCTAssertLessThan(
            encoded.count, 2 * 1024 * 1024,
            "Eight boosted lasers with retained beam history fit the native frame limit")
        XCTAssertEqual(try JSONDecoder().decode(ArenaSnapshot.self, from: encoded).effects.count, 64)
    }

    func testLaserAndCannonReloadAtTheirOwnCadenceWithMatchingHUDFallback() {
        for (weapon, ticks) in [("laser", 17), ("cannon", 17)] {
            let cooldown = Double(ticks) / 60
            let arena = PracticeArena(seed: 42, name: "RELOAD", colorIndex: 0, botCount: 0)
            arena.snapshot.tanks = [ArenaTank(id: 1, x: 42, y: 42, powerTime: 10, power: weapon, charges: 3)]
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks[0].cooldownTotal, cooldown, accuracy: 1e-12, weapon)
            for _ in 0..<(ticks - 1) { arena.step(input: GameInput(fire: true), dt: 1 / 60) }
            XCTAssertEqual(arena.snapshot.tanks[0].charges, 2, weapon)
            arena.step(input: GameInput(fire: true), dt: 1 / 60)
            XCTAssertEqual(arena.snapshot.tanks[0].charges, 1, weapon)
            let tank = ArenaTank(id: 1, cooldown: cooldown / 2, powerTime: 10, power: weapon, charges: 3)
            XCTAssertEqual(
                PilotReadout(tank: tank, snapshot: ArenaSnapshot(tanks: [tank]), infinity: true).progress,
                0.5, accuracy: 1e-12, weapon)
        }
    }
}
