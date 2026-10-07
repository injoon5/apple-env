#!/usr/bin/env bash
# Set up everything this project needs, on macOS, Ubuntu/Debian or Arch (Omarchy).
#
#   scripts/bootstrap.sh          auto: full iOS toolchain when an iOS SDK source is
#                                 available, otherwise Swift only (tests and lint)
#   scripts/bootstrap.sh --core   Swift toolchain only
#   scripts/bootstrap.sh --ios    full iOS toolchain
#
# macOS uses Xcode and installs XcodeGen with Homebrew. Linux installs
# Swift with swiftly (Arch: AUR swift-bin), then the pinned omarchy-apple-dev
# toolchain: xtool, the darwin SDK, Linux stand-ins for actool/ibtool/momc,
# rcodesign and pymobiledevice3. Its SDK comes from the first of:
#   - a darwin SDK already registered (`swift sdk list`)
#   - an SDK cached in ~/.cache/xtool by an earlier install
#   - XCODE_XIP=/path/to/Xcode_27.xip (download it once from Apple)
#   - APPLE_SDK_URL=<private URL of an Xcode .xip or of a `scripts/sdk.sh pack` archive>
#   - APPLE_SDK_PASSPHRASE=<secret>: the encrypted artifact of this repository's
#     "iOS SDK" workflow, which packs the SDK on a GitHub macOS runner
# Safe to re-run: finished steps are skipped.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=versions.env
. "$ROOT/scripts/versions.env"
. "$ROOT/scripts/env.sh"

SWIFT_VERSION="$(tr -d '[:space:]' <"$ROOT/.swift-version")"
LIMD_PREFIX="$APPLE_ENV_HOME/libimobiledevice"
STATE_DIR="$APPLE_ENV_HOME/state"
SDK_CACHE="${SDK_CACHE:-$HOME/.cache/xtool}"
# Where `sdk.sh fetch` stages Xcode SDK pieces; install-toolchain.sh builds from it.
export SDK_SRC="${SDK_SRC:-$HOME/xcode-apple-sdk-src}"

log() { printf '\033[1m==> %s\033[0m\n' "$*" >&2; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }
as_root() {
  if [ "$(id -u)" = 0 ]; then
    "$@"
  elif have sudo; then
    sudo "$@"
  else
    die "need root for: $* (install sudo or run as root)"
  fi
}

detect_os() {
  if [ "$(uname -s)" = Darwin ]; then
    echo macos
    return
  fi
  local id="" like=""
  if [ -r /etc/os-release ]; then
    id=$(. /etc/os-release && echo "${ID:-}")
    like=$(. /etc/os-release && echo "${ID_LIKE:-}")
  fi
  case " $id $like " in
    *" arch "*) echo arch ;;
    *" debian "* | *" ubuntu "*) echo debian ;;
    *) echo linux ;;
  esac
}

# --- macOS -------------------------------------------------------------------

setup_macos() {
  [ "$(id -u)" != 0 ] || die "run make setup without sudo: Homebrew refuses root, and files would end up owned by root.
It asks for your password itself when it needs it."
  local dev match
  dev=$(xcode-select -p 2>/dev/null || true)
  match=$("$ROOT/scripts/sdk.sh" xcode 2>/dev/null || true)
  case "$dev" in
    *.app/Contents/Developer) ;;
    *)
      if [ -n "$match" ]; then
        die "Xcode is installed but not selected (xcode-select -p: ${dev:-none}). Run:
  sudo xcode-select -s $match
  sudo xcodebuild -license accept
then make setup again."
      fi
      die "Xcode is not selected (xcode-select -p: ${dev:-none}).
Install Xcode $XCODE_MAJOR from the App Store, open it once, then run:
  sudo xcode-select -s /Applications/Xcode.app"
      ;;
  esac
  xcodebuild -license check >/dev/null 2>&1 ||
    die "the Xcode license is not accepted yet. Run: sudo xcodebuild -license accept"
  xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 ||
    die "Xcode has not finished its first launch. Run: sudo xcodebuild -runFirstLaunch"
  xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1 ||
    die "Xcode has no iOS SDK. Open Xcode > Settings > Components, or run: xcodebuild -downloadPlatform iOS"
  log "Xcode: $(xcodebuild -version | tr '\n' ' ')"
  local sv want
  sv=$(swift --version 2>/dev/null | grep -oE 'Swift version [0-9]+\.[0-9]+' | head -n1 | awk '{print $3}')
  want=$(cut -d. -f1-2 <<<"$SWIFT_VERSION")
  [ "$sv" = "$want" ] ||
    die "the selected Xcode has Swift ${sv:-?}; this project needs Swift $want (Xcode $XCODE_MAJOR).
${match:+It is installed: sudo xcode-select -s $match}"
  log "Swift $sv"
  # XcodeGen 2.45.1 added Icon Composer (.icon) support.
  local xg
  xg=$(xcodegen --version 2>/dev/null | sed 's/^Version: //')
  if [ -z "$xg" ] || [ "$(printf '%s\n' 2.45.1 "$xg" | sort -V | head -n1)" != 2.45.1 ]; then
    have brew || die "XcodeGen 2.45.1 or later is needed. Install Homebrew (https://brew.sh) and re-run, or see https://github.com/yonaskolb/XcodeGen#installing"
    log "Installing XcodeGen (Homebrew)"
    if [ -n "$xg" ]; then brew upgrade xcodegen; else brew install xcodegen; fi
  fi
  log "XcodeGen $(xcodegen --version 2>/dev/null | sed 's/^Version: //')"
}

# --- Linux: Swift ------------------------------------------------------------

apt_updated=0
# Container images often ship without package lists; apt-get install then
# cannot locate anything.
apt_update() {
  [ "$apt_updated" = 0 ] || return 0
  as_root apt-get update -qq
  apt_updated=1
}
apt_install() {
  local missing=() pkg
  for pkg in "$@"; do
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" || missing+=("$pkg")
  done
  [ ${#missing[@]} -eq 0 ] && return 0
  apt_update
  log "apt: ${missing[*]}"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}" >/dev/null
}

install_swift_swiftly() {
  export SWIFTLY_HOME_DIR="${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}"
  export SWIFTLY_BIN_DIR="${SWIFTLY_BIN_DIR:-$SWIFTLY_HOME_DIR/bin}"
  if [ ! -x "$SWIFTLY_BIN_DIR/swiftly" ]; then
    log "Installing swiftly"
    local tmp init_args=(--assume-yes --quiet-shell-followup --skip-install)
    tmp=$(mktemp -d)
    curl -fsSL --retry 3 "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz" | tar -xz -C "$tmp"
    # Ephemeral machines (CI, cloud sessions) get PATH from scripts/env.sh instead.
    if [ -n "${CI:-}" ] || [ "${CLAUDE_CODE_REMOTE:-}" = true ]; then init_args+=(--no-modify-profile); fi
    "$tmp/swiftly" init "${init_args[@]}" >/dev/null
    rm -rf "$tmp"
  fi
  . "$SWIFTLY_HOME_DIR/env.sh"
  hash -r
  # The system packages swiftly asks for. The file stays until they are
  # installed, so a re-run retries them even though Swift itself is in place.
  local post="$STATE_DIR/swift-post-install.sh"
  mkdir -p "$STATE_DIR"
  if [ ! -x "$SWIFTLY_HOME_DIR/toolchains/$SWIFT_VERSION/usr/bin/swift" ]; then
    log "Installing Swift $SWIFT_VERSION (about 1 GB)"
    # From $HOME so swiftly does not rewrite this project's .swift-version.
    (cd "$HOME" && swiftly install "$SWIFT_VERSION" --assume-yes --post-install-file "$post" >/dev/null)
  fi
  if [ -s "$post" ]; then
    log "Swift system dependencies"
    [ "$OS" = debian ] && apt_update
    as_root bash "$post"
  fi
  rm -f "$post"
  # Become the global default only when there is none yet.
  (cd "$HOME" && swiftly use --print-location >/dev/null 2>&1) ||
    (cd "$HOME" && swiftly use --global-default "$SWIFT_VERSION" --assume-yes >/dev/null)
}

setup_linux_core() {
  case "$OS" in
    debian)
      apt_install ca-certificates curl git gnupg make
      install_swift_swiftly
      ;;
    arch)
      have yay || die "yay is required for AUR swift-bin (Omarchy ships it)"
      as_root pacman -S --needed --noconfirm git base-devel
      yay -S --needed --noconfirm swift-bin
      ;;
    *)
      # swiftly supports Fedora, RHEL/UBI and Amazon Linux, and prints the
      # system packages it needs.
      install_swift_swiftly
      ;;
  esac
  . "$ROOT/scripts/env.sh"
  have swift || die "swift is not on PATH after install"
  log "$(swift --version 2>/dev/null | head -n1)"
}

# --- Linux: iOS toolchain ----------------------------------------------------

sdk_registered() { swift sdk list 2>/dev/null | grep -qw darwin; }
sdk_cached() { compgen -G "$SDK_CACHE/darwin-*.xtoolsdk" >/dev/null; }

# Build the libimobiledevice stack xtool links against into a private prefix.
build_limd() {
  local stamp="$LIMD_PREFIX/.revs"
  local want="$LIBPLIST_REV $LIBIMOBILEDEVICE_GLUE_REV $LIBUSBMUXD_REV $LIBTATSU_REV $LIBIMOBILEDEVICE_REV"
  if [ "$(cat "$stamp" 2>/dev/null)" = "$want" ]; then return 0; fi
  log "Building libimobiledevice $LIBIMOBILEDEVICE_REV into $LIMD_PREFIX (about 3 minutes)"
  local src="$HOME/.cache/apple-env/src" log="$STATE_DIR/libimobiledevice.log" repo rev extra
  rm -rf "$LIMD_PREFIX"
  mkdir -p "$src" "$STATE_DIR"
  : >"$log"
  export PKG_CONFIG_PATH="$LIMD_PREFIX/lib/pkgconfig"
  for spec in "libplist $LIBPLIST_REV --without-cython" \
    "libimobiledevice-glue $LIBIMOBILEDEVICE_GLUE_REV" \
    "libusbmuxd $LIBUSBMUXD_REV" \
    "libtatsu $LIBTATSU_REV" \
    "libimobiledevice $LIBIMOBILEDEVICE_REV --without-cython"; do
    read -r repo rev extra <<<"$spec"
    rm -rf "${src:?}/$repo"
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$rev" "https://github.com/libimobiledevice/$repo" "$src/$repo"
    (
      cd "$src/$repo"
      # Release tags have no .tarball-version; autogen derives it from git.
      ./autogen.sh --prefix="$LIMD_PREFIX" --disable-static $extra LDFLAGS="-Wl,-rpath,$LIMD_PREFIX/lib"
      make -j"$(nproc)"
      make install
    ) >>"$log" 2>&1 || {
      tail -n 30 "$log" >&2
      die "building $repo $rev failed; full log: $log"
    }
  done
  echo "$want" >"$stamp"
}

fetch_upstream() {
  if [ "$(git -C "$APPLE_ENV_UPSTREAM" rev-parse HEAD 2>/dev/null)" = "$OMARCHY_APPLE_DEV_REV" ]; then return 0; fi
  log "Fetching omarchy-apple-dev ${OMARCHY_APPLE_DEV_REV:0:12}"
  [ -d "$APPLE_ENV_UPSTREAM/.git" ] || git init -q "$APPLE_ENV_UPSTREAM"
  git -C "$APPLE_ENV_UPSTREAM" fetch -q --depth 1 "$OMARCHY_APPLE_DEV_REPO" "$OMARCHY_APPLE_DEV_REV"
  git -C "$APPLE_ENV_UPSTREAM" -c advice.detachedHead=false checkout -q --force FETCH_HEAD
}

# xtool links libimobiledevice at runtime. Put the private copies next to it
# (it is built with an $ORIGIN runpath), so it runs from any shell.
bundle_limd_into_xtool() {
  local xtool_dir lib
  xtool_dir=$(dirname "$(readlink -f "$HOME/.local/bin/xtool")")
  LD_LIBRARY_PATH="$LIMD_PREFIX/lib" ldd "$xtool_dir/xtool" | awk -v p="$LIMD_PREFIX/lib/" 'index($3, p) == 1 { print $3 }' |
    while read -r lib; do cp -fL "$lib" "$xtool_dir/"; done
}

ios_stamp() {
  local sdk
  sdk=$(find "$HOME/.swiftpm/swift-sdks/darwin.artifactbundle/Developer/Platforms/iPhoneOS.platform/Developer/SDKs" \
    -maxdepth 1 -name 'iPhoneOS[0-9]*.sdk' -printf '%f\n' 2>/dev/null | sort | tail -n1)
  echo "$OMARCHY_APPLE_DEV_REV swift-$SWIFT_VERSION ${sdk:-nosdk}"
}

sdk_source_available() {
  sdk_registered || sdk_cached || [ -d "$SDK_SRC/Xcode.app" ] || [ -n "${XCODE_XIP:-}" ] ||
    [ -n "${APPLE_SDK_URL:-}" ] || [ -n "${APPLE_SDK_PASSPHRASE:-}" ]
}

setup_linux_ios() {
  if [ -x "$HOME/.local/bin/xtool" ] && sdk_registered && [ "$(cat "$STATE_DIR/ios" 2>/dev/null)" = "$(ios_stamp)" ]; then
    log "iOS toolchain up to date ($(ios_stamp))"
    return 0
  fi

  case "$OS" in
    debian)
      apt_install build-essential autoconf automake libtool-bin pkg-config libssl-dev zlib1g-dev \
        liblzma-dev libcurl4-openssl-dev libxml2-dev zip unzip zstd openssl python3 python3-venv \
        usbmuxd poppler-utils libheif-examples librsvg2-bin
      build_limd
      ;;
    arch) ;;
    *) warn "untested distro: install the equivalents of the Debian packages in scripts/bootstrap.sh" ;;
  esac

  local fetched_xip="" staged=""
  if ! sdk_registered && ! sdk_cached && [ ! -d "$SDK_SRC/Xcode.app" ] && [ -z "${XCODE_XIP:-}" ] &&
    { [ -n "${APPLE_SDK_URL:-}" ] || [ -n "${APPLE_SDK_PASSPHRASE:-}" ]; }; then
    fetched_xip=$("$ROOT/scripts/sdk.sh" fetch)
    if [ -n "$fetched_xip" ]; then export XCODE_XIP="$fetched_xip"; fi
    [ -d "$SDK_SRC/Xcode.app" ] && staged=1
  fi
  fetch_upstream

  local args=(--user-only) out rc=0
  [ "$OS" = arch ] && args=()
  mkdir -p "$STATE_DIR"
  out="$STATE_DIR/install-toolchain.log"
  log "omarchy-apple-dev install-toolchain.sh ${args[*]} (first run builds xtool: 10-25 minutes; log: $out)"
  (
    export PKG_CONFIG_PATH="$LIMD_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export LD_LIBRARY_PATH="$LIMD_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    cd "$APPLE_ENV_UPSTREAM" && ./install-toolchain.sh "${args[@]}"
  ) >"$out" 2>&1 || rc=$?
  [ "$OS" = debian ] && [ -x "$HOME/.local/bin/xtool" ] && bundle_limd_into_xtool

  if [ "$rc" != 0 ]; then
    if ! grep -q "One download left" "$out"; then
      tail -n 30 "$out" >&2
      die "install-toolchain.sh failed (exit $rc); full log: $out"
    fi
    # Stopped at the SDK step: everything else is installed.
    if sdk_cached; then
      log "Registering the cached SDK"
      (cd "$APPLE_ENV_UPSTREAM" && ./install-toolchain.sh --repair) >>"$out" 2>&1 ||
        {
          tail -n 30 "$out" >&2
          die "install-toolchain.sh --repair failed; full log: $out"
        }
    else
      warn "xtool is installed, but there is no iOS SDK yet. Download Xcode $XCODE_MAJOR (.xip) from"
      warn "https://developer.apple.com/download/all/?q=Xcode and run: XCODE_XIP=/path/to/Xcode.xip make setup"
      warn "Or let GitHub Actions pack it: README, 'iOS SDK'."
      return 0
    fi
  fi
  # The SDK is now cached in ~/.cache/xtool; drop the downloaded sources.
  if [ -n "$fetched_xip" ]; then rm -f "$fetched_xip"; fi
  if [ -n "$staged" ]; then rm -rf "$SDK_SRC"; fi
  sdk_registered || die "the darwin SDK is still not registered; see $out"
  ios_stamp >"$STATE_DIR/ios"
  log "iOS toolchain ready ($(ios_stamp))"
}

# --- main --------------------------------------------------------------------

MODE=auto
case "${1:-}" in
  --core) MODE=core ;;
  --ios) MODE=ios ;;
  "" | --auto) ;;
  -h | --help)
    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *) die "unknown option: $1 (try --help)" ;;
esac

OS=$(detect_os)
if [ "$OS" = macos ]; then
  setup_macos
elif [ "$MODE" = core ]; then
  setup_linux_core
elif [ "$MODE" = ios ]; then
  setup_linux_core
  setup_linux_ios
else
  setup_linux_core
  if sdk_source_available; then
    setup_linux_ios
  else
    log "No iOS SDK source found: installed the Swift toolchain only (make test, make lint)."
    log "For iOS builds see README, 'iOS SDK'."
  fi
fi
"$ROOT/scripts/doctor.sh"
