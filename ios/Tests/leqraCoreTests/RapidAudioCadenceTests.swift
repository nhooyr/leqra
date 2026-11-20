import XCTest

@testable import leqraCore

final class RapidAudioCadenceTests: XCTestCase {
    private func state(_ effects: [ArenaEffect] = [], star: Bool = true) -> ArenaSnapshot {
        var state = ArenaSnapshot(
            tanks: [ArenaTank(id: 1, starmanTime: star ? 8 : 0, power: "rapid")], effects: effects)
        state.phase = "playing"
        state.generation = 1
        return state
    }

    func testSparseAndDenseSourcesRetainTheirAverageCadenceUnderFourMillisecondJitter() {
        for online in [false, true] {
            for infinity in [false, true] {
                for sparse in [false, true] {
                    for jitter in [false, true] {
                        var router = AudioEventRouter()
                        var effects: [ArenaEffect] = []
                        var times: [Double] = []
                        var nextID = 0
                        _ = router.consume(
                            snapshot: state(), localID: 1, infinity: infinity, online: online, now: 0)
                        for frame in 1...480 {
                            let offset =
                                jitter ? (frame % 16 == 2 ? 0.004 : frame % 16 == 10 ? -0.004 : 0) : 0
                            let now = Double(frame) / 120 + offset
                            let spacing = sparse ? 8 : 2
                            if frame % spacing == 2 % spacing {
                                nextID += 1
                                effects.append(ArenaEffect(id: nextID, kind: "shot:rapid", owner: 1))
                                if effects.count > 16 { effects.removeFirst() }
                            }
                            let cues = router.consume(
                                snapshot: state(effects), localID: 1, infinity: infinity, online: online,
                                now: now)
                            XCTAssertLessThanOrEqual(
                                cues.filter { $0.cue == .rapid }.count, 1,
                                "A snapshot batch cannot produce a rapid-sound burst")
                            if cues.contains(where: { $0.cue == .rapid }) { times.append(now) }
                        }
                        if sparse {
                            XCTAssertEqual(times.count, 60)
                        } else {
                            XCTAssertTrue((60...63).contains(times.count))
                        }
                        let gaps = zip(times, times.dropFirst()).map { $1 - $0 }
                        XCTAssertLessThanOrEqual(gaps.max() ?? 1, 0.09)
                        XCTAssertGreaterThanOrEqual(gaps.min() ?? 0, 0.065 - 1 / 60 - 1e-9)
                    }
                }
            }
        }
    }

    func testDuplicatePacketsFreshPressRecoilAndClockResetDoNotDoublePlayShots() {
        var router = AudioEventRouter()
        var feedback = LocalFireFeedback()
        let tank = state().tanks[0]
        _ = router.consume(snapshot: state(), localID: 1, infinity: true, online: true, now: 0)
        XCTAssertTrue(feedback.setFire(true, tank: tank, generation: 1, now: 1))
        XCTAssertFalse(
            LocalFireFeedback.ammoUnavailable(for: tank),
            "A loaded/boosted press only predicts recoil; it cannot add a dry or shot cue")
        let packet = state([
            ArenaEffect(id: 1, kind: "shot:rapid", owner: 1),
            ArenaEffect(id: 2, kind: "shot:rapid", owner: 1),
        ])
        XCTAssertEqual(
            router.consume(snapshot: packet, localID: 1, infinity: true, online: true, now: 1).map(\.cue),
            [.rapid])
        XCTAssertEqual(
            router.consume(snapshot: packet, localID: 1, infinity: true, online: true, now: 1.1), [])
        XCTAssertEqual(
            router.consume(
                snapshot: state([ArenaEffect(id: 3, kind: "shot:rapid", owner: 1)]), localID: 1,
                infinity: true, online: true, now: 0.5
            ).map(\.cue), [.rapid])
        XCTAssertEqual(
            router.consume(
                snapshot: state([ArenaEffect(id: 4, kind: "shot:rapid", owner: 1)]), localID: 1,
                infinity: true, online: true, now: 0.5), [])
    }

    func testAuthoritativeSourceTicksSurviveUnevenWireAndDisplayCadences() {
        for renderRate in [60, 90, 120, 144, 165] {
            for wireRate in [20, 30, 60] {
                for jitter in [false, true] {
                    var router = AudioEventRouter()
                    var delivered: [ArenaEffect] = []
                    var times: [Double] = []
                    var nextPacket = 1
                    _ = router.consume(snapshot: state(), localID: 1, infinity: true, online: true, now: 0)
                    for frame in 1...(renderRate * 4 + 8) {
                        let now = Double(frame) / Double(renderRate)
                        while nextPacket <= wireRate * 4 {
                            let offset = jitter ? (nextPacket.isMultiple(of: 2) ? 0.004 : -0.004) : 0
                            guard Double(nextPacket) / Double(wireRate) + offset <= now + 1e-12 else { break }
                            let tick = nextPacket * (60 / wireRate)
                            delivered = stride(from: 1, through: tick, by: 4).filter { $0 > tick - 12 }.map {
                                ArenaEffect(id: $0, kind: "shot:rapid", owner: 1, tick: $0)
                            }
                            nextPacket += 1
                        }
                        let cues = router.consume(
                            snapshot: state(delivered), localID: 1, infinity: true, online: true, now: now)
                        XCTAssertLessThanOrEqual(cues.filter { $0.cue == .rapid }.count, 1)
                        if cues.contains(where: { $0.cue == .rapid }) { times.append(now) }
                    }
                    let context = "render=\(renderRate), wire=\(wireRate), jitter=\(jitter)"
                    XCTAssertEqual(times.count, 60, context)
                    XCTAssertGreaterThanOrEqual(
                        zip(times, times.dropFirst()).map { $1 - $0 }.min() ?? 0, 0.0325 - 1e-9, context)
                }
            }
        }
    }

    func testSourceHighWaterSurvivesClockResetAndFreshGenerationCanStartAtZero() {
        var router = AudioEventRouter()
        _ = router.consume(snapshot: state(), localID: 1, infinity: true, online: true, now: 0)
        func shot(_ id: Int, _ tick: Int, _ now: Double) -> [AudioCueRequest] {
            router.consume(
                snapshot: state([ArenaEffect(id: id, kind: "shot:rapid", owner: 1, tick: tick)]), localID: 1,
                infinity: true, online: true, now: now)
        }
        XCTAssertEqual(shot(1, 100, 1).map(\.cue), [.rapid])
        XCTAssertEqual(shot(2, 96, 1.2), [])
        XCTAssertEqual(
            shot(3, 104, 0.1).map(\.cue), [.rapid],
            "Clock reset clears arrival state while keeping source chronology")
        XCTAssertEqual(shot(4, 0, 0.11), [])
        XCTAssertEqual(shot(5, 108, 0.116), [], "A catch-up event cannot make a16ms audio burst")
        XCTAssertEqual(shot(6, 112, 0.134).map(\.cue), [.rapid])
        var fresh = state()
        fresh.generation = 2
        _ = router.consume(snapshot: fresh, localID: 1, infinity: true, online: true, now: 0.3)
        fresh.effects = [ArenaEffect(id: 1, kind: "shot:rapid", owner: 1, tick: 0)]
        XCTAssertEqual(
            router.consume(snapshot: fresh, localID: 1, infinity: true, online: true, now: 0.31).map(\.cue),
            [.rapid])
    }
}
