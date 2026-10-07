// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        // xtool builds the app from the package's single library product.
        .library(
            name: "MyApp",
            targets: ["MyApp"]
        )
    ],
    dependencies: [
        // App logic lives in Core/, a plain Swift package that also builds and
        // tests on Linux without an iOS SDK.
        .package(path: "Core")
    ],
    targets: [
        .target(
            name: "MyApp",
            dependencies: [
                .product(name: "MyAppCore", package: "Core")
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
