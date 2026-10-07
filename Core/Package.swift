// swift-tools-version: 6.4

import PackageDescription

// Platform-independent app logic: no SwiftUI or UIKit here, so it builds and
// tests anywhere Swift runs (`make test`), including Linux without an iOS SDK.
let package = Package(
    name: "MyAppCore",
    platforms: [
        .iOS(.v27),
        // So `make test` also runs on a Mac still on macOS 26 with Xcode 27.
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "MyAppCore",
            targets: ["MyAppCore"]
        )
    ],
    targets: [
        .target(name: "MyAppCore"),
        .testTarget(
            name: "MyAppCoreTests",
            dependencies: ["MyAppCore"]
        ),
    ]
)
