#!/usr/bin/env bash
# Builds keel-silica (Keel's Sailfish.Silica for Qt 6) into mkosi.packages/.
# KEEL_SRC=<Shipwright checkout> builds its committed keel/ at HEAD instead of
# the public shipwright-open export the APKBUILD pins.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/packaging}"
APORTS_SRC="$MARATHON_IMAGE_DIR/packages"
MKOSI_PKG_DIR="$DURANIUM_DIR/mkosi.packages"

[ -d "$APORTS_SRC/keel-silica" ] || {
    echo "error: keel-silica APKBUILD not found at $APORTS_SRC/keel-silica" >&2
    exit 1
}
mkdir -p "$MKOSI_PKG_DIR"

PKGVER="$(grep -E '^pkgver=' "$APORTS_SRC/keel-silica/APKBUILD" | cut -d= -f2)"
PKGREL="$(grep -E '^pkgrel=' "$APORTS_SRC/keel-silica/APKBUILD" | cut -d= -f2)"
TARGET="keel-silica-${PKGVER}-r${PKGREL}.apk"

echo "+-- building $TARGET --+"
echo "output: $MKOSI_PKG_DIR/$TARGET"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/keel-silica-build.XXXXXX")"
trap 'podman unshare rm -rf "$WORK_DIR"' EXIT

LOCAL_COMMIT=""
if [ -n "${KEEL_SRC:-}" ]; then
    LOCAL_COMMIT="$(git -C "$KEEL_SRC" rev-parse HEAD)"
    mkdir -p "$WORK_DIR/distfiles"
    git -C "$KEEL_SRC" archive --format=tar.gz --prefix="shipwright-open-$LOCAL_COMMIT/" \
        -o "$WORK_DIR/distfiles/keel-silica-$LOCAL_COMMIT.tar.gz" HEAD keel
    echo "keel source: $KEEL_SRC @ $LOCAL_COMMIT"
fi

podman run --rm -i \
    --net=host \
    -e TARGET="$TARGET" \
    -e LOCAL_COMMIT="$LOCAL_COMMIT" \
    -v "$APORTS_SRC:/aports-src:z,ro" \
    -v "$MKOSI_PKG_DIR:/out:z" \
    -v "$WORK_DIR:/work:z" \
    -e CARGO_HOME=/work/cargo \
    -e CARGO_BUILD_JOBS=4 \
    -e CMAKE_BUILD_PARALLEL_LEVEL=4 \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail

apk add --no-cache --quiet \
    abuild rsync curl ca-certificates git \
    build-base cargo cmake samurai \
    qt6-qtbase-dev qt6-qtbase-private-dev \
    qt6-qtdeclarative-dev qt6-qtdeclarative-private-dev \
    mlite-dev dconf-dev pkgconf 2>&1 | tail -3 || true

mkdir -p /root/.abuild
abuild-keygen -a -n -q
KEY_PRIV=$(ls /root/.abuild/*.rsa | head -1)
cp "${KEY_PRIV}.pub" /etc/apk/keys/
printf 'PACKAGER_PRIVKEY=%s\nREPODEST=/root/packages\n' "$KEY_PRIV" > /etc/abuild.conf

mkdir -p /work/aports
rsync -a --checksum --no-times /aports-src/keel-silica/ /work/aports/keel-silica/

cd /work/aports/keel-silica
if [ -n "$LOCAL_COMMIT" ]; then
    mkdir -p /var/cache/distfiles
    cp /work/distfiles/*.tar.gz /var/cache/distfiles/
    sed -i "s/^_commit=.*/_commit=$LOCAL_COMMIT/" APKBUILD
    abuild -F checksum
fi
abuild -d -F

cp "/root/packages/aports/aarch64/${TARGET}" "/out/${TARGET}"
cp "/root/packages/aports/aarch64/${TARGET/keel-silica-/keel-silica-dev-}" /out/
echo "wrote /out/${TARGET}"
CSCRIPT

echo "+-- done: $MKOSI_PKG_DIR/$TARGET --+"
ls -l "$MKOSI_PKG_DIR/$TARGET"
