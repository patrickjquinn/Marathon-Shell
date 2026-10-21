# shellcheck shell=bash
# Host end-to-end harness: runs the real shell binary under Xvfb with an
# isolated HOME, runtime dir and session bus, and drives it with xdotool.
# Sourced by tests/e2e/run.sh.

E2E_REPO=${E2E_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
E2E_BUILD=${E2E_BUILD:-$E2E_REPO/build-tests}
E2E_SHELL_BIN=${E2E_SHELL_BIN:-$E2E_BUILD/shell/marathon-shell-bin}
E2E_KEEL_QML=${KEEL_QML:-/usr/lib/qt6/qml}
E2E_OUT=${E2E_OUT:-${TMPDIR:-/tmp}/marathon-e2e}
E2E_DISPLAY=${E2E_DISPLAY:-:97}
E2E_W=390
E2E_H=844
# Directory of installed apps (cmake --install of apps/ with
# -DMARATHON_APPS_DIR=...). Empty = no apps; launch flows are skipped.
E2E_APPS_DIR=${E2E_APPS_DIR:-}

E2E_PASS=0
E2E_FAIL=0
E2E_SKIP=0
E2E_RESULTS=()
E2E_STEP=0

_xvfb_pid=
_bus_pid=
_shell_pid=
_a11y_pids=
E2E_RT=
E2E_HOME=$E2E_OUT/home
E2E_SHELL_LOG=/dev/null
E2E_LAST_SHOT=

e2e_log() { printf '[e2e] %s\n' "$*" >&2; }

# Fresh profile: wipes HOME and the runtime dir.
e2e_reset_profile() {
    E2E_HOME=$E2E_OUT/home
    # Unix socket paths are capped at 108 bytes, so the runtime dir stays short.
    [ -n "$E2E_RT" ] && rm -rf "$E2E_RT"
    E2E_RT=$(mktemp -d /tmp/me2e-XXXXXX)
    rm -rf "$E2E_HOME"
    mkdir -p "$E2E_HOME/.config" "$E2E_HOME/.local/share" "$E2E_HOME/.cache"
}

e2e_start_x() {
    Xvfb "$E2E_DISPLAY" -screen 0 ${E2E_W}x${E2E_H}x24 -nolisten tcp >/dev/null 2>&1 &
    _xvfb_pid=$!
    for _ in $(seq 50); do
        DISPLAY=$E2E_DISPLAY xdotool getdisplaygeometry >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    e2e_log "Xvfb did not start"
    return 1
}

# The shell derives its session-bus address from $XDG_RUNTIME_DIR/bus
# (shell/main.cpp), so the bus must listen exactly there.
# No service directories: host services (portals, Firefox via OpenURI) must
# not be activated into the test session.
e2e_start_bus() {
    cat >"$E2E_RT/session.conf" <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:path=$E2E_RT/bus</listen>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF
    dbus-daemon --config-file="$E2E_RT/session.conf" --nofork --nopidfile >/dev/null 2>&1 &
    _bus_pid=$!
    for _ in $(seq 50); do
        [ -S "$E2E_RT/bus" ] && break
        sleep 0.1
    done
    [ -S "$E2E_RT/bus" ] || { e2e_log "dbus-daemon did not start"; return 1; }
    # AT-SPI lets checks read the text on screen; bus activation of these
    # fails outside a systemd user session, so start them by hand.
    _e2e_env /usr/libexec/at-spi-bus-launcher --launch-immediately >/dev/null 2>&1 &
    _a11y_pids="$!"
    e2e_wait_bus org.a11y.Bus 10 || { e2e_log "AT-SPI bus did not start"; return 1; }
    _e2e_env /usr/libexec/at-spi2-registryd >/dev/null 2>&1 &
    _a11y_pids="$_a11y_pids $!"
    sleep 0.5
}

# xdg-open is stubbed so a URL the shell or an app hands to the desktop is
# logged instead of opening a host browser.
_e2e_stubs() {
    mkdir -p "$E2E_OUT/stubs"
    printf '#!/bin/sh\necho "$*" >>"%s/xdg-open.log"\n' "$E2E_OUT" >"$E2E_OUT/stubs/xdg-open"
    chmod +x "$E2E_OUT/stubs/xdg-open"
}

_e2e_env() {
    env -i PATH="$E2E_OUT/stubs:/usr/bin:/bin" HOME="$E2E_HOME" USER="${USER:-e2e}" LANG=C.UTF-8 \
        XDG_RUNTIME_DIR="$E2E_RT" XDG_CONFIG_HOME="$E2E_HOME/.config" \
        XDG_DATA_HOME="$E2E_HOME/.local/share" XDG_CACHE_HOME="$E2E_HOME/.cache" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$E2E_RT/bus" DISPLAY="$E2E_DISPLAY" "$@"
}

# Runs use a copy of the binaries, so a rebuild mid-run cannot pull them
# away. The shell finds the runner at ../tools/marathon-app-runner/.
e2e_snapshot_bins() {
    local b=$E2E_OUT/bin
    mkdir -p "$b/shell" "$b/tools/marathon-app-runner" "$b/lib"
    cp "$E2E_SHELL_BIN" "$b/shell/" &&
        cp "$E2E_BUILD/tools/marathon-app-runner/marathon-app-runner" "$b/tools/marathon-app-runner/" ||
        return 1
    E2E_SHELL_BIN=$b/shell/${E2E_SHELL_BIN##*/}
    E2E_LIB_PATH=$b/lib
}

# e2e_start_shell [extra VAR=value ...]
e2e_start_shell() {
    E2E_SHELL_LOG=$E2E_OUT/shell-$E2E_SESSION.log
    _e2e_stubs
    _e2e_env MARATHON_APPS_DIR="${E2E_APPS_DIR:-$E2E_OUT/no-apps}" \
        MARATHON_FORCE_DPI=160 MARATHON_DISABLE_SANDBOX=1 MARATHON_TEST_TRUSTED=1 \
        MARATHON_WL_SOCKET_NAME=marathon-e2e-0 MARATHON_SCREENSHOT_PATH="$E2E_OUT/sigusr1.png" \
        MARATHON_RUNNER_POOL=0 MARATHON_DEBUG=1 MARATHON_FORCE_VKB=1 QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1 \
        KEEL_THEME_ICON_DIRS="$E2E_BUILD/marathon-icon-theme/themes/z1.0/icons-monochrome" \
        QML_IMPORT_PATH="$E2E_KEEL_QML:$E2E_REPO/marathon-silica:$E2E_BUILD" \
        QT_QPA_PLATFORM=xcb QT_QUICK_BACKEND=software QT_AUTO_SCREEN_SCALE_FACTOR=0 \
        QT_ENABLE_HIGHDPI_SCALING=0 QT_SCALE_FACTOR=1 ${E2E_LIB_PATH:+LD_LIBRARY_PATH="$E2E_LIB_PATH"} "$@" \
        "$E2E_SHELL_BIN" >"$E2E_SHELL_LOG" 2>&1 &
    _shell_pid=$!
    _mark=0
    e2e_wait_bus org.marathonos.Shell 30 || { e2e_log "shell never owned org.marathonos.Shell"; return 1; }
    sleep "${E2E_SETTLE:-4}"
}

e2e_stop() {
    local p
    if [ -n "$_shell_pid" ]; then
        pkill -TERM -P "$_shell_pid" 2>/dev/null
        kill "$_shell_pid" 2>/dev/null
        for _ in $(seq 30); do kill -0 "$_shell_pid" 2>/dev/null || break; sleep 0.1; done
        kill -9 "$_shell_pid" 2>/dev/null
    fi
    for p in $_a11y_pids $_bus_pid $_xvfb_pid; do kill "$p" 2>/dev/null; done
    for p in $_shell_pid $_a11y_pids $_bus_pid $_xvfb_pid; do wait "$p" 2>/dev/null; done
    _shell_pid='' _bus_pid='' _xvfb_pid='' _a11y_pids=''
}

# e2e_session <name> [shell env...]: fresh X + bus + shell, keeping the profile.
e2e_session() {
    E2E_SESSION=$1
    shift
    e2e_stop
    [ -n "$E2E_RT" ] || E2E_RT=$(mktemp -d /tmp/me2e-XXXXXX)
    e2e_start_x && e2e_start_bus && e2e_start_shell "$@"
}

e2e_alive() { [ -n "$_shell_pid" ] && kill -0 "$_shell_pid" 2>/dev/null; }

e2e_wait_log() {
    local pat=$1 t=${2:-10} i
    for i in $(seq $((t * 10))); do
        grep -q -- "$pat" "$E2E_SHELL_LOG" 2>/dev/null && return 0
        e2e_alive || return 1
        sleep 0.1
    done
    return 1
}

# Lines logged since the last e2e_mark.
e2e_mark() { _mark=$(wc -l <"$E2E_SHELL_LOG"); }
e2e_since() { tail -n +"$((${_mark:-0} + 1))" "$E2E_SHELL_LOG"; }
e2e_wait_since() {
    local pat=$1 t=${2:-10} i
    for i in $(seq 0 $((t * 10))); do
        e2e_since | grep -q -- "$pat" && return 0
        sleep 0.1
    done
    return 1
}

e2e_wait_bus() {
    local name=$1 t=${2:-10} i
    for i in $(seq $((t * 10))); do
        e2e_gdbus call -d org.freedesktop.DBus -o /org/freedesktop/DBus \
            -m org.freedesktop.DBus.NameHasOwner "$name" 2>/dev/null | grep -q true && return 0
        sleep 0.1
    done
    return 1
}

e2e_gdbus() { _e2e_env gdbus "$1" --session "${@:2}"; }

# e2e_shell <Object> <Iface> <Method> [args...]  (org.marathonos.Shell)
e2e_shell() {
    local o=$1 i=$2 m=$3
    shift 3
    e2e_gdbus call -d org.marathonos.Shell -o "/org/marathonos/Shell/$o" \
        -m "org.marathonos.Shell.$i.$m" "$@"
}

e2e_notify() { # app summary body [actions-array] [hints-dict]
    e2e_gdbus call -d org.freedesktop.Notifications -o /org/freedesktop/Notifications \
        -m org.freedesktop.Notifications.Notify "$1" 0 "" "$2" "$3" "${4:-[]}" "${5:-{\}}" 8000
}

# --- input -------------------------------------------------------------
_xdo() { DISPLAY=$E2E_DISPLAY xdotool "$@"; }

e2e_tap() {
    _xdo mousemove "$1" "$2" mousedown 1
    sleep 0.06
    _xdo mouseup 1
    sleep "${3:-0.8}"
}

e2e_longpress() {
    _xdo mousemove "$1" "$2" mousedown 1
    sleep "${3:-1.2}"
    _xdo mouseup 1
    sleep 0.8
}

# e2e_swipe x1 y1 x2 y2 [ms] [hold-at-end-ms]
e2e_swipe() {
    local x1=$1 y1=$2 x2=$3 y2=$4 ms=${5:-250} hold=${6:-0} n i x y
    n=$((ms / 16))
    [ "$n" -lt 4 ] && n=4
    _xdo mousemove "$x1" "$y1" mousedown 1
    for i in $(seq 1 "$n"); do
        x=$((x1 + (x2 - x1) * i / n))
        y=$((y1 + (y2 - y1) * i / n))
        _xdo mousemove "$x" "$y"
        sleep 0.016
    done
    [ "$hold" -gt 0 ] && sleep "$(awk "BEGIN{print $hold/1000}")"
    _xdo mouseup 1
    sleep "${E2E_AFTER_SWIPE:-1.0}"
}

e2e_type() { _xdo type --delay 60 "$1"; sleep 0.5; }
e2e_key() { _xdo key "$@"; sleep 0.4; }

# --- accessibility -----------------------------------------------------
# App surfaces sit below the shell status bar (Constants.statusBarHeight at
# this canvas and DPI).
E2E_APP_Y=${E2E_APP_Y:-17}

e2e_a11y() { _e2e_env E2E_APP_Y="$E2E_APP_Y" python3 "$E2E_REPO/tests/e2e/a11y.py" "$@"; }

# Names are looked up in the shell unless an app (AT-SPI application name,
# "marathon-app-runner" for apps) is given: background apps report their
# items as showing too.
E2E_SHELL_APP="Marathon Shell"

# True if an item named $1 (in app $2) is showing.
e2e_showing() { e2e_a11y find "$1" "${2:-$E2E_SHELL_APP}" >/dev/null; }

e2e_wait_showing() { # name [app] [timeout]
    local i
    for i in $(seq $((${3:-10} * 4))); do
        e2e_showing "$1" ${2:+"$2"} && return 0
        sleep 0.25
    done
    return 1
}

e2e_tap_name() { # name [app] [settle-seconds]
    local xy name=$1 app=$E2E_SHELL_APP settle=0.8
    shift
    if [[ ${1:-} =~ ^[0-9.]+$ ]]; then settle=$1; else app=${1:-$E2E_SHELL_APP}; settle=${2:-0.8}; fi
    xy=$(e2e_a11y find "$name" "$app") || { e2e_log "no showing item '$name'"; return 1; }
    # shellcheck disable=SC2086
    e2e_tap $xy "$settle"
}

e2e_longpress_name() {
    local xy
    xy=$(e2e_a11y find "$1" "$E2E_SHELL_APP") || { e2e_log "no showing item '$1'"; return 1; }
    # shellcheck disable=SC2086
    e2e_longpress $xy "${2:-1.2}"
}

# --- capture -----------------------------------------------------------
e2e_shot() {
    E2E_STEP=$((E2E_STEP + 1))
    E2E_LAST_SHOT=$E2E_OUT/shots/$(printf '%02d' "$E2E_STEP")-$1.png
    mkdir -p "$E2E_OUT/shots"
    local i
    for i in 1 2 3; do
        DISPLAY=$E2E_DISPLAY import -window root "$E2E_LAST_SHOT" 2>/dev/null
        [ -s "$E2E_LAST_SHOT" ] && return 0
        sleep 0.3
    done
}

# Mean luminance (0-255) of a region of the last shot: e2e_luma x y w h
e2e_luma() {
    magick "$E2E_LAST_SHOT" -crop "${3}x${4}+${1}+${2}" -colorspace Gray \
        -format '%[fx:int(mean*255)]' info: 2>/dev/null
}

# Percentage of pixels that differ between two shots.
e2e_diff_pct() {
    magick compare -metric AE -fuzz 8% "$1" "$2" null: 2>&1 | awk -v t=$((E2E_W * E2E_H)) \
        '{printf "%d", ($1 * 100) / t}'
}

# --- results -----------------------------------------------------------
e2e_check() { # e2e_check <flow> <description> <command...>
    local flow=$1 desc=$2
    shift 2
    if "$@"; then
        E2E_PASS=$((E2E_PASS + 1))
        E2E_RESULTS+=("PASS  $flow: $desc")
        e2e_log "PASS $flow: $desc"
    else
        E2E_FAIL=$((E2E_FAIL + 1))
        E2E_RESULTS+=("FAIL  $flow: $desc  [${E2E_LAST_SHOT##*/}]")
        e2e_log "FAIL $flow: $desc"
        [ -n "$E2E_LAST_SHOT" ] && e2e_a11y >"${E2E_LAST_SHOT%.png}.a11y.txt" 2>&1
    fi
}

e2e_skip() {
    E2E_SKIP=$((E2E_SKIP + 1))
    E2E_RESULTS+=("SKIP  $1: $2")
    e2e_log "SKIP $1: $2"
}

e2e_report() {
    {
        printf '%s\n' "${E2E_RESULTS[@]}"
        printf '\n%d passed, %d failed, %d skipped\n' "$E2E_PASS" "$E2E_FAIL" "$E2E_SKIP"
    } | tee "$E2E_OUT/results.txt"
    [ "$E2E_FAIL" -eq 0 ]
}
