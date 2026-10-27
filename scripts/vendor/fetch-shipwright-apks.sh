#!/usr/bin/env bash
# Puts the prebuilt Shipwright apps that packaging/vendor/shipwright.lock
# names into <dir>, each checked against its sha512. All or none: on any
# failure none are left, and the image builds without them.
# Usage: fetch-shipwright-apks.sh <mkosi.packages dir>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
lock="$here/../../packaging/vendor/shipwright.lock"
out="${1:?usage: $0 <dir>}"
mapfile -t entries < <(grep -vE '^\s*(#|$)' "$lock" || true)
if [ ${#entries[@]} -eq 0 ]; then
    echo "==> shipwright apps: none locked; building without them"
    exit 0
fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for e in "${entries[@]}"; do
    read -r apk sum url <<<"$e"
    if [ -f "$out/$apk" ] && echo "$sum  $out/$apk" | sha512sum -c --quiet - 2>/dev/null; then
        cp "$out/$apk" "$tmp/$apk"
        continue
    fi
    if ! curl -fsSL --retry 3 -o "$tmp/$apk" "$url" ||
       ! echo "$sum  $tmp/$apk" | sha512sum -c --quiet -; then
        echo "==> shipwright apps: $apk unavailable or altered; building without them" >&2
        exit 0
    fi
done
mv "$tmp"/*.apk "$out/"
echo "==> shipwright apps: ${#entries[@]} prebuilt packages in place"
