#!/usr/bin/env bash
# marathon.d/phase8.sh — persistent dev sessions (named test scenarios).
#
# Record a sequence of commands, replay later, diff snapshots vs baseline.
#
#   marathon session new NAME               start recording
#   marathon session record NAME <verb…>    append a step
#   marathon session run NAME               replay
#   marathon session diff NAME              diff snapshots vs baseline
#   marathon session list                   list saved sessions
#   marathon session rm NAME                delete
#
#   marathon bench <suite>                  canned benchmarks
#                                             doze / wake / foreground-boost
#
# shellcheck source=common.sh
# shellcheck disable=SC2154

MARATHON_SESSIONS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/marathon-dev/sessions"

_session_path() { echo "$MARATHON_SESSIONS_DIR/$1.session"; }

cmd_session_new() {
    local name="${1:-}"
    [ -z "$name" ] && { marathon::error "usage: marathon session new NAME"; return 2; }
    mkdir -p "$MARATHON_SESSIONS_DIR"
    local path
    path="$(_session_path "$name")"
    if [ -e "$path" ]; then
        marathon::error "session '$name' exists"
        return 1
    fi
    {
        echo "# Marathon session: $name"
        echo "# Created: $(date -Iseconds)"
        echo "# Each non-comment line is a verb passed to 'marathon'."
    } > "$path"
    marathon::success "created $path — 'marathon session record $name <verb>' to add steps"
}

cmd_session_record() {
    local name="${1:-}"; shift || true
    [ -z "$name" ] || [ $# -eq 0 ] && { marathon::error "usage: marathon session record NAME <verb…>"; return 2; }
    local path
    path="$(_session_path "$name")"
    [ ! -f "$path" ] && { marathon::error "no session '$name' — 'marathon session new $name' first"; return 1; }
    echo "$*" >> "$path"
    marathon::success "recorded: $*"
}

cmd_session_run() {
    local name="${1:-}"
    [ -z "$name" ] && { marathon::error "usage: marathon session run NAME"; return 2; }
    local path
    path="$(_session_path "$name")"
    [ ! -f "$path" ] && { marathon::error "no session '$name'"; return 1; }
    marathon::info "running session: $name"
    local step=0
    while IFS= read -r line; do
        [ -z "$line" ] || [[ "$line" =~ ^# ]] && continue
        step=$((step + 1))
        marathon::step "[$step] $line"
        # shellcheck disable=SC2086
        "$MARATHON_CLI_DIR/marathon" $line || marathon::warn "step $step failed"
    done < "$path"
    marathon::success "session done ($step steps)"
}

cmd_session_list() {
    if [ ! -d "$MARATHON_SESSIONS_DIR" ] || [ -z "$(ls -A "$MARATHON_SESSIONS_DIR" 2>/dev/null)" ]; then
        echo "  no saved sessions at $MARATHON_SESSIONS_DIR"
        return
    fi
    printf '  %-20s %-8s %s\n' NAME STEPS CREATED
    for f in "$MARATHON_SESSIONS_DIR"/*.session; do
        [ -f "$f" ] || continue
        local name steps created
        name="$(basename "$f" .session)"
        steps="$(grep -vcE '^\s*(#|$)' "$f")"
        created="$(grep '^# Created:' "$f" | sed 's/^# Created: //')"
        printf '  %-20s %-8s %s\n' "$name" "$steps" "$created"
    done
}

cmd_session_rm() {
    local name="${1:-}"
    [ -z "$name" ] && { marathon::error "usage: marathon session rm NAME"; return 2; }
    local path
    path="$(_session_path "$name")"
    [ ! -f "$path" ] && { marathon::error "no session '$name'"; return 1; }
    rm -f "$path"
    marathon::success "removed: $name"
}

cmd_session_diff() {
    local name="${1:-}"
    [ -z "$name" ] && { marathon::error "usage: marathon session diff NAME"; return 2; }
    marathon::info "compare snapshots in $MARATHON_SCRATCH matching '$name-*'"
    # Just list matching snaps for now; real image diff can be added later.
    ls -la "$MARATHON_SCRATCH/$name"-*.png 2>/dev/null | head -20
}

cmd_session() {
    marathon::error "usage: marathon session <new|record|run|list|rm|diff>"
    return 2
}

# ── bench <suite> ───────────────────────────────────────────────────
cmd_bench() {
    local suite="${1:-}"
    case "$suite" in
        doze)             _bench_doze ;;
        wake)             _bench_wake ;;
        foreground-boost) _bench_foreground_boost ;;
        battery-idle)     _bench_battery_idle ;;
        *) marathon::error "usage: marathon bench <doze|wake|foreground-boost|battery-idle>"; return 2 ;;
    esac
}

_bench_doze() {
    marathon::info "bench: doze enter latency"
    # Wake first
    cmd_wake >/dev/null
    sleep 1
    local t0 t1
    t0="$(date +%s%N)"
    cmd_power >/dev/null 2>&1
    # Poll bl_power until 4
    while :; do
        local bl
        bl="$(marathon::ssh 'cat /sys/class/backlight/backlight-dsi/bl_power' 2>/dev/null)"
        [ "$bl" = "4" ] && break
        sleep 0.02
    done
    t1="$(date +%s%N)"
    marathon::success "enter Doze: $(( (t1 - t0) / 1000000 )) ms"
}

_bench_wake() {
    marathon::info "bench: wake latency"
    cmd_doze_enter >/dev/null 2>&1
    sleep 1
    local t0 t1
    t0="$(date +%s%N)"
    cmd_power >/dev/null 2>&1
    while :; do
        local bl
        bl="$(marathon::ssh 'cat /sys/class/backlight/backlight-dsi/bl_power' 2>/dev/null)"
        [ "$bl" = "0" ] && break
        sleep 0.02
    done
    t1="$(date +%s%N)"
    marathon::success "wake: $(( (t1 - t0) / 1000000 )) ms"
}

_bench_foreground_boost() {
    marathon::info "bench: uclamp foreground boost end-to-end"
    marathon::step "reset uclamp to 0 on all apps"
    marathon::ssh 'for f in /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-apps/marathon-app-*/cpu.uclamp.min; do
        [ -e "$f" ] && echo 0 > "$f" 2>/dev/null
    done'
    marathon::step "launch notes"
    cmd_launch notes >/dev/null 2>&1
    sleep 3
    local u
    u="$(marathon::ssh 'cat /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-apps/marathon-app-notes/cpu.uclamp.min' 2>/dev/null | cut -d. -f1)"
    if [ "$u" = "30" ]; then
        marathon::success "foreground boost applied (uclamp.min=$u)"
    else
        marathon::error "foreground boost NOT applied (uclamp.min=$u)"
        return 1
    fi
}

_bench_battery_idle() {
    marathon::info "bench: battery idle discharge (30s window · needs unplugged)"
    local status
    status="$(marathon::ssh 'cat /sys/class/power_supply/max170xx_battery/status')"
    if [ "$status" != "Discharging" ]; then
        marathon::warn "battery status is '$status' — unplug for clean numbers"
    fi
    local ch0 t0 ch1 t1
    ch0="$(marathon::ssh 'cat /sys/class/power_supply/max170xx_battery/charge_now')"
    t0="$(date +%s)"
    sleep 30
    ch1="$(marathon::ssh 'cat /sys/class/power_supply/max170xx_battery/charge_now')"
    t1="$(date +%s)"
    local dch dt
    dch=$((ch0 - ch1))
    dt=$((t1 - t0))
    awk -v dch=$dch -v dt=$dt \
        'BEGIN{if (dt>0) printf "  discharge: %.0f uAh in %ds → %.0f mA avg\n", dch, dt, dch*3.6/dt}'
}
