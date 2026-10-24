#!/usr/bin/env bash
# Builds Shipwright's keel-mcp (keel/actions/mcp) into mkosi.packages/.
# KEEL_MCP_SRC=<Shipwright checkout> builds that checkout's HEAD instead of
# the public shipwright-open export the APKBUILD pins.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/require-clean.sh"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/packaging}"
APORTS_SRC="$MARATHON_IMAGE_DIR/packages"
MKOSI_PKG_DIR="$DURANIUM_DIR/mkosi.packages"
mkdir -p "$MKOSI_PKG_DIR"

echo "+-- building keel-mcp --+"

WORK_DIR="$(mktemp -d "${HOME}/.cache/marathon-build/keel-mcp-build.XXXXXX")"
trap 'podman unshare rm -rf "$WORK_DIR"' EXIT

LOCAL_COMMIT=""
if [ -n "${KEEL_MCP_SRC:-}" ]; then
    require_clean "$KEEL_MCP_SRC"
    LOCAL_COMMIT="$(git -C "$KEEL_MCP_SRC" rev-parse HEAD)"
    mkdir -p "$WORK_DIR/distfiles"
    # Whole tree: keel-mcp is a member of the root workspace.
    git -C "$KEEL_MCP_SRC" archive --format=tar.gz --prefix="shipwright-open-$LOCAL_COMMIT/" \
        -o "$WORK_DIR/distfiles/keel-mcp-$LOCAL_COMMIT.tar.gz" HEAD
    echo "keel-mcp source: $KEEL_MCP_SRC @ $LOCAL_COMMIT"
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

apk add --no-cache --quiet abuild rsync curl ca-certificates git build-base cargo 2>&1 | tail -3 || true

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
rsync -a --checksum --no-times /aports-src/keel-mcp/ /work/aports/keel-mcp/
cd /work/aports/keel-mcp
[ -n "$LOCAL_COMMIT" ] && sed -i "s/^_commit=.*/_commit=$LOCAL_COMMIT/" APKBUILD
abuild -F checksum
abuild -d -F
ver=$(srcdir=/; . ./APKBUILD; echo "$pkgver-r$pkgrel")
cp "/root/packages/aports/aarch64/keel-mcp-$ver.apk" /out/
echo "wrote /out/keel-mcp-$ver.apk"
CSCRIPT

echo "+-- done --+"
ls -l "$MKOSI_PKG_DIR"/keel-mcp-*.apk
