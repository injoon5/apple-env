# apple-env

A forkable iOS app template that builds on macOS with Xcode, on Linux with
[xtool](https://github.com/xtool-org/xtool), and in Claude Code cloud sessions.
The Linux toolchain is [omarchy-apple-dev](https://github.com/joshuaswarren/omarchy-apple-dev),
pinned and installed for you on Ubuntu, Debian and Arch (Omarchy).

| | Version |
|---|---|
| Swift | 6.4.0 (`.swift-version`) |
| iOS SDK | Xcode 27 (iOS 27 SDK) |
| Deployment target | iOS 18 |
| Tests | Swift Testing |
| Concurrency | Swift 6 language mode, `MainActor` by default in the app target |

## Start a new app

1. Fork this repository (or **Use this template**), then clone it.
2. Rename the app and set your bundle ID:

   ```sh
   make rename NAME=Notes BUNDLE_ID=com.you.notes
   ```

3. Install the toolchain and check the result:

   ```sh
   make setup
   make test
   ```

`make` lists every task. `make doctor` shows what the current machine can do.

## What runs where

| | Test and lint | Build the app | Run | Ship to TestFlight |
|---|---|---|---|---|
| macOS + Xcode | ✓ | ✓ | Simulator, iPhone (Xcode) | Xcode Archive |
| Linux (Ubuntu, Debian, Arch) | ✓ | ✓ with the iOS SDK | iPhone over USB | `make upload` |
| Claude Code cloud | ✓ | ✓ with `APPLE_SDK_URL` | – | `make upload` with keys |
| GitHub Actions | ✓ | ✓ (macOS job) | – | – |

There is no iOS Simulator on Linux. App logic lives in `Core/`, a plain Swift
package that builds and tests anywhere, so most work can be verified without
an iOS SDK.

## Layout

```
Core/                     App logic and its tests (no UIKit or SwiftUI)
Sources/MyApp/            SwiftUI app: views, observable models, Resources/Assets.xcassets
Package.swift, xtool.yml  The app for xtool (Linux)
project.yml, Config/      The app for Xcode, generated with XcodeGen (macOS)
Info.plist                Shared by both builds; version number lives here
scripts/                  setup, SDK, rename and doctor scripts
.claude/                  Session hook that sets up Claude Code cloud sessions
```

Both builds compile the same `Sources/MyApp`. Load images and colors with
`bundle: .assets` (see `Bundle+Assets.swift`) so they resolve in both.

## macOS

Install Xcode 27 from the App Store and open it once. Then:

```sh
make setup      # checks Xcode, installs XcodeGen with Homebrew
make xcode      # generates MyApp.xcodeproj and opens it
```

Run with Cmd-R on a simulator or your iPhone. To keep your signing team across
regenerations, put it in `Config/Local.xcconfig` (see the `.example` file), or
run `DEVELOPMENT_TEAM=ABCDE12345 make xcode` once. The `.xcodeproj` is
generated, so change targets and settings in `project.yml`.

## Linux

```sh
make setup
```

This installs Swift with [swiftly](https://www.swift.org/install/linux/) (Arch:
AUR `swift-bin`), which is enough for `make test` and `make lint`. iOS builds
also need Apple's iOS SDK, which only ships inside Xcode:

1. Download Xcode 27 (`.xip`) from https://developer.apple.com/download/all/?q=Xcode
   with a free Apple ID. No Mac needed.
2. Run `XCODE_XIP=~/Downloads/Xcode_27.xip make setup`.

The first iOS setup builds xtool and its helpers from source (10 to 25
minutes) and needs `sudo` for system packages. After that:

```sh
make build                # xtool/MyApp.app
xtool auth                # once: sign in with your Apple ID
make run                  # install and launch on a USB-connected iPhone
```

For LLDB and wireless deploys, see `device-run.sh` in
`~/.local/share/apple-env/omarchy-apple-dev`.

## Claude Code cloud

`.claude/settings.json` runs `.claude/hooks/session-start.sh` when a cloud
session starts. It installs Swift, puts it on `PATH` and reports what the
session can do. With no further setup, Claude can edit the app and run
`make test` and `make lint`.

For full iOS builds in the cloud, give the session an iOS SDK. The quickest
source is an archive of the SDK you already installed on Linux:

1. On your Linux machine, after `make setup` with Xcode: `make sdk-pack`.
   This writes `darwin-iPhoneOS27.0.xtoolsdk.tar.zst` and prints its SHA-256.
2. Upload it to private storage that gives you a download URL, for example a
   presigned S3, R2 or GCS URL, or a private GitHub release asset.
3. In the cloud environment settings, add the environment variables:
   - `APPLE_SDK_URL`: the download URL (an Xcode `.xip` URL also works)
   - `APPLE_SDK_SHA256`: optional checksum
   - `APPLE_SDK_TOKEN`: optional Bearer token, for example a fine-grained
     GitHub token when the URL is `https://api.github.com/repos/OWNER/REPO/releases/assets/ID`

The first session after that downloads the SDK and builds xtool, which takes
up to an hour; the hook allows that. Later sessions reuse the environment
cache and start in seconds. The environment's network access must allow
`download.swift.org`, `github.com` and your SDK host.

The SDK is Apple software under the Xcode license. Keep it private; never
commit it or publish the URL.

## TestFlight from Linux

Once: create an App Store Connect API key (Users and Access > Integrations,
role App Manager), download the `.p8`, and create the app record with your
bundle ID (Apps > New App). Then:

```sh
make ship    # build, sign with a test identity, validate offline
ASC_KEY_PATH=~/keys/AuthKey_XXXXXXXXXX.p8 ASC_ISSUER_ID=<issuer> ASC_KEY_ID=XXXXXXXXXX make upload
```

`make upload` creates your distribution certificate and profile on first use,
uploads the build and prints Apple's processing result. It never submits for
review. The app icon comes from `AppIcon` in `Assets.xcassets`; replace
`AppIcon.png` (1024x1024, no transparency).

## Updating versions

- Swift: edit `.swift-version`, then `make setup`. On Linux the SDK must come
  from the Xcode with the same Swift (Swift 6.4 = Xcode 27).
- Linux toolchain: bump `OMARCHY_APPLE_DEV_REV` (and the libimobiledevice
  tags) in `scripts/versions.env`, then `make setup`.
- App version: `CFBundleShortVersionString` in `Info.plist`. Builds from
  `make ship` get a UTC timestamp build number.

## Troubleshooting

- `make doctor` first.
- Linux setup logs: `~/.local/share/apple-env/state/install-toolchain.log`.
  Cloud sessions also write `/tmp/apple-env-bootstrap.log`.
- After changing the SDK or Swift version, `make clean` before building.
- The omarchy-apple-dev [FINDINGS.md](https://github.com/joshuaswarren/omarchy-apple-dev/blob/main/FINDINGS.md)
  lists most Linux build errors with their causes.
