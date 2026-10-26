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
# ALPINE_MIRROR=https://mirrors.edge.kernel.org/alpine (for example) builds
# against that mirror instead of the CDN, for when edge is mid-rebuild.
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

# The complete Rust workspace can exceed a 6 GiB tmpfs as new daemons are
# added. CI can keep the fast tmpfs default; local device builds may point this
# at a disk-backed scratch directory and remove it after packaging.
WORK_MOUNT_ARGS=(--tmpfs "/work:rw,exec,size=${MARATHON_APK_TMPFS_SIZE:-6g}")
if [ -n "${MARATHON_APK_WORK_DIR:-}" ]; then
    mkdir -p "$MARATHON_APK_WORK_DIR"
    WORK_MOUNT_ARGS=(-v "$MARATHON_APK_WORK_DIR:/work:z")
fi

# Mail's OAuth client IDs, when this checkout has them (oauth-clients.env).
OAUTH_ENV="${MARATHON_SHELL_SRC:+$MARATHON_SHELL_SRC/crates/marathon-maild/oauth-clients.env}"
# shellcheck disable=SC1090
[ -n "$OAUTH_ENV" ] && [ -f "$OAUTH_ENV" ] && . "$OAUTH_ENV"

# CMAKE_BUILD_PARALLEL_LEVEL / CARGO_BUILD_JOBS cap the build's jobs, for
# building beside another heavy build.
JOB_ENV_ARGS=()
for v in CMAKE_BUILD_PARALLEL_LEVEL CARGO_BUILD_JOBS; do
    if [ -n "${!v:-}" ]; then JOB_ENV_ARGS+=(-e "$v=${!v}"); fi
done

podman run --rm -i \
    "${WORK_MOUNT_ARGS[@]}" \
    -e MARATHON_DEFAULT_GOOGLE_CLIENT_ID="${MARATHON_DEFAULT_GOOGLE_CLIENT_ID:-}" \
    -e MARATHON_DEFAULT_MICROSOFT_CLIENT_ID="${MARATHON_DEFAULT_MICROSOFT_CLIENT_ID:-}" \
    -e MARATHON_SHELL_GIT="$MARATHON_SHELL_GIT" \
    -e MARATHON_SHELL_REF="$MARATHON_SHELL_REF" \
    -e USE_LOCAL_SHELL_SRC="$([ -n "$MARATHON_SHELL_SRC" ] && echo 1 || echo 0)" \
    -e PKGVER="$PKGVER" \
    -e PKGREL="$PKGREL" \
    -e TARGET="$TARGET" \
    -e ALPINE_MIRROR="${ALPINE_MIRROR:-}" \
    "${JOB_ENV_ARGS[@]}" \
    -v "$APORTS_SRC:/aports-src:z,ro" \
    -v "$MKOSI_PKG_DIR:/out:z" \
    -v "$MKOSI_PKG_DIR:/local-apks:z,ro" \
    "${SHELL_MOUNT_ARGS[@]}" \
    alpine:edge sh -s <<'CSCRIPT'
set -euo pipefail
# edge is sometimes caught mid-rebuild on the CDN (a library bumped before
# its dependents are rebuilt), which makes the dependency set unsatisfiable.
# ALPINE_MIRROR points at a mirror that hasn't synced the half-done state yet.
if [ -n "$ALPINE_MIRROR" ]; then
    printf '%s/edge/main\n%s/edge/community\n' "$ALPINE_MIRROR" "$ALPINE_MIRROR" \
        > /etc/apk/repositories
fi
apk add --no-cache --quiet \
    abuild rsync curl ca-certificates git \
    cargo cmake samurai build-base \
    qt6-qtbase-dev qt6-qtdeclarative-dev qt6-qtwayland-dev \
    qt6-qtwebengine-dev qt6-qtmultimedia-dev qt6-qtsensors-dev \
    qt6-qtsvg-dev qt6-qtlocation-dev qt6-qtpositioning-dev \
    qt6-qtspeech-dev qt6-qttools-dev \
    hunspell-dev pulseaudio-dev wayland-dev wayland-protocols \
    mesa-dev dbus-dev eudev-dev libinput-dev linux-pam-dev 2>&1 | tail -3 || true

KEEL_SILICA_APK="$(ls -1v /local-apks/keel-silica-[0-9]*.apk 2>/dev/null | tail -1 || true)"
KEEL_SILICA_DEV_APK="$(ls -1v /local-apks/keel-silica-dev-*.apk 2>/dev/null | tail -1 || true)"
if [ -z "$KEEL_SILICA_APK" ]; then
    echo "error: keel-silica-*.apk not found under /local-apks (run build-keel-silica-apk.sh)" >&2
    exit 1
fi
apk add --no-cache --quiet --allow-untrusted "$KEEL_SILICA_APK" $KEEL_SILICA_DEV_APK
echo "keel-silica installed from $KEEL_SILICA_APK"

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
          --exclude='.git' --exclude='/build' --exclude='/build-*' \
          --exclude='.cache' --exclude='packaging' \
          --exclude='.marathon-apk-work' --exclude='crates/target' \
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

cd /work/aports/marathon-shell
abuild -F checksum >/dev/null
abuild -d -F

cp "/root/packages/aports/aarch64/${TARGET}" "/out/${TARGET}"
echo "wrote /out/${TARGET}"
ICON_APK="$(echo "$TARGET" | sed "s/^marathon-shell-/marathon-icon-theme-/")"
cp "/root/packages/aports/aarch64/${ICON_APK}" "/out/${ICON_APK}"
echo "wrote /out/${ICON_APK}"
CSCRIPT

echo "+-- done: $MKOSI_PKG_DIR/$TARGET --+"
ls -l "$MKOSI_PKG_DIR/$TARGET"
