#!/usr/bin/env bash
# Resolve / clone the dependent repos a Marathon QEMU build needs.
# Sourced by build-qemu-image.sh. Sets the following exported vars
# on success:
#
#   MARATHON_SHELL_SRC      this repo's root
#   MARATHON_IMAGE_SRC      sibling clone of Marathon-Image (or env var)
#   MARATHON_BUILD_DIR      ~/.cache/marathon-build (overridable)
#   DURANIUM_DIR            $MARATHON_BUILD_DIR/duranium
#   MKOSI_BIN               mkosi executable (vendored or system)
#
# Auto-clone behaviour: if a dependency tree is missing, clone it
# rather than fail. Each clone uses --depth 1 and pins to a tracked
# branch so the build is reproducible.

set -euo pipefail

# Project-owned repo URLs. Override per-build with the matching
# MARATHON_*_GIT env var if you're working from a fork.
: "${MARATHON_IMAGE_GIT:=https://github.com/patrickjquinn/Marathon-Image.git}"
: "${MARATHON_IMAGE_REF:=main}"
: "${DURANIUM_GIT:=https://gitlab.postmarketos.org/postmarketOS/duranium.git}"
: "${DURANIUM_REF:=main}"
: "${MKOSI_GIT:=https://github.com/systemd/mkosi.git}"
: "${MKOSI_REF:=v25.3}"

: "${MARATHON_BUILD_DIR:=$HOME/.cache/marathon-build}"
mkdir -p "$MARATHON_BUILD_DIR"

# 1. Marathon-Image — sibling clone is the convention for local devs.
#    First check the env override, then check the conventional sibling
#    path next to this repo, then clone into $MARATHON_BUILD_DIR.
if [ -z "${MARATHON_IMAGE_SRC:-}" ]; then
    SIBLING="$(dirname "$MARATHON_SHELL_SRC")/Marathon-Image"
    if [ -d "$SIBLING/packages" ]; then
        MARATHON_IMAGE_SRC="$SIBLING"
    elif [ -d "$MARATHON_BUILD_DIR/Marathon-Image/packages" ]; then
        MARATHON_IMAGE_SRC="$MARATHON_BUILD_DIR/Marathon-Image"
    else
        echo "==> cloning Marathon-Image into $MARATHON_BUILD_DIR/Marathon-Image"
        git clone --depth 1 --branch "$MARATHON_IMAGE_REF" \
            "$MARATHON_IMAGE_GIT" \
            "$MARATHON_BUILD_DIR/Marathon-Image"
        MARATHON_IMAGE_SRC="$MARATHON_BUILD_DIR/Marathon-Image"
    fi
fi
export MARATHON_IMAGE_SRC
echo "==> Marathon-Image:  $MARATHON_IMAGE_SRC"

# 2. postmarketos-duranium — the mkosi image-build skeleton. We
#    clone it once and overlay Marathon's image-extras/ + mkosi.conf
#    patches via a sync step at build time (so upstream pulls remain
#    clean).
DURANIUM_DIR="$MARATHON_BUILD_DIR/duranium"
if [ ! -d "$DURANIUM_DIR/mkosi.images" ]; then
    echo "==> cloning postmarketos-duranium into $DURANIUM_DIR"
    git clone --depth 1 --branch "$DURANIUM_REF" \
        "$DURANIUM_GIT" "$DURANIUM_DIR"
fi
export DURANIUM_DIR
echo "==> duranium:        $DURANIUM_DIR"

# 3. mkosi — vendored at a known tag so the image build is
#    reproducible regardless of host package version.
MKOSI_SRC="$MARATHON_BUILD_DIR/mkosi-src"
if [ ! -d "$MKOSI_SRC/.git" ]; then
    echo "==> cloning mkosi $MKOSI_REF into $MKOSI_SRC"
    git clone --depth 1 --branch "$MKOSI_REF" \
        "$MKOSI_GIT" "$MKOSI_SRC"
fi
MKOSI_BIN="$MKOSI_SRC/bin/mkosi"
if [ ! -x "$MKOSI_BIN" ]; then
    echo "ERROR: $MKOSI_BIN not executable. Check the mkosi clone." >&2
    exit 1
fi
export MKOSI_BIN
echo "==> mkosi:           $MKOSI_BIN"

# 4. Overlay Marathon's image-extras/ onto $DURANIUM_DIR. We copy
#    rather than symlink so a `git status` in $DURANIUM_DIR stays
#    representative of upstream postmarketos-duranium — our customs
#    show up as uncommitted-but-tracked changes.
OVERLAY_SRC="$MARATHON_SHELL_SRC/scripts/qemu/duranium-overlay"
if [ -d "$OVERLAY_SRC" ]; then
    echo "==> overlaying Marathon customs from scripts/qemu/duranium-overlay/"
    rsync -a "$OVERLAY_SRC/" "$DURANIUM_DIR/"
fi

# 5. The build-*-apk.sh scripts under scripts/qemu/lib/ rely on the
#    MARATHON_IMAGE_DIR + MKOSI_PKG_DIR conventions. Export both.
export MARATHON_IMAGE_DIR="$MARATHON_IMAGE_SRC"
export MKOSI_PKG_DIR="$DURANIUM_DIR/mkosi.packages"
mkdir -p "$MKOSI_PKG_DIR"
