import Foundation

/// One shared effects bus, matching the browser's gain/compressor/trim/shaper/
/// master order. Pass the sum of raw cue samples; do not gain each voice first.
/// The fixed look-ahead buffer is allocated once. Keep one mutable processor on
/// the render thread rather than copying this value for every audio callback.
public struct AudioMixProcessor: Sendable {
    public let sampleRate: Double
    public let latencyFrames: Int

    private var delay: [Float]
    private var delayIndex = 0
    private var compressorGain = 1.0
    private var detectorAverage = 0.0
    private var desiredGain = 0.0
    private var envelopeRate = 0.0
    private var divisionRemaining = 0
    private var greatestAttackDifference = -1.0
    private let threshold: Double
    private let compressionExponent: Double
    private let attackFrames: Double
    private let releaseFrames: Double
    private let detectorFrames: Double
    private let postCompressorGain: Double
    private let rampFrames: Int
    private var master: Double
    private var targetMaster: Double
    private var masterIncrement = 0.0
    private var rampRemaining = 0

    public init(sampleRate: Double = 44_100, volume: Float = 0.5) {
        let rate = sampleRate.isFinite && (8_000...192_000).contains(sampleRate) ? sampleRate : 44_100
        self.sampleRate = rate
        latencyFrames = max(1, Int(rate * 0.006))
        delay = [Float](repeating: 0, count: latencyFrames)
        threshold = pow(10, AudioSynthesis.compressorThresholdDB / 20)
        compressionExponent = 1 - 1 / AudioSynthesis.compressorRatio
        attackFrames = rate * max(0.001, AudioSynthesis.compressorAttack)
        releaseFrames = rate * AudioSynthesis.compressorRelease
        detectorFrames = rate * 0.0025
        // Web Audio automatically applies makeup based on the full-range
        // compression curve. The game's trim cancels exactly that stage, so
        // quiet cues retain their requested level rather than being boosted.
        let fullRangeGain = pow(threshold, compressionExponent)
        let makeup = pow(1 / fullRangeGain, 0.6)
        postCompressorGain = makeup * AudioSynthesis.trimGain
        rampFrames = max(1, Int((rate * AudioSynthesis.volumeRampDuration).rounded()))
        let initial = Self.unit(volume)
        master = initial; targetMaster = initial
    }

    /// Slider gain comes after protection, so it remains linear even when many
    /// voices overlap. Repeated UI updates to the same value do not restart a
    /// fade; a new target starts from the current interpolated gain.
    public mutating func setVolume(_ unit: Float, immediate: Bool = false) {
        let value = Self.unit(unit)
        if immediate {
            master = value; targetMaster = value; masterIncrement = 0; rampRemaining = 0
        } else if value != targetMaster {
            targetMaster = value
            rampRemaining = rampFrames
            masterIncrement = (value - master) / Double(rampFrames)
        }
    }

    /// Clears delayed samples and compression history while retaining the
    /// requested slider level. No allocation is needed after initialization.
    public mutating func reset() {
        for index in delay.indices { delay[index] = 0 }
        delayIndex = 0; compressorGain = 1
        detectorAverage = 0; desiredGain = 0; envelopeRate = 0
        divisionRemaining = 0; greatestAttackDifference = -1
        master = targetMaster; masterIncrement = 0; rampRemaining = 0
    }

    public mutating func process(_ sample: Float) -> Float {
        // Invalid upstream PCM must not poison the envelope or future audio.
        // Double arithmetic also avoids overflow when a malformed finite Float
        // reaches the bus. 1024 exceeds any sum from the bounded voice pool.
        let input = sample.isFinite ? max(-1024, min(1024, Double(sample) * AudioSynthesis.effectGain)) : 0
        if divisionRemaining == 0 { updateEnvelope(); divisionRemaining = 32 }
        let magnitude = abs(input)
        let target = magnitude > threshold ? pow(threshold / magnitude, compressionExponent) : 1
        let detectorDB = max(2, -20 * log10(max(0.0000001, target)))
        let detectorRate = target > detectorAverage ? pow(10, detectorDB / detectorFrames / 20) - 1 : 1
        detectorAverage = min(1, detectorAverage + (target - detectorAverage) * detectorRate)
        if envelopeRate < 1 { compressorGain += (desiredGain - compressorGain) * envelopeRate }
        else { compressorGain = min(1, compressorGain * envelopeRate) }
        divisionRemaining -= 1

        let delayed = Double(delay[delayIndex])
        delay[delayIndex] = Float(input)
        delayIndex += 1
        if delayIndex == delay.count { delayIndex = 0 }
        let compressed = delayed * sin(.pi / 2 * compressorGain) * postCompressorGain
        // The browser's three-point [-.98, 0, .98] WaveShaper is linear at
        // .98*x inside [-1,1], and saturates outside that interval.
        let limited = max(-1, min(1, compressed)) * AudioSynthesis.limiterCeiling
        let output = Float(limited * master)
        if rampRemaining > 0 {
            master += masterIncrement
            rampRemaining -= 1
            if rampRemaining == 0 { master = targetMaster; masterIncrement = 0 }
        }
        return output
    }

    /// Web Audio leaves envelope curves implementation-dependent. These
    /// detector/prewarp and adaptive-release equations reproduce the Blink /
    /// WebKit behavior used by the game's actual browser graph, including its
    /// startup response. Re-evaluate the envelope once per 32 audio samples.
    /// https://webaudio.github.io/web-audio-api/#dynamicscompressornode-processing
    /// https://chromium.googlesource.com/chromium/src/+/main/third_party/blink/renderer/platform/audio/dynamics_compressor.cc
    private mutating func updateEnvelope() {
        desiredGain = asin(max(0, min(1, detectorAverage))) / (.pi / 2)
        let releasing = desiredGain > compressorGain
        let difference = desiredGain > 0 ? 20 * log10(max(0.0000000001, compressorGain / desiredGain)) : (releasing ? -1 : 1)
        if releasing {
            greatestAttackDifference = -1
            let x = (max(-12, min(0, difference)) + 12) * 0.25
            // Adaptive release passes through .09, .16, .42, .98 of the
            // requested release duration as compression approaches zero.
            let duration = 0.09 + x * (0.005988750244256685 + x * (0.050409513441085324 + x * (0.012655416910923124 + x * 0.0009463194037350395)))
            envelopeRate = pow(10, 5 / max(1, duration * releaseFrames) / 20)
        } else {
            greatestAttackDifference = max(greatestAttackDifference, difference)
            envelopeRate = 1 - pow(0.25 / max(0.5, greatestAttackDifference), 1 / attackFrames)
        }
    }

    private static func unit(_ value: Float) -> Double {
        if value.isNaN { return 0 }
        return max(0, min(1, Double(value)))
    }
}
