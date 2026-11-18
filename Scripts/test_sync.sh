#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/bobukkit-sync-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
APP="$TMP/demo app"
mkdir -p "$APP"
printf '// fixture\n' > "$APP/Package.swift"
"$ROOT/Scripts/sync.sh" "$APP"
"$ROOT/Scripts/sync.sh" --check "$APP"
(cd "$APP/Vendor/BobukKit" && shasum -a 256 -c MANIFEST.sha256 >/dev/null)
mkdir -p "$APP/Vendor/BobukKit/.build"
printf cache > "$APP/Vendor/BobukKit/.build/sentinel"
printf drift >> "$APP/Vendor/BobukKit/Sources/BobukUI/PickerStyle.swift"
if "$ROOT/Scripts/sync.sh" --check "$APP" >/dev/null 2>&1; then echo 'Missed drift' >&2; exit 1; fi
"$ROOT/Scripts/sync.sh" "$APP"
[[ -f "$APP/Vendor/BobukKit/.build/sentinel" ]]
"$ROOT/Scripts/sync.sh" --check "$APP"
rm "$APP/Vendor/BobukKit/.bobukkit-vendor"
if "$ROOT/Scripts/sync.sh" "$APP" >/dev/null 2>&1; then echo 'Overwrote unmarked directory' >&2; exit 1; fi
rm -rf "$APP/Vendor/BobukKit"
ln -s "$TMP" "$APP/Vendor/BobukKit"
if "$ROOT/Scripts/sync.sh" "$APP" >/dev/null 2>&1; then echo 'Followed symlink' >&2; exit 1; fi
printf 'SYNC_TESTS_PASSED\n'
