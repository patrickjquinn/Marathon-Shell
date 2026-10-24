#!/usr/bin/env bash
# Builds Shipwright's Pilot (shoal/pilot) into mkosi.packages/: shoal-pilotd
# (the daemon) and shoal-pilot (the app). Needs the keel-silica apks there
# first: the app links Keel's SailfishApp.
# PILOT_SRC=<Shipwright checkout> builds that checkout's PILOT_REF (default
# HEAD) instead of the public shipwright-open export the APKBUILDs pin.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/require-clean.sh"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/packaging}"
APORTS_SRC="$MARATHON_IMAGE_DIR/packages"
MKOSI_PKG_DIR="$DURANIUM_DIR/mkosi.packages"

for dep in keel-silica keel-silica-dev; do
    ls "$MKOSI_PKG_DIR/$dep"-[0-9]*.apk >/dev/null 2>&1 || {
        echo "error: no $dep apk in $MKOSI_PKG_DIR" >&2
        exit 1
    }
done

echo "+-- building shoal-pilotd and shoal-pilot --+"

WORK_DIR="$(mktemp -d "${HOME}/.cache/marathon-build/pilot-build.XXXXXX")"
trap 'podman unshare rm -rf "$WORK_DIR"' EXIT

LOCAL_COMMIT=""
if [ -n "${PILOT_SRC:-}" ]; then
    [ -n "${PILOT_REF:-}" ] || require_clean "$PILOT_SRC"
    LOCAL_COMMIT="$(git -C "$PILOT_SRC" rev-parse "${PILOT_REF:-HEAD}")"
    mkdir -p "$WORK_DIR/distfiles"
    # Whole tree: pilotd is in the root workspace, the app includes
    # tools/keel-launcher.
    git -C "$PILOT_SRC" archive --format=tar.gz --prefix="shipwright-open-$LOCAL_COMMIT/" \
        -o "$WORK_DIR/distfiles/shoal-pilot-$LOCAL_COMMIT.tar.gz" "$LOCAL_COMMIT"
    echo "pilot source: $PILOT_SRC @ $LOCAL_COMMIT"
fi

podman run --rm -i \
    --net=host \
    -e LOCAL_COMMIT="$LOCAL_COMMIT" \
    -v "$APORTS_SRC:/aports-src:z,ro" \
    -v "$MKOSI_PKG_DIR:/out:z" \
    -v "$WORK_DIR:/work:z" \
    -e CARGO_HOME=/work/cargo \
    -e CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}" \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail

apk add --no-cache --quiet abuild rsync curl ca-certificates git build-base 2>&1 | tail -3 || true
newest() { ls -1v /out/"$1"-[0-9]*.apk | tail -1; }
apk add --no-cache --quiet --allow-untrusted \
    "$(newest keel-silica)" "$(newest keel-silica-dev)" 2>&1 | tail -3

mkdir -p /root/.abuild
abuild-keygen -a -n -q
KEY_PRIV=$(ls /root/.abuild/*.rsa | head -1)
cp "${KEY_PRIV}.pub" /etc/apk/keys/
printf 'PACKAGER_PRIVKEY=%s\nREPODEST=/root/packages\n' "$KEY_PRIV" > /etc/abuild.conf
if [ -n "$LOCAL_COMMIT" ]; then
    mkdir -p /var/cache/distfiles
    cp /work/distfiles/*.tar.gz /var/cache/distfiles/
fi

for pkg in shoal-pilotd shoal-pilot; do
    mkdir -p /work/aports
    rsync -a --checksum --no-times /aports-src/$pkg/ /work/aports/$pkg/
    cd /work/aports/$pkg
    apk add --no-cache --quiet $(srcdir=/; . ./APKBUILD; echo $makedepends | tr ' ' '\n' | \
        grep -vE '^keel-silica-dev$') 2>&1 | tail -3
    [ -n "$LOCAL_COMMIT" ] && sed -i "s/^_commit=.*/_commit=$LOCAL_COMMIT/" APKBUILD
    abuild -F checksum
    # shoal-pilot depends on shoal-pilotd, built just before.
    abuild -d -F
    ver=$(srcdir=/; . ./APKBUILD; echo "$pkgver-r$pkgrel")
    cp "/root/packages/aports/aarch64/$pkg-$ver.apk" /out/
    echo "wrote /out/$pkg-$ver.apk"
done
CSCRIPT

echo "+-- done --+"
ls -l "$MKOSI_PKG_DIR"/shoal-pilot*.apk
