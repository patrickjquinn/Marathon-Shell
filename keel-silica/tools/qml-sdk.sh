#!/bin/bash
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# qml-sdk.sh BUILD_DIR: the type information of Keel's QML modules
# (Sailfish.Silica and its private modules, Sailfish.Share, Keel,
# Keel.Actions) for compiling an app's QML ahead of time against them: a
# KEEL_QML_TYPES_ONLY build tree (keel/CMakeLists.txt) in BUILD_DIR, of which
# only the .qmltypes files are built (moc and qmltyperegistrar, no
# compiler). Prints the import directory, BUILD_DIR/qml, for qmlcachegen -I
# (tools/keel-launcher/compile_qml.rs). Uses the Qt that qmake6 (or $QMAKE)
# reports; a few seconds once configured.
set -euo pipefail
[ $# = 1 ] || { sed -n '4,12p' "$0" >&2; exit 2; }
keel=$(cd "$(dirname "$0")/.." && pwd)
build=$1
mkdir -p "$build"
qmake=${QMAKE:-$(command -v qmake6 || command -v qmake)}
prefix=$("$qmake" -query QT_INSTALL_PREFIX)
if [ ! -f "$build/build.ninja" ]; then
    cmake -S "$keel" -B "$build" -G Ninja --no-warn-unused-cli -DCMAKE_PREFIX_PATH="$prefix" \
        -DKEEL_QML_TYPES_ONLY=ON -DBUILD_TESTING=OFF -DKEEL_BUILD_NEMO_COMPAT=OFF \
        -DKEEL_BUILD_SAILFISHAPP=OFF -DKEEL_BUILD_QT5COMPAT=OFF -DKEEL_BUILD_PLATFORM=OFF \
        -DKEEL_BUILD_BOOSTER=OFF >"$build.log" 2>&1 || { cat "$build.log" >&2; exit 1; }
fi
# The .qmltypes that qmltyperegistrar writes (Keel's own, keelplugin.qmltypes,
# is in the source tree: its plugin registers its types itself).
(cd "$build" && ninja $(ninja -t targets all | sed -n 's|^\(qml/.*\.qmltypes\): CUSTOM_COMMAND$|\1|p' |
    grep -vx qml/Keel/keelplugin.qmltypes)) \
    >"$build.log" 2>&1 || { cat "$build.log" >&2; exit 1; }
echo "$(cd "$build" && pwd)/qml"
