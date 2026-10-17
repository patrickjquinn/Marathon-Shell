#!/bin/sh
# A/B Raspberry Pi images: both root slots share the marathon_data
# partition for /var and /home, and keep /etc changes in an overlay on it.
# Runs after the slot's root is mounted on /sysroot, before switch_root.
root=${MARATHON_AB_TEST_ROOT:-}
sysroot=$root/sysroot
mnt=$root/marathon-data

log() {
	echo "marathon-ab: $*" > "$root/dev/kmsg"
}

# A trial boot that cannot set up its data goes back to the committed slot.
fail() {
	log "$*"
	if [ "$(od -An -tx1 -v "$root/proc/device-tree/chosen/bootloader/tryboot" 2>/dev/null | tr -d ' \n')" = 00000001 ]; then
		reboot -f
	fi
	exit 1
}

# udev has settled by now (init_2nd.sh setup_udev).
link=$root/dev/disk/by-partlabel/marathon_data
[ -e "$link" ] || exit 0
data=$(readlink -f "$link")
name=$(basename "$data")
disk=/dev/$(basename "$(dirname "$(readlink -f "$root/sys/class/block/$name")")")
partn=$(cat "$root/sys/class/block/$name/partition")

# First boot: the image ends early on the card. Move the backup GPT to the
# end and grow data into the rest.
parted -f -s "$disk" print > /dev/null 2>&1
if parted -s "$disk" print free | tail -n2 | head -n1 | grep -qi "free space"; then
	log "growing $data to the end of $disk"
	parted -f -s "$disk" resizepart "$partn" 100% || fail "cannot grow $data"
	e2fsck -f -p "$data"
	[ $? -lt 4 ] || fail "$data has errors"
	resize2fs "$data" || fail "cannot resize $data"
else
	e2fsck -p "$data"
	[ $? -lt 4 ] || fail "$data has errors"
fi

mkdir -p "$mnt"
mount -t ext4 -o rw,noatime "$data" "$mnt" || fail "cannot mount $data"
if [ ! -e "$mnt/.marathon-seeded" ]; then
	log "seeding $data from the slot's /var and /home"
	if ! { cp -a "$sysroot/var/." "$mnt/" && mkdir -p "$mnt/home" &&
		cp -a "$sysroot/home/." "$mnt/home/" && touch "$mnt/.marathon-seeded"; }; then
		fail "cannot seed $data"
	fi
fi
mkdir -p "$mnt/lib/marathon-ab/etc/upper" "$mnt/lib/marathon-ab/etc/work"
mount --move "$mnt" "$sysroot/var" || fail "cannot move $data to /var"
mount --bind "$sysroot/var/home" "$sysroot/home" || fail "cannot bind /home"
modprobe overlay
mount -t overlay overlay \
	-o "lowerdir=$sysroot/etc,upperdir=$sysroot/var/lib/marathon-ab/etc/upper,workdir=$sysroot/var/lib/marathon-ab/etc/work" \
	"$sysroot/etc" || fail "cannot mount the /etc overlay"
