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
#
# Cache invalidation: $glob is a wildcard like `marathon-shell-*.apk`,
# so any older version satisfies the existence check by default. The
# optional $aport_apkbuild arg makes the helper compare the CURRENT
# pkgver-pkgrel from the source APKBUILD against the cached filename
# — if they differ, the cache is stale and we rebuild. Without this
# guard a pkgrel bump in the source would silently fall back to the
# previous build (the bug that shipped r2 on a r5 source twice in a
# row).
build_if_missing() {
    local label="$1" glob="$2" script="$3" aport_apkbuild="${4:-}"
    if [ "${FORCE_REBUILD:-0}" = "1" ]; then
        rm -f "$MKOSI_PKG_DIR"/$glob 2>/dev/null || true
    fi

    # Stale-cache check: if the caller passed an APKBUILD path, derive
    # the expected filename from its pkgver+pkgrel and only treat the
    # cache as warm when that exact apk is present.
    if [ -n "$aport_apkbuild" ] && [ -f "$aport_apkbuild" ]; then
        local pkgver pkgrel pkgname expected
        pkgver=$(grep -E '^pkgver=' "$aport_apkbuild" | head -1 | cut -d= -f2)
        pkgrel=$(grep -E '^pkgrel=' "$aport_apkbuild" | head -1 | cut -d= -f2)
        pkgname=$(grep -E '^pkgname=' "$aport_apkbuild" | head -1 | cut -d= -f2)
        if [ -n "$pkgver" ] && [ -n "$pkgrel" ] && [ -n "$pkgname" ]; then
            expected="${pkgname}-${pkgver}-r${pkgrel}.apk"
            if [ -f "$MKOSI_PKG_DIR/$expected" ]; then
                echo "==> $label: cached ($expected)"
                return 0
            fi
            if compgen -G "$MKOSI_PKG_DIR/$glob" >/dev/null; then
                local stale
                stale=$(ls -1 "$MKOSI_PKG_DIR"/$glob | xargs -n1 basename | tr '\n' ' ')
                echo "==> $label: cache STALE (want $expected, have $stale) — rebuilding"
                rm -f "$MKOSI_PKG_DIR"/$glob
            fi
        fi
    elif compgen -G "$MKOSI_PKG_DIR/$glob" >/dev/null; then
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
APORTS_DIR="$MARATHON_IMAGE_DIR/packages"
build_if_missing "qmf"                       'qmf-libs-*.apk'                 "$LIB/build-qmf-apk.sh"                       "$APORTS_DIR/qmf/APKBUILD"
build_if_missing "marathon-base-config"      'marathon-base-config-*.apk'     "$LIB/build-marathon-base-config-apk.sh"      "$APORTS_DIR/marathon-base-config/APKBUILD"
build_if_missing "marathon-mail-oauth"       'marathon-mail-oauth-*.apk'      "$LIB/build-marathon-mail-oauth-apk.sh"       "$APORTS_DIR/marathon-mail-oauth/APKBUILD"
build_if_missing "marathon-plymouth-theme"   'marathon-plymouth-theme-*.apk'  "$LIB/build-marathon-plymouth-theme-apk.sh"   "$APORTS_DIR/marathon-plymouth-theme/APKBUILD"
build_if_missing "marathon-shell"            'marathon-shell-*.apk'           "$LIB/build-marathon-shell-apk.sh"            "$APORTS_DIR/marathon-shell/APKBUILD"
build_if_missing "postmarketos-ui-marathon"  'postmarketos-ui-marathon-*.apk' "$LIB/build-postmarketos-ui-marathon-apk.sh"  "$APORTS_DIR/postmarketos-ui-marathon/APKBUILD"

# Device-specific Marathon overlay (pulls the upstream pmaports
# device-<NAME> plus Marathon's runtime stack as dependencies).
# QEMU has no overlay aport — its mkosi.images/base picks up the
# right packages directly. Real devices need this.
DEVICE_OVERLAY_APORT="$APORTS_DIR/device-$MARATHON_TARGET_DEVICE-marathon"
if [ -d "$DEVICE_OVERLAY_APORT" ]; then
    build_if_missing "device-$MARATHON_TARGET_DEVICE-marathon" \
        "device-$MARATHON_TARGET_DEVICE-marathon-*.apk" \
        "$LIB/build-device-marathon-apk.sh" \
        "$DEVICE_OVERLAY_APORT/APKBUILD"
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
    raspberry-pi*|rpi*)
        # Pi firmware boots: kernel + initrd + cmdline.txt direct from
        # the ESP root (no UEFI on Pi 5, so systemd-stub never runs).
        # mkosi.finalize wrote /boot/cmdline.txt; the kernel landed at
        # /vmlinuz-rpi via mkosi.repart's CopyFiles=/boot:/. The initrd
        # is produced separately by mkosi's initrd sub-image and gets
        # dropped at <ESP>/<image-id>/initrd by mkosi's UKI pipeline —
        # NOT at the root where the Pi firmware expects it. Promote it.
        #
        # We rewrite the .raw directly via mtools' @@offset syntax (the
        # FAT inside the GPT-partitioned image), not the .esp.raw split
        # — that split isn't what gets flashed.
        if ! command -v mcopy >/dev/null || ! command -v sfdisk >/dev/null; then
            echo "warn: mtools/sfdisk missing; cannot promote initrd to ESP root" >&2
            echo "      install with: apt install mtools util-linux  |  dnf install mtools util-linux" >&2
        else
            # Locate ESP partition byte offset inside the .raw via sfdisk.
            # sfdisk -d formats each partition line as
            #   /path/to.raw1 : start=    2048, size=    2097152, type=C12A...
            # The whitespace between `start=` and its value breaks awk-by-field
            # parsing, so pull each value with a regex on the matching line.
            ESP_OFFSET_SECTORS=$(sfdisk -d "$LATEST_IMG" \
                | grep -i 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B' \
                | sed -E 's/.*start=[[:space:]]*([0-9]+).*/\1/')
            SECTOR_SIZE=$(sfdisk -d "$LATEST_IMG" \
                | sed -nE 's/^sector-size:[[:space:]]*([0-9]+).*/\1/p')
            if [ -z "${ESP_OFFSET_SECTORS:-}" ] || [ -z "${SECTOR_SIZE:-}" ]; then
                echo "warn: could not parse ESP offset from $LATEST_IMG; skipping initrd promotion" >&2
            else
                ESP_OFFSET_BYTES=$(( ESP_OFFSET_SECTORS * SECTOR_SIZE ))
                # mtools uses image@@offset to scope to the FAT inside.
                ESP_AT="$LATEST_IMG@@$ESP_OFFSET_BYTES"
                # Build a tiny cpio drop-in that overrides
                # systemd-repart.service's ExecStart to specify the boot disk
                # explicitly. Pi-firmware boot has no systemd-stub so
                # LoaderDevicePartUUID is unset; upstream systemd-repart
                # returns 76 ("root block device not found") which is in
                # SuccessExitStatus=76 — service "succeeds" silently, no
                # partition gets created, and initrd-root-fs.target hangs
                # forever waiting for /dev/disk/by-partlabel/pmOS_root before
                # systemd drops to emergency mode. Found via on-hardware
                # boot diagnosis 2026-05-20.
                REPART_FIX_CPIO=""
                REPART_FIX_DIR=$(mktemp -d --suffix=.cm5-repart-fix)
                if [ -n "$REPART_FIX_DIR" ]; then
                    mkdir -p "$REPART_FIX_DIR/etc/systemd/system/systemd-repart.service.d"
                    cat > "$REPART_FIX_DIR/etc/systemd/system/systemd-repart.service.d/pi-disk.conf" <<'DROPIN'
# Pi-firmware boot has no LoaderDevicePartUUID (no systemd-stub in path).
# Tell systemd-repart which disk to target explicitly. /dev/mmcblk0 is
# the SD card on Pi 5 (BCM2712 boot media via the SoC SD controller).
[Service]
ExecStart=
ExecStart=systemd-repart --dry-run=no /dev/mmcblk0
DROPIN
                    REPART_FIX_CPIO=$(mktemp --suffix=.cpio.gz)
                    (cd "$REPART_FIX_DIR" && find etc -print0 \
                        | cpio -o --null -H newc 2>/dev/null \
                        | gzip -c) > "$REPART_FIX_CPIO"
                    rm -rf "$REPART_FIX_DIR"
                fi

                # Stitch base initrd + kernel-modules initrd. The standalone
                # initrd.cpio.gz in the output dir is ONLY the base (systemd +
                # generators + veritysetup + libs). mkosi packs the kernel-
                # modules cpio archive into the UKI's .initrd section
                # because systemd-stub concatenates them at boot — but on
                # Pi 5 we don't go through the UKI, so we have to do the
                # concatenation here. Without this, dm-verity (=m) is missing
                # and verity composition fails with
                # "Cannot use device verity for verification: Operation not
                # supported" right after "Welcome to systemd!" — boot hangs.
                #
                # Linux supports concatenated initramfs natively: each piece
                # can be gzip/xz/zstd or raw cpio. We gzip the modules cpio
                # (gives ~10% size win) and append to the base.
                BASE_INITRD="$OUT_DIR_GLOB/initrd.cpio.gz"
                UKI_EFI=$(ls -1t "$OUT_DIR_GLOB"/base_*.efi 2>/dev/null | head -1)
                STITCHED=$(mktemp --suffix=.initramfs)
                if [ -f "$BASE_INITRD" ] && [ -n "$UKI_EFI" ] && [ -f "$UKI_EFI" ] && command -v objcopy >/dev/null; then
                    MODULES_CPIO=$(mktemp --suffix=.cpio)
                    # objcopy --dump-section writes the section to the first
                    # positional arg, but also REQUIRES an outfile positional
                    # arg for the (uncopied) PE rewrite. Passing /dev/null
                    # works but objcopy emits "file truncated" on stderr AND
                    # exits 1 — under set -e that kills the script. Use a
                    # throwaway tempfile and discard it after.
                    OBJCOPY_TRASH=$(mktemp --suffix=.efi-trash)
                    objcopy --dump-section ".initrd=$MODULES_CPIO" "$UKI_EFI" "$OBJCOPY_TRASH" 2>/dev/null || true
                    rm -f "$OBJCOPY_TRASH"
                    if [ -s "$MODULES_CPIO" ]; then
                        # Concatenate: base initramfs + kernel modules cpio.gz
                        # + the tiny repart drop-in cpio.gz (if produced).
                        # Linux kernel handles concatenated initramfs natively
                        # — each piece can be independently compressed and
                        # unpacks in order.
                        if [ -n "${REPART_FIX_CPIO:-}" ] && [ -s "$REPART_FIX_CPIO" ]; then
                            cat "$BASE_INITRD" <(gzip -c "$MODULES_CPIO") "$REPART_FIX_CPIO" > "$STITCHED"
                            REPART_SZ=$(stat -c%s "$REPART_FIX_CPIO")
                            echo "==> stitched base ($(stat -c%s "$BASE_INITRD") B) + modules ($(stat -c%s "$MODULES_CPIO") B raw) + repart-fix ($REPART_SZ B) -> $(stat -c%s "$STITCHED") B"
                        else
                            cat "$BASE_INITRD" <(gzip -c "$MODULES_CPIO") > "$STITCHED"
                            echo "==> stitched base ($(stat -c%s "$BASE_INITRD") B) + modules ($(stat -c%s "$MODULES_CPIO") B raw) -> $(stat -c%s "$STITCHED") B"
                        fi
                    else
                        echo "warn: could not extract .initrd from $UKI_EFI; promoting base initrd alone (dm-verity will fail)" >&2
                        cp "$BASE_INITRD" "$STITCHED"
                    fi
                    rm -f "$MODULES_CPIO" "${REPART_FIX_CPIO:-}"
                elif mdir -i "$ESP_AT" "::$MARATHON_TARGET_DEVICE/initrd" >/dev/null 2>&1; then
                    # Fallback: promote the in-ESP per-device initrd. Same
                    # missing-modules bug as before but at least something.
                    mcopy -n -i "$ESP_AT" "::$MARATHON_TARGET_DEVICE/initrd" "$STITCHED"
                    echo "warn: stitching skipped (no UKI?); kernel modules will not be in initramfs" >&2
                else
                    echo "warn: no base initrd available — Pi firmware will fail to load initramfs" >&2
                    rm -f "$STITCHED"; STITCHED=""
                fi

                if [ -n "${STITCHED:-}" ] && [ -f "$STITCHED" ]; then
                    # Replace existing initramfs-rpi if present, then write.
                    mdel -i "$ESP_AT" ::initramfs-rpi 2>/dev/null || true
                    mcopy -n -i "$ESP_AT" "$STITCHED" '::initramfs-rpi'
                    rm -f "$STITCHED"
                    INITRD_SIZE=$(mdir -i "$ESP_AT" '::initramfs-rpi' 2>/dev/null \
                        | awk '/initramfs-rpi/ {print $(NF-1); exit}')
                    echo "==> wrote /initramfs-rpi to ESP ($INITRD_SIZE bytes)"

                    # Rewrite cmdline.txt with the bits the Pi-firmware boot
                    # chain needs to actually reach Marathon. Two findings
                    # from QEMU validation (commit history for details):
                    #
                    # 1. duranium's mount-subpartitions.service is OP6-only
                    #    (it parses the LoaderDevicePartUUID EFI variable
                    #    set by systemd-boot, which Pi firmware doesn't
                    #    provide). Without masking, the service fails and
                    #    OnFailure=emergency.target stops the boot.
                    #
                    # 2. systemd-veritysetup-generator needs an explicit
                    #    usrhash= on cmdline when there's no
                    #    LoaderDevicePartUUID — otherwise it can't locate
                    #    the verity pair on disk. The hash is the two
                    #    discoverable-partition UUIDs concatenated, per
                    #    the discoverable-partitions spec.
                    VTY_UUID=$(sfdisk -d "$LATEST_IMG" \
                        | grep -iE 'usr-verity|6E11A4E7-FBCA-4DED' \
                        | sed -E 's/.*uuid=([0-9a-fA-F-]+).*/\1/' \
                        | tr '[:upper:]' '[:lower:]' | tr -d '-')
                    USR_UUID=$(sfdisk -d "$LATEST_IMG" \
                        | grep -iE 'B0E01050-EE5F-4390-949A-9101B17104E9' \
                        | sed -E 's/.*uuid=([0-9a-fA-F-]+).*/\1/' \
                        | tr '[:upper:]' '[:lower:]' | tr -d '-')
                    if [ -n "$VTY_UUID" ] && [ -n "$USR_UUID" ]; then
                        # Discoverable Partitions Spec encoding:
                        #   first  16 bytes of roothash → DATA partition's PartUUID
                        #   second 16 bytes of roothash → VERITY (hash) partition's PartUUID
                        # systemd-veritysetup-generator parses usrhash= and treats
                        # the first half as data, second as hash. Empirically
                        # verified via veritysetup verify against the source files.
                        # (Diagnosed 2026-05-20 after an on-hardware boot hung in
                        # initramfs waiting for /dev/mapper/usr because we had this
                        # backwards.)
                        USRHASH="${USR_UUID}${VTY_UUID}"
                        # consoleblank=0 stops the kernel from blanking the
                        # framebuffer console after 10 min idle. Marathon's
                        # DisplayPolicyController already manages screen-off
                        # via KMS DPMS, but the kernel's tty1 blanker fights
                        # it and can leave the panel powered-down even when
                        # the shell wants it on (reported on Hackberry CM5
                        # 2026-05-20).
                        # quiet+splash hand the framebuffer to plymouth so
                        # the Marathon boot logo replaces the kernel-log
                        # scroll. plymouth.ignore-serial-consoles leaves
                        # the serial console available for debug while
                        # plymouth still owns the tty1 framebuffer.
                        # plymouth.splash=marathon forces the Marathon
                        # theme on the very first boot — /etc/plymouth/
                        # plymouthd.conf is provisioned by tmpfiles AFTER
                        # plymouth has already started, so without this
                        # the first boot would fall back to whatever
                        # /usr/share/plymouth/plymouthd.defaults points
                        # at (pmOS's green-triangle default).
                        CMDLINE="console=tty1 console=serial0,115200 rw quiet splash plymouth.ignore-serial-consoles plymouth.splash=marathon consoleblank=0 rd.systemd.mask=mount-subpartitions.service systemd.mask=mount-subpartitions.service rd.systemd.mask=systemd-cryptsetup@pmOS_root.service systemd.mask=systemd-cryptsetup@pmOS_root.service usrhash=${USRHASH}"
                        TMP_CMDLINE=$(mktemp --suffix=.cmdline.txt)
                        printf '%s\n' "$CMDLINE" > "$TMP_CMDLINE"
                        mdel -i "$ESP_AT" ::cmdline.txt 2>/dev/null || true
                        mcopy -n -i "$ESP_AT" "$TMP_CMDLINE" '::cmdline.txt'
                        rm -f "$TMP_CMDLINE"
                        echo "==> wrote /cmdline.txt with usrhash=${USRHASH:0:16}…"
                    else
                        echo "warn: could not extract verity partition UUIDs from $LATEST_IMG; cmdline.txt unchanged (verity will not compose)" >&2
                    fi
                else
                    echo "warn: no $MARATHON_TARGET_DEVICE/initrd in ESP — Pi firmware will fail to load initramfs" >&2
                fi
            fi
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
