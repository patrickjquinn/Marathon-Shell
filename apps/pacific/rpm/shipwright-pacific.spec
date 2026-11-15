# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary
#
# Pacific: the web browser. Rust core (shoal/pacific/core) and CXX-Qt front
# end (shoal/pacific/app) on Keel, pages rendered by WPE WebKit through
# Shipwright.Pacific.WebView (shipwright-pacific-webview, which brings
# shipwright-pacific-engine).
#
# SDK convention (tools/build/sdk/README.md): no cargo in the spec.
# shoal/pacific/rpm/prebuild.sh builds the app (a shared library that is
# also executable, tools/keel-launcher/link_sailfishapp.rs) into
# target/<triple>/release/ and fetches the bundled data (autoconsent, Brave's
# scriptlet resources, the default filter lists) into shoal/pacific/rpm/data,
# checked against the pins in shoal/pacific/core/data/versions.env. By hand,
# from the repository root:
#     shoal/pacific/rpm/prebuild.sh
#     mb2 -t SailfishOS-5.2.0.15-aarch64 --snapshot=pacific \
#         -s shoal/pacific/rpm/shipwright-pacific.spec build
# or with tools/build/native/native.sh shoal/pacific/rpm/shipwright-pacific.spec.

%global app shipwright-pacific
%global srcroot shoal/pacific
%{!?_userunitdir:%global _userunitdir %{_prefix}/lib/systemd/user}
%{!?pacific_bin: %global pacific_bin target/%{_arch}-unknown-linux-gnu/release/libshipwright_pacific.so}
%{!?keel_actions_dir: %global keel_actions_dir %(dirname %{pacific_bin})/keel-actions/org.shipwright.pacific}
%global debug_package %{nil}
# The Qt Declarative release the build compiles the QML with (see Requires).
%global qt6_qml_version %(rpm -q --qf '%%{VERSION}' qt6-qtdeclarative 2>/dev/null | grep -E '^[0-9.]+$' || echo 6.8)
%global _build_id_links none

Name:           shipwright-pacific
Version:        0.1.0
Release:        27
Summary:        A fast, private web browser
License:        LicenseRef-Shipwright-Proprietary AND MPL-2.0
URL:            https://reefstore.app/#app-shipwright-pacific

# The web view module and, through it, the engine (WPE WebKit in
# /opt/pacific, /usr/libexec/pacific/pacific-env.sh, the PacificWebEngine
# Sailjail permission).
Requires:       shipwright-pacific-webview >= 0.1.0-29
# Either build of the engine (engine/rpm/shipwright-pacific-engine.spec):
# shipwright-pacific-engine for ARMv8.2 phones, -armv80 for the Xperia
# 10 II. Each refuses to install on a processor it does not run on; Reef
# installs the right one (catalogue requires_cpu).
Requires:       shipwright-pacific-engine-abi >= 2.54.0-746.1.pacific17
# Keel (Sailfish.Silica for Qt 6), its window library and Keel Actions.
Requires:       shipwright-keel-silica >= 0.1.0-29
Requires:       shipwright-keel-sailfishapp
Requires:       shipwright-keel-actions >= 0.1.0-33
# The UI's QML is compiled into the binary and installed empty (%%install):
# the engine takes a compiled file only from the Qt Declarative release that
# compiled it (down to the patch release), and would read the empty file
# under any other.
Requires:       qt6-qtdeclarative = %{qt6_qml_version}
# rustls-platform-verifier reads the system CA bundle (filter-list updates,
# search suggestions).
Requires:       ca-certificates
# Logins come from Shoal Keys when it is installed (autofill).
Suggests:       shipwright-shoal-keys

BuildRequires:  desktop-file-utils

%description
A web browser for Sailfish OS on WPE WebKit: a bottom toolbar within thumb
reach with swipes between tabs, a tab grid, private tabs, built-in ad and
tracker blocking, cookie banners rejected for you, HTTPS first, reader
mode, a learned address bar, session restore, per-site settings, logins
from Shoal Keys and Keel Actions for Pilot. Free, with no telemetry.

%prep

%build

%install
# The app, run by the launcher script under the engine's environment.
# The binary itself: Sailjail starts only ELF programs. It re-execs itself
# through the engine's pacific-env for the runtime environment.
install -D -m 0755 %{pacific_bin} %{buildroot}%{_bindir}/%{app}
install -d %{buildroot}%{_datadir}/%{app}
cp -r %{srcroot}/ui/qml %{buildroot}%{_datadir}/%{app}/qml
# Compiled into the binary (app/build.rs, precompile_app_qml), whose units
# the engine takes by these files' paths without reading them: they are
# installed empty, kept for the directory imports that list them.
find %{buildroot}%{_datadir}/%{app}/qml -type f \( -name '*.qml' -o -name '*.js' -o -name '*.mjs' \) \
    -exec truncate -s 0 {} +
install -D -m 0644 %{srcroot}/app/packaging/%{app}.desktop \
    %{buildroot}%{_datadir}/applications/%{app}.desktop
desktop-file-validate %{buildroot}%{_datadir}/applications/%{app}.desktop
# openUrl for other apps and Lipstick (src/dbus.rs).
install -D -m 0644 %{srcroot}/app/packaging/org.shipwright.pacific.ui.service \
    %{buildroot}%{_datadir}/dbus-1/services/org.shipwright.pacific.ui.service
# Started ahead of use with the session (shipwright-pacific-prestart.service).
install -D -m 0644 %{srcroot}/app/packaging/%{app}-prestart.service \
    %{buildroot}%{_userunitdir}/%{app}-prestart.service
mkdir -p %{buildroot}%{_userunitdir}/post-user-session.target.wants
ln -s ../%{app}-prestart.service %{buildroot}%{_userunitdir}/post-user-session.target.wants/%{app}-prestart.service
# Bundled data (prebuild.sh): blocking works offline from the first start.
for d in autoconsent adblock filter-lists; do
    if [ -d %{srcroot}/rpm/data/$d ]; then
        install -d %{buildroot}%{_datadir}/%{app}/$d
        install -m 0644 %{srcroot}/rpm/data/$d/* %{buildroot}%{_datadir}/%{app}/$d/
    fi
done
# Launcher icons, shared style: icons/render.sh at the repository root.
for s in 86 108 128 172; do
    install -D -m 0644 icons/hicolor/${s}x${s}/apps/%{app}.png \
        %{buildroot}%{_datadir}/icons/hicolor/${s}x${s}/apps/%{app}.png
done
# Keel Actions (ADR-0018): written by build.rs next to the binary.
install -D -m 0644 %{keel_actions_dir}/actions.json %{buildroot}%{_datadir}/keel/actions/org.shipwright.pacific.json
install -D -m 0644 %{keel_actions_dir}/org.shipwright.pacific.service %{buildroot}%{_datadir}/dbus-1/services/org.shipwright.pacific.service
install -D -m 0644 %{keel_actions_dir}/org.shipwright.pacific.actions.xml %{buildroot}%{_datadir}/dbus-1/interfaces/org.shipwright.pacific.actions.xml

%post
systemctl-user daemon-reload || :
# Started ahead of use (its unit waits for Pacific's first run). Not
# restarted on an update: Pacific may be open; a waiting one sees its
# program replaced and makes way within a minute (Browser.waiting).
if [ "$1" -eq 1 ]; then
    systemctl-user start %{app}-prestart.service || :
fi

%preun
if [ "$1" -eq 0 ]; then
    systemctl-user stop %{app}-prestart.service || :
fi

%postun
systemctl-user daemon-reload || :

%files
%license LICENSES/LicenseRef-Shipwright-Proprietary.txt
%license LICENSES/MPL-2.0.txt
%{_bindir}/%{app}
%{_datadir}/%{app}
%{_datadir}/icons/hicolor/*/apps/%{app}.png
%{_datadir}/applications/%{app}.desktop
%{_datadir}/dbus-1/services/org.shipwright.pacific.ui.service
%{_userunitdir}/%{app}-prestart.service
%{_userunitdir}/post-user-session.target.wants/%{app}-prestart.service
%{_datadir}/keel/actions/org.shipwright.pacific.json
%{_datadir}/dbus-1/services/org.shipwright.pacific.service
%{_datadir}/dbus-1/interfaces/org.shipwright.pacific.actions.xml

%changelog
* Sun Oct 25 2026 Shipwright - 0.1.0-27
- Swipe back and forward: drag a page sideways and the page before it (or after it) comes into view as you drag, as it was when you left it.
- Opening Pacific is instant: it is kept ready in the background, as the Sailfish Browser is, once you have used it.
- The address field rises out of the toolbar over the page, which stays in view behind frosted glass, instead of replacing the screen.
- The tab overview opens with the page shrinking into it, and the page grows back when you pick a tab.
- The tab count turns and pops when a tab opens or closes, so a tab opened behind the page is seen to arrive.
- The toolbar comes back when you reach the end of a page.
* Mon Oct 19 2026 Shipwright - 0.1.0-26
- Smoother scrolling on slower phones: Pacific no longer redraws its whole window for every movement of the finger.
- Pacific starts faster and its package is smaller: its interface is compiled ahead of time, much of it to native code, instead of when it first starts.
* Mon Oct 19 2026 Shipwright - 0.1.0-25
- Pacific starts faster and scrolls without its first-use pauses: its compiled interface, graphics pipelines and shaders are kept between runs. The sandbox kept them in memory only, so every start built them again.
* Sun Oct 18 2026 Shipwright - 0.1.0-24
- Pacific works with either build of its web engine; the engine package now checks the processor instead of Pacific.
* Fri Oct 16 2026 Shipwright - 0.1.0-23
- Pilot (and other Keel Actions clients) can bring Pacific to the front, starting it if it is not running, and open its bookmarks, history, downloads, tabs or settings.
* Thu Oct 15 2026 Shipwright - 0.1.0-22
- Opening Pacific while it is already running (Open in Reef, the app grid) brings it to the front. It stayed in the background: the system hands an open of a running app to its openUrl with no address, which did nothing.

* Wed Oct 14 2026 Shipwright - 0.1.0-21
- Pages keep their scroll position when you open another page and come back: parts of a page that sized themselves by whether they were visible collapsed while the page was hidden underneath.

* Tue Oct 13 2026 Shipwright - 0.1.0-20
- At large text sizes, list rows take the room their lines need instead of running into the next row.
- The number of things blocked on a page is a badge at the lock's corner, bold and in the highlight colour, so it reads as a count rather than a stray mark or a footnote to the site's name.

* Mon Oct 12 2026 Shipwright - 0.1.0-19
- Wikipedia searches go to the edition in the phone's language.
- History times and download sizes are written in the phone's language.

* Mon Oct 12 2026 Shipwright - 0.1.0-18
- You stay logged in: cookies and site data were kept only until Pacific closed.
- Going to another page, the one you are leaving blurs in place if the next takes a moment, and the new page fades in over it.
- Press and hold the tab button for a new tab, a new private tab, or closing all your tabs at once.
- In the tab switcher, swipe a tab left to close it; swiping right goes back, as everywhere else.
- Cookie banners that Pacific rejects no longer flash on screen first (The Verge).
* Sun Oct 11 2026 Shipwright - 0.1.0-17
- On a phone whose processor is older than ARMv8.2 (Xperia 10 II), Pacific no longer installs only to crash at start: the install says why.

* Sat Oct 10 2026 Shipwright - 0.1.0-16
- The toolbar is frosted glass: the page behind it shows through, blurred, with its colours lifted, under the theme's tint.
- A tap on the band under the notch takes the page to its top, as a tap on the status bar does on iOS; from far down it jumps to two screens from the top and glides the rest.
- Pull to refresh: dragging down a page that is at its top stretches it as on iOS, a tick says letting go reloads it, and dragging back up cancels. It never starts from a fling into the top, and pages that opt out (overscroll-behavior) or take the drag themselves keep it.
- Pages are protected sooner after start-up: the engine's own filters are switched on from the record on disk before the slower filter engine loads.
- Less work on the main thread while pages load: the tab list is told about progress in quarters rather than every tick, the cover reads the tabs only while it is on screen and decodes its picture in the background, and a tab's picture is not taken while the page is scrolling.

* Sat Oct 10 2026 Shipwright - 0.1.0-15
- Downloads are named as the server names them (Content-Disposition), not after the address.
- The cover follows the tab in front: its title, site and picture as it loads, and the page as it was left.
- The page-load line fills to the end before it fades, and starts each load from its own value.

* Thu Oct 08 2026 Shipwright - 0.1.0-14
- Plainer wording. Page load and filter errors say what happened.

* Wed Oct 07 2026 Shipwright - 0.1.0-13
- A drag down on the page brings the hidden toolbar back even when the
  page has stopped scrolling (a modal, a cookie or subscription wall):
  with the toolbar hidden there was no way to leave such a page.
- Pinching leaves a page's colour around a page zoomed out of what was
  drawn, not the wallpaper.
- Cookie-banner rejection costs pages less while they load: it no longer
  forces layouts to test visibility or to read its own styles, skips the
  whole-page text scan, and gives up after 10 tries (0.25 s less main-thread
  time on a Wikipedia article).

* Wed Oct 07 2026 Shipwright - 0.1.0-12
- Shields: one switch at the top of a site's page turns its ad and
  tracker blocking and cookie-banner answers off together, for a site
  that does not work properly, and back on. It replaces the "Block ads
  and trackers" switch.
- The site's page lists what was blocked from the left, the site and
  its count, the six largest first with the rest on request, under the
  total in large type.
- Resetting a site's settings, or clearing site settings with browsing
  data, puts its shields back up at once; blocking stayed off there
  until something else rebuilt the filters.

* Wed Oct 07 2026 Shipwright - 0.1.0-11
- Fixed elements at the bottom of a page (cookie banners, sites' bottom
  navigation) sit above the floating toolbar instead of under it, and a
  page's last lines scroll clear of it. The page learns what the bar
  covers once scrolling stops, so flings never stall for it.
- A page with a login form no longer brings Shoal Keys up over the
  browser: Pacific only asks a running Keys which logins it has.
- Find in page no longer opens the text selection menu over the matches.
- The tab overview opens at the tab in front.
- A link from another app uses an untouched new tab in front instead of
  leaving it behind empty.
- In portrait every page stays below the notch, as in Safari. Pages that
  ask for the whole screen (viewport-fit=cover, such as YouTube) had
  their headers under it: sites written for Safari do not pad for it.
- Find in page says which match is shown ("3 of 75"), closes on another
  page, and its count no longer turns into nonsense after a step.
- The new-tab page shows one tile per site name: bbc.com and bbc.co.uk
  were two "bbc" tiles.
- The page menu is the stock browser's pop-up card: rounded, at the
  bottom right under the menu button, over the dimmed page, with a handle
  to drag it away. It was a panel across the whole width.

* Tue Oct 06 2026 Shipwright - 0.1.0-10
- The page takes the toolbar's space as the bar starts to slide away,
  under the bar, instead of after the slide: no band of wallpaper below
  the page while it relayouts.
- Enter in the address page goes back to the page at once, as the address
  page opens, instead of a 400 ms slide.

* Tue Oct 06 2026 Shipwright - 0.1.0-9
- Pages stay below the notch; pages that ask for the whole screen
  (viewport-fit=cover) get it, with the notch as their top safe area.

* Mon Oct 05 2026 Shipwright - 0.1.0-4
- Google, YouTube and BBC consent answered; reader mode keeps collapsed
  sections.

* Mon Oct 05 2026 Shipwright - 0.1.0-3
- The address is selected when the address page opens.

* Mon Oct 05 2026 Shipwright - 0.1.0-2
- /usr/bin/shipwright-pacific is the ELF binary; it applies the engine's
  environment by re-execing through pacific-env. Sailjail refused the old
  shell wrapper ("is not elf binary"), so Pacific could not start from the
  app grid.

* Sun Oct 04 2026 Shipwright - 0.1.0-1
- First package: core, CXX-Qt app, Silica UI and Keel Actions.
