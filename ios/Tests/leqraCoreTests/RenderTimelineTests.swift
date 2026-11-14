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
        // Isolate acknowledgement replay from the independent visual easing
        // caused by changing forward to reverse between display frames.
        timeline.neutralize()
        let replayed = timeline.render(dt: 0, input: GameInput(), now: 4 / 60) { _ in }
        XCTAssertEqual(try XCTUnwrap(replayed?.tanks.first?.x), 0, accuracy: 1e-9)
        // A later acknowledgement of the same held packet accounts for more
        // elapsed server steps instead of replaying an already consumed input.
        timeline.accept(snapshot(tick: 64, x: 4, ack: 1, ackSteps: 4), at: 5 / 60)
        let consumed = timeline.render(dt: 0, input: GameInput(), now: 5 / 60) { _ in }
        XCTAssertEqual(try XCTUnwrap(consumed?.tanks.first?.x), 0, accuracy: 1e-9)
        // Authority is adopted now, while the old visible pose eases onto it.
        // Settling must not replay the reverse controls already consumed above.
        var settled = consumed
        for frame in 1...120 {
            settled = timeline.render(dt: 1 / 120, input: GameInput(), now: 5 / 60 + Double(frame) / 120) { _ in }
        }
        XCTAssertEqual(try XCTUnwrap(settled?.tanks.first?.x), 4, accuracy: 0.001)
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

    func testProjectileDespawnUsesTheSameTimelineAsItsDelayedBirth() throws {
        let timeline = timeline(localID: 99)
        var first = snapshot(tick: 60)
        first.bullets = [ArenaBullet(id: 8, x: 10, owner: 1)]
        timeline.accept(first, at: 0)
        XCTAssertEqual(timeline.render(dt: 0, input: GameInput(), now: 0) { _ in }?.bullets.first?.x, 10)
        var second = snapshot(tick: 62)
        second.bullets = [ArenaBullet(id: 8, x: 20, owner: 1)]
        timeline.accept(second, at: 1 / 30)
        XCTAssertEqual(timeline.render(dt: 0, input: GameInput(), now: 1 / 30) { _ in }?.bullets.first?.x, 10)
        timeline.accept(snapshot(tick: 64), at: 2 / 30)
        XCTAssertEqual(timeline.render(dt: 0, input: GameInput(), now: 2 / 30) { _ in }?.bullets.first?.id, 8)
        var last: ArenaSnapshot?
        for frame in 1...24 {
            last = timeline.render(dt: 1 / 120, input: GameInput(), now: 2 / 30 + Double(frame) / 120) { _ in }
        }
        XCTAssertTrue(try XCTUnwrap(last).bullets.isEmpty)
    }

    func testShortLivedCannonIsVisibleEvenAfterTheNewestStateReportsTheKill() throws {
        for delay in [0.001, 0.05, 0.2, 0.4] {
            let timeline = timeline(localID: 99)
            timeline.accept(snapshot(tick: 60), at: delay)
            var fired = snapshot(tick: 62)
            fired.bullets = [ArenaBullet(id: 9, x: 100, y: 100, vx: 520, owner: 1, kind: "cannon", life: 5.3)]
            timeline.accept(fired, at: delay + 2 / 60)
            timeline.accept(snapshot(tick: 64, hp: 0), at: delay + 4 / 60)
            var seen = false, last: ArenaSnapshot?
            for frame in 0...30 {
                last = timeline.render(dt: 1 / 120, input: GameInput(), now: delay + 4 / 60 + Double(frame) / 120) { _ in }
                seen = seen || last?.bullets.contains(where: { $0.id == 9 && $0.kind == "cannon" }) == true
                XCTAssertEqual(last?.tanks.first?.hp, 0, "Presentation never rolls back authoritative damage")
            }
            XCTAssertTrue(seen, "Authoritative cannon must survive delayed playback at \(delay)s latency")
            XCTAssertTrue(try XCTUnwrap(last).bullets.isEmpty)
        }
    }

    func testTerminalFlightRecordsRenderBetweenSnapshotsAndResetWithTheirContext() throws {
        for kind in ["regular", "rapid", "scatter", "homing", "grenade", "cannon"] {
            let timeline = timeline(localID: 99)
            timeline.accept(snapshot(tick: 60), at: 0)
            let flight = CannonFlight(id: 9, owner: 1, colorIndex: 3, startTick: 61, endTick: 61.5,
                points: [CannonFlightPoint(x: 100, y: 100, tick: 61), CannonFlightPoint(x: 106, y: 100, tick: 61.5)], kind: kind)
            var killed = snapshot(tick: 62, hp: 0)
            killed.effects = [ArenaEffect(id: 1, kind: kind == "grenade" ? "blast" : "impact", flight: flight)]
            timeline.accept(killed, at: 1 / 30)
            var seen = false, impact = false
            for frame in 1...30 {
                let value = try XCTUnwrap(timeline.render(dt: 1 / 120, input: GameInput(), now: 1 / 30 + Double(frame) / 120) { _ in })
                seen = seen || value.bullets.contains { $0.id == 9 }
                impact = impact || value.effects.contains { $0.id == 1 }
                XCTAssertEqual(value.tanks.first?.hp, 0)
                XCTAssertTrue(value.bullets.allSatisfy { (100...106).contains($0.x) })
            }
            XCTAssertTrue(seen, kind); XCTAssertTrue(impact, kind)
            var reset = killed; reset.generation = 2; reset.tick = 0
            timeline.accept(reset, at: 1)
            XCTAssertTrue(try XCTUnwrap(timeline.render(dt: 1 / 120, input: GameInput(), now: 1) { _ in }).bullets.isEmpty)
        }
    }

    func testInfinityResultFreezesCombatWhileTerminalFlightFinishes() throws {
        let timeline = timeline()
        timeline.accept(snapshot(tick: 60, x: 42), at: 0)
        _ = timeline.render(dt: 1 / 30, input: GameInput(forward: true, fire: true), now: 1 / 30) { _ in }
        var won = snapshot(tick: 62, x: 43)
        won.result = ArenaResult(id: 1, name: "Winner", score: 1)
        won.effects = [ArenaEffect(id: 1, kind: "impact", flight: CannonFlight(id: 9, owner: 1, colorIndex: 0,
            startTick: 61, endTick: 61.5, points: [CannonFlightPoint(x: 80, y: 42, tick: 61), CannonFlightPoint(x: 86, y: 42, tick: 61.5)]))]
        timeline.accept(won, at: 1 / 30)
        var seen = false, last: ArenaSnapshot?
        for frame in 1...30 {
            last = timeline.render(dt: 1 / 120, input: GameInput(forward: true, fire: true), now: 1 / 30 + Double(frame) / 120) { packet in
                XCTAssertFalse(packet.forward || packet.fire)
            }
            XCTAssertEqual(last?.tanks.first?.x, 43)
            seen = seen || last?.bullets.contains { $0.id == 9 } == true
        }
        XCTAssertTrue(seen); XCTAssertTrue(try XCTUnwrap(last).bullets.isEmpty)
    }

    func testGenerationReusingSnapshotAndProjectileIDsStartsWithFreshIndices() {
        let timeline = timeline(localID: 99)
        for generation in 1...2 {
            var value = snapshot(tick: 60, generation: generation, x: Double(generation) * 100)
            value.bullets = [ArenaBullet(id: 8, x: Double(generation) * 300, owner: 1)]
            timeline.accept(value, at: Double(generation))
            let rendered = timeline.render(dt: 0, input: GameInput(), now: Double(generation)) { _ in }
            XCTAssertEqual(rendered?.tanks.first?.x, Double(generation) * 100)
            XCTAssertEqual(rendered?.bullets.first?.x, Double(generation) * 300)
        }
    }

    @MainActor func testNativeWireVersionMatchesTheGoServerRelease() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("src/main.go"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"\bversion\s*=\s*"([^"]+)""#)
        let match = try XCTUnwrap(regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
        let range = try XCTUnwrap(Range(match.range(at: 1), in: source))
        XCTAssertEqual(NetworkClient.supportedVersion, String(source[range]), "The generated native version must follow the Go server release.")
    }
}
