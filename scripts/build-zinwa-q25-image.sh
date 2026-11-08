#!/usr/bin/env bash
# Build the Zinwa Q25 image (docs/install/ZINWA_Q25.md).
#
# Output, in $Q25_IMAGE_OUT (default $MARATHON_BUILD_DIR/q25):
#   q25-duranium-<date>-<rev>.ext4, .ext4.zst  the root (an installed
#                                     phone takes it with
#                                     q25-root-install, from the device
#                                     package)
#   q25-duranium-<date>-<rev>.userdata.img(.zst)  the whole userdata
#                                     partition for a new install
#                                     (scripts/q25/q25-userdata-image.sh)
#   u-boot-q25.bin, gimme-uboot.py    U-Boot for lk_a/lk_b, and the tool
#                                     that puts it into the phone's own lk
#                                     image (scripts/q25/build-q25-uboot.sh)
#   q25-duranium-<date>-<rev>.SHA256SUMS
# scripts/flash/flash-zinwa-q25.sh flashes them.
#   zinwa-q25_marathon_edge/zinwa-q25_marathon_edge_<IMAGE_VERSION>.ext4, the
#   root again (a hard link) as the update feed names it, for
#   scripts/ota/marathon-ota publish --image-dir (docs/OTA.md); the
#   userdata image's carrier holds it, and boots it, by this name
#
# Arguments go to scripts/build-image.sh: --bump gives the image a new
# IMAGE_VERSION, which an over-the-air update needs.
#
# Env:
#   Q25_CONNSYS_FIRMWARE_DIR  the stock CONNSYS firmware, copied into the
#                             q25-connsys-firmware aport when it is missing
#                             there
#   MARATHON_BUILD_DIR        as for scripts/build-image.sh
#   Q25_NO_USERDATA           skip the userdata (fresh install) image
#   PODMAN                    for the U-Boot build, and the userdata image
#                             where the host has e2fsprogs 1.47.3 (default podman)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"

FW_APORT="$REPO/packaging/packages/q25-connsys-firmware"
# shellcheck disable=SC1091
for f in $(set +u; . "$FW_APORT/APKBUILD"; echo "${source:-}"); do
    [ -f "$FW_APORT/$f" ] || install -m644 "${Q25_CONNSYS_FIRMWARE_DIR:?set Q25_CONNSYS_FIRMWARE_DIR to the stock CONNSYS firmware}/$f" "$FW_APORT/$f"
done

DEST="${Q25_IMAGE_OUT:-${MARATHON_BUILD_DIR:-$HOME/.cache/marathon-build}/q25}"

# Fail now, not an hour in: the space each part needs (GiB), summed by the
# filesystem it lands on. mkosi's output holds the base and dev-tools trees,
# its workspace the root tree and the raw image; $DEST the root, the
# userdata image and both compressed.
check_space() {
    local -A want=() dirs=()
    local dir gib fs avail fail=
    while read -r dir gib; do
        mkdir -p "$dir"
        fs=$(df --output=target "$dir" | tail -1)
        want[$fs]=$((${want[$fs]:-0} + gib))
        dirs[$fs]="${dirs[$fs]:-} $dir"
    done
    for fs in "${!want[@]}"; do
        avail=$(df --output=avail -BG "$fs" | tail -1 | tr -dc 0-9)
        if [ "$avail" -lt "${want[$fs]}" ]; then
            echo "error: $fs has ${avail} GiB free; the build needs ${want[$fs]} GiB there:${dirs[$fs]}" >&2
            fail=1
        fi
    done
    [ -z "$fail" ]
}
check_space << SPACE
${MARATHON_BUILD_DIR:-$HOME/.cache/marathon-build}/duranium/mkosi.output 5
${XDG_CACHE_HOME:-$HOME/.cache}/mkosi 8
$DEST $([ -n "${Q25_NO_USERDATA:-}" ] && echo 5 || echo 11)
SPACE

bash "$SCRIPT_DIR/q25/build-q25-uboot.sh" "$DEST/u-boot"

bash "$SCRIPT_DIR/build-image.sh" zinwa-q25 "$@"

DURANIUM_DIR="${MARATHON_BUILD_DIR:-$HOME/.cache/marathon-build}/duranium"
OUT_DIR="$DURANIUM_DIR/mkosi.output/zinwa-q25_marathon_edge"
VERSION="$(cat "$DURANIUM_DIR/mkosi.version")"
IMAGE="$OUT_DIR/zinwa-q25_marathon_edge_$VERSION"
set -- "$IMAGE".root-*.raw
ROOT="$1"
NAME="q25-duranium-$(date +%Y%m%d)-$(git -C "$REPO" rev-parse --short HEAD)"
mkdir -p "$DEST"
mv "$ROOT" "$DEST/$NAME.ext4"
# The disk image only wraps the same partition in a GPT.
rm -f "$IMAGE.raw"
# q25-lk-update puts the root's U-Boot into lk_a, so an update brings it too.
UB=/usr/lib/q25/u-boot-q25.bin
debugfs -w -f - "$DEST/$NAME.ext4" > /dev/null << EOF
mkdir /usr/lib/q25
write $DEST/u-boot/u-boot-q25.bin $UB
set_inode_field /usr/lib/q25 uid 0
set_inode_field /usr/lib/q25 gid 0
set_inode_field /usr/lib/q25 mode 040755
set_inode_field $UB uid 0
set_inode_field $UB gid 0
set_inode_field $UB mode 0100644
EOF
debugfs -R "cat $UB" "$DEST/$NAME.ext4" 2> /dev/null | cmp - "$DEST/u-boot/u-boot-q25.bin"
e2fsck -fn "$DEST/$NAME.ext4"
zstd -T0 -10 -f "$DEST/$NAME.ext4" -o "$DEST/$NAME.ext4.zst"
FEED=zinwa-q25_marathon_edge/zinwa-q25_marathon_edge_$VERSION.ext4
mkdir -p "$DEST/$(dirname "$FEED")"
ln -f "$DEST/$NAME.ext4" "$DEST/$FEED"
if [ -n "${Q25_NO_USERDATA:-}" ]; then
    cp "$DEST/u-boot/u-boot-q25.bin" "$DEST/u-boot/src/gimme-uboot.py" "$DEST/"
    (cd "$DEST" && sha256sum "$NAME.ext4" "$NAME.ext4.zst" u-boot-q25.bin gimme-uboot.py > "$NAME.SHA256SUMS")
    echo "==> for the update feed: $DEST/$FEED (no userdata image: Q25_NO_USERDATA)"
    cat "$DEST/$NAME.SHA256SUMS"
    exit 0
fi
# The carrier holds the root by its feed name, so sysupdate counts it as
# installed and does not offer the same version as an update.
# e2fsprogs 1.47.3 cannot copy the root into the carrier; Alpine's can.
if [ "$(mke2fs -V 2>&1 | sed -n 's/^mke2fs \([0-9.]*\).*/\1/p')" = 1.47.3 ]; then
    # shellcheck disable=SC2016
    "${PODMAN:-podman}" run --rm --security-opt label=disable -v "$DEST:/out" -v "$SCRIPT_DIR/q25:/s:ro" \
        docker.io/library/alpine:edge sh -euc '
apk add -q bash coreutils e2fsprogs e2fsprogs-extra dosfstools mtools sfdisk android-tools
bash /s/q25-userdata-image.sh "/out/$2" "/out/$1.userdata.img"' sh "$NAME" "$FEED"
else
    bash "$SCRIPT_DIR/q25/q25-userdata-image.sh" "$DEST/$FEED" "$DEST/$NAME.userdata.img"
fi
zstd -T0 -10 -f "$DEST/$NAME.userdata.img" -o "$DEST/$NAME.userdata.img.zst"
cp "$DEST/u-boot/u-boot-q25.bin" "$DEST/u-boot/src/gimme-uboot.py" "$DEST/"
(cd "$DEST" && sha256sum "$NAME.ext4" "$NAME.ext4.zst" "$NAME.userdata.img" "$NAME.userdata.img.zst" \
    u-boot-q25.bin gimme-uboot.py > "$NAME.SHA256SUMS")
echo "==> $DEST/$NAME.userdata.img"
echo "==> for the update feed: $DEST/$FEED"
cat "$DEST/$NAME.SHA256SUMS"
