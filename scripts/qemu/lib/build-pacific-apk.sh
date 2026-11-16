#!/usr/bin/env bash
# Builds pacific (apps/pacific, Marathon's browser) from this repository into
# mkosi.packages/. Needs the keel-silica and wpewebkit apks there first:
# Pacific links Keel's SailfishApp and builds its WebView against WPE.
#
# The aport's source tarball is staged from the tree, uncommitted changes
# included, so its source= URL is never fetched here: apps/pacific, crates/
# (the Keel crates the app uses inherit that workspace), the Keel Actions
# activation template (apps/keel-actions.service.in) and the build helpers
# in tools/keel-launcher.
#
# PACIFIC_SRC=<checkout> (else MARATHON_SHELL_SRC) builds that tree instead
# of this one; PACIFIC_BUILD_DIR holds the work tree (default
# ~/.cache/marathon-build).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/packaging}"
APORTS_SRC="$MARATHON_IMAGE_DIR/packages"
MKOSI_PKG_DIR="${MKOSI_PKG_DIR:-$DURANIUM_DIR/mkosi.packages}"
PACIFIC_SRC="${PACIFIC_SRC:-${MARATHON_SHELL_SRC:-$(cd "$SCRIPT_DIR/../../.." && pwd)}}"

PKGVER="$(grep -E '^pkgver=' "$APORTS_SRC/pacific/APKBUILD" | cut -d= -f2)"
PKGREL="$(grep -E '^pkgrel=' "$APORTS_SRC/pacific/APKBUILD" | cut -d= -f2)"
TARGET="pacific-${PKGVER}-r${PKGREL}.apk"

for dep in keel-silica keel-silica-dev wpewebkit wpewebkit-dev; do
    ls "$MKOSI_PKG_DIR/$dep"-[0-9]*.apk >/dev/null 2>&1 || {
        echo "error: no $dep apk in $MKOSI_PKG_DIR" >&2
        exit 1
    }
done

echo "+-- building $TARGET from $PACIFIC_SRC --+"

# The cargo target directory runs to several GB: keep it off a RAM /tmp
# (PACIFIC_BUILD_DIR moves it).
mkdir -p "${PACIFIC_BUILD_DIR:-${HOME}/.cache/marathon-build}"
WORK_DIR="$(mktemp -d "${PACIFIC_BUILD_DIR:-${HOME}/.cache/marathon-build}/pacific-build.XXXXXX")"
trap 'podman unshare rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/distfiles"
tar -C "$PACIFIC_SRC" --exclude=crates/target --exclude=apps/pacific/app/target \
    --exclude=apps/pacific/core/target \
    --transform 's,^,Marathon-Shell-main/,' \
    -czf "$WORK_DIR/distfiles/pacific-$PKGVER.tar.gz" crates apps/pacific apps/keel-actions.service.in tools/keel-launcher

podman run --rm -i \
    --net=host \
    -e TARGET="$TARGET" \
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
# wpewebkit links libjxl 0.11, which edge has moved past; the image
# carries it as libjxl0.11.
apk add --no-cache --quiet --allow-untrusted \
    "$(newest keel-silica)" "$(newest keel-silica-dev)" \
    $(ls /out/libjxl0.11-[0-9]*.apk 2>/dev/null | tail -1) \
    "$(newest wpewebkit)" "$(newest wpewebkit-dev)" 2>&1 | tail -3

mkdir -p /root/.abuild
abuild-keygen -a -n -q
KEY_PRIV=$(ls /root/.abuild/*.rsa | head -1)
cp "${KEY_PRIV}.pub" /etc/apk/keys/
printf 'PACKAGER_PRIVKEY=%s\nREPODEST=/root/packages\n' "$KEY_PRIV" > /etc/abuild.conf

mkdir -p /work/aports /var/cache/distfiles
rsync -a --checksum --no-times /aports-src/pacific/ /work/aports/pacific/
cp /work/distfiles/*.tar.gz /var/cache/distfiles/
cd /work/aports/pacific
# makedepends besides the local apks installed above.
apk add --no-cache --quiet $(srcdir=/; . ./APKBUILD; echo $makedepends | tr ' ' '\n' | \
    grep -vE '^(keel-silica-dev|wpewebkit-dev)$') 2>&1 | tail -3

abuild -F checksum
abuild -d -F

cp "/root/packages/aports/"*"/${TARGET}" "/out/${TARGET}"
echo "wrote /out/${TARGET}"
CSCRIPT

echo "+-- done: $MKOSI_PKG_DIR/$TARGET --+"
ls -l "$MKOSI_PKG_DIR/$TARGET"
