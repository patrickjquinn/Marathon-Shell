#!/usr/bin/env bash
# Build marathon-shell-<pkgver>-r<pkgrel>.apk for Duranium's mkosi.packages/.
#
# Builds the shell from THIS repo by default: the aport and the source
# live in one tree now, so what you build is what you are standing in.
# Runs abuild in an alpine:edge podman container, signs with a throwaway
# key, copies the resulting .apk into mkosi.packages/.
#
# Set MARATHON_SHELL_SRC=/some/checkout to build a different tree, or
# MARATHON_SHELL_SRC="" (explicitly empty) to fall back to cloning
# MARATHON_SHELL_GIT at MARATHON_SHELL_REF.
#
# The APKBUILD's source= URL is a floating branch tarball and is NOT what
# gets built here — the tree below is staged into /var/cache/distfiles
# under the expected filename and abuild -F checksum is re-run over it,
# so abuild never fetches. That URL only fires for a standalone abuild
# outside this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-$(cd "$SCRIPT_DIR/../../.." && pwd)/packaging}"
APORTS_SRC="$MARATHON_IMAGE_DIR/packages"
MKOSI_PKG_DIR="$DURANIUM_DIR/mkosi.packages"

MARATHON_SHELL_GIT="${MARATHON_SHELL_GIT:-https://github.com/patrickjquinn/Marathon-Shell.git}"
MARATHON_SHELL_REF="${MARATHON_SHELL_REF:-ux-overhaul}"
MARATHON_SHELL_SRC="${MARATHON_SHELL_SRC-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

[ -d "$APORTS_SRC/marathon-shell" ] || {
    echo "error: marathon-shell APKBUILD not found at $APORTS_SRC/marathon-shell" >&2
    exit 1
}
mkdir -p "$MKOSI_PKG_DIR"

PKGVER="$(grep -E '^pkgver=' "$APORTS_SRC/marathon-shell/APKBUILD" | cut -d= -f2)"
PKGREL="$(grep -E '^pkgrel=' "$APORTS_SRC/marathon-shell/APKBUILD" | cut -d= -f2)"
TARGET="marathon-shell-${PKGVER}-r${PKGREL}.apk"

echo "+-- building $TARGET --+"
echo "shell src: ${MARATHON_SHELL_SRC:-$MARATHON_SHELL_GIT @ $MARATHON_SHELL_REF}"
echo "output:    $MKOSI_PKG_DIR/$TARGET"

SHELL_MOUNT_ARGS=()
if [ -n "$MARATHON_SHELL_SRC" ]; then
    # :z (shared) not :Z (exclusive) — multiple :Z mounts to the same
    # container can land on conflicting MCS labels under SELinux and
    # produce "Permission denied" on read. :z relabels once with a
    # shared label that all bindmounts can see.
    SHELL_MOUNT_ARGS=(-v "$MARATHON_SHELL_SRC:/shellsrc:z,ro")
fi

podman run --rm -i \
    -e MARATHON_SHELL_GIT="$MARATHON_SHELL_GIT" \
    -e MARATHON_SHELL_REF="$MARATHON_SHELL_REF" \
    -e USE_LOCAL_SHELL_SRC="$([ -n "$MARATHON_SHELL_SRC" ] && echo 1 || echo 0)" \
    -e PKGVER="$PKGVER" \
    -e PKGREL="$PKGREL" \
    -e TARGET="$TARGET" \
    -v "$APORTS_SRC:/aports-src:z,ro" \
    -v "$MKOSI_PKG_DIR:/out:z" \
    -v "$MKOSI_PKG_DIR:/local-apks:z,ro" \
    "${SHELL_MOUNT_ARGS[@]}" \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail
apk add --no-cache --quiet \
    abuild rsync curl ca-certificates git \
    cmake samurai build-base \
    qt6-qtbase-dev qt6-qtdeclarative-dev qt6-qtwayland-dev \
    qt6-qtwebengine-dev qt6-qtmultimedia-dev qt6-qtsensors-dev \
    qt6-qtsvg-dev qt6-qtlocation-dev qt6-qtpositioning-dev \
    qt6-qtspeech-dev \
    hunspell-dev pulseaudio-dev wayland-dev wayland-protocols \
    mesa-dev dbus-dev eudev-dev libinput-dev linux-pam-dev 2>&1 | tail -3 || true

# qmf-dev is built locally (it isn't in alpine:edge upstream yet) so we
# install it from /local-apks with --allow-untrusted. find_library() in
# our CMakeLists.txt needs libQmfClient.so + qmailstore.h to land at the
# canonical /usr/lib + /usr/include/qt6/QmfClient paths.
# `|| true` is load-bearing under `set -euo pipefail`: when the glob
# matches nothing, ls exits 2, pipefail propagates that through `head`,
# and the assignment aborts the whole script with no message on stderr
# (it was sent to /dev/null). Locally /local-apks always holds qmf apks
# from an earlier build so it never fired; on a clean CI runner the
# directory is empty and the build died silently one minute in.
QMF_DEV_APK="$(ls /local-apks/qmf-dev-*.apk 2>/dev/null | head -1 || true)"
QMF_LIBS_APK="$(ls /local-apks/qmf-libs-*.apk 2>/dev/null | head -1 || true)"
QMF_MS_APK="$(ls /local-apks/qmf-messageserver-*.apk 2>/dev/null | head -1 || true)"
if [ -n "$QMF_DEV_APK" ] && [ -n "$QMF_LIBS_APK" ] && [ -n "$QMF_MS_APK" ]; then
    apk add --no-cache --quiet --allow-untrusted \
        "$QMF_LIBS_APK" "$QMF_MS_APK" "$QMF_DEV_APK" 2>&1 | tail -3 || true
    echo "qmf-dev installed from $QMF_DEV_APK"
else
    echo "WARNING: qmf-*.apk not found under /local-apks — Mail backend will be skipped"
fi

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
          --exclude='build-ui' --exclude='.cache' --exclude='packaging' \
          /shellsrc/ /tmp/shellsrc-stage/Marathon-Shell-main/
else
    echo "cloning $MARATHON_SHELL_GIT @ $MARATHON_SHELL_REF"
    rm -rf /tmp/shellsrc-stage/Marathon-Shell-main
    git clone --depth 1 --branch "$MARATHON_SHELL_REF" \
        "$MARATHON_SHELL_GIT" /tmp/shellsrc-stage/Marathon-Shell-main 2>&1 | tail -3 || true
    rm -rf /tmp/shellsrc-stage/Marathon-Shell-main/.git
fi
( cd /tmp/shellsrc-stage && tar -cf - Marathon-Shell-main ) | gzip -1 \
    > "/var/cache/distfiles/marathon-shell-${PKGVER}.tar.gz"

[ -f /var/cache/distfiles/asyncfuture.tar.gz ] || \
    curl -fsL -o /var/cache/distfiles/asyncfuture.tar.gz \
        https://github.com/vpicaver/asyncfuture/archive/master.tar.gz

cd /work/aports/marathon-shell
abuild -F checksum >/dev/null
abuild -d -F

cp "/root/packages/aports/aarch64/${TARGET}" "/out/${TARGET}"
echo "wrote /out/${TARGET}"
CSCRIPT

echo "+-- done: $MKOSI_PKG_DIR/$TARGET --+"
ls -l "$MKOSI_PKG_DIR/$TARGET"
