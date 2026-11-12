// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "leqraCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "leqraCore", targets: ["leqraCore"])],
    targets: [
        .target(name: "leqraCore", plugins: [.plugin(name: "VersionPlugin")]),
        .testTarget(name: "leqraCoreTests", dependencies: ["leqraCore"]),
        .plugin(name: "VersionPlugin", capability: .buildTool())
    ]
)
