#!/bin/sh
# marathon-doze-measure-ondevice.sh — runs ENTIRELY on the L5 with no
# host-side SSH dependency. Push it to the device, kick it off, unplug
# USB, wait for it to finish, plug back in, read the result file.
#
# Why on-device: the host-side harness (marathon-doze-measure.sh) SSHs
# over the USB-net bridge (172.16.42.1) since most dev hosts aren't on
# the phone's wifi LAN. Unplugging USB kills SSH instantly. This script
# does all the sampling itself and writes /tmp/marathon-doze-result.txt
# so you only need SSH at the start (kickoff) and the end (collect).
#
# Usage (host-side):
#   scp marathon-doze-measure-ondevice.sh root@marathon.local:/tmp/
#   ssh root@marathon.local '/tmp/marathon-doze-measure-ondevice.sh 60'
#   # ↑ now UNPLUG the USB cable. Script runs for ~ 3*duration + slack.
#   # After ~ 4 min, plug back in:
#   scp root@marathon.local:/tmp/marathon-doze-result.txt .
#   cat marathon-doze-result.txt
#
# arg1: per-scenario duration in seconds (default 60)

set -u
DUR="${1:-60}"
OUT=/tmp/marathon-doze-result.txt
BAT=/sys/class/power_supply/max170xx_battery
BL=/sys/class/backlight/backlight-dsi

: > "$OUT"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT"; }

log "=== marathon-doze-measure  duration=${DUR}s ==="
log "kernel=$(uname -r)"
log "battery status=$(cat $BAT/status 2>/dev/null) voltage=$(cat $BAT/voltage_now 2>/dev/null)uV"

# Cache cpuidle state info.
STATES=""
for s in /sys/devices/system/cpu/cpu0/cpuidle/state*; do
    n=$(cat "$s/name" 2>/dev/null)
    [ -n "$n" ] && STATES="$STATES $(basename $s)=$n"
done
log "cpuidle states:$STATES"
log ""

# Sample one CPU's idle counters. /proc/cpuinfo has 4 CPUs on the L5;
# we average the residency across all of them since some scenarios may
# park CPUs unevenly. Returns space-separated:
#   total_us state0_us state1_us ...
sample_cpuidle() {
    awk '
        BEGIN { for (i=0;i<8;i++) tot[i]=0; cpus=0 }
        { tot[FNR-1] += $1; if (FNR>n) n=FNR }
        END {
            total=0
            for (i=0;i<n;i++) total += tot[i]
            printf "%d", total
            for (i=0;i<n;i++) printf " %d", tot[i]
            print ""
        }
    ' /sys/devices/system/cpu/cpu*/cpuidle/state*/time 2>/dev/null
}

# Snapshot: ts charge_uAh voltage_uV current_uA <cpuidle...>
snap() {
    ts=$(date +%s%3N)
    ch=$(cat $BAT/charge_now 2>/dev/null || echo 0)
    v=$(cat $BAT/voltage_now 2>/dev/null || echo 0)
    i=$(cat $BAT/current_now 2>/dev/null || echo 0)
    ci=$(sample_cpuidle)
    echo "$ts $ch $v $i $ci"
}

run_scenario() {
    label=$1; setup=$2; teardown=$3; mode=$4
    log "--- scenario: $label ---"
    eval "$setup"
    start=$(snap)
    log "start: $start"

    if [ "$mode" = "suspend" ]; then
        log "calling rtcwake -m mem -s $DUR ..."
        rtcwake -m mem -s "$DUR" >/dev/null 2>&1
        log "wake at $(date +%H:%M:%S); 3 s settle for fuel gauge"
        sleep 3
    else
        sleep "$DUR"
    fi

    end=$(snap)
    log "end:   $end"
    eval "$teardown"

    # Parse: ts ch v i total s0 s1 ...
    set -- $start; T0=$1; CH0=$2; V0=$3; I0=$4; TOT0=$5
    shift 5; S0=$@
    set -- $end;   T1=$1; CH1=$2; V1=$3; I1=$4; TOT1=$5
    shift 5; S1=$@

    dt_ms=$(( T1 - T0 ))
    dt_s=$(awk -v x=$dt_ms 'BEGIN{printf "%.1f", x/1000}')
    dch=$(( CH0 - CH1 ))   # discharge positive
    avg_mA=$(awk -v dch=$dch -v t=$dt_s 'BEGIN{if(t>0) printf "%.1f", dch*3.6/t; else print "?"}')
    avg_V=$(awk -v v=$V1 'BEGIN{printf "%.2f", v/1000000}')
    avg_mW=$(awk -v ma=$avg_mA -v v=$avg_V 'BEGIN{printf "%.0f", ma*v}')

    log "  duration: ${dt_s}s   dCharge: ${dch} uAh   avg: ${avg_mA} mA  (${avg_mW} mW @ ${avg_V} V)"

    # Residency across all CPUs.
    tot_d=$(( TOT1 - TOT0 ))
    j=0
    set -- $S0; s0_arr="$@"
    set -- $S1; s1_arr="$@"
    resid=""
    set -- $s0_arr
    a=$@
    set -- $s1_arr
    b=$@
    # awk it
    resid=$(awk -v a="$a" -v b="$b" -v total="$tot_d" '
        BEGIN {
            split(a, A, " "); split(b, B, " ")
            for (i in B) {
                d = B[i] - A[i]
                pct = (total>0) ? 100.0*d/total : 0
                printf "s%d=%.1f%% ", (i-1), pct
            }
        }
    ')
    log "  residency: $resid"
    log ""
}

# Pre-flight wait: give the user 20 s after kickoff to physically unplug.
log "kickoff: unplug USB now if you want clean numbers. proceeding in 20 s..."
sleep 20

run_scenario "ACTIVE" \
    "echo 0 > $BL/bl_power; echo 12 > $BL/brightness" \
    ":" "wait"

run_scenario "SCREEN_OFF" \
    "echo 4 > $BL/bl_power" \
    "echo 0 > $BL/bl_power" "wait"

# Ensure greetd is alive before triggering suspend (avoid colliding with
# logind IdleAction). Mask the IdleAction temporarily to prevent it
# firing again mid-test.
run_scenario "SUSPEND" \
    ":" \
    ":" "suspend"

log ""
log "=== DONE ==="
log "post-run battery: status=$(cat $BAT/status 2>/dev/null) charge=$(cat $BAT/charge_now 2>/dev/null) uAh voltage=$(cat $BAT/voltage_now 2>/dev/null) uV"
log "result file: $OUT"
