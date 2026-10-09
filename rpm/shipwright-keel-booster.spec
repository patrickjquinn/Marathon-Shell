# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# booster-keel: mapplauncherd booster for Keel (Qt 6) apps (ADR-0016,
# keel/booster). Built on its own against the installed libkeel-sailfishapp
# and mapplauncherd's libapplauncherd:
#
#   mb2 -t SailfishOS-5.2.0.15-aarch64 --snapshot=<you> \
#       -s keel/rpm/shipwright-keel-booster.spec build
#
# Under mb2 the build runs in the checkout (the repository root).
Name:       shipwright-keel-booster
Version:    0.1.0
Release:    5
Summary:    Application launch booster for Keel (Qt 6 Silica) apps
License:    MIT
URL:        https://github.com/shipwright/shipwright
Source0:    %{name}-%{version}.tar.bz2

BuildRequires:  cmake >= 3.19
BuildRequires:  ninja
BuildRequires:  gcc-c++
BuildRequires:  pkgconfig(applauncherd) >= 4.2.3
BuildRequires:  pkgconfig(systemd)
BuildRequires:  qt6-qtbase-devel >= 6.8
BuildRequires:  qt6-qtdeclarative-devel >= 6.8
Requires:       mapplauncherd >= 4.2.3
# booster-keel.service starts through the silica-session booster, as
# booster-silica-qt5.service does.
Requires:       mapplauncherd-booster-silica-qt5
Requires:       systemd-user-session-targets
Requires:       shipwright-keel-sailfishapp
Requires:       shipwright-keel-silica
Requires:       qt6-qtwayland
# booster.inc, which the sandboxed booster's profile includes.
Requires:       sailjail-permissions

%description
A mapplauncherd booster for apps built on Keel: it starts Qt 6 for
Lipstick (wayland-egl with the wl-shell integration) and a QML engine with
Sailfish.Silica and Keel loaded and their common types compiled, before an
app is launched. An unsandboxed app (X-Nemo-Application-Type=keel in its
desktop file) runs in booster-keel.service's prepared process. A sandboxed
app runs in booster-keel@<app>.service, a booster inside the app's own
Sailjail sandbox, which the app's package starts with the session
(user-session.target.d) and its desktop file reaches with
`invoker --type=keel -A`, as Jolla's camera and email do with theirs.

%prep
%setup -q -n %{name}-%{version}

%build
# libkeel-sailfishapp from this same tree, built and staged first: the
# shipwright-keel-sailfishapp-devel package from the same CI build is not
# installable into mb2's build root (tools/build/sdk/build-rpms.sh).
%cmake -S keel -B build-keel-sailfishapp -G Ninja --no-warn-unused-cli \
    -DCMAKE_BUILD_TYPE=Release \
    -DKEEL_BUILD_SILICA=OFF \
    -DKEEL_BUILD_ACTIONS=OFF \
    -DKEEL_BUILD_NEMO_COMPAT=OFF \
    -DKEEL_BUILD_QT5COMPAT=OFF \
    -DKEEL_BUILD_PLATFORM=OFF \
    -DKEEL_BUILD_BOOSTER=OFF \
    -DBUILD_TESTING=OFF
cmake --build build-keel-sailfishapp %{?_smp_mflags}
DESTDIR=$PWD/sailfishapp-stage cmake --install build-keel-sailfishapp
%cmake -S keel/booster -B build-keel-booster -G Ninja --no-warn-unused-cli \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH=$PWD/sailfishapp-stage%{_prefix}
cmake --build build-keel-booster %{?_smp_mflags}

%install
DESTDIR=%{buildroot} cmake --install build-keel-booster
mkdir -p %{buildroot}%{_userunitdir}/user-session.target.wants
ln -s ../booster-keel.service %{buildroot}%{_userunitdir}/user-session.target.wants/

%post
# The boosters, started now rather than at the next session (apps installed
# with this package's update would otherwise not start: `invoker -A` needs
# their booster). The shared one is only started, not restarted: Reef, which
# may be doing this install, can be running in it.
systemctl-user daemon-reload >/dev/null 2>&1 || :
systemctl-user start booster-keel.service >/dev/null 2>&1 || :
systemctl-user try-restart 'booster-keel@*.service' >/dev/null 2>&1 || :

%preun
if [ $1 -eq 0 ]; then
    systemctl-user stop booster-keel.service 'booster-keel@*.service' >/dev/null 2>&1 || :
fi

%postun
systemctl-user daemon-reload >/dev/null 2>&1 || :

%files
%{_libexecdir}/mapplauncherd/booster-keel
%{_datadir}/booster-keel
%{_userunitdir}/booster-keel.service
%{_userunitdir}/booster-keel@.service
%{_userunitdir}/user-session.target.wants/booster-keel.service
%{_sysconfdir}/sailjail/permissions/booster-keel.profile
%license LICENSES/MIT.txt

%changelog
* Fri Oct 09 2026 Shipwright - 0.1.0-5
- Starts the boosters when it is installed or updated, not at the next restart.

* Fri Oct 09 2026 Shipwright - 0.1.0-4
- The Sailjail profile of the per-application booster (booster-keel@<app>.service), without which a sandboxed Keel app's booster could not start.

* Sat Oct 03 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-3
- Licence: MIT (LICENSING.md).

* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-2
- Build against libkeel-sailfishapp staged from the same tree.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-1
- First booster: Qt 6 for Lipstick, Sailfish.Silica and Keel preloaded.
