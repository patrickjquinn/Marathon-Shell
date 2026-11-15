#!/bin/bash
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Runs in the builder container (build.sh starts it; /w is the work
# directory, /cfg this directory): build-webkit.sh STAGE [JOBS]
#   STAGE generate: PGO-instrumented, no LTO (for profiling on the phone)
#   STAGE use:      PGO-optimised, ThinLTO, relocations kept for BOLT
#   STAGE lto:      as use without a profile (the A/B baseline for PGO)
# Source /w/src/$PACIFIC_SRC_DIR (build.sh's source step: WebKit with
# Atlantic's patch stack and ours), output /w/build-STAGE, installed to
# /w/stage-STAGE/opt/pacific.
set -euo pipefail
stage=$1 jobs=${2:-5}
src=/w/src/${PACIFIC_SRC_DIR:?} out=/w/build-$stage
export PKG_CONFIG_SYSROOT_DIR=/w/sysroot
export PKG_CONFIG_LIBDIR=/w/sysroot/opt/pacific/lib/pkgconfig:/w/sysroot/opt/woff2/lib64/pkgconfig:/w/sysroot/opt/woff2/lib/pkgconfig:/w/sysroot/usr/lib64/pkgconfig:/w/sysroot/usr/share/pkgconfig
export CCACHE_DIR=/w/ccache CCACHE_MAXSIZE=20G CCACHE_SLOPPINESS=time_macros,include_file_mtime,include_file_ctime CCACHE_BASEDIR=/w
extra=(-DUSE_LD_LLD=ON)
if [ "$stage" = use ] || [ "$stage" = lto ]; then
    extra+=(-DLTO_MODE=thin -DPACIFIC_BOLT=ON)
fi
if [ ! -f "$out/build.ninja" ]; then
    cmake -S "$src" -B "$out" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE=/cfg/pacific-toolchain.cmake -DPACIFIC_PGO="${stage/lto/none}" -DPACIFIC_CPU="${PACIFIC_CPU:-armv8.2}" \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS_RELEASE="-O3 -DNDEBUG" -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG" \
        -DCMAKE_INSTALL_PREFIX=/opt/pacific -DCMAKE_SKIP_RPATH=ON \
        -C /cfg/atlantic-wpe-features.cmake \
        -DPORT=WPE -DENABLE_WPE_LEGACY_API=ON -DENABLE_WPE_PLATFORM=OFF -DENABLE_WPE_QT_API=OFF \
        -DENABLE_DOCUMENTATION=OFF -DENABLE_INTROSPECTION=OFF -DENABLE_MINIBROWSER=OFF \
        -DENABLE_API_TESTS=OFF -DDEVELOPER_MODE=OFF -DUSE_SYSPROF_CAPTURE=OFF \
        -DUSE_JPEGXL=OFF -DUSE_THIN_ARCHIVES=ON \
        -DBWRAP_EXECUTABLE=/usr/bin/bwrap -DDBUS_PROXY_EXECUTABLE=/usr/bin/xdg-dbus-proxy \
        "${extra[@]}"
fi
ccache -z >/dev/null
ninja -C "$out" -j"$jobs" -k 0
rm -rf /w/stage-$stage && DESTDIR=/w/stage-$stage cmake --install "$out" >/dev/null
ccache -s | grep -E "Hits|Misses" || true
echo "== built $stage"
