import Foundation
import XCTest
@testable import leqraCore

final class AudioRenderBusTests: XCTestCase {
    private func render(_ bus: AudioRenderBus, _ count: Int) -> [Float] {
        var result = [Float](repeating: 0, count: count)
        result.withUnsafeMutableBufferPointer { bus.render(into: $0.baseAddress!, count: count) }
        return result
    }

    func testMailboxPreservesSharedWaveformsAndThe32VoiceLimit() {
        let bus = AudioRenderBus(), samples = AudioSynthesis.samples(for: .regular, sampleRate: 48_000)
        for _ in 0..<64 { bus.enqueue(samples) }
        let result = render(bus, samples.count + 512)
        var reference = AudioMixProcessor(sampleRate: 48_000)
        for index in result.indices {
            var mixed: Float = 0
            if index < samples.count { for _ in 0..<32 { mixed += samples[index] } }
            XCTAssertEqual(result[index], reference.process(mixed), accuracy: 1e-7)
        }
    }

    func testClearDiscardsOlderQueuedVoicesButRetainsNewerCommandsAndVolume() {
        let bus = AudioRenderBus(), old = [Float](repeating: 0.002, count: 1024), new = [Float](repeating: -0.001, count: 1024)
        bus.enqueue(old); bus.setStarman(true); bus.setVolume(0.8, immediate: true)
        bus.clear(); bus.enqueue(new)
        let result = render(bus, 1536)
        var reference = AudioMixProcessor(sampleRate: 48_000, volume: 0.8)
        for index in result.indices { XCTAssertEqual(result[index], reference.process(index < new.count ? new[index] : 0), accuracy: 1e-7) }
        bus.clear()
        XCTAssertTrue(render(bus, 1024).allSatisfy { $0 == 0 }, "No delayed pre-clear PCM may leak into a resumed engine")
    }

    func testFadeAndMuteKeepTheirExistingEnvelopesAndDiscardQueuedEffects() {
        let bus = AudioRenderBus()
        bus.setStarman(true)
        XCTAssertTrue(render(bus, 1024).contains { $0 != 0 })
        bus.enqueue([Float](repeating: 0.1, count: 5000))
        XCTAssertTrue(bus.fadeLoopAndClearEffects())
        let faded = render(bus, 4800)
        XCTAssertTrue(faded.suffix(2400).allSatisfy { $0 == 0 })
        XCTAssertFalse(bus.fadeLoopAndClearEffects())
        bus.enqueue([Float](repeating: 0.1, count: 1024)); bus.setVolume(0, immediate: true)
        XCTAssertTrue(render(bus, 1536).allSatisfy { $0 == 0 })
    }

    func testCoalescedVolumeCommandsPreserveImmediateAndResetOrdering() {
        for resets in [false, true] {
            let bus = AudioRenderBus(), samples = [Float](repeating: 0.001, count: 2048)
            var reference = AudioMixProcessor(sampleRate: 48_000)
            bus.setVolume(0, immediate: true); reference.setVolume(0, immediate: true)
            bus.setVolume(0.8); reference.setVolume(0.8)
            if resets { bus.clear(); reference.reset() }
            bus.setVolume(0.3); reference.setVolume(0.3)
            bus.enqueue(samples)
            let output = render(bus, 2048)
            for index in output.indices { XCTAssertEqual(output[index], reference.process(samples[index]), accuracy: 1e-7) }
        }
    }

    func testGameplayCommandsCanProgressWhileAnAudioBufferIsStillMixing() {
        let bus = AudioRenderBus(), done = DispatchSemaphore(value: 0)
        let worker = DispatchQueue(label: "leqra.audio-render-bus-regression")
        worker.async {
            var output = [Float](repeating: 0, count: 256_000)
            output.withUnsafeMutableBufferPointer { bus.render(into: $0.baseAddress!, count: $0.count) }
            done.signal()
        }
        let deadline = Date().addingTimeInterval(5)
        while bus.startedRenderBlocks == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
        XCTAssertGreaterThan(bus.startedRenderBlocks, 0)
        bus.enqueue([0.001, 0.002]); bus.setStarman(true); bus.setVolume(0.7)
        bus.fadeLoopAndClearEffects(); bus.clear(); bus.enqueue([0.001, 0.002])
        // This checks concurrent progress rather than imposing a machine-
        // dependent millisecond threshold on the test runner.
        XCTAssertEqual(done.wait(timeout: .now()), .timedOut, "Commands must not wait for the entire DSP buffer")
        XCTAssertEqual(done.wait(timeout: .now() + 10), .success)
        XCTAssertTrue(render(bus, 1024).allSatisfy(\.isFinite))
    }
}
