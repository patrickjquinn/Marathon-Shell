#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: Apache-2.0
#
# Pacific's layout audit (layout.qml.in) in the real binary with the mock
# web view, on the Jolla Phone's screen, in a scratch profile.
#
#   shoal/pacific/ui/layout-tests/run.sh [path/to/libshipwright_pacific.so]
#
# Needs KEEL_QML (a Keel build's qml directory) and the mock web view built
# (tests/run-tests.sh builds it into MOCKVIEW_BUILD).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../../.." && pwd)
bin=${1:-${CARGO_TARGET_DIR:-$repo/target}/debug/libshipwright_pacific.so}
[ -x "$bin" ] || { echo "layout: no binary at $bin (cargo build first)" >&2; exit 2; }
: "${KEEL_QML:?set KEEL_QML to the qml directory of a Keel build}"
mock=${MOCKVIEW_BUILD:-${TMPDIR:-/tmp}/pacific-mockview}
[ -d "$mock/qml" ] || { cmake -S "$here/../tests/mockview" -B "$mock" -G Ninja >/dev/null && cmake --build "$mock" >/dev/null; }
work=$(mktemp -d "${TMPDIR:-/tmp}/pacific-layout.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/home" "$work/runtime"
chmod 700 "$work/runtime"
ln -s "$bin" "$work/shipwright-pacific"
sed -e "s|@UI_DIR@|file://$repo/shoal/pacific/ui/qml|g" -e "s|@AUDIT@|file://$repo/tools/ui-audit/LayoutAudit.qml|g" \
    "$here/layout.qml.in" > "$work/layout.qml"
printf '{"screens":[{"name":"phone","x":0,"y":0,"width":1032,"height":2272,"logicalDpi":96,"logicalBaseDpi":96,"dpr":1}]}\n' > "$work/phone-screen.json"
status=0
env -i PATH="/usr/bin:/bin" HOME="$work/home" XDG_RUNTIME_DIR="$work/runtime" LANG=C.UTF-8 \
    KEEL_SCREEN_CUTOUTS="[[310, 0, 414, 66]]" KEEL_SCREEN_ROUNDED_CORNERS="[[35, 35, 35], [-35, 35, 35], [40, -40, 40], [-40, -40, 40]]" \
    KEEL_THEME_PIXEL_RATIO=1.5 KEEL_SCREEN_DIAGONAL=6.36 \
    QT_QPA_PLATFORM="offscreen:configfile=$work/phone-screen.json" QT_FORCE_STDERR_LOGGING=1 \
    QT_LOGGING_RULES="qml.debug=true;js.debug=true;default.debug=true;qt.qml.invalidOverride.warning=false;qt.qml.propertyCache.append.warning=false" \
    QML_IMPORT_PATH="$mock/qml:$KEEL_QML" DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent/pacific-layout" \
    timeout 300 "$work/shipwright-pacific" --qml "$work/layout.qml" > "$work/out" 2>&1 || status=$?
grep -E "SMOKE (layout|ok)|LAYOUT" "$work/out" | sed 's/.*qml: //'
if [ $status -ne 0 ] || ! grep -q "LAYOUT PASS" "$work/out"; then
    tail -30 "$work/out" >&2
    exit 1
fi
