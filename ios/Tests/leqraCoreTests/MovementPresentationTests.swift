import XCTest
@testable import leqraCore

final class MovementPresentationTests: XCTestCase {
    private let world = ArenaWorld(width: 8400, height: 8400, cols: 100, rows: 100)

    private func move(_ tank: inout ArenaTank, _ input: GameInput, _ dt: Double) {
        TankMovement.step(tank: &tank, input: input, dt: dt, walls: [], width: world.width, height: world.height)
    }

    private func pose(_ tank: ArenaTank, input: GameInput, fraction: Double, previous: ArenaTank? = nil) -> ArenaTank {
        TankMovement.presentation(tank: tank, input: input, fraction: fraction, previous: previous, move: move)
    }

    private func arena(ghost: Bool = true) -> PracticeArena {
        let arena = PracticeArena(seed: 42, name: "MOTION FOX", colorIndex: 0, botCount: 0, world: world)
        arena.snapshot.tanks = [ArenaTank(id: 1, x: 4200, y: 4200, speedTime: 100,
                                         ghostTime: ghost ? 100 : 0, speedStacks: 5)]
        var rules = RoomRules(); rules.pickupRate = "off"
        arena.configure(rules: rules)
        return arena
    }

    func testBoostedTurnVelocityRemainsContinuousAcrossAllPhysicsTickHeadings() {
        let input = GameInput(forward: true, right: true), epsilon = 0.0001
        for stacks in [0, 1, 5] {
            var tank = ArenaTank(x: 4200, y: 4200, speedTime: stacks == 0 ? 0 : 100,
                                 ghostTime: 100, speedStacks: stacks)
            for _ in 0..<240 {
                let end = pose(tank, input: input, fraction: 1)
                let before = pose(tank, input: input, fraction: 1 - epsilon)
                var next = tank
                move(&next, input, 1 / 60)
                let after = pose(next, input: input, fraction: epsilon, previous: tank)
                XCTAssertEqual(end.x, next.x, accuracy: 1e-10)
                XCTAssertEqual(end.y, next.y, accuracy: 1e-10)
                let scale = 60 / epsilon
                let velocityJump = hypot((after.x - next.x - end.x + before.x) * scale,
                                         (after.y - next.y - end.y + before.y) * scale)
                // The old fractional Euler path jumped by 7.8–74.4 px/s.
                XCTAssertLessThan(velocityJump, 0.02, "Speed stacks: \(stacks)")
                tank = next
            }
        }
    }

    func testWholeFrameBoostedTurnJerkFallsAtActualDisplayCadences() {
        func measurement(touch: Bool, refresh: Double, smooth: Bool) -> (jerk: Double, acceleration: Double, authority: ArenaTank) {
            var tank = ArenaTank(id: 1, x: 4200, y: 4200, speedTime: 120, ghostTime: 120, speedStacks: 5)
            var remainder = 0.0, time = 0.0, previous = tank
            var tick: UInt64 = 0
            var velocity: (x: Double, y: Double)?, acceleration: (x: Double, y: Double)?
            var jerks: [Double] = [], accelerations: [Double] = []
            let presenter = TankMotionPresenter(), dt = 1 / refresh
            for _ in 0..<Int(refresh * 8) {
                time += dt; remainder += dt
                let input = touch ? GameInput(stickX: cos(time * 6), stickY: sin(time * 6), touchAim: true)
                    : GameInput(forward: true, right: true, touchAim: false)
                while remainder + 1e-9 >= 1 / 60 {
                    move(&tank, input, 1 / 60)
                    remainder = max(0, remainder - 1 / 60); tick += 1
                }
                var image = tank
                if smooth {
                    image = presenter.present(tank: tank, input: input, tick: tick, fraction: remainder * 60, move: move)
                } else if remainder > 0 { move(&image, input, remainder) }
                let nextVelocity = (x: (image.x - previous.x) / dt, y: (image.y - previous.y) / dt)
                if let velocity {
                    let nextAcceleration = (x: (nextVelocity.x - velocity.x) / dt, y: (nextVelocity.y - velocity.y) / dt)
                    if time > 3 { accelerations.append(hypot(nextAcceleration.x, nextAcceleration.y)) }
                    if let acceleration, time > 3 {
                        jerks.append(hypot(nextAcceleration.x - acceleration.x, nextAcceleration.y - acceleration.y) / dt)
                    }
                    acceleration = nextAcceleration
                }
                velocity = nextVelocity; previous = image
            }
            func p95(_ values: [Double]) -> Double {
                let sorted = values.sorted()
                return sorted[Int(Double(sorted.count - 1) * 0.95)]
            }
            return (p95(jerks), p95(accelerations), tank)
        }
        for refresh in [90.0, 119.9892, 120.0, 144.0] {
            for touch in [false, true] {
                let before = measurement(touch: touch, refresh: refresh, smooth: false)
                let after = measurement(touch: touch, refresh: refresh, smooth: true)
                XCTAssertLessThan(after.jerk, before.jerk * 0.2, "\(refresh) Hz, touch=\(touch)")
                XCTAssertLessThan(after.acceleration, before.acceleration, "\(refresh) Hz, touch=\(touch)")
                XCTAssertEqual(after.authority, before.authority)
            }
        }
    }

    func testNinetyDegreeTouchTurnDoesNotInventReverseMotionWhileThrottleIsZero() {
        let tank = ArenaTank(x: 4200, y: 4200, speedTime: 10, ghostTime: 10, speedStacks: 5)
        let input = GameInput(stickY: 1, touchAim: true)
        for fraction in [0.125, 0.25, 0.5, 0.75, 1] {
            let image = pose(tank, input: input, fraction: fraction)
            XCTAssertEqual(image.x, tank.x, accuracy: 1e-10)
            XCTAssertEqual(image.y, tank.y, accuracy: 1e-10)
            XCTAssertGreaterThan(image.angle, tank.angle)
        }
    }

    func testSpeedExpiryDoesNotOvershootThenReverseBeforeTheNextTick() {
        for remaining in [0.001, 0.008, 1.0 / 60] {
            let tank = ArenaTank(x: 4200, y: 4200, speedTime: remaining, ghostTime: 10, speedStacks: 5)
            let input = GameInput(forward: true, right: true)
            var endpoint = tank
            move(&endpoint, input, 1 / 60)
            var previous = tank
            for fraction in [0.125, 0.25, 0.5, 0.75, 0.875, 1] {
                let image = pose(tank, input: input, fraction: fraction)
                XCTAssertGreaterThanOrEqual(image.x, previous.x)
                XCTAssertGreaterThanOrEqual(image.y, previous.y)
                XCTAssertLessThanOrEqual(image.x, endpoint.x)
                XCTAssertLessThanOrEqual(image.y, endpoint.y)
                XCTAssertLessThanOrEqual(image.angle, endpoint.angle)
                previous = image
            }
        }
    }

    func testNonTickReleaseReverseAndStickChangesDoNotResetThePresentedPose() throws {
        let arena = arena(), forward = GameInput(forward: true)
        let authority = arena.snapshot
        let before = try XCTUnwrap(arena.presentationSnapshot(fraction: 0.5, localInput: forward).tanks.first)
        for input in [GameInput(), GameInput(reverse: true), GameInput(stickY: 1), GameInput(stickX: 0.05)] {
            let image = try XCTUnwrap(arena.presentationSnapshot(fraction: 0.5, localInput: input).tanks.first)
            XCTAssertEqual(image.x, before.x, accuracy: 1e-9)
            XCTAssertEqual(image.y, before.y, accuracy: 1e-9)
            XCTAssertEqual(image.angle, before.angle, accuracy: 1e-9)
        }
        XCTAssertEqual(arena.snapshot, authority)
    }

    func testReleaseAtTickBoundaryCorrectsBriefPredictionGradually() throws {
        let arena = arena(), forward = GameInput(forward: true)
        let before = try XCTUnwrap(arena.presentationSnapshot(fraction: 0.5, localInput: forward).tanks.first)
        arena.step(input: GameInput(), dt: 1 / 60)
        let boundary = try XCTUnwrap(arena.presentationSnapshot(fraction: 0, localInput: GameInput()).tanks.first)
        let after = try XCTUnwrap(arena.presentationSnapshot(fraction: 0.5, localInput: GameInput()).tanks.first)
        XCTAssertGreaterThanOrEqual(boundary.x, before.x)
        XCTAssertLessThan(boundary.x - after.x, 2)
        XCTAssertEqual(arena.snapshot.tanks[0].x, 4200)
    }

    func testFrequentAnalogChangesStayBoundedAcrossDisplayCadences() throws {
        let cadences: [[Double]] = [[1 / 90], [1 / 120], [1 / 144], [1 / 100, 1 / 144, 1 / 120, 1 / 90]]
        for intervals in cadences {
            let arena = arena()
            var remainder = 0.0, time = 0.0
            var previousSource: ArenaTank?
            for frame in 0..<480 {
                let dt = intervals[frame % intervals.count]
                time += dt; remainder += dt
                let input = GameInput(stickX: cos(time * 12), stickY: sin(time * 12), touchAim: true)
                while remainder + 1e-9 >= 1 / 60 {
                    previousSource = arena.snapshot.tanks[0]
                    arena.step(input: input, dt: 1 / 60)
                    remainder = max(0, remainder - 1 / 60)
                }
                let source = arena.snapshot.tanks[0]
                let raw = pose(source, input: input, fraction: remainder * 60, previous: previousSource)
                let shown = try XCTUnwrap(arena.presentationSnapshot(fraction: remainder * 60, localInput: input).tanks.first)
                XCTAssertLessThanOrEqual(hypot(shown.x - raw.x, shown.y - raw.y), 544 / 60 + 1e-9)
                XCTAssertLessThanOrEqual(abs(atan2(sin(shown.angle - raw.angle), cos(shown.angle - raw.angle))), 0.3375 + 1e-9)
                XCTAssertTrue(shown.x.isFinite && shown.y.isFinite && shown.angle.isFinite)
            }
        }
    }

    func testPresentationCorrectionsNeverCrossWallsAndResetOnSpawn() throws {
        let wall = MazeWall(x: 80, y: 0, w: 8, h: 252, axis: "v", line: 84)
        let fixed = ArenaWorld(width: 252, height: 252, cols: 3, rows: 3, walls: [wall])
        let arena = PracticeArena(seed: 42, name: "MOTION FOX", colorIndex: 0, botCount: 0, world: fixed)
        arena.snapshot.tanks = [ArenaTank(id: 1, x: 60, y: 42, speedTime: 10, speedStacks: 5)]
        for fraction in [0.25, 0.5, 0.75] {
            for input in [GameInput(forward: true), GameInput(reverse: true), GameInput(stickY: 1)] {
                let image = try XCTUnwrap(arena.presentationSnapshot(fraction: fraction, localInput: input).tanks.first)
                XCTAssertFalse(arena.maze.blocked(x: image.x, y: image.y, radius: 17))
            }
        }
        arena.snapshot.tanks[0] = ArenaTank(id: 1, x: 126, y: 126, spawnSerial: 2)
        let respawned = try XCTUnwrap(arena.presentationSnapshot(fraction: 0.8, localInput: GameInput()).tanks.first)
        XCTAssertEqual(respawned.x, 126)
        XCTAssertEqual(respawned.y, 126)
    }

    func testGhostSolidificationKeepsItsDiscreteSafeExit() throws {
        let wall = MazeWall(x: 80, y: 0, w: 8, h: 168, axis: "v", line: 84)
        let fixed = ArenaWorld(width: 168, height: 168, cols: 2, rows: 2, walls: [wall])
        let arena = PracticeArena(seed: 42, name: "MOTION FOX", colorIndex: 0, botCount: 0, world: fixed)
        arena.snapshot.tanks = [ArenaTank(id: 1, x: 84, y: 42, ghostTime: 0.001)]
        let shown = try XCTUnwrap(arena.presentationSnapshot(fraction: 0.5, localInput: GameInput()).tanks.first)
        XCTAssertEqual(shown.ghostTime, 0)
        XCTAssertFalse(arena.maze.blocked(x: shown.x, y: shown.y, radius: 17))
        XCTAssertEqual(arena.snapshot.tanks[0].x, 84)
        XCTAssertEqual(arena.snapshot.tanks[0].ghostTime, 0.001)
    }

    func testGhostSlideCannotCurveOutsideTheFixedMapBoundary() {
        let movement: (inout ArenaTank, GameInput, Double) -> Void = {
            TankMovement.step(tank: &$0, input: $1, dt: $2, walls: [], width: 252, height: 252)
        }
        let input = GameInput(forward: true)
        let previous = ArenaTank(id: 1, x: 24, y: 100, angle: .pi * 0.75,
                                 speedTime: 10, ghostTime: 10, speedStacks: 5)
        var current = previous
        movement(&current, input, 1 / 60)
        XCTAssertEqual(current.x, 21)
        for fraction in [0.125, 0.25, 0.5, 0.75, 0.875] {
            let image = TankMovement.presentation(tank: current, input: input, fraction: fraction,
                previous: previous, move: movement)
            XCTAssertGreaterThanOrEqual(image.x, 21)
            XCTAssertGreaterThan(image.y, current.y)
        }
    }

    func testGhostPresentationKeepsOuterBoundsWhileAllowingInternalWallPhasing() throws {
        let wall = MazeWall(x: 80, y: 0, w: 8, h: 252, axis: "v", line: 84)
        let fixed = ArenaWorld(width: 252, height: 252, cols: 3, rows: 3, walls: [wall])
        let arena = PracticeArena(seed: 42, name: "MOTION FOX", colorIndex: 0, botCount: 0, world: fixed)
        arena.snapshot.tanks = [ArenaTank(id: 1, x: 24, y: 100, angle: .pi * 0.75,
                                         speedTime: 10, ghostTime: 10, speedStacks: 5)]
        var crossedInternalWall = false
        for frame in 0..<120 {
            let input = GameInput(stickX: frame < 40 ? -1 : 1, stickY: frame < 40 ? 1 : 0)
            if frame.isMultiple(of: 2) { arena.step(input: input, dt: 1 / 60) }
            let shown = try XCTUnwrap(arena.presentationSnapshot(fraction: frame.isMultiple(of: 2) ? 0 : 0.5,
                                                               localInput: input).tanks.first)
            XCTAssertTrue(TankMovement.presentationFitsBounds(tank: shown, world: fixed))
            if shown.x > 105 { crossedInternalWall = true }
        }
        XCTAssertTrue(crossedInternalWall)
    }
}
