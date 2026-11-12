import XCTest
@testable import leqraCore

final class NetworkCadenceTests: XCTestCase {
    func testPreviewDelayIncludesRequestTimeAndNeverOverlapsSlowRequests() {
        XCTAssertEqual(NetworkRefreshCadence.interval, 1)
        XCTAssertEqual(NetworkRefreshCadence.remainingNanoseconds(startedAt: 100, now: 100), 1_000_000_000)
        XCTAssertEqual(NetworkRefreshCadence.remainingNanoseconds(startedAt: 100, now: 100.25), 750_000_000)
        XCTAssertEqual(NetworkRefreshCadence.remainingNanoseconds(startedAt: 100, now: 101), 0)
        XCTAssertEqual(NetworkRefreshCadence.remainingNanoseconds(startedAt: 100, now: 106), 0)
    }

    func testConnectedRoomAndInfinityProbeImmediatelyThenEachSecond() {
        var sampler = NetworkLatencySampler()
        XCTAssertEqual(sampler.nextPing(at: 100), 100)
        XCTAssertNil(sampler.nextPing(at: 1099))
        XCTAssertEqual(sampler.nextPing(at: 1100), 1100)
        XCTAssertNil(sampler.nextPing(at: 1100))
        XCTAssertEqual(sampler.nextPing(at: 2100), 2100)
        XCTAssertEqual(sampler.roundTrip(echo: 2100, now: 2137), 37)
    }

    func testSlowRepliesSurviveLaterProbesButDuplicateUnknownAndExpiredRepliesDoNot() {
        var sampler = NetworkLatencySampler()
        XCTAssertEqual(sampler.nextPing(at: 100), 100)
        XCTAssertEqual(sampler.nextPing(at: 1100), 1100)
        XCTAssertEqual(sampler.roundTrip(echo: 100, now: 1800), 1700)
        XCTAssertNil(sampler.roundTrip(echo: 100, now: 1900))
        XCTAssertNil(sampler.roundTrip(echo: 42, now: 1900))
        XCTAssertNil(sampler.roundTrip(echo: 1100, now: 7101))
        for index in 8...30 { _ = sampler.nextPing(at: Double(index * 1000)) }
        XCTAssertNil(sampler.roundTrip(echo: 8000, now: 30_001))
        XCTAssertEqual(sampler.roundTrip(echo: 30_000, now: 30_047), 47)
        sampler = NetworkLatencySampler()
        XCTAssertNil(sampler.roundTrip(echo: 30_000, now: 30_048), "retired connections cannot supply RTT")
    }
}
