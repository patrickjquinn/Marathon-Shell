#!/bin/sh
# Run as root on the device after copying dbus-rtt and under-cpu-load.py
# to /run/marathon-dbus-rtt and /run/marathon-under-cpu-load.py.
set -eu

case "${1:-}" in
    idle|load) mode=$1 ;;
    *) echo "usage: device-latency.sh idle|load" >&2; exit 2 ;;
esac

policy=/sys/devices/system/cpu/cpufreq/policy0
previous=$(cat "$policy/scaling_governor")
trap 'printf "%s\n" "$previous" > "$policy/scaling_governor"' EXIT
trap 'exit 1' HUP INT TERM
printf 'performance\n' > "$policy/scaling_governor"
sleep 2
echo "mode=$mode governor=performance previous=$previous frequency_kHz=$(cat "$policy/scaling_cur_freq")" >&2

command='set -e; export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; for run in 1 2 3; do /run/marathon-dbus-rtt 1000; done'
if [ "$mode" = idle ]; then
    su user -c "$command"
else
    python3 /run/marathon-under-cpu-load.py su user -c "$command"
fi
