#!/usr/bin/env bash
# Make the Q25's userdata image from a root image: a nested GPT with 4 KiB
# sectors, as the phone's U-Boot and initramfs expect.
#
#   q25-userdata-image.sh ROOT.ext4 OUT.img
#
#   p1  pmOS_boot  FAT32 ESP: systemd-boot, the kernel, initramfs and DTB
#                  from ROOT's /boot, and one loader entry
#   p2  pmOS_root  ext4 carrier holding ROOT as
#                  /var/lib/marathon/images/<ROOT name>.ext4
#
# OUT is an Android sparse image for `fastboot flash userdata`. The carrier
# is just big enough for ROOT; the initramfs grows it into the rest of
# userdata on first boot, before q25-root-grow and q25-home-crypt need
# the room.
set -euo pipefail

ROOT=$(realpath "${1:?usage: q25-userdata-image.sh ROOT.ext4 OUT.img}")
OUT=$(realpath -m "${2:?usage: q25-userdata-image.sh ROOT.ext4 OUT.img}")
NAME=$(basename "$ROOT" .ext4)
case $NAME in *[!A-Za-z0-9._-]* | '') echo "error: $ROOT: name must be [A-Za-z0-9._-]" >&2; exit 1 ;; esac
IMAGES=/var/lib/marathon/images
SECTOR=4096
ESP_START=2048
ESP_SECTORS=60416
CARRIER_START=$((ESP_START + ESP_SECTORS))
GPT_TAIL=256

WORK=$(mktemp -d -p "$(dirname "$OUT")" .q25-userdata.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# Files from ROOT, as its packages installed them.
take() {
    debugfs -R "dump $1 $WORK/$2" "$ROOT" 2> /dev/null
    [ -s "$WORK/$2" ] || { echo "error: $ROOT has no $1" >&2; exit 1; }
}
take /boot/linux.efi linux.efi
take /boot/initramfs initramfs
take /boot/dtbs/mediatek/mt8781-zinwa-q25.dtb q25.dtb
take /usr/lib/systemd/boot/efi/systemd-bootaa64.efi BOOTAA64.EFI
take /usr/lib/kernel-cmdline.d/50-device-zinwa-q25.conf cmdline.conf
CMDLINE=$(sed 's/#.*//' "$WORK/cmdline.conf" | xargs)

ROOT_UUID=$(cat /proc/sys/kernel/random/uuid)
BOOT_ID=$(od -An -N4 -tx4 /dev/urandom | tr -d ' ' | tr a-f A-F)
BOOT_UUID=${BOOT_ID%????}-${BOOT_ID#????}

ESP=$WORK/esp.img
truncate -s $((ESP_SECTORS * SECTOR)) "$ESP"
# FAT32 with 4 KiB sectors has fewer clusters than mkfs.fat suggests; it
# is what the phone was installed with.
mkfs.vfat -F 32 -S $SECTOR -n pmOS_boot -i "$BOOT_ID" "$ESP" > /dev/null 2>&1
ENTRY=marathon-q25-$NAME.conf
cat > "$WORK/$ENTRY" << EOF
title Marathon
linux /linux.efi
initrd /initramfs
devicetree /dtbs/mediatek/mt8781-zinwa-q25.dtb
options $CMDLINE pmos_boot_uuid=$BOOT_UUID pmos_root_uuid=$ROOT_UUID q25.rootfs_file=$IMAGES/$NAME.ext4
EOF
echo "default $ENTRY" > "$WORK/loader.conf"
mmd -i "$ESP" ::/EFI ::/EFI/BOOT ::/dtbs ::/dtbs/mediatek ::/loader ::/loader/entries
mcopy -i "$ESP" "$WORK/BOOTAA64.EFI" ::/EFI/BOOT/BOOTAA64.EFI
mcopy -i "$ESP" "$WORK/linux.efi" "$WORK/initramfs" ::/
mcopy -i "$ESP" "$WORK/q25.dtb" ::/dtbs/mediatek/mt8781-zinwa-q25.dtb
mcopy -i "$ESP" "$WORK/loader.conf" ::/loader/loader.conf
mcopy -i "$ESP" "$WORK/$ENTRY" ::/loader/entries/

# The initramfs mounts the carrier as pmOS's root first, so it needs an
# os-release; the ESP is mounted on its /boot before the file root.
TREE=$WORK/carrier
mkdir -p "$TREE$IMAGES" "$TREE/boot" "$TREE/usr/lib"
printf 'NAME="Marathon Q25 carrier"\nID=marathon-q25-carrier\n' > "$TREE/usr/lib/os-release"
chmod 700 "$TREE/var/lib/marathon" "$TREE$IMAGES"
ln "$ROOT" "$TREE$IMAGES/$NAME.ext4" 2> /dev/null || cp --sparse=always "$ROOT" "$TREE$IMAGES/$NAME.ext4"
CARRIER_SECTORS=$((($(stat -c %s "$ROOT") + (256 << 20)) / SECTOR))

DISK=$WORK/userdata.img
truncate -s $(((CARRIER_START + CARRIER_SECTORS + GPT_TAIL) * SECTOR)) "$DISK"
sfdisk -q --sector-size $SECTOR "$DISK" << EOF
label: gpt
start=$ESP_START, size=$ESP_SECTORS, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=primary
start=$CARRIER_START, size=$CARRIER_SECTORS, type=B921B045-1DF0-41C3-AF44-4C6F280D3FAE, name=primary
EOF
dd if="$ESP" of="$DISK" bs=$SECTOR seek=$ESP_START conv=notrunc,sparse status=none
OFFSET=$((CARRIER_START * SECTOR))
mke2fs -q -t ext4 -b $SECTOR -L pmOS_root -U "$ROOT_UUID" -E offset=$OFFSET,root_owner=0:0 \
    -d "$TREE" "$DISK" $CARRIER_SECTORS
# mke2fs -d keeps the builder's ownership, and the root file may be a
# hard link to ROOT.
for p in /boot /usr /usr/lib /usr/lib/os-release /var /var/lib /var/lib/marathon $IMAGES "$IMAGES/$NAME.ext4"; do
    printf 'sif %s uid 0\nsif %s gid 0\n' "$p" "$p"
done | debugfs -w -f - "$DISK?offset=$OFFSET" > /dev/null 2>&1
debugfs -w -R "sif $IMAGES/$NAME.ext4 mode 0100600" "$DISK?offset=$OFFSET" > /dev/null 2>&1
e2fsck -fn "$DISK?offset=$OFFSET" > /dev/null 2>&1 || { echo "error: the carrier fails e2fsck" >&2; exit 1; }
img2simg "$DISK" "$OUT" $SECTOR
echo "==> $OUT ($NAME, pmos_boot_uuid=$BOOT_UUID pmos_root_uuid=$ROOT_UUID)"
