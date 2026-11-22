#!/usr/bin/env bash
# Copy the canonical kit into consumer apps, or check their copies:
#   - the Swift package into a marked, self-contained snapshot at <app>/Vendor/BobukKit;
#   - the release kit (ReleaseKit/release and ReleaseKit/entry) into <app>/Scripts/release and
#     the five entry points (with package_app.sh) in <app>/Scripts/, for apps with a release.env.
# App facts (release.env, version.env, Info.extra.plist, App.entitlements, homebrew_cask.rb, check_bundle.swift) are
# never touched.
#   Scripts/sync.sh                  sync every consumer in consumers.txt
#   Scripts/sync.sh --check [app...] fail on missing or drifted copies; never write
#   Scripts/sync.sh /path/to/app     an explicit consumer, including a fresh checkout
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECK=false
if [[ ${1:-} == --check ]]; then CHECK=true; shift; fi
SNAPSHOT=$(mktemp -d "${TMPDIR:-/tmp}/bobukkit-sync.XXXXXX")
trap 'rm -rf "$SNAPSHOT"' EXIT
for file in Package.swift LICENSE README.md AGENTS.md COOKBOOK.md VERSION; do cp "$ROOT/$file" "$SNAPSHOT/"; done
for folder in Sources Tests Examples; do cp -R "$ROOT/$folder" "$SNAPSHOT/"; done
mkdir "$SNAPSHOT/Scripts"
cp "$ROOT/Scripts/check-vendor.sh" "$SNAPSHOT/Scripts/"
printf 'Managed snapshot of https://github.com/bobuk-io/BobukKit; edit upstream, then sync.\n' > "$SNAPSHOT/.bobukkit-vendor"
(cd "$SNAPSHOT" && find . -type f ! -name MANIFEST.sha256 | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$file"; done) > "$SNAPSHOT/MANIFEST.sha256"

RELEASE="$ROOT/ReleaseKit/release"
ENTRY="$ROOT/ReleaseKit/entry"
RELEASE_MARKER="Managed copy of BobukKit/ReleaseKit/release; edit upstream, then run BobukKit/Scripts/sync.sh."

TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then
    while IFS= read -r relative || [[ -n "$relative" ]]; do
        [[ -z "$relative" || "$relative" == \#* ]] && continue
        TARGETS+=("$ROOT/$relative")
    done < "$ROOT/consumers.txt"
fi

# The release kit of one app: Scripts/release mirrors ReleaseKit/release plus a marker.
sync_release() {
    local app=$1 release="$1/Scripts/release"
    [[ -f "$app/release.env" ]] || return 0
    [[ ! -L "$app/Scripts" && ! -L "$release" ]] || { echo "Refusing symlinked Scripts/release: $app" >&2; return 1; }
    if $CHECK; then
        local status=0
        diff -qr -x .bobukkit-release "$RELEASE" "$release" >&2 || status=1
        [[ "$(cat "$release/.bobukkit-release" 2>/dev/null)" == "$RELEASE_MARKER" ]] || { echo "$app: Scripts/release has no BobukKit marker" >&2; status=1; }
        for entry in "$ENTRY"/*.sh; do
            cmp -s "$entry" "$app/Scripts/$(basename "$entry")" || { echo "$app: Scripts/$(basename "$entry") differs from ReleaseKit/entry" >&2; status=1; }
        done
        [[ $status -eq 0 ]] || { echo "Release kit drift: $app" >&2; return 1; }
    else
        mkdir -p "$release"
        rsync -a --delete --exclude=.bobukkit-release "$RELEASE/" "$release/"
        printf '%s\n' "$RELEASE_MARKER" > "$release/.bobukkit-release"
        for entry in "$ENTRY"/*.sh; do cp -p "$entry" "$app/Scripts/"; done
    fi
}

status=0
for app in "${TARGETS[@]}"; do
    [[ -d "$app" && -f "$app/Package.swift" ]] || { echo "Not an app package: $app" >&2; exit 1; }
    app=$(cd "$app" && pwd -P)
    [[ ! -L "$app/Vendor" && ! -L "$app/Vendor/BobukKit" ]] || { echo 'Refusing symlinked vendor directory.' >&2; exit 1; }
    target="$app/Vendor/BobukKit"
    [[ "$target" != "$ROOT" && "$ROOT" != "$target/"* ]] || { echo 'Refusing to overwrite the canonical kit.' >&2; exit 1; }
    if $CHECK; then
        diff -qr -x .build -x .swiftpm "$SNAPSHOT" "$target" || { echo "BobukKit drift: $app" >&2; status=1; }
        sync_release "$app" || status=1
    else
        if [[ -d "$target" && ! -f "$target/.bobukkit-vendor" && -n "$(ls -A "$target")" ]]; then
            echo "Refusing unmarked directory: $target" >&2; exit 1
        fi
        mkdir -p "$target"
        rsync -a --delete --exclude=.build --exclude=.swiftpm "$SNAPSHOT/" "$target/"
        sync_release "$app"
    fi
    echo "BobukKit $(cat "$ROOT/VERSION"): $app ($($CHECK && echo checked || echo synced))"
done
exit $status
