// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pookie",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pookie",
            path: "Sources/Pookie",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
