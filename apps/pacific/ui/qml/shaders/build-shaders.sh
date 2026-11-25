#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: Apache-2.0
#
# Regenerates the committed .qsb files from the shader sources here, as
# Keel's keel-silica/silica/qml/shaders/build-shaders.sh does (same GLSL
# versions; the device build roots carry no qsb).
#   QSB=/path/to/qsb apps/pacific/ui/qml/shaders/build-shaders.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
qsb=${QSB:-qsb}
for src in "$here"/*.frag; do
    "$qsb" --glsl "100 es,120,150" -o "$src.qsb" "$src"
    sed -n 's|^// \(SPDX-[A-Za-z-]*: .*\)|\1|p' "$src" > "$src.qsb.license"
done
