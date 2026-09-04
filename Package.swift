// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DMC",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "DMC",
            path: "Sources/DMC",
            // .v5 language mode on purpose: AppKit/WebKit delegates and AVAudioEngine
            // render callbacks are pervasively non-Sendable, and strict v6 checking buys
            // nothing for a single-window local tool.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
