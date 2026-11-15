# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Pacific's web engine: our own WPE WebKit 2.54.2 build (legacy libwpe API;
# build/build.sh, PGO-trained on the phone it is built for), with libwpe,
# WPEBackend-fdo, libepoxy and Atlantic's Sailfish compat libraries and shims
# from Atlantic's build 746.1 (shoal/pacific/engine/README.md). WebKit is
# compiled by build/build.sh, outside this spec; here only the EGL probe is.
#
# Everything lives in /opt/pacific, so it installs next to Atlantic's own
# packages without a file in common. libWPEWebKit has its helper paths
# compiled in (/opt/wpe-sfos/...); %%install rewrites that prefix, byte for
# byte, to /opt/pacific/ (same length, see the comment there).
#
# The RPMs come from rpm/prebuild.sh (fetch-rpms.sh: local mirror or
# Atlantic's repository, checked against SHA256SUMS) into
# target/pacific-engine/rpms. By hand, from the repository root:
#     shoal/pacific/engine/rpm/prebuild.sh
#     tools/build/native/native.sh shoal/pacific/engine/rpm/shipwright-pacific-engine.spec
#
# Two builds of WebKit, one per processor (build/pacific-toolchain.cmake),
# each its own package with the same files, so exactly one is installed:
#   pacific_cpu armv8.2 (the default): shipwright-pacific-engine, for the
#     Jolla Phone and C2 and the Xperia 10 III and IV (ARMv8.2 with LSE
#     atomics, RCpc, dot product and FP16), from
#     pacific-webkit-2.54.2-aarch64.tar.xz; also builds -dictionaries
#     (noarch, shared by both) and -devel.
#   pacific_cpu armv8.0: shipwright-pacific-engine-armv80, for the Xperia
#     10 II (ARMv8.0 with CRC and crypto), from
#     pacific-webkit-2.54.2-aarch64-armv8.0.tar.xz; the engine only.
# Both provide shipwright-pacific-engine-abi, which Pacific and its web view
# require; Reef installs the one the phone's processor runs
# (reef/client/backend, catalogue requires_cpu). The armv8.0 build:
#     PACIFIC_CPU=armv8.0 shoal/pacific/engine/rpm/prebuild.sh
#     PACIFIC_CPU=armv8.0 tools/build/native/native.sh shoal/pacific/engine/rpm/shipwright-pacific-engine.spec
# (tools/build/sdk/specs.conf turns PACIFIC_CPU into --define 'pacific_cpu ...').

%global srcroot shoal/pacific/engine
%{!?engine_rpms: %global engine_rpms %{shipwright_src}/target/pacific-engine/rpms}
%{!?engine_sources: %global engine_sources %{shipwright_src}/target/pacific-engine/sources}
%global dictionaries en_US en_GB de_DE fr_FR es_ES it_IT sv_SE nl_NL pl_PL pt_BR pt_PT ga_IE
%global prefix_dir /opt/pacific
%{!?pacific_cpu: %global pacific_cpu armv8.2}
%if "%{pacific_cpu}" == "armv8.0"
%global engine_name shipwright-pacific-engine-armv80
%global other_engine shipwright-pacific-engine
%global tarball_suffix -armv8.0
# What -march=armv8-a+crc+crypto uses beyond ARMv8.0 (/proc/cpuinfo names).
%global cpu_needs aes pmull sha1 sha2 crc32
%global cpu_name an ARMv8.0 processor with the crypto and CRC extensions
%global cpu_hint %{nil}
%global main_build 0
%else
%global engine_name shipwright-pacific-engine
%global other_engine shipwright-pacific-engine-armv80
%global tarball_suffix %{nil}
# What -march=armv8.2-a+crypto+rcpc+dotprod+fp16 uses (LSE atomics, FP16,
# RCpc, dot product, crypto), as /proc/cpuinfo names them; the catalogue's
# requires_cpu for this package (tools/build/reef/cpu-builds.json) is the
# same list.
%global cpu_needs atomics fphp asimdhp lrcpc asimddp aes
%global cpu_name an ARMv8.2 processor (as in the Jolla Phone or Xperia 10 III and later)
%global cpu_hint Install shipwright-pacific-engine-armv80 instead.
%global main_build 1
%endif
%global debug_package %{nil}
# Prebuilt, already linked against the 5.2 root: keep rpm from rewriting
# them beyond stripping.
%global __brp_check_rpaths %{nil}
# The bundled sonames are private (not provided to other packages), so
# automatic requirements on them are dropped; system libraries stay
# required automatically.
%global __provides_exclude_from ^%{prefix_dir}/.*$
%global __requires_exclude ^lib(WPEWebKit-2\\.0|wpe-1\\.0|WPEBackend-fdo-1\\.0|epoxy|woff2common|woff2dec|gbm|jpeg|avif|dav1d|brotlicommon|brotlidec|enchant-2|voikko|gssapi_krb5|atomic|hybris-common|hybris-platformcommon|hybris-eglplatformcommon|gralloc|hardware|ui|sync)\\.so.*$

Name:           %{engine_name}
Version:        2.54.2
Release:        746.1.pacific17.10
Summary:        WPE WebKit engine for Pacific
# WebKit: LGPL-2.0-or-later, LGPL-2.1-or-later and BSD-2-Clause. libwpe,
# WPEBackend-fdo: BSD-2-Clause. libepoxy, Mesa libgbm, dav1d, brotli: MIT or
# BSD. libavif: BSD-2-Clause. libjpeg-turbo: IJG AND BSD-3-Clause AND Zlib.
# enchant: LGPL-2.1-or-later (built here). libvoikko: MPL-1.1 OR
# GPL-2.0-or-later OR LGPL-2.1-or-later (built here). Atlantic's shims and environment script: MPL-2.0.
License:        LGPL-2.0-or-later AND LGPL-2.1-or-later AND BSD-2-Clause AND BSD-3-Clause AND MIT AND IJG AND Zlib AND MPL-2.0 AND (MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later)
URL:            https://github.com/SpecSierra/atlantic-engine
ExclusiveArch:  aarch64

BuildRequires:  cpio
BuildRequires:  gcc
BuildRequires:  patchelf
BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  pkgconfig(glib-2.0)
BuildRequires:  pkgconfig(gmodule-2.0)
BuildRequires:  hunspell-devel
BuildRequires:  python3-base
BuildRequires:  unzip
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(glesv2)
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-server)
BuildRequires:  wayland-devel
# libhybris's Wayland platform includes wayland-egl-backend.h.
BuildRequires:  pkgconfig(wayland-egl-backend)
# Sailfish OS 5.2 ships libsoup 3 (Atlantic's 5.1 build carried its own).
Requires:       libsoup3 >= 3.4
Requires:       libicu >= 73
Requires:       libseccomp
Requires:       gstreamer1.0
# Spell checking: enchant's hunspell provider uses the system libhunspell;
# the dictionaries are Pacific's own (subpackage).
Requires:       hunspell
Requires:       shipwright-pacific-engine-dictionaries = %{version}-%{release}
# What Pacific and its web view require: either build of the engine.
Provides:       shipwright-pacific-engine-abi = %{version}-%{release}
# Both builds install the same files in /opt/pacific.
Conflicts:      %{other_engine}
# Only Pacific uses it (nothing else requires the engine or the web view;
# the -devel and -examples subpackages are for development), and it is large
# (the engine and dictionaries are about 150 MB, with the boost socket
# enabled): it must not outlive Pacific. Pacific requires it and it requires
# Pacific, so removing either by any route (Reef, pkcon, rpm, the app grid)
# removes both.
Requires:       shipwright-pacific
# Hardware decoding and the camera, where the phone has them.
Recommends:     gstreamer1.0-droid
Recommends:     gstreamer1.0-plugins-good
Recommends:     gstreamer1.0-plugins-bad
Recommends:     gstreamer1.0-libav

%description
WPE WebKit 2.54.2 for Sailfish OS (libwpe and WPEBackend-fdo, exportable
EGL images, Skia, JIT on), built by Shipwright for %{pacific_cpu} and
optimised from browsing on the phone, with the libraries Sailfish OS lacks
and Atlantic's libhybris shims, in /opt/pacific for Pacific's Qt 6 web view.
Installs /usr/libexec/pacific/pacific-env.sh (the runtime environment), the
PacificWebEngine Sailjail permission and pacific-egl-probe.

%if %{main_build}
%package -n shipwright-pacific-engine-dictionaries
Summary:        Spell-checking dictionaries for Pacific's engine
BuildArch:      noarch
# Per dictionary (README.md): en_US/en_GB MIT AND BSD; de_DE GPL-2.0 OR
# GPL-3.0; fr_FR MPL-2.0; es_ES GPL-3.0 OR LGPL-3.0 OR MPL-1.1; it_IT
# GPL-3.0; sv_SE LGPL-3.0; nl_NL BSD-3-Clause OR CC-BY-3.0; pl_PL GPL-3.0 OR
# LGPL-3.0 OR MPL-2.0; pt_BR LGPL-3.0 OR MPL-2.0; pt_PT GPL-2.0 OR LGPL-2.1
# OR MPL-1.1; ga_IE GPL-2.0. Finnish Voikko data: GPL-2.0-or-later.
License:        (MIT AND BSD-3-Clause) AND (GPL-2.0-only OR GPL-3.0-only) AND MPL-2.0 AND (GPL-3.0-only OR LGPL-3.0-only OR MPL-1.1) AND GPL-3.0-only AND LGPL-3.0-only AND (BSD-3-Clause OR CC-BY-3.0) AND (GPL-3.0-only OR LGPL-3.0-only OR MPL-2.0) AND (LGPL-3.0-only OR MPL-2.0) AND (GPL-2.0-only OR LGPL-2.1-only OR MPL-1.1) AND GPL-2.0-only AND GPL-2.0-or-later

# As the engine (above).
Requires:       shipwright-pacific

%description -n shipwright-pacific-engine-dictionaries
Hunspell dictionaries for spell checking in Pacific, in
%{prefix_dir}/share/hunspell: English (US, GB), German, French, Spanish,
Italian, Swedish, Dutch, Polish, Portuguese (Brazil, Portugal) and Irish,
from wooorm/dictionaries (which normalises the LibreOffice and upstream
dictionaries to UTF-8), and Finnish from the Voikko project (morphology
data in %{prefix_dir}/share/voikko, with the voikko-fi source it is built
from). Each dictionary's licence is installed with it.

%package devel
Summary:        Headers and pkg-config files for building against Pacific's engine
Requires:       %{name} = %{version}-%{release}
Requires:       pkgconfig(glib-2.0)
Requires:       pkgconfig(libsoup-3.0)
Requires:       pkgconfig(xkbcommon)

%description devel
WPE WebKit 2.0, libwpe 1.0 and WPEBackend-fdo 1.0 headers with pkg-config
files in %{prefix_dir}/lib/pkgconfig (PKG_CONFIG_PATH=%{prefix_dir}/lib/pkgconfig).
%endif

%prep
case "%{pacific_cpu}" in
    armv8.2|armv8.0) ;;
    *) echo "pacific_cpu must be armv8.2 or armv8.0, not %{pacific_cpu}" >&2; exit 1 ;;
esac

%build
# enchant 2.3.3 (the version libWPEWebKit was linked against), built for
# /opt/pacific: its provider directory, data directory and default hunspell
# dictionary directory are compiled in, so nothing is looked up in system
# paths (Atlantic's Ubuntu-built enchant looks in /usr/lib/aarch64-linux-gnu).
# Finnish: libvoikko (VFST backend only) for enchant's voikko provider, its
# dictionary path compiled in as %{prefix_dir}/share/voikko.
rm -rf target/pacific-engine/enchant
mkdir -p target/pacific-engine/enchant
voikko=$PWD/target/pacific-engine/enchant/voikko-stage
tar -xzf %{engine_sources}/libvoikko-4.3.2.tar.gz -C target/pacific-engine/enchant
(cd target/pacific-engine/enchant/libvoikko-4.3.2 &&
    ./configure --prefix=%{prefix_dir} --libdir=%{prefix_dir}/lib --disable-static \
        --disable-hfst --disable-buildtools --with-dictionary-path=%{prefix_dir}/share/voikko &&
    make -j4 && make install DESTDIR="$voikko")
tar -xzf %{engine_sources}/enchant-2.3.3.tar.gz -C target/pacific-engine/enchant
(cd target/pacific-engine/enchant/enchant-2.3.3 &&
    ./configure --prefix=%{prefix_dir} --libdir=%{prefix_dir}/lib --disable-static \
        --with-hunspell --with-voikko --without-aspell --without-nuspell --without-hspell \
        --with-hunspell-dir=%{prefix_dir}/share/hunspell \
        VOIKKO_CFLAGS="-I$voikko%{prefix_dir}/include" VOIKKO_LIBS="-L$voikko%{prefix_dir}/lib -lvoikko" \
        CPPFLAGS="-I$voikko%{prefix_dir}/include" &&
    make -j4)
# The runtime environment as an ELF program: Sailjail starts only ELF
# binaries and its sandbox has no shell, so Pacific re-execs itself through
# pacific-env instead of a wrapper script (launcher/pacific-env.c).
gcc %{optflags} -o pacific-env %{srcroot}/launcher/pacific-env.c
gcc %{optflags} -o pacific-boostd %{srcroot}/boost/pacific-boostd.c
gcc %{optflags} -shared -fPIC -o libpacific-eglshadercache.so %{srcroot}/shims/eglshadercache.c -ldl
# libhybris's Wayland EGL platform with cancelled buffers fixed (hybris/README.md).
CXXFLAGS="%{optflags}" sh %{srcroot}/hybris/build.sh %{srcroot}/hybris hybris-build
gcc %{optflags} -o pacific-egl-probe %{srcroot}/probe/egl-probe.c \
    $(pkg-config --cflags --libs egl glesv2 wayland-client)

%install
stage=$PWD/target/pacific-engine/stage
rm -rf "$stage"
mkdir -p "$stage"
# Atlantic's RPMs and this processor's WebKit tarball, each against its line
# in SHA256SUMS (the other processor's tarball need not be here).
webkit=pacific-webkit-%{version}-aarch64%{tarball_suffix}.tar.xz
grep -q "  $webkit\$" %{shipwright_src}/%{srcroot}/SHA256SUMS ||
    { echo "SHA256SUMS has no line for $webkit (build/build.sh tarball prints it)" >&2; exit 1; }
(cd %{engine_rpms} && grep -E "  ([^ ]+\.rpm|$webkit)\$" %{shipwright_src}/%{srcroot}/SHA256SUMS |
    sha256sum -c --quiet -)
for r in wpewebkit2-2.54.0 libwpe-1.17.0 wpebackend-fdo-1.17.0 libepoxy-1.5.11 wpe-sfos-compat-1.0.0; do
    (cd "$stage" && rpm2cpio %{engine_rpms}/$r-746.1.aarch64.rpm | cpio -idm --quiet)
done
# WebKit itself is our own build (../build: clang 22, ThinLTO, PGO, BOLT,
# for %{pacific_cpu}, installed to /opt/pacific). Atlantic's packages still
# supply libwpe, WPEBackend-fdo, libepoxy and the compat set.
ours=$PWD/target/pacific-engine/ours
rm -rf "$ours"; mkdir -p "$ours"
tar -xJf %{engine_rpms}/$webkit -C "$ours"

P=%{buildroot}%{prefix_dir}
install -d $P/lib/compat $P/lib/shims $P/lib/gstreamer-1.0 $P/libexec/wpe-webkit-2.0 \
    $P/lib/wpe-webkit-2.0/injected-bundle $P/share $P/include $P/lib/pkgconfig

# Engine libraries (with their soname links).
cp -a "$ours"%{prefix_dir}/lib/libWPEWebKit-2.0.so.1* $P/lib/
cp -a "$stage"/usr/lib64/libwpe-1.0.so.1* \
    "$stage"/usr/lib64/libWPEBackend-fdo-1.0.so.1* "$stage"/usr/lib64/libepoxy.so.0* \
    "$stage"/usr/lib64/libwoff2common.so.1* "$stage"/usr/lib64/libwoff2dec.so.1* $P/lib/
# Development links.
ln -s libWPEWebKit-2.0.so.1 $P/lib/libWPEWebKit-2.0.so
ln -s libwpe-1.0.so.1 $P/lib/libwpe-1.0.so
ln -s libWPEBackend-fdo-1.0.so.1 $P/lib/libWPEBackend-fdo-1.0.so

# Helpers: WebProcess, NetworkProcess, the injected bundle. Built with
# /opt/pacific as their prefix, so their compiled-in paths are already ours.
LC_ALL=C grep -a -q '%{prefix_dir}/libexec/wpe-webkit-2.0' $P/lib/libWPEWebKit-2.0.so.1.* ||
    { echo "libWPEWebKit does not look for its helpers in %{prefix_dir}" >&2; exit 1; }
install -m 0755 "$ours"%{prefix_dir}/libexec/wpe-webkit-2.0/WPEWebProcess "$ours"%{prefix_dir}/libexec/wpe-webkit-2.0/WPENetworkProcess \
    $P/libexec/wpe-webkit-2.0/
install -m 0755 "$ours"%{prefix_dir}/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so \
    $P/lib/wpe-webkit-2.0/injected-bundle/

# Compat libraries Sailfish OS 5.2 lacks. Not libsoup (5.2 has 3.6), not
# hunspell (5.2 has 1.7.3), not enchant (built above) and not Atlantic's
# libharfbuzz-icu stand-in (patch 0036: WebKit no longer links it).
for l in libatomic.so.1 libavif.so.16 libbrotlicommon.so.1 libbrotlidec.so.1 libdav1d.so.7 \
         libgbm.so.1 libgssapi_krb5.so.2 libjpeg.so.8; do
    cp -a "$stage"/usr/lib64/wpe-compat/$l* $P/lib/compat/
done
install -m 0755 "$stage"/usr/lib64/wpe-compat/libegl-stubs.so "$stage"/usr/lib64/wpe-compat/libsyncskip.so \
    "$stage"/usr/lib64/wpe-compat/libsigill_skip.so $P/lib/shims/
install -m 0755 libpacific-eglshadercache.so $P/lib/shims/
# Camera device provider for getUserMedia (gst-droid camera source).
install -m 0755 "$stage"/usr/lib64/gstreamer-1.0/libgstdroidcamdeviceprovider.so $P/lib/gstreamer-1.0/

# enchant and its hunspell and voikko providers, plus enchant-lsmod-2 and
# enchant-2 for diagnostics (device-check.sh).
ench=$PWD/target/pacific-engine/enchant/stage
rm -rf "$ench"
make -C target/pacific-engine/enchant/enchant-2.3.3 install DESTDIR="$ench"
cp -a "$ench"%{prefix_dir}/lib/libenchant-2.so.2* $P/lib/
install -d $P/lib/enchant-2 $P/bin $P/share/enchant $P/share/hunspell
install -m 0755 "$ench"%{prefix_dir}/lib/enchant-2/enchant_hunspell.so "$ench"%{prefix_dir}/lib/enchant-2/enchant_voikko.so $P/lib/enchant-2/
cp -a target/pacific-engine/enchant/voikko-stage%{prefix_dir}/lib/libvoikko.so.1* $P/lib/
install -m 0755 "$ench"%{prefix_dir}/bin/enchant-lsmod-2 "$ench"%{prefix_dir}/bin/enchant-2 $P/bin/
install -m 0644 "$ench"%{prefix_dir}/share/enchant/enchant.ordering $P/share/enchant/
for f in $P/lib/enchant-2/*.so $P/bin/enchant-lsmod-2 $P/bin/enchant-2; do
    patchelf --page-size 65536 --set-rpath %{prefix_dir}/lib "$f"
done

# Dictionaries, each with its licence.
# Only the main build packages them (-dictionaries is shared); the armv8.0
# build drops them at the end of %%install.
install -d %{buildroot}%{_datadir}/licenses/shipwright-pacific-engine-dictionaries
for d in %{dictionaries}; do
    install -m 0644 %{engine_sources}/$d.aff %{engine_sources}/$d.dic $P/share/hunspell/
    install -m 0644 %{engine_sources}/$d.license %{buildroot}%{_datadir}/licenses/shipwright-pacific-engine-dictionaries/$d.license
done
# Finnish (Voikko): the VFST morphology, its licence, and the voikko-fi source.
install -d $P/share/voikko/source
(cd $P/share/voikko && unzip -q %{engine_sources}/voikko-fi-dict-5.zip)
install -m 0644 %{engine_sources}/voikko-fi-2.5.tar.gz $P/share/voikko/source/
tar -xzOf %{engine_sources}/voikko-fi-2.5.tar.gz voikko-fi-2.5/COPYING \
    > %{buildroot}%{_datadir}/licenses/shipwright-pacific-engine-dictionaries/fi_FI-voikko.license

# A run path to the private libraries, so every ELF resolves without
# LD_LIBRARY_PATH (ldd checks, and the helpers if a launcher forgets the
# environment). The shims are preloaded and need nothing. patchelf may have
# to add a LOAD segment; --page-size 65536 keeps it aligned for any kernel
# page size (its 4 KiB default breaks loading on 16 KiB kernels).
find $P/lib -maxdepth 1 -type f -name '*.so.*' -exec patchelf --page-size 65536 --set-rpath %{prefix_dir}/lib:%{prefix_dir}/lib/compat {} \;
find $P/lib/compat -type f -name '*.so*' -exec patchelf --page-size 65536 --set-rpath %{prefix_dir}/lib/compat:%{prefix_dir}/lib {} \;
for f in $P/libexec/wpe-webkit-2.0/* $P/lib/wpe-webkit-2.0/injected-bundle/*.so; do
    patchelf --page-size 65536 --set-rpath %{prefix_dir}/lib:%{prefix_dir}/lib/compat "$f"
done

install -m 0644 "$stage"/opt/wpe-sfos/libexec/atlantic/pulse-client.conf $P/share/pulse-client.conf
# Our build looks for the Web Inspector's resources in its own data
# directory (Atlantic's had them at share/inspector.gresource).
install -D -m 0644 "$ours"%{prefix_dir}/share/wpe-webkit-2.0/inspector.gresource $P/share/wpe-webkit-2.0/inspector.gresource
cp -a "$ours"%{prefix_dir}/share/build-config $P/share/

# Headers and pkg-config.
cp -a "$ours"%{prefix_dir}/include/wpe-webkit-2.0 "$stage"/usr/include/wpe-1.0 "$stage"/usr/include/wpe-fdo-1.0 \
    "$stage"/usr/include/epoxy $P/include/
cat > $P/lib/pkgconfig/wpe-1.0.pc <<EOF
prefix=%{prefix_dir}
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: wpe-1.0
Description: libwpe (Pacific engine)
Version: 1.17.0
Requires.private: xkbcommon
Libs: -L\${libdir} -lwpe-1.0
Cflags: -I\${includedir}/wpe-1.0
EOF
cat > $P/lib/pkgconfig/wpebackend-fdo-1.0.pc <<EOF
prefix=%{prefix_dir}
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: wpebackend-fdo-1.0
Description: WPEBackend-fdo (Pacific engine)
Version: 1.17.0
Requires: wpe-1.0
Libs: -L\${libdir} -lWPEBackend-fdo-1.0
Cflags: -I\${includedir}/wpe-fdo-1.0
EOF
cat > $P/lib/pkgconfig/wpe-webkit-2.0.pc <<EOF
prefix=%{prefix_dir}
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: WPE WebKit
Description: WPE WebKit 2.54 (Pacific engine)
Version: %{version}
Requires: glib-2.0 gio-2.0 libsoup-3.0 wpe-1.0
Libs: -L\${libdir} -lWPEWebKit-2.0
Cflags: -I\${includedir}/wpe-webkit-2.0
EOF

install -D -m 0755 %{srcroot}/pacific-env.sh %{buildroot}%{_libexecdir}/pacific/pacific-env.sh
install -D -m 0755 pacific-env %{buildroot}%{_libexecdir}/pacific/pacific-env
install -D -m 0755 pacific-egl-probe %{buildroot}%{_libexecdir}/pacific/pacific-egl-probe
# Clock floors while a page is touched or scrolls (boost/pacific-boostd.c).
install -D -m 0755 pacific-boostd %{buildroot}%{_libexecdir}/pacific/pacific-boostd
install -D -m 0644 %{srcroot}/boost/pacific-boost.service %{buildroot}%{_unitdir}/pacific-boost.service
install -D -m 0644 %{srcroot}/boost/pacific-boost.socket %{buildroot}%{_unitdir}/pacific-boost.socket
install -D -m 0644 %{srcroot}/boost/pacific-boost-baseline.service %{buildroot}%{_unitdir}/pacific-boost-baseline.service
# Only the socket is enabled: the daemon starts on Pacific's first request.
install -d %{buildroot}%{_unitdir}/sockets.target.wants
ln -s ../pacific-boost.socket %{buildroot}%{_unitdir}/sockets.target.wants/pacific-boost.socket
ln -s ../pacific-boost-baseline.service %{buildroot}%{_unitdir}/sockets.target.wants/pacific-boost-baseline.service
# HYBRIS_EGLPLATFORM_DIR (pacific-env): the fixed Wayland platform, the
# system's other platforms beside it.
install -D -m 0755 hybris-build/eglplatform_wayland.so $P/lib/hybris/eglplatform_wayland.so
for platform in null fbdev hwcomposer; do
    ln -s /usr/lib64/libhybris/eglplatform_$platform.so $P/lib/hybris/eglplatform_$platform.so
done
install -D -m 0755 %{srcroot}/device-check.sh %{buildroot}%{_libexecdir}/pacific/device-check.sh
install -D -m 0644 %{srcroot}/sailjail/PacificWebEngine.permission \
    %{buildroot}%{_sysconfdir}/sailjail/permissions/PacificWebEngine.permission
install -D -m 0644 %{srcroot}/README.md %{buildroot}%{_docdir}/%{name}/README.md
install -d %{buildroot}%{_datadir}/licenses/%{name}
install -m 0644 LICENSES/LGPL-2.1-or-later.txt LICENSES/MPL-2.0.txt LICENSES/MIT.txt LICENSES/BSD-3-Clause.txt \
    %{buildroot}%{_datadir}/licenses/%{name}/
install -m 0644 target/pacific-engine/enchant/libvoikko-4.3.2/COPYING %{buildroot}%{_datadir}/licenses/%{name}/libvoikko-COPYING
install -m 0644 target/pacific-engine/enchant/libvoikko-4.3.2/LICENSE.CORE %{buildroot}%{_datadir}/licenses/%{name}/libvoikko-LICENSE.CORE
rm -rf "$stage" "$ours"
%if %{main_build} == 0
# The armv8.0 build is the engine only: -dictionaries and -devel come from
# the main build (they hold no code for the processor).
rm -rf $P/share/hunspell $P/share/voikko %{buildroot}%{_datadir}/licenses/shipwright-pacific-engine-dictionaries \
    $P/include $P/lib/pkgconfig
rm -f $P/lib/*.so
%endif

# Built for one processor: on another, the WebProcess dies with SIGILL at
# start, so the install stops here, saying why. Reef offers each phone only
# the build its processor runs (catalogue requires_cpu); this catches pkcon,
# zypper and rpm, which pick a provider of shipwright-pacific-engine-abi
# without looking at the processor.
%pre
f=$(grep -m1 '^Features' /proc/cpuinfo 2>/dev/null)
if [ -n "$f" ]; then
  for x in %{cpu_needs}; do
    case " ${f#*:} " in
      *" $x "*) ;;
      *) echo "This build of Pacific's engine (%{name}) needs %{cpu_name}; this phone's lacks $x. %{cpu_hint}" >&2
         exit 1 ;;
    esac
  done
fi

# An earlier version ran the daemon from boot, bound to the socket's name:
# stop it (it puts the clocks back) before the socket takes the name.
%post
systemctl daemon-reload >/dev/null 2>&1 || :
systemctl stop pacific-boost.service >/dev/null 2>&1 || :
# The clocks to put back, taken now (the old daemon has just put its own back).
%{_libexecdir}/pacific/pacific-boostd --baseline >/dev/null 2>&1 || :
systemctl start pacific-boost.socket >/dev/null 2>&1 || :

%preun
if [ "$1" = 0 ]; then
    systemctl stop pacific-boost.socket pacific-boost.service >/dev/null 2>&1 || :
fi

%postun
systemctl daemon-reload >/dev/null 2>&1 || :

%files
%dir %{prefix_dir}
%dir %{prefix_dir}/lib
%{prefix_dir}/lib/*.so.*
%{prefix_dir}/lib/compat
%{prefix_dir}/lib/shims
%{prefix_dir}/lib/hybris
%{prefix_dir}/lib/gstreamer-1.0
%{prefix_dir}/lib/wpe-webkit-2.0
%{prefix_dir}/lib/enchant-2
%{prefix_dir}/bin
%{prefix_dir}/libexec
%dir %{prefix_dir}/share
%{prefix_dir}/share/enchant
%{prefix_dir}/share/pulse-client.conf
%{prefix_dir}/share/wpe-webkit-2.0
%{prefix_dir}/share/build-config
%{_libexecdir}/pacific
%config %{_sysconfdir}/sailjail/permissions/PacificWebEngine.permission
%{_docdir}/%{name}
%{_datadir}/licenses/%{name}
%{_unitdir}/pacific-boost.service
%{_unitdir}/pacific-boost.socket
%{_unitdir}/sockets.target.wants/pacific-boost.socket
%{_unitdir}/pacific-boost-baseline.service
%{_unitdir}/sockets.target.wants/pacific-boost-baseline.service

%if %{main_build}
%files -n shipwright-pacific-engine-dictionaries
%{prefix_dir}/share/hunspell
%{prefix_dir}/share/voikko
%{_datadir}/licenses/shipwright-pacific-engine-dictionaries

%files devel
%{prefix_dir}/include
%{prefix_dir}/lib/*.so
%{prefix_dir}/lib/pkgconfig
%endif

%changelog
* Mon Oct 26 2026 Shipwright - 2.54.2-746.1.pacific17.10
- A fling no longer stutters partway: the threads that move the page get
  the CPU sooner instead of waiting behind painting.
- A page that turns a blur effect on or off as it scrolls no longer freezes
  and stops responding to touch.
* Mon Oct 26 2026 Shipwright - 2.54.2-746.1.pacific17.9
- A fast fling no longer runs onto a white page: the page is painted ahead
  of where the fling is going, and what is on screen is painted first.
- Arabic, Hebrew, Indic and Thai text is shaped for its script: Arabic
  letters join again.
- A WebP image scaled down while it decodes no longer reads freed memory.
* Sun Oct 25 2026 Shipwright - 2.54.2-746.1.pacific17.8
- A drag no longer freezes while the page repaints: on OSNews it stopped
  for a tenth of a second each time the page redrew.
- Pages move in screen pixels rather than whole CSS pixels, so slow drags
  and the end of a fling glide instead of stepping, and a finger that stops
  holds the page still instead of letting it slide back a few pixels.
- A finger that catches a moving page and drags on moves it at once, without
  a pause and a jump, and a drag starts at its pace without a jump the size
  of the touch slop.
- Scripts that listen for pointer or touch events (analytics, ads) no longer
  hold up a drag once it is scrolling.
* Sun Oct 25 2026 Shipwright - 2.54.2-746.1.pacific17.7
- The engine is WPE WebKit 2.54.2, from 2.54.0. 2.54.1 brought touch
  scrolling that does not wait for a busy page where the page does not listen
  for touches, pasting images, input method fixes (text deleted, the caret
  while composing, inputmode honoured), correct memory-use thresholds, and
  fixes to scaled backgrounds, filters and 3D layers. 2.54.2 composites
  backdrop filters faster, frees suspended pages and idle processes when
  memory runs low, fixes more of the input method, and fixes crashes and
  rendering bugs.
- A dark page stays dark under the floating toolbar and past its end: the
  page's own background colour shows there instead of white.
- 100vh is the whole screen, as in Safari: sections sized to the screen no
  longer stop at the toolbar and leave a band when it slides away (svh is the
  screen with the toolbar, dvh follows it).
- Flicks still stack: 2.54.1's new touch scrolling would have dropped the
  speed a caught page carries into the next flick.
* Mon Oct 19 2026 Shipwright - 2.54.0-746.1.pacific17.6
- Smoother scrolling on phones with an Adreno GPU (the Xperia 10 II): the compositor no longer waits on the CPU for each frame's GPU fence.
* Mon Oct 19 2026 Shipwright - 2.54.0-746.1.pacific17.5
- The store and the installer describe the engine as what it is now: our own WebKit build, not a repackage of Atlantic's.
- shipwright-pacific-engine-armv80 is out: the engine for older processors (Xperia 10 II, Sailfish OS 5.1), trained on that phone.
* Sun Oct 18 2026 Shipwright - 2.54.0-746.1.pacific17.4
- The engine now checks before installing that the phone's processor can run it, and comes in a separate build for older processors (the Xperia 10 II).
* Thu Oct 15 2026 Shipwright - 2.54.0-746.1.pacific17.3
- Builds in a fresh Sailfish OS 5.2.0.20 build root: it asks for the Wayland
  EGL headers it uses instead of relying on another package to bring them.

* Mon Oct 12 2026 Shipwright - 2.54.0-746.1.pacific17.2
- The clock floors the touch boost puts back are taken at boot, before the
  screen is touched: on phones whose kernel raises the floor for a moment on
  every touch, a boosted floor could otherwise have been kept all boot.
- A program refused a boost is mentioned in the journal at most once a minute.
- On a phone without a Mali GPU (the Xperia 10 II), the journal says the
  GPU settings were not tuned for it. Nothing else changes.

* Mon Oct 12 2026 Shipwright - 2.54.0-746.1.pacific17.1
- The touch boost runs only while Pacific is in use: it starts on Pacific's
  first request and exits a minute after the last, instead of from boot.
- The clocks always come back, even if the boost service crashes or is
  killed while boosting: the values from before any boost are kept for the
  whole boot and put back by every instance and after every exit.
- The engine and its dictionaries require Pacific (which requires them):
  removing Pacific from the app grid or with pkcon removes them too,
  instead of leaving about 150 MB and the boost socket behind.
- Only Pacific itself can ask for a boost.

* Mon Oct 12 2026 Shipwright - 2.54.0-746.1.pacific17
- Flicks stack smoothly (patch 0019): a flick on a page still moving adds
  that page's speed, only when the flick itself is at least half that speed
  and the page moves at 350 px/s or more. Lifting a finger that caught the
  page no longer throws it to the end, and the second flick of a train no
  longer jumps to full speed. A finger that catches a page late in a long
  fling is a catch, not a press.
- Going back to a site you just left always loads (patch 0020): the address
  bar sometimes showed the new address over the old page and nothing
  happened, and Stop did not help (The Verge, OSNews, The Verge again).
* Sat Oct 10 2026 Shipwright - 2.54.0-746.1.pacific16
- Drags are drawn where the finger will be when the frame is shown, from
  its recent velocity, not where it was a resampling latency ago
  (patch 0017). 200 ms flicks: the page trailed the finger by 33-42 ms
  as it lifted, now 2-12 ms, with steps as even as before. The
  prediction eases in, never moves the page against the finger, fades at
  low speed, is dropped on a reversal and eases back while the finger
  rests. PACIFIC_SCROLL_PREDICT=0 turns it off.
- Flings slow as on iOS (pacific-env sets WEBKIT_KINETIC_DECEL_FRICTION
  to 2): upstream's desktop tuning lost half a flick's speed in 200 ms and
  coasted 420 css px; it now goes about 820, as far as iOS, at the same
  frame rates.
- Flings behave as iOS's (patch 0018): a finger landing on a coasting
  page stops it within a frame, and that tap is not a click (it opened the
  link under the finger); a fling launches at the finger's speed as it
  lifts (it was 0.8x); quick flicks carry as on iOS, building from 2 to
  about 20 css px per ms over ten flicks (they stayed at about 3); a
  finger that rests before lifting no longer flings.

* Tue Oct 06 2026 Shipwright - 2.54.0-746.1.pacific15
- Pages no longer freeze after a long scroll: zero-copy tiles' gralloc
  buffers used up the WebProcess's 1024 open files and the next frame
  buffer could not be imported. pacific-env raises the limit to the hard
  limit, and the tile pool keeps within a sixth of it (patch 0006).
- CSS drop-shadow, blur and colour-matrix filters are recorded as Skia
  image filters and run on the painting threads, not applied on the main
  thread (patch 0008). Flinging The Verge: 40% less main-thread CPU, 77
  frames a second with no pause over 25 ms, from 74 with 7.
- Dragging is resampled to the display's frames (patch 0009): moves from
  the touchscreen no longer beat against the 90 Hz panel. Frames that did
  not move while dragging: OSNews 0.9% from 28%, The Verge 4.7% from 28%.
- The touch slop is the embedder's (patch 0010): a drag starts scrolling
  after 8 dp instead of 16, 42-44 ms after touch-down instead of 59-62.
- Scrolling runs on one clock, the frames (patch 0011): the display link
  no longer ticks animations a second time between frames, so each frame
  moves by an even step. Step spread while flinging: 0.16-0.21 from
  0.58-0.78.
- The embedder can say what its toolbar covers (patch 0012): fixed
  elements at the bottom of a page, such as cookie banners and sites'
  bottom navigation, sit above Pacific's floating toolbar, and a page's
  last lines scroll clear of it.
- Back is instant on sites that send Cache-Control: no-store (patch
  0013): their pages are kept for going back, for three minutes and only
  while the site's HttpOnly (session) cookies are unchanged, as Chrome
  does. Back on The Verge took a 2.5 s reload.
- Find in page highlights the matches of what was typed (patch 0014):
  it showed those of the text one keystroke earlier, every "n" of the
  first keystroke while finding "Norway".
- A pinch no longer scrolls the page (patch 0015): a second finger stops
  any scroll without a fling, and only one finger ever scrolls.
- Even steps while dragging and no lurch when the finger lifts (patch
  0016): the fling starts after the last move is shown, only frames
  advance scrolling, and the touch resampling waits as long as reports
  actually take. Drag step spread halved.

* Tue Oct 06 2026 Shipwright - 2.54.0-746.1.pacific14
- Scroll animations step with the frames (patch 0007): the compositor's
  frame acknowledgements tick them, by whole refresh periods, instead of a
  timer that drifted against the display. Flinging, frames composited
  without moving: OSNews 0-3% from 8%, The Verge 1-2% from 8-59%.

* Tue Oct 06 2026 Shipwright - 2.54.0-746.1.pacific13
- pacific-boostd: CPU and GPU clock floors while a page is touched or
  scrolls (the web view asks for them). Flinging on the Jolla Phone, frames
  a second while the page moves: OSNews 74 to 87, Wikipedia 83 to 90 (the
  panel's rate), The Verge 80 to 86; frames over 25 ms down by two thirds.

* Tue Oct 06 2026 Shipwright - 2.54.0-746.1.pacific12
- libhybris's Wayland EGL platform with cancelled buffers fixed, used in
  place of the system's on the Jolla Phone (libhybris 0.0.5.58): when the
  GPU driver cancelled a buffer it stayed queued, and the next swap aborted
  the WebProcess (WaylandNativeWindow::finishSwap: wnb->busy == 1).

* Tue Oct 06 2026 Shipwright - 2.54.0-746.1.pacific11
- Zero-copy CPU tiles (patch 0006): a whole tile is painted into a pooled
  gralloc buffer the compositor shows through its EGLImage, with no upload.
  Flinging OSNews: 74 frames a second with 3-7 pauses over 25 ms in ten
  flings, against 65-68 with 14-15. PACIFIC_ZERO_COPY_TILES=0 turns it off.

* Tue Oct 06 2026 Shipwright - 2.54.0-746.1.pacific10
- Tiles are painted on the CPU by four threads in 512 px tiles and the GPU
  only composites (PACIFIC_GPU_MODE=mali; mali-gpu paints on the GPU as
  before). Flinging OSNews: 70 frames a second with no pause over 31 ms,
  against 61 with a repeatable 75 ms pause.
- The compositor thread runs at real-time priority, like the scrolling
  thread (patch 0005; PACIFIC_COMPOSITOR_REALTIME=0 turns it off).

* Tue Oct 06 2026 Shipwright - 2.54.0-746.1.pacific9
- A fling is never throttled with offscreen animations (patch 0004): once
  Wikipedia's header had scrolled away, flings ran at 10 frames a second.

* Tue Oct 06 2026 Shipwright - 2.54.0-746.1.pacific8
- The GPU driver's compiled shaders are kept on disk
  (libpacific-eglshadercache.so names Android's EGL blob cache file, as
  Android does for its apps). Each WebProcess compiled every shader Skia
  needed afresh, and scrolling paused while it did.

* Tue Oct 06 2026 Shipwright - 2.54.0-746.1.pacific7
- A finger tap never presses the scrollbar (patch 0003), and the scrollbar
  is back to WebKit's size (WEBKIT_SCROLLBAR_SCALE 1): Atlantic's 3 made its
  track 63 CSS px wide, so close buttons near the right edge, such as The
  Verge's terms-of-use notice, jumped the page instead of closing.
- wpe_sfos_set_safe_area_insets() for env(safe-area-inset-*) (patch 0002).

* Tue Oct 06 2026 Shipwright - 2.54.0-746.1.pacific6
- WebKit is our own build (../build): clang 22 with ThinLTO and profile-
  guided optimisation from a browsing workload on the Jolla Phone, for its
  Cortex-A78/A55 (armv8.2-a, LSE atomics). Speedometer 3.1 4.79 against
  3.95 for Atlantic's build. Atlantic's packages still supply libwpe,
  WPEBackend-fdo, libepoxy and the compat libraries.
- Offscreen animations are composited at 10 Hz: an idle Wikipedia page
  composited ~95 frames a second for a pulsing dot scrolled out of view.
- The Web Inspector's resources are where this build looks for them.

* Mon Oct 05 2026 Shipwright - 2.54.0-746.1.pacific5
- Mali mode without synchronous tile readback and per-frame glFinish:
  60 to 70 frames a second scrolling on the Jolla Phone instead of 54.

* Mon Oct 05 2026 Shipwright - 2.54.0-746.1.pacific4
- pacific-env, the runtime environment as an ELF program (Sailjail runs
  only ELF binaries and the sandbox has no shell); pacific-env.sh uses it.
- PacificWebEngine no longer whitelists /run/display: Firejail then hid the
  rest of /run, systemd-resolved's resolv.conf among it, and no name
  resolved in the sandbox.

* Sun Oct 04 2026 Shipwright - 2.54.0-746.1.pacific3
- Finnish spell checking: libvoikko 4.3.2 and enchant's voikko provider,
  the Voikko Finnish morphology in the -dictionaries subpackage.

* Sun Oct 04 2026 Shipwright - 2.54.0-746.1.pacific2
- Spell checking: enchant 2.3.3 built for /opt/pacific with the hunspell
  provider on the system libhunspell; twelve dictionaries in the new
  -dictionaries subpackage.

* Sun Oct 04 2026 Shipwright - 2.54.0-746.1.pacific1
- First package: Atlantic's engine build 746.1 in /opt/pacific, without
  bubblewrap, Qt 5, the Qualcomm tuning package or system services.
