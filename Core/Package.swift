// swift-tools-version: 6.2

import PackageDescription

// Platform-independent app logic: no SwiftUI or UIKit here, so it builds and
// tests anywhere Swift runs (`make test`), including Linux without an iOS SDK.
let package = Package(
    name: "MyAppCore",
    platforms: [
        .iOS(.v26),
        // Lower than the app so `make test` runs on any Mac that runs Xcode 26.
        .macOS(.v15),
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
