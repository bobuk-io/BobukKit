#!/usr/bin/env bash
# Copy the canonical package into marked, self-contained consumer snapshots.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECK=false
if [[ ${1:-} == --check ]]; then CHECK=true; shift; fi
SNAPSHOT=$(mktemp -d "${TMPDIR:-/tmp}/bobukkit-sync.XXXXXX")
trap 'rm -rf "$SNAPSHOT"' EXIT
for file in Package.swift LICENSE README.md VERSION; do cp "$ROOT/$file" "$SNAPSHOT/"; done
for folder in Sources Tests Examples; do cp -R "$ROOT/$folder" "$SNAPSHOT/"; done
mkdir "$SNAPSHOT/Scripts"
cp "$ROOT/Scripts/check-vendor.sh" "$SNAPSHOT/Scripts/"
printf 'Managed snapshot of https://github.com/bobuk-io/BobukKit; edit upstream, then sync.\n' > "$SNAPSHOT/.bobukkit-vendor"
(cd "$SNAPSHOT" && find . -type f ! -name MANIFEST.sha256 | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$file"; done) > "$SNAPSHOT/MANIFEST.sha256"
TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then
    while IFS= read -r relative || [[ -n "$relative" ]]; do
        [[ -z "$relative" || "$relative" == \#* ]] && continue
        TARGETS+=("$ROOT/$relative")
    done < "$ROOT/consumers.txt"
fi
for app in "${TARGETS[@]}"; do
    [[ -d "$app" && -f "$app/Package.swift" ]] || { echo "Not an app package: $app" >&2; exit 1; }
    app=$(cd "$app" && pwd -P)
    [[ ! -L "$app/Vendor" && ! -L "$app/Vendor/BobukKit" ]] || { echo 'Refusing symlinked vendor directory.' >&2; exit 1; }
    target="$app/Vendor/BobukKit"
    [[ "$target" != "$ROOT" && "$ROOT" != "$target/"* ]] || { echo 'Refusing to overwrite the canonical kit.' >&2; exit 1; }
    if $CHECK; then
        diff -qr -x .build -x .swiftpm "$SNAPSHOT" "$target" || { echo "BobukKit drift: $app" >&2; exit 1; }
    else
        if [[ -d "$target" && ! -f "$target/.bobukkit-vendor" && -n "$(ls -A "$target")" ]]; then
            echo "Refusing unmarked directory: $target" >&2; exit 1
        fi
        mkdir -p "$target"
        rsync -a --delete --exclude=.build --exclude=.swiftpm "$SNAPSHOT/" "$target/"
    fi
    echo "BobukKit $(cat "$ROOT/VERSION"): $app ($($CHECK && echo checked || echo synced))"
done
