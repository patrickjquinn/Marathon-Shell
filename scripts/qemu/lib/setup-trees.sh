#!/usr/bin/env bash
# Resolve / clone the dependent repos a Marathon QEMU build needs.
# Sourced by build-qemu-image.sh. Sets the following exported vars
# on success:
#
#   MARATHON_SHELL_SRC      this repo's root
#   MARATHON_IMAGE_SRC      in-tree packaging/ (or env var)
#   MARATHON_BUILD_DIR      ~/.cache/marathon-build (overridable)
#   DURANIUM_DIR            $MARATHON_BUILD_DIR/duranium
#   MKOSI_BIN               mkosi executable (vendored or system)
#
# Auto-clone behaviour: if a dependency tree is missing, clone it
# rather than fail. Each clone uses --depth 1 and pins to a tracked
# branch so the build is reproducible.

set -euo pipefail

# duranium + mkosi upstream URLs and pinned commits live in
# packaging/pipeline-patches/bootstrap.sh — the patch series and the
# commit it applies to have to move together, so they are stated once.

: "${MARATHON_BUILD_DIR:=$HOME/.cache/marathon-build}"
mkdir -p "$MARATHON_BUILD_DIR"

# 1. Packaging (aports + duranium patch series) is in-tree since the
#    Marathon-Image merge. The env override stays honoured so a build
#    can still be pointed at an external checkout.
: "${MARATHON_IMAGE_SRC:=$MARATHON_SHELL_SRC/packaging}"
if [ ! -d "$MARATHON_IMAGE_SRC/packages" ]; then
    echo "ERROR: no packages/ under $MARATHON_IMAGE_SRC" >&2
    exit 1
fi
export MARATHON_IMAGE_SRC
echo "==> packaging:       $MARATHON_IMAGE_SRC"

# 2. duranium + mkosi. Bootstrapped as one unit by the patch series'
#    own script, so the tree the build uses is the tree the patches were
#    written against. This previously cloned upstream main bare and
#    relied on the overlay rsync below for Marathon's divergence — but
#    the overlay only ever carried a stale subset (a 309-line
#    mkosi.finalize against the patched 954-line one), so every image
#    built here was missing the Librem 5 boot composer, the Pi 5 boot
#    chain, and the loader-entry synthesis from patch 0007.
DURANIUM_DIR="$MARATHON_BUILD_DIR/duranium"
"$MARATHON_IMAGE_SRC/pipeline-patches/bootstrap.sh" "$MARATHON_BUILD_DIR"
export DURANIUM_DIR
echo "==> duranium:        $DURANIUM_DIR (upstream pin + Marathon patches)"

# 3. mkosi — bootstrap.sh stages a pinned checkout next to duranium.
#    Resolution order: $MKOSI_SRC override, bootstrap's own checkout,
#    then the canonical dev location.
if [ -z "${MKOSI_SRC:-}" ]; then
    if [ -x "$MARATHON_BUILD_DIR/mkosi-src/bin/mkosi" ]; then
        MKOSI_SRC="$MARATHON_BUILD_DIR/mkosi-src"
    elif [ -x "$HOME/duranium-build/mkosi-src/bin/mkosi" ]; then
        MKOSI_SRC="$HOME/duranium-build/mkosi-src"
    else
        echo "ERROR: no mkosi checkout found. Run" >&2
        echo "  $MARATHON_IMAGE_SRC/pipeline-patches/bootstrap.sh $MARATHON_BUILD_DIR" >&2
        exit 1
    fi
fi
MKOSI_BIN="$MKOSI_SRC/bin/mkosi"
if [ ! -x "$MKOSI_BIN" ]; then
    echo "ERROR: $MKOSI_BIN not executable. Check the mkosi checkout." >&2
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
            echo "    $OVERLAY_SRC/ or 'git stash' them in the duranium tree."
            # NOTE: single quotes above are deliberate. Backticks inside a
            # double-quoted echo are command substitution, not literal text —
            # the earlier `git stash` here actually RAN git stash against the
            # user's working tree every time this warning fired.
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

    # ── Optional WiFi pre-seed ────────────────────────────────
    # If the operator has dropped a wifi-preset.conf with SSID/PSK
    # next to this lib script, generate a NetworkManager keyfile and
    # land it in the per-image mkosi.skeleton so it ends up at
    # /etc/NetworkManager/system-connections/ in the baked image.
    # NetworkManager auto-loads it at boot and the device joins WiFi
    # without needing OOBE on first power-on. INSECURE — the PSK
    # reaches the image in cleartext. Use only for dev/QA images
    # against networks you control; never ship a release image
    # built with this file present.
    WIFI_PRESET="$MARATHON_SHELL_SRC/scripts/qemu/wifi-preset.conf"
    NM_SKEL_DIR="$DURANIUM_DIR/mkosi.images/base/mkosi.skeleton/etc/NetworkManager/system-connections"
    NM_KEYFILE="$NM_SKEL_DIR/marathon-dev.nmconnection"
    # Always clear any stale keyfile first — protects against the case
    # where the operator removes wifi-preset.conf but the previously-
    # generated keyfile lingers in the skeleton and gets baked anyway.
    rm -f "$NM_KEYFILE"
    if [ -f "$WIFI_PRESET" ]; then
        # shellcheck disable=SC1090
        . "$WIFI_PRESET"
        if [ -n "${SSID:-}" ] && [ -n "${PSK:-}" ]; then
            : "${INTERFACE_NAME:=wlan0}"
            mkdir -p "$NM_SKEL_DIR"
            # NetworkManager refuses keyfiles unless mode is 0600.
            cat > "$NM_KEYFILE" <<EOF
[connection]
id=marathon-dev
type=wifi
interface-name=$INTERFACE_NAME
autoconnect=true

[wifi]
mode=infrastructure
ssid=$SSID

[wifi-security]
key-mgmt=wpa-psk
psk=$PSK

[ipv4]
method=auto

[ipv6]
method=auto
EOF
            chmod 0600 "$NM_KEYFILE"
            echo "==> WiFi pre-seed: baked nmconnection for SSID '$SSID' (mode 0600)"
        else
            echo "==> WARNING: $WIFI_PRESET present but SSID or PSK empty — skipping WiFi pre-seed"
        fi
        unset SSID PSK INTERFACE_NAME
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
