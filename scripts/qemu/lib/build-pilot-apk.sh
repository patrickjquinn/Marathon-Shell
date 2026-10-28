#!/usr/bin/env bash
# Builds Pilot and Reef from this repository into mkosi.packages/: keel-mcp,
# shoal-pilotd (the daemon), shoal-pilot (the app) and shipwright-reef (the
# store). Needs the keel-silica apks there first: the apps link Keel's
# SailfishApp.
#
# The aports' source tarball is staged from the tree, uncommitted changes
# included, so their source= URL is never fetched here: crates/ (cargo
# resolves the whole workspace to build one member), apps/pilot, apps/reef
# and the build helpers in tools/keel-launcher.
#
# PILOT_SRC=<checkout> (else MARATHON_SHELL_SRC) builds that tree instead of
# this one; PILOT_PKGS limits which of the four are built; PILOT_BUILD_DIR
# holds the work tree (default ~/.cache/marathon-build).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/packaging}"
APORTS_SRC="$MARATHON_IMAGE_DIR/packages"
MKOSI_PKG_DIR="${MKOSI_PKG_DIR:-$DURANIUM_DIR/mkosi.packages}"
PILOT_SRC="${PILOT_SRC:-${MARATHON_SHELL_SRC:-$(cd "$SCRIPT_DIR/../../.." && pwd)}}"
PILOT_PKGS="${PILOT_PKGS:-keel-mcp shoal-pilotd shoal-pilot shipwright-reef}"

case " $PILOT_PKGS " in
*" shoal-pilot "* | *" shipwright-reef "*)
    for dep in keel-silica keel-silica-dev; do
        ls "$MKOSI_PKG_DIR/$dep"-[0-9]*.apk >/dev/null 2>&1 || {
            echo "error: no $dep apk in $MKOSI_PKG_DIR" >&2
            exit 1
        }
    done
    ;;
esac

echo "+-- building $PILOT_PKGS from $PILOT_SRC --+"

mkdir -p "${PILOT_BUILD_DIR:-${HOME}/.cache/marathon-build}"
WORK_DIR="$(mktemp -d "${PILOT_BUILD_DIR:-${HOME}/.cache/marathon-build}/pilot-build.XXXXXX")"
trap 'podman unshare rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/tmp"
tar -C "$PILOT_SRC" --exclude=crates/target --exclude=apps/pilot/target \
    --exclude=apps/reef/target \
    --transform 's,^,Marathon-Shell-main/,' \
    -czf "$WORK_DIR/source.tar.gz" crates apps/pilot apps/reef tools/keel-launcher

podman run --rm -i \
    --net=host \
    -e PILOT_PKGS="$PILOT_PKGS" \
    -e CARGO_HOME=/work/cargo \
    -e CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}" \
    -e TMPDIR=/work/tmp \
    -v "$APORTS_SRC:/aports-src:z,ro" \
    -v "$MKOSI_PKG_DIR:/out:z" \
    -v "$WORK_DIR:/work:z" \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail

apk add --no-cache --quiet abuild rsync curl ca-certificates build-base 2>&1 | tail -3 || true
case " $PILOT_PKGS " in
*" shoal-pilot "* | *" shipwright-reef "*)
    newest() { ls -1v /out/"$1"-[0-9]*.apk | tail -1; }
    apk add --no-cache --quiet --allow-untrusted \
        "$(newest keel-silica)" "$(newest keel-silica-dev)" 2>&1 | tail -3
    ;;
esac

mkdir -p /root/.abuild
abuild-keygen -a -n -q
KEY_PRIV=$(ls /root/.abuild/*.rsa | head -1)
cp "${KEY_PRIV}.pub" /etc/apk/keys/
printf 'PACKAGER_PRIVKEY=%s\nREPODEST=/root/packages\n' "$KEY_PRIV" > /etc/abuild.conf
mkdir -p /var/cache/distfiles

for pkg in $PILOT_PKGS; do
    mkdir -p /work/aports
    rsync -a --checksum --no-times /aports-src/$pkg/ /work/aports/$pkg/
    cd /work/aports/$pkg
    ver=$(srcdir=/; . ./APKBUILD; echo "$pkgver-r$pkgrel")
    cp /work/source.tar.gz "/var/cache/distfiles/$pkg-${ver%-r*}.tar.gz"
    apk add --no-cache --quiet $(srcdir=/; . ./APKBUILD; echo $makedepends | tr ' ' '\n' | \
        grep -vE '^keel-silica-dev$') 2>&1 | tail -3
    abuild -F checksum
    # -d: shoal-pilot depends on shoal-pilotd, which no repository here has.
    abuild -d -F
    cp "/root/packages/aports/"*"/$pkg-$ver.apk" /out/
    echo "wrote /out/$pkg-$ver.apk"
done
CSCRIPT

echo "+-- done --+"
for pkg in $PILOT_PKGS; do ls -l "$MKOSI_PKG_DIR/$pkg"-[0-9]*.apk; done
