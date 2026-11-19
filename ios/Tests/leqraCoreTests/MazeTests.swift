import Foundation
import XCTest
import CryptoKit
@testable import leqraCore

final class MazeTests: XCTestCase {
    func testFixedQueryCacheKeepsExactBoundsAndOriginalWallOrder() {
        var rules = RoomRules()
        rules.mapSize = "ultrawide"
        let world = FixedArena(rules: rules, name: "PERF", colorIndex: 0, botCount: 0, seed: 42).world
        let maze = InfiniteMaze(world: world)
        for index in 0..<1200 {
            let x = Double((index * 37) % 2100) - 50
            let y = Double((index * 53) % 1200) - 50
            for offset in [0.0, 0.75] {
                let x0 = x + offset, y0 = y + offset, x1 = x0 + 91, y1 = y0 + 173
                let expected = world.walls.filter { $0.x <= x1 && $0.x + $0.w >= x0 && $0.y <= y1 && $0.y + $0.h >= y0 }
                XCTAssertEqual(maze.walls(x0: x0, y0: y0, x1: x1, y1: y1), expected)
            }
        }
    }

    func testReportLaserGuideCPU() throws {
        guard ProcessInfo.processInfo.environment["LEQRA_PROFILE_GUIDE"] == "1" else { throw XCTSkip("Opt in to the laser guide CPU benchmark.") }
        let maze = InfiniteMaze(seed: 42)
        var samples: [Double] = []
        for run in 0..<240 {
            let start = ProcessInfo.processInfo.systemUptime
            for frame in 0..<24 {
                _ = maze.laserGuide(x: 420 + Double(run) * 0.75, y: 420, angle: Double(run * 24 + frame) / 1200, range: 36 * 84)
            }
            if run >= 40 { samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000 / 24) }
        }
        samples.sort()
        print("Laser guide CPU ms/frame p50=\(samples[100]) p95=\(samples[190]) p99=\(samples[198])")
    }

    func testBoundedLaserGuideMatchesFullSegmentSearchAtEveryRicochet() {
        for seed: UInt32 in [1, 42, 12345] {
            let maze = InfiniteMaze(seed: seed)
            for index in 0..<60 {
                let startX = Double(index % 7) * 83 + 31, startY = Double(index % 5) * 83 + 49
                let angle = Double(index) * 0.107, range = 36 * 84.0
                let actual = maze.laserGuide(x: startX, y: startY, angle: angle, range: range)
                guard let launch = maze.launchRay(x: startX, y: startY, angle: angle, kind: "laser", radius: 3) else { XCTAssertTrue(actual.isEmpty); continue }
                var x = launch.x, y = launch.y, ux = launch.ux, uy = launch.uy
                var left = range - launch.distance
                var expected: [BeamPoint] = []
                for segment in 0..<256 {
                    let wall = maze.rayHit(x: x, y: y, dx: ux * left, dy: uy * left, radius: 3)
                    let length = left * (wall?.fraction ?? 1)
                    if segment == 0 {
                        let crop = launch.bounced ? 0 : 28.0
                        expected.append(BeamPoint(x: x + ux * min(crop, length), y: y + uy * min(crop, length)))
                    }
                    x += ux * length; y += uy * length; left -= length
                    expected.append(BeamPoint(x: x, y: y))
                    guard let wall, left > 1e-7 else { break }
                    if wall.nx != 0 { ux = -ux }; if wall.ny != 0 { uy = -uy }
                    let nudge = min(0.001, left)
                    x += ux * nudge; y += uy * nudge; left -= nudge
                }
                XCTAssertEqual(actual.count, expected.count)
                for (a, b) in zip(actual, expected) {
                    XCTAssertEqual(a.x, b.x, accuracy: 1e-6)
                    XCTAssertEqual(a.y, b.y, accuracy: 1e-6)
                }
            }
        }
    }
    private struct Fixture: Decodable {
        var seed: UInt32
        var bounds: [Double]
        var count: Int
        var sha256: String
    }

    func testMazeMatchesGoAndBrowserFixtureHashes() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("src/tests/fixtures/infinite-maze.json"))
        for fixture in try JSONDecoder().decode([Fixture].self, from: data) {
            let b = fixture.bounds
            let walls = InfiniteMaze(seed: fixture.seed).walls(x0: b[0], y0: b[1], x1: b[2], y1: b[3])
            XCTAssertEqual(walls.count, fixture.count)
            // All fixture coordinates are integers. Match Go's struct-key order
            // and compact integer formatting rather than Swift's encoder order.
            let records = walls.map { w in
                "{\"x\":\(Int(w.x)),\"y\":\(Int(w.y)),\"w\":\(Int(w.w)),\"h\":\(Int(w.h)),\"axis\":\"\(w.axis)\",\"line\":\(Int(w.line))}"
            }.joined(separator: ",")
            let hash = SHA256.hash(data: Data("[\(records)]".utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hash, fixture.sha256, "seed \(fixture.seed)")
        }
    }

    func testCacheEvictionPreservesMazeAndBoundsMemory() {
        let maze = InfiniteMaze(seed: 42)
        let original = maze.walls(x0: -100, y0: -100, x1: 100, y1: 100)
        for index in 0..<150 {
            let x = Double(index * 672)
            _ = maze.walls(x0: x, y0: 0, x1: x + 100, y1: 100)
        }
        XCTAssertEqual(maze.cachedChunkCount, 128)
        XCTAssertEqual(maze.walls(x0: -100, y0: -100, x1: 100, y1: 100), original)
    }

    func testCircleTangencyAndGhostExit() throws {
        let maze = InfiniteMaze(seed: 1)
        let wall = try XCTUnwrap(maze.walls(x0: 0, y0: 0, x1: 100, y1: 100).first { $0.axis == "h" })
        let x = wall.x + wall.w / 2, tangentY = wall.y + wall.h + 17
        XCTAssertFalse(maze.blocked(x: x, y: tangentY, radius: 17))
        XCTAssertTrue(maze.blocked(x: x, y: tangentY - 0.01, radius: 17))
        let point = maze.phaseExit(x: x, y: wall.y + wall.h / 2)
        XCTAssertFalse(maze.blocked(x: point.x, y: point.y, radius: 17))
    }

    func testInvalidQueriesDoNotTrapOrAllocateChunks() {
        let maze = InfiniteMaze(seed: 1)
        XCTAssertTrue(maze.walls(x0: .nan, y0: 0, x1: 1, y1: 1).isEmpty)
        XCTAssertTrue(maze.walls(x0: 2, y0: 0, x1: 1, y1: 1).isEmpty)
        XCTAssertTrue(maze.walls(x0: 0, y0: 0, x1: 1e30, y1: 1).isEmpty)
        XCTAssertEqual(maze.cachedChunkCount, 0)
    }

    func testLaserGuideRicochetsFromEmbeddedOriginWhileCannonIgnoresInterior() {
        let world = ArenaWorld(width: 168, height: 168, cols: 2, rows: 2, walls: [
            MazeWall(x: 80, y: -4, w: 8, h: 176, axis: "v", line: 84),
            MazeWall(x: -4, y: -4, w: 8, h: 176, axis: "v", line: 0),
            MazeWall(x: 164, y: -4, w: 8, h: 176, axis: "v", line: 168)
        ])
        let maze = InfiniteMaze(world: world)
        let laser = maze.laserGuide(x: 42, y: 42, angle: 0, range: 150)
        XCTAssertGreaterThan(laser.count, 2)
        XCTAssertLessThanOrEqual(laser[1].x, 77)
        let embedded = maze.laserGuide(x: 84, y: 42, angle: 0, range: 150)
        XCTAssertGreaterThan(embedded.count, 1)
        XCTAssertLessThan(embedded[0].x, 80, "An embedded muzzle must begin on the firing side of the wall.")
        XCTAssertLessThan(embedded[1].x, embedded[0].x, "The guide must initially point back from the wall, just like the fired laser.")
        let cannon = maze.projectileGuide(x: 84, y: 42, angle: 0, kind: "cannon", range: 150, radius: 14)
        XCTAssertGreaterThan(cannon.count, 1)
        XCTAssertEqual(cannon[1].x, 150, accuracy: 1e-10)
    }
}
