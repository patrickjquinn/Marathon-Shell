#!/usr/bin/env bash
# Shared Marathon image-build orchestrator. Per-device entry points
# (scripts/build-qemu-image.sh, build-oneplus6-image.sh, …) call this
# with the right $MARATHON_TARGET_DEVICE and any device-specific
# overlays. Don't run this directly unless you know which device you
# want — the wrappers are the discoverable surface.
#
# Stages, top to bottom:
#
#   1. Check host tools (podman, qemu, mkosi, EFI firmware) and print
#      install hints per package manager when missing.
#   2. Resolve / clone Marathon-Image, postmarketos-duranium, and a
#      pinned mkosi tag under ~/.cache/marathon-build/. Override the
#      location with MARATHON_BUILD_DIR=/path.
#   3. Build local apks in dependency order, skipping any already
#      cached in mkosi.packages/ (drop the .apk or set
#      FORCE_REBUILD=1 to invalidate):
#        qmf (libs + dev + messageserver)            ~ 5-10 min cold
#        marathon-base-config                        ~ 30 s
#        marathon-mail-oauth (Rust)                  ~ 1 min
#        marathon-shell                              ~ 2-3 min
#        postmarketos-ui-marathon                    ~ 30 s
#        device-<device>-marathon  (if present)      ~ 30 s
#   4. Run mkosi to bake the duranium image for the target device.
#      Image lands at ~/.cache/marathon-build/duranium/mkosi.output/.
#   5. Optional --boot / --verify post-bake steps (QEMU target only;
#      device images need flashing — see scripts/flash/).
#
# Inputs:
#   $1                      target device, e.g. "qemu-aarch64",
#                           "oneplus-enchilada", "purism-librem5".
#                           Maps to mkosi's `device-<NAME>` arg.
#                           Also picks up Marathon-Image's
#                           device-<NAME>-marathon overlay aport
#                           (when present).
#
# Env overrides:
#   MARATHON_IMAGE_GIT      upstream repo for Marathon-Image
#   MARATHON_IMAGE_REF      branch / tag (default main)
#   DURANIUM_GIT            upstream repo for postmarketos-duranium
#   DURANIUM_REF            branch / tag (default main)
#   MKOSI_REF               pinned mkosi tag (default v25.3)
#   MARATHON_BUILD_DIR      build-cache root (default ~/.cache/marathon-build)
#   MARATHON_IMAGE_SRC      use existing local Marathon-Image clone
#   FORCE_REBUILD           "1" → drop cached apks before rebuild

set -euo pipefail

# Resolve repo root (this script lives at $repo/scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MARATHON_SHELL_SRC="$(dirname "$SCRIPT_DIR")"
LIB="$SCRIPT_DIR/qemu/lib"

# Pluck the target device off the front of the arg list. Everything
# after it is forwarded to the option parser.
DEVICE="${1:-}"
if [ -z "$DEVICE" ] || [ "$DEVICE" = "-h" ] || [ "$DEVICE" = "--help" ]; then
    sed -n '2,/^set -euo pipefail/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi
shift
case "$DEVICE" in
    -*) echo "first arg must be the target device, not an option ($DEVICE)" >&2; exit 64 ;;
esac
export MARATHON_TARGET_DEVICE="$DEVICE"

# CLI parsing — keep it small.
#
#   --boot          (after the bake) launch a GL-accelerated interactive
#                   QEMU. Auto-picks GTK if $DISPLAY/$WAYLAND_DISPLAY are
#                   present, else VNC on 127.0.0.1:5905.
#   --verify        (after the bake) headless boot + run verify-mail.sh.
#                   Exits with verify-mail.sh's return code.
#   --boot-only     SKIP the build/bake stages; boot the already-baked
#                   image. Use for fast iteration after a build.
BOOT=0
BOOT_ONLY=0
VERIFY=0
for a in "$@"; do
    case "$a" in
        --boot)       BOOT=1 ;;
        --verify)     BOOT=1; VERIFY=1 ;;
        --boot-only)  BOOT_ONLY=1; BOOT=1 ;;
        -h|--help)
            sed -n '2,/^set -euo pipefail/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown arg: $a (try --help)" >&2; exit 64 ;;
    esac
done

echo "==> stage 1: host prerequisites"
bash "$LIB/check-host.sh"

echo "==> stage 2: dependency trees"
# shellcheck source=qemu/lib/setup-trees.sh
. "$LIB/setup-trees.sh"

# --boot-only short-circuits the build chain — straight to the
# launcher. Useful after a regular build to pop the QEMU window
# again without re-running mkosi.
if [ "$BOOT_ONLY" -eq 1 ]; then
    echo "==> --boot-only: skipping build, baking, and verify"
    exec bash "$LIB/boot-image.sh"
fi

# Helper — only build an apk if no matching file already exists in
# mkosi.packages/ (or FORCE_REBUILD=1). Each builder script writes
# its output via its own MKOSI_PKG_DIR env var that we already
# exported from setup-trees.sh.
build_if_missing() {
    local label="$1" glob="$2" script="$3"
    shift 3
    if [ "${FORCE_REBUILD:-0}" = "1" ]; then
        rm -f "$MKOSI_PKG_DIR"/$glob 2>/dev/null || true
    fi
    if compgen -G "$MKOSI_PKG_DIR/$glob" >/dev/null; then
        echo "==> $label: cached ($(ls -1 "$MKOSI_PKG_DIR"/$glob | tail -1 | xargs -n1 basename))"
        return 0
    fi
    echo "==> $label: building"
    MARATHON_SHELL_SRC="$MARATHON_SHELL_SRC" \
    MARATHON_IMAGE_DIR="$MARATHON_IMAGE_DIR" \
    DURANIUM_DIR="$DURANIUM_DIR" \
    MKOSI_PKG_DIR="$MKOSI_PKG_DIR" \
        bash "$script"
}

echo "==> stage 3: build apks"
build_if_missing "qmf"                       'qmf-libs-*.apk'                  "$LIB/build-qmf-apk.sh"
build_if_missing "marathon-base-config"      'marathon-base-config-*.apk'      "$LIB/build-marathon-base-config-apk.sh"
build_if_missing "marathon-mail-oauth"       'marathon-mail-oauth-*.apk'       "$LIB/build-marathon-mail-oauth-apk.sh"
build_if_missing "marathon-plymouth-theme"   'marathon-plymouth-theme-*.apk'   "$LIB/build-marathon-plymouth-theme-apk.sh"
build_if_missing "marathon-shell"            'marathon-shell-*.apk'            "$LIB/build-marathon-shell-apk.sh"
build_if_missing "postmarketos-ui-marathon"  'postmarketos-ui-marathon-*.apk'  "$LIB/build-postmarketos-ui-marathon-apk.sh"

# Device-specific Marathon overlay (pulls the upstream pmaports
# device-<NAME> plus Marathon's runtime stack as dependencies).
# QEMU has no overlay aport — its mkosi.images/base picks up the
# right packages directly. Real devices need this.
DEVICE_OVERLAY_APORT="$MARATHON_IMAGE_DIR/packages/device-$MARATHON_TARGET_DEVICE-marathon"
if [ -d "$DEVICE_OVERLAY_APORT" ]; then
    build_if_missing "device-$MARATHON_TARGET_DEVICE-marathon" \
        "device-$MARATHON_TARGET_DEVICE-marathon-*.apk" \
        "$LIB/build-device-marathon-apk.sh"
fi

echo "==> stage 4: bake image for device=$MARATHON_TARGET_DEVICE"
cd "$DURANIUM_DIR"
PATH="$(dirname "$MKOSI_BIN"):$PATH" \
    python3 scripts/build-image.py "device-$MARATHON_TARGET_DEVICE" ui-marathon

# mkosi names its output dir + raw artifacts by the device + ui
# pair. Find the freshly written one.
OUT_DIR_GLOB="$DURANIUM_DIR/mkosi.output/${MARATHON_TARGET_DEVICE}_marathon_edge"
LATEST_IMG=$(ls -1t "$OUT_DIR_GLOB"/${MARATHON_TARGET_DEVICE}_marathon_edge_*.raw 2>/dev/null \
    | grep -E "/${MARATHON_TARGET_DEVICE}_marathon_edge_[0-9]+\.raw$" | head -1)
[ -z "$LATEST_IMG" ] && { echo "no image produced for device-$MARATHON_TARGET_DEVICE" >&2; exit 1; }
echo "==> image ready: $LATEST_IMG"

# Post-bake device-conditional extraction. Some flash flows need
# artifacts the user shouldn't have to fish out of the .raw or apk
# cache by hand; we drop them next to the .raw so the per-device
# flash scripts can pick them up unambiguously.
case "$MARATHON_TARGET_DEVICE" in
    purism-librem5)
        # uuu (SDP → Fastboot) needs phone-boot.img on the HOST to
        # chainload u-boot into the phone's RAM before the eMMC is
        # reachable. Source of truth: the u-boot-librem5 apk that
        # mkosi already downloaded.
        UBOOT_APK=$(ls -1t "$DURANIUM_DIR"/mkosi.cache/*/cache/apk/u-boot-librem5-*.apk \
            "$DURANIUM_DIR"/mkosi.packages/u-boot-librem5-*.apk 2>/dev/null | head -1 || true)
        if [ -n "$UBOOT_APK" ]; then
            PHONE_BOOT="$OUT_DIR_GLOB/phone-boot.img"
            echo "==> extracting phone-boot.img from $(basename "$UBOOT_APK") to $PHONE_BOOT"
            # apk packages are gzipped tarballs; -O streams the entry to stdout.
            tar -xzOf "$UBOOT_APK" usr/share/u-boot/librem5/phone-boot.img > "$PHONE_BOOT" \
                || { echo "warn: phone-boot.img not in apk — uuu flash will need manual UBOOT=" >&2; rm -f "$PHONE_BOOT"; }
        else
            echo "warn: u-boot-librem5 apk not found in mkosi cache; flash-librem5.sh emmc will need UBOOT= set" >&2
        fi
        ;;
    oneplus-enchilada)
        # Duranium installs to a GPT inside the OP6's `userdata`
        # partition. The Android `boot` partition gets a separate
        # one-time-flash bootimg containing u-boot + initramfs +
        # EFI-loader. boot-deploy ran during the rootfs bake (the
        # device aport depends on mkbootimg + systemd-boot +
        # deviceinfo_generate_bootimg=true) and dropped boot.img-<kver>
        # under /boot/, which mkosi.repart's CopyFiles=/boot:/ landed
        # at the ESP root. Extract it next to the .raw so
        # flash-oneplus6.sh can pick it up without slicing the GPT
        # image at flash time.
        ESP_RAW=$(ls -1t "$OUT_DIR_GLOB"/${MARATHON_TARGET_DEVICE}_marathon_edge_*.esp.raw 2>/dev/null | head -1 || true)
        if [ -n "$ESP_RAW" ]; then
            if command -v mcopy >/dev/null; then
                BOOT_IMG="$OUT_DIR_GLOB/boot.img"
                # mcopy needs a target path that exists; -n overwrites.
                if mcopy -n -i "$ESP_RAW" ::boot.img-\* "$BOOT_IMG" 2>/dev/null; then
                    echo "==> extracted boot.img from $(basename "$ESP_RAW") to $BOOT_IMG"
                else
                    echo "warn: no boot.img-* in $(basename "$ESP_RAW"); flash-oneplus6.sh will need BOOT_IMG= set" >&2
                    rm -f "$BOOT_IMG"
                fi
            else
                echo "warn: mtools/mcopy not installed; cannot extract boot.img from ESP" >&2
                echo "      install with: apt install mtools  |  dnf install mtools" >&2
            fi
        else
            echo "warn: no *.esp.raw split artifact found (mkosi SplitArtifacts disabled?); cannot extract boot.img" >&2
        fi
        ;;
esac

# --boot / --verify only make sense for the QEMU target. Real
# devices need flashing — see scripts/flash/flash-<device>.sh.
if [ "$MARATHON_TARGET_DEVICE" != "qemu-aarch64" ]; then
    if [ "$BOOT" -eq 1 ] || [ "$VERIFY" -eq 1 ]; then
        echo "==> --boot/--verify are QEMU-only. Image is at:" >&2
        echo "    $LATEST_IMG" >&2
        echo "    Flash to hardware via scripts/flash/flash-$MARATHON_TARGET_DEVICE.sh" >&2
        exit 0
    fi
    echo "==> done. Flash to hardware:"
    echo "    scripts/flash/flash-$MARATHON_TARGET_DEVICE.sh ... $LATEST_IMG"
    exit 0
fi

if [ "$VERIFY" -eq 1 ]; then
    echo "==> stage 5: boot + verify"
    bash "$LIB/boot-and-verify-mail.sh"
elif [ "$BOOT" -eq 1 ]; then
    echo "==> stage 5: boot (Ctrl-C in this terminal stops QEMU)"
    exec bash "$LIB/boot-image.sh"
else
    echo "==> done. Boot with:"
    echo "    $0 --boot       (interactive shell window — GTK or VNC depending on host display)"
    echo "    $0 --verify     (headless boot + Mail verification harness)"
    echo "    $0 --boot-only  (skip rebuild, just launch QEMU again)"
fi
