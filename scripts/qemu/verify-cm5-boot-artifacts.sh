#!/usr/bin/env bash
# verify-cm5-boot-artifacts.sh — check the on-disk Pi-firmware boot
# chain that mkosi.finalize is supposed to assemble for raspberry-pi5
# images. Reads the .raw image via sfdisk + mtools (no mounts needed).
#
# usage: verify-cm5-boot-artifacts.sh [path/to/image.raw]
#
# defaults to the most recently built raspberry-pi5 .raw.
set -euo pipefail

CACHE="${MARATHON_BUILD_DIR:-$HOME/.cache/marathon-build}/duranium/mkosi.output/raspberry-pi5_marathon_edge"
IMG="${1:-$(ls -1t "$CACHE"/raspberry-pi5_marathon_edge_*.raw 2>/dev/null | grep -E "/raspberry-pi5_marathon_edge_[0-9]+\.raw$" | head -1)}"

[ -n "$IMG" ] && [ -f "$IMG" ] || { echo "error: no .raw image found in $CACHE" >&2; exit 1; }

echo "==> image: $IMG ($(stat -c%s "$IMG") bytes)"
echo

# Partition layout
echo "==> partition layout:"
/usr/sbin/sfdisk -d "$IMG" 2>&1 \
    | grep -E '^/|^label|^sector-size' \
    | sed 's/^/   /'
echo

# Confirm discoverable-partition types
VTY_TYPE='6E11A4E7-FBCA-4DED-B9E9-E1A512BB664E'  # GptUsrVerityArm64
USR_TYPE='B0E01050-EE5F-4390-949A-9101B17104E9'  # GptUsrArm64
ESP_TYPE='C12A7328-F81F-11D2-BA4B-00A0C93EC93B'  # ESP

check_part_type() {
    local name=$1 expected=$2
    if /usr/sbin/sfdisk -d "$IMG" | grep -qi "type=$expected"; then
        echo "   [ok]  $name partition type ($expected) present"
    else
        echo "   [FAIL] $name partition type ($expected) MISSING"
        return 1
    fi
}

echo "==> discoverable-partitions check:"
check_part_type "ESP"      "$ESP_TYPE"
check_part_type "usr-vty"  "$VTY_TYPE"
check_part_type "usr-data" "$USR_TYPE"
echo

# Extract ESP offset + size from sfdisk's dump. The partition line is
#   /path.raw1 : start=    2048, size=    2097152, type=C12A...
# The whitespace between key= and value defeats awk-by-field parsing,
# so pull each value with a regex against the matching line.
ESP_LINE=$(/usr/sbin/sfdisk -d "$IMG" | grep -i "$ESP_TYPE")
ESP_OFFSET=$(echo "$ESP_LINE" | sed -E 's/.*start=[[:space:]]*([0-9]+).*/\1/')
ESP_SIZE=$(echo "$ESP_LINE"   | sed -E 's/.*size=[[:space:]]*([0-9]+).*/\1/')
SECTOR_SIZE=$(/usr/sbin/sfdisk -d "$IMG" | sed -nE 's/^sector-size:[[:space:]]*([0-9]+).*/\1/p')
SECTOR_SIZE=${SECTOR_SIZE:-512}

[ -n "${ESP_OFFSET:-}" ] && [ -n "${ESP_SIZE:-}" ] || { echo "error: could not parse ESP partition layout" >&2; exit 1; }

ESP_FILE=$(mktemp --suffix=.esp.raw)
trap 'rm -f "$ESP_FILE"' EXIT
dd if="$IMG" of="$ESP_FILE" bs="$SECTOR_SIZE" skip="$ESP_OFFSET" count="$ESP_SIZE" status=none

# Pi-firmware-boot artifact checks at ESP root.
PASS=0
FAIL=0

check_esp_file() {
    local path=$1 minsize=${2:-1}
    local actual
    actual=$(mdir -i "$ESP_FILE" "::$path" 2>/dev/null | awk '/files/ {next} NF>=4 && $NF !~ /<DIR>/ {print $(NF-1); exit}')
    if mdir -i "$ESP_FILE" "::$path" >/dev/null 2>&1; then
        # mdir lists the entry; size is the second-to-last column. Use mtype + wc as belt-and-suspenders.
        local size
        size=$(mtype -i "$ESP_FILE" "::$path" 2>/dev/null | wc -c)
        if [ "$size" -ge "$minsize" ]; then
            echo "   [ok]  $path ($size bytes)"
            PASS=$((PASS+1))
            return 0
        else
            echo "   [FAIL] $path exists but is too small ($size bytes < $minsize)"
            FAIL=$((FAIL+1))
            return 1
        fi
    fi
    echo "   [FAIL] $path MISSING"
    FAIL=$((FAIL+1))
    return 1
}

check_esp_dir_entry() {
    local path=$1
    if mdir -i "$ESP_FILE" "::$path" >/dev/null 2>&1; then
        local count
        count=$(mdir -i "$ESP_FILE" "::$path" 2>/dev/null | grep -c -v -E '^( |$|Vol|Direct)')
        echo "   [ok]  $path/ ($count entries)"
        PASS=$((PASS+1))
    else
        echo "   [FAIL] $path/ MISSING"
        FAIL=$((FAIL+1))
    fi
}

echo "==> Pi-firmware boot chain at ESP root:"
check_esp_file '/config.txt'                100   # main RPi firmware config
check_esp_file '/usercfg.txt'               100   # marathon device-specific overrides
check_esp_file '/cmdline.txt'                30   # kernel command line (NEW from build #14)
check_esp_file '/vmlinuz-rpi'          15000000   # ~23 MB
check_esp_file '/initramfs-rpi'        20000000   # ~40 MB (NEW from build #14)
check_esp_file '/bootcode.bin'           40000
check_esp_file '/start4.elf'           2000000
check_esp_file '/bcm2712-rpi-cm5-cm5io.dtb'  60000
check_esp_dir_entry '/overlays'
check_esp_file '/overlays/hackberrypi.dtbo'    500
echo

echo "==> cmdline.txt content:"
mtype -i "$ESP_FILE" '::cmdline.txt' 2>/dev/null | sed 's/^/   | /' || echo "   (missing)"
echo

echo "==> usercfg.txt content:"
mtype -i "$ESP_FILE" '::usercfg.txt' 2>/dev/null | sed 's/^/   | /' || echo "   (missing)"
echo

# Overlay-arg cross-check: every dtoverlay= in usercfg.txt should have a
# matching .dtbo on the ESP.
echo "==> dtoverlay references vs files in /overlays:"
mtype -i "$ESP_FILE" '::usercfg.txt' 2>/dev/null \
    | sed -n 's/^dtoverlay=\([^[:space:]]*\).*$/\1/p' \
    | while read -r ov; do
        if mdir -i "$ESP_FILE" "::overlays/${ov}.dtbo" >/dev/null 2>&1; then
            echo "   [ok]  ::overlays/${ov}.dtbo"
        else
            echo "   [FAIL] dtoverlay=$ov referenced but ::overlays/${ov}.dtbo MISSING"
        fi
    done

echo
echo "==> summary: $PASS pass / $FAIL fail"
if [ "$FAIL" -gt 0 ]; then
    echo "==> FAIL — image will not boot on the CM5"
    exit 1
fi
echo "==> PASS — image ready for ./scripts/flash/flash-hackberry-cm5.sh /dev/<SD>"
