# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT

Name:       shipwright-keel-shell
Summary:    Nested Wayland compositor that runs Keel (Qt6) apps as Lipstick citizens
Version:    0.1.0
Release:    3
# src/backend/*, src/core/{containerstate,runner}.* and the orientation table
# are BSD-3-Clause (derived from qt-runner and newcompositor); the rest is
# Shipwright proprietary until the Keel licence is chosen (docs/plan.md).
License:    BSD-3-Clause AND MIT
URL:        https://github.com/shipwright/shipwright
Source0:    %{name}-%{version}.tar.bz2

# Same Qt/compositor build dependencies as qt-runner (rinigus/qt-runner
# rpm/qt-runner.spec), minus Silica/sailfishapp/svg which keel-shell does
# not use, plus the private QtCompositor headers (same package).
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Gui)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(Qt5DBus)
BuildRequires:  pkgconfig(Qt5Compositor) >= 5.6.0
BuildRequires:  pkgconfig(wayland-server)

Requires:   qt5-qtwayland-wayland_egl
# Runtime helper used for ambience forwarding (dconf dump / dconf watch).
Requires:   dconf
# The nested app needs Qt6 with the wl-shell integration and, for the
# Sailfish keyboard, the Maliit input context that talks to keel-shell's
# peer bus (the qt-runner-qt6 set). They live in Chum (chum:testing for 5.2).
Recommends: qt6-qtwayland
Recommends: qt6-sfos-maliit-platforminputcontext

%description
keel-shell starts a private Wayland compositor for one Qt6 app, maps the
app's main surface into a Lipstick window and its cover surface into a
second Lipstick window with CATEGORY=cover, and forwards orientation,
ambience, activation and DPI to the app. Part of Shipwright Keel.

%prep
%setup -q -n %{name}-%{version}

%build
# Works both from the monorepo root (tools/build/sdk, %%{_builddir} is the
# repository) and from keel/shell alone; builds out of tree either way.
pro=%{_builddir}/keel-shell.pro
[ -f "$pro" ] || pro=%{_builddir}/keel/shell/keel-shell.pro
mkdir -p %{_builddir}/target/rpm/keel-shell
cd %{_builddir}/target/rpm/keel-shell
%qmake5 "$pro" VERSION=%{version}
%make_build

%install
cd %{_builddir}/target/rpm/keel-shell
%qmake5_install

%files
%{_bindir}/keel-shell
%{_datadir}/doc/%{name}
%license %{_datadir}/licenses/%{name}

%changelog
* Sat Oct 03 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-3
- Licence: BSD-3-Clause AND MIT (LICENSING.md).

* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-2
- Private D-Bus socket in a 0700 runtime directory with EXTERNAL auth only;
  asynchronous dconf reads; qt5compat on QML_IMPORT_PATH from the build's
  libdir; licence files marked %%license.

* Wed Sep 30 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-1
- Initial keel-shell: qt-runner-style nested compositor on system Qt 5.6
  with newcompositor-style multi-window and a CATEGORY=cover window.
