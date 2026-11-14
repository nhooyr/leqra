import UIKit
import AVFoundation
import SwiftUI
import leqraCore

/// Two disposable simulator apps use the production GameAudio class and an
/// independent background player. No personal media or app preferences are used.
@main
struct AudioMixingFixtureApp: App {
    @UIApplicationDelegateAdaptor(AudioMixingFixture.self) private var delegate
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            Color.black.onChange(of: phase) { value in
                if value != .active { delegate.deactivate() }
            }
        }
    }
}

final class AudioMixingFixture: UIResponder, UIApplicationDelegate {
    private var player: AVAudioPlayer?
    private var audio: GameAudio?
    private var timer: Timer?
    private var interruptions = 0
    private var observer: NSObjectProtocol?
    private var starStarted: TimeInterval?
    private var starPaused = false
    private var starResumed = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        do {
            if arguments.contains("--sentinel") {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback)
                try session.setActive(true)
                observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notice in
                    if notice.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue {
                        self?.interruptions += 1
                    }
                }
                try startPlayer()
            } else if arguments.contains("--exclusive") {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback)
                try session.setActive(true)
                try startPlayer()
            } else {
                audio = GameAudio()
                audio?.enabled = !arguments.contains("--muted")
                if arguments.contains("--zero-volume") { audio?.volume = 0 }
                if arguments.contains("--game") { audio?.resume(); audio?.preview(.regular) }
                if arguments.contains("--starman") { starStarted = ProcessInfo.processInfo.systemUptime; updateStarman() }
            }
            writeStatus()
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.updateStarman(); self?.writeStatus() }
        } catch {
            writeStatus(error: String(describing: error))
        }
        return true
    }

    private func startPlayer() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000 * 120)!
        buffer.frameLength = buffer.frameCapacity
        for frame in 0..<Int(buffer.frameLength) {
            buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 2 * .pi * 220 / 48_000) * 0.002)
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("background.caf")
        let output = try AVAudioFile(forWriting: file, settings: format.settings)
        try output.write(from: buffer)
        player = try AVAudioPlayer(contentsOf: file)
        player?.numberOfLoops = -1
        player?.play()
    }

    func applicationWillResignActive(_ application: UIApplication) { audio?.pause(fadeLoop: false) }
    func deactivate() { audio?.pause(fadeLoop: false) }

    private func updateStarman() {
        guard let started = starStarted else { return }
        let arguments = ProcessInfo.processInfo.arguments, elapsed = ProcessInfo.processInfo.systemUptime - started
        if elapsed >= 0.5, !starPaused, arguments.contains("--pause-star") || arguments.contains("--resume-star") {
            starPaused = true; audio?.pause()
        }
        if elapsed >= 1.1, starPaused, !starResumed, arguments.contains("--resume-star") {
            starResumed = true; audio?.resume()
        }
        if starPaused && !starResumed { return }
        let secondary = arguments.contains("--second-star"), remote = arguments.contains("--remote-star")
        let expired = arguments.contains("--expire-star") && elapsed >= 0.5
        let dead = arguments.contains("--dead-star") && elapsed >= 0.5
        let power = expired ? 0 : max(0, 15 - elapsed)
        let state = ArenaSnapshot(tick: UInt64(elapsed * 60), tanks: [
            ArenaTank(id: 1, hp: dead ? 0 : 1, starmanTime: secondary || remote ? 0 : power),
            ArenaTank(id: secondary ? 2 : 3, bot: remote, starmanTime: secondary || remote ? power : 0)])
        audio?.consume(snapshot: state, localID: 1, infinity: true, online: false,
                       secondaryLocalID: secondary ? 2 : nil, gameplayActive: !starPaused || starResumed)
    }

    private func writeStatus(error: String? = nil) {
        var status: [String: Any] = ["playing": player?.isPlaying ?? false,
            "time": player?.currentTime ?? 0, "interruptions": interruptions,
            "category": AVAudioSession.sharedInstance().category.rawValue,
            "mixes": AVAudioSession.sharedInstance().category == .ambient || AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers)]
        status["error"] = error
        if let audio {
            status["starman"] = Mirror(reflecting: audio).children.first(where: { $0.label == "starmanRequested" })?.value as? Bool ?? false
        }
        let file = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/status.json")
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: status) { try? data.write(to: file, options: .atomic) }
    }
}
