#!/usr/bin/env bash
# The iOS SDK that xtool builds against on Linux. Apple ships it only inside
# Xcode, so it reaches Linux in one of these forms:
#
#   scripts/sdk.sh status        what is registered and cached
#   scripts/sdk.sh pack [OUT]    macOS: archive the SDK pieces of the installed Xcode
#                                whose Swift matches .swift-version (about 3 GB of
#                                files). Linux: archive the installed SDK cache.
#   scripts/sdk.sh fetch [URL]   get an SDK source and stage it for bootstrap.sh:
#                                - URL or APPLE_SDK_URL: an Xcode .xip or a `pack` archive
#                                - otherwise the latest `darwin-sdk` artifact of this
#                                  repository's "iOS SDK" workflow (needs APPLE_SDK_PASSPHRASE)
#
# APPLE_SDK_PASSPHRASE encrypts `pack` output (AES-256, PBKDF2) and decrypts on
# fetch. Optional: APPLE_SDK_TOKEN (Bearer token for the download or the GitHub
# API; defaults to GITHUB_TOKEN, GH_TOKEN or `gh auth token`), APPLE_SDK_SHA256,
# APPLE_SDK_REPO (owner/repo holding the workflow artifact; default: origin).
#
# The SDK is Apple software under the Xcode license. Keep archives private or
# encrypted; never commit or publish them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_CACHE="${SDK_CACHE:-$HOME/.cache/xtool}"
SDK_SRC="${SDK_SRC:-$HOME/xcode-apple-sdk-src}"
DOWNLOADS="${XDG_CACHE_HOME:-$HOME/.cache}/apple-env/downloads"
ARTIFACT=darwin-sdk

log() { printf '\033[1m==> %s\033[0m\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

latest_cache() { ls -dt "$SDK_CACHE"/darwin-*.xtoolsdk 2>/dev/null | head -n1 || true; }

openssl_bin() {
  # macOS ships LibreSSL as `openssl`; prefer Homebrew's OpenSSL 3 there.
  local brewed
  brewed=$(brew --prefix openssl@3 2>/dev/null)/bin/openssl
  if [ -x "$brewed" ]; then echo "$brewed"; else echo openssl; fi
}
encrypt() { "$(openssl_bin)" enc -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -salt -pass env:APPLE_SDK_PASSPHRASE; }
decrypt() {
  [ -n "${APPLE_SDK_PASSPHRASE:-}" ] || die "the SDK archive is encrypted: set APPLE_SDK_PASSPHRASE"
  "$(openssl_bin)" enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -pass env:APPLE_SDK_PASSPHRASE
}

github_token() {
  local t="${APPLE_SDK_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"
  if [ -z "$t" ] && have gh; then t=$(gh auth token 2>/dev/null || true); fi
  echo "$t"
}

# --- status ------------------------------------------------------------------

cmd_status() {
  echo "registered: $(swift sdk list 2>/dev/null | grep -w darwin || echo none)"
  local c
  c=$(latest_cache)
  echo "cached:     ${c:-none}"
  [ -d "$SDK_SRC/Xcode.app" ] && echo "staged:     $SDK_SRC/Xcode.app"
  return 0
}

# --- pack --------------------------------------------------------------------

# The parts of Xcode.app that xtool's SDK builder reads (omarchy-apple-dev,
# install-toolchain.sh "Route B"), relative to Xcode.app/Contents.
XCODE_PIECES=(
  Info.plist
  version.plist
  Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift
  Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift_static
  Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang
  Developer/Platforms/iPhoneOS.platform/Info.plist
  Developer/Platforms/iPhoneOS.platform/Developer/SDKs
  Developer/Platforms/iPhoneOS.platform/Developer/Library
  Developer/Platforms/iPhoneOS.platform/Developer/usr/lib
  Developer/Platforms/MacOSX.platform/Info.plist
  Developer/Platforms/MacOSX.platform/Developer/SDKs
  Developer/Platforms/MacOSX.platform/Developer/Library
  Developer/Platforms/MacOSX.platform/Developer/usr/lib
  Developer/Platforms/iPhoneSimulator.platform/Info.plist
  Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs
  Developer/Platforms/iPhoneSimulator.platform/Developer/Library
  Developer/Platforms/iPhoneSimulator.platform/Developer/usr/lib
  # App Shortcuts phrase training for ship.sh (optional)
  Frameworks/SiriSSUKitModel.framework/Versions/A/Resources
)

# The newest installed Xcode whose Swift matches .swift-version (6.4 = Xcode 27).
# Release Xcodes win over betas: App Store Connect rejects builds from beta SDKs.
find_xcode() {
  local want mm app swiftv best="" bestv="" beta="" betav=""
  want=$(tr -d '[:space:]' <"$ROOT/.swift-version")
  mm=$(cut -d. -f1-2 <<<"$want")
  for app in /Applications/Xcode*.app; do
    [ -d "$app" ] || continue
    app=$(cd "$app" && pwd -P)
    swiftv=$("$app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" --version 2>/dev/null | head -n1)
    log "found $app: ${swiftv:-no swift}"
    grep -qE "Swift version ${mm//./\\.}([^0-9]|$)" <<<"$swiftv" || continue
    local v
    v=$(plutil -extract CFBundleShortVersionString raw "$app/Contents/version.plist" 2>/dev/null || echo 0)
    case "$(basename "$app")" in
      *[Bb]eta*)
        if [ -z "$beta" ] || [ "$(printf '%s\n%s\n' "$betav" "$v" | sort -V | tail -n1)" = "$v" ]; then
          beta=$app
          betav=$v
        fi
        ;;
      *)
        if [ -z "$best" ] || [ "$(printf '%s\n%s\n' "$bestv" "$v" | sort -V | tail -n1)" = "$v" ]; then
          best=$app
          bestv=$v
        fi
        ;;
    esac
  done
  if [ -z "$best" ] && [ -n "$beta" ]; then
    log "only a beta Xcode matches; fine for development, but App Store uploads need a release Xcode"
    best=$beta
  fi
  [ -n "$best" ] || die "no installed Xcode has Swift $mm (from .swift-version). Install the matching Xcode."
  echo "$best"
}

cmd_pack() {
  local out="${1:-}" src name items=() tar_args=()
  if [ "$(uname -s)" = Darwin ]; then
    local app
    app=$(find_xcode)
    log "Packing the SDK pieces of $app"
    for p in "${XCODE_PIECES[@]}"; do
      [ -e "$app/Contents/$p" ] && items+=("$(basename "$app")/Contents/$p")
    done
    name="Xcode-$(plutil -extract CFBundleShortVersionString raw "$app/Contents/version.plist")-sdk"
    src=$(dirname "$app")
    # bsdtar: store as Xcode.app/..., keep symlinks, leave macOS metadata out.
    tar_args=(-s ",^$(basename "$app"),Xcode.app," --no-xattrs)
  else
    local sdk
    sdk=$(latest_cache)
    [ -n "$sdk" ] || die "no cached SDK in $SDK_CACHE (install one first: XCODE_XIP=... make setup)"
    name=$(basename "$sdk")
    items=("$name")
    for extra in "$name.version.plist" "$name.SiriSSUKitModel"; do
      [ -e "$SDK_CACHE/$extra" ] && items+=("$extra")
    done
    src=$SDK_CACHE
  fi
  have zstd || die "zstd is missing (brew install zstd / apt install zstd)"
  local suffix=.tar.zst
  [ -n "${APPLE_SDK_PASSPHRASE:-}" ] && suffix=.tar.zst.enc
  out="${out:-$PWD/$name$suffix}"
  case "$out" in *.enc) [ -n "${APPLE_SDK_PASSPHRASE:-}" ] || die "set APPLE_SDK_PASSPHRASE to write an encrypted archive" ;; esac
  log "Writing $out"
  if [ -n "${APPLE_SDK_PASSPHRASE:-}" ]; then
    COPYFILE_DISABLE=1 tar -C "$src" ${tar_args[@]+"${tar_args[@]}"} -cf - "${items[@]}" | zstd -T0 -12 -q -c | encrypt >"$out"
  else
    COPYFILE_DISABLE=1 tar -C "$src" ${tar_args[@]+"${tar_args[@]}"} -cf - "${items[@]}" | zstd -T0 -12 -q -c >"$out"
  fi
  log "Done: $(du -h "$out" | cut -f1)"
}

# --- fetch -------------------------------------------------------------------

# Unpack an archive (any of: encrypted, zstd, gzip, xz tar) into the SDK
# cache or, for Xcode pieces, into $SDK_SRC. Prints a .xip path instead.
stage_file() {
  local file=$1 magic
  magic=$(head -c 8 "$file" | od -An -tx1 | tr -d ' \n')
  case "$magic" in
    78617221*) # "xar!": an Xcode .xip
      mv "$file" "$DOWNLOADS/Xcode.xip"
      echo "$DOWNLOADS/Xcode.xip"
      return
      ;;
  esac
  local unpack="$DOWNLOADS/unpack"
  rm -rf "$unpack"
  mkdir -p "$unpack"
  log "Unpacking"
  case "$magic" in
    53616c7465645f5f) decrypt <"$file" | zstd -dc | tar -x -C "$unpack" ;; # "Salted__"
    28b52ffd*) zstd -dc "$file" | tar -x -C "$unpack" ;;
    1f8b*) tar -xzf "$file" -C "$unpack" ;;
    fd377a585a00*) tar -xJf "$file" -C "$unpack" ;;
    *) die "unknown file type (magic $magic): expected an Xcode .xip or an archive from 'sdk.sh pack'" ;;
  esac || die "could not unpack the SDK archive (wrong APPLE_SDK_PASSPHRASE?)"
  rm -f "$file"
  if [ -d "$unpack/Xcode.app" ]; then
    rm -rf "$SDK_SRC"
    mkdir -p "$SDK_SRC"
    mv "$unpack/Xcode.app" "$SDK_SRC/"
    log "Staged Xcode SDK pieces in $SDK_SRC"
  elif compgen -G "$unpack/darwin-*.xtoolsdk" >/dev/null; then
    mkdir -p "$SDK_CACHE"
    for f in "$unpack"/*; do
      rm -rf "${SDK_CACHE:?}/$(basename "$f")"
      mv "$f" "$SDK_CACHE/"
    done
    log "Unpacked into $SDK_CACHE"
  else
    die "the archive holds neither Xcode.app nor darwin-*.xtoolsdk"
  fi
  rm -rf "$unpack"
}

fetch_url() {
  local url=$1 file="$DOWNLOADS/apple-sdk.download" token
  local curl_args=(-fL --retry 5 --retry-delay 5 -C - -o "$file.part")
  token="${APPLE_SDK_TOKEN:-}"
  case "$url" in https://api.github.com/*)
    token=$(github_token)
    curl_args+=(-H "Accept: application/octet-stream")
    ;;
  esac
  [ -n "$token" ] && curl_args+=(-H "Authorization: Bearer $token")
  log "Downloading the iOS SDK (several GB)"
  curl "${curl_args[@]}" "$url" >&2
  mv "$file.part" "$file"
  if [ -n "${APPLE_SDK_SHA256:-}" ]; then
    echo "$APPLE_SDK_SHA256  $file" | sha256sum -c --quiet - >&2 || {
      rm -f "$file"
      die "checksum mismatch (APPLE_SDK_SHA256)"
    }
  fi
  stage_file "$file"
}

origin_repo() {
  git -C "$ROOT" remote get-url origin 2>/dev/null |
    sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#'
}

fetch_artifact() {
  local repo="${APPLE_SDK_REPO:-$(origin_repo)}" token auth=() url
  [ -n "$repo" ] || die "cannot tell the GitHub repository; set APPLE_SDK_REPO=owner/repo"
  token=$(github_token)
  [ -n "$token" ] && auth=(-H "Authorization: Bearer $token")
  log "Looking up the latest $ARTIFACT artifact in $repo"
  url=$(curl -fsSL "${auth[@]}" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$repo/actions/artifacts?name=$ARTIFACT&per_page=10" |
    python3 -c 'import json, sys
for a in json.load(sys.stdin).get("artifacts", []):
    if not a.get("expired"):
        print(a["archive_download_url"]); break') ||
    die "could not list artifacts of $repo (private repository? set APPLE_SDK_TOKEN)"
  [ -n "$url" ] || die "no $ARTIFACT artifact in $repo: run the \"iOS SDK\" workflow (Actions tab) first"
  local zip="$DOWNLOADS/$ARTIFACT.zip"
  log "Downloading the iOS SDK artifact (about 1 GB)"
  curl -fL --retry 5 --retry-delay 5 "${auth[@]}" -o "$zip" "$url" >&2 ||
    die "artifact download failed (needs a GitHub token with Actions read access: set APPLE_SDK_TOKEN)"
  local inner
  inner=$(unzip -Z1 "$zip" | head -n1)
  unzip -o -q "$zip" "$inner" -d "$DOWNLOADS"
  rm -f "$zip"
  stage_file "$DOWNLOADS/$inner"
}

cmd_fetch() {
  mkdir -p "$DOWNLOADS"
  local url="${1:-${APPLE_SDK_URL:-}}"
  if [ -n "$url" ]; then
    fetch_url "$url"
  elif [ -n "${APPLE_SDK_PASSPHRASE:-}" ]; then
    fetch_artifact
  else
    die "nothing to fetch: set APPLE_SDK_PASSPHRASE (GitHub workflow artifact) or APPLE_SDK_URL"
  fi
}

case "${1:-status}" in
  status) cmd_status ;;
  fetch) cmd_fetch "${2:-}" ;;
  pack) cmd_pack "${2:-}" ;;
  xcode) find_xcode ;; # macOS: path of the Xcode that matches .swift-version
  -h | --help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $1 (status, fetch, pack, xcode)" ;;
esac
