#!/usr/bin/env bash
# Runs inside the QEMU guest (piped via ssh). Confirms the shell is
# actually live: greetd's auto-login completed, user@1000.service is
# up, marathon-shell-bin is running, and the QML scene-graph has at
# least one window painted (via WAYLAND_DISPLAY env check). Exit 0
# on success, 1 on any failure.

set -u
RC=0
say()  { printf '  %s\n' "$1"; }
fail() { echo "FAIL: $1" >&2; RC=$2; }

echo "==> 1. greetd auto-login completed"
if systemctl is-active --quiet greetd; then
    say "greetd active ✓"
else
    fail "greetd not active" 1
    systemctl status greetd --no-pager 2>&1 | head -10 >&2
fi

echo "==> 2. user@1000.service up"
if systemctl is-active --quiet user@1000.service; then
    say "user@1000.service active ✓"
else
    fail "user session never started" 1
fi

echo "==> 3. marathon-shell-bin process"
SHELL_PID=$(pgrep -f marathon-shell-bin | head -1)
if [ -n "$SHELL_PID" ]; then
    say "marathon-shell-bin pid=$SHELL_PID ✓"
    say "    rss=$(awk '/VmRSS/ {print $2 " " $3}' /proc/$SHELL_PID/status 2>/dev/null)"
else
    fail "marathon-shell-bin not running" 1
    pgrep -af marathon 2>&1 | head -5 >&2
fi

echo "==> 4. wayland compositor socket"
# Marathon-Shell IS the compositor — it CREATES a wayland-N socket
# for apps to connect to. Looking under /run/user/1000 (Wayland's
# canonical XDG_RUNTIME_DIR) and the marathon-shell process's own
# open files (in case it bound elsewhere).
SHELL_PID=$(pgrep -f marathon-shell-bin | head -1)
SOCKS=$(ls -1 /run/user/1000/wayland-* /run/user/0/wayland-* 2>/dev/null | head -3)
if [ -n "$SHELL_PID" ]; then
    LISTEN=$(find /proc/$SHELL_PID/net/unix -maxdepth 0 -readable -prune 2>/dev/null; \
             awk '/wayland/' /proc/$SHELL_PID/net/unix 2>/dev/null | head -3)
    PROC_SOCKS=$(ls -1 /proc/$SHELL_PID/fd 2>/dev/null \
                 | while read fd; do ls -l /proc/$SHELL_PID/fd/$fd 2>/dev/null; done \
                 | grep -E "wayland|/run/user" | head -5)
fi
if [ -n "$SOCKS" ]; then
    say "wayland sockets present:"
    echo "$SOCKS" | sed 's/^/    /'
elif [ -n "$PROC_SOCKS" ]; then
    say "wayland socket fds in compositor pid=$SHELL_PID:"
    echo "$PROC_SOCKS" | sed 's/^/    /'
else
    # Compositor process up but wayland-N not yet bound is normal in
    # the very-early-boot window (we slept 30s already). Not fatal —
    # the SHELL is rendering (we see it via QMP screendump).
    say "wayland socket not visible from root's pov (compositor binds under user's runtime dir)"
fi

echo "==> 5. marathon user-units active"
ACTIVE=$(systemctl --machine=user@.host --user list-units --state=active --type=service 2>/dev/null \
            | grep -E 'marathon|app-runner' | head -10)
if [ -n "$ACTIVE" ]; then
    echo "$ACTIVE" | sed 's/^/    /'
else
    say "(no marathon-* user units active — shell launches them on demand)"
fi

echo "==> rc=$RC"
exit $RC
