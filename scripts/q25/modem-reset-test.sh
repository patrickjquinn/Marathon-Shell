#!/bin/sh
# Check that MD1 comes back after a reset without a reboot
# (docs: ~/Downloads/marathon-research/q25-modem-recovery.md). Runs on the
# Q25 as root, never during a call. It only issues ioctls on
# /dev/ccci_ioctl1 and never writes to a ccci port (that crashes the modem).
#
#   modem-reset-test.sh reset    CCCI_IOC_MD_RESET: a restart, no crash
#   modem-reset-test.sh assert   CCCI_IOC_FORCE_MD_ASSERT: a real exception
#
# Pass: the boot state returns to md1:4 within the timeout, q25-modem.target
# is never stopped, and the owner state is unchanged. On a fail, capture the
# printed logs and reboot (no worse than without the fix).
set -eu
case "${1:-}" in
reset) ioc=0x4300 ;;
assert) ioc=0x4304 ;;
*) echo "usage: $0 reset|assert" >&2; exit 2 ;;
esac
STATE=/sys/devices/platform/soc/soc:md1-owner/state
log=/tmp/modem-reset-test.$$
since=$(date '+%Y-%m-%d %H:%M:%S')

boot() { cat /sys/kernel/ccci/boot 2>/dev/null; }
[ "$(boot)" = "md1:4" ] || { echo "MD1 not ready ($(boot)); not testing" >&2; exit 1; }
owner=$(cat $STATE)
echo "before: boot=$(boot) owner=$owner"

python3 -c "import os, fcntl; fcntl.ioctl(os.open('/dev/ccci_ioctl1', os.O_RDWR), $ioc)"
echo "issued $1 ($ioc)"

ok=0
for i in $(seq 120); do
	sleep 1
	[ "$(boot)" = "md1:4" ] && [ "$i" -gt 3 ] && { ok=1; break; }
done
echo "after ${i}s: boot=$(boot) owner=$(cat $STATE)"

journalctl --since "$since" --no-pager -o short-monotonic \
	-u 'q25-*' -u ModemManager > $log.journal
dmesg | grep -i -E "ccci|md1|mddriver" | tail -80 > $log.dmesg
if grep -q "Stopped target Q25 MD1" $log.journal; then
	echo "FAIL: the modem target was stopped"; ok=0
fi
[ "$(cat $STATE)" = "$owner" ] || { echo "FAIL: owner state changed"; ok=0; }
grep -q -i "boot failed\|usage count underflow" $log.dmesg && { echo "FAIL: see $log.dmesg"; ok=0; }
echo "logs: $log.journal $log.dmesg"
if [ $ok = 1 ]; then
	echo PASS
else
	echo "FAIL: reboot to get cellular back"
	exit 1
fi
