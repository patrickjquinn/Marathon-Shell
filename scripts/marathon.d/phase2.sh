#!/usr/bin/env bash
# marathon.d/phase2.sh — interaction + measurement.
#
# Subcommands: tap, swipe, power, doze, freq, irqs, wakeups, cgroup,
# monitor <what>.

# ── tap ─────────────────────────────────────────────────────────────
cmd_tap() {
    local x="${1:-}" y="${2:-}"
    [ -z "$x" ] || [ -z "$y" ] && { marathon::error "usage: marathon tap <x> <y>"; return 2; }
    marathon::ssh "marathon-touchctl tap $x $y" >/dev/null
    marathon::success "tapped ($x, $y)"
}

# ── swipe ───────────────────────────────────────────────────────────
cmd_swipe() {
    if [ $# -lt 4 ]; then
        marathon::error "usage: marathon swipe <x1> <y1> <x2> <y2> [steps]"
        return 2
    fi
    local steps="${5:-30}"
    marathon::ssh "marathon-touchctl swipe $1 $2 $3 $4 $steps" >/dev/null
    marathon::success "swiped ($1,$2) → ($3,$4) in $steps steps"
}

# ── power (synthetic KEY_POWER) ─────────────────────────────────────
cmd_power() {
    marathon::step "inject KEY_POWER"
    marathon::ssh 'python3 - <<PYEOF
from evdev import UInput, ecodes as e
import time
ui = UInput({e.EV_KEY: [e.KEY_POWER]}, name="marathon-power")
time.sleep(0.2)
ui.write(e.EV_KEY, e.KEY_POWER, 1); ui.syn(); time.sleep(0.08)
ui.write(e.EV_KEY, e.KEY_POWER, 0); ui.syn(); ui.close()
PYEOF' 2>/dev/null
    sleep 1
    local bl
    bl="$(marathon::ssh 'cat /sys/class/backlight/backlight-dsi/bl_power')"
    if [ "$bl" = "0" ]; then
        marathon::success "screen ON (bl=0)"
    elif [ "$bl" = "4" ]; then
        marathon::success "screen OFF / Doze (bl=4)"
    else
        marathon::warn "bl_power=$bl (unexpected)"
    fi
}

# ── doze ────────────────────────────────────────────────────────────
cmd_doze_enter() {
    marathon::info "enter Doze via KEY_POWER"
    local bl
    bl="$(marathon::ssh 'cat /sys/class/backlight/backlight-dsi/bl_power')"
    [ "$bl" = "4" ] && { marathon::success "already in Doze"; return 0; }
    cmd_power
}

cmd_doze_exit() {
    marathon::info "exit Doze via KEY_POWER"
    local bl
    bl="$(marathon::ssh 'cat /sys/class/backlight/backlight-dsi/bl_power')"
    [ "$bl" = "0" ] && { marathon::success "already awake"; return 0; }
    cmd_power
}

cmd_doze_status() {
    local bl br psm
    bl="$(marathon::ssh 'cat /sys/class/backlight/backlight-dsi/bl_power' 2>/dev/null)"
    br="$(marathon::ssh 'cat /sys/class/backlight/backlight-dsi/brightness' 2>/dev/null)"
    psm="$(marathon::ssh 'iw dev wlan0 get power_save 2>/dev/null | sed s/Power.save..//')"
    if [ "$bl" = "4" ]; then
        marathon::info "Doze — bl=$bl (screen off), br=$br, wifi PSM=$psm"
    else
        marathon::info "Active — bl=$bl, br=$br, wifi PSM=$psm"
    fi
}

# ── freq histogram ─────────────────────────────────────────────────
cmd_freq() {
    local sample=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --sample|-s) sample="$2"; shift 2 ;;
            *) marathon::error "freq: unknown arg $1"; return 2 ;;
        esac
    done

    if [ "$sample" -gt 0 ]; then
        marathon::step "resetting counter + sampling ${sample}s"
        marathon::ssh 'echo 1 > /sys/devices/system/cpu/cpu0/cpufreq/stats/reset'
        sleep "$sample"
    fi
    marathon::ssh 'gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
echo "governor: $gov"
awk "{tot+=\$2; a[NR]=\$1\" \"\$2} END {
  for(i=1;i<=NR;i++){
    split(a[i], f, \" \");
    pct=(tot>0)?100.0*f[2]/tot:0;
    if(pct>=0.05) printf \"  %7d kHz: %6.2f%%\\n\", f[1], pct
  }
}" /sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state'
}

# ── irqs delta ─────────────────────────────────────────────────────
cmd_irqs() {
    local secs="${1:-2}"
    marathon::step "sampling ${secs}s"
    marathon::ssh "awk 'NR>1 {tot=0; for(i=2;i<=NF-2;i++) tot+=\$i; print \$1, tot}' /proc/interrupts > /tmp/marathon-irqs-a
sleep $secs
awk 'NR>1 {tot=0; for(i=2;i<=NF-2;i++) tot+=\$i; print \$1, tot}' /proc/interrupts > /tmp/marathon-irqs-b
join /tmp/marathon-irqs-a /tmp/marathon-irqs-b | \
  awk -v s=$secs '{d=\$3-\$2; if(d>=1) print d/s, \$1}' | \
  sort -rn | head -20 | \
  awk '{printf \"  %8.1f/s  %s\\n\", \$1, \$2}'"
}

# ── wakeup sources ─────────────────────────────────────────────────
cmd_wakeups() {
    marathon::ssh 'awk "NR>1 && \$3>0" /sys/kernel/debug/wakeup_sources | \
        sort -k3 -n -r | head -15 | \
        awk "{printf \"  %-30s active=%s events=%s\\n\", \$1, \$2, \$3}"'
}

# ── cgroup APPID ───────────────────────────────────────────────────
cmd_cgroup() {
    local app="${1:-}"
    [ -z "$app" ] && { marathon::error "usage: marathon cgroup <appId>"; return 2; }
    marathon::ssh "CG=/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-apps/marathon-app-$app
if [ ! -d \"\$CG\" ]; then echo '  no cgroup for $app'; exit 1; fi
echo '  === $app cgroup ==='
echo \"  freeze:            \$(cat \$CG/cgroup.freeze)\"
echo \"  uclamp.min:        \$(cat \$CG/cpu.uclamp.min 2>/dev/null)\"
echo \"  uclamp.max:        \$(cat \$CG/cpu.uclamp.max 2>/dev/null)\"
echo \"  procs:             \$(wc -l < \$CG/cgroup.procs 2>/dev/null) [\$(cat \$CG/cgroup.procs | tr '\n' ' ')]\"
echo \"  memory.current:    \$(awk 'BEGIN{c=0} END{printf \"%.1f MB\", c/1048576}' RS='' \$CG/memory.current 2>/dev/null || cat \$CG/memory.current | awk '{printf \"%.1f MB\", \$1/1048576}')\"
echo \"  memory.peak:       \$(cat \$CG/memory.peak 2>/dev/null | awk '{printf \"%.1f MB\", \$1/1048576}')\"
echo \"  memory.swap:       \$(cat \$CG/memory.swap.current 2>/dev/null | awk '{printf \"%.1f MB\", \$1/1048576}')\"
echo \"  cpu.pressure:      \$(head -1 \$CG/cpu.pressure 2>/dev/null)\"
echo \"  memory.pressure:   \$(head -1 \$CG/memory.pressure 2>/dev/null)\""
}

# ── monitor <what> ──────────────────────────────────────────────────
# Long-running poll that reports state changes. Ctrl-C to stop.

cmd_monitor() {
    local what="${1:-}"
    shift || true
    case "$what" in
        cgroup)  _marathon_monitor_cgroup "$@" ;;
        logs)    _marathon_monitor_logs "$@" ;;
        wifi)    _marathon_monitor_wifi "$@" ;;
        modem)   _marathon_monitor_modem "$@" ;;
        freq)    _marathon_monitor_freq "$@" ;;
        bl|backlight) _marathon_monitor_bl "$@" ;;
        wakeups) _marathon_monitor_wakeups "$@" ;;
        "")      marathon::error "usage: marathon monitor <cgroup|logs|wifi|modem|freq|bl|wakeups>"; return 2 ;;
        *)       marathon::error "unknown monitor: $what"; return 2 ;;
    esac
}

_marathon_monitor_cgroup() {
    marathon::info "monitoring app cgroup state (Ctrl-C to stop)"
    marathon::ssh 'declare -A prev_u
declare -A prev_f
while true; do
    for CG in /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-apps/marathon-app-*/; do
        a=$(basename "$CG" | sed s/marathon-app-//)
        u=$(cat "$CG"/cpu.uclamp.min 2>/dev/null | cut -d. -f1)
        f=$(cat "$CG"/cgroup.freeze 2>/dev/null)
        pu="${prev_u[$a]:-init}"
        pf="${prev_f[$a]:-init}"
        if [ "$pu" != "init" ] && ([ "$u" != "$pu" ] || [ "$f" != "$pf" ]); then
            printf "%s  %-12s  uclamp %s→%s  freeze %s→%s\n" "$(date +%H:%M:%S)" "$a" "$pu" "$u" "$pf" "$f"
        fi
        prev_u[$a]="$u"
        prev_f[$a]="$f"
    done
    sleep 0.4
done'
}

_marathon_monitor_logs() {
    local pattern="${1:-.}"
    marathon::info "tail crash.log — pattern '$pattern' (Ctrl-C to stop)"
    marathon::ssh "tail -Fn 0 /home/user/.marathon/crash.log 2>/dev/null | grep -vE '\\[AppRunner stderr\\]' | grep -E '$pattern' --line-buffered"
}

_marathon_monitor_wifi() {
    marathon::info "wifi state — poll every 2s"
    marathon::ssh 'while true; do
  psm=$(iw dev wlan0 get power_save 2>/dev/null | sed s/Power.save..//)
  link=$(iw dev wlan0 link 2>/dev/null | awk "/SSID/ {print \$2} /signal/ {print \$2\"dBm\"}" | tr "\n" " ")
  printf "%s  psm=%-4s  %s\n" "$(date +%H:%M:%S)" "$psm" "$link"
  sleep 2
done'
}

_marathon_monitor_modem() {
    marathon::info "modem state — poll every 3s"
    marathon::ssh 'while true; do
  state=$(mmcli -m 0 2>/dev/null | grep "state:" | head -1 | awk -F: "{print \$2}" | xargs)
  sig=$(mmcli -m 0 2>/dev/null | grep "signal quality" | awk -F: "{print \$2}" | xargs)
  ru=$(cat /sys/bus/usb/devices/1-1.2/power/runtime_status 2>/dev/null)
  printf "%s  state=%-12s  signal=%-8s  usb=%s\n" "$(date +%H:%M:%S)" "$state" "$sig" "$ru"
  sleep 3
done'
}

_marathon_monitor_freq() {
    marathon::info "cpu0 freq — poll every 1s"
    marathon::ssh 'while true; do
  f=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
  l=$(awk "{print \$1}" /proc/loadavg)
  printf "%s  cpu0=%s kHz  load=%s\n" "$(date +%H:%M:%S)" "$f" "$l"
  sleep 1
done'
}

_marathon_monitor_bl() {
    marathon::info "backlight — poll every 1s"
    marathon::ssh 'BL=/sys/class/backlight/backlight-dsi
prev_bl=-1; prev_br=-1
while true; do
  bl=$(cat $BL/bl_power)
  br=$(cat $BL/brightness)
  if [ "$bl" != "$prev_bl" ] || [ "$br" != "$prev_br" ]; then
    printf "%s  bl=%s  br=%s\n" "$(date +%H:%M:%S)" "$bl" "$br"
    prev_bl=$bl; prev_br=$br
  fi
  sleep 1
done'
}

_marathon_monitor_wakeups() {
    marathon::info "wakeup source event counts — every 5s"
    marathon::ssh 'declare -A prev
while true; do
  while IFS= read -r line; do
    name=$(echo "$line" | awk "{print \$1}")
    events=$(echo "$line" | awk "{print \$3}")
    [ -z "$name" ] && continue
    p="${prev[$name]:-init}"
    if [ "$p" != "init" ] && [ "$events" != "$p" ]; then
      printf "%s  %-30s %s→%s\n" "$(date +%H:%M:%S)" "$name" "$p" "$events"
    fi
    prev[$name]="$events"
  done < <(awk "NR>1 && \$3>0" /sys/kernel/debug/wakeup_sources)
  sleep 5
done'
}
