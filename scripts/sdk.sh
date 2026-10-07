#!/usr/bin/env bash
# The darwin (iOS) SDK that xtool builds against on Linux.
#
#   scripts/sdk.sh status        what is registered and cached
#   scripts/sdk.sh fetch [URL]   download APPLE_SDK_URL: an Xcode .xip (its path is
#                                printed for XCODE_XIP) or an archive made by `pack`
#                                (unpacked into the SDK cache)
#   scripts/sdk.sh pack [OUT]    archive the cached SDK, so other Linux machines
#                                (cloud sessions, CI) skip the Xcode download
#
# Optional: APPLE_SDK_TOKEN (sent as a Bearer token, e.g. for a private GitHub
# release asset via api.github.com), APPLE_SDK_SHA256 (verified after download).
#
# The SDK is Apple software under the Xcode license. Keep archives private
# (presigned S3/R2/GCS URL, private release asset); never publish them.
set -euo pipefail

SDK_CACHE="${SDK_CACHE:-$HOME/.cache/xtool}"
DOWNLOADS="${XDG_CACHE_HOME:-$HOME/.cache}/apple-env/downloads"

log() { printf '\033[1m==> %s\033[0m\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

latest_cache() { ls -dt "$SDK_CACHE"/darwin-*.xtoolsdk 2>/dev/null | head -n1 || true; }

cmd_status() {
  echo "registered: $(swift sdk list 2>/dev/null | grep -w darwin || echo none)"
  local c
  c=$(latest_cache)
  echo "cached:     ${c:-none}"
}

cmd_fetch() {
  local url="${1:-${APPLE_SDK_URL:-}}"
  [ -n "$url" ] || die "no URL: pass one or set APPLE_SDK_URL"
  mkdir -p "$DOWNLOADS"
  local file="$DOWNLOADS/apple-sdk.download"
  local curl_args=(-fL --retry 5 --retry-delay 5 -C - -o "$file.part")
  if [ -n "${APPLE_SDK_TOKEN:-}" ]; then curl_args+=(-H "Authorization: Bearer $APPLE_SDK_TOKEN"); fi
  case "$url" in https://api.github.com/*) curl_args+=(-H "Accept: application/octet-stream") ;; esac
  if [ ! -f "$file" ]; then
    log "Downloading the iOS SDK source (several GB)"
    curl "${curl_args[@]}" "$url" >&2
    mv "$file.part" "$file"
  fi
  if [ -n "${APPLE_SDK_SHA256:-}" ]; then
    echo "$APPLE_SDK_SHA256  $file" | sha256sum -c --quiet - >&2 || {
      rm -f "$file"
      die "checksum mismatch (APPLE_SDK_SHA256)"
    }
  fi
  local magic tar_flag
  magic=$(head -c 6 "$file" | od -An -tx1 | tr -d ' \n')
  case "$magic" in
    78617221*) # "xar!": an Xcode .xip
      mv "$file" "$DOWNLOADS/Xcode.xip"
      echo "$DOWNLOADS/Xcode.xip"
      return
      ;;
    28b52ffd*) tar_flag=--zstd ;;
    1f8b*) tar_flag=-z ;;
    fd377a585a00) tar_flag=-J ;;
    *) die "unknown file type (magic $magic): expected an Xcode .xip or a tar.zst/tar.gz/tar.xz from 'sdk.sh pack'" ;;
  esac
  log "Unpacking into $SDK_CACHE"
  mkdir -p "$SDK_CACHE"
  tar $tar_flag -xf "$file" -C "$SDK_CACHE"
  rm -f "$file"
  [ -n "$(latest_cache)" ] || die "the archive holds no darwin-*.xtoolsdk"
}

cmd_pack() {
  local sdk name out
  sdk=$(latest_cache)
  [ -n "$sdk" ] || die "no cached SDK in $SDK_CACHE (install one first: XCODE_XIP=... make setup)"
  name=$(basename "$sdk")
  out="${1:-$PWD/$name.tar.zst}"
  log "Packing $name into $out"
  # The .version.plist and .SiriSSUKitModel siblings exist when the SDK was
  # built from an Xcode.app; ship.sh reads them.
  local items=("$name")
  for extra in "$name.version.plist" "$name.SiriSSUKitModel"; do
    [ -e "$SDK_CACHE/$extra" ] && items+=("$extra")
  done
  case "$out" in
    *.zst) tar -C "$SDK_CACHE" -cf - "${items[@]}" | zstd -T0 -10 -q -o "$out" ;;
    *.gz) tar -C "$SDK_CACHE" -czf "$out" "${items[@]}" ;;
    *) die "OUT must end in .tar.zst or .tar.gz" ;;
  esac
  log "Done: $(du -h "$out" | cut -f1). sha256: $(sha256sum "$out" | cut -d' ' -f1)"
  echo "Upload it somewhere private, then set APPLE_SDK_URL (and APPLE_SDK_SHA256) in the environment." >&2
}

case "${1:-status}" in
  status) cmd_status ;;
  fetch) cmd_fetch "${2:-}" ;;
  pack) cmd_pack "${2:-}" ;;
  -h | --help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $1 (status, fetch, pack)" ;;
esac
