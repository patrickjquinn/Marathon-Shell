#!/usr/bin/env bash
# Verify the Phase C split-process architecture on a booted duranium image.
# Designed to run as root over SSH; resolves the marathon user via
# /etc/default_user. Mirrors verify-lifecycle.sh / verify-dynamic.sh.
set -u
PASS=0
FAIL=0

check() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "✓ $label"; PASS=$((PASS+1))
    else
        echo "✗ $label"; FAIL=$((FAIL+1))
    fi
}

MARATHON_USER="$(cat /etc/default_user 2>/dev/null || echo user)"
MARATHON_UID="$(id -u "$MARATHON_USER" 2>/dev/null || echo 0)"
CG_USER="/sys/fs/cgroup/user.slice/user-${MARATHON_UID}.slice/user@${MARATHON_UID}.service"

echo "== Marathon split-process verification =="
echo "user: $MARATHON_USER (uid $MARATHON_UID)"
echo

echo "-- process layout --"
COMPOSITOR_PIDS=$(pgrep -af marathon-compositor | grep -v marathon-shell || true)
SHELL_PIDS=$(pgrep -af marathon-shell-bin || true)
echo "compositor: $COMPOSITOR_PIDS"
echo "shell:      $SHELL_PIDS"
check "exactly one marathon-compositor PID" \
    test "$(echo "$COMPOSITOR_PIDS" | wc -l)" -eq 1
check "exactly one marathon-shell-bin PID" \
    test "$(echo "$SHELL_PIDS" | wc -l)" -eq 1

COMP_PID=$(echo "$COMPOSITOR_PIDS" | awk '{print $1}')
SHELL_PID=$(echo "$SHELL_PIDS" | awk '{print $1}')
COMP_CG=$(awk -F: '/^0::/{print $3}' "/proc/$COMP_PID/cgroup" 2>/dev/null || echo "")
SHELL_CG=$(awk -F: '/^0::/{print $3}' "/proc/$SHELL_PID/cgroup" 2>/dev/null || echo "")
echo "compositor cgroup: $COMP_CG"
echo "shell cgroup:      $SHELL_CG"
check "compositor + shell live in different cgroups" \
    test "$COMP_CG" != "$SHELL_CG"

echo
echo "-- wayland protocols --"
WL_DISPLAY=$(systemctl --user --machine="$MARATHON_USER@" show-environment 2>/dev/null \
    | sed -n 's/^WAYLAND_DISPLAY=//p')
WL_DISPLAY="${WL_DISPLAY:-marathon-wayland-0}"
echo "WAYLAND_DISPLAY=$WL_DISPLAY"
INFO=$(sudo -u "$MARATHON_USER" \
    XDG_RUNTIME_DIR="/run/user/${MARATHON_UID}" \
    WAYLAND_DISPLAY="$WL_DISPLAY" wayland-info 2>/dev/null || true)
for iface in xdg_wm_base zwlr_layer_shell_v1 zwlr_foreign_toplevel_manager_v1 \
             zwlr_screencopy_manager_v1 ext_session_lock_manager_v1; do
    if grep -q "interface: '$iface'" <<<"$INFO"; then
        echo "✓ $iface advertised"; PASS=$((PASS+1))
    else
        echo "✗ $iface missing"; FAIL=$((FAIL+1))
    fi
done

echo
echo "-- shell-restart resilience --"
# Foreground something so we can prove apps survive a shell crash.
APP_PIDS_BEFORE=$(pgrep -af marathon-app-runner | wc -l)
SHELL_PID_BEFORE=$SHELL_PID
echo "shell PID before kill: $SHELL_PID_BEFORE"
echo "app-runners before:    $APP_PIDS_BEFORE"
sudo -u "$MARATHON_USER" \
    XDG_RUNTIME_DIR="/run/user/${MARATHON_UID}" \
    systemctl --user kill marathon-shell.service 2>/dev/null || true
# Restart sec is 2; give it a generous 8s ceiling.
for _ in 1 2 3 4 5 6 7 8; do
    sleep 1
    NEW_PID=$(pgrep -f marathon-shell-bin | head -n1)
    [ -n "$NEW_PID" ] && [ "$NEW_PID" != "$SHELL_PID_BEFORE" ] && break
done
APP_PIDS_AFTER=$(pgrep -af marathon-app-runner | wc -l)
echo "shell PID after kill:  $NEW_PID"
echo "app-runners after:     $APP_PIDS_AFTER"
check "shell respawned with new PID" \
    test -n "$NEW_PID" -a "$NEW_PID" != "$SHELL_PID_BEFORE"
check "compositor PID unchanged"   \
    test "$(pgrep -f marathon-compositor | head -n1)" = "$COMP_PID"
check "app-runners survived shell restart" \
    test "$APP_PIDS_AFTER" -ge "$APP_PIDS_BEFORE"

echo
echo "-- memory --"
COMP_RSS_KB=$(awk '/^Rss:/{s+=$2}END{print s}' "/proc/$COMP_PID/smaps_rollup" 2>/dev/null || echo 0)
SHELL_RSS_KB=$(awk '/^Rss:/{s+=$2}END{print s}' "/proc/$(pgrep -f marathon-shell-bin | head -n1)/smaps_rollup" 2>/dev/null || echo 0)
echo "compositor RSS: $((COMP_RSS_KB / 1024)) MB"
echo "shell RSS:      $((SHELL_RSS_KB / 1024)) MB"
# Targets from the Phase C-7 plan; warn (not fail) when over.
[ "$((COMP_RSS_KB / 1024))" -lt 80 ]  && echo "✓ compositor < 80 MB" \
                                      || echo "! compositor over 80 MB target"
[ "$((SHELL_RSS_KB / 1024))" -lt 250 ] && echo "✓ shell < 250 MB" \
                                       || echo "! shell over 250 MB target"

echo
echo "== summary: $PASS pass / $FAIL fail =="
exit $FAIL
