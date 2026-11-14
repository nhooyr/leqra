import Foundation

/// An original bright, upbeat chip loop shared by the three clients. Generate
/// once per output rate, outside the real-time callback and gameplay frames.
public enum StarmanAudio {
    public static let duration = 4.0
    public static let fadeDuration = 0.012
    public static let leadNotes = [74, 78, 81, 86, 83, 81, 78, 81, 76, 79, 83, 88, 86, 83, 79, 83,
                                   74, 81, 86, 90, 88, 86, 81, 78, 73, 76, 81, 85, 83, 81, 76, 73]
    public static let bassNotes = [50, 55, 50, 57, 50, 55, 52, 57]

    public static func samples(sampleRate: Double = 48_000) -> [Float] {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate) else { return [] }
        let leads = leadNotes.map { 440 * pow(2, Double($0 - 69) / 12) }
        let basses = bassNotes.map { 440 * pow(2, Double($0 - 69) / 12) }
        var pcm = [Float](repeating: 0, count: Int((duration * sampleRate).rounded()))
        for index in pcm.indices {
            let time = Double(index) / sampleRate
            let leadStep = min(leadNotes.count - 1, Int(time / 0.125))
            let leadTime = time - Double(leadStep) * 0.125
            var value = 0.0
            if leadTime < 0.105 {
                let envelope = max(0, min(1, leadTime / 0.006) * min(1, (0.105 - leadTime) / 0.035)
                    * (0.7 + 0.3 * exp(-10 * leadTime)))
                let phase = 2 * Double.pi * leads[leadStep] * leadTime
                let wave = (sin(phase) - sin(3 * phase) / 9 + sin(5 * phase) / 25) * 8 / (Double.pi * Double.pi)
                value += wave * envelope * 0.0035
            }
            let bassStep = min(bassNotes.count - 1, Int(time / 0.5))
            let bassTime = time - Double(bassStep) * 0.5
            if bassTime < 0.42 {
                let envelope = max(0, min(1, bassTime / 0.008) * min(1, (0.42 - bassTime) / 0.06))
                let phase = 2 * Double.pi * basses[bassStep] * bassTime
                value += (sin(phase) + 0.18 * sin(2 * phase)) * envelope * 0.0018
            }
            pcm[index] = Float(value)
        }
        return pcm
    }

    /// Snapshot state, never pickup history, controls the loop. P2's ID must
    /// come from the active arena identity rather than a retained room socket.
    public static func isActive(snapshot: ArenaSnapshot, primaryID: Int, secondaryID: Int? = nil,
                                gameplayActive: Bool = true) -> Bool {
        guard gameplayActive, !snapshot.spectating, snapshot.phase == "playing", snapshot.result == nil,
              snapshot.objectives?.survival?.status != "break" else { return false }
        return snapshot.tanks.contains { tank in
            (tank.id == primaryID && primaryID >= 0 || secondaryID.map { $0 >= 0 && tank.id == $0 } == true)
                && !tank.bot && tank.hp > 0 && tank.starmanTime.isFinite && tank.starmanTime > 0
        }
    }
}

/// One bounded, allocation-free loop voice. Reactivating during its release
/// reverses that same envelope; reset/resume never schedules missed notes.
public struct AudioLoopVoice: Sendable {
    private let samples: [Float]
    private let fadeFrames: Int
    private var cursor = 0
    private var gain: Float = 0
    private var target: Float = 0
    private var increment: Float = 0
    private var remaining = 0
    public private(set) var requested = false
    public var sounding: Bool { requested || gain > 0 }
    public var position: Int { cursor }

    public init(samples: [Float], sampleRate: Double = 48_000) {
        self.samples = samples
        let rate = sampleRate.isFinite ? max(8_000, min(192_000, sampleRate)) : 48_000
        fadeFrames = max(1, Int((rate * StarmanAudio.fadeDuration).rounded()))
    }

    public mutating func setActive(_ active: Bool) {
        guard active != requested, !samples.isEmpty else { return }
        requested = active
        if active && gain == 0 { cursor = 0 }
        target = active ? 1 : 0
        remaining = fadeFrames
        increment = (target - gain) / Float(fadeFrames)
    }

    public mutating func reset() {
        cursor = 0; gain = 0; target = 0; increment = 0; remaining = 0; requested = false
    }

    public mutating func nextSample() -> Float {
        guard sounding, !samples.isEmpty else { return 0 }
        let output = samples[cursor] * gain
        cursor += 1
        if cursor == samples.count { cursor = 0 }
        if remaining > 0 {
            gain += increment; remaining -= 1
            if remaining == 0 {
                gain = target; increment = 0
                if target == 0 { cursor = 0 }
            }
        }
        return output
    }
}
