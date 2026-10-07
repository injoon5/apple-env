# shellcheck shell=bash disable=SC2296
# Put this project's toolchain on PATH (bash or zsh):  . scripts/env.sh
# Makefile targets and the Claude Code session hook source it for you.
# Safe to source repeatedly.

APPLE_ENV_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)"
APPLE_ENV_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/apple-env"
APPLE_ENV_UPSTREAM="$APPLE_ENV_HOME/omarchy-apple-dev"
export APPLE_ENV_ROOT APPLE_ENV_HOME APPLE_ENV_UPSTREAM

_apple_env_prepend() {
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}

_apple_env_prepend "$HOME/.local/bin"

if [ "$(uname -s)" = Linux ]; then
  _apple_env_swiftly="${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}"
  if [ -f "$_apple_env_swiftly/env.sh" ]; then
    . "$_apple_env_swiftly/env.sh"
  fi
  [ -d "$APPLE_ENV_HOME/libimobiledevice/bin" ] && _apple_env_prepend "$APPLE_ENV_HOME/libimobiledevice/bin"
  # The toolchain's own bin dir goes first. The darwin SDK must be compiled
  # against the toolchain's clang, never a system clang of another version.
  _apple_env_tc=
  if command -v swiftly >/dev/null 2>&1; then
    _apple_env_tc="$(cd "$APPLE_ENV_ROOT" && swiftly use --print-location 2>/dev/null)/usr/bin" || _apple_env_tc=
  elif command -v swift >/dev/null 2>&1; then
    _apple_env_tc="$(dirname "$(readlink -f "$(command -v swift)")")"
  fi
  if [ -n "$_apple_env_tc" ] && [ -x "$_apple_env_tc/swift" ]; then
    PATH="$_apple_env_tc:$PATH"
  fi
  unset _apple_env_swiftly _apple_env_tc
fi

unset -f _apple_env_prepend
export PATH
