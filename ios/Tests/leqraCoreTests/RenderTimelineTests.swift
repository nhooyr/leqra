import Foundation
import XCTest
@testable import leqraCore

final class RenderTimelineTests: XCTestCase {
    private func timeline(localID: Int = 1) -> RenderTimeline {
        RenderTimeline(localID: localID) { tank, input, dt in
            if input.forward { tank.x += dt * 60 }
            if input.reverse { tank.x -= dt * 60 }
        }
    }

    private func snapshot(tick: UInt64 = 0, generation: Int = 1, x: Double = 0,
                          hp: Int = 1, spawn: Int = 1, ack: UInt64 = 0, ackSteps: UInt32 = 0) -> ArenaSnapshot {
        var value = ArenaSnapshot(tick: tick, tanks: [ArenaTank(id: 1, name: "SNOW", x: x, hp: hp, ack: ack,
                                                               ackSteps: ackSteps, spawnSerial: spawn)])
        value.generation = generation
        return value
    }

    func testDisplayRatesProduceTheSameSixtyHzInputAndMovement() throws {
        for refreshRate in [60, 90, 120] {
            let timeline = timeline()
            timeline.accept(snapshot(), at: 0)
            var packets: [GameInput] = [], last: ArenaSnapshot?
            for frame in 1...refreshRate {
                last = timeline.render(dt: 1 / Double(refreshRate), input: GameInput(forward: true),
                                       now: Double(frame) / Double(refreshRate)) { packets.append($0) }
            }
            XCTAssertEqual(packets.count, 60, "\(refreshRate) Hz display")
            XCTAssertEqual(packets.map(\.seq), Array(1...60).map(UInt64.init))
            XCTAssertEqual(try XCTUnwrap(last?.tanks.first?.x), 60, accuracy: 1e-9)
        }
    }

    func testOneHundredTwentyHzSubframeMovesWithoutSendingAnExtraPacket() throws {
        let timeline = timeline()
        timeline.accept(snapshot(), at: 0)
        var packets: [GameInput] = []
        let halfway = timeline.render(dt: 1 / 120, input: GameInput(forward: true), now: 1 / 120) { packets.append($0) }
        XCTAssertEqual(try XCTUnwrap(halfway?.tanks.first?.x), 0.5, accuracy: 1e-9)
        XCTAssertTrue(packets.isEmpty)
        let full = timeline.render(dt: 1 / 120, input: GameInput(forward: true), now: 1 / 60) { packets.append($0) }
        XCTAssertEqual(try XCTUnwrap(full?.tanks.first?.x), 1, accuracy: 1e-9)
        XCTAssertEqual(packets.count, 1)
    }

    func testLongDisplayStallBoundsCatchUpWork() {
        let timeline = timeline()
        timeline.accept(snapshot(), at: 0)
        var packets: [GameInput] = []
        _ = timeline.render(dt: 5, input: GameInput(forward: true), now: 1) { packets.append($0) }
        XCTAssertEqual(packets.count, 6)
    }

    func testHeldInputAcknowledgementStepsReplayOnlyUnconsumedMovement() throws {
        let timeline = timeline()
        timeline.accept(snapshot(tick: 60), at: 0)
        _ = timeline.render(dt: 2 / 60, input: GameInput(forward: true), now: 2 / 60) { _ in }
        _ = timeline.render(dt: 2 / 60, input: GameInput(reverse: true), now: 4 / 60) { _ in }
        // One packet remained held for two server ticks. Both consumed local
        // steps must be removed before replaying the newer reverse controls.
        timeline.accept(snapshot(tick: 62, x: 2, ack: 1, ackSteps: 2), at: 4 / 60)
        let replayed = timeline.render(dt: 0, input: GameInput(), now: 4 / 60) { _ in }
        XCTAssertEqual(try XCTUnwrap(replayed?.tanks.first?.x), 0, accuracy: 1e-9)
        // A later acknowledgement of the same held packet accounts for more
        // elapsed server steps instead of replaying an already consumed input.
        timeline.accept(snapshot(tick: 64, x: 4, ack: 1, ackSteps: 4), at: 5 / 60)
        let consumed = timeline.render(dt: 0, input: GameInput(), now: 5 / 60) { _ in }
        XCTAssertEqual(try XCTUnwrap(consumed?.tanks.first?.x), 4, accuracy: 1e-9)
    }

    func testDeathAndRespawnDiscardThePreviousLifePrediction() throws {
        let timeline = timeline()
        timeline.accept(snapshot(), at: 0)
        _ = timeline.render(dt: 2 / 60, input: GameInput(forward: true), now: 2 / 60) { _ in }
        timeline.accept(snapshot(tick: 2, x: 500, hp: 0), at: 3 / 60)
        let dead = timeline.render(dt: 1 / 60, input: GameInput(forward: true), now: 4 / 60) { _ in }
        XCTAssertEqual(dead?.tanks.first?.hp, 0)
        XCTAssertEqual(dead?.tanks.first?.x, 500)
        timeline.accept(snapshot(tick: 3, x: 800, spawn: 2), at: 5 / 60)
        let respawned = timeline.render(dt: 0, input: GameInput(), now: 5 / 60) { _ in }
        XCTAssertEqual(respawned?.tanks.first?.spawnSerial, 2)
        XCTAssertEqual(respawned?.tanks.first?.x, 800)
    }

    func testGenerationResetDiscardsHistoryAndKeepsSequencesIncreasing() throws {
        let timeline = timeline()
        timeline.accept(snapshot(tick: 100, generation: 1), at: 0)
        var packets: [GameInput] = []
        _ = timeline.render(dt: 2 / 60, input: GameInput(forward: true), now: 2 / 60) { packets.append($0) }
        timeline.accept(snapshot(tick: 1, generation: 2, x: 90, hp: 0), at: 3 / 60)
        let next = timeline.render(dt: 1 / 60, input: GameInput(forward: true), now: 4 / 60) { packets.append($0) }
        XCTAssertEqual(next?.generation, 2)
        XCTAssertEqual(next?.tanks.first?.hp, 0)
        XCTAssertEqual(next?.tanks.first?.x, 90)
        XCTAssertEqual(packets.map(\.seq), [1, 2, 3])
    }

    func testOldSnapshotCannotResurrectADeadTank() {
        let timeline = timeline()
        timeline.accept(snapshot(tick: 10, x: 100, hp: 0), at: 0)
        timeline.accept(snapshot(tick: 9, x: 80), at: 0.01)
        let result = timeline.render(dt: 0, input: GameInput(), now: 0.01) { _ in }
        XCTAssertEqual(result?.tick, 10)
        XCTAssertEqual(result?.tanks.first?.hp, 0)
        XCTAssertEqual(result?.tanks.first?.x, 100)
        timeline.accept(snapshot(tick: 200, generation: 0, x: 80), at: 0.02)
        let olderGeneration = timeline.render(dt: 0, input: GameInput(), now: 0.02) { _ in }
        XCTAssertEqual(olderGeneration?.generation, 1)
        XCTAssertEqual(olderGeneration?.tanks.first?.hp, 0)
    }

    func testRemoteDeathAndNewLifeNeverInterpolateBackIntoOldLife() throws {
        let timeline = timeline(localID: 99)
        timeline.accept(snapshot(tick: 0, x: 0), at: 0)
        timeline.accept(snapshot(tick: 2, x: 10, hp: 0), at: 2 / 60)
        let dead = timeline.render(dt: 1 / 120, input: GameInput(), now: 3 / 60) { _ in }
        XCTAssertEqual(dead?.tanks.first?.hp, 0)
        XCTAssertEqual(dead?.tanks.first?.x, 10)
        timeline.accept(snapshot(tick: 4, x: 100, spawn: 2), at: 4 / 60)
        let fresh = timeline.render(dt: 1 / 120, input: GameInput(), now: 5 / 60) { _ in }
        XCTAssertEqual(fresh?.tanks.first?.spawnSerial, 2)
        XCTAssertEqual(fresh?.tanks.first?.x, 100)
    }

    func testStaleConnectionFreezesPredictionAndSendsNeutralControls() throws {
        let timeline = timeline()
        timeline.accept(snapshot(), at: 0)
        let held = GameInput(forward: true, fire: true, stickX: 1, stickY: -0.5)
        _ = timeline.render(dt: 1 / 60, input: held, now: 1 / 60) { _ in }
        var packets: [GameInput] = []
        let frozen = timeline.render(dt: 1 / 60, input: held, now: 3) { packets.append($0) }
        XCTAssertTrue(timeline.stale)
        XCTAssertEqual(try XCTUnwrap(frozen?.tanks.first?.x), 1, accuracy: 1e-9)
        let later = timeline.render(dt: 1 / 60, input: held, now: 4) { packets.append($0) }
        XCTAssertEqual(try XCTUnwrap(later?.tanks.first?.x), 1, accuracy: 1e-9)
        XCTAssertEqual(packets.count, 2)
        for packet in packets {
            XCTAssertFalse(packet.forward || packet.reverse || packet.left || packet.right || packet.fire)
            XCTAssertEqual(packet.stickX, 0)
            XCTAssertEqual(packet.stickY, 0)
        }
        timeline.accept(snapshot(tick: 4, x: 5, ack: packets.last!.seq, ackSteps: 1), at: 4)
        XCTAssertFalse(timeline.stale)
    }

    func testPauseNeutralPacketsKeepTheSocketSequenceMonotonic() {
        let timeline = timeline()
        timeline.accept(snapshot(), at: 0)
        var packets: [GameInput] = []
        _ = timeline.render(dt: 1 / 60, input: GameInput(fire: true), now: 1 / 60) { packets.append($0) }
        packets.append(timeline.neutralPacket())
        _ = timeline.render(dt: 1 / 120, input: GameInput(fire: true), now: 2 / 60) { packets.append($0) }
        packets.append(timeline.neutralPacket())
        _ = timeline.render(dt: 1 / 60, input: GameInput(fire: true), now: 3 / 60) { packets.append($0) }
        timeline.accept(snapshot(tick: 2, hp: 0), at: 4 / 60)
        _ = timeline.render(dt: 1 / 60, input: GameInput(), now: 5 / 60) { packets.append($0) }
        XCTAssertEqual(packets.map(\.seq), [1, 2, 3, 4, 5])
        XCTAssertFalse(packets[1].fire)
        XCTAssertFalse(packets[2].fire)
    }

    @MainActor func testNativeWireVersionMatchesTheGoServerRelease() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("src/main.go"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"\bversion\s*=\s*"([^"]+)""#)
        let match = try XCTUnwrap(regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
        let range = try XCTUnwrap(Range(match.range(at: 1), in: source))
        XCTAssertEqual(NetworkClient.supportedVersion, String(source[range]), "Update the native wire version with each compatible server release.")
    }
}
