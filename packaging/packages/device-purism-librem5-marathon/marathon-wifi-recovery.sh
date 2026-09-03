#!/bin/sh
# marathon-wifi-recovery — recover the RS9116 wifi modem on the Librem 5
# when the in-kernel SDIO probe fails at boot.
#
# Failure signature in dmesg:
#   mmc1: error -110 whilst initialising SDIO card
#   mmc1: Failed to initialize a non-removable card
#
# The RS9116 is wired to the SDHCI host at 30b50000.mmc through a power
# sequence (mmc-pwrseq) GPIO. On a cold boot the chip occasionally fails
# to respond to CMD5 within the timeout window; once that happens the
# kernel marks mmc1 as a failed-init non-removable card and gives up,
# never retrying — so no wlan* interface ever appears.
#
# Recovery: unbind + rebind the sdhci-esdhc-imx platform driver for
# 30b50000.mmc. That re-runs the pwrseq + clock + voltage init and
# usually re-enumerates the chip cleanly.
#
# This script:
#   1. Looks for the failure signature in dmesg.
#   2. If found AND no wlan* interface exists, attempts the rebind up
#      to MAX_TRIES times with backoff.
#   3. Bails out the moment a wlan* appears, or after exhausting tries.
#
# Triggered:
#   - At boot, by marathon-wifi-recovery.service (After=NetworkManager).
#   - On rfkill state-change (kill switch toggled), by 95-marathon-wifi-
#     rfkill.rules → systemctl start --no-block marathon-wifi-recovery.

set -u

LOG_TAG="marathon-wifi-recovery"
SDHCI_DEV="30b50000.mmc"
SDHCI_DRIVER="/sys/bus/platform/drivers/sdhci-esdhc-imx"
MAX_TRIES=3
BACKOFF_SECS="2 3 5"

log() {
    logger -t "$LOG_TAG" -- "$*"
    echo "[$LOG_TAG] $*" >&2
}

has_wlan() {
    for iface in /sys/class/net/wlan* /sys/class/net/wlp*; do
        [ -e "$iface" ] && return 0
    done
    return 1
}

needs_recovery() {
    # If wlan is already up, nothing to do.
    if has_wlan; then
        return 1
    fi
    # Look for the boot-time timeout error. dmesg is ring-buffered so
    # this only fires for relatively-recent failures.
    if dmesg | grep -q "mmc1: error -110 whilst initialising SDIO card"; then
        return 0
    fi
    if dmesg | grep -q "mmc1: Failed to initialize a non-removable card"; then
        return 0
    fi
    return 1
}

try_rebind() {
    if [ ! -d "$SDHCI_DRIVER" ]; then
        log "sdhci-esdhc-imx driver not present at $SDHCI_DRIVER; aborting"
        return 1
    fi
    log "Unbinding $SDHCI_DEV"
    echo "$SDHCI_DEV" > "$SDHCI_DRIVER/unbind" 2>/dev/null || true
    sleep 1
    log "Rebinding $SDHCI_DEV"
    echo "$SDHCI_DEV" > "$SDHCI_DRIVER/bind" 2>/dev/null || true
}

main() {
    if has_wlan; then
        log "wlan already present — nothing to do"
        return 0
    fi

    if ! needs_recovery; then
        log "no SDIO-timeout signature in dmesg — leaving alone"
        return 0
    fi

    log "RS9116 SDIO timeout detected, attempting recovery"

    i=0
    for backoff in $BACKOFF_SECS; do
        i=$((i + 1))
        if [ "$i" -gt "$MAX_TRIES" ]; then
            break
        fi
        log "attempt $i/$MAX_TRIES"
        try_rebind
        sleep "$backoff"
        if has_wlan; then
            log "wlan came up after attempt $i — done"
            return 0
        fi
    done

    log "exhausted $MAX_TRIES attempts — wifi still not enumerated; user may need to toggle physical kill switch or reboot"
    return 1
}

main "$@"
