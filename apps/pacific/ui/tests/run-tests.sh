#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary
#
# Pacific's QML tests on the offscreen platform: the UI's helpers and the
# mock web view's contract (built here with CMake).
#
#   KEEL_QML=/path/to/keel-build/qml shoal/pacific/ui/tests/run-tests.sh
#
# MOCKVIEW_BUILD: where to build the mock (default ${TMPDIR:-/tmp}/pacific-mockview).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
: "${KEEL_QML:?set KEEL_QML to the qml directory of a Keel build}"
mock=${MOCKVIEW_BUILD:-${TMPDIR:-/tmp}/pacific-mockview}
cmake -S "$here/mockview" -B "$mock" -G Ninja >/dev/null
cmake --build "$mock" >/dev/null
runner=${QMLTESTRUNNER:-$(for c in /usr/lib/qt6/bin/qmltestrunner /usr/lib64/qt6/bin/qmltestrunner; do [ -x "$c" ] && break; done; echo "$c")}
QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 "$runner" -import "$KEEL_QML" -import "$mock/qml" -input "$here"
