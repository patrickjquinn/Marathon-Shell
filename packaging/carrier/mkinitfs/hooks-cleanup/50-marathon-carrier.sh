#!/bin/sh
# The root is an ext4 file on the userdata carrier, named by
# <name>.rootfs_file=, where <name> is CARRIER_NAME in carrier.conf (the
# manifest's boot.carrier). By now init_2nd.sh has grown the carrier
# (partition 2 of the nested GPT) into the rest of userdata and mounted it
# on /sysroot, with the ESP on /sysroot/boot. Mount the file there instead
# and keep the carrier at /.<name>-carrier/root.
root=${MARATHON_CARRIER_TEST_ROOT:-}
sysroot=$root/sysroot

name=
while IFS='=' read -r key value; do
	[ "$key" = CARRIER_NAME ] && name=$value
done < "$root/usr/share/marathon/carrier.conf"
case $name in
'' | *[!a-z0-9]*) echo "carrier: no CARRIER_NAME in carrier.conf" > "$root/dev/kmsg"; exit 1 ;;
esac
carrier=$root/$name-carrier

log() {
	echo "$name-carrier: $*" > "$root/dev/kmsg"
}

file=
read -r cmdline < "$root/proc/cmdline"
for arg in $cmdline; do
	case $arg in "$name.rootfs_file="*) file=${arg#"$name.rootfs_file="} ;; esac
done
[ -n "$file" ] || exit 0
case $file in
*..* | *[!A-Za-z0-9_./-]*) log "refusing $name.rootfs_file=$file"; exit 1 ;;
/var/lib/marathon/images/*.ext4) ;;
*) log "refusing $name.rootfs_file=$file"; exit 1 ;;
esac
[ -f "$sysroot$file" ] || { log "no $file on the carrier"; exit 1; }

mkdir -p "$carrier"
mount --move "$sysroot" "$carrier" || exit 1
if ! loop=$(losetup --find --show --sector-size 4096 "$carrier$file") ||
	! mount -t ext4 -o rw "$loop" "$sysroot"; then
	log "cannot mount $file"
	[ -z "$loop" ] || losetup -d "$loop"
	mount --move "$carrier" "$sysroot"
	exit 1
fi
if mountpoint -q "$carrier/boot"; then
	mount --move "$carrier/boot" "$sysroot/boot"
	mount -o remount,ro "$sysroot/boot"
fi
# Only root may reach the carrier, which holds the encrypted /home.
mkdir -p "$sysroot/.$name-carrier/root"
chmod 0700 "$sysroot/.$name-carrier"
mount --move "$carrier" "$sysroot/.$name-carrier/root"
