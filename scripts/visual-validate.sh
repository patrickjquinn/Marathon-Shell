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
  # MARATHON_DISABLE_SANDBOX skips bwrap (which requires /usr/share/marathon-apps
  # to exist — only true on installed systems). Validation runs unsandboxed.
  MARATHON_FORCE_DPI=160 \
  MARATHON_DISABLE_SANDBOX=1 \
  MARATHON_SHELL_QML_IMPORT_PATH="$PROJECT_DIR/build/shell/qml" \
  MARATHON_UI_QML_IMPORT_PATH="$PROJECT_DIR/build" \
  QT_QPA_PLATFORM=xcb \
  QT_AUTO_SCREEN_SCALE_FACTOR=0 \
  QT_ENABLE_HIGHDPI_SCALING=0 \
  QT_SCALE_FACTOR=1 \
  QT_QUICK_CONTROLS_STYLE="" \
  QT_MEDIA_BACKEND=gstreamer \
  QML_IMPORT_PATH="$PROJECT_DIR/build/shell/qml:$PROJECT_DIR/build" \
  QML2_IMPORT_PATH="$PROJECT_DIR/build/shell/qml:$PROJECT_DIR/build" \
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
  # Multi-step drag so Qt's gesture recogniser reads it as a flick
  # rather than a click.
  local wid="$1" x1="$2" y1="$3" x2="$4" y2="$5"
  local steps=14
  xdotool mousemove --window "$wid" "$x1" "$y1" 2>/dev/null || true
  xdotool mousedown 1 2>/dev/null || true
  local i
  for i in $(seq 1 $steps); do
    local cx=$(( x1 + (x2 - x1) * i / steps ))
    local cy=$(( y1 + (y2 - y1) * i / steps ))
    xdotool mousemove --window "$wid" "$cx" "$cy" 2>/dev/null || true
    sleep 0.025
  done
  xdotool mouseup 1 2>/dev/null || true
  sleep 0.8
}

# --- Surfaces --------------------------------------------------------------

capture_lock_no_media() {
  echo "→ lock-no-media"
  local pid wid
  pid=$(launch_shell --demo-notifications)
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
  echo "→ hub (--start-on=hub)"
  local pid wid
  pid=$(launch_shell --skip-lock --start-on=hub --demo-notifications)
  sleep 4
  wid=$(wait_for_window) || { echo "no window"; kill -9 "$pid"; return 1; }
  capture "$wid" "$VDIR/hub.png"
  kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
}

capture_quicksettings() {
  echo "→ quick-settings (--start-on=quicksettings)"
  local pid wid
  pid=$(launch_shell --skip-lock --start-on=quicksettings)
  sleep 4
  wid=$(wait_for_window) || { echo "no window"; kill -9 "$pid"; return 1; }
  capture "$wid" "$VDIR/quick-settings.png"
  kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
}

# Auto-launch an installed app via MARATHON_AUTO_LAUNCH_APP_ID
# (honoured by shell/main.cpp). The window state machine routes the
# AppLaunchService through the compositor so the app's QML lands as
# the foreground surface.
capture_app() {
  local app_id="$1"
  echo "→ app:$app_id"
  local pid wid
  pid=$(launch_shell --skip-lock --start-on=app:"$app_id")
  # 5 s for shell init + 600 ms for the start-on timer + ~5 s for the
  # external QML app process to spawn and render its first frame past
  # the "Loading…" splash.
  sleep 12
  wid=$(wait_for_window) || { echo "no window"; kill -9 "$pid"; return 1; }
  capture "$wid" "$VDIR/app-$app_id.png"
  kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
}

# --- Driver ---------------------------------------------------------------

case "${1:-help}" in
  lock-no-media)   capture_lock_no_media ;;
  home)            capture_home ;;
  hub)             capture_hub ;;
  quicksettings)   capture_quicksettings ;;
  app:*)           capture_app "${1#app:}" ;;
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
