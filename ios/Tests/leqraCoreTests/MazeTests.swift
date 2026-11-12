import XCTest
import CryptoKit
@testable import leqraCore

final class MazeTests: XCTestCase {
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

    func testLaserGuideRicochetsAndHidesInsideWallWhileCannonIgnoresInterior() {
        let world = ArenaWorld(width: 168, height: 168, cols: 2, rows: 2, walls: [
            MazeWall(x: 80, y: -4, w: 8, h: 176, axis: "v", line: 84),
            MazeWall(x: -4, y: -4, w: 8, h: 176, axis: "v", line: 0),
            MazeWall(x: 164, y: -4, w: 8, h: 176, axis: "v", line: 168)
        ])
        let maze = InfiniteMaze(world: world)
        let laser = maze.laserGuide(x: 42, y: 42, angle: 0, range: 150)
        XCTAssertGreaterThan(laser.count, 2)
        XCTAssertLessThanOrEqual(laser[1].x, 77)
        XCTAssertTrue(maze.laserGuide(x: 84, y: 42, angle: 0, range: 150).isEmpty)
        let cannon = maze.projectileGuide(x: 84, y: 42, angle: 0, kind: "cannon", range: 150, radius: 14)
        XCTAssertGreaterThan(cannon.count, 1)
        XCTAssertEqual(cannon[1].x, 150, accuracy: 1e-10)
    }
}
