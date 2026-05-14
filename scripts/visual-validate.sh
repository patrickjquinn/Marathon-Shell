#!/bin/bash
# Marathon Shell — visual validation harness.
#
# Launches the shell with MARATHON_FORCE_DPI=160 so scaleFactor=1.0 and
# design pixels = window pixels on the standard 540×1140 phone canvas.
# Captures one surface per invocation. Each capture goes to
# /tmp/marathon-validate/<surface>.png so it can be diffed against
# the corresponding reference in screenshots/ or design uploads.
#
# Usage:
#   scripts/visual-validate.sh lock-no-media        # plain lock screen
#   scripts/visual-validate.sh home                 # active frames home
#   scripts/visual-validate.sh hub                  # via swipe-up gesture
#   scripts/visual-validate.sh quicksettings        # via swipe-down gesture
#   scripts/visual-validate.sh app:phone            # launch phone app
#   scripts/visual-validate.sh all                  # capture every preset
#
# Notes:
#   - Wayland gestures are simulated via xdotool against the X11 window.
#     Some gestures may not trigger reliably; the script logs which ones
#     succeed and which need a manual nudge.
#   - The shell binary is rebuilt only if outdated; pass FORCE_BUILD=1 to
#     always rebuild.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

VDIR="${MARATHON_VALIDATE_DIR:-/tmp/marathon-validate}"
mkdir -p "$VDIR"

if [ "${FORCE_BUILD:-0}" = "1" ] || [ ! -x "$PROJECT_DIR/build/shell/marathon-shell-bin" ]; then
  echo "→ Building marathon-shell-bin"
  cmake --build "$PROJECT_DIR/build" --target marathon-shell -j8 >/dev/null
fi

# --- Helpers ---------------------------------------------------------------

kill_shell() {
  for p in $(pgrep -x marathon-shell 2>/dev/null); do
    kill -9 "$p" 2>/dev/null || true
  done
  rm -f /run/user/1000/marathon-wayland-0 /run/user/1000/marathon-wayland-0.lock 2>/dev/null || true
  sleep 0.3
}

launch_shell() {
  local extra_args=("$@")
  kill_shell
  MARATHON_FORCE_DPI=160 \
  QT_QPA_PLATFORM=xcb \
  QT_AUTO_SCREEN_SCALE_FACTOR=0 \
  QT_ENABLE_HIGHDPI_SCALING=0 \
  QT_SCALE_FACTOR=1 \
  QT_QUICK_CONTROLS_STYLE="" \
  QT_MEDIA_BACKEND=gstreamer \
  QML_IMPORT_PATH="$PROJECT_DIR/build/shell/qml" \
  MARATHON_DATA_DIR="$PROJECT_DIR/shell/resources" \
  QT_WEBENGINE_DISABLE_SANDBOX=1 \
  MARATHON_DEBUG=1 \
  "$PROJECT_DIR/build/shell/marathon-shell-bin" "${extra_args[@]}" \
    > /tmp/marathon-shell.log 2>&1 &
  echo $!
}

wait_for_window() {
  local tries=20
  while [ $tries -gt 0 ]; do
    local wid
    wid=$(xdotool search --name "Marathon" 2>/dev/null | tail -1 || true)
    if [ -n "$wid" ]; then
      echo "$wid"
      return 0
    fi
    sleep 0.3
    tries=$((tries - 1))
  done
  return 1
}

capture() {
  local wid="$1" out="$2"
  xdotool windowactivate "$wid" 2>/dev/null || true
  sleep 0.3
  import -window "$wid" "$out"
  echo "  captured → $out ($(identify -format '%wx%h' "$out"))"
}

swipe() {
  # swipe <wid> <x1> <y1> <x2> <y2>
  local wid="$1" x1="$2" y1="$3" x2="$4" y2="$5"
  xdotool mousemove --window "$wid" "$x1" "$y1" mousedown 1 \
                    mousemove --window "$wid" "$x2" "$y2" mouseup 1 \
    2>/dev/null || true
  sleep 0.6
}

# --- Surfaces --------------------------------------------------------------

capture_lock_no_media() {
  echo "→ lock-no-media"
  local pid wid
  pid=$(launch_shell)
  sleep 4
  wid=$(wait_for_window) || { echo "no window"; kill -9 "$pid"; return 1; }
  capture "$wid" "$VDIR/lock-no-media.png"
  kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
}

capture_home() {
  echo "→ home (active frames)"
  local pid wid
  pid=$(launch_shell --skip-lock)
  sleep 4
  wid=$(wait_for_window) || { echo "no window"; kill -9 "$pid"; return 1; }
  capture "$wid" "$VDIR/home-active-frames.png"
  kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
}

capture_hub() {
  echo "→ hub (swipe up + right)"
  local pid wid
  pid=$(launch_shell --skip-lock)
  sleep 4
  wid=$(wait_for_window) || { echo "no window"; kill -9 "$pid"; return 1; }
  # Marathon Hub gesture = swipe up from bottom + arc right
  swipe "$wid" 270 1100 270 200
  capture "$wid" "$VDIR/hub.png"
  kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
}

capture_quicksettings() {
  echo "→ quick-settings (swipe down from top)"
  local pid wid
  pid=$(launch_shell --skip-lock)
  sleep 4
  wid=$(wait_for_window) || { echo "no window"; kill -9 "$pid"; return 1; }
  swipe "$wid" 270 5 270 900
  capture "$wid" "$VDIR/quick-settings.png"
  kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
}

# --- Driver ---------------------------------------------------------------

case "${1:-help}" in
  lock-no-media)   capture_lock_no_media ;;
  home)            capture_home ;;
  hub)             capture_hub ;;
  quicksettings)   capture_quicksettings ;;
  all)
    capture_lock_no_media
    capture_home
    capture_hub
    capture_quicksettings
    echo "✓ captures in $VDIR/"
    ;;
  *)
    echo "usage: $0 {lock-no-media|home|hub|quicksettings|all}"
    exit 1
    ;;
esac
