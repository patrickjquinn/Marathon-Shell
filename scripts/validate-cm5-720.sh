#!/usr/bin/env bash
# Validate Marathon QML renders responsively at 720x720 (HackberryPi
# CM5 panel size). Launches the shell with -geometry 720x720 under
# XCB, then walks through the major surfaces, screenshotting each.
#
# Output: /tmp/marathon-validate/cm5-<surface>.png
#
# Usage:
#   scripts/validate-cm5-720.sh        # full sweep
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

VDIR="/tmp/marathon-validate"
mkdir -p "$VDIR"
rm -f "$VDIR"/cm5-*.png

kill_shell() {
    pkill -9 -x marathon-shell-bin 2>/dev/null || true
    rm -f /run/user/1000/marathon-wayland-0 /run/user/1000/marathon-wayland-0.lock 2>/dev/null || true
    sleep 0.3
}

launch() {
    kill_shell
    MARATHON_DISABLE_SANDBOX=1 \
    QT_QPA_PLATFORM=xcb \
    QT_AUTO_SCREEN_SCALE_FACTOR=0 \
    QT_ENABLE_HIGHDPI_SCALING=0 \
    QT_SCALE_FACTOR=1 \
    MARATHON_FORCE_DPI=160 \
    MARATHON_SHELL_QML_IMPORT_PATH="$PROJECT_DIR/build/shell/qml" \
    MARATHON_UI_QML_IMPORT_PATH="$PROJECT_DIR/build" \
    QML_IMPORT_PATH="$PROJECT_DIR/build/shell/qml:$PROJECT_DIR/build" \
    MARATHON_DATA_DIR="$PROJECT_DIR/shell/resources" \
    "$PROJECT_DIR/build/shell/marathon-shell-bin" -geometry 720x720 \
        > /tmp/marathon-shell-cm5.log 2>&1 &
    SHELL_PID=$!
    for i in $(seq 1 30); do
        sleep 0.4
        kill -0 $SHELL_PID 2>/dev/null || { echo "shell died early"; tail -20 /tmp/marathon-shell-cm5.log; exit 1; }
        WID=$(xdotool search --name "Marathon" 2>/dev/null | tail -1 || true)
        [ -n "$WID" ] && break
    done
    [ -z "$WID" ] && { echo "no window"; kill $SHELL_PID 2>/dev/null; exit 1; }
    # Force geometry — the WM may have repositioned it.
    xdotool windowsize $WID 720 720 2>/dev/null
    sleep 1.5
    echo "$WID"
}

shot() {
    local name="$1" wid="$2"
    import -window "$wid" "$VDIR/cm5-$name.png" 2>&1 | head -2
    echo "  ↳ $VDIR/cm5-$name.png ($(file "$VDIR/cm5-$name.png" | awk -F, '{print $2}' | xargs))"
}

unlock_with_pin() {
    local wid="$1"
    # Swipe up to dismiss lock
    xdotool mousemove --window "$wid" 360 600
    xdotool mousedown --window "$wid" 1
    for y in 580 540 480 400 320 200; do
        xdotool mousemove --window "$wid" 360 $y
        sleep 0.04
    done
    xdotool mouseup --window "$wid" 1
    sleep 1
    # Marathon's PIN: default in dev is empty / "1234"
    xdotool key --window "$wid" 1 2 3 4 Return 2>/dev/null || true
    sleep 1.5
}

swipe_up_from_bottom() {
    local wid="$1"
    xdotool mousemove --window "$wid" 360 710
    xdotool mousedown --window "$wid" 1
    for y in 700 600 500 400 200; do
        xdotool mousemove --window "$wid" 360 $y
        sleep 0.05
    done
    xdotool mouseup --window "$wid" 1
    sleep 1
}

swipe_down_from_top() {
    local wid="$1"
    xdotool mousemove --window "$wid" 360 10
    xdotool mousedown --window "$wid" 1
    for y in 20 80 200 400 600; do
        xdotool mousemove --window "$wid" 360 $y
        sleep 0.05
    done
    xdotool mouseup --window "$wid" 1
    sleep 1
}

echo "==> launch shell at 720x720"
WID=$(launch)
echo "  window id $WID"

echo "==> capture: lock"
shot lock-no-media "$WID"

echo "==> unlock"
unlock_with_pin "$WID"
shot home-after-unlock "$WID"

echo "==> swipe up (peek → hub?)"
swipe_up_from_bottom "$WID"
shot hub "$WID"

# Back to home: tap home / center
xdotool key --window "$WID" Escape 2>/dev/null || true
sleep 1
shot home "$WID"

echo "==> swipe down (quick settings)"
swipe_down_from_top "$WID"
shot quicksettings "$WID"

xdotool key --window "$WID" Escape 2>/dev/null || true
sleep 1
shot home-final "$WID"

kill $SHELL_PID 2>/dev/null
wait $SHELL_PID 2>/dev/null

echo
echo "==> screenshots:"
ls -lh "$VDIR"/cm5-*.png 2>/dev/null
echo
echo "==> log tail:"
tail -10 /tmp/marathon-shell-cm5.log
