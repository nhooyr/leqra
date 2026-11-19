import XCTest
@testable import leqraCore

final class MuzzlePresentationTests: XCTestCase {
    func testBarrelRetractsToWallAndExtendsWhenTurningAway() {
        let wall = MazeWall(x: 122, y: 50, w: 8, h: 100)
        let maze = InfiniteMaze(world: ArenaWorld(width: 840, height: 840, walls: [wall]))
        for recoil in [0.0, 0.5, 1.0] {
            var tank = ArenaTank(x: 100, y: 100, angle: 0)
            XCTAssertEqual(MuzzlePresentation.retraction(tank: tank, maze: maze, recoil: recoil), 9.5, accuracy: 1e-7)
            tank.angle = .pi
            XCTAssertEqual(MuzzlePresentation.retraction(tank: tank, maze: maze, recoil: recoil), recoil * 4, accuracy: 1e-7)
        }
    }

    func testTouchKeepsFastTurnsAndFineAim() {
        let touch = GameInput(stickX: 0, stickY: 1, touchAim: true)
        let stick = GameInput(stickX: 0, stickY: 1, touchAim: false)
        XCTAssertEqual(TankMovement.steer(angle: 0, input: touch, dt: 1 / 60).angle, 9 / 60, accuracy: 1e-12)
        XCTAssertEqual(TankMovement.steer(angle: 0, input: stick, dt: 1 / 60).angle, 5.8 / 60, accuracy: 1e-12)
        let fine = GameInput(stickX: cos(0.04), stickY: sin(0.04), touchAim: true)
        XCTAssertEqual(TankMovement.steer(angle: 0, input: fine, dt: 1 / 60).angle, 0.04, accuracy: 1e-12)
    }

    func testCornerGrazingUsesProjectileWidth() {
        let wall = MazeWall(x: 122, y: 102.5, w: 8, h: 40)
        let maze = InfiniteMaze(world: ArenaWorld(width: 840, height: 840, walls: [wall]))
        var tank = ArenaTank(x: 100, y: 100, angle: 0)
        XCTAssertGreaterThan(MuzzlePresentation.retraction(tank: tank, maze: maze), 0)
        tank.power = "rapid"
        XCTAssertEqual(MuzzlePresentation.retraction(tank: tank, maze: maze), 0)
    }

    func testNearWallLaunchDoesNotInstantlyTravelBackThroughBarrel() throws {
        let wall = MazeWall(x: 122, y: 50, w: 8, h: 100)
        for kind in ["", "rapid", "scatter", "homing", "grenade"] {
            let game = PracticeArena(seed: 42, name: "Pilot", colorIndex: 0, botCount: 0,
                world: ArenaWorld(width: 840, height: 840, walls: [wall]))
            var pilot = ArenaTank(id: 1, x: 100, y: 100)
            if !kind.isEmpty { PracticeArena.applyPower(tank: &pilot, kind: kind) }
            game.snapshot.tanks = [pilot]
            game.step(input: GameInput(fire: true), dt: 1 / 120)
            let bullet = try XCTUnwrap(game.snapshot.bullets.first, kind)
            let radius = kind == "rapid" ? 3.5 / 3 : kind == "homing" ? 5.0 : kind == "grenade" ? 6.0 : 3.5
            XCTAssertLessThan(bullet.vx, 0, kind)
            XCTAssertGreaterThanOrEqual(bullet.x, wall.x - radius - 0.13 - hypot(bullet.vx, bullet.vy) / 120, kind)
        }
    }

    func testPointBlankPlaybackStartsAtContactInsteadOfTankCentre() throws {
        for kind in ["", "rapid", "scatter", "homing", "grenade"] {
            let game = PracticeArena(seed: 42, name: "Pilot", colorIndex: 0, botCount: 0,
                world: ArenaWorld(width: 840, height: 840))
            var pilot = ArenaTank(id: 1, x: 100, y: 100)
            if !kind.isEmpty { PracticeArena.applyPower(tank: &pilot, kind: kind) }
            game.snapshot.tanks = [pilot, ArenaTank(id: 2, x: 135, y: 100)]
            game.step(input: GameInput(fire: true), dt: 1 / 120)
            let flight = try XCTUnwrap(game.snapshot.effects.compactMap(\.flight).first, kind)
            XCTAssertGreaterThan(try XCTUnwrap(flight.points.first).x, 101, kind)
        }
    }

    func testGhostCentreOutsideWallHandlesAnOverlappingMuzzle() throws {
        let wall = MazeWall(x: 122, y: 50, w: 8, h: 100)
        for kind in ["", "rapid", "scatter", "homing", "grenade"] {
            let game = PracticeArena(seed: 42, name: "Ghost", colorIndex: 0, botCount: 0,
                world: ArenaWorld(width: 840, height: 840, walls: [wall]))
            var pilot = ArenaTank(id: 1, x: 121, y: 100)
            PracticeArena.applyPower(tank: &pilot, kind: "ghost")
            if !kind.isEmpty { PracticeArena.applyPower(tank: &pilot, kind: kind) }
            XCTAssertLessThanOrEqual(30-MuzzlePresentation.retraction(tank: pilot, maze: game.maze), 1.1)
            game.snapshot.tanks = [pilot]
            game.step(input: GameInput(fire: true), dt: 1 / 120)
            let bullet = try XCTUnwrap(game.snapshot.bullets.first, kind)
            let radius = kind == "rapid" ? 3.5 / 3 : kind == "homing" ? 5.0 : kind == "grenade" ? 6.0 : 3.5
            XCTAssertLessThan(bullet.vx, 0)
            XCTAssertGreaterThanOrEqual(bullet.x, wall.x-radius-0.13-hypot(bullet.vx,bullet.vy)/120)
        }
    }
}
