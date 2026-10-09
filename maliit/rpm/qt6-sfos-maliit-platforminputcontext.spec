# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-only
#
# The Qt 6 Maliit input context (the Sailfish keyboard for Qt 6 apps),
# rebuilt from Chum's source with Keel's two fixes (keel/maliit/README.md).
# Same name as Chum's package and a higher release, so Reef's repository
# replaces it. keel/maliit/rpm/prebuild.sh fetches the pinned source.
%global commit f5aa5d6e4b1ccfdadb631e5ab88782f8651d3443
%global srcroot keel/maliit
Name:       qt6-sfos-maliit-platforminputcontext
Version:    1.0.1+qt6.20241010182000.1.g9bb86e6
Release:    1.2.1.bso.shipwright1
Summary:    Maliit input context for Qt 6 apps on Sailfish OS (Keel fixes)
License:    LGPL-2.1-only
URL:        https://github.com/sailfishos-open/maliit-framework

BuildRequires:  cmake >= 3.19
BuildRequires:  ninja
BuildRequires:  gcc-c++
BuildRequires:  patch
BuildRequires:  qt6-qtbase-devel >= 6.8
BuildRequires:  qt6-qtbase-private-devel >= 6.8
BuildRequires:  qt6-qtdeclarative-devel >= 6.8
BuildRequires:  pkgconfig(xkbcommon)

%description
The Maliit platform input context plugin for Qt 6: connects Qt 6 apps to
the Sailfish keyboard (maliit-server). Built from the same source as
Chum's package, with two fixes for Keel apps on Lipstick: no crash when
the keyboard opens (an uninitialised pointer), and the keyboard's
rectangle reported, so text fields move above the keyboard.

%prep

%build
rm -rf target/keel-maliit/src
mkdir -p target/keel-maliit/src
tar -xzf target/keel-maliit/maliit-framework-%{commit}.tar.gz -C target/keel-maliit/src --strip-components=1
patch -d target/keel-maliit/src -p1 < %{srcroot}/patches/0001-keel-input-context.patch
%cmake -S target/keel-maliit/src -B target/keel-maliit/build -G Ninja --no-warn-unused-cli \
    -DCMAKE_BUILD_TYPE=Release \
    -Denable-docs=OFF -Denable-tests=OFF -Denable-glib=OFF -Denable-xcb=OFF \
    -Denable-wayland=OFF -Denable-hwkeyboard=OFF -Denable-qt6-inputcontext=ON
cmake --build target/keel-maliit/build --target maliitplatforminputcontextplugin %{?_smp_mflags}

%install
install -D -m 0755 target/keel-maliit/build/libmaliitplatforminputcontextplugin.so \
    %{buildroot}%{_libdir}/qt6/plugins/platforminputcontexts/libmaliitplatforminputcontextplugin.so

%files
%{_libdir}/qt6/plugins/platforminputcontexts/libmaliitplatforminputcontextplugin.so

%changelog
* Mon Oct 05 2026 Shipwright - 1.0.1+qt6.20241010182000.1.g9bb86e6-1.2.1.bso.shipwright1
- Initialise containerConnectionInterface: Qt 6 apps crashed when the
  keyboard opened (Jolla Phone).
- keyboardRect() returns the keyboard's rectangle, so Keel apps lay out
  above the keyboard.
