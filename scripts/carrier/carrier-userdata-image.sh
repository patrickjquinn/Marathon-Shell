#!/usr/bin/env bash
# Make a userdata carrier image from a root image: a nested GPT with 4 KiB
# sectors, as the phone's chain-loaded U-Boot and initramfs expect.
#
#   carrier-userdata-image.sh ROOT.ext4 OUT.img
#
#   p1  pmOS_boot  FAT32 ESP: systemd-boot, the kernel, initramfs and DTB
#                  from ROOT's /boot, and one loader entry
#   p2  pmOS_root  ext4 carrier holding ROOT as
#                  /var/lib/marathon/images/<ROOT name>.ext4
#
# The device's part comes from ROOT's /usr/share/marathon/carrier.conf,
# which build-image.sh writes from the manifest's boot.carrier: the board
# DTB, the kernel command-line file, and the carrier's name, which names
# the kernel argument <name>.rootfs_file= the initramfs hook boots by.
#
# OUT is an Android sparse image for `fastboot flash userdata`. The carrier
# is just big enough for ROOT; the initramfs grows it into the rest of
# userdata on first boot.
#
# Env: PODMAN, where the host's mke2fs is 1.47.3 (default podman)
set -euo pipefail

ROOT=$(realpath "${1:?usage: carrier-userdata-image.sh ROOT.ext4 OUT.img}")
OUT=$(realpath -m "${2:?usage: carrier-userdata-image.sh ROOT.ext4 OUT.img}")

# mke2fs 1.47.3's -d stops with "Ext2 file too big" on an 8 GiB root whose
# data runs to its end; 1.47.4 copies it. Alpine's does: run there, with
# ROOT and OUT under one mount so the carrier can hard-link ROOT.
if [ "$(mke2fs -V 2>&1 | sed -n 's/^mke2fs \([0-9.]*\).*/\1/p')" = 1.47.3 ]; then
    if [ -n "${MARATHON_CARRIER_CONTAINER:-}" ]; then
        echo "error: mke2fs 1.47.3 cannot copy the root into the carrier; use e2fsprogs 1.47.4 or later" >&2
        exit 1
    fi
    common=$(dirname "$OUT")
    while [ "${ROOT#"$common"/}" = "$ROOT" ]; do common=$(dirname "$common"); done
    [ "$common" != / ] || { echo "error: $ROOT and $OUT share no directory to mount" >&2; exit 1; }
    mkdir -p "$(dirname "$OUT")"
    # shellcheck disable=SC2016
    exec "${PODMAN:-podman}" run --rm --security-opt label=disable -e MARATHON_CARRIER_CONTAINER=1 \
        -v "$common:/c" -v "$(dirname "$(realpath "$0")"):/s:ro" docker.io/library/alpine:edge sh -euc '
apk add -q bash coreutils e2fsprogs e2fsprogs-extra dosfstools mtools sfdisk android-tools
bash /s/carrier-userdata-image.sh "/c/$1" "/c/$2"' sh "${ROOT#"$common"/}" "${OUT#"$common"/}"
fi

NAME=$(basename "$ROOT" .ext4)
case $NAME in *[!A-Za-z0-9._-]* | '') echo "error: $ROOT: name must be [A-Za-z0-9._-]" >&2; exit 1 ;; esac
IMAGES=/var/lib/marathon/images
SECTOR=4096
ESP_START=2048
ESP_SECTORS=60416
CARRIER_START=$((ESP_START + ESP_SECTORS))
GPT_TAIL=256

WORK=$(mktemp -d -p "$(dirname "$OUT")" .carrier-userdata.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# Files from ROOT, as its packages installed them.
take() {
    debugfs -R "dump $1 $WORK/$2" "$ROOT" 2> /dev/null
    [ -s "$WORK/$2" ] || { echo "error: $ROOT has no $1" >&2; exit 1; }
}
take /usr/share/marathon/carrier.conf carrier.conf
conf() { sed -n "s/^$1=//p" "$WORK/carrier.conf" | tail -n 1; }
CARRIER=$(conf CARRIER_NAME)
DTB=$(conf CARRIER_DTB)
CMDLINE_FILE=$(conf CARRIER_CMDLINE)
case $CARRIER in *[!a-z0-9]* | '') echo "error: carrier.conf: CARRIER_NAME must be [a-z0-9]+" >&2; exit 1 ;; esac
case $DTB in *..* | /* | *[!A-Za-z0-9._/-]* | '') echo "error: carrier.conf: bad CARRIER_DTB '$DTB'" >&2; exit 1 ;; esac
case $CMDLINE_FILE in /usr/lib/kernel-cmdline.d/*.conf) ;; *) echo "error: carrier.conf: bad CARRIER_CMDLINE '$CMDLINE_FILE'" >&2; exit 1 ;; esac
take /boot/linux.efi linux.efi
take /boot/initramfs initramfs
take "/boot/dtbs/$DTB" board.dtb
take /usr/lib/systemd/boot/efi/systemd-bootaa64.efi BOOTAA64.EFI
take "$CMDLINE_FILE" cmdline.conf
CMDLINE=$(sed 's/#.*//' "$WORK/cmdline.conf" | xargs)

ROOT_UUID=$(cat /proc/sys/kernel/random/uuid)
BOOT_ID=$(od -An -N4 -tx4 /dev/urandom | tr -d ' ' | tr a-f A-F)
BOOT_UUID=${BOOT_ID%????}-${BOOT_ID#????}

ESP=$WORK/esp.img
truncate -s $((ESP_SECTORS * SECTOR)) "$ESP"
# FAT32 with 4 KiB sectors has fewer clusters than mkfs.fat suggests; it
# is what the phone was installed with.
mkfs.vfat -F 32 -S $SECTOR -n pmOS_boot -i "$BOOT_ID" "$ESP" > /dev/null 2>&1
ENTRY=marathon-$CARRIER-$NAME.conf
cat > "$WORK/$ENTRY" << EOF
title Marathon
linux /linux.efi
initrd /initramfs
devicetree /dtbs/$DTB
options $CMDLINE pmos_boot_uuid=$BOOT_UUID pmos_root_uuid=$ROOT_UUID $CARRIER.rootfs_file=$IMAGES/$NAME.ext4
EOF
echo "default $ENTRY" > "$WORK/loader.conf"
DTB_DIRS=()
d=/dtbs
IFS=/ read -ra parts <<< "$(dirname "$DTB")"
for p in "${parts[@]}"; do [ "$p" = . ] || { d=$d/$p; DTB_DIRS+=("::$d"); }; done
mmd -i "$ESP" ::/EFI ::/EFI/BOOT ::/dtbs "${DTB_DIRS[@]}" ::/loader ::/loader/entries
mcopy -i "$ESP" "$WORK/BOOTAA64.EFI" ::/EFI/BOOT/BOOTAA64.EFI
mcopy -i "$ESP" "$WORK/linux.efi" "$WORK/initramfs" ::/
mcopy -i "$ESP" "$WORK/board.dtb" "::/dtbs/$DTB"
mcopy -i "$ESP" "$WORK/loader.conf" ::/loader/loader.conf
mcopy -i "$ESP" "$WORK/$ENTRY" ::/loader/entries/

# The initramfs mounts the carrier as pmOS's root first, so it needs an
# os-release; the ESP is mounted on its /boot before the file root.
TREE=$WORK/carrier
mkdir -p "$TREE$IMAGES" "$TREE/boot" "$TREE/usr/lib"
printf 'NAME="Marathon %s carrier"\nID=marathon-%s-carrier\n' "${CARRIER^^}" "$CARRIER" > "$TREE/usr/lib/os-release"
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
# e2fsck sees the carrier's metadata only: a disk that filled during the
# copy left holes in the root file, and the phone could not run its init.
debugfs -R "cat $IMAGES/$NAME.ext4" "$DISK?offset=$OFFSET" 2> /dev/null | cmp -s - "$ROOT" ||
	{ echo "error: the root file on the carrier differs from $ROOT" >&2; exit 1; }
img2simg "$DISK" "$OUT" $SECTOR
echo "==> $OUT ($NAME, pmos_boot_uuid=$BOOT_UUID pmos_root_uuid=$ROOT_UUID)"
