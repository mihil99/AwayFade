// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AwayFade",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AwayFade", targets: ["AwayFade"])
    ],
    targets: [
        .target(
            name: "AwayFadeCore",
            path: "Sources/AwayFadeCore"
        ),
        .executableTarget(
            name: "AwayFade",
            dependencies: ["AwayFadeCore"],
            path: "Sources/AwayFade",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "AwayFadeCoreTests",
            dependencies: ["AwayFadeCore"],
            path: "Tests/AwayFadeCoreTests"
        )
    ]
)
