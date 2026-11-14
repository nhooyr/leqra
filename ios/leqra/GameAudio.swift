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
    private let renderState = AudioRenderBus(sampleRate: 48_000)
    private var source: AVAudioSourceNode?
    private var buffers: [BufferKey: [Float]] = [:]
    private var router = AudioEventRouter()
    private var active = false
    private var sessionLifecycle: AudioSessionLifecycle?
    private var activationPending = false
    private var interrupted = false
    private var requestedActive = false
    private var previewActive = false
    private var pendingPreview: AudioCue?
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
    private nonisolated static let sessionQueue = DispatchQueue(label: "com.leqra.audio-session", qos: .userInitiated)

    init() {
        for cue in AudioCue.allCases {
            let local = AudioSynthesis.samples(for: cue, sampleRate: Self.sampleRate)
            buffers[BufferKey(cue: cue, local: true)] = local
            buffers[BufferKey(cue: cue, local: false)] = AudioSynthesis.recipe(cue) == AudioSynthesis.recipe(cue, local: false)
                ? local : AudioSynthesis.samples(for: cue, local: false, sampleRate: Self.sampleRate)
        }
        sessionLifecycle = AudioSessionLifecycle(
            activate: { try await Self.activateAudioSession() },
            deactivate: { [weak self] in
                self?.engine?.pause()
                await Self.deactivateAudioSession()
            },
            ready: { [weak self] in try self?.startPlayback() },
            failed: { [weak self] in
                guard let self else { return }
                self.active = false; self.activationPending = false
                self.previewActive = false; self.pendingPreview = nil
                self.clearPlayback()
            })
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if rawType == AVAudioSession.InterruptionType.began.rawValue {
                    self.interrupted = true
                    self.sessionLifecycle?.invalidateActivation()
                    self.previewTask?.cancel(); self.previewTask = nil
                    self.shutdownTask?.cancel(); self.shutdownTask = nil
                    self.previewActive = false; self.pendingPreview = nil
                    self.activationPending = false
                    self.clearPlayback()
                    self.router.reset(); self.generation = nil
                    self.engine?.pause()
                    self.active = false
                    self.deactivateSession()
                } else {
                    self.interrupted = false
                    let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                    if !shouldResume { self.requestedActive = false }
                    if self.requestedActive, shouldResume,
                          UIApplication.shared.applicationState == .active {
                        self.resume()
                    }
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
                self.activationPending = false
                self.sessionLifecycle?.invalidateActivation()
                if self.wantsPlayback && UIApplication.shared.applicationState == .active { self.activatePlayback() }
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
        let lifecycle = sessionLifecycle
        Task { @MainActor in lifecycle?.request(false) }
    }

    func resume() {
        guard enabled else { return }
        requestedActive = true
        shutdownTask?.cancel(); shutdownTask = nil
        activatePlayback()
    }

    private var wantsPlayback: Bool {
        enabled && volume > 0 && !interrupted && (requestedActive || previewActive)
    }

    private func activatePlayback() {
        guard wantsPlayback, !active || engine?.isRunning != true, !activationPending else { return }
        activationPending = true
        sessionLifecycle?.request(true)
    }

    private func startPlayback() throws {
        activationPending = false
        guard wantsPlayback else { deactivateSession(); return }
        do {
            let engine = playbackEngine()
            renderState.setVolume(volume, immediate: true)
            if !engine.isRunning { engine.prepare(); try engine.start() }
            active = true
            playPendingPreview()
        } catch {
            active = false
            engine?.pause()
            throw error // The lifecycle releases the route; a match continues silently.
        }
    }

    func pause(fadeLoop: Bool = true) {
        previewTask?.cancel(); previewTask = nil
        shutdownTask?.cancel(); shutdownTask = nil
        requestedActive = false; active = false
        activationPending = false; previewActive = false; pendingPreview = nil
        starmanRequested = false
        router.reset(); generation = nil
        if fadeLoop, engine?.isRunning == true, UIApplication.shared.applicationState == .active,
           renderState.fadeLoopAndClearEffects() {
            // Include one I/O block for mailbox delivery, then let the 12ms
            // envelope and shared 6ms look-ahead drain. One cancelable task
            // covers pause/menu/connection transitions.
            let bufferDuration = AVAudioSession.sharedInstance().ioBufferDuration
            let drain = bufferDuration.isFinite ? min(0.25, max(0, bufferDuration) + 0.022) : 0.022
            shutdownTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(drain * 1_000_000_000))
                guard !Task.isCancelled, let self, !self.requestedActive else { return }
                self.clearPlayback(); self.engine?.pause(); self.deactivateSession()
                self.shutdownTask = nil
            }
        } else {
            clearPlayback(); engine?.pause(); deactivateSession()
        }
    }

    private func deactivateSession() {
        sessionLifecycle?.request(false)
    }

    private static func sessionWork(_ operation: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do { try operation(); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func activateAudioSession() async throws {
        // Configure mixing before graph creation, including on muted-first launches.
        try await sessionWork { try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default) }
        if #available(iOS 27.0, *) {
            guard try await AVAudioSession.sharedInstance().activate() else {
                throw NSError(domain: "leqra.AudioSession", code: 1)
            }
        } else {
            try await sessionWork { try AVAudioSession.sharedInstance().setActive(true) }
        }
    }

    private static func deactivateAudioSession() async {
        if #available(iOS 27.0, *) {
            _ = try? await AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation)
        } else {
            try? await sessionWork {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
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
        guard enabled, volume > 0, !interrupted else { return }
        previewTask?.cancel()
        shutdownTask?.cancel(); shutdownTask = nil
        pendingPreview = cue; previewActive = true
        activatePlayback()
        if active { playPendingPreview() }
    }

    private func playPendingPreview() {
        guard active, let cue = pendingPreview else { return }
        pendingPreview = nil
        play(cue)
        guard !requestedActive else { previewActive = false; return }
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
