# CLAUDE.md

iOS app template: SwiftUI app in `Sources/MyApp`, platform-independent logic
and tests in the `Core/` package. Built by xtool on Linux and by Xcode (via
XcodeGen) on macOS. See README.md for setup.

## Commands

- `make test`: Core tests (Swift Testing). Works everywhere, no iOS SDK needed.
- `make lint` / `make format`: swift-format with `.swift-format`.
- `make build`: full iOS build. Needs an iOS SDK on Linux; check `make doctor` first.
- `make doctor`: what this machine can do. In cloud sessions the session-start
  hook prints it; if it says `ios-sdk none`, do not try `make build`.

Before committing: `make format`, then `make lint test`, and `make build` when
the SDK is available.

## Code rules

- Swift 6 language mode. The app target defaults to `MainActor` isolation
  (`.defaultIsolation(MainActor.self)` in Package.swift,
  `SWIFT_DEFAULT_ACTOR_ISOLATION` in project.yml); keep both in sync.
- Put logic in `Core/` with tests in `Core/Tests`. `Core` must not import
  SwiftUI, UIKit or other Apple-only frameworks, so it keeps building on Linux.
- The app layer stays thin: views plus `@Observable` models that wrap Core types.
- Deployment target is iOS 18; no `#available` checks below that.
- Load assets with `bundle: .assets` (`Image("x", bundle: .assets)`); the plain
  initializers miss xtool's resource bundle.
- New files under `Sources/MyApp` need no project changes: Package.swift and
  project.yml both take the whole directory. Add dependencies to both
  Package.swift (xtool) and project.yml (Xcode).
- Info.plist keys go in `Info.plist`, which both builds read. Use literal
  values; xtool does not expand `$(VARIABLES)`.
- The app's bundle ID appears in `xtool.yml` and `project.yml`; use
  `make rename` to change it or the app name.

## Environment notes

- Linux toolchain: Swift via swiftly (`.swift-version`), omarchy-apple-dev at
  the revision in `scripts/versions.env`. `. scripts/env.sh` puts it on PATH;
  Makefile targets do this already.
- The iOS SDK cannot be downloaded without an Apple ID. Never try to fetch
  Xcode from Apple; ask the user to set `APPLE_SDK_URL` (README, "Claude Code cloud").
- There is no simulator or device in cloud sessions: verify with `make test`
  and `make build`, not by running the app.
