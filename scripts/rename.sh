#!/usr/bin/env bash
# Rename the app everywhere: module, target and file names, bundle ID, docs.
#
#   scripts/rename.sh Notes com.you.notes
#   make rename NAME=Notes BUNDLE_ID=com.you.notes
#
# BUNDLE_ID defaults to com.example.<name in lowercase>. Run it on a clean
# working tree so `git diff` shows exactly what changed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

new=${1:-}
[ -n "$new" ] || die "usage: scripts/rename.sh NewName [com.you.newname]"
[[ "$new" =~ ^[A-Z][A-Za-z0-9]*$ ]] || die "name must be UpperCamelCase letters and digits, e.g. Notes or HabitTracker"
bid=${2:-com.example.$(tr '[:upper:]' '[:lower:]' <<<"$new")}
[[ "$bid" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || die "bad bundle ID: $bid (expected reverse DNS, e.g. com.you.notes)"

old=$(sed -n 's/^    name: "\(.*\)",$/\1/p' Package.swift | head -n1)
old_bid=$(sed -n 's/^bundleID: *//p' xtool.yml | head -n1)
[ -n "$old" ] && [ -n "$old_bid" ] || die "could not read the current name from Package.swift and xtool.yml"
if [ "$old" = "$new" ] && [ "$old_bid" = "$bid" ]; then
  echo "Already named $new ($bid)."
  exit 0
fi

list_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -co --exclude-standard
  else
    find . -type f -not -path './.git/*' -not -path '*/.build/*' | sed 's|^\./||'
  fi
}

# Contents first (text files only), then paths, deepest first.
while IFS= read -r f; do
  [ -f "$f" ] && grep -Iq . "$f" 2>/dev/null || continue
  grep -qF -e "$old" -e "$old_bid" "$f" || continue
  OLD="$old" NEW="$new" OLD_BID="$old_bid" BID="$bid" PREFIX="${bid%.*}" \
    perl -pi -e 's/^(\s*bundleIdPrefix:\s*).*/$1$ENV{PREFIX}/; s/\Q$ENV{OLD_BID}\E/$ENV{BID}/g; s/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$f"
done < <(list_files)
while IFS= read -r path; do
  dest="$(dirname "$path")/$(basename "$path" | sed "s/$old/$new/g")"
  mv "$path" "$dest"
done < <(find . -depth -name "*$old*" -not -path './.git/*' -not -path '*/.build/*' -not -path './xtool/*')

rm -rf .build Core/.build xtool "$old.xcodeproj"
echo "Renamed $old ($old_bid) to $new ($bid). Review with: git status && git diff"
