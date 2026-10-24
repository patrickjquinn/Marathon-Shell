#!/usr/bin/env bash
# Builds Deckard (the Rust host daemons and the Android overlay files) into
# mkosi.packages/.
# DECKARD_SRC=<Marathon-Deckard checkout> builds that checkout's HEAD instead
# of the commit the APKBUILD pins.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/require-clean.sh"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/packaging}"
APORTS_SRC="$MARATHON_IMAGE_DIR/packages"
MKOSI_PKG_DIR="${MKOSI_PKG_DIR:-$DURANIUM_DIR/mkosi.packages}"
mkdir -p "$MKOSI_PKG_DIR"

echo "+-- building deckard --+"

WORK_DIR="$(mktemp -d "${HOME}/.cache/marathon-build/deckard-build.XXXXXX")"
trap 'podman unshare rm -rf "$WORK_DIR"' EXIT

LOCAL_COMMIT=""
if [ -n "${DECKARD_SRC:-}" ]; then
    require_clean "$DECKARD_SRC"
    LOCAL_COMMIT="$(git -C "$DECKARD_SRC" rev-parse HEAD)"
    mkdir -p "$WORK_DIR/distfiles"
    git -C "$DECKARD_SRC" archive --format=tar.gz --prefix="Marathon-Deckard-$LOCAL_COMMIT/" \
        -o "$WORK_DIR/distfiles/deckard-$LOCAL_COMMIT.tar.gz" HEAD
    echo "deckard source: $DECKARD_SRC @ $LOCAL_COMMIT"
fi

podman run --rm -i \
    --security-opt label=disable \
    --net=host \
    -e LOCAL_COMMIT="$LOCAL_COMMIT" \
    -v "$APORTS_SRC:/aports-src:z,ro" \
    -v "$MKOSI_PKG_DIR:/out:z" \
    -v "$WORK_DIR:/work:z" \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail

apk add --no-cache --quiet abuild rsync curl ca-certificates build-base 2>&1 | tail -3 || true

mkdir -p /root/.abuild
abuild-keygen -a -n -q
KEY_PRIV=$(ls /root/.abuild/*.rsa | head -1)
cp "${KEY_PRIV}.pub" /etc/apk/keys/
printf 'PACKAGER_PRIVKEY=%s\nREPODEST=/root/packages\n' "$KEY_PRIV" > /etc/abuild.conf
if [ -n "$LOCAL_COMMIT" ]; then
    mkdir -p /var/cache/distfiles
    cp /work/distfiles/*.tar.gz /var/cache/distfiles/
fi

mkdir -p /work/aports
rsync -a --checksum --no-times /aports-src/deckard/ /work/aports/deckard/
cd /work/aports/deckard
if [ -n "$LOCAL_COMMIT" ]; then
    sed -i "s/^_commit=.*/_commit=$LOCAL_COMMIT/" APKBUILD
    sed -i "s/deckard-[0-9a-f]\{40\}\.tar\.gz/deckard-$LOCAL_COMMIT.tar.gz/" APKBUILD
fi
abuild -F checksum
# -d: depends names marathon-shell, which no repository here has.
apk add --no-cache --quiet $(srcdir=/; . ./APKBUILD; echo $depends $makedepends $checkdepends |
    tr ' ' '\n' | grep -v '^marathon-shell')
# The tests create whiteouts, which the container's overlay root refuses.
mkdir -p /work/tmp
TMPDIR=/work/tmp abuild -d -F
ver=$(srcdir=/; . ./APKBUILD; echo "$pkgver-r$pkgrel")
cp "/root/packages/aports/"*"/deckard-$ver.apk" /out/
echo "wrote /out/deckard-$ver.apk"
CSCRIPT

echo "+-- done --+"
ls -l "$MKOSI_PKG_DIR"/deckard-*.apk
