import AVFoundation
import UIKit
import leqraCore

/// Cached browser voices feed one native render bus, with shared compression,
/// peak protection and master volume applied to their combined signal.
@MainActor
final class GameAudio {
    var enabled = true {
        didSet { if oldValue != enabled && !enabled { pause(fadeLoop: false) } }
    }
    var volume: Float = 0.5 {
        didSet {
            guard oldValue != volume else { return }
            renderState.setVolume(volume)
            if volume <= 0 {
                let ongoing = requestedActive
                pause(fadeLoop: false); requestedActive = ongoing
            } else if requestedActive && enabled { resume() }
        }
    }

    private struct BufferKey: Hashable {
        let cue: AudioCue
        let local: Bool
    }

    private static let sampleRate = 48_000.0
    private var engine: AVAudioEngine?
    private let renderState = NativeAudioRenderState(sampleRate: 48_000)
    private var source: AVAudioSourceNode?
    private var buffers: [BufferKey: [Float]] = [:]
    private var router = AudioEventRouter()
    private var active = false
    private var sessionActive = false
    private var requestedActive = false
    private var generation: Int?
    private var previousHP: Int?
    private var lastHaptic = 0.0
    private var lastChat = -Double.infinity
    private var previewTask: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?
    private var starmanRequested = false
    private var interruptionObserver: NSObjectProtocol?
    private var configurationObserver: NSObjectProtocol?
    private let pickupHaptic = UIImpactFeedbackGenerator(style: .light)
    private let hitHaptic = UIImpactFeedbackGenerator(style: .medium)

    init() {
        for cue in AudioCue.allCases {
            let local = AudioSynthesis.samples(for: cue, sampleRate: Self.sampleRate)
            buffers[BufferKey(cue: cue, local: true)] = local
            buffers[BufferKey(cue: cue, local: false)] = AudioSynthesis.recipe(cue) == AudioSynthesis.recipe(cue, local: false)
                ? local : AudioSynthesis.samples(for: cue, local: false, sampleRate: Self.sampleRate)
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if rawType == AVAudioSession.InterruptionType.began.rawValue {
                    self.clearPlayback()
                    self.router.reset(); self.generation = nil
                    self.engine?.pause()
                    self.active = false
                    self.sessionActive = false
                } else if self.requestedActive,
                          AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume),
                          UIApplication.shared.applicationState == .active {
                    self.resume()
                }
            }
        }
    }

    /// Creating the output graph can implicitly activate iOS audio. Configure
    /// its mixing category first, and never create it for a muted launch.
    private func playbackEngine() -> AVAudioEngine {
        if let engine { return engine }
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
        let state = renderState
        let source = AVAudioSourceNode(format: format) { isSilent, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let first = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            state.render(into: first, count: Int(frameCount))
            for buffer in buffers.dropFirst() {
                buffer.mData?.assumingMemoryBound(to: Float.self).update(from: first, count: Int(frameCount))
            }
            isSilent.pointee = false
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        self.engine = engine
        self.source = source
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.engine?.isRunning != true else { return }
                self.clearPlayback()
                self.router.reset(); self.generation = nil; self.active = false
                if self.requestedActive && self.enabled && UIApplication.shared.applicationState == .active { self.resume() }
            }
        }
        return engine
    }

    deinit {
        previewTask?.cancel()
        shutdownTask?.cancel()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        engine?.stop()
        if sessionActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    func resume() {
        guard enabled else { return }
        requestedActive = true
        shutdownTask?.cancel(); shutdownTask = nil
        guard volume > 0, !active || engine?.isRunning != true else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // Ambient mixes with music and honors the Ring/Silent switch.
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            sessionActive = true
            let engine = playbackEngine()
            renderState.setVolume(volume, immediate: true)
            if !engine.isRunning { engine.prepare(); try engine.start() }
            active = true
        } catch {
            active = false
            engine?.pause()
            deactivateSession()
            // Losing an audio route must never stop a match.
        }
    }

    func pause(fadeLoop: Bool = true) {
        previewTask?.cancel(); previewTask = nil
        shutdownTask?.cancel(); shutdownTask = nil
        requestedActive = false; active = false
        starmanRequested = false
        router.reset(); generation = nil
        if fadeLoop, engine?.isRunning == true, UIApplication.shared.applicationState == .active,
           renderState.fadeLoopAndClearEffects() {
            // Let the 12ms envelope and the shared 6ms look-ahead drain. One
            // cancelable task covers pause/menu/connection transitions.
            shutdownTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 22_000_000)
                guard !Task.isCancelled, let self, !self.requestedActive else { return }
                self.clearPlayback(); self.engine?.pause(); self.deactivateSession()
                self.shutdownTask = nil
            }
        } else {
            clearPlayback(); engine?.pause(); deactivateSession()
        }
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        sessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func reset() {
        pause()
        router.reset()
        generation = nil; previousHP = nil; lastHaptic = 0; lastChat = -.infinity
    }

    func consume(snapshot: ArenaSnapshot, localID: Int, infinity: Bool, online: Bool,
                 secondaryLocalID: Int? = nil, gameplayActive: Bool = true) {
        let local = snapshot.tanks.first { $0.id == localID }
        if generation != snapshot.generation {
            generation = snapshot.generation
            clearPlayback()
            previousHP = local?.hp
        }
        let justDied = (previousHP ?? 0) > 0 && local?.hp == 0
        previousHP = local?.hp
        let now = ProcessInfo.processInfo.systemUptime
        let requests = router.consume(snapshot: snapshot, localID: localID, infinity: infinity, online: online, now: now)
        updateStarman(snapshot: snapshot, localID: localID, secondaryLocalID: secondaryLocalID, gameplayActive: gameplayActive)
        guard enabled, volume > 0, active, engine?.isRunning == true else { return }
        if justDied, now - lastHaptic >= 0.1 {
            hitHaptic.impactOccurred(intensity: 0.55)
            lastHaptic = now
        }
        for request in requests {
            play(request.cue, local: request.local)
            if request.cue == .pickup, request.local, now - lastHaptic >= 0.1 {
                pickupHaptic.impactOccurred(intensity: 0.35)
                lastHaptic = now
            }
        }
    }

    func updateStarman(snapshot: ArenaSnapshot, localID: Int, secondaryLocalID: Int? = nil, gameplayActive: Bool) {
        let wanted = enabled && volume > 0 && active && engine?.isRunning == true && generation == snapshot.generation
            && StarmanAudio.isActive(snapshot: snapshot, primaryID: localID, secondaryID: secondaryLocalID, gameplayActive: gameplayActive)
        guard starmanRequested != wanted else { return }
        starmanRequested = wanted
        renderState.setStarman(wanted)
    }

    private func clearPlayback() {
        starmanRequested = false
        renderState.clear()
    }

    func notifyChat() {
        let now = ProcessInfo.processInfo.systemUptime
        guard enabled, volume > 0, active, engine?.isRunning == true, now - lastChat >= AudioSynthesis.chatInterval else { return }
        lastChat = now
        play(.chat)
    }

    func preview(_ cue: AudioCue) {
        guard enabled, volume > 0 else { return }
        let ongoing = requestedActive
        resume()
        requestedActive = ongoing
        guard active else { return }
        play(cue)
        previewTask?.cancel()
        guard !ongoing else { return }
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self, !self.requestedActive else { return }
            self.pause()
        }
    }

    private func play(_ cue: AudioCue, local: Bool = true) {
        guard let samples = buffers[BufferKey(cue: cue, local: local)] else { return }
        renderState.enqueue(samples)
    }
}

/// Control changes and the audio callback share this short, bounded critical
/// section. Sounds and the 32 voice slots are prepared before playback; the
/// callback neither constructs sounds nor truncates a playing waveform.
private final class NativeAudioRenderState: @unchecked Sendable {
    private struct Voice {
        var samples: [Float] = []
        var cursor = 0
    }
    private let lock = NSLock()
    private var voices = Array(repeating: Voice(), count: 32)
    private var processor: AudioMixProcessor
    private var starman: AudioLoopVoice

    init(sampleRate: Double) {
        processor = AudioMixProcessor(sampleRate: sampleRate)
        starman = AudioLoopVoice(samples: StarmanAudio.samples(sampleRate: sampleRate), sampleRate: sampleRate)
    }

    func setStarman(_ active: Bool) {
        lock.lock(); defer { lock.unlock() }
        starman.setActive(active)
    }

    func fadeLoopAndClearEffects() -> Bool {
        lock.lock(); defer { lock.unlock() }
        for index in voices.indices { voices[index].cursor = voices[index].samples.count }
        starman.setActive(false)
        return starman.sounding
    }

    func enqueue(_ samples: [Float]) {
        lock.lock(); defer { lock.unlock() }
        // Omit a new effect if every voice is busy instead of clicking by
        // interrupting another sound partway through its waveform.
        guard let index = voices.indices.first(where: { voices[$0].cursor >= voices[$0].samples.count }) else { return }
        voices[index].samples = samples
        voices[index].cursor = 0
    }

    func setVolume(_ volume: Float, immediate: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        processor.setVolume(volume, immediate: immediate)
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        for index in voices.indices { voices[index].cursor = voices[index].samples.count }
        starman.reset()
        processor.reset()
    }

    func render(into output: UnsafeMutablePointer<Float>, count: Int) {
        lock.lock(); defer { lock.unlock() }
        for frame in 0..<count {
            var mixed = starman.nextSample()
            for index in voices.indices where voices[index].cursor < voices[index].samples.count {
                mixed += voices[index].samples[voices[index].cursor]
                voices[index].cursor += 1
            }
            output[frame] = processor.process(mixed)
        }
    }
}
