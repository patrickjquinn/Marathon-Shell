#!/usr/bin/env bash
# For whoever holds the Shipwright source: builds Marathon's closed apps from
# a Shipwright commit, publishes them as a release of this repository, and
# pins them in packaging/vendor/shipwright.lock so anyone's image build can
# use them. Also brings Pacific's engine patches (WebKit is LGPL; they are
# public in packaging/packages/wpewebkit) up to that commit.
#
# SHIPWRIGHT=<checkout> (default ~/Developer/Shipwright), REF=<commit>
# (default HEAD), REPO=<owner/name> (default patrickjquinn/Marathon-Shell).
# NO_PUBLISH=1 builds and pins locally without a release.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
SHIPWRIGHT=${SHIPWRIGHT:-$HOME/Developer/Shipwright}
REF=${REF:-HEAD}
REPO=${REPO:-patrickjquinn/Marathon-Shell}
commit=$(git -C "$SHIPWRIGHT" rev-parse "$REF^{commit}")
short=${commit:0:12}
pkgs="$root/packaging/packages"
out=${MKOSI_PKG_DIR:-$HOME/.cache/marathon-build/duranium/mkosi.packages}

# Pin, bumping pkgrel when the commit moves.
for p in pacific shoal-pilot shoal-pilotd keel-mcp; do
    f="$pkgs/$p/APKBUILD"
    if ! grep -q "^_commit=$commit$" "$f"; then
        rel=$(grep -m1 '^pkgrel=' "$f" | cut -d= -f2)
        sed -i "s/^_commit=.*/_commit=$commit/; s/^pkgrel=$rel$/pkgrel=$((rel + 1))/" "$f"
        echo "==> $p: $short, r$((rel + 1))"
    fi
done

# Engine patches, then the recipe's checksums for its local files.
eng="$SHIPWRIGHT/shoal/pacific/engine/build/patches"
wpe="$pkgs/wpewebkit"
for f in "$eng"/0*.patch; do cp "$f" "$wpe/pacific-$(basename "$f")"; done
for f in "$eng"/atlantic/*.patch; do [ -e "$f" ] && cp "$f" "$wpe/atlantic-$(basename "$f").rebased"; done
python3 - "$wpe/APKBUILD" <<'PY'
import hashlib, os, re, sys
p = sys.argv[1]; d = os.path.dirname(p); s = open(p).read()
def h(m):
    f = os.path.join(d, m.group(2))
    return (hashlib.sha512(open(f, 'rb').read()).hexdigest() if os.path.isfile(f) else m.group(1)) + '  ' + m.group(2)
i = s.index('sha512sums="')
s = s[:i] + re.sub(r'([0-9a-f]{128})  (\S+)', h, s[i:])
open(p, 'w').write(s)
PY
echo "==> engine patches: $(ls "$wpe"/pacific-0*.patch | wc -l) at $short (new ones go in wpewebkit's source= by hand)"

# Build from the source, at that commit.
lib="$root/scripts/qemu/lib"
export MARATHON_IMAGE_DIR="$root/packaging" MKOSI_PKG_DIR="$out"
PACIFIC_SRC="$SHIPWRIGHT" bash "$lib/build-pacific-apk.sh"
PILOT_SRC="$SHIPWRIGHT" PILOT_REF="$commit" bash "$lib/build-pilot-apk.sh"
KEEL_MCP_SRC="$SHIPWRIGHT" bash "$lib/build-keel-mcp-apk.sh"
APORT=marathon-shipwright-apps bash "$lib/build-aport-apk.sh"

# Publish and lock.
apks=()
for p in pacific shoal-pilot shoal-pilotd keel-mcp marathon-shipwright-apps; do
    v=$(set +u; . "$pkgs/$p/APKBUILD" >/dev/null 2>&1; echo "$pkgname-$pkgver-r$pkgrel")
    [ -f "$out/$v.apk" ] || { echo "error: $v.apk was not built" >&2; exit 1; }
    apks+=("$out/$v.apk")
done
tag="shipwright-$short"
if [ "${NO_PUBLISH:-0}" != 1 ]; then
    gh release view "$tag" --repo "$REPO" >/dev/null 2>&1 ||
        gh release create "$tag" --repo "$REPO" --title "Shipwright apps $short" \
            --notes "Pacific, Pilot and keel-mcp prebuilt from Shipwright $commit for Marathon images (packaging/vendor/shipwright.lock)."
    gh release upload "$tag" --repo "$REPO" --clobber "${apks[@]}"
fi
lock="$root/packaging/vendor/shipwright.lock"
{
    sed -n '/^#/p' "$lock"
    for a in "${apks[@]}"; do
        n=$(basename "$a")
        echo "$n $(sha512sum "$a" | cut -d' ' -f1) https://github.com/$REPO/releases/download/$tag/$n"
    done
} > "$lock.new" && mv "$lock.new" "$lock"
echo "==> locked ${#apks[@]} packages at $tag"
