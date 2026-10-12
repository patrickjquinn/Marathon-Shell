#!/usr/bin/env bash
# Build a Marathon fork aport that compiles source (linux-*-marathon,
# u-boot-*-marathon) into mkosi.packages/. Unlike the device overlay these
# need their makedepends, some of which (postmarketos-installkernel) only
# postmarketOS ships, so its signed repo is added next to Alpine's.
#
# Usage: build-aport-apk.sh <pkgname>, or APORT=<pkgname> in the env.
set -euo pipefail

PKG="${1:-${APORT:?usage: $0 <pkgname> (or APORT=<pkgname>)}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/packaging}"
APORTS_SRC="$MARATHON_IMAGE_DIR/packages"
MKOSI_PKG_DIR="${MKOSI_PKG_DIR:-$DURANIUM_DIR/mkosi.packages}"
PMOS_KEY="$DURANIUM_DIR/pmaports/main/postmarketos-keys/build.postmarketos.org.rsa.pub"

[ -f "$APORTS_SRC/$PKG/APKBUILD" ] || { echo "error: no aport $APORTS_SRC/$PKG" >&2; exit 1; }
[ -f "$PMOS_KEY" ] || { echo "error: postmarketOS key not found at $PMOS_KEY" >&2; exit 1; }
mkdir -p "$MKOSI_PKG_DIR"

echo "+-- building $PKG --+"

podman run --rm -i \
    -e PKG="$PKG" \
    -v "$APORTS_SRC:/aports-src:z,ro" \
    -v "$PMOS_KEY:/etc/apk/keys/build.postmarketos.org.rsa.pub:z,ro" \
    -v "$MKOSI_PKG_DIR:/out:z" \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail
echo https://mirror.postmarketos.org/postmarketos/master >> /etc/apk/repositories
apk add --no-cache --quiet abuild rsync 2>&1 | tail -3 || true

mkdir -p /root/.abuild
abuild-keygen -a -n -q
KEY_PRIV=$(ls /root/.abuild/*.rsa | head -1)
cp "${KEY_PRIV}.pub" /etc/apk/keys/
printf 'PACKAGER_PRIVKEY=%s\nREPODEST=/root/packages\n' "$KEY_PRIV" > /etc/abuild.conf

mkdir -p /work/aports
rsync -a --checksum --no-times "/aports-src/$PKG/" "/work/aports/$PKG/"
cd "/work/aports/$PKG"
abuild -F checksum >/dev/null
abuild -r -F

cp /root/packages/aports/*/"$PKG"-*.apk /out/
CSCRIPT

ls -l "$MKOSI_PKG_DIR/$PKG"-*.apk
