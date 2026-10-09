# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Keel's Sailfish platform modules for Qt6 apps (keel/platform, see
# keel/platform/PROVENANCE.md and README.md). So far: Sailfish.Media,
# Sailfish.Pickers, Sailfish.WebView / Sailfish.WebEngine,
# Sailfish.Secrets / Sailfish.Crypto (Qt6 builds of the sailfish-secrets
# client libraries), org.nemomobile.mpris (qtmpris), libaccounts-qt6
# with org.nemomobile.accounts, Amber.Web.Authorization, Amber.Mpris,
# Nemo.Thumbnailer, Nemo.Mce, Sailfish.Accounts and Sailfish.Policy.
#
#   mb2 -t SailfishOS-5.2.0.15-aarch64 --snapshot=<you> \
#       -s keel/rpm/shipwright-keel-platform.spec build

Name:       shipwright-keel-platform
Version:    0.1.0
Release:    19
Summary:    Sailfish platform QML modules for Qt6 apps (Keel)
# Clean-room code is Shipwright's; sailfish-secrets, nemo-qml-plugin-accounts,
# nemo-qml-plugin-thumbnailer, libmce-qt and sailfish-components-accounts
# are BSD-3-Clause (Jolla Ltd and others), libsignon-qt and libbuteosyncfw are
# LGPL-2.1-only (Nokia, Canonical, Jolla),
# amber-web-authorization is BSD-3-Clause (Open Mobile Platform LLC, Jolla
# Ltd), libaccounts-qt is
# LGPL-2.1-only (Nokia, Canonical), qtmpris is LGPL-2.1-or-later (Jolla Ltd),
# amber-mpris is LGPL-2.1-or-later with LGPL-2.1-only files (Jolla Ltd).
License:    MIT AND BSD-3-Clause AND LGPL-2.1-only AND LGPL-2.1-or-later AND MPL-2.0
URL:        https://github.com/shipwright/shipwright
Source0:    %{name}-%{version}.tar.bz2

# Chum's Qt6 (6.8.4 in chum:testing for Sailfish OS 5.2).
BuildRequires:  cmake >= 3.19
BuildRequires:  ninja
BuildRequires:  gcc-c++
BuildRequires:  pkgconfig
BuildRequires:  qt6-qtbase-devel >= 6.8
BuildRequires:  qt6-qtdeclarative-devel >= 6.8
# MediaKey sets the GRABBED_KEYS window property through Qt's platform
# native interface (qpa/qplatformnativeinterface.h).
BuildRequires:  qt6-qtbase-private-devel >= 6.8
BuildRequires:  pkgconfig(libaccounts-glib) >= 1.24
# Sailfish.Accounts: stored client keys and the user-group check, as the Qt 5
# module uses them.
BuildRequires:  pkgconfig(libsailfishkeyprovider)
BuildRequires:  pkgconfig(sailfishaccesscontrol)
BuildRequires:  pkgconfig(glib-2.0)
# Nemo.Thumbnailer reads the screen size from dconf (Chum's mlite-qt6-devel).
BuildRequires:  pkgconfig(mlite6)
# Nemo.Mce: MCE's D-Bus names (mce-headers).
BuildRequires:  pkgconfig(mce)
# Keel.WebEngine (-webview-qtwebengine): Qt WebEngine's C++ API for the
# WebEngineSettings it has no QML property for (Chum, chum:testing).
BuildRequires:  qt6-qtwebengine-devel >= 6.8
Requires:       %{name}-media = %{version}-%{release}
Requires:       %{name}-pickers = %{version}-%{release}
Requires:       %{name}-gallery = %{version}-%{release}
Requires:       %{name}-webview = %{version}-%{release}
Requires:       %{name}-secrets = %{version}-%{release}
Requires:       %{name}-accounts = %{version}-%{release}
Requires:       %{name}-mpris = %{version}-%{release}
Requires:       %{name}-amber = %{version}-%{release}
Requires:       %{name}-thumbnailer = %{version}-%{release}
Requires:       %{name}-mce = %{version}-%{release}
Requires:       %{name}-sailfish-accounts = %{version}-%{release}
Requires:       %{name}-policy = %{version}-%{release}

%description
Qt6 QML modules for Keel apps that Sailfish OS provides to Qt 5 apps
(so far Sailfish.Media, Sailfish.Pickers, Sailfish.Gallery, Sailfish.WebView and
Sailfish.WebEngine, Sailfish.Secrets and Sailfish.Crypto,
org.nemomobile.mpris, org.nemomobile.accounts, Amber.Web.Authorization,
Amber.Mpris, Nemo.Thumbnailer, Nemo.Mce, Sailfish.Accounts and
Sailfish.Policy). This package pulls in
all of them except Amber.Mpris, which comes from
%{name}-amber-mpris or from Chum's amber-qml-plugin-mpris-qt6.

%package media
Summary:    Sailfish.Media 1.0 for Qt6 (MediaKey and media player types)
Requires:   qt6-qtbase-gui >= 6.8
Requires:   qt6-qtdeclarative >= 6.8
Requires:   shipwright-keel-silica
# MprisPlayerControls controls MPRIS players through Amber.Mpris (this
# spec's -amber-mpris, or Chum's amber-qml-plugin-mpris-qt6).
Recommends: %{name}-amber-mpris = %{version}-%{release}

%description media
Sailfish.Media 1.0 for Keel: MediaKey (keys grabbed through Lipstick's
GRABBED_KEYS window property), MediaPlayerControls, MetadataReader,
MediaListItem, MediaPlayerControlsPanel, MediaPlayerPanelBackground and
MprisPlayerControls.

%package gallery
Summary:    Sailfish.Gallery 1.0 for Qt6 (ThumbnailImage, ImageViewer)
Requires:   qt6-qtdeclarative >= 6.8
Requires:   shipwright-keel-silica

%description gallery
Sailfish.Gallery 1.0 for Keel: ThumbnailImage and ImageViewer, the types
apps use outside the Gallery app.

%package pickers
Summary:    Sailfish.Pickers 1.0 for Qt6 (content, file and folder pickers)
Requires:   qt6-qtdeclarative >= 6.8
Requires:   shipwright-keel-silica
# The pickers list media from Tracker's index when it answers on the session
# bus, and scan the home directory otherwise.
Recommends: tracker

%description pickers
Sailfish.Pickers 1.0 for Keel: the picker pages and dialogs (images,
videos, music, documents, downloads, files and folders) on Keel's Silica.

%package webview
Summary:    Sailfish.WebView and Sailfish.WebEngine 1.0 for Qt6
Requires:   qt6-qtdeclarative >= 6.8
Requires:   shipwright-keel-silica
# Sailfish.WebView.Pickers opens Sailfish.Pickers' pages for file uploads.
Requires:   %{name}-pickers = %{version}-%{release}
# Pages render with Qt WebEngine (Chum's qt6-qtwebengine, chum:testing,
# pulled in by -webview-qtwebengine); without it a WebView shows the address
# and opens it in the browser.
Recommends: %{name}-webview-qtwebengine = %{version}-%{release}

%description webview
Sailfish.WebView 1.0 (WebView, WebViewPage, WebViewFlickable) and
Sailfish.WebEngine 1.0 (WebEngine, WebEngineSettings, DownloadHelper) for
Keel, rendering with Qt WebEngine, with sailfish-components-webview's
Sailfish.WebView.Popups, .Pickers and .Controls (MPL-2.0) for the page's
dialogs, permission requests, context menu and pickers.

%package webview-qtwebengine
Summary:    Qt WebEngine settings for Keel's Sailfish.WebView
Requires:   %{name}-webview = %{version}-%{release}
Requires:   qt6-qtwebengine >= 6.8

%description webview-qtwebengine
Keel.WebEngine 1.0 (ProfilePolicy), which applies Sailfish.WebEngine's
cookieBehavior, doNotTrack and colorScheme settings to Keel's WebView through
Qt WebEngine's C++ API. Kept apart so that -webview does not depend on Qt
WebEngine.

%package secrets
Summary:    Sailfish.Secrets and Sailfish.Crypto 1.0 for Qt6
Requires:   qt6-qtbase >= 6.8
Requires:   qt6-qtdeclarative >= 6.8
# The client libraries talk to the system's secrets daemon.
Requires:   sailfishsecretsdaemon

%description secrets
Qt6 builds of the sailfish-secrets client libraries (libsailfishsecrets-qt6,
libsailfishcrypto-qt6) and their QML plugins, Sailfish.Secrets 1.0 and
Sailfish.Crypto 1.0, for Keel apps. They use the system's sailfishsecretsd.

%package secrets-devel
Summary:    Headers for the Qt6 sailfish-secrets client libraries
Requires:   %{name}-secrets = %{version}-%{release}
Requires:   qt6-qtbase-devel >= 6.8

%description secrets-devel
Headers (under include/sailfish-qt6) and pkg-config files
(sailfishsecrets-qt6, sailfishcrypto-qt6) for C++ Keel apps.

%package mpris
Summary:    org.nemomobile.mpris 1.0 for Qt6 (MPRIS media players)
Requires:   qt6-qtbase >= 6.8
Requires:   qt6-qtdeclarative >= 6.8

%description mpris
qtmpris built for Qt6: org.nemomobile.mpris 1.0 (Mpris, MprisPlayer,
MprisManager). An MprisPlayer publishes the app on the session bus as an
MPRIS media player, which the lock screen and other MPRIS clients control.

%package amber
Summary:    Amber.Web.Authorization 1.0 for Qt6 (OAuth 1.0a / 2.0 sign-in)
Requires:   qt6-qtbase >= 6.8
Requires:   qt6-qtdeclarative >= 6.8

%description amber
amber-web-authorization built for Qt6 as a QML plugin:
Amber.Web.Authorization 1.0 (OAuth1, OAuth2Ac, OAuth2AcPkce,
OAuth2Implicit, RedirectListener and the OAuth10a / OAuth2* QML helpers).
The sign-in page opens in the system browser and comes back to a loopback
redirect listener. No C++ library is installed.

%package amber-mpris
Summary:    Amber.Mpris 1.0 for Qt6 (MPRIS players and controllers)
Requires:   qt6-qtbase >= 6.8
Requires:   qt6-qtdeclarative >= 6.8
# Chum ships the same upstream plugin at the same path; either serves Keel
# apps, so the metapackage requires neither (PROVENANCE.md).
Conflicts:  amber-qml-plugin-mpris-qt6

%description amber-mpris
amber-mpris built for Qt6 as a QML plugin: Amber.Mpris 1.0 (MprisPlayer,
MprisController, Mpris, MprisMetaData). An MprisPlayer publishes the app on
the session bus as an MPRIS media player; an MprisController follows and
controls the other players. No C++ library is installed.

%package thumbnailer
Summary:    Nemo.Thumbnailer 1.0 for Qt6 (image, video and PDF thumbnails)
Requires:   qt6-qtbase-gui >= 6.8
Requires:   qt6-qtdeclarative >= 6.8
# Video and PDF thumbnails come from thumbnaild's helpers
# (thumbnaild-video, thumbnaild-pdf), as for the Qt 5 plugin.
Requires:   thumbnaild

%description thumbnailer
nemo-qml-plugin-thumbnailer built for Qt6 as a QML plugin: Nemo.Thumbnailer
1.0 (Thumbnail and the image://nemoThumbnail provider), sharing the system
thumbnail cache with Qt 5 apps. No C++ library is installed.

%package mce
Summary:    Nemo.Mce 1.0 for Qt6 (display, lock, battery and call state)
Requires:   qt6-qtbase >= 6.8
Requires:   qt6-qtdeclarative >= 6.8
Requires:   mce

%description mce
libmce-qt built for Qt6 as a QML plugin: Nemo.Mce 1.0 (MceDisplay,
MceTkLock, MceBatteryLevel, MceBatteryState, MceBatteryStatus,
MceCableState, MceChargerState, MceChargerType, MceChargingState,
McePowerSaveMode, MceCallState, MceNameOwner), following MCE on the system
bus. No C++ library is installed.

%package accounts
Summary:    libaccounts-qt6 and org.nemomobile.accounts 1.0 for Qt6
Requires:   qt6-qtbase >= 6.8
Requires:   qt6-qtdeclarative >= 6.8
Requires:   libaccounts-glib >= 1.24

%description accounts
libaccounts-qt 1.17 built for Qt6 and nemo-qml-plugin-accounts ported to Qt6
(org.nemomobile.accounts 1.0), reading the system accounts database through
libaccounts-glib. Sign-in is in %{name}-sailfish-accounts.

%package sailfish-accounts
Summary:    Sailfish.Accounts 1.0 for Qt6 (accounts and sign-in)
Requires:   %{name}-accounts = %{version}-%{release}
Requires:   qt6-qtdeclarative >= 6.8
Requires:   shipwright-keel-silica
# Sign-in goes through the system's signond (peer-to-peer D-Bus), sync
# profiles through msyncd, as for the Qt 5 module.
Requires:   signon-qt5
Requires:   libsailfishkeyprovider
Requires:   sailfish-access-control
Recommends: buteo-syncfw-qt5-msyncd

%description sailfish-accounts
sailfish-components-accounts built for Qt6 as a QML plugin: Sailfish.Accounts
1.0 (Account, AccountManager, AccountModel, Provider, Service and their
models, SignInParameters, AccountAuthenticator, AccountValue, the
AccountSyncManager types and the Silica account views), with Qt6 builds of
libsignon-qt and of libbuteosyncfw's profile and client parts compiled in. No
C++ library is installed.

%package policy
Summary:    Sailfish.Policy 1.0 for Qt6 (device policies set by an MDM)
Requires:   qt6-qtbase >= 6.8
Requires:   qt6-qtdeclarative >= 6.8
# The policy store (/var/lib/policy) is sailfish-policy's; without it every
# policy reads as disabled.
Requires:   sailfish-policy

%description policy
Sailfish.Policy 1.0 (PolicyValue, AccessPolicy) and libsailfishpolicy-qt6
for Keel: the device policies MDM applications set, read from Sailfish's
policy store, and the privacy switch state. Read only; a policy Keel cannot
read is reported as disabled.

%package policy-devel
Summary:    Headers for libsailfishpolicy-qt6
Requires:   %{name}-policy = %{version}-%{release}
Requires:   qt6-qtbase-devel >= 6.8

%description policy-devel
Headers (under include/sailfishpolicy-qt6) and the sailfishpolicy-qt6
pkg-config file for C++ Keel apps.

%package accounts-devel
Summary:    Headers for libaccounts-qt6
Requires:   %{name}-accounts = %{version}-%{release}
Requires:   qt6-qtbase-devel >= 6.8
Requires:   pkgconfig(libaccounts-glib)

%description accounts-devel
Headers (under include/accounts-qt6) and the accounts-qt6 pkg-config file.

%prep
%setup -q -n %{name}-%{version}

%build
%cmake -S keel -B build-keel-platform -G Ninja --no-warn-unused-cli \
    -DCMAKE_BUILD_TYPE=Release \
    -DKEEL_BUILD_SILICA=OFF \
    -DKEEL_BUILD_ACTIONS=OFF \
    -DKEEL_BUILD_NEMO_COMPAT=OFF \
    -DKEEL_BUILD_SAILFISHAPP=OFF \
    -DKEEL_BUILD_QT5COMPAT=OFF \
    -DKEEL_BUILD_BOOSTER=OFF \
    -DKEEL_BUILD_PLATFORM=ON \
    -DKEEL_REQUIRE_ACCOUNTS=ON \
    -DKEEL_REQUIRE_MLITE=ON \
    -DKEEL_REQUIRE_MCE_HEADERS=ON \
    -DKEEL_REQUIRE_SAILFISH_ACCOUNTS_DEPS=ON \
    -DKEEL_REQUIRE_WEBENGINE=ON \
    -DBUILD_TESTING=OFF \
    -DKEEL_QML_INSTALL_DIR=%{_libdir}/qt6/qml
# Under sb2 (qemu) the target's qmlcachegen writes its .cpp outputs with mode
# 000 (as in shipwright-keel-silica.spec). Make them readable and resume.
for attempt in 1 2 3 4 5 6 7 8; do
    if cmake --build build-keel-platform %{?_smp_mflags}; then
        built=1
        break
    fi
    find build-keel-platform -type f -perm 000 -exec chmod 0644 {} +
done
test "${built:-0}" = 1

%install
DESTDIR=%{buildroot} cmake --install build-keel-platform/platform
install -D -m 0644 keel/platform/PROVENANCE.md %{buildroot}%{_datadir}/doc/%{name}/PROVENANCE.md
install -D -m 0644 keel/platform/README.md %{buildroot}%{_datadir}/doc/%{name}/README.md

# Read access to the access policy store for sandboxed apps (KeelPolicy).
install -D -m 0644 keel/platform/policy/sailjail/KeelPolicy.permission \
    %{buildroot}%{_sysconfdir}/sailjail/permissions/KeelPolicy.permission

%post secrets -p /sbin/ldconfig
%postun secrets -p /sbin/ldconfig
%post accounts -p /sbin/ldconfig
%postun accounts -p /sbin/ldconfig
%post policy -p /sbin/ldconfig
%postun policy -p /sbin/ldconfig

%files
%license LICENSES/MIT.txt
%{_datadir}/doc/%{name}

%files media
%dir %{_libdir}/qt6/qml/Sailfish
%{_libdir}/qt6/qml/Sailfish/Media

%files gallery
%dir %{_libdir}/qt6/qml/Sailfish
%{_libdir}/qt6/qml/Sailfish/Gallery

%files pickers
%dir %{_libdir}/qt6/qml/Sailfish
%{_libdir}/qt6/qml/Sailfish/Pickers

%files webview
%license LICENSES/MPL-2.0.txt
%dir %{_libdir}/qt6/qml/Sailfish
%{_libdir}/qt6/qml/Sailfish/WebView
%{_libdir}/qt6/qml/Sailfish/WebEngine

%files webview-qtwebengine
%dir %{_libdir}/qt6/qml/Keel
%{_libdir}/qt6/qml/Keel/WebEngine

%files secrets
%license keel/platform/secrets/upstream-licenses/sailfish-secrets.LICENSE
%dir %{_libdir}/qt6/qml/Sailfish
%{_libdir}/libsailfishsecrets-qt6.so.*
%{_libdir}/libsailfishcrypto-qt6.so.*
%{_libdir}/qt6/qml/Sailfish/Secrets
%{_libdir}/qt6/qml/Sailfish/Crypto

%files secrets-devel
%{_includedir}/sailfish-qt6
%{_libdir}/libsailfishsecrets-qt6.so
%{_libdir}/libsailfishcrypto-qt6.so
%{_libdir}/pkgconfig/sailfishsecrets-qt6.pc
%{_libdir}/pkgconfig/sailfishcrypto-qt6.pc

%files mpris
%license keel/platform/mpris/upstream-licenses/qtmpris.COPYING
%dir %{_libdir}/qt6/qml/org
%dir %{_libdir}/qt6/qml/org/nemomobile
%{_libdir}/qt6/qml/org/nemomobile/mpris

%files amber
%license keel/platform/amber-web-authorization/upstream-licenses/amber-web-authorization.LICENSE
%dir %{_libdir}/qt6/qml/Amber
%dir %{_libdir}/qt6/qml/Amber/Web
%{_libdir}/qt6/qml/Amber/Web/Authorization

%files amber-mpris
%license keel/platform/amber-mpris/upstream-licenses/amber-mpris.COPYING
%dir %{_libdir}/qt6/qml/Amber
%{_libdir}/qt6/qml/Amber/Mpris

%files thumbnailer
%license keel/platform/thumbnailer/upstream-licenses/nemo-qml-plugin-thumbnailer.LICENSE.BSD
%dir %{_libdir}/qt6/qml/Nemo
%{_libdir}/qt6/qml/Nemo/Thumbnailer

%files mce
%license keel/platform/mce/upstream-licenses/libmce-qt.LICENSE
%dir %{_libdir}/qt6/qml/Nemo
%{_libdir}/qt6/qml/Nemo/Mce

%files accounts
%license keel/platform/accounts/upstream-licenses/*
%{_libdir}/libaccounts-qt6.so.*
%dir %{_libdir}/qt6/qml/org
%dir %{_libdir}/qt6/qml/org/nemomobile
%{_libdir}/qt6/qml/org/nemomobile/accounts

%files sailfish-accounts
%license keel/platform/sailfish-accounts/upstream-licenses/sailfish-components-accounts.BSD-3-Clause.txt
%license keel/platform/signon/upstream-licenses/signond.COPYING
%license keel/platform/buteosyncfw/upstream-licenses/buteo-syncfw.COPYING
%dir %{_libdir}/qt6/qml/Sailfish
%{_libdir}/qt6/qml/Sailfish/Accounts

%files policy
%config(noreplace) %{_sysconfdir}/sailjail/permissions/KeelPolicy.permission
%dir %{_libdir}/qt6/qml/Sailfish
%{_libdir}/libsailfishpolicy-qt6.so.*
%{_libdir}/qt6/qml/Sailfish/Policy

%files policy-devel
%{_includedir}/sailfishpolicy-qt6
%{_libdir}/libsailfishpolicy-qt6.so
%{_libdir}/pkgconfig/sailfishpolicy-qt6.pc

%files accounts-devel
%{_includedir}/accounts-qt6
%{_libdir}/libaccounts-qt6.so
%{_libdir}/pkgconfig/accounts-qt6.pc

%changelog
* Mon Oct 05 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-19
- KeelPolicy Sailjail permission: sandboxed apps can read the access policy
  store, so the camera no longer reads as disabled by the device policy.

* Sat Oct 03 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-18
- Licence: MIT AND BSD-3-Clause AND LGPL-2.1-only AND LGPL-2.1-or-later AND MPL-2.0 (LICENSING.md).
- Two compiler warnings fixed (signon braces, accounts sign compare).

* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-17
- Sailfish.Gallery (-gallery): ThumbnailImage and ImageViewer.
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-16
- Sailfish.WebView and Sailfish.WebEngine: the rest of the documented API
  (security, crashed, frame scripts and messages, scroll geometry and
  chrome, desktopMode, downloads, user style sheets, isAccelerated,
  stopEmbedding and the other lifecycle members).
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-15
- Sailfish.WebView.Popups, .Pickers and .Controls (-webview): upstream
  sailfish-components-webview 1.8.0 (MPL-2.0) over Qt WebEngine, with
  remembered site permissions; Sailfish.WebEngine's DownloadHelper.
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-14
- Sailfish.Media: MprisPlayerControls over Amber.Mpris.
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-13
- Sailfish.Policy (-policy, -policy-devel): PolicyValue and AccessPolicy
  reading the MDM policy store, read only and fail-closed.
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-12
- Keel.WebEngine (-webview-qtwebengine): Sailfish.WebEngine's cookieBehavior,
  doNotTrack and colorScheme settings on Qt WebEngine.
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-11
- Sailfish.Accounts (-sailfish-accounts): sailfish-components-accounts built
  for Qt6 with libsignon-qt and libbuteosyncfw.
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-10
- Nemo.Mce (-mce): libmce-qt built for Qt6.
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-9
- Nemo.Thumbnailer (-thumbnailer): nemo-qml-plugin-thumbnailer built for
  Qt6.
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-8
- Amber.Mpris (-amber-mpris): amber-mpris built for Qt6; conflicts with
  Chum's amber-qml-plugin-mpris-qt6.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-7
- Amber.Web.Authorization (-amber): amber-web-authorization built for Qt6.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-6
- org.nemomobile.mpris (-mpris): qtmpris built for Qt6.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-5
- Sailfish.WebView and Sailfish.WebEngine (-webview) on Qt WebEngine, with
  an open-in-browser fallback.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-4
- libaccounts-qt6 and org.nemomobile.accounts (-accounts, -accounts-devel).
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-3
- Sailfish.Pickers (-pickers): picker pages and dialogs over Tracker 3 or
  a file system scan.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-2
- Sailfish.Secrets / Sailfish.Crypto: sailfish-secrets client libraries and
  QML plugins built for Qt6 (-secrets, -secrets-devel).
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-1
- Sailfish.Media: MediaKey (Lipstick GRABBED_KEYS), MediaPlayerControls,
  MetadataReader, MediaListItem, MediaPlayerControlsPanel,
  MediaPlayerPanelBackground.
