#!/usr/bin/env bash
# Build the device-<NAME>-marathon overlay apk.
#
# Reads $MARATHON_TARGET_DEVICE from the env (set by the
# orchestrator) and locates the matching aport at
#   $MARATHON_IMAGE_DIR/packages/device-$MARATHON_TARGET_DEVICE-marathon
#
# These are small meta-packages whose APKBUILDs declare depends= on
# the upstream pmaports device-<NAME> + marathon-shell + the runtime
# stack (greetd, networkmanager, modemmanager, …). No source builds.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/packaging}"
APORTS_SRC="$MARATHON_IMAGE_DIR/packages"
MKOSI_PKG_DIR="${MKOSI_PKG_DIR:-$DURANIUM_DIR/mkosi.packages}"
DEVICE="${MARATHON_TARGET_DEVICE:?MARATHON_TARGET_DEVICE not set}"

APORT="$APORTS_SRC/device-${DEVICE}-marathon"
[ -d "$APORT" ] || {
    echo "no overlay aport at $APORT — skipping" >&2
    exit 0
}

PKGVER="$(grep -E '^pkgver=' "$APORT/APKBUILD" | cut -d= -f2)"
PKGREL="$(grep -E '^pkgrel=' "$APORT/APKBUILD" | cut -d= -f2)"
TARGET="device-${DEVICE}-marathon-${PKGVER}-r${PKGREL}.apk"

echo "+-- building $TARGET --+"

podman run --rm -i \
    -e DEVICE="$DEVICE" \
    -v "$APORTS_SRC:/aports-src:z,ro" \
    -v "$MKOSI_PKG_DIR:/out:z" \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail
apk add --no-cache --quiet abuild rsync 2>&1 | tail -3 || true

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

cd "/work/aports/device-${DEVICE}-marathon"
abuild -F checksum >/dev/null
abuild -d -F

cp "/root/packages/aports/aarch64/device-${DEVICE}-marathon-"*.apk /out/
CSCRIPT

echo "+-- done: $MKOSI_PKG_DIR/$TARGET --+"
ls -l "$MKOSI_PKG_DIR/$TARGET"
