#!/usr/bin/env bash
# marathon.d/phase5.sh — doctor / self-heal.
#
# `marathon doctor` runs a sequence of environment + device checks and
# reports pass/fail for each. `marathon doctor --fix` also attempts
# auto-repair for the known-fixable cases.

# shellcheck source=common.sh  # _c_* colors come from here at runtime
# shellcheck disable=SC2154    # sourced by dispatcher

# ── check runner infrastructure ─────────────────────────────────────
#
# Each check is a function `_check_<name>` that:
#   - prints a one-line ✓/✗ status to stdout
#   - returns 0 on pass, 1 on fail
#   - has a companion `_fix_<name>` that returns 0 if auto-fix worked
#
# Order matters — host-side checks run first (askpass, pmbootstrap) so
# device-side checks (which need SSH) can rely on them.

_marathon_doctor_pass=0
_marathon_doctor_fail=0
_marathon_doctor_fixed=0

_check() {
    local name="$1"; shift
    local desc="$1"; shift
    local fn="_check_$name"
    printf '  %-40s ' "$desc"
    if "$fn" >/dev/null 2>&1; then
        echo "${_c_green}✓${_c_reset}"
        _marathon_doctor_pass=$((_marathon_doctor_pass + 1))
        return 0
    else
        echo "${_c_red}✗${_c_reset}"
        _marathon_doctor_fail=$((_marathon_doctor_fail + 1))
        if [ "${1:-}" = "--fix" ] || [ "${MARATHON_DOCTOR_FIX:-0}" = "1" ]; then
            local fix_fn="_fix_$name"
            if declare -F "$fix_fn" >/dev/null 2>&1; then
                printf '    %s attempting fix... ' "${_c_yellow}→${_c_reset}"
                if "$fix_fn" >/dev/null 2>&1; then
                    echo "${_c_green}fixed${_c_reset}"
                    _marathon_doctor_fixed=$((_marathon_doctor_fixed + 1))
                    return 0
                fi
                echo "${_c_red}couldn't auto-fix${_c_reset}"
            fi
        fi
        return 1
    fi
}

# ── individual checks ──────────────────────────────────────────────

_check_askpass() { [ -x /tmp/askpass.sh ]; }
_fix_askpass()   { marathon::askpass::ensure; }

_check_askpass_source() { [ -x "$HOME/.marathon-secrets/askpass.sh" ]; }

_check_pmbootstrap() { command -v pmbootstrap >/dev/null 2>&1; }

_check_pmbootstrap_config() {
    [ -f "$HOME/.config/pmbootstrap_v3.cfg" ] && \
        grep -q "aports.*pmaports" "$HOME/.config/pmbootstrap_v3.cfg"
}

_check_marathon_src() {
    [ -d "$MARATHON_SRC" ] && [ -f "$MARATHON_SRC/shell/main.cpp" ]
}

_check_marathon_image() {
    [ -d "$MARATHON_IMAGE" ] && [ -f "$MARATHON_IMAGE/packages/marathon-shell/APKBUILD" ]
}

_check_sshpass() { command -v sshpass >/dev/null 2>&1; }

_check_evdev_python() {
    marathon::ssh 'python3 -c "import evdev"' >/dev/null 2>&1
}

_check_device_reachable() { marathon::ssh::alive; }

_check_shell_running() {
    marathon::ssh 'pidof marathon-shell-bin' >/dev/null 2>&1
}

_check_shell_hash_matches() {
    local pkgrel latest_apk local_hash remote_hash
    pkgrel="$(grep -oE '^pkgrel=[0-9]+' \
        "$MARATHON_IMAGE/packages/marathon-shell/APKBUILD" | cut -d= -f2)"
    latest_apk="$(ls -t "$HOME/.local/var/pmbootstrap-work/packages/edge/aarch64/marathon-shell-1.0.0_"*"-r${pkgrel}.apk" 2>/dev/null | head -1)"
    [ -n "$latest_apk" ] || return 1
    local extract="$MARATHON_SCRATCH/apk-r$pkgrel"
    [ -f "$extract/usr/bin/marathon-shell-bin" ] || {
        mkdir -p "$extract"; tar -xzf "$latest_apk" -C "$extract" 2>/dev/null; }
    local_hash="$(sha256sum "$extract/usr/bin/marathon-shell-bin" 2>/dev/null | cut -c1-16)"
    remote_hash="$(marathon::ssh 'sha256sum /usr/bin/marathon-shell-bin' 2>/dev/null | cut -c1-16)"
    [ "$local_hash" = "$remote_hash" ]
}
_fix_shell_hash_matches() { cmd_deploy --skip-build; }

_check_iw_cap() {
    marathon::ssh 'getcap /usr/sbin/iw | grep -q cap_net_admin' 2>/dev/null
}
_fix_iw_cap() {
    marathon::ssh 'systemctl restart marathon-iw-setcap.service && getcap /usr/sbin/iw | grep -q cap_net_admin'
}

_check_oom_service() {
    marathon::ssh 'systemctl is-active marathon-shell-oom.service' >/dev/null 2>&1
}
_fix_oom_service() { marathon::ssh 'systemctl restart marathon-shell-oom.service'; }

_check_cpu_governor() {
    marathon::ssh 'systemctl is-active marathon-cpu-governor.service' >/dev/null 2>&1 || \
    marathon::ssh 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor' 2>/dev/null | grep -q ondemand
}
_fix_cpu_governor() {
    marathon::ssh 'systemctl restart marathon-cpu-governor.service 2>/dev/null || for g in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do echo ondemand > $g 2>/dev/null; done'
}

_check_mm_tune() {
    marathon::ssh 'systemctl is-active marathon-mm-tune.service' >/dev/null 2>&1 || \
    marathon::ssh 'cat /proc/sys/vm/swappiness' 2>/dev/null | grep -q '^100$'
}
_fix_mm_tune() { marathon::ssh 'systemctl restart marathon-mm-tune.service 2>/dev/null'; }

_check_cgroup_cpu_delegated() {
    marathon::ssh 'cat /sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-apps/cgroup.subtree_control 2>/dev/null | grep -q cpu' 2>/dev/null
}

_check_uclamp_writable() {
    marathon::ssh 'CG=/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-apps
for app in "$CG"/marathon-app-*/cpu.uclamp.min; do
    [ -e "$app" ] || continue
    owner=$(stat -c %u "$app" 2>/dev/null)
    if [ "$owner" != "1000" ]; then
        exit 1
    fi
done
exit 0' 2>/dev/null
}
_fix_uclamp_writable() { _fix_oom_service; }

_check_backlight_present() {
    marathon::ssh '[ -e /sys/class/backlight/backlight-dsi/bl_power ]'
}

_check_battery_temp_ok() {
    local temp
    temp="$(marathon::ssh 'cat /sys/class/power_supply/max170xx_battery/temp' 2>/dev/null)"
    [ -n "$temp" ] && [ "$temp" -lt 550 ]
}

_check_battery_health_ok() {
    marathon::ssh 'awk -v f=$(cat /sys/class/power_supply/max170xx_battery/charge_full) -v d=$(cat /sys/class/power_supply/max170xx_battery/charge_full_design) "BEGIN{exit (100*f/d < 70) ? 1 : 0}"' 2>/dev/null
}

_check_modem_registered() {
    marathon::ssh 'mmcli -m 0 2>/dev/null | grep -q "state: registered"'
}

_check_wifi_up() {
    marathon::ssh 'iw dev wlan0 link 2>/dev/null | grep -q SSID'
}

# ── doctor entry point ────────────────────────────────────────────
cmd_doctor() {
    local fix=0
    case "${1:-}" in
        --fix|-f) fix=1; shift ;;
    esac
    [ "$fix" = "1" ] && export MARATHON_DOCTOR_FIX=1

    echo
    echo "  Marathon doctor · $MARATHON_DEVICE ($MARATHON_DEVICE_KIND) → $MARATHON_HOST"
    echo "  $(date +'%Y-%m-%d %H:%M:%S')"
    echo

    echo "  --- host env ---"
    _check askpass          "askpass at /tmp/askpass.sh (chmod 700)"
    _check askpass_source   "askpass source at ~/.marathon-secrets/"
    _check pmbootstrap      "pmbootstrap on PATH"
    _check pmbootstrap_config "pmbootstrap aports configured"
    _check marathon_src     "MARATHON_SRC exists + has shell/"
    _check marathon_image   "MARATHON_IMAGE exists + has APKBUILD"
    _check sshpass          "sshpass on PATH"
    echo

    echo "  --- device connectivity ---"
    _check device_reachable "device reachable"
    if [ "$_marathon_doctor_fail" -gt 0 ]; then
        echo
        marathon::warn "device unreachable — skipping remaining checks"
        _summarize
        return 1
    fi
    _check evdev_python     "python3-evdev on device"
    echo

    echo "  --- shell state ---"
    _check shell_running    "marathon-shell-bin process alive"
    _check shell_hash_matches "deployed binary matches latest r$(grep -oE '^pkgrel=[0-9]+' "$MARATHON_IMAGE/packages/marathon-shell/APKBUILD" | cut -d= -f2) APK"
    echo

    echo "  --- boot-time services ---"
    _check iw_cap           "iw has cap_net_admin"
    _check oom_service      "marathon-shell-oom.service active"
    _check cpu_governor     "cpufreq governor = ondemand"
    _check mm_tune          "vm.swappiness = 100"
    echo

    echo "  --- cgroup + uclamp ---"
    _check cgroup_cpu_delegated "cpu controller delegated to marathon-apps"
    _check uclamp_writable  "cpu.uclamp.min owned by uid 1000"
    echo

    echo "  --- hardware ---"
    _check backlight_present "backlight-dsi present"
    _check battery_temp_ok  "battery temp < 55°C"
    _check battery_health_ok "battery health > 70%"
    _check modem_registered "modem registered on network"
    _check wifi_up          "wifi associated"
    echo

    _summarize
}

_summarize() {
    local msg="passed $_marathon_doctor_pass · failed $_marathon_doctor_fail"
    [ "$_marathon_doctor_fixed" -gt 0 ] && msg="$msg · fixed $_marathon_doctor_fixed"
    if [ "$_marathon_doctor_fail" -gt "$_marathon_doctor_fixed" ]; then
        marathon::warn "$msg"
        return 1
    fi
    marathon::success "$msg"
    return 0
}
