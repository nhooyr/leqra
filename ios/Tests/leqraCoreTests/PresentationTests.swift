import XCTest
@testable import leqraCore

final class PresentationTests: XCTestCase {
    func testWinningSideIncludesWinningTeammate() {
        let snapshot = ArenaSnapshot(tanks: [ArenaTank(id: 1, team: 2), ArenaTank(id: 3, team: 2)], winner: 3)
        XCTAssertEqual(snapshot.isWinningSide(localID: 1), true)
        XCTAssertEqual(snapshot.isWinningSide(localID: 3), true)
    }

    func testWinningSideRejectsEnemyTeam() {
        let snapshot = ArenaSnapshot(tanks: [ArenaTank(id: 1, team: 1), ArenaTank(id: 3, team: 2)], winner: 3)
        XCTAssertEqual(snapshot.isWinningSide(localID: 1), false)
    }

    func testWinningSideDoesNotGroupFreeForAllPilots() {
        let snapshot = ArenaSnapshot(tanks: [ArenaTank(id: 1), ArenaTank(id: 3)], winner: 3)
        XCTAssertEqual(snapshot.isWinningSide(localID: 1), false)
        XCTAssertEqual(snapshot.isWinningSide(localID: 3), true)
    }

    func testWinningSideIsUnknownForDrawAndMissingWinner() {
        XCTAssertNil(ArenaSnapshot(tanks: [ArenaTank(id: 1)]).isWinningSide(localID: 1))
        XCTAssertNil(ArenaSnapshot(tanks: [ArenaTank(id: 1)], winner: 3).isWinningSide(localID: 1))
    }

    func testWinningSideIsUnknownForSpectator() {
        let snapshot = ArenaSnapshot(tanks: [ArenaTank(id: 3, team: 2)], winner: 3)
        XCTAssertNil(snapshot.isWinningSide(localID: 1))
    }

    func testRemoteGhostExpiryDoesNotBlendBackInsideWall() throws {
        let timeline = RenderTimeline(localID: 99) { _, _, _ in }
        let before = ArenaTank(id: 1, x: 84, y: 42, ghostTime: 0.02)
        let after = ArenaTank(id: 1, x: 62.99, y: 42)
        timeline.accept(ArenaSnapshot(tick: 0, tanks: [before]), at: 0)
        timeline.accept(ArenaSnapshot(tick: 2, tanks: [after]), at: 2 / 60)
        let image = try XCTUnwrap(timeline.render(dt: 1 / 120, input: GameInput(), now: 3 / 60) { _ in })
        XCTAssertEqual(image.tanks[0].x, 62.99)
        XCTAssertEqual(image.tanks[0].ghostTime, 0)
    }

    func testAcknowledgementHistoryRemainsBoundedWhenSnapshotsStop() {
        let timeline = RenderTimeline(localID: 1) { _, _, _ in }
        timeline.accept(ArenaSnapshot(tanks: [ArenaTank(id: 1)]), at: 0)
        for frame in 0..<1200 {
            _ = timeline.render(dt: 1 / 60, input: GameInput(forward: true), now: Double(frame) / 60) { _ in }
        }
        XCTAssertTrue(timeline.stale)
        XCTAssertLessThanOrEqual(timeline.bufferedAcknowledgementCount, 240)
        for _ in 0..<1000 { _ = timeline.neutralPacket() }
        XCTAssertLessThanOrEqual(timeline.bufferedAcknowledgementCount, 240)
    }

    func testPracticeSubframeMovesTanksAndProjectilesWithoutAdvancingSimulation() throws {
        let arena = PracticeArena(seed: 42, name: "SNOW FOX", colorIndex: 0)
        var tank = ArenaTank(id: 1, name: "SNOW FOX", x: 42, y: 42)
        PracticeArena.applyPower(tank: &tank, kind: "cannon")
        arena.snapshot.tanks = [tank]
        arena.step(input: GameInput(fire: true), dt: 1 / 60)
        let authoritative = arena.snapshot
        let image = arena.presentationSnapshot(fraction: 0.5, localInput: GameInput(forward: true))
        XCTAssertEqual(image.tanks[0].x - authoritative.tanks[0].x, 128 / 120, accuracy: 1e-10)
        XCTAssertEqual(try XCTUnwrap(image.bullets.first).x - XCTUnwrap(authoritative.bullets.first).x, 1128 / 120, accuracy: 1e-10)
        XCTAssertEqual(arena.snapshot, authoritative)
    }

    func testPracticePresentationDoesNotConsumeRandomnessOrAwardHits() {
        let first = PracticeArena(seed: 42, name: "SNOW FOX", colorIndex: 0)
        let second = PracticeArena(seed: 42, name: "SNOW FOX", colorIndex: 0)
        for tick in 0..<600 {
            let input = GameInput(forward: tick % 180 < 90, right: tick % 120 > 60, fire: tick % 10 < 5)
            _ = first.presentationSnapshot(fraction: 0.5, localInput: input)
            _ = first.presentationSnapshot(fraction: 1, localInput: input)
            first.step(input: input, dt: 1 / 60)
            second.step(input: input, dt: 1 / 60)
        }
        XCTAssertEqual(first.snapshot, second.snapshot)
    }

    func testNewOnlineBulletEntersDelayedTimelineWithoutJumpingBackwards() {
        let timeline = RenderTimeline(localID: 99) { _, _, _ in }
        timeline.accept(ArenaSnapshot(tick: 0), at: 0)
        var positions: [Double] = []
        for frame in 1...48 {
            let now = Double(frame) / 120
            if frame.isMultiple(of: 4) {
                let tick = UInt64(frame / 2)
                let bullet = ArenaBullet(id: 1, x: Double(tick) * 10, y: 42, vx: 600, owner: 2, kind: "cannon", life: 5)
                timeline.accept(ArenaSnapshot(tick: tick, bullets: [bullet]), at: now)
            }
            let image = timeline.render(dt: 1 / 120, input: GameInput(), now: now) { _ in }
            if let bullet = image?.bullets.first { positions.append(bullet.x) }
        }
        XCTAssertFalse(positions.isEmpty)
        for pair in zip(positions, positions.dropFirst()) { XCTAssertGreaterThanOrEqual(pair.1, pair.0) }
        XCTAssertGreaterThan(Set(positions).count, 20)
    }

    func testRemovedOnlineBulletsNeverReappearFromDelayedSamples() {
        let timeline = RenderTimeline(localID: 99) { _, _, _ in }
        let bullet = ArenaBullet(id: 1, x: 42, y: 42, vx: 282, life: 5)
        timeline.accept(ArenaSnapshot(tick: 0, bullets: [bullet]), at: 0)
        timeline.accept(ArenaSnapshot(tick: 2), at: 2 / 60)
        let image = timeline.render(dt: 1 / 120, input: GameInput(), now: 3 / 60) { _ in }
        XCTAssertTrue(image?.bullets.isEmpty == true)
    }

    func testOnlineRicochetDoesNotBlendThroughWallCorner() throws {
        let timeline = RenderTimeline(localID: 99) { _, _, _ in }
        let before = ArenaBullet(id: 1, x: 75, y: 42, vx: 282, life: 5)
        let after = ArenaBullet(id: 1, x: 73, y: 48, vx: -282, life: 5, bounces: 1)
        timeline.accept(ArenaSnapshot(tick: 0, bullets: [before]), at: 0)
        timeline.accept(ArenaSnapshot(tick: 2, bullets: [after]), at: 2 / 60)
        let image = try XCTUnwrap(timeline.render(dt: 0.1, input: GameInput(), now: 0.1) { _ in })
        XCTAssertEqual(image.bullets[0].x, before.x)
        XCTAssertEqual(image.bullets[0].y, before.y)
        XCTAssertEqual(image.bullets[0].vx, before.vx)
    }

    func testRemoteTankCornerInterpolationHoldsClearPoseAndAllowsGhost() throws {
        let wall = MazeWall(x: 80, y: 80, w: 8, h: 84, axis: "v", line: 84)
        let world = ArenaWorld(width: 252, height: 252, cols: 3, rows: 3, walls: [wall])
        for ghost in [0.0, 5.0] {
            let timeline = RenderTimeline(localID: 99) { _, _, _ in }
            let before = ArenaTank(id: 1, x: 62, y: 98, ghostTime: ghost)
            let after = ArenaTank(id: 1, x: 98, y: 62, ghostTime: ghost)
            timeline.accept(ArenaSnapshot(tick: 0, tanks: [before], world: world), at: 0)
            timeline.accept(ArenaSnapshot(tick: 2, tanks: [after], world: world), at: 2 / 60)
            let image = try XCTUnwrap(timeline.render(dt: 0.1, input: GameInput(), now: 0.1) { _ in })
            if ghost == 0 {
                XCTAssertEqual(image.tanks[0].x, before.x)
                XCTAssertEqual(image.tanks[0].y, before.y)
            } else {
                XCTAssertGreaterThan(image.tanks[0].x, before.x)
                XCTAssertLessThan(image.tanks[0].y, before.y)
            }
        }
    }

    func testInfinityTimelineUsesSeededMazeToRejectWallCrossingBlend() throws {
        let maze = InfiniteMaze(seed: 42)
        let wall = try XCTUnwrap(maze.walls(x0: 0, y0: 0, x1: 100, y1: 100).first { $0.axis == "h" })
        let x = wall.x + wall.w / 2
        let before = ArenaTank(id: 1, x: x, y: wall.y - 18)
        let after = ArenaTank(id: 1, x: x, y: wall.y + wall.h + 18)
        XCTAssertFalse(maze.blocked(x: before.x, y: before.y, radius: 17))
        XCTAssertFalse(maze.blocked(x: after.x, y: after.y, radius: 17))
        let timeline = RenderTimeline(localID: 99, maze: maze) { _, _, _ in }
        timeline.accept(ArenaSnapshot(tick: 0, tanks: [before]), at: 0)
        timeline.accept(ArenaSnapshot(tick: 2, tanks: [after]), at: 2 / 60)
        let image = try XCTUnwrap(timeline.render(dt: 0.1, input: GameInput(), now: 0.1) { _ in })
        XCTAssertEqual(image.tanks[0].y, before.y)
        XCTAssertFalse(maze.blocked(x: image.tanks[0].x, y: image.tanks[0].y, radius: 17))
    }
}
