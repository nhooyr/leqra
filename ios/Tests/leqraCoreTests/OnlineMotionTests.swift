import XCTest
@testable import leqraCore

final class OnlineMotionTests: XCTestCase {
    private func state(tick: UInt64, x: Double, ack: UInt64 = 0, ghost: Double = 0,
                       spawn: Int = 1, world: ArenaWorld? = nil) -> ArenaSnapshot {
        var tank = ArenaTank(id: 1, name: "PILOT", x: x, y: 210, ack: ack, ackSteps: 1,
                             spawnSerial: spawn, track: x, speedTime: 15, ghostTime: ghost, speedStacks: 5)
        tank.angle = 0
        var snapshot = ArenaSnapshot(tick: tick, tanks: [tank])
        snapshot.generation = 1
        snapshot.world = world
        return snapshot
    }

    private func timeline(localID: Int = 1) -> RenderTimeline {
        RenderTimeline(localID: localID) { tank, input, dt in
            if input.forward { tank.x += dt * 544; tank.track += dt * 544 }
        }
    }

    func testSmallAuthoritativeCorrectionsPreserveTheCurrentRenderedPose() throws {
        let timeline = timeline()
        timeline.accept(state(tick: 0, x: 100), at: 0)
        let first = try XCTUnwrap(timeline.render(dt: 1 / 60, input: GameInput(forward: true), now: 1 / 60) { _ in }?.tanks.first)
        timeline.accept(state(tick: 1, x: first.x + 3, ack: 1), at: 1 / 60)
        let corrected = try XCTUnwrap(timeline.render(dt: 0, input: GameInput(), now: 1 / 60) { _ in }?.tanks.first)
        XCTAssertEqual(corrected.x, first.x, accuracy: 1e-9, "A snapshot correction must not jump the tank and its camera between display frames.")
        var settled = corrected
        for frame in 1...120 {
            settled = try XCTUnwrap(timeline.render(dt: 1 / 120, input: GameInput(), now: 1 / 60 + Double(frame) / 120) { _ in }?.tanks.first)
        }
        XCTAssertEqual(settled.x, first.x + 3, accuracy: 0.001, "Presentation smoothing must settle onto the authoritative pose.")
    }

    func testAuthorityRebaseDoesNotApplyAControlTransitionBiasTwice() throws {
        let timeline = timeline()
        timeline.accept(state(tick: 0, x: 100), at: 0)
        let first = try XCTUnwrap(timeline.render(dt: 1 / 120, input: GameInput(forward: true), now: 1 / 120) { _ in }?.tanks.first)
        let released = try XCTUnwrap(timeline.render(dt: 0, input: GameInput(), now: 1 / 120) { _ in }?.tanks.first)
        XCTAssertEqual(released.x, first.x, accuracy: 1e-9)
        timeline.accept(state(tick: 1, x: 103), at: 1 / 120)
        let corrected = try XCTUnwrap(timeline.render(dt: 0, input: GameInput(), now: 1 / 120) { _ in }?.tanks.first)
        XCTAssertEqual(corrected.x, first.x, accuracy: 1e-9)
        let boundary = try XCTUnwrap(timeline.render(dt: 1 / 120, input: GameInput(), now: 1 / 60) { _ in }?.tanks.first)
        let expected = 100 + (first.x - 100) * exp(-(1 / 120) / 0.04)
        XCTAssertEqual(boundary.x, expected, accuracy: 1e-9, "A network delta must not reappear as a second input-transition correction at the next tick.")
    }

    func testFastTurningPredictionHasContinuousVelocityAcrossTheSixtyHzBoundary() throws {
        let world = ArenaWorld(width: 4000, height: 4000, cols: 48, rows: 48, walls: [])
        let timeline = RenderTimeline(localID: 1) { tank, input, dt in
            TankMovement.step(tank: &tank, input: input, dt: dt, walls: [], width: world.width, height: world.height)
        }
        let initial = state(tick: 0, x: 2000, world: world)
        timeline.accept(initial, at: 0)
        let input = GameInput(forward: true, right: true), epsilon = 0.000001
        var packets = 0
        let before = try XCTUnwrap(timeline.render(dt: 1 / 60 - epsilon, input: input, now: 1 / 60 - epsilon) { _ in packets += 1 }?.tanks.first)
        let boundary = try XCTUnwrap(timeline.render(dt: epsilon, input: input, now: 1 / 60) { _ in packets += 1 }?.tanks.first)
        let after = try XCTUnwrap(timeline.render(dt: epsilon, input: input, now: 1 / 60 + epsilon) { _ in packets += 1 }?.tanks.first)
        let velocityChange = hypot((after.x - boundary.x) / epsilon - (boundary.x - before.x) / epsilon,
                                   (after.y - boundary.y) / epsilon - (boundary.y - before.y) / epsilon)
        print("Local online Speed×5 turn tick-boundary velocity change: \(velocityChange)")
        XCTAssertLessThan(velocityChange, 1, "Fractional presentation must not reset turning velocity each simulation tick.")
        var expected = try XCTUnwrap(initial.tanks.first)
        TankMovement.step(tank: &expected, input: input, dt: 1 / 60, walls: [], width: world.width, height: world.height)
        XCTAssertEqual(boundary.x, expected.x, accuracy: 1e-9)
        XCTAssertEqual(boundary.y, expected.y, accuracy: 1e-9)
        XCTAssertEqual(boundary.angle, expected.angle, accuracy: 1e-9)
        XCTAssertEqual(packets, 1, "Presentation must not emit extra network input steps.")
    }

    func testRepeatedSmallSpeedCorrectionsCannotCreateLargeDisplaySteps() throws {
        let timeline = timeline()
        timeline.accept(state(tick: 0, x: 100), at: 0)
        var lastSequence: UInt64 = 0, positions: [Double] = []
        for frame in 1...240 {
            let now = Double(frame) / 120
            let tank = try XCTUnwrap(timeline.render(dt: 1 / 120, input: GameInput(forward: true), now: now) { lastSequence = $0.seq }?.tanks.first)
            if frame > 60 { positions.append(tank.x) }
            if frame % 4 == 0 {
                let error = frame % 8 == 0 ? 3.0 : -3.0
                timeline.accept(state(tick: UInt64(frame / 2), x: 100 + now * 544 + error, ack: lastSequence), at: now)
            }
        }
        let stepErrors = zip(positions, positions.dropFirst()).map { abs(($1 - $0) - 544 / 120) }
        let largest = try XCTUnwrap(stepErrors.max())
        print("Local online Speed×5 largest corrected display-step error: \(largest)")
        XCTAssertLessThan(largest, 0.7, "Small 30 Hz timing errors must not create multi-pixel camera jumps at 120 Hz.")
    }

    func testHeadingCorrectionsUseTheShortPathAcrossTheAngleWrap() throws {
        let timeline = timeline()
        var first = state(tick: 0, x: 100)
        first.tanks[0].angle = 179 * .pi / 180
        timeline.accept(first, at: 0)
        var second = state(tick: 1, x: 100)
        second.tanks[0].angle = -179 * .pi / 180
        timeline.accept(second, at: 1 / 60)
        var previous = try XCTUnwrap(timeline.render(dt: 0, input: GameInput(), now: 1 / 60) { _ in }?.tanks.first?.angle)
        XCTAssertEqual(previous, first.tanks[0].angle, accuracy: 1e-9)
        for frame in 1...120 {
            let angle = try XCTUnwrap(timeline.render(dt: 1 / 120, input: GameInput(), now: 1 / 60 + Double(frame) / 120) { _ in }?.tanks.first?.angle)
            let delta = atan2(sin(angle - previous), cos(angle - previous))
            XCTAssertLessThan(abs(delta), 0.01)
            previous = angle
        }
        XCTAssertEqual(previous, second.tanks[0].angle, accuracy: 0.001)
    }

    func testPauseAndResumeDiscardCorrectionsAccumulatedWithoutRendering() throws {
        for usePacket in [false, true] {
            let timeline = timeline()
            timeline.accept(state(tick: 0, x: 100), at: 0)
            timeline.accept(state(tick: 2, x: 103), at: 1 / 30)
            XCTAssertEqual(timeline.render(dt: 0, input: GameInput(), now: 1 / 30) { _ in }?.tanks.first?.x, 100)
            timeline.neutralize()
            for packet in 1...8 {
                timeline.accept(state(tick: UInt64(2 + packet * 2), x: 103 + Double(packet)), at: Double(packet + 1) / 30)
            }
            if usePacket { _ = timeline.neutralPacket() } else { timeline.neutralize() }
            let resumed = try XCTUnwrap(timeline.render(dt: 0, input: GameInput(), now: 0.3) { _ in }?.tanks.first)
            XCTAssertEqual(resumed.x, 111, accuracy: 1e-9, "Resume must not apply a stale offset retained by the pause menu.")
        }
    }

    func testPauseResumeRestartsTheRemotePlayheadAtItsNormalBufferDelay() throws {
        let timeline = timeline(localID: 99)
        timeline.accept(state(tick: 0, x: 100), at: 0)
        timeline.neutralize()
        for packet in 1...8 {
            timeline.accept(state(tick: UInt64(packet * 2), x: 100 + Double(packet) / 30 * 544), at: Double(packet) / 30)
        }
        _ = timeline.neutralPacket()
        let resumed = try XCTUnwrap(timeline.render(dt: 0, input: GameInput(), now: 8 / 30) { _ in }?.tanks.first)
        XCTAssertEqual(resumed.x, 100 + (8 / 30 - 0.085) * 544, accuracy: 1e-9)
    }

    func testSnapshotRecoveryDropsOldPredictionAndCorrectionAfterALongGap() throws {
        for renderStaleFrame in [false, true] {
            let timeline = timeline()
            timeline.accept(state(tick: 0, x: 100), at: 0)
            var lastSequence: UInt64 = 0
            _ = timeline.render(dt: 2 / 60, input: GameInput(forward: true), now: 2 / 60) { lastSequence = $0.seq }
            timeline.accept(state(tick: 2, x: 115, ack: lastSequence), at: 2 / 60)
            if renderStaleFrame {
                _ = timeline.render(dt: 0, input: GameInput(forward: true), now: 3) { _ in }
                XCTAssertTrue(timeline.stale)
            }
            timeline.accept(state(tick: 180, x: 120, ack: lastSequence), at: 3)
            let recovered = try XCTUnwrap(timeline.render(dt: 0, input: GameInput(), now: 3) { _ in }?.tanks.first)
            XCTAssertEqual(recovered.x, 120, accuracy: 1e-9)
            XCTAssertFalse(timeline.stale)
            var nextSequence: UInt64 = 0
            _ = timeline.render(dt: 1 / 60, input: GameInput(), now: 3 + 1 / 60) { nextSequence = $0.seq }
            XCTAssertEqual(nextSequence, lastSequence + 1)
        }
    }

    func testLargeCorrectionsAndNewLivesAreImmediate() throws {
        let timeline = timeline()
        timeline.accept(state(tick: 0, x: 100), at: 0)
        timeline.accept(state(tick: 1, x: 300), at: 1 / 60)
        XCTAssertEqual(timeline.render(dt: 0, input: GameInput(), now: 1 / 60) { _ in }?.tanks.first?.x, 300)
        timeline.accept(state(tick: 2, x: 310, ghost: 1), at: 2 / 60)
        XCTAssertEqual(timeline.render(dt: 0, input: GameInput(), now: 2 / 60) { _ in }?.tanks.first?.x, 310)
        timeline.accept(state(tick: 3, x: 320, spawn: 2), at: 3 / 60)
        XCTAssertEqual(timeline.render(dt: 0, input: GameInput(), now: 3 / 60) { _ in }?.tanks.first?.x, 320)
    }

    func testCorrectionSmoothingCannotCarryTheTankThroughAWall() throws {
        let wall = MazeWall(x: 480, y: 0, w: 8, h: 1000, axis: "v")
        let world = ArenaWorld(width: 1000, height: 1000, cols: 12, rows: 12, walls: [wall])
        let timeline = timeline()
        timeline.accept(state(tick: 0, x: 450, world: world), at: 0)
        timeline.accept(state(tick: 1, x: 510, world: world), at: 1 / 60)
        let rendered = try XCTUnwrap(timeline.render(dt: 0, input: GameInput(), now: 1 / 60) { _ in }?.tanks.first)
        XCTAssertEqual(rendered.x, 510, accuracy: 1e-9, "A correction across solid geometry must snap instead of smoothing through it.")
    }

    func testRemoteTrackPresentationUsesTheSameTimelineAsPosition() throws {
        let timeline = timeline(localID: 99)
        timeline.accept(state(tick: 0, x: 100), at: 0)
        timeline.accept(state(tick: 2, x: 110), at: 1 / 30)
        let rendered = try XCTUnwrap(timeline.render(dt: 0.1, input: GameInput(), now: 0.1) { _ in }?.tanks.first)
        XCTAssertGreaterThan(rendered.x, 100)
        XCTAssertLessThan(rendered.x, 110)
        XCTAssertEqual(rendered.track, rendered.x, accuracy: 1e-9)
    }

    func testSpeedStackedRemoteMotionDoesNotPulseAtSnapshotCadence() throws {
        for refresh in [60, 120, 144] {
            let timeline = timeline(localID: 99)
            timeline.accept(state(tick: 0, x: 100), at: 0)
            var packet = 0, positions: [Double] = []
            for frame in 1...(refresh * 3) {
                let now = Double(frame) / Double(refresh)
                while Double(packet + 1) / 30 <= now + 1e-9 {
                    packet += 1
                    timeline.accept(state(tick: UInt64(packet * 2), x: 100 + Double(packet) / 30 * 544), at: now)
                }
                let pose = try XCTUnwrap(timeline.render(dt: 1 / Double(refresh), input: GameInput(), now: now) { _ in }?.tanks.first)
                if frame > refresh { positions.append(pose.x) }
            }
            let speeds = zip(positions, positions.dropFirst()).map { ($1 - $0) * Double(refresh) }
            let largestChange = zip(speeds, speeds.dropFirst()).map { abs($1 - $0) }.max() ?? 0
            print("Remote Speed×5 \(refresh) Hz largest per-frame speed change: \(largestChange)")
            XCTAssertLessThan(largestChange, 4, "\(refresh) Hz motion must not switch playback speed abruptly at 30 Hz snapshot arrivals.")
        }
    }

    func testRemoteFastTurnsRemainSmoothAcrossThirtyHzSnapshotBoundaries() throws {
        let speed = 544.0, turn = 3.65 * 2.25, radius = speed / turn
        func point(_ time: Double) -> (x: Double, y: Double) {
            (1000 + sin(time * turn) * radius, 1000 + (1 - cos(time * turn)) * radius)
        }
        func sample(_ packet: Int) -> ArenaSnapshot {
            let time = Double(packet) / 30, position = point(time)
            var value = state(tick: UInt64(packet * 2), x: position.x)
            value.tanks[0].y = position.y; value.tanks[0].angle = time * turn
            return value
        }
        for refresh in [60, 120, 144] {
            let timeline = timeline(localID: 99)
            timeline.accept(sample(0), at: 0)
            var packet = 0, poses: [(x: Double, y: Double)] = [], linear: [(x: Double, y: Double)] = []
            for frame in 1...(refresh * 3) {
                let now = Double(frame) / Double(refresh)
                while Double(packet + 1) / 30 <= now + 1e-9 {
                    packet += 1; timeline.accept(sample(packet), at: now)
                }
                let pose = try XCTUnwrap(timeline.render(dt: 1 / Double(refresh), input: GameInput(), now: now) { _ in }?.tanks.first)
                if frame > refresh {
                    poses.append((pose.x, pose.y))
                    let stamp = pose.angle / turn * 30, first = floor(stamp), alpha = stamp - first
                    let a = point(first / 30), b = point((first + 1) / 30)
                    linear.append((a.x + (b.x - a.x) * alpha, a.y + (b.y - a.y) * alpha))
                }
            }
            func largestVelocityChange(_ values: [(x: Double, y: Double)]) -> Double {
                let velocities = zip(values, values.dropFirst()).map { ((($1.x - $0.x) * Double(refresh)), (($1.y - $0.y) * Double(refresh))) }
                return zip(velocities, velocities.dropFirst()).map { hypot($1.0 - $0.0, $1.1 - $0.1) }.max() ?? 0
            }
            let before = largestVelocityChange(linear), after = largestVelocityChange(poses)
            print("Remote Speed×5 turn \(refresh) Hz largest velocity change, linear/curved: \(before) / \(after)")
            XCTAssertLessThan(after, before * 0.65, "The buffered turn path must not kink at every snapshot boundary.")
        }
    }

    func testRemoteCurveFallsBackWhenItsArcWouldEnterASolidWall() throws {
        let world = ArenaWorld(width: 500, height: 500, cols: 6, rows: 6,
                               walls: [MazeWall(x: 60, y: 70, w: 120, h: 10, axis: "h")])
        let timeline = timeline(localID: 99)
        for (index, y) in [140.0, 100, 100, 140, 160].enumerated() {
            var value = state(tick: UInt64(index * 2), x: 80 + Double(index) * 20, world: world)
            value.tanks[0].y = y
            timeline.accept(value, at: Double(index) / 30)
        }
        timeline.neutralize()
        let tank = try XCTUnwrap(timeline.render(dt: 0, input: GameInput(), now: 4 / 30) { _ in }?.tanks.first)
        XCTAssertGreaterThan(tank.x, 100); XCTAssertLessThan(tank.x, 120)
        XCTAssertEqual(tank.y, 100, accuracy: 1e-9, "An unsafe curved path must retain the original clear straight segment.")
    }

    func testGhostRemoteCurveCannotDipOutsideTheFixedMapBoundary() throws {
        let world = ArenaWorld(width: 252, height: 252, cols: 3, rows: 3, walls: [])
        for includesWorld in [false, true] {
            let timeline = RenderTimeline(localID: 99, maze: InfiniteMaze(world: world)) { _, _, _ in }
            for (index, x) in [24.0, 21, 21, 21, 21].enumerated() {
                var value = state(tick: UInt64(index * 2), x: x, ghost: 15, world: includesWorld ? world : nil)
                value.tanks[0].y = 100 + Double(index) * 10
                timeline.accept(value, at: Double(index) / 30)
            }
            timeline.neutralize()
            let tank = try XCTUnwrap(timeline.render(dt: 0, input: GameInput(), now: 4 / 30) { _ in }?.tanks.first)
            XCTAssertEqual(tank.x, 21, accuracy: 1e-9)
            XCTAssertGreaterThan(tank.y, 110); XCTAssertLessThan(tank.y, 120)
        }
    }

    func testGhostAuthorityCorrectionCannotMoveAClampedTankOutsideTheMap() throws {
        let world = ArenaWorld(width: 252, height: 252, cols: 3, rows: 3, walls: [])
        let timeline = RenderTimeline(localID: 1, maze: InfiniteMaze(world: world)) { tank, input, dt in
            TankMovement.step(tank: &tank, input: input, dt: dt, walls: [], width: world.width, height: world.height)
        }
        var initial = state(tick: 0, x: 21, ghost: 15)
        initial.tanks[0].angle = .pi
        timeline.accept(initial, at: 0)
        _ = timeline.render(dt: 1 / 60, input: GameInput(forward: true), now: 1 / 60) { _ in }
        var authority = state(tick: 2, x: 24, ack: 1, ghost: 15)
        authority.tanks[0].angle = .pi
        timeline.accept(authority, at: 1 / 60)
        let tank = try XCTUnwrap(timeline.render(dt: 1 / 60, input: GameInput(forward: true), now: 2 / 60) { _ in }?.tanks.first)
        XCTAssertGreaterThanOrEqual(tank.x, 21, "A Ghost correction may cross internal walls but not the outer map boundary.")
    }

    func testGhostPresentationStillPhasesThroughInternalWalls() throws {
        let world = ArenaWorld(width: 252, height: 252, cols: 3, rows: 3,
                               walls: [MazeWall(x: 90, y: 0, w: 8, h: 252, axis: "v")])
        let timeline = RenderTimeline(localID: 1, maze: InfiniteMaze(world: world)) { tank, input, dt in
            TankMovement.step(tank: &tank, input: input, dt: dt, walls: world.walls, width: world.width, height: world.height)
        }
        timeline.accept(state(tick: 0, x: 80, ghost: 15), at: 0)
        let tank = try XCTUnwrap(timeline.render(dt: 1 / 120, input: GameInput(forward: true), now: 1 / 120) { _ in }?.tanks.first)
        XCTAssertGreaterThan(tank.x, 80)
        XCTAssertTrue(TankMovement.presentationFitsBounds(tank: tank, world: world))
    }
}
