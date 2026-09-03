#!/usr/bin/env bash
# Build marathon-plymouth-theme-<pkgver>-r<pkgrel>.apk for Duranium's
# mkosi.packages/. Static asset-only package — abuild runs in seconds.
# Same pattern as build-marathon-base-config-apk.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/packaging}"
APORTS_SRC="$MARATHON_IMAGE_DIR/packages"
MKOSI_PKG_DIR="$DURANIUM_DIR/mkosi.packages"

[ -d "$APORTS_SRC/marathon-plymouth-theme" ] || {
    echo "error: marathon-plymouth-theme APKBUILD not found at $APORTS_SRC/marathon-plymouth-theme" >&2
    exit 1
}
mkdir -p "$MKOSI_PKG_DIR"

PKGVER="$(grep -E '^pkgver=' "$APORTS_SRC/marathon-plymouth-theme/APKBUILD" | cut -d= -f2)"
PKGREL="$(grep -E '^pkgrel=' "$APORTS_SRC/marathon-plymouth-theme/APKBUILD" | cut -d= -f2)"
TARGET="marathon-plymouth-theme-${PKGVER}-r${PKGREL}.apk"

echo "+-- building $TARGET --+"

podman run --rm -i \
    -e PKGVER="$PKGVER" \
    -e PKGREL="$PKGREL" \
    -e TARGET="$TARGET" \
    -v "$APORTS_SRC:/aports-src:Z,ro" \
    -v "$MKOSI_PKG_DIR:/out:Z" \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail
apk add --no-cache --quiet abuild rsync 2>&1 | tail -2 || true

mkdir -p /root/.abuild
abuild-keygen -a -n -q
KEY_PRIV=$(ls /root/.abuild/*.rsa | head -1)
cp "${KEY_PRIV}.pub" /etc/apk/keys/
# REPODEST must be explicit. Writing /etc/abuild.conf wipes the
# distro default, and abuild >=3.18 then falls back to
# $XDG_DATA_HOME/abuild, not /root/packages — the copy below silently
# found nothing and the image baked without these apks.
printf 'PACKAGER_PRIVKEY=%s\nREPODEST=/root/packages\n' "$KEY_PRIV" > /etc/abuild.conf

mkdir -p /work/aports
rsync -a --checksum --no-times /aports-src/ /work/aports/
cd /work/aports/marathon-plymouth-theme
abuild -F checksum >/dev/null
abuild -d -F

# abuild stages noarch packages under the build host's arch directory,
# NOT aports/noarch — same as marathon-base-config (arch=all).
ARCH_DIR="$(uname -m)"
cp "/root/packages/aports/${ARCH_DIR}/${TARGET}" "/out/${TARGET}"
echo "wrote /out/${TARGET}"
CSCRIPT

echo "+-- done: $MKOSI_PKG_DIR/$TARGET --+"
ls -l "$MKOSI_PKG_DIR/$TARGET"
