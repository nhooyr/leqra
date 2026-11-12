import XCTest
@testable import leqraCore

final class AudioSynthesisTests: XCTestCase {
    func testWeaponRecipesMatchCurrentBrowserSource() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("src/web/assets/v4.49.36/game.js"))
        let expression = try NSRegularExpression(pattern: "(regular|rapid|scatter|laser|homing|grenade|cannon):(\\[\\[[^\\n]*?\\]\\])")
        let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
        XCTAssertEqual(matches.count, 7)
        for match in matches {
            let name = String(source[Range(match.range(at: 1), in: source)!])
            var json = String(source[Range(match.range(at: 2), in: source)!]).replacingOccurrences(of: "'", with: "\"")
            json = json.replacingOccurrences(of: "(?<=[,\\[])\\.(\\d+)", with: "0.$1", options: .regularExpression)
            let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[Any]])
            let cue = try XCTUnwrap(AudioCue(rawValue: name))
            for local in [true, false] {
                let recipe = AudioSynthesis.recipe(cue, local: local)
                XCTAssertNil(recipe.noise, name)
                XCTAssertEqual(recipe.tones.count, rows.count, name)
                for (tone, row) in zip(recipe.tones, rows) {
                    XCTAssertEqual(tone.frequency, try XCTUnwrap(row[0] as? Double), name)
                    XCTAssertEqual(tone.endFrequency, try XCTUnwrap(row[1] as? Double), name)
                    XCTAssertEqual(tone.duration, try XCTUnwrap(row[2] as? Double), name)
                    XCTAssertEqual(tone.gain, try XCTUnwrap(row[local ? 3 : 4] as? Double), name)
                    XCTAssertEqual(tone.waveform.rawValue, try XCTUnwrap(row[5] as? String), name)
                    XCTAssertEqual(tone.delay, 0, name)
                }
            }
        }
    }

    func testGainEnvelopeMatchesWebAutomationAndFinishesWithoutAnEdge() {
        let tone = AudioSynthesis.recipe(.regular).tones[0]
        XCTAssertEqual(AudioSynthesis.envelope(tone, at: 0), 0)
        XCTAssertEqual(AudioSynthesis.envelope(tone, at: 0.006), 0.024, accuracy: 1e-12)
        XCTAssertEqual(AudioSynthesis.envelope(tone, at: 0.012), 0.048, accuracy: 1e-12)
        XCTAssertEqual(AudioSynthesis.envelope(tone, at: 0.051), sqrt(0.048 * 0.0001), accuracy: 1e-12)
        XCTAssertEqual(AudioSynthesis.envelope(tone, at: 0.09), 0.0001, accuracy: 1e-12)
        XCTAssertEqual(AudioSynthesis.envelope(tone, at: 0.094), 0.00005, accuracy: 1e-12)
        XCTAssertEqual(AudioSynthesis.envelope(tone, at: 0.098), 0, accuracy: 1e-12)
        let rapid = AudioSynthesis.recipe(.rapid).tones[0]
        XCTAssertEqual(AudioSynthesis.envelope(rapid, at: 0.0096), 0.023, accuracy: 1e-12)
    }

    func testSweepUsesGeometricPitchAndHoldsEndFrequencyDuringRelease() {
        let tone = AudioTone(frequency: 800, endFrequency: 200, duration: 0.2, gain: 0.03)
        XCTAssertEqual(AudioSynthesis.frequency(tone, at: 0.1), 400, accuracy: 1e-10)
        XCTAssertEqual(AudioSynthesis.frequency(tone, at: 0.25), 200, accuracy: 1e-10)
        let delta = 0.000001
        for (time, pitch) in [(0.05, 800 / sqrt(2)), (0.15, 200 * sqrt(2)), (0.205, 200)] {
            let measured = (AudioSynthesis.phase(tone, at: time + delta) - AudioSynthesis.phase(tone, at: time - delta)) / (4 * .pi * delta)
            XCTAssertEqual(measured, pitch, accuracy: 1e-6)
        }
    }

    func testPickupChordDelaysAndFullReleaseArePreservedInOneBuffer() {
        let recipe = AudioSynthesis.recipe(.pickup)
        XCTAssertEqual(recipe.tones.map(\.frequency), [480, 640, 880])
        XCTAssertEqual(recipe.tones.map(\.endFrequency), [520, 700, 980])
        XCTAssertEqual(recipe.tones.map(\.delay), [0, 0.07, 0.14])
        XCTAssertEqual(recipe.tones.map(\.gain), [0.013, 0.011, 0.010])
        XCTAssertEqual(recipe.duration, 0.272, accuracy: 1e-12)
        let delayed = AudioRecipe(tones: [recipe.tones[2]])
        let pcm = AudioSynthesis.samples(for: delayed)
        XCTAssertEqual(pcm.count, Int(ceil(0.272 * 44_100)))
        XCTAssertTrue(pcm.prefix(6_175).allSatisfy { $0 == 0 })
        XCTAssertTrue(pcm.dropFirst(6_200).contains { abs($0) > 0.001 })
        XCTAssertTrue(pcm.suffix(170).allSatisfy { $0 == 0 })
    }

    func testRemoteWeaponUsesItsFarGainWithoutChangingWaveShape() {
        let local = AudioSynthesis.samples(for: .regular)
        let remote = AudioSynthesis.samples(for: .regular, local: false)
        let nearTone = AudioSynthesis.recipe(.regular).tones[0]
        let farTone = AudioSynthesis.recipe(.regular, local: false).tones[0]
        XCTAssertEqual(local.count, remote.count)
        var maximumError = 0.0
        for (index, pair) in zip(local, remote).enumerated() {
            let time = Double(index) / 44_100, envelope = AudioSynthesis.envelope(nearTone, at: time)
            // Both voices decay to the same absolute .0001 gain. Their gain
            // ratio therefore converges to one during the release.
            let expected = envelope > 0 ? Double(pair.0) * AudioSynthesis.envelope(farTone, at: time) / envelope : 0
            maximumError = max(maximumError, abs(Double(pair.1) - expected))
        }
        XCTAssertLessThan(maximumError, 1e-8)
    }

    func testExplosionUsesFilteredDecayingNoiseAndSeparateBassLayers() throws {
        let death = AudioSynthesis.recipe(.explosion), grenade = AudioSynthesis.recipe(.grenadeExplosion)
        let deathNoise = try XCTUnwrap(death.noise), grenadeNoise = try XCTUnwrap(grenade.noise)
        XCTAssertEqual(deathNoise.cutoff, 320); XCTAssertEqual(grenadeNoise.cutoff, 750)
        XCTAssertEqual(deathNoise.resonanceDB, 0.5)
        XCTAssertEqual(deathNoise.gain, 0.10); XCTAssertEqual(grenadeNoise.gain, 0.12)
        XCTAssertEqual(death.tones.map(\.frequency), [90])
        XCTAssertEqual(grenade.tones.map(\.frequency), [160, 360])
        XCTAssertEqual(grenade.tones.map(\.delay), [0, 0.02])
        let low = AudioSynthesis.samples(for: AudioRecipe(noise: deathNoise))
        let high = AudioSynthesis.samples(for: AudioRecipe(noise: grenadeNoise))
        XCTAssertEqual(low, AudioSynthesis.samples(for: AudioRecipe(noise: deathNoise)))
        XCTAssertNotEqual(low, AudioSynthesis.samples(for: AudioRecipe(noise: deathNoise), noiseSeed: 42))
        func differenceEnergy(_ samples: [Float]) -> Double {
            let energy = samples.reduce(0.0) { $0 + Double($1 * $1) }
            return zip(samples, samples.dropFirst()).reduce(0.0) { $0 + pow(Double($1.1 - $1.0), 2) } / energy
        }
        // A noise-heavy weapon or an unfiltered explosion fails these bounds.
        XCTAssertLessThan(differenceEnergy(low), 0.01)
        XCTAssertGreaterThan(differenceEnergy(high), differenceEnergy(low) * 3)
        XCTAssertLessThan(differenceEnergy(high), 0.08)
        let early = low[1_000..<4_000].reduce(0.0) { $0 + Double($1 * $1) }
        let late = low[10_000..<13_000].reduce(0.0) { $0 + Double($1 * $1) }
        XCTAssertLessThan(late, early / 20)
    }

    func testAllVoicesRetainHeadroomAndSilentStartStop() {
        for cue in AudioCue.allCases {
            let pcm = AudioSynthesis.samples(for: cue)
            XCTAssertFalse(pcm.isEmpty, cue.rawValue)
            XCTAssertEqual(pcm.first, 0, cue.rawValue)
            XCTAssertTrue(pcm.allSatisfy { $0.isFinite && abs($0) < 0.2 }, cue.rawValue)
            XCTAssertLessThan(abs(pcm.last ?? 1), 1e-8, cue.rawValue)
            XCTAssertTrue(pcm.contains { abs($0) > 0.001 }, cue.rawValue)
        }
        XCTAssertTrue(AudioSynthesis.samples(for: .regular, sampleRate: 0).isEmpty)
        XCTAssertTrue(AudioSynthesis.samples(for: .regular, sampleRate: .nan).isEmpty)
    }

    func testRawVoiceEnergyMatchesActualOfflineWebAudioRendering() {
        // Chromium OfflineAudioContext, 48 kHz/.6 s, actual v4.49.36 webTone,
        // shotSound, pickupSound and boom, before the shared mix bus. Delayed
        // oscillator start phase is engine-dependent; energy and peaks match.
        let references: [(AudioCue, Double, Double)] = [
            (.regular, 0.0036482660528818927, 0.04722806438803673),
            (.laser, 0.002774291993038309, 0.026573486626148224),
            (.pickup, 0.0021029309166631753, 0.012912243604660034),
            (.explosion, 0.007940465198757839, 0.05132853239774704),
            (.grenadeExplosion, 0.010716303496570814, 0.06949907541275024)
        ]
        for (cue, rms, peak) in references {
            let pcm = AudioSynthesis.samples(for: cue, sampleRate: 48_000)
            let measured = sqrt(pcm.reduce(0.0) { $0 + Double($1) * Double($1) } / 28_800)
            XCTAssertEqual(measured, rms, accuracy: rms * 0.001, cue.rawValue)
            XCTAssertEqual(Double(pcm.map(abs).max() ?? 0), peak, accuracy: peak * 0.001, cue.rawValue)
        }
    }

    func testNoiseMatchesOfflineWebAudioLowpassFixture() throws {
        // Actual BiquadFilterNode output, Q=.5 dB/cutoff320, using the shared
        // xorshift0x51e9a7c3 noise texture and browser's two decay envelopes.
        let noise = try XCTUnwrap(AudioSynthesis.recipe(.explosion).noise)
        let pcm = AudioSynthesis.samples(for: AudioRecipe(noise: noise), sampleRate: 48_000)
        for (index, reference) in [(1, 1.18927189874e-7), (64, -0.000294787227176),
                                    (960, -0.00562115199864), (1000, -0.0088546378538),
                                    (4096, 0.00888813566417), (8192, 0.00225069350563),
                                    (12000, 0.000367495318642), (14399, -1.88370363752e-9)] {
            XCTAssertEqual(Double(pcm[index]), reference, accuracy: 2e-9)
        }
    }

    func testTransitionsAndSharedMixUseBrowserLevels() {
        XCTAssertEqual(AudioSynthesis.recipe(.countdown).tones[0].frequency, 390)
        XCTAssertEqual(AudioSynthesis.recipe(.go).tones[0].frequency, 740)
        XCTAssertEqual(AudioSynthesis.recipe(.roundWin).tones.map(\.delay), [0, 0.13])
        XCTAssertEqual(AudioSynthesis.recipe(.onlineRoundEnd).tones[0].frequency, 600)
        XCTAssertEqual(AudioSynthesis.recipe(.onlineRoundEnd, local: false).tones[0].frequency, 300)
        XCTAssertEqual(AudioSynthesis.recipe(.roundDraw).tones[0].endFrequency, 180)
        XCTAssertEqual(AudioSynthesis.recipe(.homingWarning).tones.map(\.frequency), [620, 740])
        XCTAssertEqual(AudioSynthesis.recipe(.homingWarning).tones.map(\.endFrequency), [740, 860])
        XCTAssertEqual(AudioSynthesis.recipe(.homingWarning).tones.map(\.delay), [0, 0.105])
        XCTAssertEqual(AudioSynthesis.recipe(.homingWarning).tones.map(\.duration), [0.08, 0.09])
        XCTAssertEqual(AudioSynthesis.recipe(.homingWarning).tones.map(\.gain), [0.015, 0.013])
        XCTAssertEqual(AudioSynthesis.effectGain, 32)
        XCTAssertEqual(AudioSynthesis.trimGain, pow(10, -1.35 / 20), accuracy: 1e-12)
        XCTAssertEqual(AudioSynthesis.limiterCeiling, 0.98)
        XCTAssertEqual(AudioSynthesis.repeatedShotInterval, 0.065)
        XCTAssertEqual(AudioSynthesis.volumeRampDuration, 0.012)
    }
}
