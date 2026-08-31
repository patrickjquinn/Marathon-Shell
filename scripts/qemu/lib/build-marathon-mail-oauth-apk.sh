#!/usr/bin/env bash
# Build marathon-mail-oauth-<pkgver>-r<pkgrel>.apk for Duranium's
# mkosi.packages/. Mirrors build-marathon-shell-apk.sh's shape but
# packages just the Rust crate at tools/marathon-mail-oauth/ in the
# Marathon-Shell source tree.
#
# The crate is its own .apk because (a) Rust + cargo-auditable carry a
# very different upgrade cadence to the C++ shell, (b) it loads in a
# different process (QMF messageserver5 + each Mail app launch), and
# (c) ~75 MB of cargo dep download time shouldn't gate every
# marathon-shell apk iteration.
#
# Builds from THIS repo by default (matches build-marathon-shell-apk.sh).
# Set MARATHON_SHELL_SRC=/some/checkout to build a different tree, or
# MARATHON_SHELL_SRC="" (explicitly empty) to clone MARATHON_SHELL_GIT at
# MARATHON_SHELL_REF instead. Note the OAuth client-ID bake below reads
# tools/marathon-mail-oauth/oauth-clients.env from this tree — the clone
# path cannot bake IDs and yields a community apk.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/packaging}"
APORTS_SRC="$MARATHON_IMAGE_DIR/packages"
MKOSI_PKG_DIR="$DURANIUM_DIR/mkosi.packages"

MARATHON_SHELL_GIT="${MARATHON_SHELL_GIT:-https://github.com/patrickjquinn/Marathon-Shell.git}"
MARATHON_SHELL_REF="${MARATHON_SHELL_REF:-ux-overhaul}"
MARATHON_SHELL_SRC="${MARATHON_SHELL_SRC-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

[ -d "$APORTS_SRC/marathon-mail-oauth" ] || {
    echo "error: marathon-mail-oauth APKBUILD not found at $APORTS_SRC/marathon-mail-oauth" >&2
    exit 1
}
mkdir -p "$MKOSI_PKG_DIR"

PKGVER="$(grep -E '^pkgver=' "$APORTS_SRC/marathon-mail-oauth/APKBUILD" | cut -d= -f2)"
PKGREL="$(grep -E '^pkgrel=' "$APORTS_SRC/marathon-mail-oauth/APKBUILD" | cut -d= -f2)"
TARGET="marathon-mail-oauth-${PKGVER}-r${PKGREL}.apk"

echo "+-- building $TARGET --+"
echo "shell src: ${MARATHON_SHELL_SRC:-$MARATHON_SHELL_GIT @ $MARATHON_SHELL_REF}"
echo "output:    $MKOSI_PKG_DIR/$TARGET"

SHELL_MOUNT_ARGS=()
if [ -n "$MARATHON_SHELL_SRC" ]; then
    SHELL_MOUNT_ARGS=(-v "$MARATHON_SHELL_SRC:/shellsrc:z,ro")
fi

# Per-deployment OAuth client IDs. Source oauth-clients.env if the
# project maintainer has copied + filled in the .example template;
# otherwise build a community apk that emits oauth_not_configured at
# runtime. Either way is fine — see docs/MAIL_OAUTH_REGISTRATION.md.
GOOGLE_CID=""
MS_CID=""
OAUTH_ENV_FILE=""
if [ -n "$MARATHON_SHELL_SRC" ] && \
   [ -f "$MARATHON_SHELL_SRC/tools/marathon-mail-oauth/oauth-clients.env" ]; then
    OAUTH_ENV_FILE="$MARATHON_SHELL_SRC/tools/marathon-mail-oauth/oauth-clients.env"
    # shellcheck disable=SC1090
    . "$OAUTH_ENV_FILE"
    GOOGLE_CID="${MARATHON_DEFAULT_GOOGLE_CLIENT_ID:-}"
    MS_CID="${MARATHON_DEFAULT_MICROSOFT_CLIENT_ID:-}"
fi
if [ -n "$GOOGLE_CID" ] || [ -n "$MS_CID" ]; then
    echo "oauth bake: gmail=$([ -n "$GOOGLE_CID" ] && echo set || echo unset), microsoft=$([ -n "$MS_CID" ] && echo set || echo unset)"
else
    echo "oauth bake: none — community apk (set via $MARATHON_SHELL_SRC/tools/marathon-mail-oauth/oauth-clients.env if you want IDs baked)"
fi

# --net=host is needed because `options="net"` in the APKBUILD tells
# abuild to allow network in build() (cargo fetch). Without --net=host
# abuild still tries to use its own networking but inside the rootless
# podman default-bridge — DNS works but the per-network firewall can
# drop packets to crates.io's CDN intermittently.
podman run --rm -i \
    --net=host \
    -e MARATHON_SHELL_GIT="$MARATHON_SHELL_GIT" \
    -e MARATHON_SHELL_REF="$MARATHON_SHELL_REF" \
    -e USE_LOCAL_SHELL_SRC="$([ -n "$MARATHON_SHELL_SRC" ] && echo 1 || echo 0)" \
    -e PKGVER="$PKGVER" \
    -e PKGREL="$PKGREL" \
    -e TARGET="$TARGET" \
    -e MARATHON_DEFAULT_GOOGLE_CLIENT_ID="$GOOGLE_CID" \
    -e MARATHON_DEFAULT_MICROSOFT_CLIENT_ID="$MS_CID" \
    -v "$APORTS_SRC:/aports-src:z,ro" \
    -v "$MKOSI_PKG_DIR:/out:z" \
    "${SHELL_MOUNT_ARGS[@]}" \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail

apk add --no-cache --quiet \
    abuild rsync curl ca-certificates git \
    cargo cargo-auditable 2>&1 | tail -3 || true

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

mkdir -p /var/cache/distfiles /tmp/shellsrc-stage
if [ "${USE_LOCAL_SHELL_SRC:-0}" = "1" ]; then
    rsync -a --checksum --no-times --delete \
          --exclude='.git' --exclude='build' --exclude='build-apps' \
          --exclude='build-ui' --exclude='.cache' --exclude='target' --exclude='packaging' \
          /shellsrc/ /tmp/shellsrc-stage/Marathon-Shell-main/
else
    echo "cloning $MARATHON_SHELL_GIT @ $MARATHON_SHELL_REF"
    rm -rf /tmp/shellsrc-stage/Marathon-Shell-main
    git clone --depth 1 --branch "$MARATHON_SHELL_REF" \
        "$MARATHON_SHELL_GIT" /tmp/shellsrc-stage/Marathon-Shell-main 2>&1 | tail -3 || true
    rm -rf /tmp/shellsrc-stage/Marathon-Shell-main/.git
fi
( cd /tmp/shellsrc-stage && tar -cf - Marathon-Shell-main ) | gzip -1 \
    > "/var/cache/distfiles/marathon-mail-oauth-${PKGVER}.tar.gz"

cd /work/aports/marathon-mail-oauth
abuild -F checksum >/dev/null
abuild -d -F

cp "/root/packages/aports/aarch64/${TARGET}" "/out/${TARGET}"
echo "wrote /out/${TARGET}"
CSCRIPT

echo "+-- done: $MKOSI_PKG_DIR/$TARGET --+"
ls -l "$MKOSI_PKG_DIR/$TARGET"
