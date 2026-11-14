import XCTest
@testable import leqraCore

final class MovementTests: XCTestCase {
    func testStarmanExpiryIsAgedDuringPredictionAndOnlyOnceInPractice() {
        var tank = ArenaTank(x: 420, y: 420, starmanTime: 1 / 120)
        TankMovement.step(tank: &tank, input: GameInput(forward: true), dt: 1 / 60, walls: [], width: 840, height: 840)
        XCTAssertEqual(tank.starmanTime, 0)
        XCTAssertEqual(tank.x, 420 + 128.0 / 60, accuracy: 1e-10)
        let arena = PracticeArena(seed: 42, name: "Pilot", colorIndex: 0, botCount: 0)
        arena.snapshot.tanks[0].starmanTime = 2.5 / 60
        arena.step(input: GameInput(), dt: 1 / 60)
        XCTAssertEqual(arena.snapshot.tanks[0].starmanTime, 1.5 / 60, accuracy: 1e-10)
        _ = arena.presentationSnapshot(fraction: 0.5)
        XCTAssertEqual(arena.snapshot.tanks[0].starmanTime, 1.5 / 60, accuracy: 1e-10)
    }
    func testStarmanMatchesTwoSpeedPickupsWithoutReplacingStrongerOrStoredBoosts() {
        let world = ArenaWorld(width: 840, height: 840, cols: 10, rows: 10)
        for bot in [false, true] {
            for collected in 0...5 {
                var star = ArenaTank(x: 420, y: 420, bot: bot, speedTime: collected == 0 ? 0 : 5,
                                     starmanTime: 8, speedStacks: collected, difficulty: "normal")
                var reference = star
                reference.starmanTime = 0; reference.speedTime = 5; reference.speedStacks = max(2, collected)
                let input = GameInput(forward: true, right: true, stickX: bot ? 1 : 0, stickY: bot ? 1 : 0)
                if bot {
                    TankMovement.stepBot(tank: &star, input: input, dt: 1 / 60, world: world)
                    TankMovement.stepBot(tank: &reference, input: input, dt: 1 / 60, world: world)
                } else {
                    TankMovement.step(tank: &star, input: input, dt: 1 / 60, walls: [], width: 840, height: 840)
                    TankMovement.step(tank: &reference, input: input, dt: 1 / 60, walls: [], width: 840, height: 840)
                }
                XCTAssertEqual(star.x, reference.x, accuracy: 1e-10)
                XCTAssertEqual(star.y, reference.y, accuracy: 1e-10)
                XCTAssertEqual(star.angle, reference.angle, accuracy: 1e-10)
                XCTAssertEqual(star.speedStacks, collected)
                XCTAssertEqual(star.speedTime, collected == 0 ? 0 : 5 - 1 / 60, accuracy: 1e-10)
                star.starmanTime = 0
                XCTAssertEqual(TankMovement.effectiveSpeedStacks(star), collected)
            }
        }
        var star = ArenaTank(x: 420, y: 420, starmanTime: 8), speed = star
        speed.starmanTime = 0; speed.speedTime = 5; speed.speedStacks = 2
        let maze = InfiniteMaze(seed: 42)
        star.ghostTime = 8; speed.ghostTime = 8
        TankMovement.step(tank: &star, input: GameInput(forward: true, right: true), dt: 1 / 60, maze: maze)
        TankMovement.step(tank: &speed, input: GameInput(forward: true, right: true), dt: 1 / 60, maze: maze)
        XCTAssertEqual(star.x, speed.x, accuracy: 1e-10); XCTAssertEqual(star.y, speed.y, accuracy: 1e-10)
        XCTAssertEqual(star.angle, speed.angle, accuracy: 1e-10)
    }
    private struct Fixture: Decodable {
        var name: String
        var angle: Double
        var input: GameInput
        var turnScale: Double
        var angleAfter: Double
        var throttle: Double
    }

    func testTouchSteeringMatchesSharedFixtures() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("src/tests/fixtures/touch-steering.json"))
        for fixture in try JSONDecoder().decode([Fixture].self, from: data) {
            let result = TankMovement.steer(angle: fixture.angle, input: fixture.input, turnScale: fixture.turnScale, dt: 1 / 60)
            XCTAssertEqual(result.angle, fixture.angleAfter, accuracy: 1e-12, fixture.name)
            XCTAssertEqual(result.throttle, fixture.throttle, accuracy: 1e-12, fixture.name)
        }
    }

    func testBoostExpiryAndGhostExitPrecedeMovement() {
        let maze = InfiniteMaze(seed: 42)
        var tank = ArenaTank(x: 0, y: 0, speedTime: 1 / 120, ghostTime: 1 / 120, speedStacks: 5)
        TankMovement.step(tank: &tank, input: GameInput(), dt: 1 / 60, maze: maze)
        XCTAssertEqual(tank.speedTime, 0)
        XCTAssertEqual(tank.speedStacks, 0)
        XCTAssertEqual(tank.ghostTime, 0)
        XCTAssertFalse(maze.blocked(x: tank.x, y: tank.y, radius: 17))
    }

    func testFixedMazePredictionSeparatesWallsAndClampsBounds() {
        let wall = MazeWall(x: 80, y: 0, w: 8, h: 200, axis: "v", line: 84)
        var tank = ArenaTank(x: 62, y: 42)
        for _ in 0..<60 {
            TankMovement.step(tank: &tank, input: GameInput(forward: true), dt: 1 / 60, walls: [wall], width: 168, height: 168)
        }
        XCTAssertLessThan(tank.x, 63.001)
        tank.x = -500
        TankMovement.step(tank: &tank, input: GameInput(), dt: 1 / 60, walls: [], width: 168, height: 168)
        XCTAssertEqual(tank.x, 21)
    }

    func testFixedGhostExpiryChoosesNearestSafeCellInterior() {
        let wall = MazeWall(x: 80, y: 0, w: 8, h: 168, axis: "v", line: 84)
        var tank = ArenaTank(x: 84, y: 42, ghostTime: 1 / 120)
        TankMovement.step(tank: &tank, input: GameInput(), dt: 1 / 60, walls: [wall], width: 168, height: 168)
        XCTAssertEqual(tank.x, 62.99, accuracy: 1e-10)
        XCTAssertEqual(tank.y, 42)
        XCTAssertEqual(tank.invulnerable, 0)
    }

    func testFiniteBotsUseDifficultySpeedAndTurnWithSharedBoosts() {
        let world = ArenaWorld(width: 840, height: 840, cols: 10, rows: 10)
        for (level, speed, turn) in [("dumb", 60.0, 1.8), ("easy", 89.0, 2.8), ("normal", 108.0, 3.4),
                                      ("hard", 123.0, 4.3), ("godlike", 123.0, 4.3)] {
            for stacks in [0, 3] {
                var tank = ArenaTank(x: 420, y: 420, bot: true, speedTime: stacks == 0 ? 0 : 5,
                                     speedStacks: stacks, difficulty: level)
                TankMovement.stepBot(tank: &tank, input: GameInput(stickX: 1), dt: 1 / 60, world: world)
                XCTAssertEqual(tank.x, 420 + speed * (1 + 0.65 * Double(stacks)) / 60, accuracy: 1e-10, level)
                XCTAssertEqual(tank.y, 420, accuracy: 1e-10)
                tank.x = 420; tank.y = 420
                TankMovement.stepBot(tank: &tank, input: GameInput(stickY: 1), dt: 1 / 60, world: world)
                XCTAssertEqual(tank.angle, turn * (1 + 0.25 * Double(stacks)) / 60, accuracy: 1e-10, level)
            }
        }
    }
}
