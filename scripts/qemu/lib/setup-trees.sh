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

# 3. mkosi — duranium needs `Distribution=postmarketos` support, which
#    vanilla upstream mkosi DOES NOT carry; pmOS maintains a fork.
#    Resolution priority:
#      (a) $MKOSI_SRC env override (user pin)
#      (b) ~/duranium-build/mkosi-src if it has a postmarketos
#          distribution module — that's the canonical Marathon dev
#          location per project memory (feedback_duranium_primary).
#      (c) Fall back to cloning the upstream tag at $MKOSI_GIT —
#          will only work for non-postmarketos targets.
if [ -z "${MKOSI_SRC:-}" ]; then
    if [ -f "$HOME/duranium-build/mkosi-src/mkosi/distribution/postmarketos.py" ] \
       || [ -f "$HOME/duranium-build/mkosi-src/mkosi/distributions/postmarketos.py" ]; then
        MKOSI_SRC="$HOME/duranium-build/mkosi-src"
        echo "==> mkosi: using duranium-build fork at $MKOSI_SRC (has postmarketos support)"
    else
        MKOSI_SRC="$MARATHON_BUILD_DIR/mkosi-src"
    fi
fi
if [ ! -d "$MKOSI_SRC/.git" ]; then
    echo "==> cloning mkosi $MKOSI_REF into $MKOSI_SRC"
    echo "    NOTE: upstream v25.3 has no Distribution=postmarketos. If the bake step" >&2
    echo "    fails with that error, install pmOS's mkosi fork at ~/duranium-build/mkosi-src." >&2
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
    # Safety check: warn if the duranium tree's copy of an overlay file
    # has DIVERGED from the overlay source. Anyone editing the duranium
    # tree directly (the natural mental model — "the build uses
    # ~/duranium-build/duranium so I'll edit there") gets their changes
    # silently overwritten by this rsync. r80–r87 lost SEVEN rounds of
    # postinst fixes to this exact trap. Warn so it can't happen again
    # without the operator at least seeing it.
    if [ -d "$DURANIUM_DIR" ]; then
        DIVERGED=$(
            cd "$OVERLAY_SRC" && find . -type f -print0 |
                while IFS= read -r -d '' f; do
                    tree_file="$DURANIUM_DIR/$f"
                    overlay_file="$OVERLAY_SRC/$f"
                    if [ -f "$tree_file" ] && ! cmp -s "$tree_file" "$overlay_file"; then
                        echo "$f"
                    fi
                done
        )
        if [ -n "$DIVERGED" ]; then
            echo "==> WARNING: duranium tree has edits that will be overwritten by the overlay:"
            printf '    %s\n' $DIVERGED
            echo "    These edits will NOT land in the image. Either copy them into"
            echo "    $OVERLAY_SRC/ or `git stash` them in the duranium tree."
        fi
    fi

    echo "==> overlaying Marathon customs from scripts/qemu/duranium-overlay/"
    rsync -a "$OVERLAY_SRC/" "$DURANIUM_DIR/"

    # Patch duranium's top-level mkosi.conf RootPassword.
    #
    # Upstream postmarketos-duranium ships RootPassword=hashed:! (locked)
    # so production images can't be ssh'd into with a default credential.
    # Per the mkosi v25 changelog, RootPassword is a "universal" setting
    # that can only be specified at the top-level conf — per-image
    # mkosi.images/base/mkosi.conf overrides are silently ignored.
    #
    # The marathon overlay's RootPassword override therefore has to land
    # in the cache's top-level mkosi.conf via this sed. Hash below is
    # sha512crypt of "marathon" with salt "marathondev" (generated via
    # `openssl passwd -6 -salt marathondev marathon`). DEV/QA ONLY —
    # replace with hashed:! before shipping a release image.
    DURANIUM_TOP_CONF="$DURANIUM_DIR/mkosi.conf"
    if [ -f "$DURANIUM_TOP_CONF" ] && \
       grep -q '^RootPassword=hashed:' "$DURANIUM_TOP_CONF"; then
        echo "==> patching $DURANIUM_TOP_CONF — RootPassword to dev hash 'marathon'"
        sed -i 's|^RootPassword=hashed:.*$|RootPassword=hashed:$6$marathondev$HzxHox2zMxplL5HL5br6IYDb4oQBp3QBfrXebGDGyrf9x0UY7Np6mHN/kjTb5.5iN7R4.U8hD9FYsdLC7yunq/|' \
            "$DURANIUM_TOP_CONF"
    fi
fi

# Mirror the working duranium-build's `marathon-extras/` directory into
# our cache. The mkosi.postinst (overlay) references `/work/src/marathon-
# extras/...` paths (xdg-terminal-exec, flathub.gpg, marathon-store-*,
# StoreApp.qml). mkosi auto-bind-mounts the conf's source tree at
# /work/src/, so this dir needs to be present alongside mkosi.conf to be
# visible in the chroot. Per feedback_duranium_primary the canonical
# location is $HOME/duranium-build/duranium/marathon-extras/.
USER_MARATHON_EXTRAS="$HOME/duranium-build/duranium/marathon-extras"
if [ -d "$USER_MARATHON_EXTRAS" ] && [ ! -d "$DURANIUM_DIR/marathon-extras" ]; then
    echo "==> syncing marathon-extras/ from $USER_MARATHON_EXTRAS"
    rsync -a "$USER_MARATHON_EXTRAS/" "$DURANIUM_DIR/marathon-extras/"
fi

# 5. The build-*-apk.sh scripts under scripts/qemu/lib/ rely on the
#    MARATHON_IMAGE_DIR + MKOSI_PKG_DIR conventions. Export both.
export MARATHON_IMAGE_DIR="$MARATHON_IMAGE_SRC"
export MKOSI_PKG_DIR="$DURANIUM_DIR/mkosi.packages"
mkdir -p "$MKOSI_PKG_DIR"
