#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# The web view's tests against the real engine on the development host
# (README.md "Running"): smoke.qml on the GPU path, smoke.qml again with the
# WebProcess on software GL (Mesa llvmpipe: frames arrive as wl_shm buffers,
# the path the CPU fallback takes), spelling.qml, privacy.qml, userscripts.qml,
# filters.qml, visibility.qml and, with KEEL_QML set, visibility-silica.qml.
#
#   shoal/pacific/webview/tests/run-host-tests.sh <prefix> <build>
#
# Runs in a private headless mutter when mutter is installed.
#
# Exits 1 when any test fails or crashes.
set -u
here=$(cd "$(dirname "$0")" && pwd)
prefix=${1:?usage: run-host-tests.sh <prefix> <build>}
build=${2:?build dir}
run="$here/../tools/host-run.sh $prefix $build"
qml=${QML6:-$(command -v qml6 || echo /usr/lib64/qt6/bin/qml)}
failed=0

# A private headless compositor (mutter), so the test windows are always
# exposed and never cover or get covered by the desktop's windows: an
# occluded window is (correctly) not visible, and the visibility tests fail
# on a busy desktop. PACIFIC_TEST_DESKTOP=1 uses the session's compositor.
compositor=""
if [ -z "${PACIFIC_TEST_DESKTOP:-}" ] && command -v mutter >/dev/null 2>&1; then
    display=pacific-tests-$$
    mutter --headless --wayland --no-x11 --wayland-display "$display" --virtual-monitor 540x960 \
        >"${TMPDIR:-/tmp}/pacific-tests-mutter.log" 2>&1 &
    compositor=$!
    socket=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$display
    i=0
    while [ ! -S "$socket" ] && [ "$i" -lt 100 ]; do
        i=$((i + 1))
        sleep 0.1
    done
    if [ -S "$socket" ]; then
        export WAYLAND_DISPLAY="$display"
    else
        echo "mutter did not start; using the session's compositor" >&2
    fi
fi
trap '[ -n "$compositor" ] && kill "$compositor" 2>/dev/null' EXIT

check() {
    name=$1
    shift
    out=$("$@" 2>&1)
    rc=$?
    summary=$(printf '%s\n' "$out" | grep -E ': (all passed|[0-9]+ failure|FAIL)' | tail -3)
    if [ "$rc" -eq 0 ]; then
        echo "ok   $name"
    else
        echo "FAIL $name (exit $rc)"
        printf '%s\n' "$summary" | sed 's/^/     /'
        failed=1
    fi
}

# shellcheck disable=SC2086 # $run is a command line
check "smoke (GPU frames)" $run "$qml" "$here/smoke.qml"
# shellcheck disable=SC2086
check "smoke (software frames, wl_shm)" env LIBGL_ALWAYS_SOFTWARE=1 PACIFIC_GPU_MODE=cpu WEBKIT_SKIA_ENABLE_CPU_RENDERING=1 \
    $run "$qml" "$here/smoke.qml"
# shellcheck disable=SC2086
check "spelling (English, Finnish)" $run "$qml" "$here/spelling.qml"
# shellcheck disable=SC2086
check "user scripts (page and named worlds)" $run "$qml" "$here/userscripts.qml"
# shellcheck disable=SC2086
check "console (capture on demand, page-world reports)" $run "$qml" "$here/console.qml"
python3 "$here/privacy-server.py" 18089 &
server=$!
sleep 1
# shellcheck disable=SC2086
check "privacy (blocked requests, GPC)" $run "$qml" "$here/privacy.qml"
# shellcheck disable=SC2086
check "content filters (disable, enable, delete)" $run "$qml" "$here/filters.qml"
kill "$server" 2>/dev/null
python3 "$here/download-server.py" 18090 /tmp/pacific-download-test &
server=$!
sleep 1
# shellcheck disable=SC2086
check "downloads (suggested name, claimed destination)" $run "$qml" "$here/downloads.qml"
kill "$server" 2>/dev/null
# shellcheck disable=SC2086
check "visibility (tabs, discard, promote, reparent)" $run "$qml" "$here/visibility.qml"
# The Silica variant needs Keel's QML modules (KEEL_QML: a Keel build's qml/).
if [ -n "${KEEL_QML:-}" ] && [ -d "$KEEL_QML/Sailfish/Silica" ]; then
    # shellcheck disable=SC2086
    check "visibility (Silica pages)" env QML_IMPORT_PATH="$KEEL_QML" $run "$qml" "$here/visibility-silica.qml"
else
    echo "skip visibility (Silica pages): set KEEL_QML to a Keel build's qml directory"
fi
exit "$failed"
