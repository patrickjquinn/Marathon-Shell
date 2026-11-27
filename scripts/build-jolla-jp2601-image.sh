#!/usr/bin/env bash
# Build the Jolla Phone (2026) image (devices/jolla/jp2601/BRINGUP.md).
#
# Output, in $JP2601_IMAGE_OUT (default $MARATHON_BUILD_DIR/jp2601):
#   jp2601-duranium-<date>-<rev>.ext4, .ext4.zst  the root
#   jp2601-duranium-<date>-<rev>.userdata.img(.zst)  the whole userdata
#                                     partition: the root on its carrier
#                                     beside an ESP made from its /boot
#                                     (scripts/carrier/carrier-userdata-image.sh),
#                                     an Android sparse image for fastboot
#   jp2601-duranium-<date>-<rev>.SHA256SUMS
#   jolla-jp2601_marathon_edge/jolla-jp2601_marathon_edge_<IMAGE_VERSION>.ext4,
#                                     the root again (a hard link) as the
#                                     update feed names it, for
#                                     scripts/ota/marathon-ota publish
#                                     --image-dir (docs/OTA.md); the
#                                     userdata image's carrier holds it, and
#                                     boots it, by this name
#
# U-Boot stays as it is in boot_b; it boots the ESP in userdata when there
# is one.
#
# Arguments go to scripts/build-image.sh: --bump gives the image a new
# IMAGE_VERSION, which an over-the-air update needs.
#
# Env:
#   JP2601_CONNSYS_FIRMWARE_DIR  the stock /vendor/firmware dump, for the
#                        CONNSYS files the jp2601-connsys-firmware aport
#                        lacks (they are not committed)
#   MARATHON_BUILD_DIR   as for scripts/build-image.sh
#   JP2601_NO_USERDATA   skip the userdata (fresh install) image
#   PODMAN               for the userdata image where the host has
#                        e2fsprogs 1.47.3 (default podman)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
DEST="${JP2601_IMAGE_OUT:-${MARATHON_BUILD_DIR:-$HOME/.cache/marathon-build}/jp2601}"

FW_APORT="$REPO/packaging/packages/jp2601-connsys-firmware"
# shellcheck disable=SC1091
for f in $(set +u; . "$FW_APORT/APKBUILD"; echo "${source:-}"); do
    [ -f "$FW_APORT/$f" ] || install -m644 "${JP2601_CONNSYS_FIRMWARE_DIR:?set JP2601_CONNSYS_FIRMWARE_DIR to the stock /vendor/firmware}/$f" "$FW_APORT/$f"
done

bash "$SCRIPT_DIR/build-image.sh" jolla-jp2601 "$@"

DURANIUM_DIR="${MARATHON_BUILD_DIR:-$HOME/.cache/marathon-build}/duranium"
OUT_DIR="$DURANIUM_DIR/mkosi.output/jolla-jp2601_marathon_edge"
VERSION="$(cat "$DURANIUM_DIR/mkosi.version")"
IMAGE="$OUT_DIR/jolla-jp2601_marathon_edge_$VERSION"
set -- "$IMAGE".root-*.raw
NAME="jp2601-duranium-$(date +%Y%m%d)-$(git -C "$REPO" rev-parse --short HEAD)"
mkdir -p "$DEST"
mv "$1" "$DEST/$NAME.ext4"
# The disk image only wraps the same partition in a GPT.
rm -f "$IMAGE.raw"
e2fsck -fn "$DEST/$NAME.ext4"
zstd -T0 -10 -f "$DEST/$NAME.ext4" -o "$DEST/$NAME.ext4.zst"
FEED=jolla-jp2601_marathon_edge/jolla-jp2601_marathon_edge_$VERSION.ext4
mkdir -p "$DEST/$(dirname "$FEED")"
ln -f "$DEST/$NAME.ext4" "$DEST/$FEED"
if [ -n "${JP2601_NO_USERDATA:-}" ]; then
    (cd "$DEST" && sha256sum "$NAME.ext4" "$NAME.ext4.zst" > "$NAME.SHA256SUMS")
    echo "==> for the update feed: $DEST/$FEED (no userdata image: JP2601_NO_USERDATA)"
    cat "$DEST/$NAME.SHA256SUMS"
    exit 0
fi
# The carrier holds the root by its feed name, so sysupdate counts it as
# installed and does not offer the same version as an update.
bash "$SCRIPT_DIR/carrier/carrier-userdata-image.sh" "$DEST/$FEED" "$DEST/$NAME.userdata.img"
zstd -T0 -10 -f "$DEST/$NAME.userdata.img" -o "$DEST/$NAME.userdata.img.zst"
(cd "$DEST" && sha256sum "$NAME.ext4" "$NAME.ext4.zst" "$NAME.userdata.img" "$NAME.userdata.img.zst" > "$NAME.SHA256SUMS")
echo "==> $DEST/$NAME.userdata.img"
echo "==> for the update feed: $DEST/$FEED"
cat "$DEST/$NAME.SHA256SUMS"
