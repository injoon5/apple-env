#!/usr/bin/env bash
# Report what this machine can do with the project: test, build, run, ship.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/scripts/env.sh"

ok() { printf '  \033[32m✓\033[0m %-10s %s\n' "$1" "$2"; }
no() { printf '  \033[33m✗\033[0m %-10s %s\n' "$1" "$2"; }
have() { command -v "$1" >/dev/null 2>&1; }

want=$(tr -d '[:space:]' <"$ROOT/.swift-version")
echo "Toolchain"
if have swift; then
  v=$(swift --version 2>/dev/null | grep -oE 'Swift version [0-9.]+' | head -n1)
  ok swift "${v:-unknown} (wanted $want)"
else
  no swift "missing: run make setup"
fi

can_build=0
if [ "$(uname -s)" = Darwin ]; then
  if xcrun --sdk iphoneos --show-sdk-version >/dev/null 2>&1; then
    ok xcode "$(xcodebuild -version 2>/dev/null | head -n1), iOS SDK $(xcrun --sdk iphoneos --show-sdk-version)"
    can_build=1
  else
    no xcode "no iOS SDK: install Xcode and run sudo xcode-select -s /Applications/Xcode.app"
  fi
else
  if swift sdk list 2>/dev/null | grep -qw darwin; then
    sdk=$(ls "$HOME/.swiftpm/swift-sdks/darwin.artifactbundle/Developer/Platforms/iPhoneOS.platform/Developer/SDKs" 2>/dev/null |
      grep -E '^iPhoneOS[0-9]' | sort | tail -n1)
    ok ios-sdk "${sdk%.sdk}"
    can_build=1
  else
    no ios-sdk "none: tests and lint only (README, 'iOS SDK')"
  fi
fi
if [ "$(uname -s)" = Darwin ]; then
  if have xcodegen; then
    ok xcodegen "$(xcodegen --version 2>/dev/null)"
  else
    no xcodegen "missing: run make setup"
    can_build=0
  fi
elif have xtool; then
  ok xtool "$(xtool --version 2>/dev/null | head -n1)"
else
  no xtool "missing"
  can_build=0
fi

echo "This machine can"
ok test "make test, make lint"
if [ "$can_build" = 1 ]; then
  ok build "make build"
  if [ "$(uname -s)" = Darwin ]; then
    ok run "make xcode (simulator, previews), make run (iPhone over USB)"
  elif [ -n "${CLAUDE_CODE_REMOTE:-}${CI:-}" ]; then
    no run "no iPhone attached in the cloud; build only"
  else
    ok run "make run (iPhone over USB, after xtool auth)"
  fi
  [ "$(uname -s)" = Linux ] && ok ship "make ship, make upload (TestFlight)"
else
  no build "needs an iOS SDK and xtool"
fi
exit 0
