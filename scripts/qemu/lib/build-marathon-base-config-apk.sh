#!/usr/bin/env bash
# Build marathon-base-config-<pkgver>-r<pkgrel>.apk for Duranium's mkosi.packages/.
# Static config-only package — abuild runs in seconds. Same pattern as
# build-marathon-shell-apk.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-${HOME}/Developer/Marathon-Image}"
APORTS_SRC="$MARATHON_IMAGE_DIR/packages"
MKOSI_PKG_DIR="$DURANIUM_DIR/mkosi.packages"

[ -d "$APORTS_SRC/marathon-base-config" ] || {
    echo "error: marathon-base-config APKBUILD not found at $APORTS_SRC/marathon-base-config" >&2
    exit 1
}
mkdir -p "$MKOSI_PKG_DIR"

PKGVER="$(grep -E '^pkgver=' "$APORTS_SRC/marathon-base-config/APKBUILD" | cut -d= -f2)"
PKGREL="$(grep -E '^pkgrel=' "$APORTS_SRC/marathon-base-config/APKBUILD" | cut -d= -f2)"
TARGET="marathon-base-config-${PKGVER}-r${PKGREL}.apk"

echo "+-- building $TARGET --+"

podman run --rm -i \
    -e PKGVER="$PKGVER" \
    -e PKGREL="$PKGREL" \
    -e TARGET="$TARGET" \
    -v "$APORTS_SRC:/aports-src:Z,ro" \
    -v "$MKOSI_PKG_DIR:/out:Z" \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail
apk add --no-cache --quiet abuild rsync 2>&1 | tail -2

mkdir -p /root/.abuild
abuild-keygen -a -n -q
KEY_PRIV=$(ls /root/.abuild/*.rsa | head -1)
cp "${KEY_PRIV}.pub" /etc/apk/keys/
echo "PACKAGER_PRIVKEY=$KEY_PRIV" > /etc/abuild.conf

mkdir -p /work/aports
rsync -a --checksum --no-times /aports-src/ /work/aports/
cd /work/aports/marathon-base-config
abuild -F checksum >/dev/null
abuild -d -F

# pmaports place the resulting apk under aarch64 even when the host is
# noarch; marathon-base-config builds for "all" so the arch directory is
# the host's arch.
ARCH_DIR="$(uname -m)"
cp "/root/packages/aports/${ARCH_DIR}/${TARGET}" "/out/${TARGET}"
echo "wrote /out/${TARGET}"
CSCRIPT

echo "+-- done: $MKOSI_PKG_DIR/$TARGET --+"
ls -l "$MKOSI_PKG_DIR/$TARGET"
