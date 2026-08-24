// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DroidDrive",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DroidDrive",
            path: "Sources/DroidDrive",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
