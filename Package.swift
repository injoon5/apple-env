// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [
        .iOS(.v27),
        .macOS(.v27),
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
            // Icon Composer icon: Xcode compiles it from project.yml, and on
            // Linux `make ship` compiles it into the App Store build.
            exclude: ["AppIcon.icon"],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
