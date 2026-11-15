#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-only
#
# build.sh <this directory> <output directory>: eglplatform_wayland.so, libhybris's
# Wayland EGL platform with cancelled buffers fixed (README.md). Needs gcc, g++,
# wayland-scanner and wayland-client/-server; libhybris's own libraries are
# stubbed (stubs.txt) and come from the device at run time.
set -eu
here=$(cd "$1" && pwd)
out=$2
mkdir -p "$out/stubs" "$out/gen"
wayland-scanner client-header "$here/libhybris/platforms/common/wayland-android.xml" "$out/gen/wayland-android-client-protocol.h"

# Link stubs: one shared library per soname, defining the symbols used.
for lib in $(grep -v '^#' "$here/stubs.txt" | awk '{print $1}' | sort -u); do
    c="$out/stubs/${lib%%.so.*}.c"
    : > "$c"
    grep -v '^#' "$here/stubs.txt" | awk -v l="$lib" '$1 == l && $2 == "func" {print "void " $3 "(void) {}"} $1 == l && $2 == "data" {print "char " $3 "[1];"}' >> "$c"
    gcc -shared -fPIC -o "$out/stubs/$lib" -Wl,-soname,"$lib" "$c"
    ln -sf "$lib" "$out/stubs/${lib%%.so.*}.so"
done

H="$here/libhybris"
g++ -shared -fPIC -O2 -g ${CXXFLAGS:-} \
    -D_Nonnull= -D_Nullable= -D_Null_unspecified= '-D__INTRODUCED_IN(x)=' '-D__REMOVED_IN(x)=' -D__ANDROID_API__=36 \
    -I"$H/common" -I"$H/platforms/common" -I"$H/platforms/wayland" -I"$H/egl/platforms/wayland" -I"$H/include" \
    -I"$H/egl" -I"$H/egl/platforms/common" -I"$out/gen" -I"$here" -I"$here/aosp" \
    -o "$out/eglplatform_wayland.so" \
    "$H/egl/platforms/wayland/eglplatform_wayland.cpp" "$H/egl/platforms/wayland/wayland_window.cpp" \
    "$H/platforms/wayland/wayland_window_common.cpp" \
    -L"$out/stubs" -Wl,--no-as-needed -lhybris-eglplatformcommon -lhybris-platformcommon -lwayland-server \
    -lgralloc -lhardware -lui -lhybris-common -lwayland-client -lsync -Wl,-soname,eglplatform_wayland.so
