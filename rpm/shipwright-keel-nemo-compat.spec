# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Qt6 builds of the open Nemo QML plugins (Nemo.DBus, Nemo.Notifications,
# Nemo.KeepAlive, Nemo.Configuration) with the legacy org.nemomobile.* URIs,
# plus libngf-qt's Nemo.Ngf plugin (events played by ngfd),
# nemo-qml-plugin-policy's Nemo.Policy (on libresourceqt's ResourceSet with
# Keel's QtDBus engine for the resource policy manager) and lipstick's
# launcher types as org.nemomobile.lipstick, for Keel apps.
#
#   mb2 -t SailfishOS-5.2.0.15-aarch64 -s keel/rpm/shipwright-keel-nemo-compat.spec build

Name:       shipwright-keel-nemo-compat
Version:    0.1.0
Release:    7
Summary:    Nemo QML plugins (DBus, Notifications, KeepAlive, Configuration) for Qt6 (Keel)
# Upstream sources keep their licences (keel/nemo-compat/PROVENANCE.md):
# nemo-qml-plugin-dbus plugin, nemo-keepalive, libngf-qt, libresourceqt,
# lipstick's launcher sources and mlite's MDesktopEntry are LGPL-2.1-only, nemo-dbus helpers, nemo-qml-plugin-notifications,
# nemo-qml-plugin-configuration, nemo-qml-plugin-policy and lipstick's
# synchronizelists.h are BSD-3-Clause.
License:    LGPL-2.1-only AND BSD-3-Clause AND MIT
URL:        https://github.com/shipwright/shipwright
Source0:    %{name}-%{version}.tar.bz2

BuildRequires:  cmake >= 3.19
BuildRequires:  ninja
BuildRequires:  gcc-c++
BuildRequires:  pkgconfig
BuildRequires:  qt6-qtbase-devel >= 6.8
BuildRequires:  qt6-qtdeclarative-devel >= 6.8
BuildRequires:  pkgconfig(libiphb)
BuildRequires:  mce-headers
# Chum's mlite-qt6-devel (MDConfGroup/MDConfItem over dconf).
BuildRequires:  pkgconfig(mlite6)
# org.nemomobile.lipstick launches .desktop files through GIO.
BuildRequires:  pkgconfig(gio-unix-2.0)
Requires:       qt6-qtbase >= 6.8
Requires:       qt6-qtbase-gui >= 6.8
Requires:       qt6-qtdeclarative >= 6.8
Requires:       (%{name}-dbus or nemo-qml-plugin-dbus-qt6)
Requires:       (%{name}-configuration or nemo-qml-plugin-configuration-qt6)
# Nemo.Ngf plays its events through the system's feedback daemon.
Requires:       ngfd

%description
Qt6 QML plugins API-compatible with Nemo.Notifications 1.0 and
Nemo.KeepAlive 1.1/1.2, plus the legacy imports org.nemomobile.dbus 2.0,
org.nemomobile.notifications 1.0, org.nemomobile.keepalive 1.0/1.1 and
org.nemomobile.configuration 1.0; org.nemomobile.lipstick 0.1 (lipstick's
LauncherItem, LauncherModel, LauncherWatcherModel, LauncherFolderModel and
LauncherFolderItem), Nemo.Ngf / org.nemomobile.ngf 1.0 (libngf-qt's plugin, events played
by ngfd) and Nemo.Policy / org.nemomobile.policy 1.0 (resources from the
system's resource policy manager; granted at once where none runs).
Nemo.DBus comes from %{name}-dbus or from
Chum's nemo-qml-plugin-dbus-qt6, Nemo.Configuration from
%{name}-configuration or from Chum's
nemo-qml-plugin-configuration-qt6.

%package dbus
Summary:    Nemo.DBus 2.0 for Qt6 (Keel build with Qt6 fixes)
# Chum ships the same upstream plugin at the same path. Keel's build adds
# two Qt6 fixes (PROVENANCE.md) that are offered upstream; once Chum has
# them this subpackage can be dropped.
Conflicts:  nemo-qml-plugin-dbus-qt6

%description dbus
The Nemo.DBus 2.0 QML plugin (DBusInterface, DBusAdaptor) built for Qt6,
with Keel's fixes for D-Bus variant demarshalling and Properties.Get.

%package configuration
Summary:    Nemo.Configuration 1.0 for Qt6 (Keel build)
# Chum ships the same upstream plugin at the same path; this subpackage is
# Keel's build of it, against Chum's mlite-qt6.
Conflicts:  nemo-qml-plugin-configuration-qt6

%description configuration
The Nemo.Configuration 1.0 QML plugin (ConfigurationValue,
ConfigurationGroup) built for Qt6 against mlite-qt6, so values are dconf keys.

%prep
%setup -q -n %{name}-%{version}

%build
%cmake -S keel -B build-keel-nemo -G Ninja --no-warn-unused-cli \
    -DCMAKE_BUILD_TYPE=Release \
    -DKEEL_BUILD_SILICA=OFF \
    -DKEEL_BUILD_ACTIONS=OFF \
    -DKEEL_BUILD_SAILFISHAPP=OFF \
    -DKEEL_BUILD_QT5COMPAT=OFF \
    -DKEEL_BUILD_PLATFORM=OFF \
    -DKEEL_REQUIRE_IPHB=ON \
    -DKEEL_REQUIRE_MLITE=ON \
    -DKEEL_REQUIRE_GIO=ON \
    -DBUILD_TESTING=OFF \
    -DKEEL_QML_INSTALL_DIR=%{_libdir}/qt6/qml
cmake --build build-keel-nemo %{?_smp_mflags}

%install
DESTDIR=%{buildroot} cmake --install build-keel-nemo
install -D -m 0644 keel/nemo-compat/PROVENANCE.md %{buildroot}%{_datadir}/doc/%{name}/PROVENANCE.md

%files
%{_libdir}/qt6/qml/Nemo/Notifications
%{_libdir}/qt6/qml/Nemo/KeepAlive
%{_libdir}/qt6/qml/org/nemomobile/dbus
%{_libdir}/qt6/qml/org/nemomobile/notifications
%{_libdir}/qt6/qml/org/nemomobile/keepalive
%{_libdir}/qt6/qml/org/nemomobile/configuration
%{_libdir}/qt6/qml/org/nemomobile/lipstick
%{_libdir}/qt6/qml/org/nemomobile/policy
%{_libdir}/qt6/qml/Nemo/Policy
%{_libdir}/qt6/qml/Nemo/Ngf
%{_libdir}/qt6/qml/org/nemomobile/ngf
%dir %{_libdir}/qt6/qml/Nemo
%dir %{_libdir}/qt6/qml/org/nemomobile
%dir %{_libdir}/qt6/qml/org
%license LICENSES/MIT.txt
%license keel/nemo-compat/upstream-licenses/*
%{_datadir}/doc/%{name}

%files dbus
%dir %{_libdir}/qt6/qml/Nemo
%{_libdir}/qt6/qml/Nemo/DBus

%files configuration
%dir %{_libdir}/qt6/qml/Nemo
%{_libdir}/qt6/qml/Nemo/Configuration

%changelog
* Sat Oct 03 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-7
- Licence: LGPL-2.1-only AND BSD-3-Clause AND MIT (LICENSING.md).

* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-6
- org.nemomobile.lipstick is lipstick's launcher types built for Qt6 (with
  mlite's MDesktopEntry compiled in) instead of Keel's LauncherItem.
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-5
- Nemo.Policy is nemo-qml-plugin-policy on libresourceqt's ResourceSet,
  ported to Qt6, with Keel's QtDBus engine talking to the resource policy
  manager, instead of the grant-always stand-in.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-4
- Nemo.Ngf is libngf-qt's QML plugin built for Qt6 (events played by ngfd)
  instead of the no-op stand-in; Requires ngfd.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-3
- Licences marked %%license; -dbus and -configuration own the Nemo
  QML directory; Nemo.Ngf / org.nemomobile.ngf no-op stand-in.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-2
- Nemo.Configuration (against mlite-qt6) with org.nemomobile.configuration;
  org.nemomobile.lipstick LauncherItem; Nemo.Policy grant-always stand-in.
* Wed Sep 30 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-1
- Initial Qt6 build of Nemo.DBus, Nemo.Notifications and Nemo.KeepAlive
  with legacy org.nemomobile URIs.
