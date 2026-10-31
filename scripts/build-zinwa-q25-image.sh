#!/usr/bin/env bash
# Build the Zinwa Q25 root: an ext4 file that the phone's carrier boots
# with q25.rootfs_file=, on the kernel, initramfs and ESP already on the
# phone. Nothing here builds or changes those.
#
# Output, in $Q25_IMAGE_OUT (default $MARATHON_BUILD_DIR/q25):
#   q25-duranium-<date>-<rev>.ext4, .ext4.zst and SHA256SUMS
#
# Env:
#   Q25_KERNEL_APK            the prebuilt linux-postmarketos-mediatek-g99
#                             7.0-r1000 package the phone's modules match
#   Q25_CONNSYS_FIRMWARE_DIR  the stock CONNSYS firmware, copied into the
#                             q25-connsys-firmware aport when it is missing
#                             there
#   MARATHON_BUILD_DIR        as for scripts/build-image.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"

export Q25_KERNEL_APK="${Q25_KERNEL_APK:?set Q25_KERNEL_APK to linux-postmarketos-mediatek-g99-7.0-r1000.apk}"
KERNEL_APK_SHA256=04e459cd8582ab5c08fc76122b9c4a8d1debcd1d952109f1cbf568cf1c6adfb6
echo "$KERNEL_APK_SHA256  $Q25_KERNEL_APK" | sha256sum -c --quiet

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
(cd "$DEST" && sha256sum "$NAME.ext4" "$NAME.ext4.zst" > "$NAME.SHA256SUMS")
echo "==> $DEST/$NAME.ext4"
cat "$DEST/$NAME.SHA256SUMS"
