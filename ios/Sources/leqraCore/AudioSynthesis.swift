import Foundation

public enum AudioCue: String, CaseIterable, Sendable {
    case regular, rapid, scatter, laser, homing, grenade, cannon
    case explosion, grenadeExplosion, ricochet, impact, shield, pickup, chat, volumePreview, unmute
    case countdown, go, roundWin, roundLoss, roundDraw, onlineRoundEnd, homingWarning
}

public enum AudioWaveform: String, Sendable {
    case sine, triangle, square, sawtooth
}

public struct AudioTone: Equatable, Sendable {
    public let frequency: Double
    public let endFrequency: Double
    public let duration: Double
    public let gain: Double
    public let waveform: AudioWaveform
    public let delay: Double

    public init(frequency: Double, endFrequency: Double, duration: Double, gain: Double,
                waveform: AudioWaveform = .sine, delay: Double = 0) {
        self.frequency = frequency; self.endFrequency = endFrequency
        self.duration = duration; self.gain = gain; self.waveform = waveform; self.delay = delay
    }
}

public struct AudioNoise: Equatable, Sendable {
    public let duration: Double
    public let gain: Double
    public let cutoff: Double
    /// Web Audio lowpass Q is expressed in dB, rather than a linear Q factor.
    public let resonanceDB: Double
    public let attack: Double

    public init(duration: Double = 0.3, gain: Double, cutoff: Double,
                resonanceDB: Double = 0.5, attack: Double = 0.02) {
        self.duration = duration; self.gain = gain; self.cutoff = cutoff
        self.resonanceDB = resonanceDB; self.attack = attack
    }
}

public struct AudioRecipe: Equatable, Sendable {
    public let tones: [AudioTone]
    public let noise: AudioNoise?
    public var duration: Double {
        max(tones.map { $0.delay + $0.duration + 0.012 }.max() ?? 0, noise?.duration ?? 0)
    }
    public init(tones: [AudioTone] = [], noise: AudioNoise? = nil) {
        self.tones = tones; self.noise = noise
    }
}

/// The current browser's Web Audio voices, before its shared effects bus.
/// Waveform gains are intentionally small: apply effectGain once to the mixed
/// bus, followed by compression, trim, limiting, and finally the volume slider.
public enum AudioSynthesis {
    public static let effectGain = 32.0
    public static let compressorThresholdDB = -3.0
    public static let compressorKnee = 0.0
    public static let compressorRatio = 4.0
    public static let compressorAttack = 0.003
    public static let compressorRelease = 0.08
    public static let trimGain = pow(10, compressorThresholdDB * (1 - 1 / compressorRatio) * 0.6 / 20)
    public static let limiterCeiling = 0.98
    public static let volumeRampDuration = 0.012
    public static let repeatedShotInterval = 0.065
    public static let ricochetInterval = 0.07
    public static let explosionInterval = 0.07
    public static let chatInterval = 0.18
    public static let homingWarningInterval = 1.5

    public static func recipe(_ cue: AudioCue, local: Bool = true) -> AudioRecipe {
        func tone(_ start: Double, _ end: Double, _ duration: Double, _ near: Double,
                  _ far: Double, _ wave: AudioWaveform = .sine, _ delay: Double = 0) -> AudioTone {
            AudioTone(frequency: start, endFrequency: end, duration: duration,
                      gain: local ? near : far, waveform: wave, delay: delay)
        }
        let layers: [AudioTone]
        switch cue {
        case .regular: layers = [tone(200, 90, 0.09, 0.048, 0.029, .triangle)]
        case .rapid: layers = [tone(210, 120, 0.06, 0.023, 0.014, .triangle)]
        case .scatter: layers = [tone(165, 85, 0.10, 0.045, 0.027, .triangle), tone(330, 150, 0.055, 0.012, 0.007)]
        case .laser: layers = [tone(720, 270, 0.18, 0.021, 0.013), tone(1080, 540, 0.10, 0.006, 0.004)]
        case .homing: layers = [tone(150, 300, 0.21, 0.027, 0.016), tone(260, 390, 0.13, 0.009, 0.005, .triangle)]
        case .grenade: layers = [tone(180, 85, 0.14, 0.032, 0.019, .triangle)]
        case .cannon: layers = [tone(105, 55, 0.24, 0.055, 0.033), tone(240, 110, 0.13, 0.022, 0.013, .triangle)]
        case .explosion:
            return AudioRecipe(tones: [tone(90, 45, 0.26, 0.055, 0.055)],
                               noise: AudioNoise(gain: 0.10, cutoff: 320))
        case .grenadeExplosion:
            return AudioRecipe(tones: [tone(160, 75, 0.26, 0.065, 0.065),
                                       tone(360, 140, 0.17, 0.040, 0.040, .triangle, 0.02)],
                               noise: AudioNoise(gain: 0.12, cutoff: 750))
        case .ricochet: layers = [tone(650, 420, 0.045, 0.016, 0.016)]
        case .impact: layers = [tone(170, 95, 0.095, 0.025, 0.025)]
        case .shield: layers = [tone(500, 260, 0.16, 0.020, 0.020)]
        case .pickup:
            layers = [tone(480, 520, 0.095, 0.013, 0.013),
                      tone(640, 700, 0.10, 0.011, 0.011, .sine, 0.07),
                      tone(880, 980, 0.12, 0.010, 0.010, .sine, 0.14)]
        case .chat:
            layers = [tone(660, 720, 0.07, 0.014, 0.014),
                      tone(880, 760, 0.09, 0.010, 0.010, .sine, 0.065)]
        case .volumePreview: layers = [tone(620, 760, 0.10, 0.008, 0.008)]
        case .unmute: layers = [tone(500, 700, 0.10, 0.008, 0.008)]
        case .countdown: layers = [tone(390, 360, 0.07, 0.012, 0.012)]
        case .go: layers = [tone(740, 880, 0.15, 0.012, 0.012)]
        // The browser plays this local-round chord for any winning side.
        case .roundWin:
            layers = [tone(430, 550, 0.12, 0.012, 0.012),
                      tone(650, 800, 0.19, 0.011, 0.011, .sine, 0.13)]
        case .roundLoss: layers = [tone(300, 450, 0.16, 0.012, 0.012)]
        case .roundDraw: layers = [tone(260, 180, 0.20, 0.012, 0.012)]
        case .onlineRoundEnd: layers = [tone(local ? 600 : 300, 450, 0.16, 0.012, 0.012)]
        case .homingWarning:
            layers = [tone(620, 740, 0.08, 0.015, 0.015),
                      tone(740, 860, 0.09, 0.013, 0.013, .sine, 0.105)]
        }
        return AudioRecipe(tones: layers)
    }

    public static func samples(for cue: AudioCue, local: Bool = true, sampleRate: Double = 44_100,
                               noiseSeed: UInt32 = 0x51e9a7c3) -> [Float] {
        samples(for: recipe(cue, local: local), sampleRate: sampleRate, noiseSeed: noiseSeed)
    }

    public static func samples(for recipe: AudioRecipe, sampleRate: Double = 44_100,
                               noiseSeed: UInt32 = 0x51e9a7c3) -> [Float] {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate),
              recipe.duration.isFinite, recipe.duration > 0, recipe.duration <= 10 else { return [] }
        var samples = [Float](repeating: 0, count: Int(ceil(recipe.duration * sampleRate)))
        for tone in recipe.tones {
            guard tone.frequency.isFinite, tone.frequency > 0, tone.endFrequency.isFinite,
                  tone.duration.isFinite, tone.duration > 0, tone.gain.isFinite, tone.gain > 0,
                  tone.delay.isFinite, tone.delay >= 0 else { continue }
            let start = Int(ceil(tone.delay * sampleRate)), stop = min(samples.count, Int(ceil((tone.delay + tone.duration + 0.012) * sampleRate)))
            guard start < stop else { continue }
            // Fix the harmonic budget for a sweep so partials cannot pop in or
            // out while its pitch changes. The recipes stay well below Nyquist.
            let harmonics = max(1, min(256, Int(sampleRate / (2 * max(tone.frequency, tone.endFrequency, 20)))))
            for index in start..<stop {
                let time = Double(index) / sampleRate - tone.delay
                let phase = phase(tone, at: time)
                samples[index] += Float(wave(tone.waveform, phase: phase, harmonics: harmonics) * envelope(tone, at: time))
            }
        }
        if let noise = recipe.noise { addNoise(noise, sampleRate: sampleRate, seed: noiseSeed, samples: &samples) }
        return samples
    }

    static func envelope(_ tone: AudioTone, at time: Double) -> Double {
        guard time >= 0, time < tone.duration + 0.008, tone.gain > 0 else { return 0 }
        let attack = min(0.012, tone.duration * 0.16)
        if time < attack { return tone.gain * time / attack }
        if time <= tone.duration {
            return tone.gain * pow(0.0001 / tone.gain, (time - attack) / (tone.duration - attack))
        }
        return 0.0001 * (1 - (time - tone.duration) / 0.008)
    }

    static func frequency(_ tone: AudioTone, at time: Double) -> Double {
        tone.frequency * pow(max(20, tone.endFrequency) / tone.frequency, min(max(time / tone.duration, 0), 1))
    }

    static func phase(_ tone: AudioTone, at time: Double) -> Double {
        let span = min(max(time, 0), tone.duration)
        let rate = log(max(20, tone.endFrequency) / tone.frequency) / tone.duration
        let cycles = abs(rate) < 1e-12 ? tone.frequency * span : tone.frequency * expm1(rate * span) / rate
        return 2 * .pi * (cycles + max(0, time - tone.duration) * max(20, tone.endFrequency))
    }

    private static func wave(_ waveform: AudioWaveform, phase: Double, harmonics: Int) -> Double {
        switch waveform {
        case .sine: return sin(phase)
        case .triangle:
            var result = 0.0
            for harmonic in stride(from: 1, through: harmonics, by: 2) {
                let h = Double(harmonic), sign = harmonic % 4 == 1 ? 1.0 : -1.0
                result += sign * sin(h * phase) / (h * h)
            }
            return result * 8 / (.pi * .pi)
        case .square:
            var result = 0.0
            for harmonic in stride(from: 1, through: harmonics, by: 2) { result += sin(Double(harmonic) * phase) / Double(harmonic) }
            return result * 4 / .pi
        case .sawtooth:
            var result = 0.0
            for harmonic in 1...harmonics { result += (harmonic % 2 == 1 ? 1.0 : -1.0) * sin(Double(harmonic) * phase) / Double(harmonic) }
            return result * 2 / .pi
        }
    }

    private static func addNoise(_ noise: AudioNoise, sampleRate: Double, seed: UInt32, samples: inout [Float]) {
        guard noise.duration.isFinite, noise.duration > 0, noise.attack > 0, noise.attack < noise.duration,
              noise.gain.isFinite, noise.gain > 0, noise.cutoff.isFinite, noise.cutoff > 0,
              noise.resonanceDB.isFinite else { return }
        let count = min(samples.count, Int(floor(noise.duration * sampleRate)))
        let omega = 2 * Double.pi * min(noise.cutoff, sampleRate / 2) / sampleRate
        let cosine = cos(omega), alpha = sin(omega) / (2 * pow(10, noise.resonanceDB / 20)), a0 = 1 + alpha
        let b0 = (1 - cosine) / 2 / a0, b1 = (1 - cosine) / a0, b2 = b0
        let a1 = -2 * cosine / a0, a2 = (1 - alpha) / a0
        var random = seed == 0 ? 1 : seed
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for index in 0..<count {
            random ^= random << 13; random ^= random >> 17; random ^= random << 5
            // The browser reuses one decaying white-noise buffer. A seed makes
            // that otherwise random texture repeatable without changing its DSP.
            let input = (Double(random) / Double(UInt32.max) * 2 - 1) * (1 - Double(index) / Double(count))
            let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = input; y2 = y1; y1 = output
            let time = Double(index) / sampleRate
            let gain = noise.gain * (time < noise.attack ? time / noise.attack : (noise.duration - time) / (noise.duration - noise.attack))
            samples[index] += Float(output * gain)
        }
    }
}
