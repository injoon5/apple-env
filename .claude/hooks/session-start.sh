#!/usr/bin/env bash
# Claude Code cloud sessions: install the toolchain, then hand the session its
# PATH. Local machines are left alone (run `make setup` yourself).
set -euo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = true ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"

log="${TMPDIR:-/tmp}/apple-env-bootstrap.log"
if ! scripts/bootstrap.sh >"$log" 2>&1; then
  echo "Toolchain setup failed (full log: $log). Last lines:"
  tail -n 25 "$log"
  exit 0 # let the session start; the log says what to fix
fi

. scripts/env.sh
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    printf 'export PATH=%q\n' "$PATH"
    printf 'export APPLE_ENV_UPSTREAM=%q\n' "$APPLE_ENV_UPSTREAM"
  } >>"$CLAUDE_ENV_FILE"
fi

# Shown to Claude at session start.
scripts/doctor.sh | sed 's/\x1b\[[0-9;]*m//g'
