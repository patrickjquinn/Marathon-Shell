# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Keel's Sailfish.Silica module for Qt6 (plus the `Keel` extension module).
#
# The CXX-Qt native part (keel/silica/plugin) is Rust 1.85+, newer than the
# SDK's Rust (1.75), so it is cross-compiled first (house rule: no cargo in
# specs) and passed in:
#
#   keel/rpm/build-native.sh /home/mersdk/<you>/native
#   mb2 -t SailfishOS-5.2.0.15-aarch64 -s keel/rpm/shipwright-keel-silica.spec \
#       build -- --define "keel_native_dir /home/mersdk/<you>/native"
#
# Under mb2 the build runs in the checkout (the repository root).

%{!?keel_native_dir: %global keel_native_dir %{_builddir}/keel-native}

Name:       shipwright-keel-silica
Version:    0.1.0
Release:    26
Summary:    Sailfish.Silica compatibility module for Qt6 apps (Keel)
# Clean-room QML and C++ are Shipwright's; most QML files are Silica's own
# BSD-3-Clause QML (Jolla Ltd), ported to Qt 6: keel/silica/PROVENANCE.md
# lists every file and its origin.
License:    MIT AND BSD-3-Clause
URL:        https://github.com/shipwright/shipwright
Source0:    %{name}-%{version}.tar.bz2

# Chum's Qt6 (6.8.4 in chum:testing for Sailfish OS 5.2).
BuildRequires:  cmake >= 3.19
BuildRequires:  ninja
BuildRequires:  gcc-c++
BuildRequires:  qt6-qtbase-devel >= 6.8
BuildRequires:  qt6-qtdeclarative-devel >= 6.8
# Direct mode tags the cover window CATEGORY=cover through Qt's platform
# native interface (qpa/qplatformnativeinterface.h).
BuildRequires:  qt6-qtbase-private-devel >= 6.8
# dconf through libdconf (keel/silica/plugin/cpp/keeldconf.h): Sailjail's
# private-bin leaves sandboxed apps no dconf program.
BuildRequires:  pkgconfig(dconf)
Requires:       qt6-qtbase >= 6.8
Requires:       qt6-qtbase-gui >= 6.8
Requires:       qt6-qtdeclarative >= 6.8
# Direct mode (ADR-0016): the app's windows are Lipstick windows through Qt 6's
# Wayland client with the wl-shell integration; the ambience and the
# display's cutouts are read through libdconf (in dconf). keel-shell is the
# opt-in fallback.
Requires:       qt6-qtwayland
Requires:       dconf
# Nemo.Configuration, which Silica's FirstTimeUseCounter.qml imports
# (RemorsePopup and RemorseItem use it): without it no page with a remorse
# can be created.
Requires:       shipwright-keel-nemo-compat-configuration
Suggests:       shipwright-keel-shell
# SilicaWebView shows web content through Sailfish.WebView, made at run time.
Suggests:       shipwright-keel-platform-webview

%description
Keel's implementation of the Sailfish.Silica 1.0 QML API for Qt6 apps:
pages and page stack, dialogs, pulley menus, list items, text fields and
other controls, Theme (ambience colours from dconf), covers (rendered
in a second window that Lipstick shows as the app's cover) and the Keel 1.0
extension module, plus Sailfish.Share 1.0 (ShareAction opens the system
share dialog, or copies to the clipboard without it; ShareProvider receives
shares). Installed into Qt6's QML import path; the system Qt5
Silica is not touched.

%package -n shipwright-keel-actions
Summary:    Keel Actions: typed app actions for Pilot and MCP clients
License:    MIT
Requires:   qt6-qtbase >= 6.8
Requires:   qt6-qtdeclarative >= 6.8
# Owns the Keel QML directory this module sits in.
Requires:   %{name} = %{version}-%{release}

%description -n shipwright-keel-actions
The Keel.Actions 1.0 QML module (ADR-0018): KeelAction, KeelParam,
KeelResult, KeelEntity, KeelContext and KeelShortcut, with the runtime
that validates calls against the app's generated actions.json and serves
them on D-Bus (org.shipwright.Keel.Actions), so that keel-mcp can offer
the app's actions, entities, context and shortcuts to MCP clients.

%prep
%setup -q -n %{name}-%{version}

%build
%cmake -S keel -B build-keel-silica -G Ninja --no-warn-unused-cli \
    -DCMAKE_BUILD_TYPE=Release \
    -DKEEL_BUILD_NEMO_COMPAT=OFF \
    -DKEEL_BUILD_SAILFISHAPP=OFF \
    -DKEEL_BUILD_QT5COMPAT=OFF \
    -DKEEL_BUILD_PLATFORM=OFF \
    -DBUILD_TESTING=OFF \
    -DKEEL_REQUIRE_LIBDCONF=ON \
    -DKEEL_RUST_PREBUILT_DIR=%{keel_native_dir} \
    -DKEEL_QML_INSTALL_DIR=%{_libdir}/qt6/qml
# Under sb2 (qemu) the target's qmlcachegen writes its .cpp outputs with mode
# 000 (QSaveFile cannot read back the permissions: sb2 logs "Path not found
# for FD" on statx). Make them readable and resume the build.
for attempt in 1 2 3 4 5 6 7 8; do
    if cmake --build build-keel-silica %{?_smp_mflags}; then
        built=1
        break
    fi
    find build-keel-silica -type f -perm 000 -exec chmod 0644 {} +
done
test "${built:-0}" = 1

%install
DESTDIR=%{buildroot} cmake --install build-keel-silica
install -D -m 0644 keel/silica/PROVENANCE.md %{buildroot}%{_datadir}/doc/%{name}/PROVENANCE.md
install -D -m 0644 keel/silica/COMPATIBILITY.md %{buildroot}%{_datadir}/doc/%{name}/COMPATIBILITY.md

%post
# A running booster keeps the old Keel in memory: restart the per-app ones
# (the shared one hosts Reef, which may be doing this update).
systemctl-user try-restart 'booster-keel@*.service' >/dev/null 2>&1 || :

%files
%{_libdir}/qt6/qml/Sailfish/Silica
%{_libdir}/qt6/qml/Sailfish/Share
%{_libdir}/qt6/qml/Keel
%exclude %{_libdir}/qt6/qml/Keel/Actions
%dir %{_libdir}/qt6/qml/Sailfish
%license LICENSES/BSD-3-Clause.txt LICENSES/MIT.txt
%{_datadir}/doc/%{name}

%files -n shipwright-keel-actions
%{_libdir}/qt6/qml/Keel/Actions
%license LICENSES/MIT.txt

%changelog
* Sat Oct 10 2026 Shipwright - 0.1.0-26
- PagedView shows a page that was made later than asked for. In a page that loads in the background, its pages were made in the background too, and the view never showed them: Shoal Camera's roll, opened before a photo was taken, stayed black.
- No more "load glyph failed ... glyph=65535" warnings in every app's log. Sailfish's UI font keeps its ligatures in Apple's format, and Qt warned about a placeholder glyph while laying out text such as "left"; nothing was drawn wrongly.

* Fri Oct 09 2026 Shipwright - 0.1.0-25
- Requires Keel's Nemo.Configuration. Silica's remorse popups and items need it, and without it a page that has one could not be opened: on a phone that had nothing else of Keel's installed, tapping an app in Reef did nothing.
- A page that cannot be created says why in the app's log, as Qt's Loader does.
- An update restarts the running app boosters, so apps start with the new Keel.

* Fri Oct 09 2026 Shipwright - 0.1.0-24
- SilicaText (the base of Label) is native code: each label is one object instead of a QML component with its own bindings.
- A palette no longer re-evaluates every colour binding of its item when it completes, and reads the ambience's colours from one shared cache instead of parsing them for each item.
- A page pushed again reuses its compiled component instead of looking it up through the type loader.
- SilicaItem, SilicaControl, SilicaMouseArea and SilicaRectangle are native code as well.
- About 200 more of Silica's QML functions are compiled ahead of time (65%, from 60%): names qualified with their object's id and functions typed, in the page stack, text fields, pulley menus, headers and list items.
- A typical page is created in 12.8 ms, from 14.7; a button in 0.72 ms, from 0.95. Pushing a typical page through the page stack takes about 10 ms, as with Silica's own (about 9.5 ms).

* Fri Oct 09 2026 Shipwright - 0.1.0-23
- Theme is native code (module Keel.SilicaCore, which Sailfish.Silica re-exports): its colour helpers no longer run as JavaScript, and about 220 more of Silica's QML functions are compiled ahead of time (60%, from 54%). A typical page is created in 14.7 ms, from 19.9.
- Pulley menus, text fields, highlight bars and tab bars create their optional parts (haptics, settings) from one compiled component each, instead of compiling a new one per item: a page with a pulley menu is created about 12 ms faster.
- A list view without a highlight no longer runs a highlight-resize animation on every move.

* Thu Oct 08 2026 Shipwright - 0.1.0-22
- Deleting the page on show in a PagedView no longer crashes the app (the camera's roll).

* Thu Oct 08 2026 Shipwright - 0.1.0-21
- A list's quick-scroll handle finishes loading before it is removed, so it no longer crashes.

* Wed Oct 07 2026 Shipwright - 0.1.0-20
- A page let go of mid-swipe carries on from where the finger left it.
  Qt 6's Binding puts the old value back when it turns off (Qt 5's did
  not), so the page jumped back to its start on release and then slid out
  again from there: a double slide on every back swipe, and no snap-back
  after a short one. The page stack's drag bindings keep the value.

* Tue Oct 06 2026 Shipwright - 0.1.0-19
- Theme values for touch handling are read from a Theme object found once
  per engine. The page stack's gesture area and DragFilter looked Theme up
  on every touch move, and qmlTypeId() built a temporary QML engine each
  time: a third of a scrolling app's main thread.

* Mon Oct 05 2026 Shipwright - 0.1.0-16
- PageStack logs why touch is blocked (keel.silica.touchblocker, off by
  default).

* Mon Oct 05 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-15
- Theme: Silica's own sizes at pixelRatio 1.5 (the z1.5 theme), measured
  on the Jolla Phone: paddings 10/20/40, _lineWidth 4, itemSizeExtraSmall
  106, itemSizeLarge 166, itemSizeExtraLarge 202, iconSizeLauncher 128,
  fontSizeExtraLarge 76, the button widths and maximumFlickVelocity, where
  the scaled 1.0 values drew controls thinner and closer together than
  Sailfish's own apps; lightSecondaryColor is Silica's opaque #bababa.
- PagedView: a drag that starts at the end of a NoWrap view moves the
  enclosing PagedView along the same axis instead (the Jolla Camera's camera
  roll inside its switcher: swiping back from the newest photo returns to
  the viewfinder again).

* Mon Oct 05 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-14
- dconf is read through libdconf, not the dconf program, which Sailjail's
  private-bin removes from a sandboxed app: sandboxed Keel apps had no
  ambience, so no theme pixel ratio and no theme icons. The program stays
  as the fallback on hosts without the library, and a `dconf watch` child
  now dies with its app instead of being left running.
- Screen: topCutout, hasCutouts and the four rounded corners from the
  adaptation's dconf (/desktop/sailfish/silica/cutouts and
  rounded_corners), so pages and headers clear a notch as on Silica.
- The theme icon provider starts at the phone's pixel ratio, so the first
  icons are not looked up in another ratio's directory.
- RemorsePopup and RemorseItem use MouseArea's canceled() instead of
  redeclaring it (an invalid override in Qt 6).

* Mon Oct 05 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-13
- Shaders compiled for GLSL ES 100 only, as Qt's own: the phone's GL
  driver refused to link Keel's ES 300 fragment shaders with Qt's ES 100
  vertex shader, so the pulley menu (and every other shader effect) drew
  nothing.
- Page stack swipe navigation by touch: the gesture takes the touch point
  over; before, a finger drag left the stack half moved and stuck.

* Mon Oct 05 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-12
- Direct mode: app windows carry what Lipstick reads from a Silica window
  (WINID, BACKGROUND_VISIBLE, SAILFISH_HAVE_COVER, SAILFISH_COVER_WINDOW),
  so Lipstick draws the ambience behind the app and uses its cover; the
  cover says whether it is transparent.
- Theme icons from the theme's z<pixel ratio> directories and from
  icons-monochrome (icon-m-search, busy indicators).

* Sat Oct 03 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-11
- Theme.highlightDimmerColor matches Silica: the highlight's hue saturated
  at a fifth of full value (#80d9ff gives #002333, as measured on a phone).

* Sat Oct 03 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-10
- Licence: MIT AND BSD-3-Clause (LICENSING.md).

* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-9
- ApplicationWindow: the app's own children share the page stack's item
  (a negative z is under the pages, as in Silica).
- PagedView takes an ObjectModel; attached properties are current when
  currentItem changes.
- ContextMenu on the software scene graph shades the window around its
  item instead of dimming the menu too.
- Theme icons: colour scheme variants (-dark/-light), substitutes for
  icons a theme lacks, monochrome icons in the primary colour in a light
  ambience (HighlightImage, IconTextSwitch).
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-8
- PagedView, the Palette type and SilicaWebView (on Sailfish.WebView).
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-7
- New subpackage shipwright-keel-actions: Keel.Actions 1.0 (ADR-0018).
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-6
- Notice and the Notices singleton (in-app notices with Silica's NoticeItem).
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-5
- Sailfish.Share: ShareAction opens the system share dialog
  (org.sailfishos.share); ShareProvider and ShareResource for share targets.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-4
- Direct mode (ADR-0016): covers tagged CATEGORY=cover, orientation,
  activation, cover status and close from Lipstick itself, ambience from
  dconf; keel-shell becomes an opt-in fallback.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-3
- Rebuilt on Silica's own BSD QML from sailfishsilica-qt5 1.2.156 (133
  ports) with clean-room native types; Qt 6 shaders; licences marked
  %%license.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-2
- Corpus gaps: Format/Formatter, InfoLabel, SlideshowView, ProgressCircle,
  DockedPanel, Drawer, TimePicker, enum holders, ListItem and text field
  properties, app-relative icon URLs; Sailfish.Share 1.0 ShareAction.
* Wed Sep 30 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-1
- Keel v0.1: Sailfish.Silica 1.0 for Qt6 with keel-shell covers and ambience.
