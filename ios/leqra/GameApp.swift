import AVFoundation
import SwiftUI
import UIKit

@main
struct GameApp: App {
    @StateObject private var session: GameSession
    init() {
        // Establish the app-wide mixing policy before SpriteKit or an audio
        // graph can implicitly activate the default exclusive session.
        // Setting the category does not activate audio on a muted launch.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        _session = StateObject(wrappedValue: GameSession())
    }
    var body: some Scene {
        WindowGroup("leqra") {
            ContentView(session: session).preferredColorScheme(.dark)
                #if targetEnvironment(macCatalyst)
                    .background(MacWindowConfiguration())
                #endif
        }
        #if targetEnvironment(macCatalyst)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandGroup(replacing: .appSettings) {
                    Button("Controls…") { session.openDesktopControls() }
                    .keyboardShortcut(",", modifiers: .command)
                }
                CommandMenu("Game") {
                    Button(session.paused ? "Resume Game" : "Pause Game") {
                        session.toggleDesktopPause()
                    }.keyboardShortcut("p", modifiers: [])
                    .disabled(session.screen != .playing || session.hasModal)
                    Button(session.soundEnabled ? "Mute Sound" : "Unmute Sound") {
                        session.toggleDesktopSound()
                    }.keyboardShortcut("m", modifiers: [])
                    .disabled(session.screen != .playing || session.hasModal)
                    Divider()
                    Button("Controls…") { session.openDesktopControls() }
                    Button("Close Panel / Resume") { session.handleDesktopEscape() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(!session.hasModal && !session.paused && !session.showShowcase)
                }
            }
        #endif
    }
}

#if targetEnvironment(macCatalyst)
    private struct MacWindowConfiguration: UIViewRepresentable {
        func makeUIView(context: Context) -> WindowConfigurationView { WindowConfigurationView() }
        func updateUIView(_ view: WindowConfigurationView, context: Context) { view.configureWindow() }

        final class WindowConfigurationView: UIView {
            override init(frame: CGRect) {
                super.init(frame: frame)
                isUserInteractionEnabled = false
            }
            required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
            override func didMoveToWindow() {
                super.didMoveToWindow()
                configureWindow()
            }
            func configureWindow() {
                guard let scene = window?.windowScene else { return }
                scene.title = "leqra"
                scene.titlebar?.titleVisibility = .visible
                scene.sizeRestrictions?.minimumSize = CGSize(width: 720, height: 480)
                scene.sizeRestrictions?.maximumSize = CGSize(
                    width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                scene.sizeRestrictions?.allowsFullScreen = true
            }
        }
    }
#endif
