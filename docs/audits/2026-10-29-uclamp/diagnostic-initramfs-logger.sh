#!/bin/busybox ash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
state=/run/marathon-kernel-diag
mountpoint=/kernel-diag
mark() {
 text="$(cut -d' ' -f1 /proc/uptime) $*"
 echo "marathon-kernel-diag: $text" >/dev/kmsg
 if test -f "$state/mounted"; then echo "$text" >>"$mountpoint/uclamp-diagnostic-stages.log"; fi
}
case "$1" in
 start)
  mkdir -p "$state" "$mountpoint"
  # This timer starts before udev, unlike the original /hooks guard.
  ( sleep 180; echo 'marathon-kernel-diag: early guard expired; rebooting to stock' >/dev/kmsg; reboot -f ) &
  echo $! >"$state/guard"
  for attempt in $(seq 1 40); do test -b /dev/mmcblk0p3 && break; sleep 0.1; done
  if mount -t vfat -o rw,sync,noatime /dev/mmcblk0p3 "$mountpoint"; then
   touch "$state/mounted"
   echo '=== uclamp diagnostic boot ===' >>"$mountpoint/uclamp-diagnostic-stages.log"
   uname -a >>"$mountpoint/uclamp-diagnostic-stages.log"
   cat /proc/cmdline >>"$mountpoint/uclamp-diagnostic-stages.log"
   dmesg >"$mountpoint/uclamp-diagnostic-early-kernel.log"
   awk '{print; if ($0 ~ /panic|Oops|BUG:|Call trace/) fflush()}' </dev/kmsg >>"$mountpoint/uclamp-diagnostic-kernel.log" &
   echo $! >"$state/logger"
  fi
  mark 'init started; early guard armed'
  ;;
 mark) shift; mark "$*" ;;
 finish)
  mark 'initramfs complete; switching to real root'
  test ! -f "$state/logger" || kill "$(cat "$state/logger")" 2>/dev/null
  if test -f "$state/mounted"; then
   dmesg >"$mountpoint/uclamp-diagnostic-final-kernel.log"
   sync
   umount "$mountpoint" || { mark 'diagnostic log filesystem could not unmount'; reboot -f; }
   rm -f "$state/mounted"
  fi
  test ! -f "$state/guard" || kill "$(cat "$state/guard")" 2>/dev/null
  ;;
esac
