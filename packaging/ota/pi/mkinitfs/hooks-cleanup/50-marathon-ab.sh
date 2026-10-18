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

# An encrypted data partition opens with the empty passphrase until the
# person sets a PIN, then with the PIN (docs/ENCRYPTION.md).
unlock() {
	echo | $open 2> /dev/null && return 0
	prompt="Enter PIN"
	while :; do
		if plymouth --ping 2> /dev/null; then
			plymouth ask-for-password --prompt="$prompt" --command="$open" && return 0
		elif command -v unl0kr > /dev/null; then
			unl0kr | $open && return 0
		else
			return 1
		fi
		prompt="Wrong PIN. Try again"
		sleep 1
	done
}

# udev has settled by now (init_2nd.sh setup_udev).
link=$root/dev/disk/by-partlabel/marathon_data
[ -e "$link" ] || exit 0
part=$(readlink -f "$link")
name=$(basename "$part")
disk=/dev/$(basename "$(dirname "$(readlink -f "$root/sys/class/block/$name")")")
partn=$(cat "$root/sys/class/block/$name/partition")
open="cryptsetup open --perf-no_read_workqueue --perf-no_write_workqueue $part marathon_data"

# First boot: the image ends early on the card. Move the backup GPT to the
# end and grow data into the rest.
grown=
parted -f -s "$disk" print > /dev/null 2>&1
if parted -s "$disk" print free | tail -n2 | head -n1 | grep -qi "free space"; then
	log "growing $part to the end of $disk"
	parted -f -s "$disk" resizepart "$partn" 100% || fail "cannot grow $part"
	grown=1
fi

data=$part
if cryptsetup isLuks "$part" 2> /dev/null; then
	unlock || fail "no way to ask for the PIN of $part"
	data=$root/dev/mapper/marathon_data
fi

if [ -n "$grown" ]; then
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
