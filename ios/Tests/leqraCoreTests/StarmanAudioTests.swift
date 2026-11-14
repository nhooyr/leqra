import Foundation
import XCTest
@testable import leqraCore

final class StarmanAudioTests: XCTestCase {
    func testPCMMatchesTheActualSharedWebFixtureAtAllOutputRates() throws {
        struct Fixture: Decodable {
            struct Profile: Decodable {
                struct Sample: Decodable { let index: Int; let value: Double }
                let rate: Double; let frames: Int; let peak: Double; let rms: Double; let samples: [Sample]
            }
            let profiles: [Profile]
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("src/tests/starman-audio-fixtures.json")))
        for profile in fixture.profiles {
            let pcm = StarmanAudio.samples(sampleRate: profile.rate)
            XCTAssertEqual(pcm.count, profile.frames)
            XCTAssertEqual(pcm.first, 0); XCTAssertEqual(pcm.last, 0)
            var energy = 0.0, peak = 0.0
            for sample in pcm { energy += Double(sample) * Double(sample); peak = max(peak, abs(Double(sample))) }
            XCTAssertEqual(peak, profile.peak, accuracy: 1e-8)
            XCTAssertEqual(sqrt(energy / Double(pcm.count)), profile.rms, accuracy: 1e-8)
            for sample in profile.samples { XCTAssertEqual(Double(pcm[sample.index]), sample.value, accuracy: 1e-8) }
            XCTAssertTrue(pcm.suffix(Int(profile.rate * 0.019)).allSatisfy { $0 == 0 }, "The loop seam must remain silent")
        }
        XCTAssertTrue(StarmanAudio.samples(sampleRate: 0).isEmpty)
        XCTAssertTrue(StarmanAudio.samples(sampleRate: .nan).isEmpty)
    }

    func testTwelveMillisecondFadesDoNotRestartWhenTheSameStateIsRefreshed() {
        var voice = AudioLoopVoice(samples: [Float](repeating: 1, count: 4800))
        voice.setActive(true)
        XCTAssertEqual(voice.nextSample(), 0)
        for frame in 1..<576 {
            if frame.isMultiple(of: 64) { voice.setActive(true) }
            XCTAssertEqual(voice.nextSample(), Float(frame) / 576, accuracy: 0.00001)
        }
        XCTAssertEqual(voice.nextSample(), 1)
        voice.setActive(false)
        for frame in 0..<576 {
            if frame.isMultiple(of: 64) { voice.setActive(false) }
            XCTAssertEqual(voice.nextSample(), 1 - Float(frame) / 576, accuracy: 0.00001)
        }
        XCTAssertFalse(voice.sounding); XCTAssertEqual(voice.position, 0); XCTAssertEqual(voice.nextSample(), 0)
    }

    func testBothLocalPilotsUseOneContinuousVoiceAndRemotePowerDoesNotStartIt() {
        var state = ArenaSnapshot(tanks: [ArenaTank(id: 1, starmanTime: 4), ArenaTank(id: 2, starmanTime: 2),
                                         ArenaTank(id: 3, bot: true, starmanTime: 8)])
        var voice = AudioLoopVoice(samples: [Float](repeating: 0.001, count: 192_000))
        for frame in 0..<2400 {
            if frame == 1200 { state.tanks[0].hp = 0 }
            voice.setActive(StarmanAudio.isActive(snapshot: state, primaryID: 1, secondaryID: 2))
            _ = voice.nextSample()
        }
        XCTAssertEqual(voice.position, 2400, "P1 expiry/death must not duplicate or restart P2's existing loop")
        state.tanks[1].starmanTime = 0
        XCTAssertFalse(StarmanAudio.isActive(snapshot: state, primaryID: 1, secondaryID: 2))
        XCTAssertFalse(StarmanAudio.isActive(snapshot: state, primaryID: 3), "A remote bot cannot be treated as a local pilot")
        XCTAssertFalse(StarmanAudio.isActive(snapshot: state, primaryID: -1))
    }

    func testGameplayTransitionsAndNonFiniteEffectsCannotLeaveTheLoopRunning() {
        var state = ArenaSnapshot(tanks: [ArenaTank(id: 1, starmanTime: 1)])
        XCTAssertTrue(StarmanAudio.isActive(snapshot: state, primaryID: 1))
        XCTAssertFalse(StarmanAudio.isActive(snapshot: state, primaryID: 1, gameplayActive: false), "Pause, mute, background and stale/disconnected contexts are inactive")
        for phase in ["countdown", "paused", "roundOver", "matchOver", "lobby"] {
            state.phase = phase; XCTAssertFalse(StarmanAudio.isActive(snapshot: state, primaryID: 1), phase)
        }
        state.phase = "playing"; state.result = ArenaResult(id: 1)
        XCTAssertFalse(StarmanAudio.isActive(snapshot: state, primaryID: 1))
        state.result = nil
        state.objectives = ArenaObjectives(mode: "survival", survival: ArenaSurvival(status: "break"))
        XCTAssertFalse(StarmanAudio.isActive(snapshot: state, primaryID: 1))
        state.objectives = nil
        for remaining in [0.0, -1, .nan, .infinity] {
            state.tanks[0].starmanTime = remaining
            XCTAssertFalse(StarmanAudio.isActive(snapshot: state, primaryID: 1))
        }
    }

    func testResetAndResumeStartCurrentMusicWithoutCatchUpOrQueuedCopies() {
        var voice = AudioLoopVoice(samples: [0, 1, 0, -1])
        voice.setActive(true)
        for _ in 0..<1000 { _ = voice.nextSample() }
        voice.reset()
        XCTAssertFalse(voice.requested); XCTAssertEqual(voice.position, 0)
        for _ in 0..<1000 { XCTAssertEqual(voice.nextSample(), 0) }
        voice.setActive(true)
        XCTAssertEqual(voice.nextSample(), 0); XCTAssertEqual(voice.position, 1)
        voice.setActive(false)
        for _ in 0..<100 { _ = voice.nextSample() }
        let position = voice.position
        voice.setActive(true)
        XCTAssertEqual(voice.position, position, "A rapid fade reversal keeps one voice and continuous phase")
    }

    func testLoopSharesTheProtectedMasterBusAndLeavesRoomForPickupAndRapidFire() {
        let pcm = StarmanAudio.samples(), pickup = AudioSynthesis.samples(for: .pickup, sampleRate: 48_000)
        let rapid = AudioSynthesis.samples(for: .rapid, sampleRate: 48_000)
        var voice = AudioLoopVoice(samples: pcm), mixer = AudioMixProcessor(sampleRate: 48_000, volume: 1)
        voice.setActive(true)
        var peak: Float = 0, energy = 0.0
        for frame in 0..<192_000 {
            let sound = voice.nextSample() + (frame < pickup.count ? pickup[frame] : 0) + rapid[frame % rapid.count] * 32
            let output = mixer.process(sound)
            XCTAssertTrue(output.isFinite); XCTAssertLessThanOrEqual(abs(output), 0.98)
            peak = max(peak, abs(output)); energy += Double(output) * Double(output)
        }
        XCTAssertGreaterThan(peak, 0.05); XCTAssertGreaterThan(energy, 1)
    }

    func testCachedLoopAndBusRenderCostIsMeasuredWithoutSynthesizingInTheCallback() {
        let pcm = StarmanAudio.samples()
        var voice = AudioLoopVoice(samples: pcm), mixer = AudioMixProcessor(sampleRate: 48_000)
        voice.setActive(true)
        let start = ProcessInfo.processInfo.systemUptime
        var checksum = 0.0
        for _ in 0..<480_000 { checksum += Double(mixer.process(voice.nextSample())) }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print("Cached Starman voice + shared bus: \(elapsed * 100) ms CPU per rendered second, Debug, 48kHz")
        XCTAssertTrue(checksum.isFinite)
    }
}
