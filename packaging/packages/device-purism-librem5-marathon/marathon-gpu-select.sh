#!/bin/sh
# Boot-time GPU driver selection for the Librem 5.
#
# etnaviv (open) and NXP's Vivante galcore (proprietary blob) both bind the
# GC7000Lite and cannot coexist. Both are blacklisted from udev autoload
# (see /etc/modprobe.d/marathon-gpu.conf); this service loads exactly one,
# chosen by GPU_STACK in the device profile, with a HARD fallback to etnaviv.
#
# Safety contract (the anti-wedge red line): the display controllers
# (mxsfb / imx-dcss) are separate hardware and are already up by the time this
# runs, so even total GPU-driver failure leaves a working panel on software
# render — never an unwakeable phone. Recovery override: append
# `marathon.gpu=etnaviv` to the kernel cmdline to force the known-good driver.
#
# Hard-hang self-recovery (the crux fix): galcore can HANG the SoC at
# module-init (D-state in `modprobe galcore`), which the session-layer
# crash-loop guard cannot catch — a kernel hang never restarts greetd, so the
# guard never runs, and a plain power-cycle just re-hangs. We break that loop
# with a persistent "in-flight" marker on the (rw, persistent) rootfs: it is
# written and fsync'd to eMMC BEFORE the modprobe and cleared immediately
# AFTER. If a later boot finds the marker still present, the previous galcore
# attempt never returned — it hung — so we force etnaviv this boot. Net: at
# most ONE vivante attempt hangs, then the next power-cycle self-recovers to a
# usable etnaviv boot, with no serial console or reflash needed.
set -u

CONF=/etc/marathon/device-profile.conf
# Persistent (survives power-off) marker on the root filesystem — NOT tmpfs.
VIV_INFLIGHT=/var/lib/marathon/.vivante-galcore-inflight
stack=mesa-etnaviv
[ -r "$CONF" ] && stack=$(sed -n 's/^GPU_STACK=[[:space:]]*//p' "$CONF" | tr -d '[:space:]')

# Kernel cmdline override wins (recovery / bring-up).
for tok in $(cat /proc/cmdline 2>/dev/null); do
	case "$tok" in
		marathon.gpu=*) stack=${tok#marathon.gpu=} ;;
	esac
done

load_etnaviv() {
	if modprobe etnaviv; then
		echo "marathon-gpu-select: etnaviv loaded"
	else
		echo "marathon-gpu-select: etnaviv FAILED to load — software render only" >&2
	fi
}

case "$stack" in
	vivante-blob)
		if [ -e "$VIV_INFLIGHT" ]; then
			# The previous boot armed the marker and never cleared it, i.e. the
			# last `modprobe galcore` hung the kernel. Do NOT try galcore again
			# — fall back to etnaviv so the phone comes up wakeable.
			rm -f "$VIV_INFLIGHT"; sync
			echo "marathon-gpu-select: previous galcore init did not survive (in-flight marker present) — forcing etnaviv" >&2
			load_etnaviv
		else
			# Arm the marker and flush it to eMMC BEFORE the risky modprobe, so a
			# hard hang leaves it set for the next boot to detect.
			mkdir -p "$(dirname "$VIV_INFLIGHT")" 2>/dev/null || true
			: > "$VIV_INFLIGHT"; sync
			if modprobe galcore 2>/dev/null && [ -e /dev/galcore ]; then
				rm -f "$VIV_INFLIGHT"; sync
				echo "marathon-gpu-select: Vivante galcore loaded (/dev/galcore present)"
			else
				rm -f "$VIV_INFLIGHT"; sync
				echo "marathon-gpu-select: galcore unavailable — falling back to etnaviv" >&2
				load_etnaviv
			fi
		fi
		;;
	*)
		load_etnaviv
		;;
esac

exit 0
