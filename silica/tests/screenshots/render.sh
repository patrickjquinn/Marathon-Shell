#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Renders every reference scene into <outdir> (default: ./after) with the
# keel-silica-shot tool from a Keel build, plus a REUSE .license sidecar.
#   keel/silica/tests/screenshots/render.sh <keel-build-dir> [outdir]
#
# As a phone draws them: on OpenGL (Mesa llvmpipe through xvfb-run, so that
# Silica's shader effects show; KEEL_SHOT_SOFTWARE=1 or no xvfb-run: the
# software scene graph) and, with KEEL_SHOT_FONTS=<dir> holding Sailfish's
# SailSansPro-*.ttf (tools/screenshots/run.sh finds or fetches them), in
# Sail Sans Pro; else in DejaVu Sans, fixed so that renders compare between
# hosts. A Jolla 1 screen (540x960, pixelRatio 1.0, 4.5").
set -eu
build=${1:?usage: render.sh <keel-build-dir> [outdir]}
here=$(cd "$(dirname "$0")" && pwd)
out=${2:-$here/after}
mkdir -p "$out"
export QT_QPA_PLATFORM=offscreen KEEL_SCREEN_DIAGONAL=4.5
export QML_IMPORT_PATH="$build/qml" QML2_IMPORT_PATH="$build/qml"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$tmp}"
export QT_QPA_FONTDIR="${QT_QPA_FONTDIR:-/usr/share/fonts/truetype/dejavu}"
if [ -n "${KEEL_SHOT_FONTS:-}" ]; then
    mkdir -p "$tmp/fonts"
    cp "$KEEL_SHOT_FONTS"/SailSansPro-*.ttf "$QT_QPA_FONTDIR"/DejaVuSans*.ttf "$tmp/fonts/"
    cat >"$tmp/fonts/fonts.conf" <<CONF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig><dir>$tmp/fonts</dir><cachedir>$tmp/fonts/cache</cachedir></fontconfig>
CONF
    export FONTCONFIG_FILE="$tmp/fonts/fonts.conf"
fi
run=""
if [ -z "${KEEL_SHOT_SOFTWARE:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
    export QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl LIBGL_ALWAYS_SOFTWARE=1 QSG_RENDER_LOOP=basic
    run="xvfb-run -a"
else
    export QT_QUICK_BACKEND=software
fi
for scene in "$here"/scenes/*.qml; do
    name=$(basename "$scene" .qml)
    # shellcheck disable=SC2086 # $run is a command prefix or nothing
    $run "$build/silica/tests/keel-silica-shot" "$scene" "$out/$name.png"
    # REUSE-IgnoreStart
    printf 'SPDX-FileCopyrightText: 2026 Patrick Quinn\nSPDX-License-Identifier: MIT\n' > "$out/$name.png.license"
    # REUSE-IgnoreEnd
done
