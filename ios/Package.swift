// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "leqraCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "leqraCore", targets: ["leqraCore"])],
    targets: [
        .target(name: "leqraCore", plugins: [.plugin(name: "VersionPlugin")]),
        .target(name: "leqraAccountStore", dependencies: ["leqraCore"], path: "leqra",
                exclude: ["Assets.xcassets", "Info.plist", "PrivacyInfo.xcprivacy", "ContentView.swift", "FrameProfiler.swift",
                          "GameApp.swift", "GameAudio.swift", "GameChrome.swift", "GameDialogs.swift", "GameScene.swift",
                          "GameSession.swift", "NativeGameView.swift", "ReadyRoomView.swift", "WebStyle.swift"],
                sources: ["PublicInfinitySessionStore.swift"]),
        .testTarget(name: "leqraCoreTests", dependencies: ["leqraCore", "leqraAccountStore"]),
        .plugin(name: "VersionPlugin", capability: .buildTool())
    ]
)
