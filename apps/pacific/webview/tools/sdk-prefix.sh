#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Makes a build and run prefix from the engine RPMs (Atlantic's, mirrored):
#
#   shoal/pacific/webview/tools/sdk-prefix.sh <prefix> [rpm directory]
#
# The RPMs are unpacked into <prefix>/root, and <prefix>/pkgconfig gets
# wpe-webkit-2.0.pc, wpe-1.0.pc and wpebackend-fdo-1.0.pc pointing there
# (Atlantic's own .pc files name /usr/lib, not /usr/lib64). Then:
#
#   PKG_CONFIG_PATH=<prefix>/pkgconfig cmake -S shoal/pacific/webview -B build
#
# Runs on the host (Fedora) and inside the Sailfish build container. The RPM
# directory defaults to ~/.cache/shipwright/atlantic-mirror/aarch64, whose
# SHA256SUMS is checked first.
set -eu
prefix=${1:?usage: sdk-prefix.sh <prefix> [rpm directory]}
rpms=${2:-$HOME/.cache/shipwright/atlantic-mirror/aarch64}
command -v rpm2cpio >/dev/null || { echo "sdk-prefix.sh: needs rpm2cpio and cpio" >&2; exit 2; }
if [ -f "$rpms/SHA256SUMS" ]; then
    (cd "$rpms" && sha256sum -c SHA256SUMS >/dev/null) || { echo "sdk-prefix.sh: checksum mismatch in $rpms" >&2; exit 1; }
fi
mkdir -p "$prefix/root" "$prefix/pkgconfig"
prefix=$(cd "$prefix" && pwd)
rpms=$(cd "$rpms" && pwd)
for r in "$rpms"/libwpe-*.rpm "$rpms"/wpebackend-fdo-*.rpm "$rpms"/libepoxy-*.rpm \
         "$rpms"/wpewebkit2-2*.rpm "$rpms"/wpe-sfos-compat-*.rpm; do
    [ -f "$r" ] || { echo "sdk-prefix.sh: missing $r" >&2; exit 1; }
    (cd "$prefix/root" && rpm2cpio "$r" | cpio -idm --quiet 2>/dev/null)
done
usr=$prefix/root/usr
cat > "$prefix/pkgconfig/wpe-1.0.pc" <<PC
prefix=$usr
libdir=$usr/lib64
includedir=$usr/include
Name: wpe-1.0
Description: libwpe (engine prefix)
Version: 1.17.0
Requires.private: xkbcommon
Libs: -L\${libdir} -lwpe-1.0
Cflags: -I\${includedir}/wpe-1.0
PC
cat > "$prefix/pkgconfig/wpebackend-fdo-1.0.pc" <<PC
prefix=$usr
libdir=$usr/lib64
includedir=$usr/include
Name: wpebackend-fdo-1.0
Description: WPEBackend-fdo (engine prefix)
Version: 1.17.0
Requires: wpe-1.0
Libs: -L\${libdir} -lWPEBackend-fdo-1.0
Cflags: -I\${includedir}/wpe-fdo-1.0
PC
cat > "$prefix/pkgconfig/wpe-webkit-2.0.pc" <<PC
prefix=$usr
libdir=$usr/lib64
includedir=$usr/include
Name: WPE WebKit
Description: WPE WebKit 2.54 (engine prefix)
Version: 2.54.0
Requires: glib-2.0 gio-2.0 libsoup-3.0 wpe-1.0
Libs: -L\${libdir} -lWPEWebKit-2.0
Cflags: -I\${includedir}/wpe-webkit-2.0
PC
echo "$prefix/pkgconfig"
