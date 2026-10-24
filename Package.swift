// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pookie",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Pookie",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Pookie",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                // SwiftPM places Sparkle beside bare executables; app bundles
                // embed it in Frameworks. Neither path depends on a checkout.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                              "-Xlinker", "-rpath", "-Xlinker", "@executable_path"])
            ]
        ),
        .testTarget(name: "PookieTests", dependencies: ["Pookie"])
    ]
)
