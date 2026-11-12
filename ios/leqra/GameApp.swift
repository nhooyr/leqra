import SwiftUI

@main
struct GameApp: App {
    @StateObject private var session = GameSession()
    var body: some Scene {
        WindowGroup { ContentView(session: session).preferredColorScheme(.dark) }
    }
}
