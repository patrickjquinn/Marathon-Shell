#!/usr/bin/env bash
# marathon.d/phase3.sh — specialist probes.
#
# Subcommands: modem, wifi, gov, scheduler, fuel-gauge, backlight.

# ── modem ───────────────────────────────────────────────────────────
# `modem at "AT+CFUN?"` — raw AT command through ModemManager DBus if
# --debug allowed, else stops MM briefly + talks to /dev/ttyUSB2, then
# restarts MM. Preserves calls/data across the operation.

cmd_modem_info() {
    marathon::ssh 'mmcli -m 0 2>/dev/null | grep -iE "model|state|power|access|signal|3gpp|imei|operator|packet" | head -12'
}

cmd_modem_at() {
    local cmd="${1:-}"
    [ -z "$cmd" ] && { marathon::error "usage: marathon modem at 'AT+CFUN?'"; return 2; }
    marathon::step "stop MM"
    marathon::ssh 'systemctl stop ModemManager' >/dev/null
    sleep 5
    marathon::step "AT: $cmd"
    marathon::ssh "python3 - <<PYEOF
import serial, time
s = serial.Serial('/dev/ttyUSB2', 115200, timeout=3)
time.sleep(0.5)
s.write(b'AT\r\n'); time.sleep(0.3); s.read(4096)
s.reset_input_buffer()
s.write(('$cmd' + '\r\n').encode()); s.flush()
time.sleep(0.6)
print(s.read(8192).decode(errors='replace').strip())
s.close()
PYEOF" 2>&1 | grep -vE '^$'
    marathon::step "restart MM"
    marathon::ssh 'systemctl start ModemManager' >/dev/null
    marathon::wait_reachable 30 >/dev/null 2>&1 || true
}

cmd_modem_psm() {
    local val="${1:-}"
    case "$val" in
        on)  cmd_modem_at 'AT+CPSMS=1,,,"01011110","00100001"' ;;
        off) cmd_modem_at 'AT+CPSMS=0' ;;
        status) cmd_modem_at 'AT+CPSMS?' ;;
        *)   marathon::error "usage: marathon modem psm on|off|status"; return 2 ;;
    esac
}

cmd_modem_edrx() {
    local val="${1:-}"
    case "$val" in
        off)     cmd_modem_at 'AT+CEDRXS=0' ;;
        status)  cmd_modem_at 'AT+CEDRXRDP' ;;
        [0-9]*)  cmd_modem_at "AT+CEDRXS=1,4,\"$val\"" ;;
        *)       marathon::error "usage: marathon modem edrx <off|status|binary4>"; return 2 ;;
    esac
}

cmd_modem_reset() {
    marathon::step "modem soft reset via mmcli"
    marathon::ssh 'mmcli -m 0 --reset' 2>&1 | head -3
    marathon::wait_reachable 60 >/dev/null 2>&1 || true
}

# ── wifi ────────────────────────────────────────────────────────────
cmd_wifi_psm() {
    local val="${1:-}"
    case "$val" in
        on|off)  marathon::ssh "iw dev wlan0 set power_save $val"
                 marathon::ssh 'iw dev wlan0 get power_save' ;;
        status)  marathon::ssh 'iw dev wlan0 get power_save' ;;
        *)       marathon::error "usage: marathon wifi psm on|off|status"; return 2 ;;
    esac
}

cmd_wifi_scan() {
    marathon::info "wifi scan (may take a few seconds)"
    marathon::ssh 'iw dev wlan0 scan 2>/dev/null | awk "/BSS |SSID:|signal:/ {print}" | head -30'
}

cmd_wifi_link() {
    marathon::ssh 'iw dev wlan0 link'
}

# ── gov ─────────────────────────────────────────────────────────────
cmd_gov() {
    local val="${1:-}"
    if [ -z "$val" ]; then
        marathon::ssh 'echo "current: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
echo "available: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors)"'
        return 0
    fi
    marathon::step "set governor to $val on all CPUs"
    marathon::ssh "for g in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
  echo $val > \$g 2>/dev/null
done
echo \"now: \$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)\""
}

# ── scheduler <disk> <sched> ────────────────────────────────────────
cmd_scheduler() {
    local disk="${1:-}" sched="${2:-}"
    if [ -z "$disk" ]; then
        marathon::ssh 'for d in /sys/block/mmcblk0 /sys/block/sd*; do
  [ -d "$d" ] || continue
  echo "  $(basename $d): $(cat $d/queue/scheduler)"
done'
        return 0
    fi
    if [ -z "$sched" ]; then
        marathon::ssh "cat /sys/block/$disk/queue/scheduler"
        return 0
    fi
    marathon::step "load $sched module (if needed) + assign to $disk"
    marathon::ssh "modprobe $sched 2>/dev/null || true
echo $sched > /sys/block/$disk/queue/scheduler
echo \"now: \$(cat /sys/block/$disk/queue/scheduler)\""
}

# ── fuel-gauge ─────────────────────────────────────────────────────
cmd_fuel_gauge() {
    marathon::ssh 'BAT=/sys/class/power_supply/max170xx_battery
echo "  status:            $(cat $BAT/status)"
awk -v c=$(cat $BAT/capacity) "BEGIN{printf \"  capacity:          %d%%\n\", c}"
awk -v v=$(cat $BAT/voltage_now) "BEGIN{printf \"  voltage:           %.3f V\n\", v/1e6}"
awk -v i=$(cat $BAT/current_now) "BEGIN{printf \"  current_now:       %s%.0f mA  (positive = charging)\n\", (i>=0?\"+\":\"\"), i/1000}"
awk -v c=$(cat $BAT/charge_now) -v f=$(cat $BAT/charge_full) -v d=$(cat $BAT/charge_full_design) \
    "BEGIN{printf \"  charge:            %.2f Ah / %.2f Ah  (design %.2f Ah · health %.0f%%)\n\", c/1e6, f/1e6, d/1e6, 100.0*f/d}"
awk -v t=$(cat $BAT/temp) "BEGIN{printf \"  temperature:       %.1f°C\n\", t/10}"
for thermal in /sys/class/thermal/thermal_zone*/; do
  name=$(cat $thermal/type 2>/dev/null)
  temp=$(cat $thermal/temp 2>/dev/null)
  [ -n "$temp" ] && awk -v n=$name -v t=$temp "BEGIN{printf \"  soc %-14s %.1f°C\n\", n\":\", t/1000}"
done'
}

# ── backlight <val> ────────────────────────────────────────────────
cmd_backlight() {
    local val="${1:-}"
    if [ -z "$val" ]; then
        marathon::ssh 'BL=/sys/class/backlight/backlight-dsi
echo "  bl_power:          $(cat $BL/bl_power)  (0=on, 4=off)"
echo "  brightness:        $(cat $BL/brightness) / $(cat $BL/max_brightness)"
echo "  actual_brightness: $(cat $BL/actual_brightness)"'
        return 0
    fi
    marathon::ssh "echo 0 > /sys/class/backlight/backlight-dsi/bl_power
echo $val > /sys/class/backlight/backlight-dsi/brightness
echo \"  bl=$(cat /sys/class/backlight/backlight-dsi/bl_power) br=$(cat /sys/class/backlight/backlight-dsi/brightness)/$(cat /sys/class/backlight/backlight-dsi/max_brightness)\""
}
