#!/usr/bin/env bash
# Build the postmarketos-ui-marathon meta-package apk.
#
# postmarketos-ui-marathon has no sources — it's a one-file APKBUILD
# whose depends= list pulls in marathon-shell + greetd + the rest of
# the runtime stack. duranium's pmaports resolver auto-adds this
# package to the image's Packages= list when invoked with
# `ui-marathon`, so we have to make sure the local apk exists in
# mkosi.packages/ before the bake.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-${HOME}/Developer/Marathon-Image}"
APORTS_SRC="$MARATHON_IMAGE_DIR/packages"
MKOSI_PKG_DIR="${MKOSI_PKG_DIR:-$DURANIUM_DIR/mkosi.packages}"

[ -d "$APORTS_SRC/postmarketos-ui-marathon" ] || {
    echo "error: postmarketos-ui-marathon APKBUILD not found at $APORTS_SRC/postmarketos-ui-marathon" >&2
    exit 1
}
mkdir -p "$MKOSI_PKG_DIR"

PKGVER="$(grep -E '^pkgver=' "$APORTS_SRC/postmarketos-ui-marathon/APKBUILD" | cut -d= -f2)"
PKGREL="$(grep -E '^pkgrel=' "$APORTS_SRC/postmarketos-ui-marathon/APKBUILD" | cut -d= -f2)"
TARGET="postmarketos-ui-marathon-${PKGVER}-r${PKGREL}.apk"

echo "+-- building $TARGET --+"

podman run --rm -i \
    -v "$APORTS_SRC:/aports-src:z,ro" \
    -v "$MKOSI_PKG_DIR:/out:z" \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail
apk add --no-cache --quiet abuild rsync 2>&1 | tail -3 || true

mkdir -p /root/.abuild
abuild-keygen -a -n -q
KEY_PRIV=$(ls /root/.abuild/*.rsa | head -1)
cp "${KEY_PRIV}.pub" /etc/apk/keys/
echo "PACKAGER_PRIVKEY=$KEY_PRIV" > /etc/abuild.conf

mkdir -p /work/aports
rsync -a --checksum --no-times /aports-src/ /work/aports/

cd /work/aports/postmarketos-ui-marathon
abuild -F checksum >/dev/null
abuild -d -F

cp /root/packages/aports/aarch64/postmarketos-ui-marathon-*.apk /out/
CSCRIPT

echo "+-- done: $MKOSI_PKG_DIR/$TARGET --+"
ls -l "$MKOSI_PKG_DIR/$TARGET"
