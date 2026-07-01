#!/usr/bin/env bash
# marathon.d/phase1.sh — daily-drivers.
#
# Subcommands: status, deploy, reset, wake, unlock, snap, logs, apps, launch.
# Each is a Bash function named cmd_<verb>; the dispatcher in
# scripts/marathon looks them up.

# shellcheck source=common.sh
# common.sh already sourced by dispatcher; declarations available.

# ── status ──────────────────────────────────────────────────────────
cmd_status() {
    marathon::info "device: $MARATHON_DEVICE ($MARATHON_DEVICE_KIND) → $MARATHON_HOST"
    if ! marathon::ssh::alive; then
        marathon::error "unreachable"
        return 1
    fi
    # One SSH round-trip to gather everything.
    marathon::ssh 'echo "=== shell ==="
pid=$(pidof marathon-shell-bin 2>/dev/null || echo none)
if [ "$pid" != "none" ]; then
  hash=$(sha256sum /usr/bin/marathon-shell-bin | cut -c1-16)
  uptime_s=$(awk "{print int(\$1)}" /proc/uptime)
  echo "  pid=$pid  hash=$hash  boot-uptime=${uptime_s}s"
else
  echo "  NOT RUNNING"
fi
echo "=== display ==="
BL=/sys/class/backlight/backlight-dsi
if [ -d "$BL" ]; then
  echo "  bl_power=$(cat $BL/bl_power) brightness=$(cat $BL/brightness)/$(cat $BL/max_brightness) actual=$(cat $BL/actual_brightness)"
fi
echo "=== cpu ==="
gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo ?)
cur=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo ?)
load=$(awk "{print \$1}" /proc/loadavg)
echo "  gov=$gov  cur=${cur}kHz  load=$load"
echo "=== battery ==="
BAT=/sys/class/power_supply/max170xx_battery
if [ -d "$BAT" ]; then
  status=$(cat $BAT/status)
  cap=$(cat $BAT/capacity)
  temp=$(cat $BAT/temp)
  volt=$(cat $BAT/voltage_now)
  echo "  ${cap}%  ${status}  $(awk -v t=$temp "BEGIN{printf \"%.1f°C\", t/10}")  $(awk -v v=$volt "BEGIN{printf \"%.2fV\", v/1000000}")"
fi'
}

# ── deploy ──────────────────────────────────────────────────────────
cmd_deploy() {
    local mode="hot"
    local skip_build=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --hot)  mode=hot; shift ;;
            --full) mode=full; shift ;;
            --skip-build) skip_build=1; shift ;;
            *) marathon::error "deploy: unknown flag $1"; return 2 ;;
        esac
    done

    marathon::askpass::ensure || return 1

    local pkgrel
    pkgrel="$(grep -oE '^pkgrel=[0-9]+' \
        "$MARATHON_IMAGE/packages/marathon-shell/APKBUILD" | cut -d= -f2)"
    marathon::info "target: r$pkgrel · $mode deploy · device $MARATHON_DEVICE"

    local apk
    apk="$(ls -t "$HOME/.local/var/pmbootstrap-work/packages/edge/aarch64/marathon-shell-1.0.0_"*"-r${pkgrel}.apk" 2>/dev/null | head -1)"

    if [ "$skip_build" = "0" ] && [ -z "$apk" ]; then
        marathon::step "no APK for r$pkgrel — building"
        cmd_build_shell || return 1
        apk="$(ls -t "$HOME/.local/var/pmbootstrap-work/packages/edge/aarch64/marathon-shell-1.0.0_"*"-r${pkgrel}.apk" 2>/dev/null | head -1)"
    fi
    [ -n "$apk" ] || { marathon::error "no APK found for r$pkgrel"; return 1; }
    marathon::debug "apk: $apk"

    # Extract to scratch.
    local extract="$MARATHON_SCRATCH/apk-r$pkgrel"
    if [ ! -f "$extract/usr/bin/marathon-shell-bin" ]; then
        mkdir -p "$extract"
        tar -xzf "$apk" -C "$extract" 2>/dev/null || true
    fi
    local local_bin="$extract/usr/bin/marathon-shell-bin"
    [ -f "$local_bin" ] || { marathon::error "APK extract missing binary"; return 1; }
    local local_hash
    local_hash="$(sha256sum "$local_bin" | cut -c1-16)"

    marathon::step "push binary to device (r$pkgrel · $local_hash)"
    marathon::scp "$local_bin" '/tmp/marathon-shell-bin.new' >/dev/null

    marathon::step "atomic replace + restart greetd"
    marathon::ssh 'mv /tmp/marathon-shell-bin.new /usr/bin/marathon-shell-bin && chmod 755 /usr/bin/marathon-shell-bin && systemctl restart greetd' >/dev/null

    marathon::step "wait for shell up"
    local deadline=$(( $(date +%s) + 30 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if marathon::ssh 'pidof marathon-shell-bin' >/dev/null 2>&1; then
            local remote_hash
            remote_hash="$(marathon::ssh 'sha256sum /usr/bin/marathon-shell-bin | cut -c1-16' 2>/dev/null)"
            if [ "$remote_hash" = "$local_hash" ]; then
                marathon::success "deployed r$pkgrel · hash $local_hash · shell up"
                return 0
            fi
        fi
        sleep 1
    done
    marathon::error "shell didn't come up cleanly"
    return 1
}

# Build the shell APK via pmbootstrap. Called by deploy when needed.
cmd_build_shell() {
    marathon::askpass::ensure || return 1
    local pkgrel
    pkgrel="$(grep -oE '^pkgrel=[0-9]+' \
        "$MARATHON_IMAGE/packages/marathon-shell/APKBUILD" | cut -d= -f2)"
    marathon::info "build shell r$pkgrel from $MARATHON_SRC"
    # Keep pmbootstrap's aports in sync with ours.
    cp "$MARATHON_IMAGE/packages/marathon-shell/APKBUILD" \
       "$HOME/pmaports-upstream/main/marathon-shell/APKBUILD"
    pmbootstrap -y build --force marathon-shell \
        --arch=aarch64 --src="$MARATHON_SRC" 2>&1 | tail -5
}

# ── reset ───────────────────────────────────────────────────────────
cmd_reset() {
    marathon::info "restart greetd (safer than pkill)"
    marathon::ssh 'systemctl restart greetd'
    marathon::step "wait for shell"
    marathon::wait_reachable 30 || return 1
    local deadline=$(( $(date +%s) + 20 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        marathon::ssh 'pidof marathon-shell-bin' >/dev/null 2>&1 && \
            { marathon::success "shell back up"; return 0; }
        sleep 1
    done
    marathon::error "shell didn't respawn"
    return 1
}

# ── wake ────────────────────────────────────────────────────────────
cmd_wake() {
    marathon::ssh 'echo 0 > /sys/class/backlight/backlight-dsi/bl_power
echo 200 > /sys/class/backlight/backlight-dsi/brightness
echo "  bl=$(cat /sys/class/backlight/backlight-dsi/bl_power) br=$(cat /sys/class/backlight/backlight-dsi/brightness)"'
    marathon::success "backlight forced on (bl=0, br=200)"
}

# ── unlock ──────────────────────────────────────────────────────────
# Digit tap coordinates for the PIN keypad on 720x1440 device:
#   1=(195,400)  2=(360,400)  3=(525,400)
#   4=(195,560)  5=(360,560)  6=(525,560)
#   7=(195,715)  8=(360,715)  9=(525,715)
#   0=(360,875)
# shellcheck disable=SC2120  # called with 0 or 1 arg (PIN override)
cmd_unlock() {
    local pin="${1:-$MARATHON_PIN}"
    [ ${#pin} -ne 6 ] && { marathon::error "PIN must be 6 digits"; return 2; }

    marathon::info "unlock (PIN len=${#pin})"
    marathon::step "swipe up from lock screen"
    marathon::ssh 'marathon-touchctl swipe 360 1300 360 400 30' >/dev/null 2>&1 || true
    sleep 2

    marathon::step "enter PIN"
    local i=0
    while [ $i -lt ${#pin} ]; do
        local d="${pin:$i:1}"
        local coord
        case "$d" in
            0) coord="360 875" ;;
            1) coord="195 400" ;;
            2) coord="360 400" ;;
            3) coord="525 400" ;;
            4) coord="195 560" ;;
            5) coord="360 560" ;;
            6) coord="525 560" ;;
            7) coord="195 715" ;;
            8) coord="360 715" ;;
            9) coord="525 715" ;;
            *) marathon::error "invalid digit '$d'"; return 2 ;;
        esac
        marathon::ssh "marathon-touchctl tap $coord" >/dev/null 2>&1 || true
        sleep 0.4
        i=$((i + 1))
    done
    sleep 3

    if marathon::ssh 'pgrep -f app-runner >/dev/null || cat /sys/class/backlight/backlight-dsi/bl_power' \
            2>/dev/null | grep -q '^0$'; then
        marathon::success "unlocked (screen on)"
    else
        marathon::success "unlock sent (verify with 'marathon snap')"
    fi
}

# ── snap ────────────────────────────────────────────────────────────
cmd_snap() {
    local label="${1:-snap-$(date +%H%M%S)}"
    local out="$MARATHON_SCRATCH/$label.png"
    mkdir -p "$MARATHON_SCRATCH"
    marathon::ssh 'PID=$(pgrep -f marathon-shell-bin | head -1)
rm -f /tmp/marathon-shot.png
kill -USR1 $PID
prev=-1
for i in $(seq 1 40); do
  sleep 0.1
  cur=$(stat -c %s /tmp/marathon-shot.png 2>/dev/null || echo 0)
  if [ "$cur" -gt 0 ] && [ "$cur" = "$prev" ]; then
    tail=$(tail -c 4 /tmp/marathon-shot.png 2>/dev/null | od -An -tx1 | tr -d " ")
    [ "$tail" = "ae426082" ] && break
  fi
  prev=$cur
done' 2>/dev/null
    local raw="$MARATHON_SCRATCH/.$label.raw.png"
    sshpass -p "$MARATHON_PASSWORD" scp \
        -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR "$MARATHON_HOST:/tmp/marathon-shot.png" "$raw" 2>/dev/null
    magick "$raw" -strip -define png:color-type=6 "$out" 2>/dev/null \
        || convert "$raw" -strip "$out" 2>/dev/null
    rm -f "$raw"
    if [ -f "$out" ]; then
        marathon::success "$out ($(stat -c %s "$out") B)"
    else
        marathon::error "snap failed"
        return 1
    fi
}

# ── logs ────────────────────────────────────────────────────────────
cmd_logs() {
    local follow=0
    local grep_pattern=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -f|--follow) follow=1; shift ;;
            --warnings) grep_pattern="WARNING"; shift ;;
            *) grep_pattern="$1"; shift ;;
        esac
    done

    local cmd='cat /home/user/.marathon/crash.log 2>/dev/null | grep -vE "\\[AppRunner stderr\\]"'
    [ -n "$grep_pattern" ] && cmd="$cmd | grep -iE \"$grep_pattern\""
    if [ "$follow" = "1" ]; then
        cmd='tail -Fn 20 /home/user/.marathon/crash.log 2>/dev/null | grep -vE "\\[AppRunner stderr\\]"'
        [ -n "$grep_pattern" ] && cmd="$cmd | grep -iE \"$grep_pattern\" --line-buffered"
        marathon::info "tailing shell log (Ctrl-C to stop)"
        marathon::ssh "$cmd"
    else
        marathon::ssh "$cmd | tail -30"
    fi
}

# ── apps ────────────────────────────────────────────────────────────
cmd_apps() {
    marathon::ssh 'echo "  APP-ID       PID       UCLAMP  FREEZE  PROCS  STATE"
for CG in /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-apps/marathon-app-*/; do
  a=$(basename "$CG" | sed s/marathon-app-//)
  u=$(cat "$CG"/cpu.uclamp.min 2>/dev/null | cut -d. -f1)
  f=$(cat "$CG"/cgroup.freeze 2>/dev/null)
  procs=$(cat "$CG"/cgroup.procs 2>/dev/null)
  pid="-"
  n=0
  if [ -n "$procs" ]; then
    pid=$(echo "$procs" | head -1)
    n=$(echo "$procs" | wc -l)
  fi
  state="idle"
  if [ "$n" != "0" ]; then
    if [ "$f" = "1" ]; then state="frozen"
    elif [ "${u:-0}" -ge 30 ]; then state="foreground"
    else state="background"
    fi
  fi
  printf "  %-12s %-9s %-7s %-7s %-6s %s\n" "$a" "$pid" "${u:-0}" "${f:-0}" "$n" "$state"
done'
}

# ── launch APPID ───────────────────────────────────────────────────
# Icon coordinates (720x1440 device, standard 4-column app grid on
# home page 1). Only the ~14 pinned apps.
_marathon_icon_coord() {
    case "$1" in
        phone)      echo "100 320" ;;
        messages)   echo "270 320" ;;
        mail)       echo "440 320" ;;
        browser)    echo "610 320" ;;
        store)      echo "100 610" ;;
        music)      echo "270 610" ;;
        camera)     echo "440 610" ;;
        gallery)    echo "610 610" ;;
        maps)       echo "100 890" ;;
        calendar)   echo "270 890" ;;
        clock)      echo "440 890" ;;
        calculator) echo "610 890" ;;
        notes)      echo "100 1180" ;;
        settings)   echo "270 1180" ;;
        *) return 1 ;;
    esac
}

cmd_launch() {
    local app="${1:-}"
    [ -z "$app" ] && { marathon::error "usage: marathon launch <appId>"; return 2; }
    local coord
    coord="$(_marathon_icon_coord "$app")" || {
        marathon::error "unknown app '$app' — supported: phone messages mail browser store music camera gallery maps calendar clock calculator notes settings"
        return 2
    }
    marathon::info "launch $app at ($coord)"

    # If already running, just make sure it's foreground: DBus or tap.
    if marathon::ssh "pgrep -f 'app-runner --app-id $app' >/dev/null 2>&1"; then
        marathon::success "$app already running — tapping to bring foreground"
    fi

    # Screen off? wake first.
    local bl
    bl="$(marathon::ssh 'cat /sys/class/backlight/backlight-dsi/bl_power' 2>/dev/null || echo 4)"
    [ "$bl" = "4" ] && cmd_wake >/dev/null
    # Lockscreen? unlock first.
    local locked
    locked="$(marathon::ssh 'pgrep -f "app-runner" | head -1' 2>/dev/null || true)"
    if [ -z "$locked" ]; then
        # Best-effort: unlock. If we're not actually at lockscreen this is harmless.
        cmd_unlock >/dev/null 2>&1 || true
    fi

    marathon::ssh "marathon-touchctl tap $coord" >/dev/null 2>&1
    sleep 3
    if marathon::ssh "pgrep -f 'app-runner --app-id $app' >/dev/null"; then
        marathon::success "$app running"
    else
        marathon::warn "$app did not appear — check 'marathon snap' and re-tap"
    fi
}
