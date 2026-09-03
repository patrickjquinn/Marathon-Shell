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
    while IFS= read -r line <&3; do
        [ -z "$line" ] || [[ "$line" =~ ^# ]] && continue
        step=$((step + 1))
        marathon::step "[$step] $line"
        # Redirect the sub-command's stdin from /dev/null so SSH (or
        # anything else that reads stdin) doesn't drain the remaining
        # session lines out from under our while loop. FD 3 keeps our
        # loop's stream separate from the sub-command's stdin.
        # shellcheck disable=SC2086
        "$MARATHON_CLI_DIR/marathon" $line </dev/null || marathon::warn "step $step failed"
    done 3< "$path"
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
    cmd_wake >/dev/null
    sleep 1
    # Poll ON DEVICE — inject KEY_POWER + tight loop reading bl_power.
    # Doing this via one SSH invocation eliminates the per-poll network
    # round-trip that was dominating the measurement (~3 s of noise vs
    # actual sub-300 ms latency).
    local ms
    ms="$(marathon::ssh 'python3 - <<PYEOF 2>/dev/null
from evdev import UInput, ecodes as e
import time
ui = UInput({e.EV_KEY: [e.KEY_POWER]}, name="marathon-bench")
time.sleep(0.2)
BL = "/sys/class/backlight/backlight-dsi/bl_power"
def read(): return open(BL).read().strip()
if read() == "4":
    print("already-doze"); raise SystemExit
t0 = time.monotonic_ns()
ui.write(e.EV_KEY, e.KEY_POWER, 1); ui.syn(); time.sleep(0.08)
ui.write(e.EV_KEY, e.KEY_POWER, 0); ui.syn()
ui.close()
while True:
    if read() == "4": break
    if (time.monotonic_ns() - t0) > 2_000_000_000: print("timeout"); raise SystemExit
    time.sleep(0.005)
print(int((time.monotonic_ns() - t0) / 1_000_000))
PYEOF')"
    case "$ms" in
        already-doze) marathon::warn "already in Doze — cmd_wake didn't take" ;;
        timeout)      marathon::error "timed out waiting for bl_power=4" ;;
        [0-9]*)       marathon::success "enter Doze: $ms ms" ;;
        *)            marathon::error "unexpected bench output: $ms" ;;
    esac
}

_bench_wake() {
    marathon::info "bench: wake latency"
    cmd_doze_enter >/dev/null 2>&1
    sleep 1
    local ms
    ms="$(marathon::ssh 'python3 - <<PYEOF 2>/dev/null
from evdev import UInput, ecodes as e
import time
ui = UInput({e.EV_KEY: [e.KEY_POWER]}, name="marathon-bench")
time.sleep(0.2)
BL = "/sys/class/backlight/backlight-dsi/bl_power"
def read(): return open(BL).read().strip()
if read() == "0":
    print("already-awake"); raise SystemExit
t0 = time.monotonic_ns()
ui.write(e.EV_KEY, e.KEY_POWER, 1); ui.syn(); time.sleep(0.08)
ui.write(e.EV_KEY, e.KEY_POWER, 0); ui.syn()
ui.close()
while True:
    if read() == "0": break
    if (time.monotonic_ns() - t0) > 2_000_000_000: print("timeout"); raise SystemExit
    time.sleep(0.005)
print(int((time.monotonic_ns() - t0) / 1_000_000))
PYEOF')"
    case "$ms" in
        already-awake) marathon::warn "already awake — cmd_doze_enter didn't take" ;;
        timeout)       marathon::error "timed out waiting for bl_power=0" ;;
        [0-9]*)        marathon::success "wake: $ms ms" ;;
        *)             marathon::error "unexpected bench output: $ms" ;;
    esac
}

_bench_foreground_boost() {
    marathon::info "bench: uclamp foreground boost end-to-end"

    # Two-stage test that observes the shell doing its job, doesn't
    # try to poke it:
    #   Stage A — read the current foreground: does any app have
    #             uclamp.min=30? if so, boost is working right now.
    #   Stage B — launch a different app, observe the demote of the
    #             old fg + the promote of the new fg.
    #
    # This avoids the false-negative shape where we "reset uclamp
    # then wait for the shell to notice" — the shell only writes
    # uclamp on state transitions, not on external file writes.

    marathon::step "Stage A: current foreground has uclamp=30?"
    local current_fg current_u
    current_fg="$(marathon::ssh 'for CG in /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-apps/marathon-app-*/; do
        u=$(cat "$CG"/cpu.uclamp.min 2>/dev/null | cut -d. -f1)
        if [ "$u" = "30" ]; then basename "$CG" | sed s/marathon-app-//; exit; fi
    done')" || true

    if [ -n "$current_fg" ]; then
        marathon::success "Stage A ✓  foreground app '$current_fg' has uclamp.min=30"
    else
        current_u="$(marathon::ssh 'for CG in /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-apps/marathon-app-*/; do
            procs=$(cat "$CG"/cgroup.procs 2>/dev/null)
            u=$(cat "$CG"/cpu.uclamp.min 2>/dev/null)
            f=$(cat "$CG"/cgroup.freeze 2>/dev/null)
            n=$(basename "$CG" | sed s/marathon-app-//)
            [ -n "$procs" ] && [ "$f" = "0" ] && printf "  %s: uclamp=%s (running, unfrozen)\n" "$n" "$u"
        done')" || true
        if [ -n "$current_u" ]; then
            marathon::warn "Stage A ✗  no app is at uclamp=30, but these are running unfrozen:"
            echo "$current_u"
            marathon::info "  → 'marathon launch <appId>' to bring one foreground, then rerun bench"
            return 1
        fi
        marathon::warn "Stage A ✗  no app is currently foreground"
        marathon::info "  → 'marathon launch notes' (or any app), then rerun bench"
        return 1
    fi

    # Stage B: pick a different app and swap. We look for a running-
    # frozen sibling to promote; if there isn't one, skip Stage B.
    local swap_target
    swap_target="$(marathon::ssh "for CG in /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-apps/marathon-app-*/; do
        n=\$(basename \"\$CG\" | sed s/marathon-app-//)
        [ \"\$n\" = \"$current_fg\" ] && continue
        procs=\$(cat \"\$CG\"/cgroup.procs 2>/dev/null)
        [ -n \"\$procs\" ] && { echo \"\$n\"; exit; }
    done")"

    if [ -z "$swap_target" ]; then
        marathon::info "Stage B skipped — no other running app to swap with"
        marathon::success "bench: foreground boost verified via Stage A"
        return 0
    fi

    marathon::step "Stage B: launch '$swap_target' → expect ${current_fg}→0 + ${swap_target}→30"
    cmd_launch "$swap_target" >/dev/null 2>&1
    sleep 3

    local new_fg_u prev_fg_u
    new_fg_u="$(marathon::ssh "cat /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-apps/marathon-app-$swap_target/cpu.uclamp.min" 2>/dev/null | cut -d. -f1)"
    prev_fg_u="$(marathon::ssh "cat /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-apps/marathon-app-$current_fg/cpu.uclamp.min" 2>/dev/null | cut -d. -f1)"

    if [ "$new_fg_u" = "30" ] && [ "$prev_fg_u" != "30" ]; then
        marathon::success "Stage B ✓  ${current_fg} → uclamp=$prev_fg_u, ${swap_target} → uclamp=$new_fg_u"
    else
        marathon::warn "Stage B ✗  ${current_fg}=$prev_fg_u, ${swap_target}=$new_fg_u (expected 0 + 30)"
        return 1
    fi

    marathon::success "bench: foreground boost verified end-to-end"
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
