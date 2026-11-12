import Foundation
import XCTest
@testable import leqraCore

final class AudioMixProcessorTests: XCTestCase {
    func testShortCueMixMatchesActualBrowserOfflineAudioReference() {
        // Independent 48 kHz OfflineAudioContext output from v4.49.36's own
        // recipes and graph at 50%, padded to .6s. This catches startup detector
        // behavior that a generic one-pole compressor gets audibly wrong.
        let references: [(AudioCue, Double, Double)] = [
            (.regular, 0.2438400536775589, 0.021938487078701455),
            (.rapid, 0.10355628281831741, 0.008488832582143476),
            (.laser, 0.15497878193855286, 0.02378347603170648),
            (.cannon, 0.33652395009994507, 0.055846590780702775),
            (.pickup, 0.17037874460220337, 0.027143030315682107)
        ]
        for (cue, expectedPeak, expectedRMS) in references {
            let raw = AudioSynthesis.samples(for: cue, sampleRate: 48_000)
            var processor = AudioMixProcessor(sampleRate: 48_000)
            var peak = 0.0, energy = 0.0
            for frame in 0..<28_800 {
                let sample = Double(processor.process(frame < raw.count ? raw[frame] : 0))
                peak = max(peak, abs(sample)); energy += sample * sample
            }
            // Overlapping pickup oscillators have a small phase-dependent
            // transient difference; their integrated level stays within .5%.
            XCTAssertEqual(peak, expectedPeak, accuracy: expectedPeak * (cue == .pickup ? 0.025 : 0.005), cue.rawValue)
            XCTAssertEqual(sqrt(energy / 28_800), expectedRMS, accuracy: expectedRMS * 0.005, cue.rawValue)
        }
    }

    func testQuietCueAfterSilentWarmupRetainsWebGainWithoutExtraTrimAttenuation() {
        for rate in [44_100.0, 48_000.0] {
            let raw = AudioSynthesis.samples(for: .volumePreview, sampleRate: rate)
            var processor = AudioMixProcessor(sampleRate: rate)
            for _ in 0..<Int(rate) { _ = processor.process(0) }
            var output = raw.map { processor.process($0) }
            for _ in 0..<processor.latencyFrames { output.append(processor.process(0)) }
            let inputEnergy = raw.reduce(0.0) { $0 + Double($1) * Double($1) }
            let outputEnergy = output.reduce(0.0) { $0 + Double($1) * Double($1) }
            // This cue stays below the compressor threshold. Its integrated
            // energy must retain the browser's gain32, shaper .98 and master50%.
            XCTAssertEqual(sqrt(outputEnergy / inputEnergy), 15.68, accuracy: 0.00001)
        }
    }

    func testOverlappingShotsAndExplosionsStayBounded() {
        let rate = 48_000.0
        let shot = AudioSynthesis.samples(for: .cannon, sampleRate: rate)
        let blast = AudioSynthesis.samples(for: .grenadeExplosion, sampleRate: rate)
        var processor = AudioMixProcessor(sampleRate: rate, volume: 1)
        var peak = 0.0
        for frame in 0..<48_000 {
            let a = frame < shot.count ? shot[frame] : 0
            let b = frame < blast.count ? blast[frame] : 0
            let value = processor.process(a * 16 + b * 16)
            XCTAssertTrue(value.isFinite)
            peak = max(peak, abs(Double(value)))
            XCTAssertLessThanOrEqual(abs(value), 0.98)
        }
        XCTAssertGreaterThan(peak, 0.3)
    }

    func testMasterSliderScalesAfterCompressionEvenOnAnOverloadedBus() {
        var full = AudioMixProcessor(sampleRate: 48_000, volume: 1)
        var quarter = AudioMixProcessor(sampleRate: 48_000, volume: 0.25)
        var energy = 0.0
        for frame in 0..<12_000 {
            let input = Float(sin(Double(frame) * 2 * .pi * 180 / 48_000) * 0.4)
            let loud = full.process(input), quiet = quarter.process(input)
            XCTAssertEqual(quiet, loud * 0.25, accuracy: 0.000001)
            energy += Double(loud * loud)
        }
        XCTAssertGreaterThan(energy, 1)
    }

    func testMuteFadeIsContinuousAndRepeatedUIUpdatesDoNotRestartIt() {
        let rate = 48_000.0
        var processor = AudioMixProcessor(sampleRate: rate, volume: 1)
        for _ in 0..<48_000 { _ = processor.process(0.001) }
        let before = processor.process(0.001)
        processor.setVolume(0)
        var previous = before
        var largestStep: Float = 0
        var last: Float = before
        for frame in 0..<1000 {
            if frame.isMultiple(of: 64) { processor.setVolume(0) }
            last = processor.process(0.001)
            largestStep = max(largestStep, abs(last - previous))
            previous = last
        }
        XCTAssertEqual(last, 0)
        XCTAssertLessThan(largestStep, before / 100)
        processor.setVolume(0.75)
        let first = processor.process(0.001)
        XCTAssertEqual(first, 0)
        for _ in 0..<1000 { last = processor.process(0.001) }
        XCTAssertEqual(last, before * 0.75, accuracy: 0.000001)
    }

    func testResetDiscardsDelayedSoundsAndCompressionHistory() {
        var processor = AudioMixProcessor(sampleRate: 48_000, volume: 0.3)
        for _ in 0..<24_000 { _ = processor.process(0.4) }
        processor.reset()
        var fresh = AudioMixProcessor(sampleRate: 48_000, volume: 0.3)
        for frame in 0..<1000 {
            let input: Float = frame == 0 ? 0.001 : 0
            XCTAssertEqual(processor.process(input), fresh.process(input))
        }
    }

    func testMalformedPCMDoesNotLeakNonFiniteSamplesOrPoisonLaterCues() {
        var processor = AudioMixProcessor(sampleRate: .nan, volume: .infinity)
        for sample in [Float.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude] {
            XCTAssertTrue(processor.process(sample).isFinite)
        }
        for _ in 0..<1000 {
            let output = processor.process(0.001)
            XCTAssertTrue(output.isFinite)
            XCTAssertLessThanOrEqual(abs(output), 0.98)
        }
        processor.setVolume(.nan, immediate: true)
        XCTAssertEqual(processor.process(0.1), 0)
    }
}
