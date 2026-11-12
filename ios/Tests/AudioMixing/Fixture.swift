import UIKit
import AVFoundation
import SwiftUI

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
            }
            writeStatus()
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.writeStatus() }
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

    func applicationWillResignActive(_ application: UIApplication) { audio?.pause() }
    func deactivate() { audio?.pause() }

    private func writeStatus(error: String? = nil) {
        var status: [String: Any] = ["playing": player?.isPlaying ?? false,
            "time": player?.currentTime ?? 0, "interruptions": interruptions,
            "category": AVAudioSession.sharedInstance().category.rawValue,
            "mixes": AVAudioSession.sharedInstance().category == .ambient || AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers)]
        status["error"] = error
        let file = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/status.json")
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: status) { try? data.write(to: file, options: .atomic) }
    }
}
