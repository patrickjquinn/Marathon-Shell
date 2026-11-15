#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: Apache-2.0
#
# Pacific's app tests: the real UI and the real Shipwright.Pacific plugin over
# the mock web view (ui/tests/mockview), on the offscreen platform, with a
# throwaway profile.
#
#   KEEL_QML=<keel qml dir> [PACIFIC_PLUGIN=<dir with Shipwright/Pacific>] apps/pacific/tests/run.sh
#
# Without PACIFIC_PLUGIN it builds app/ (CARGO_TARGET_DIR, default app/target) first.
#
# PACIFIC_PLUGIN is CXX-Qt's export of the app crate's build
# (<target>/cxxqt/qml_modules), with libshipwright_pacific.so copied in as
# Shipwright/Pacific/libShipwright_Pacific.so, as the package installs it.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
: "${KEEL_QML:?set KEEL_QML to the qml dir of a Keel build}"
if [ -z "${PACIFIC_PLUGIN:-}" ]; then
	target=${CARGO_TARGET_DIR:-$here/../app/target}
	CARGO_TARGET_DIR=$target cargo build --locked --manifest-path "$here/../app/Cargo.toml"
	PACIFIC_PLUGIN=$target/cxxqt/qml_modules
	cp "$target/debug/libshipwright_pacific.so" "$PACIFIC_PLUGIN/Shipwright/Pacific/libShipwright_Pacific.so"
fi
runner=${QMLTESTRUNNER:-$(qtpaths6 --query QT_INSTALL_BINS)/qmltestrunner}

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mock=${MOCKVIEW_BUILD:-$stage/mockview}
cmake -S "$here/../ui/tests/mockview" -B "$mock" -G Ninja >/dev/null
cmake --build "$mock" >/dev/null

# Where the plugin keeps the profile, for the freeze test.
mkdir -p "$stage/PacificTest" "$stage/home" "$stage/share"
printf 'module PacificTest\nsingleton Paths 1.0 Paths.qml\n' >"$stage/PacificTest/qmldir"
cat >"$stage/PacificTest/Paths.qml" <<EOF
pragma Singleton
import QtQuick
QtObject {
    readonly property string profile: "$stage/home/.local/share/marathon-apps/shipwright-pacific"
}
EOF

HOME=$stage/home XDG_DATA_HOME=$stage/home/.local/share XDG_CACHE_HOME=$stage/home/.cache \
	PACIFIC_SHARE=$stage/share PACIFIC_OFFLINE=1 KEEL_DCONF_FILE=$stage/dconf.json \
	QML_XHR_ALLOW_FILE_READ=1 QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
	"$runner" -import "$KEEL_QML" -import "$here/../../../marathon-silica" -import "$mock/qml" \
	-import "$PACIFIC_PLUGIN" -import "$stage" -input "$here"
