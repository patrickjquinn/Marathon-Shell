#!/bin/bash
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Builds the Sailfish OS sysroot the engine is compiled against:
#
#   shoal/pacific/engine/build/make-sysroot.sh <workdir> [release]
#
# 1. A throwaway container from the native build image for <release>
#    (default 5.2.0.15, the oldest release the engine serves) gets WebKit's
#    build dependencies from the Sailfish repositories; its /usr and /lib
#    become <workdir>/sysroot.
# 2. The current engine RPMs (RPMS/<release>) supply /opt/pacific: libwpe,
#    WPEBackend-fdo, libepoxy, enchant and the compat libraries, with their
#    headers. Their old WebKit is removed.
# 3. Headers Sailfish lacks for libraries the engine bundles (libavif,
#    enchant) come from their release tarballs, with pkg-config files.
# 4. woff2 1.0.2 is built as a static library with the engine toolchain.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../../.." && pwd)
W=$(realpath -m "${1:?usage: make-sysroot.sh <workdir> [release]}")
release=${2:-5.2.0.15}
S=$W/sysroot P=$W/sysroot/opt/pacific
mkdir -p "$W/deps"
# woff2 is built with the engine's builder image (build.sh's): make it first
# on a machine that has never built the engine.
podman image exists localhost/shipwright-webkit-builder:f44 ||
    podman build -t localhost/shipwright-webkit-builder:f44 "$here"

deps=(glib2-devel libsoup3-devel gstreamer1.0-devel gstreamer1.0-plugins-base-devel
      gstreamer1.0-plugins-bad-devel harfbuzz-devel libicu-devel libxml2-devel sqlite-devel
      libwebp-devel libpng-devel libjpeg-turbo-devel freetype-devel fontconfig-devel
      libtasn1-devel libgcrypt-devel wayland-devel wayland-protocols-devel libdrm-devel
      libseccomp-devel systemd-devel zlib-devel brotli-devel libxkbcommon-devel
      mesa-llvmpipe-libgbm-devel expat-devel hunspell-devel libgudev-devel libnice-devel
      libsrtp-devel libvpx-devel openssl-devel libatomic)
name=pacific-sysroot-$$
podman run -d --name "$name" "localhost/shipwright-sailfish:$release" sleep infinity >/dev/null
trap 'podman rm -f "$name" >/dev/null' EXIT
podman exec "$name" zypper -n --no-refresh in --no-recommends "${deps[@]}" >/dev/null
rm -rf "$S"; mkdir -p "$S"
podman export "$name" | tar -x -C "$S" --wildcards 'usr/include/*' 'usr/lib64/*' 'usr/lib/*' \
    'usr/share/pkgconfig/*' 'usr/share/wayland-protocols/*' 'lib64' 'lib' 'bin' 'etc/os-release' 2>/dev/null || true

# /opt/pacific from the engine RPMs, without their WebKit.
for r in "$repo"/RPMS/$release/shipwright-pacific-engine-2*.aarch64.rpm \
         "$repo"/RPMS/$release/shipwright-pacific-engine-devel-*.aarch64.rpm; do
    (cd "$S" && rpm2cpio "$r" | cpio -idm --quiet)
done
rm -rf "$P"/lib/libWPEWebKit-2.0.so* "$P"/lib/pkgconfig/wpe-webkit-2.0.pc \
    "$P"/lib/pkgconfig/wpe-web-process-extension-2.0.pc "$P"/include/wpe-webkit-2.0 \
    "$P"/libexec/wpe-webkit-2.0 "$P"/lib/wpe-webkit-2.0

# Bundled libraries' headers and pkg-config files.
fetch() { [ -f "$W/deps/$2" ] || curl -fsSL -o "$W/deps/$2" "$1"; echo "$3  $W/deps/$2" | sha256sum -c --quiet -; tar -xzf "$W/deps/$2" -C "$W/deps"; }
fetch https://github.com/AOMediaCodec/libavif/archive/refs/tags/v1.4.2.tar.gz libavif-1.4.2.tar.gz \
    2b645287340ba5a631d268b551dc2d72bd73ac33335962dd36dcdb6d8366921d
fetch https://github.com/AbiWord/enchant/releases/download/v2.3.3/enchant-2.3.3.tar.gz enchant-2.3.3.tar.gz \
    3da12103f11cf49c3cf2fd2ce3017575c5321a489e5b9bfa81dd91ec413f3891
fetch https://github.com/google/woff2/archive/refs/tags/v1.0.2.tar.gz woff2-1.0.2.tar.gz \
    add272bb09e6384a4833ffca4896350fdb16e0ca22df68c0384773c67a175594
mkdir -p "$P"/include/avif "$P"/include/enchant-2
cp "$W"/deps/libavif-1.4.2/include/avif/*.h "$P"/include/avif/
cp "$W"/deps/enchant-2.3.3/src/enchant.h "$W"/deps/enchant-2.3.3/src/enchant++.h "$P"/include/enchant-2/
ln -sf libavif.so.16 "$P"/lib/compat/libavif.so
ln -sf libenchant-2.so.2 "$P"/lib/libenchant-2.so
ln -sf libepoxy.so.0 "$P"/lib/libepoxy.so
pc() { printf 'prefix=/opt/pacific\nName: %s\nDescription: %s\nVersion: %s\nCflags: %s\nLibs: %s\n%s' "$2" "$3" "$4" "$5" "$6" "${7:-}" > "$P/lib/pkgconfig/$1.pc"; }
pc libavif libavif 'AV1 images (bundled, decode-only)' 1.4.2 '-I${prefix}/include' '-L${prefix}/lib/compat -lavif'
pc enchant-2 enchant-2 'Spell checking (bundled enchant 2.3.3)' 2.3.3 '-I${prefix}/include/enchant-2' '-L${prefix}/lib -lenchant-2' $'Requires: glib-2.0\n'
pc epoxy epoxy 'GL dispatch (bundled, RTLD_DEFAULT patch)' 1.5.11 '-I${prefix}/include' '-L${prefix}/lib -lepoxy' $'epoxy_has_glx=0\nepoxy_has_egl=1\nepoxy_has_wgl=0\n'

# woff2 (static): Sailfish has none, and WOFF2 is most of the web's fonts.
# 1.0.2's output.h misses <cstdint> with GCC 13's libstdc++.
grep -q '<cstdint>' "$W"/deps/woff2-1.0.2/include/woff2/output.h ||
    sed -i 's|#include <string>|#include <cstdint>\n#include <string>|' "$W"/deps/woff2-1.0.2/include/woff2/output.h
podman run --rm --memory 4g -v "$W":/w:Z -v "$here":/cfg:ro,Z localhost/shipwright-webkit-builder:f44 sh -c '
    cd /w/deps/woff2-1.0.2 && rm -rf b &&
    PKG_CONFIG_SYSROOT_DIR=/w/sysroot PKG_CONFIG_LIBDIR=/w/sysroot/usr/lib64/pkgconfig \
    cmake -S . -B b -G Ninja -DCMAKE_TOOLCHAIN_FILE=/cfg/pacific-toolchain.cmake -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_INSTALL_PREFIX=/opt/woff2 \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_C_FLAGS="-O3 -flto=thin" -DCMAKE_CXX_FLAGS="-O3 -flto=thin" \
        -DBROTLIDEC_INCLUDE_DIRS=/w/sysroot/usr/include -DBROTLIDEC_LIBRARIES=/w/sysroot/usr/lib64/libbrotlidec.so \
        -DBROTLIENC_INCLUDE_DIRS=/w/sysroot/usr/include -DBROTLIENC_LIBRARIES=/w/sysroot/usr/lib64/libbrotlienc.so >/dev/null &&
    ninja -C b >/dev/null && DESTDIR=/w/sysroot cmake --install b >/dev/null'
# Sailfish's kernel headers are Linux 4.4's; WebKit's GBM and dma-buf code
# needs newer uapi headers (stable ABI, and the phones run 5.x or 6.x
# kernels). Only missing files are added, from the builder's kernel-headers.
podman run --rm -v "$S":/s:Z localhost/shipwright-webkit-builder:f44 sh -c '
    dnf -q -y install kernel-headers >/dev/null 2>&1; cd /usr/include &&
    for f in linux/dma-buf.h linux/dma-heap.h linux/udmabuf.h linux/sync_file.h; do
        [ -e "/s/usr/include/$f" ] || cp "$f" "/s/usr/include/$f"; done'
# WebKit links libwoff2dec alone; as a static archive it needs woff2common
# and brotli after it, so libwoff2dec.a becomes a linker script (lld prefixes
# the sysroot to absolute paths in scripts inside it).
mv "$S"/opt/woff2/lib/libwoff2dec.a "$S"/opt/woff2/lib/libwoff2dec-objects.a
printf 'GROUP ( /opt/woff2/lib/libwoff2dec-objects.a /opt/woff2/lib/libwoff2common.a -lbrotlidec -lbrotlicommon )\n' \
    > "$S"/opt/woff2/lib/libwoff2dec.a
# WebKit finds the library but does not add its include directory.
cp -r "$S"/opt/woff2/include/woff2 "$S"/usr/include/
echo "sysroot: $S"
