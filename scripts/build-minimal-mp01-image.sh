#!/usr/bin/env bash
# Build the Minimal Phone MP01 image (devices/minimal/mp01/README.md).
#
# Output, in $MP01_IMAGE_OUT (default $MARATHON_BUILD_DIR/mp01):
#   mp01-duranium-<date>-<rev>.ext4, .ext4.zst    the root
#   mp01-duranium-<date>-<rev>.userdata.img(.zst) the whole userdata
#                                     partition: the root on its carrier
#                                     beside an ESP made from its /boot
#                                     (scripts/carrier/carrier-userdata-image.sh)
#   mp01-duranium-<date>-<rev>.SHA256SUMS
# scripts/flash/flash-minimal-mp01.sh flashes the userdata image with the
# U-Boot boot image for boot_b, which is built outside this tree
# (devices/minimal/mp01/FLASHING.md).
#
# Needs the kernel aport device-minimal-mp01 names (linux-minimal-mp01).
# Arguments go to scripts/build-image.sh.
#
# Env:
#   Q25_CONNSYS_FIRMWARE_DIR  the stock CONNSYS firmware the Q25 and MP01
#                        share, copied into the q25-connsys-firmware aport
#                        when it is missing there
#   MARATHON_BUILD_DIR   as for scripts/build-image.sh
#   PODMAN               for the userdata image where the host has
#                        e2fsprogs 1.47.3 (default podman)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
DEST="${MP01_IMAGE_OUT:-${MARATHON_BUILD_DIR:-$HOME/.cache/marathon-build}/mp01}"

FW_APORT="$REPO/packaging/packages/q25-connsys-firmware"
# shellcheck disable=SC1091
for f in $(set +u; . "$FW_APORT/APKBUILD"; echo "${source:-}"); do
    [ -f "$FW_APORT/$f" ] || install -m644 "${Q25_CONNSYS_FIRMWARE_DIR:?set Q25_CONNSYS_FIRMWARE_DIR to the stock CONNSYS firmware}/$f" "$FW_APORT/$f"
done

bash "$SCRIPT_DIR/build-image.sh" minimal-mp01 "$@"

DURANIUM_DIR="${MARATHON_BUILD_DIR:-$HOME/.cache/marathon-build}/duranium"
OUT_DIR="$DURANIUM_DIR/mkosi.output/minimal-mp01_marathon_edge"
VERSION="$(cat "$DURANIUM_DIR/mkosi.version")"
IMAGE="$OUT_DIR/minimal-mp01_marathon_edge_$VERSION"
set -- "$IMAGE".root-*.raw
NAME="mp01-duranium-$(date +%Y%m%d)-$(git -C "$REPO" rev-parse --short HEAD)"
mkdir -p "$DEST"
mv "$1" "$DEST/$NAME.ext4"
# The disk image only wraps the same partition in a GPT.
rm -f "$IMAGE.raw"
e2fsck -fn "$DEST/$NAME.ext4"
bash "$SCRIPT_DIR/carrier/carrier-userdata-image.sh" "$DEST/$NAME.ext4" "$DEST/$NAME.userdata.img"
zstd -T0 -10 -f "$DEST/$NAME.ext4" -o "$DEST/$NAME.ext4.zst"
zstd -T0 -10 -f "$DEST/$NAME.userdata.img" -o "$DEST/$NAME.userdata.img.zst"
(cd "$DEST" && sha256sum "$NAME.ext4" "$NAME.ext4.zst" "$NAME.userdata.img" "$NAME.userdata.img.zst" > "$NAME.SHA256SUMS")
echo "==> $DEST/$NAME.userdata.img"
cat "$DEST/$NAME.SHA256SUMS"
