#!/usr/bin/env bash
# Build qmf-<pkgver>-r<pkgrel>.apk for Duranium's mkosi.packages/.
#
# QMF = Qt Messaging Framework (qt-labs/messagingframework on code.qt.io).
# This is the real mail backend that replaces the webmail-picker — Qt-native
# IMAP/SMTP/POP3 sync daemon + QML-bindable QMailMessageListModel etc.
#
# Same abuild-in-podman pattern as build-marathon-shell-apk.sh: pull the
# APKBUILD from Marathon-Image/packages/qmf, build in an alpine:edge
# container with a throwaway signing key, drop the resulting apks
# (qmf, qmf-libs, qmf-messageserver, qmf-dev) into mkosi.packages/.
#
# Override QMF_SRC=/path/to/local/messagingframework to skip the upstream
# tarball fetch (useful when iterating on patches).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DURANIUM_DIR="${DURANIUM_DIR:-${HOME}/.cache/marathon-build/duranium}"
MARATHON_IMAGE_DIR="${MARATHON_IMAGE_DIR:-${HOME}/Developer/Marathon-Image}"
APORTS_SRC="$MARATHON_IMAGE_DIR/packages"
MKOSI_PKG_DIR="$DURANIUM_DIR/mkosi.packages"

QMF_SRC="${QMF_SRC:-}"
QMF_GIT="${QMF_GIT:-https://code.qt.io/qt-labs/messagingframework.git}"
QMF_REF="${QMF_REF:-master}"
# code.qt.io disables cgit snapshot URLs; we always fetch via git on the host
# (network access from the host is reliable) and feed abuild a local tarball
# via SRCDEST so the container build is offline-after-clone.

[ -d "$APORTS_SRC/qmf" ] || {
    echo "error: qmf APKBUILD not found at $APORTS_SRC/qmf" >&2
    echo "Expected at $APORTS_SRC/qmf/APKBUILD" >&2
    exit 1
}
mkdir -p "$MKOSI_PKG_DIR"

PKGVER="$(grep -E '^pkgver=' "$APORTS_SRC/qmf/APKBUILD" | cut -d= -f2)"
PKGREL="$(grep -E '^pkgrel=' "$APORTS_SRC/qmf/APKBUILD" | cut -d= -f2)"
TARGET="qmf-${PKGVER}-r${PKGREL}.apk"

echo "+-- building $TARGET (and subpackages) --+"
echo "qmf src: ${QMF_SRC:-upstream code.qt.io tarball per APKBUILD}"
echo "output:  $MKOSI_PKG_DIR/qmf*.apk"

# Resolve QMF source — either honour QMF_SRC=/path or git-clone fresh.
if [ -z "$QMF_SRC" ]; then
    QMF_SRC="$(mktemp -d /tmp/qmf-src.XXXXXX)"
    trap 'rm -rf "$QMF_SRC"' EXIT
    echo "+ cloning $QMF_GIT @ $QMF_REF → $QMF_SRC"
    git clone --depth 1 --branch "$QMF_REF" "$QMF_GIT" "$QMF_SRC" 2>&1 | tail -3
fi
[ -d "$QMF_SRC" ] || {
    echo "error: QMF_SRC=$QMF_SRC does not exist" >&2
    exit 1
}
# :z (shared) per the convention in sibling builder scripts — multiple :Z
# mounts to the same container land on conflicting MCS labels under SELinux.
QMF_MOUNT_ARGS=(-v "$QMF_SRC:/qmf-src:z,ro")

# We don't bake QMF_SRC into the APKBUILD — the apkbuild always pulls
# from upstream. If QMF_SRC is set, we shim a local-tarball-from-checkout
# before abuild reaches network.
podman run --rm -i \
    -e PKGVER="$PKGVER" \
    -e PKGREL="$PKGREL" \
    -e TARGET="$TARGET" \
    -e QMF_LOCAL="/qmf-src" \
    -v "$APORTS_SRC:/aports-src:Z,ro" \
    -v "$MKOSI_PKG_DIR:/out:Z" \
    "${QMF_MOUNT_ARGS[@]}" \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail
apk add --no-cache --quiet abuild rsync samurai cmake build-base \
    qt6-qtbase-dev qt6-qtbase-sqlite qt6-qt5compat-dev \
    openssl-dev icu-dev tar 2>&1 | tail -2

mkdir -p /root/.abuild
abuild-keygen -a -n -q
KEY_PRIV=$(ls /root/.abuild/*.rsa | head -1)
cp "${KEY_PRIV}.pub" /etc/apk/keys/
echo "PACKAGER_PRIVKEY=$KEY_PRIV" > /etc/abuild.conf

mkdir -p /work/aports
rsync -a --checksum --no-times /aports-src/ /work/aports/
cd /work/aports/qmf

# Shim the QMF git checkout into a tarball at /work/aports/qmf/ so abuild's
# checksum + fetch both find it (APKBUILD-dir is checked before SRCDEST).
# The tarball must extract to a directory matching `builddir` from the
# APKBUILD (messagingframework-master).
LOCAL_TARBALL="/work/aports/qmf/qmf-${PKGVER}.tar.gz"
( cd /qmf-src/.. && \
  tar czf "$LOCAL_TARBALL" --transform "s,^$(basename /qmf-src),messagingframework-master," \
      "$(basename /qmf-src)" )

abuild -F checksum >/dev/null
abuild -d -F

ARCH_DIR="$(uname -m)"
for sub in qmf qmf-libs qmf-messageserver qmf-dev; do
    src="/root/packages/aports/$ARCH_DIR/${sub}-${PKGVER}-r${PKGREL}.apk"
    if [ -e "$src" ]; then
        cp "$src" /out/
        echo "  → /out/$(basename "$src")"
    fi
done
CSCRIPT

echo "+-- qmf built --+"
ls -la "$MKOSI_PKG_DIR"/qmf*.apk 2>/dev/null || true
