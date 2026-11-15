#!/bin/bash
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: Apache-2.0
#
# QML lint for Pacific's UI, with the repository's tools (tools/lint):
# qmllint against Keel, the app's CXX-Qt module and the mock web view, with
# the findings accepted in qmllint-accepted.txt; and the Sailfish UI rules
# (silica-style.py). Exits non-zero on any finding.
#
#   KEEL_BUILD=<repo>/build/keel shoal/pacific/ui/tests/lint.sh
#
# Environment: KEEL_BUILD (a built Keel), CARGO_TARGET_DIR (where
# shoal/pacific/app was built; default <repo>/target), MOCKVIEW_BUILD (where
# to build the mock web view; default ${TMPDIR:-/tmp}/pacific-mockview).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../../.." && pwd)
cd "$repo"
: "${KEEL_BUILD:=$repo/build/keel}"
target=${CARGO_TARGET_DIR:-$repo/target}
mock=${MOCKVIEW_BUILD:-${TMPDIR:-/tmp}/pacific-mockview}
qmllint=${QMLLINT6:-$(for c in /usr/lib/qt6/bin/qmllint /usr/lib64/qt6/bin/qmllint; do [ -x "$c" ] && break; done; echo "$c")}

cmake -S "$here/mockview" -B "$mock" -G Ninja >/dev/null
cmake --build "$mock" >/dev/null

work=$(mktemp -d "${TMPDIR:-/tmp}/pacific-lint.XXXXXX")
trap 'rm -rf "$work"' EXIT
mapfile -t files < <(git ls-files -co --exclude-standard -- shoal/pacific/ui/qml | grep -E '\.(qml|js)$')
failed=0
python3 tools/lint/qmllint-check.py --qmllint "$qmllint" --repo "$repo" --accepted "$here/qmllint-accepted.txt" \
    --used "$work/used" --label "qmllint6 shoal/pacific/ui" -I "$KEEL_BUILD/qml" -I "$mock/qml" \
    --cxxqt-target "$target" --cxxqt-module Shipwright.Pacific -- "${files[@]}" || failed=1
python3 tools/lint/qmllint-check.py --stale --accepted "$here/qmllint-accepted.txt" --used "$work/used" || failed=1
tools/lint/lint.sh style || failed=1
exit $failed
