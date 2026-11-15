# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Shipwright.Pacific.WebView 1.0: Pacific's Qt 6 web view (QML module) on
# WPE WebKit, and the pacific-minibrowser test app.
#
# Builds against the engine: shipwright-pacific-engine-devel when it is
# installed (/opt/pacific/lib/pkgconfig), otherwise the prefix rpm/prebuild.sh
# makes from the engine RPMs in target/pacific-sdk. By hand, from the
# repository root:
#     shoal/pacific/webview/rpm/prebuild.sh
#     tools/build/native/native.sh shoal/pacific/webview/rpm/shipwright-pacific-webview.spec

%global srcroot shoal/pacific/webview
%{!?pacific_sdk: %global pacific_sdk %{shipwright_src}/target/pacific-sdk}
%global debug_package %{nil}
# The engine's libraries are private to shipwright-pacific-engine (no
# soname provides); depend on the package instead.
%global __requires_exclude ^lib(WPEWebKit-2\\.0|wpe-1\\.0|WPEBackend-fdo-1\\.0)\\.so.*$

Name:           shipwright-pacific-webview
Version:        0.1.0
Release:        30
Summary:        Pacific's Qt 6 web view (Shipwright.Pacific.WebView) on WPE WebKit
# The view derives from Igalia's WPE Qt API and Atlantic's qt5-plugin
# (LGPL-2.1-or-later); the page bridges from Atlantic's browser (MPL-2.0).
License:        LGPL-2.1-or-later AND MPL-2.0
URL:            https://github.com/patrickjquinn/shipwright-open

BuildRequires:  cmake >= 3.21
BuildRequires:  ninja
BuildRequires:  gcc-c++
BuildRequires:  pkgconfig
BuildRequires:  cpio
BuildRequires:  qt6-qtbase-devel >= 6.8
BuildRequires:  qt6-qtbase-private-devel >= 6.8
BuildRequires:  qt6-qtdeclarative-devel >= 6.8
BuildRequires:  qt6-qtpositioning-devel >= 6.8
BuildRequires:  qt6-qtsensors-devel >= 6.8
BuildRequires:  pkgconfig(glib-2.0)
BuildRequires:  pkgconfig(libsoup-3.0)
BuildRequires:  pkgconfig(xkbcommon)
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(glesv2)
BuildRequires:  pkgconfig(wayland-server)
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-egl)
# Either build of the engine (ARMv8.2 or ARMv8.0).
Requires:       shipwright-pacific-engine-abi >= 2.54.0
# Only Pacific uses it (nothing else requires the engine or the web view;
# the -devel and -examples subpackages are for development), and it is large
# (the engine and dictionaries are about 150 MB, with the boost socket
# enabled): it must not outlive Pacific. Pacific requires it and it requires
# Pacific, so removing either by any route (Reef, pkcon, rpm, the app grid)
# removes both.
Requires:       shipwright-pacific
Requires:       qt6-qtbase-gui >= 6.8
Requires:       qt6-qtdeclarative >= 6.8
Requires:       qt6-qtpositioning >= 6.8
Requires:       qt6-qtsensors >= 6.8

%description
The QML module Shipwright.Pacific.WebView 1.0 (WebView, WebProfile,
WebEngine and the request types): WPE WebKit pages in Qt 6 Quick through
WPEBackend-fdo's exported EGL images, with the input method, touch,
downloads, permissions, private sessions, tab discarding and Pilot's page
access. Apps run with /usr/libexec/pacific/pacific-env.sh's environment and
Qt Quick on OpenGL.

%package examples
Summary:        pacific-minibrowser, a test app for Pacific's web view
Requires:       %{name} = %{version}-%{release}

%description examples
A small browser window for testing the engine and the view on the phone:
pacific-minibrowser [--silica] [--headless --snapshot] [--screenshot file] [url].
Run it under /usr/libexec/pacific/pacific-env.sh.

%prep

%build
if [ -d %{pacific_sdk}/pkgconfig ]; then
    export PKG_CONFIG_PATH=%{pacific_sdk}/pkgconfig
else
    export PKG_CONFIG_PATH=/opt/pacific/lib/pkgconfig
fi
cmake -S %{srcroot} -B target/pacific-webview-build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=%{_prefix} \
    -DCMAKE_INSTALL_LIBDIR=%{_lib} \
    -DPACIFIC_ENGINE_LIBDIR=/opt/pacific/lib
cmake --build target/pacific-webview-build -j4

%install
DESTDIR=%{buildroot} cmake --install target/pacific-webview-build
install -D -m 0644 %{srcroot}/README.md %{buildroot}%{_docdir}/%{name}/README.md
install -d %{buildroot}%{_datadir}/licenses/%{name}
install -m 0644 LICENSES/LGPL-2.1-or-later.txt LICENSES/MPL-2.0.txt %{buildroot}%{_datadir}/licenses/%{name}/

%files
%{_libdir}/qt6/qml/Shipwright/Pacific/WebView
%{_libdir}/shipwright-pacific-webview
%{_docdir}/%{name}
%{_datadir}/licenses/%{name}

%files examples
%{_bindir}/pacific-minibrowser

%changelog
* Mon Oct 26 2026 Shipwright - 0.1.0-30
- Links to apps work as in Chrome on Android: a tapped tel:, mailto: or sms: link goes to the phone's app for it, an intent: link to its web page when it has one, and a page that sends itself to an app's link on its own stays where it is. WebKit replaced the page with "The URL can't be shown" (AliExpress's home page did it on every visit).
* Sun Oct 25 2026 Shipwright - 0.1.0-29
- Swipe back and forward: dragging a page sideways where it cannot scroll any further goes back or forward, for the browser to show (swipeNavMoved), with a picture of each page as it was left (captureHistoryPicture).
- A link no longer stays highlighted after a flick that started on it: hover is only passed on from a mouse or touchpad.
* Mon Oct 19 2026 Shipwright - 0.1.0-28
- Private browsing's content filters are kept between runs. The sandbox kept them in memory only, so every start compiled all the filter lists again (24 s of two cores on an Xperia 10 II).
* Sun Oct 18 2026 Shipwright - 0.1.0-27
- Works with either build of Pacific's web engine.
* Wed Oct 14 2026 Shipwright - 0.1.0-26
- Pages show at screen scales that do not divide the screen width evenly (1.75 at 270 DPI): the view waited for a frame exactly as wide as itself, which WebKit draws a pixel narrower there, and stayed blank. Reported by Marathon OS.
- Checksum checks work with BusyBox's sha256sum as well as coreutils'.

* Mon Oct 12 2026 Shipwright - 0.1.0-25
- Requires Pacific (which requires it): removing Pacific from the app grid or with pkcon removes the web view too.

* Mon Oct 12 2026 Shipwright - 0.1.0-24
- Catching a scrolling page with your finger never selects text or opens a menu, however long you hold it.
- During a page change the page being left stays on screen until the next one has drawn, instead of garbled frames of the old page.
- Site data can be kept where the app's sandbox keeps it (PACIFIC_WEB_DATA, PACIFIC_WEB_CACHE).
* Sat Oct 10 2026 Shipwright - 0.1.0-23
- Scrolling with the toolbar showing does less work per frame: each of WebKit's frame buffers keeps its texture instead of being imported again for every new frame, and the page is drawn opaque instead of blended over the window.
- Touching a link to another site starts resolving its address before the tap completes.
- Pull to refresh: the view reports a one-finger pull on a page that was at its top when the finger landed (the page's word, from its own script world), unless the page opts out with overscroll-behavior or takes the drag itself.
- PACIFIC_TRACE_LOAD prints each navigation's commit, first frame and finish times.

* Sat Oct 10 2026 Shipwright - 0.1.0-22
- Downloads work: a destination the app chose (and claimed as an empty file) is written instead of refused as an existing file.
- PACIFIC_DEBUG_FPS also counts the frames dropped unseen.

* Wed Oct 07 2026 Shipwright - 0.1.0-21
- Pinch to zoom follows the fingers: the scaled page moves with their
  midpoint, held to the document's edges as WebKit holds it, and the
  final scale is anchored so the page settles where the pinch left it.
  When the fingers lift, the frame on screen is copied and shown, scaled,
  until the frame at the new scale is the one drawn: the page no longer
  zooms out and back in on release. (WebKit reports the new scale as
  soon as it is asked for, so frames of the old one were taken for it.)
- pulledDown(): one finger dragged down on the page, scrolled or not.
- zooming: a pinch is scaling the page or its result is on its way.

* Wed Oct 07 2026 Shipwright - 0.1.0-20
- addUserScript() returns a handle for the new removeUserScript() and
  takes sites the script stays out of (skipHosts).

* Wed Oct 07 2026 Shipwright - 0.1.0-19
- A drag becomes a scroll after 8 dp, Android's touch slop, set from the
  screen's density for the engine (PACIFIC_TOUCH_SLOP_PX): the page starts
  moving about 18 ms sooner and no longer jumps by WebKit's 40 px.
- Pacific introduces itself as Chrome on Android (desktop mode: what
  Chrome on Android sends for desktop sites). With its own Sailfish user
  agent Facebook showed an unsupported-browser page and Yahoo its desktop
  site; as Safari on an iPhone, sites offered App Store apps.
- obscuredBottom: what the UI's own controls cover at the bottom of the
  page, for the engine (wpe_sfos_set_obscured_content_insets): fixed
  elements stay above them and the page's end scrolls clear of them.
- findMatchCount is the total from counted-matches alone: a search's
  found-text said G_MAXUINT and a step to the next match said 1, and
  both overwrote it.
- clang-tidy clean.

* Tue Oct 06 2026 Shipwright - 0.1.0-18
- Direct composition hands WebKit's own buffers to Lipstick on libhybris
  instead of copying each frame into the subsurface with GL. Flinging
  OSNews, the GPU was 9-13% busy instead of 49-52% and the UI process used
  a third less CPU. PACIFIC_DIRECT_ATTACH=0 keeps the copy.

* Tue Oct 06 2026 Shipwright - 0.1.0-17
- Asks pacific-boostd (the engine) for CPU and GPU clock floors while a
  page is touched or scrolls. PACIFIC_BOOST=0 turns it off.

* Tue Oct 06 2026 Shipwright - 0.1.0-16
- PACIFIC_DEBUG_FRAMES logs each web frame and each frame the compositor
  used, with CLOCK_MONOTONIC times.

* Tue Oct 06 2026 Shipwright - 0.1.0-15
- Tab thumbnails are scaled and saved on a pool thread, not the GUI
  thread (a tenth of it at start).
- Spelling dictionaries load when a text field first has focus, not with
  the first page.

* Tue Oct 06 2026 Shipwright - 0.1.0-14
- Direct composition presents a frame when the compositor has used the
  last one: 68-78 frames a second reach the screen while flinging, against
  45-59 when every frame was presented as it arrived.
- Qt's path targets its texture only for a new web frame, and direct
  composition keeps a texture per WebKit buffer.
- PACIFIC_DEBUG_FPS counts the frames the compositor used.

* Tue Oct 06 2026 Shipwright - 0.1.0-13
- Pinch to zoom previews in the scene graph, at the panel's rate, and
  WebKit renders the final scale once when the fingers lift.
- safeAreaTop: env(safe-area-inset-top) for pages with viewport-fit=cover
  (needs the engine's wpe_sfos_set_safe_area_insets).
- WebKit gets the size Qt renders at, once per frame: the window's
  provisional size at start no longer costs a layout, and a web frame at
  another width is never shown (it was a white band across the top).

* Mon Oct 05 2026 Shipwright - 0.1.0-9
- PACIFIC_DEBUG_FPS logs web frames per second and the longest gap.

* Mon Oct 05 2026 Shipwright - 0.1.0-8
- Settings set before the view exists are applied when it is created
  (restored tabs lost their JavaScript and autoplay settings).

* Mon Oct 05 2026 Shipwright - 0.1.0-7
- Pages are laid out at the width their meta viewport asks for (980 CSS px
  without one) and scaled to fit, as in phone browsers; WPE ignores it.

* Mon Oct 05 2026 Shipwright - 0.1.0-6
- Page console capture only while captureConsole is on (8703a8f).

* Mon Oct 05 2026 Shipwright - 0.1.0-5
- Page visibility follows the view on screen (item, window exposure, app
  state) by itself; frames are kept while hidden, so tabs created behind
  others draw when shown; input coordinates in device pixels; content
  filters can be disabled and enabled without deleting them.

* Mon Oct 05 2026 Shipwright - 0.1.0-4
- Software-rendered (wl_shm) web frames: copied and shown instead of
  crashing the app; the CPU fallback works.

* Sun Oct 04 2026 Shipwright - 0.1.0-3
- Finnish spell checking (Voikko). WebView.blockedRequestCount and
  blockedRequest(url) from a WebProcess extension that sees content-filter
  blocks; WebProfile.globalPrivacyControl (Sec-GPC: 1), on by default.

* Sun Oct 04 2026 Shipwright - 0.1.0-2
- Spell checking on by default in the phone's language: WebEngine and
  WebProfile spellChecking/spellCheckingLanguages, suggestions in
  contextMenuRequested, applySpellingSuggestion, learnSpelling.

* Sun Oct 04 2026 Shipwright - 0.1.0-1
- First package.
