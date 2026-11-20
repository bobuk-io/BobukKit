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
# The release kit: copied with a marker, drift and stray files are found, app files are kept.
REL="$TMP/release app"
mkdir -p "$REL/Scripts/release"
printf '// fixture\n' > "$REL/Package.swift"
printf 'APP_NAME=Demo\nBUNDLE_ID=io.bobuk.demo\n' > "$REL/release.env"
printf 'app owned\n' > "$REL/Scripts/check_bundle.swift"
printf 'stale\n' > "$REL/Scripts/release/sync_kit.sh"
"$ROOT/Scripts/sync.sh" "$REL" >/dev/null
[[ -f "$REL/Scripts/release/.bobukkit-release" && -x "$REL/Scripts/release_next.sh" && -f "$REL/Scripts/release/next.sh" ]]
[[ ! -e "$REL/Scripts/release/sync_kit.sh" ]] || { echo 'Kept a file the kit no longer has' >&2; exit 1; }
[[ "$(cat "$REL/Scripts/check_bundle.swift")" == 'app owned' && -x "$REL/Scripts/package_app.sh" ]] || { echo 'Touched an app file' >&2; exit 1; }
"$ROOT/Scripts/sync.sh" --check "$REL" >/dev/null
printf '# drift\n' >> "$REL/Scripts/release/common.sh"
if "$ROOT/Scripts/sync.sh" --check "$REL" >/dev/null 2>&1; then echo 'Missed release kit drift' >&2; exit 1; fi
"$ROOT/Scripts/sync.sh" "$REL" >/dev/null
printf 'x\n' >> "$REL/Scripts/release.sh"
if "$ROOT/Scripts/sync.sh" --check "$REL" >/dev/null 2>&1; then echo 'Missed entry point drift' >&2; exit 1; fi
printf 'SYNC_TESTS_PASSED\n'
