# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Qt 5 QML API shims for unported Sailfish apps on Keel (keel/qt5compat).
# QML only. Installed into Keel's own import directory, which keel-shell puts
# first on QML_IMPORT_PATH for the apps it runs; nothing goes into Qt 6's QML
# directory.
#
#   mb2 -t SailfishOS-5.2.0.15-aarch64 --snapshot=<you> \
#       -s keel/rpm/shipwright-keel-qt5compat.spec build

Name:       shipwright-keel-qt5compat
Version:    0.1.0
Release:    6
Summary:    Qt 5 QML API shims for Sailfish apps on Keel
License:    MIT
URL:        https://github.com/shipwright/shipwright
Source0:    %{name}-%{version}.tar.bz2

# The qmldir files would otherwise make rpm provide qml(QtGraphicalEffects),
# qml(QtFeedback) and qml(QtMultimedia), which Qt 5 apps' generated requires
# could then resolve to this Qt 6 package instead of the Qt 5 modules.
%global __provides_exclude ^qml\\(
# QML and JavaScript only: nothing for debuginfo or debugsource.
%global debug_package %{nil}

BuildRequires:  cmake >= 3.19
BuildRequires:  ninja
BuildRequires:  gcc-c++
BuildRequires:  qt6-qtbase-devel >= 6.8
BuildRequires:  qt6-qtdeclarative-devel >= 6.8
Requires:       qt6-qtdeclarative >= 6.8
# The Qt Quick 2.x shims re-export Keel.SilicaScreen (Silica's Screen).
Requires:       shipwright-keel-silica
# QtGraphicalEffects 1.x re-exports Qt5Compat.GraphicalEffects (Chum).
Requires:       qt6-qt5compat >= 6.8
# QtMultimedia 5.x (MediaPlayer, Camera, ...) wraps Qt 6 Multimedia, whose QML
# module and backends Chum's qt6-qtmultimedia contains; only apps importing
# it need it.
Recommends:     qt6-qtmultimedia >= 6.8

%description
QML modules that give Qt 5 era Sailfish apps the Qt 5 QML APIs Qt 6
removed, without source changes: QtGraphicalEffects 1.x (on
Qt5Compat.GraphicalEffects), QtFeedback 5.0 (no-op), RegExpValidator and
VisualItemModel under QtQuick 2.0 to 2.14, and the Qt 5 MediaPlayer,
Audio, VideoOutput, SoundEffect and Camera API under QtMultimedia 5.x.

%prep
%setup -q -n %{name}-%{version}

%build
%cmake -S keel -B build-keel-qt5compat -G Ninja --no-warn-unused-cli \
    -DCMAKE_BUILD_TYPE=Release \
    -DKEEL_BUILD_SILICA=OFF \
    -DKEEL_BUILD_ACTIONS=OFF \
    -DKEEL_BUILD_NEMO_COMPAT=OFF \
    -DKEEL_BUILD_SAILFISHAPP=OFF \
    -DKEEL_BUILD_PLATFORM=OFF \
    -DBUILD_TESTING=OFF \
    -DKEEL_QT5COMPAT_INSTALL_DIR=%{_libdir}/keel/qt5compat
cmake --build build-keel-qt5compat %{?_smp_mflags}

%install
DESTDIR=%{buildroot} cmake --install build-keel-qt5compat

%files
%dir %{_libdir}/keel
%{_libdir}/keel/qt5compat
%license LICENSES/MIT.txt

%changelog
* Sat Oct 03 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-6
- Licence: MIT (LICENSING.md).

* Sat Oct 03 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-5
- No debuginfo or debugsource packages: the package has no binaries.
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-4
- QtQuick 2.x shims re-export Keel.SilicaScreen after Qt Quick, so an
  unqualified Screen is Silica's whatever the import order.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-3
- QtMultimedia 5.x: Camera (over Qt 6 CaptureSession), QtMultimedia
  singleton, VideoOutput source: camera, map*() functions.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-2
- Licence file.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-1
- Initial Qt 5 QML API shims: QtGraphicalEffects, QtFeedback,
  RegExpValidator, VisualItemModel, QtMultimedia 5.x.
