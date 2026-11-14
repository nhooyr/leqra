import Foundation

/// A single audio callback owns voices and DSP. UI/gameplay controls only touch
/// the bounded mailbox, so firing never waits for an entire audio buffer to mix.
public final class AudioRenderBus: @unchecked Sendable {
    private struct Voice { var samples: [Float] = []; var cursor = 0 }
    private let lock = NSLock()
    private var voices = Array(repeating: Voice(), count: 32)
    private var processor: AudioMixProcessor
    private var starman: AudioLoopVoice
    private var pendingSamples: [[Float]?] = Array(repeating: nil, count: 32)
    private var pendingCount = 0
    private var pendingVolume: (Float, Bool)?
    private var pendingImmediateVolume: Float?
    private var pendingStarman: Bool?
    private var pendingClear = false
    private var pendingFade = false
    private var loopMaySound = false
    private var renderBlocks = 0
    var startedRenderBlocks: Int {
        lock.lock(); defer { lock.unlock() }
        return renderBlocks
    }

    public init(sampleRate: Double = 48_000) {
        processor = AudioMixProcessor(sampleRate: sampleRate)
        starman = AudioLoopVoice(samples: StarmanAudio.samples(sampleRate: sampleRate), sampleRate: sampleRate)
    }

    public func enqueue(_ samples: [Float]) {
        lock.lock(); defer { lock.unlock() }
        guard !samples.isEmpty, pendingCount < pendingSamples.count else { return }
        pendingSamples[pendingCount] = samples
        pendingCount += 1
    }

    public func setVolume(_ volume: Float, immediate: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        if immediate { pendingImmediateVolume = volume; pendingVolume = nil }
        else { pendingVolume = (volume, false) }
    }

    public func setStarman(_ active: Bool) {
        lock.lock(); defer { lock.unlock() }
        pendingStarman = active
        if active { loopMaySound = true }
    }

    @discardableResult public func fadeLoopAndClearEffects() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let sounding = loopMaySound
        discardPendingSamples()
        pendingFade = true; pendingStarman = false
        return sounding
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        discardPendingSamples()
        // Reset adopts the latest requested target immediately. Preserve that
        // ordering even if a newer slider ramp arrives before the callback.
        if let (volume, _) = pendingVolume { pendingImmediateVolume = volume; pendingVolume = nil }
        pendingClear = true; pendingFade = false; pendingStarman = nil; loopMaySound = false
    }

    private func discardPendingSamples() {
        for index in 0..<pendingCount { pendingSamples[index] = nil }
        pendingCount = 0
    }

    private func applyCommands() {
        lock.lock(); defer { lock.unlock() }
        if pendingClear {
            for index in voices.indices { voices[index].cursor = voices[index].samples.count }
            starman.reset(); processor.reset(); pendingClear = false
        } else if pendingFade {
            for index in voices.indices { voices[index].cursor = voices[index].samples.count }
            starman.setActive(false)
        }
        pendingFade = false
        if let volume = pendingImmediateVolume { processor.setVolume(volume, immediate: true); pendingImmediateVolume = nil }
        if let (volume, immediate) = pendingVolume { processor.setVolume(volume, immediate: immediate); pendingVolume = nil }
        if let active = pendingStarman { starman.setActive(active); pendingStarman = nil }
        for index in 0..<pendingCount {
            if let samples = pendingSamples[index],
               let slot = voices.indices.first(where: { voices[$0].cursor >= voices[$0].samples.count }) {
                voices[slot].samples = samples; voices[slot].cursor = 0
            }
            pendingSamples[index] = nil
        }
        pendingCount = 0
        renderBlocks += 1
    }

    /// Only the audio engine's single render callback may call this method.
    /// Storage and cue samples are allocated before callback execution.
    public func render(into output: UnsafeMutablePointer<Float>, count: Int) {
        guard count > 0 else { return }
        applyCommands()
        // The expensive per-sample work deliberately owns no UI/control lock.
        for frame in 0..<count {
            var mixed = starman.nextSample()
            for index in voices.indices where voices[index].cursor < voices[index].samples.count {
                mixed += voices[index].samples[voices[index].cursor]
                voices[index].cursor += 1
            }
            output[frame] = processor.process(mixed)
        }
        lock.lock()
        loopMaySound = pendingClear ? pendingStarman == true : starman.sounding || pendingStarman == true
        lock.unlock()
    }
}
