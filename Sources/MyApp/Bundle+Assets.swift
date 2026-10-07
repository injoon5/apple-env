import Foundation

extension Bundle {
    /// Where `Assets.xcassets` ends up: SwiftPM's resource bundle when xtool builds
    /// the app, the app bundle itself when Xcode does. Pass it to `Image(_:bundle:)`
    /// and `Color(_:bundle:)` so assets load in both builds.
    static var assets: Bundle {
        #if SWIFT_PACKAGE
            .module
        #else
            .main
        #endif
    }
}
