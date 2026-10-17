#!/bin/sh
# A trial boot (reboot '0 tryboot') stuck in the initramfs reboots. The
# firmware has already cleared the flag, so that boots the committed slot.
# init_2nd.sh kills every sh before switch_root, this one included.
root=${MARATHON_AB_TEST_ROOT:-}
[ "$(od -An -tx1 -v "$root/proc/device-tree/chosen/bootloader/tryboot" 2>/dev/null | tr -d ' \n')" = 00000001 ] || exit 0
(
	sleep "${MARATHON_AB_GUARD_SECS:-180}"
	echo "marathon-ab: trial boot stuck in the initramfs; rebooting" > "$root/dev/kmsg"
	reboot -f
) &
