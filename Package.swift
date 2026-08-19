// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SessionReplaySDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SessionReplaySDK",
            targets: ["SessionReplaySDK"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SessionReplaySDK",
            dependencies: [],
            path: "Sources/SessionReplaySDK"
        ),
        .testTarget(
            name: "SessionReplaySDKTests",
            dependencies: ["SessionReplaySDK"],
            path: "Tests/SessionReplaySDKTests"
        )
    ]
)
