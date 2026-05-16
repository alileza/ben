// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Ben",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Ben",
            path: "Sources/Ben",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        )
    ]
)
