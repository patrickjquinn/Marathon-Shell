#!/usr/bin/env bash
# Build the Zinwa Q25 image (docs/install/ZINWA_Q25.md).
#
# Output, in $Q25_IMAGE_OUT (default $MARATHON_BUILD_DIR/q25):
#   q25-duranium-<date>-<rev>.ext4, .ext4.zst  the root, which the carrier
#                                     boots with q25.rootfs_file= (an
#                                     installed phone takes it with
#                                     scripts/q25/q25-root-install.sh)
#   q25-duranium-<date>-<rev>.userdata.img(.zst)  the whole userdata
#                                     partition for a new install
#                                     (scripts/q25/q25-userdata-image.sh)
#   u-boot-q25.bin, gimme-uboot.py    U-Boot for lk_a/lk_b, and the tool
#                                     that puts it into the phone's own lk
#                                     image (scripts/q25/build-q25-uboot.sh)
#   q25-duranium-<date>-<rev>.SHA256SUMS
# scripts/flash/flash-zinwa-q25.sh flashes them.
#
# Env:
#   Q25_CONNSYS_FIRMWARE_DIR  the stock CONNSYS firmware, copied into the
#                             q25-connsys-firmware aport when it is missing
#                             there
#   MARATHON_BUILD_DIR        as for scripts/build-image.sh
#   PODMAN                    for the U-Boot build (default podman)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"

FW_APORT="$REPO/packaging/packages/q25-connsys-firmware"
# shellcheck disable=SC1091
for f in $(set +u; . "$FW_APORT/APKBUILD"; echo "${source:-}"); do
    [ -f "$FW_APORT/$f" ] || install -m644 "${Q25_CONNSYS_FIRMWARE_DIR:?set Q25_CONNSYS_FIRMWARE_DIR to the stock CONNSYS firmware}/$f" "$FW_APORT/$f"
done

bash "$SCRIPT_DIR/build-image.sh" zinwa-q25

DURANIUM_DIR="${MARATHON_BUILD_DIR:-$HOME/.cache/marathon-build}/duranium"
OUT_DIR="$DURANIUM_DIR/mkosi.output/zinwa-q25_marathon_edge"
IMAGE="$OUT_DIR/zinwa-q25_marathon_edge_$(cat "$DURANIUM_DIR/mkosi.version")"
set -- "$IMAGE".root-*.raw
ROOT="$1"
DEST="${Q25_IMAGE_OUT:-${MARATHON_BUILD_DIR:-$HOME/.cache/marathon-build}/q25}"
NAME="q25-duranium-$(date +%Y%m%d)-$(git -C "$REPO" rev-parse --short HEAD)"
mkdir -p "$DEST"
mv "$ROOT" "$DEST/$NAME.ext4"
# The disk image only wraps the same partition in a GPT.
rm -f "$IMAGE.raw"
e2fsck -fn "$DEST/$NAME.ext4"
zstd -T0 -10 -f "$DEST/$NAME.ext4" -o "$DEST/$NAME.ext4.zst"
bash "$SCRIPT_DIR/q25/q25-userdata-image.sh" "$DEST/$NAME.ext4" "$DEST/$NAME.userdata.img"
zstd -T0 -10 -f "$DEST/$NAME.userdata.img" -o "$DEST/$NAME.userdata.img.zst"
bash "$SCRIPT_DIR/q25/build-q25-uboot.sh" "$DEST/u-boot"
cp "$DEST/u-boot/u-boot-q25.bin" "$DEST/u-boot/src/gimme-uboot.py" "$DEST/"
(cd "$DEST" && sha256sum "$NAME.ext4" "$NAME.ext4.zst" "$NAME.userdata.img" "$NAME.userdata.img.zst" \
    u-boot-q25.bin gimme-uboot.py > "$NAME.SHA256SUMS")
echo "==> $DEST/$NAME.userdata.img"
cat "$DEST/$NAME.SHA256SUMS"
