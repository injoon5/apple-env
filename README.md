# apple-env

A forkable iOS app template that builds on macOS with Xcode, on Linux with
[xtool](https://github.com/xtool-org/xtool), and in Claude Code cloud sessions.
The Linux toolchain is [omarchy-apple-dev](https://github.com/joshuaswarren/omarchy-apple-dev),
pinned and installed for you on Ubuntu, Debian and Arch (Omarchy).

| | Version |
|---|---|
| Swift | 6.4.0 (`.swift-version`) |
| iOS SDK | Xcode 27 (iOS 27 SDK) |
| Deployment target | iOS 27, no older versions |
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
| Claude Code cloud | ✓ | ✓ with the iOS SDK | – | `make upload` with keys |
| GitHub Actions | ✓ | ✓ (macOS job) | – | – |

There is no iOS Simulator on Linux. App logic lives in `Core/`, a plain Swift
package that builds and tests anywhere, so most work can be verified without
an iOS SDK.

## Layout

```
Core/                     App logic and its tests (no UIKit or SwiftUI)
Sources/MyApp/            SwiftUI app: views, models, AppIcon.icon, Resources/Assets.xcassets
Package.swift, xtool.yml  The app for xtool (Linux)
project.yml, Config/      The app for Xcode, generated with XcodeGen (macOS)
Info.plist                Shared by both builds; version number lives here
scripts/                  setup, SDK, rename and doctor scripts
.claude/                  Session hook that sets up Claude Code cloud sessions
```

Both builds compile the same `Sources/MyApp`. Load images and colors with
`bundle: .assets` (see `Bundle+Assets.swift`) so they resolve in both.

## macOS

Install Xcode 27 from the App Store (required: the manifests use
`swift-tools-version: 6.4`) and open it once. Then:

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
also need the iOS SDK (next section). With it, the first setup builds xtool
and its helpers from source (about 10 minutes) and needs `sudo` for system
packages. After that:

```sh
make build                # xtool/MyApp.app
xtool auth                # once: sign in with your Apple ID
make run                  # install and launch on a USB-connected iPhone
```

For LLDB and wireless deploys, see `device-run.sh` in
`~/.local/share/apple-env/omarchy-apple-dev`.

## iOS SDK

Linux builds need Apple's iOS SDK, which ships only inside Xcode. It must come
from the Xcode whose Swift matches `.swift-version` (Swift 6.4 = Xcode 27).
`make setup` takes it from any of these.

**A. GitHub Actions (recommended; no Apple download, works for cloud sessions)**

GitHub's macOS runners have Xcode installed. The **iOS SDK** workflow packs the
SDK files from it (about 3 GB before compression), encrypts them, and stores
them as the `darwin-sdk` artifact of your repository.

1. Create a passphrase, for example with `openssl rand -base64 32`.
2. Add it as the repository secret `APPLE_SDK_PASSPHRASE`
   (Settings > Secrets and variables > Actions).
3. Run the workflow: Actions > iOS SDK > Run workflow. It refreshes itself
   monthly, because artifacts expire after 90 days.
4. Give the same passphrase to every machine that builds:
   - Claude Code cloud: add the environment variable `APPLE_SDK_PASSPHRASE` in
     the cloud environment settings. Sessions reach the artifact through the
     session's GitHub access.
   - Your Linux machine: `APPLE_SDK_PASSPHRASE=... make setup`. It downloads the
     artifact with the `gh` CLI login, or `APPLE_SDK_TOKEN` (a token with
     Actions read access).

The archive is encrypted because artifacts of public repositories can be
downloaded by any signed-in GitHub user. Without the passphrase they are
useless; never commit the passphrase. If the runner lacks the matching Xcode,
the workflow lists the Xcodes it found; pick another runner label when you run it.

**B. Xcode download (Linux machine)**

Download Xcode 27 (`.xip`) from https://developer.apple.com/download/all/?q=Xcode
with a free Apple ID, then run `XCODE_XIP=~/Downloads/Xcode_27.xip make setup`.

**C. Your own storage**

`make sdk-pack` writes an archive of the SDK: on macOS from your Xcode, on Linux
from the installed SDK. It is encrypted when `APPLE_SDK_PASSPHRASE` is set.
Upload it anywhere that gives a download URL and set `APPLE_SDK_URL` (plus
`APPLE_SDK_PASSPHRASE`, and optionally `APPLE_SDK_SHA256` and `APPLE_SDK_TOKEN`
for a Bearer token). An Xcode `.xip` URL works too.

The SDK is Apple software under the Xcode license. Keep it private or
encrypted, and note that Apple's license limits Xcode to Apple hardware.

## Claude Code cloud

`.claude/settings.json` runs `.claude/hooks/session-start.sh` when a cloud
session starts. It installs Swift, puts it on `PATH` and reports what the
session can do. With no further setup, Claude can edit the app and run
`make test` and `make lint`.

With an iOS SDK source (option A or C above), the first session also builds
xtool and installs the SDK, which takes 15 to 30 minutes; the hook allows up
to an hour. Later sessions reuse the environment cache and start in seconds.
The environment's network access must allow `download.swift.org` and
`github.com` (plus your SDK host for option C).

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
review.

## App icon

`Sources/MyApp/AppIcon.icon` is an Icon Composer icon: `icon.json` plus layer
images in `Assets/` (SVG or PNG). Edit it in Icon Composer (macOS, comes with
Xcode), or by hand. Xcode compiles it, and on Linux `make ship`
compiles it with the omarchy-apple-dev `actool` into the layered Liquid Glass
icon with its light, dark and tinted appearances. Linux debug builds (`make build`, `make run`) do not
include the icon; App Store builds do.

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
