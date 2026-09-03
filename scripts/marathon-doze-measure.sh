#!/usr/bin/env bash
# marathon-doze-measure.sh — power + cpuidle residency comparison harness.
#
# Three scenarios, compared head-to-head to inform the Marathon-Doze design:
#
#   ACTIVE       Screen on, idle at home screen
#   SCREEN_OFF   Backlight off (bl_power=4), kernel running, no suspend
#   SUSPEND      rtcwake -m mem -s N (full S3)
#
# Each scenario runs for $DURATION seconds. Per scenario we report:
#   - Avg battery current (mA) + power (mW)  — from MAX17055 fuel gauge
#   - cpuidle state residency (% of CPU0 time)
#
# Output: a single table printed at the end. Run with the device on battery
# (NOT charging) for representative numbers.
#
# Usage:
#   scripts/marathon-doze-measure.sh                # default 120 s per scenario
#   DURATION=60 scripts/marathon-doze-measure.sh    # quicker iteration
#   MARATHON_HOST=root@10.0.0.42 ...                # override host

set -euo pipefail

HOST="${MARATHON_HOST:-root@marathon.local}"
PASSWORD="${MARATHON_PASSWORD:-marathon}"
DURATION="${DURATION:-120}"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR -o ConnectTimeout=10
          -o ServerAliveInterval=15 -o ServerAliveCountMax=3)
SSH=(sshpass -p "$PASSWORD" ssh "${SSH_OPTS[@]}" "$HOST")

ssh_run() {
    "${SSH[@]}" "$@"
}

ssh_wait_back() {
    # After suspend, ssh resolves but TCP may take a while to accept.
    local deadline=$(( $(date +%s) + 60 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if "${SSH[@]}" -o ConnectTimeout=4 'echo up' >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    echo "ERROR: device never came back after suspend" >&2
    return 1
}

# ---- Pre-flight ------------------------------------------------------------

echo "==> Pre-flight"

CHARGING=$(ssh_run 'cat /sys/class/power_supply/max170xx_battery/status 2>/dev/null || echo unknown')
echo "    Battery status: $CHARGING"
if [ "$CHARGING" != "Discharging" ]; then
    echo "    WARNING: device is not discharging. Results will be skewed by charger."
    echo "    Unplug USB and re-run for clean numbers. Continuing anyway in 5 s..."
    sleep 5
fi

# Cache the cpuidle state names + their /sys paths once.
STATE_NAMES=$(ssh_run '
for s in /sys/devices/system/cpu/cpu0/cpuidle/state*; do
    name=$(cat $s/name 2>/dev/null)
    [ -n "$name" ] && echo "$(basename $s):$name"
done
')
echo "    cpuidle states: $(echo $STATE_NAMES | tr "\n" " ")"

# ---- Sampler ---------------------------------------------------------------
#
# One sample = a single composite line written by the device. We snapshot
# fuel gauge + every cpuidle state's cumulative time/usage so the deltas
# divide cleanly between scenarios.

snapshot() {
    # Echo a single line: ts_ms charge_uAh voltage_uV current_uA \
    #                     state0_time state0_usage state1_time state1_usage ...
    ssh_run '
        ts=$(date +%s%3N)
        ch=$(cat /sys/class/power_supply/max170xx_battery/charge_now 2>/dev/null || echo 0)
        v=$(cat /sys/class/power_supply/max170xx_battery/voltage_now 2>/dev/null || echo 0)
        i=$(cat /sys/class/power_supply/max170xx_battery/current_now 2>/dev/null || echo 0)
        line="$ts $ch $v $i"
        for s in /sys/devices/system/cpu/cpu0/cpuidle/state*; do
            t=$(cat $s/time 2>/dev/null || echo 0)
            u=$(cat $s/usage 2>/dev/null || echo 0)
            line="$line $t $u"
        done
        echo "$line"
    '
}

# Parse a snapshot into shell variables for delta math.
# Sets: T (ms), CHARGE (uAh), V (uV), I (uA),
#       S0T S0U S1T S1U ... (us / counts)
parse_snapshot() {
    set -- $1
    T=$1; CHARGE=$2; V=$3; I=$4
    shift 4
    local idx=0
    while [ $# -ge 2 ]; do
        eval "S${idx}T=$1"
        eval "S${idx}U=$2"
        shift 2
        idx=$((idx + 1))
    done
    NSTATES=$idx
}

# ---- Scenario runners ------------------------------------------------------

run_scenario() {
    local label=$1 setup=$2 teardown=$3 mode=$4
    echo ""
    echo "==> Scenario: $label  ($DURATION s)"
    eval "$setup"

    local start=$(snapshot)
    if [ "$mode" = "suspend" ]; then
        # rtcwake -m mem -s N suspends the kernel for N seconds, then resumes.
        # The ssh socket dies; reconnect after.
        echo "    triggering rtcwake -m mem -s $DURATION ..."
        ssh_run "rtcwake -m mem -s $DURATION" >/dev/null 2>&1 || true
        ssh_wait_back || return 1
        # Brief settle for the fuel gauge ADC to refresh post-resume.
        sleep 3
    else
        sleep "$DURATION"
    fi
    local end=$(snapshot)

    eval "$teardown"

    # Compute deltas and stash for the summary.
    parse_snapshot "$start"
    local T0=$T CH0=$CHARGE
    local S=()
    for i in $(seq 0 $((NSTATES - 1))); do
        S+=( $(eval echo \$S${i}T) )
    done

    parse_snapshot "$end"
    local T1=$T CH1=$CHARGE V1=$V

    local dt_ms=$((T1 - T0))
    local dt_s=$(awk -v x=$dt_ms 'BEGIN{printf "%.1f", x/1000}')
    local dch_uAh=$((CH0 - CH1))             # discharge = positive
    # Avg current (mA) = (dCharge_uAh / dt_s) * 3600 / 1000 = dch * 3.6 / dt_s
    local avg_mA=$(awk -v dch=$dch_uAh -v t=$dt_s 'BEGIN{
        if (t>0) printf "%.1f", dch * 3.6 / t; else print "?"
    }')
    local avg_V=$(awk -v v=$V1 'BEGIN{printf "%.2f", v/1000000}')
    local avg_mW=$(awk -v ma=$avg_mA -v v=$avg_V 'BEGIN{printf "%.0f", ma * v}')

    # State residency %.
    local residency=""
    local tot_us=0
    for i in $(seq 0 $((NSTATES - 1))); do
        local before=${S[$i]}
        local after=$(eval echo \$S${i}T)
        local d=$((after - before))
        tot_us=$((tot_us + d))
    done
    for i in $(seq 0 $((NSTATES - 1))); do
        local before=${S[$i]}
        local after=$(eval echo \$S${i}T)
        local d=$((after - before))
        local pct=$(awk -v x=$d -v t=$tot_us 'BEGIN{
            if (t>0) printf "%.1f", 100.0*x/t; else print "?"
        }')
        local name=$(echo "$STATE_NAMES" | awk -F: -v idx=$((i+1)) 'NR==idx{print $2}')
        residency="$residency  $name=${pct}%"
    done

    printf "    %-12s dt=%ss  dCh=%s uAh  avg=%s mA (%s mW @ %s V)\n" \
        "$label" "$dt_s" "$dch_uAh" "$avg_mA" "$avg_mW" "$avg_V"
    printf "    residency:%s\n" "$residency"

    # Stash for final table.
    RESULTS+=("$label|$dt_s|$avg_mA|$avg_mW|$residency")
}

RESULTS=()

# ACTIVE — screen on, sit idle.
run_scenario "ACTIVE" \
    "ssh_run 'echo 0 > /sys/class/backlight/backlight-dsi/bl_power; echo 12 > /sys/class/backlight/backlight-dsi/brightness'" \
    ":" \
    "wait"

# SCREEN_OFF — kernel running, display power-gated. The Doze candidate baseline.
run_scenario "SCREEN_OFF" \
    "ssh_run 'echo 4 > /sys/class/backlight/backlight-dsi/bl_power'" \
    "ssh_run 'echo 0 > /sys/class/backlight/backlight-dsi/bl_power'" \
    "wait"

# SUSPEND — full S3. The "what we're giving up" baseline.
run_scenario "SUSPEND" \
    ":" \
    ":" \
    "suspend"

# ---- Summary ---------------------------------------------------------------

echo ""
echo "==> Summary"
printf "%-12s  %-6s  %-8s  %-8s  %s\n" "scenario" "dt(s)" "mA" "mW" "residency"
printf "%-12s  %-6s  %-8s  %-8s  %s\n" "--------" "-----" "--" "--" "---------"
for r in "${RESULTS[@]}"; do
    IFS='|' read -r label dt mA mW resid <<< "$r"
    printf "%-12s  %-6s  %-8s  %-8s  %s\n" "$label" "$dt" "$mA" "$mW" "$resid"
done
echo ""
echo "Notes:"
echo "  - positive mA = discharge; charging skews to negative or zero."
echo "  - residency: % of CPU0 time spent in each cpuidle state."
echo "  - WFI is the shallowest idle (1 us); cpu-sleep is deeper (1500 us)."
echo "    The i.MX 8M Quad on this kernel exposes ONLY these two — there is"
echo "    no cluster-off / SoC-off state available to userspace."
