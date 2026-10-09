# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# SailfishApp API (SailfishApp::main, pathTo, createView, ...) for Qt6 apps
# on Keel. Named so that it installs next to the system (Qt5) libsailfishapp.
#
#   mb2 -t SailfishOS-5.2.0.15-aarch64 -s keel/rpm/shipwright-keel-sailfishapp.spec build

Name:       shipwright-keel-sailfishapp
Version:    0.1.0
Release:    13
Summary:    SailfishApp library for Qt6 apps (Keel)
# keel-wl-shell's protocol code is generated from Qt's BSD-3-Clause
# surface-extension.xml (keel/shell/PROVENANCE.md).
License:    MIT AND BSD-3-Clause
URL:        https://github.com/shipwright/shipwright
Source0:    %{name}-%{version}.tar.bz2

BuildRequires:  cmake >= 3.19
BuildRequires:  ninja
BuildRequires:  gcc-c++
BuildRequires:  qt6-qtbase-devel >= 6.8
BuildRequires:  qt6-qtdeclarative-devel >= 6.8
# keel-wl-shell: Qt's Wayland client plugin API, libwayland-client and
# wayland-scanner.
BuildRequires:  qt6-qtwayland-devel >= 6.8
BuildRequires:  wayland-devel
Requires:       qt6-qtbase-gui >= 6.8
Requires:       qt6-qtwayland >= 6.8
Requires:       qt6-qtdeclarative >= 6.8
Requires:       shipwright-keel-silica

%description
libkeel-sailfishapp provides the SailfishApp API for Qt6 apps built
against Keel: application(), createView(), pathTo(), pathToMainQml() and
main(), with app data under /usr/share/<appname>. It also holds Keel's
launcher (keellauncher.h): direct mode on Lipstick and the hand-over of
booster-keel's prepared application and view, and keel-wl-shell, the Qt
Wayland shell integration that gives Lipstick the windows it expects
(wl_shell and qt_extended_surface, as native Qt 5 apps).

%package devel
Summary:    Development files for shipwright-keel-sailfishapp
Requires:   %{name} = %{version}-%{release}
Requires:   qt6-qtbase-devel
Requires:   qt6-qtdeclarative-devel

%description devel
Header (sailfishapp.h), pkg-config files and CMake package for building
Qt6 apps against Keel's SailfishApp. `sailfishapp.pc` lives in
%{_libdir}/keel/pkgconfig so that it only replaces the Qt5 one when that
directory is put first in PKG_CONFIG_PATH; `keel-sailfishapp.pc` is always
available.

%prep
%setup -q -n %{name}-%{version}

%build
%cmake -S keel -B build-keel-sailfishapp -G Ninja --no-warn-unused-cli \
    -DCMAKE_BUILD_TYPE=Release \
    -DKEEL_BUILD_SILICA=OFF \
    -DKEEL_BUILD_ACTIONS=OFF \
    -DKEEL_BUILD_NEMO_COMPAT=OFF \
    -DKEEL_BUILD_QT5COMPAT=OFF \
    -DKEEL_BUILD_PLATFORM=OFF \
    -DBUILD_TESTING=OFF \
    -DKEEL_QML_INSTALL_DIR=%{_libdir}/qt6/qml \
    -DKEEL_SAILFISHAPP_SHARE_DIR=%{_datadir}
cmake --build build-keel-sailfishapp %{?_smp_mflags}

%install
DESTDIR=%{buildroot} cmake --install build-keel-sailfishapp

%post
/sbin/ldconfig
# A running booster keeps the old library in memory: restart the per-app
# ones (the shared one hosts Reef, which may be doing this update).
systemctl-user try-restart 'booster-keel@*.service' >/dev/null 2>&1 || :
%postun -p /sbin/ldconfig

%files
%{_libdir}/libkeel-sailfishapp.so.*
%{_libdir}/qt6/plugins/wayland-shell-integration/libkeel-wl-shell.so
%license LICENSES/MIT.txt LICENSES/BSD-3-Clause.txt

%files devel
%dir %{_includedir}/keel
%dir %{_libdir}/keel
%dir %{_libdir}/keel/pkgconfig
%{_includedir}/keel/sailfishapp
%{_libdir}/libkeel-sailfishapp.so
%{_libdir}/keel/pkgconfig/sailfishapp.pc
%{_libdir}/pkgconfig/keel-sailfishapp.pc
%{_libdir}/cmake/KeelSailfishApp

%changelog
* Fri Oct 09 2026 Shipwright - 0.1.0-13
- An update restarts the running app boosters, so apps start with the new library.

* Fri Oct 09 2026 Shipwright - 0.1.0-12
- KEEL_STARTUP_TRACE=1 prints the time of the app's first frame, for measuring launch times, boosted or not.

* Fri Oct 09 2026 Shipwright - 0.1.0-11
- Scrolling and page transitions move in step with the display. The app's cover window no longer counts as on screen while the app is in front, so Qt drives animations from the display's frames instead of a separate timer. On the Jolla Phone a list fling misses 2.3% of frames, from 4.0% (stock Silica apps: 2.7%), and the list starts moving about 80 ms sooner.
- An app's own QML files are compiled in the background shortly after start-up, so the first push of each page is quicker (about 40 ms on the Jolla Phone). KEEL_QML_WARMUP=0 turns it off.
- KEEL_QML_PROFILE=<port> turns on QML profiling (qmlprofiler) for a run.

* Thu Oct 08 2026 Shipwright - 0.1.0-10
- Each installed build of an app keeps its own QML cache, so an update never runs the last build's compiled QML.

* Tue Oct 06 2026 Shipwright - 0.1.0-9
- The QML disk cache works in Sailjail: Firejail sets
  QML_DISABLE_DISK_CACHE=1 for every program, so sandboxed apps compiled
  all of their QML at every start. Keel unsets it (KEEL_QML_DISK_CACHE=0
  keeps it off).
- KEEL_SWAP_INTERVAL overrides the swap interval.

* Mon Oct 05 2026 Shipwright - 0.1.0-7
- keel-wl-shell keeps windows exposed: Lipstick sends Hidden to apps on
  screen, and treating it as "not exposed" throttled every Keel app
  (Pacific scrolled at 9 frames a second).

* Mon Oct 05 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-6
- keel-wl-shell, Keel's Qt Wayland shell integration for Lipstick, and the
  launcher's default (QT_WAYLAND_SHELL_INTEGRATION="keel-wl-shell;wl-shell"):
  a window Lipstick hides (display off, the switcher) keeps its surface and
  is drawn again when shown, instead of being destroyed by Qt 6's wl-shell;
  window properties in Qt 5.6's format; the cover is not full screen.

* Sat Oct 03 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-5
- Licence: MIT (LICENSING.md).

* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-4
- English singular and plural for numerus qsTr() strings without a
  catalog ("(s)", "(singular|plural)").
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-3
- Keel's launcher (keellauncher.h): direct mode on Lipstick by default on
  Sailfish OS, booster-keel's application and view (ADR-0016).
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-2
- Licence file; -devel owns its include, keel and pkgconfig directories.
* Wed Sep 30 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-1
- Initial Qt6 SailfishApp for Keel.
