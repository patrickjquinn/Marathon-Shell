#!/usr/bin/env bash
# Builds pacific (Shipwright's browser, shoal/pacific) into mkosi.packages/.
# Needs the keel-silica and wpewebkit apks there first: Pacific links Keel's
# SailfishApp and builds its WebView against WPE.
# PACIFIC_SRC=<Shipwright checkout> builds that checkout's HEAD instead of the
# public shipwright-open export the APKBUILD pins.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/require-clean.sh"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/packaging}"
APORTS_SRC="$MARATHON_IMAGE_DIR/packages"
MKOSI_PKG_DIR="$DURANIUM_DIR/mkosi.packages"

PKGVER="$(grep -E '^pkgver=' "$APORTS_SRC/pacific/APKBUILD" | cut -d= -f2)"
PKGREL="$(grep -E '^pkgrel=' "$APORTS_SRC/pacific/APKBUILD" | cut -d= -f2)"
TARGET="pacific-${PKGVER}-r${PKGREL}.apk"

for dep in keel-silica keel-silica-dev wpewebkit wpewebkit-dev; do
    ls "$MKOSI_PKG_DIR/$dep"-[0-9]*.apk >/dev/null 2>&1 || {
        echo "error: no $dep apk in $MKOSI_PKG_DIR" >&2
        exit 1
    }
done

echo "+-- building $TARGET --+"

# The cargo target directory runs to several GB: keep it off a RAM /tmp.
WORK_DIR="$(mktemp -d "${HOME}/.cache/marathon-build/pacific-build.XXXXXX")"
trap 'podman unshare rm -rf "$WORK_DIR"' EXIT

LOCAL_COMMIT=""
if [ -n "${PACIFIC_SRC:-}" ]; then
    require_clean "$PACIFIC_SRC"
    LOCAL_COMMIT="$(git -C "$PACIFIC_SRC" rev-parse HEAD)"
    mkdir -p "$WORK_DIR/distfiles"
    # Whole tree: the Keel crates Pacific uses inherit the root workspace.
    git -C "$PACIFIC_SRC" archive --format=tar.gz --prefix="shipwright-open-$LOCAL_COMMIT/" \
        -o "$WORK_DIR/distfiles/pacific-$LOCAL_COMMIT.tar.gz" HEAD
    echo "pacific source: $PACIFIC_SRC @ $LOCAL_COMMIT"
fi

podman run --rm -i \
    --net=host \
    -e TARGET="$TARGET" \
    -e LOCAL_COMMIT="$LOCAL_COMMIT" \
    -v "$APORTS_SRC:/aports-src:z,ro" \
    -v "$MKOSI_PKG_DIR:/out:z" \
    -v "$WORK_DIR:/work:z" \
    -e CARGO_HOME=/work/cargo \
    -e CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}" \
    -e CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-4}" \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail

apk add --no-cache --quiet abuild rsync curl ca-certificates git bash build-base 2>&1 | tail -3 || true
newest() { ls -1v /out/"$1"-[0-9]*.apk | tail -1; }
apk add --no-cache --quiet --allow-untrusted \
    "$(newest keel-silica)" "$(newest keel-silica-dev)" \
    "$(newest wpewebkit)" "$(newest wpewebkit-dev)" 2>&1 | tail -3

mkdir -p /root/.abuild
abuild-keygen -a -n -q
KEY_PRIV=$(ls /root/.abuild/*.rsa | head -1)
cp "${KEY_PRIV}.pub" /etc/apk/keys/
printf 'PACKAGER_PRIVKEY=%s\nREPODEST=/root/packages\n' "$KEY_PRIV" > /etc/abuild.conf

mkdir -p /work/aports
rsync -a --checksum --no-times /aports-src/pacific/ /work/aports/pacific/
cd /work/aports/pacific
# makedepends besides the local apks installed above.
apk add --no-cache --quiet $(srcdir=/; . ./APKBUILD; echo $makedepends | tr ' ' '\n' | \
    grep -vE '^(keel-silica-dev|wpewebkit-dev)$') 2>&1 | tail -3

if [ -n "$LOCAL_COMMIT" ]; then
    mkdir -p /var/cache/distfiles
    cp /work/distfiles/*.tar.gz /var/cache/distfiles/
    sed -i "s/^_commit=.*/_commit=$LOCAL_COMMIT/" APKBUILD
fi
abuild -F checksum
abuild -d -F

cp "/root/packages/aports/aarch64/${TARGET}" "/out/${TARGET}"
echo "wrote /out/${TARGET}"
CSCRIPT

echo "+-- done: $MKOSI_PKG_DIR/$TARGET --+"
ls -l "$MKOSI_PKG_DIR/$TARGET"
