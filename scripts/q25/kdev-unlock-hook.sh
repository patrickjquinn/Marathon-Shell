#!/bin/sh
# kdev test boots only: scripts/q25/kdev.sh adds this to the boot's
# initramfs, never to an image. Takes the /home PIN once over the USB
# network, so a test boot needs nobody at the phone; without a PIN within
# 120 s the normal prompt asks for it.
f=/sysroot/.q25-carrier/root/var/lib/marathon/images/home.luks
[ -e "$f" ] || exit 0
echo "kdev-unlock: waiting 120 s for the PIN on port 4444" > /dev/kmsg
pin=$(busybox timeout 120 busybox nc -l -p 4444 2> /dev/null | head -c 64)
[ -n "$pin" ] || exit 0
if printf %s "$pin" | cryptsetup open --allow-discards --perf-no_read_workqueue \
	--perf-no_write_workqueue --key-file=- "$f" q25-home; then
	echo "kdev-unlock: /home opened" > /dev/kmsg
else
	echo "kdev-unlock: the PIN did not open /home" > /dev/kmsg
fi
exit 0
