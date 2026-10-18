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

# Something with letter keys (KEY_A and KEY_Z), not just power or volume.
has_keyboard() {
	for caps in "$root"/sys/class/input/input*/capabilities/key; do
		[ -r "$caps" ] || continue
		read -r bits < "$caps"
		low=${bits##* }
		[ $((0x$low >> 30 & 1)) = 1 ] && [ $((0x$low >> 44 & 1)) = 1 ] && return 0
	done
	return 1
}

# An encrypted data partition opens with the empty passphrase until the
# person sets a PIN, then with the PIN (docs/ENCRYPTION.md). Plymouth draws
# the prompt but takes no touch; without a keyboard, unl0kr's on-screen one.
unlock() {
	echo | $open 2> /dev/null && return 0
	prompt="Enter PIN"
	if ! has_keyboard && command -v unl0kr > /dev/null; then
		plymouth quit 2> /dev/null
	fi
	while :; do
		if plymouth --ping 2> /dev/null; then
			plymouth ask-for-password --prompt="$prompt" --number-of-tries=1 --command="$open" && pin_typed=1 && return 0
		elif command -v unl0kr > /dev/null; then
			unl0kr | $open && pin_typed=1 && return 0
		else
			return 1
		fi
		prompt="Wrong PIN. Try again"
		sleep 1
	done
}

# A new install's data partition is an empty ext4 file system.
fresh() {
	mkdir -p "$mnt"
	mount -t ext4 -o ro "$part" "$mnt" 2> /dev/null || return 1
	entries=$(find "$mnt" -mindepth 1 -maxdepth 1 ! -name lost+found)
	umount "$mnt" || return 1
	[ -z "$entries" ]
}

# On the device, so each one gets its own volume key.
encrypt() {
	log "encrypting $part"
	echo | cryptsetup -q --force-password luksFormat --type luks2 \
		--pbkdf pbkdf2 --pbkdf-force-iterations 1000 "$part" &&
		echo | $open && mke2fs -q -F -t ext4 "$root/dev/mapper/marathon_data"
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
elif fresh; then
	if encrypt; then
		data=$root/dev/mapper/marathon_data
	else
		log "cannot encrypt $part; leaving it unencrypted"
		cryptsetup close marathon_data 2> /dev/null
		mke2fs -q -F -t ext4 "$part" || fail "cannot format $part"
	fi
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
# The PIN was typed here: the shell starts unlocked this once
# (marathon-data-key consume-boot-unlock).
if [ -n "${pin_typed:-}" ]; then
	(umask 077 && mkdir -p "$mnt/lib/marathon-data-key" &&
		cat "$root/proc/sys/kernel/random/boot_id" > "$mnt/lib/marathon-data-key/boot-unlocked")
fi
mkdir -p "$mnt/lib/marathon-ab/etc/upper" "$mnt/lib/marathon-ab/etc/work"
mount --move "$mnt" "$sysroot/var" || fail "cannot move $data to /var"
mount --bind "$sysroot/var/home" "$sysroot/home" || fail "cannot bind /home"
modprobe overlay
mount -t overlay overlay \
	-o "lowerdir=$sysroot/etc,upperdir=$sysroot/var/lib/marathon-ab/etc/upper,workdir=$sysroot/var/lib/marathon-ab/etc/work" \
	"$sysroot/etc" || fail "cannot mount the /etc overlay"
