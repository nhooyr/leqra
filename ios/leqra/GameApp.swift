import SwiftUI
import AVFoundation

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
        WindowGroup { ContentView(session: session).preferredColorScheme(.dark) }
    }
}
