#!/usr/bin/env bash
# Builds keel-silica, Marathon Silica (keel-silica/ in this repo, Marathon's
# fork of Keel), into mkosi.packages/. It packages the committed keel-silica/
# at HEAD; KEEL_SRC=<another Marathon checkout> packages that one's instead.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/require-clean.sh"
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

KEEL_SRC="${KEEL_SRC:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
require_clean "$KEEL_SRC" keel-silica
mkdir -p "$WORK_DIR/distfiles"
git -C "$KEEL_SRC" archive --format=tar.gz --prefix=Marathon-Shell-main/ \
    -o "$WORK_DIR/distfiles/keel-silica-$PKGVER.tar.gz" HEAD keel-silica
echo "keel source: $KEEL_SRC @ $(git -C "$KEEL_SRC" rev-parse --short HEAD)"

podman run --rm -i \
    --net=host \
    -e TARGET="$TARGET" \
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
mkdir -p /var/cache/distfiles
cp /work/distfiles/*.tar.gz /var/cache/distfiles/
abuild -F checksum
abuild -d -F

cp "/root/packages/aports/aarch64/${TARGET}" "/out/${TARGET}"
cp "/root/packages/aports/aarch64/${TARGET/keel-silica-/keel-silica-dev-}" /out/
echo "wrote /out/${TARGET}"
CSCRIPT

echo "+-- done: $MKOSI_PKG_DIR/$TARGET --+"
ls -l "$MKOSI_PKG_DIR/$TARGET"
