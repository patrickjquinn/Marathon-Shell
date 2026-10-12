# Keel-for-Marathon programme ledger

Spec: docs/superpowers/specs/2026-10-11-keel-for-marathon-design.md
User (2026-10-12): do the whole programme without stopping between phases; test on hardware as you go.
Branch: feat/keel-framework-1a (continue on it).

| Phase | State | Device-validated |
| --- | --- | --- |
| 1a theme pipeline | done (12 commits) | yes (r366) |
| 1b Marathon.Silica a11y + keys | committed (109 qml tests) | yes r369/r370: keys, menus, Esc, Tab, typing, AT-SPI tree |
| 1c TabBar/TabView, PageIndicator, FilterChip; icon theme | built (marathon-icon-theme subpkg, lint) | icons installed r367; visual check pending |
| 1d Marathon.Platform; Ngf/Configuration/Notifications backends | committed | Ngf Play/Status on system bus OK; Configuration persists via dconf across restart; remote actions host-tested only |
| 1e pool pre-compiles framework; notes-silica on framework | committed | first frame 1.28-1.44 s (target <=1.87) |
| 2 shell redesign | in progress: Keel cost 11.7 MB RSS in shell; covers (r371) built; portal Settings backend built | covers pending |
| 3 app migration | | |
| 4 remove MarathonUI | | |
| 5 Sailfish app support | | |

## Rulings
- 1b: Escape. The compositor turned every Esc key into system back before apps saw it. Ruling: for Keel apps the compositor passes Esc through (KeyRouting); Silica controls use it (menus, dialogs, remorse) and Page turns an unused Esc into handleBack. MarathonUI apps unchanged. Cost if wrong: a Keel app that swallows Esc can't be backed out of by keyboard (back gesture still works).
- 1b: Page Esc on depth 1 calls handleBack (minimise) — keyboard back parity with the gesture.

## Nemo/Sailfish survey (2026-10-12)
Keel ships the Qt 6 client side of every API; Marathon supplies services:
- Nemo.Ngf → own service owning com.nokia.NonGraphicFeedback1.Backend (system bus), events mapped to shell haptics (ngfd not on Alpine; nemo-packaging has PKGBUILD as fallback).
- Nemo.Configuration → use Alpine mlite + dconf, build keel-silica with KEEL_REQUIRE_MLITE=ON.
- Nemo.Notifications → extend shell org.freedesktop.Notifications: GetNotifications(appName), x-nemo-* hints (remote actions etc.).
- Sailfish.Share → own org.sailfishos.share service + X-Share-Methods targets.
- Accounts → Alpine signond/libaccounts-qt6 as-is; our own setup flow + provider XML.
- Secrets → sailfishsecretsd is Qt5; port later if an app needs it.
- sailjail → translate [X-Sailjail] Permissions into bwrap args + Permissions1 (reference: github.com/sailfishos/sailjail-permissions).
- com.nokia.mce minimal shim for display/tklock/battery (Nemo.Mce, keepalive).
- Recipes: github.com/nemomobile-ux/nemo-packaging; lipstick Qt6 port at nemomobile-ux/lipstick (reference only).

## Deferred minors
- TextField/TextArea expose an extra unnamed inner editor node in AT-SPI.
- Nemo Notifications GetNotifications/GetNotificationsByCategory not implemented (apps can't list their own posted notifications).
- keys.py on device: /var/tmp/keys.py (uinput); a11y dump: /var/tmp/a11ytree.py (run as user).

## Device test helpers
- Enable AT-SPI: busctl --address=unix:path=/run/user/1000/bus set-property org.a11y.Bus /org/a11y/bus org.a11y.Status IsEnabled b true (as user), then restart runners.

## Sub-project 2 plan (shell redesign on the framework, option A)
Order (each device-validated with screenshots vs Sailfish references):
1. Shell loads Marathon.Silica: measure shell start + RSS on PinePhone before/after (spec risk).
2. Covers: compositor recognises `keel:cover` titled toplevels per appId (KeyRouting-style pure matcher + test), keeps them out of app windows, exposes the cover surface to TaskCard; runner sets KEEL_SHELL_COVER_ENABLED=1 and drives CoverStatus from switcher visibility (shell→runner over AppLifecycle1). Legacy apps keep live thumbnails.
3. Task switcher: Sailfish-style cover grid (Theme.coverSizeLarge/Small, ambience glass), close by ✕/swipe kept.
4. Chrome: status bar + gesture bar in Silica typography/colours (Theme.*), ambience-tinted.
5. Hub (Events view): Silica list/section headers, notifications as Silica ListItems.
6. Quick settings (Top Menu): Silica switch grid + sliders.
7. Lock screen: Silica clock typography, notification icons, ambience wallpaper.
8. Portal: xdg-desktop-portal Settings color-scheme + accent from AmbienceService.
Known shell issue to fold in: OSK pops up while typing on a hardware keyboard.

## Sub-project 5 plan (Sailfish app support)
Reality check: Harbour/OpenRepos RPMs are Qt 5 + glibc binaries linked to SFOS libs; they cannot run on Alpine (musl, Qt 6) as-is.
1. QML-only apps (Exec=sailfish-qml <app>): install the RPM payload (/usr/share/<app>/qml, desktop file, icons) and run under marathon-app-runner as a Keel app with Keel's qt5compat import path first (keel/qt5compat). keel-silica must ship qt5compat (KEEL_BUILD_SAILFISHAPP=ON).
2. C++ SailfishApp apps rebuilt for Qt 6 against Keel's sailfishapp shim: launched on the native path through a small host wrapper (KeelHost + AmbienceClient + CloseRequested on SIGTERM, then exec the app) so they get ambience/covers/close semantics.
3. [X-Sailjail] Permissions= → bwrap binds + Marathon permissions (reference sailfishos/sailjail-permissions).
4. Backends: org.sailfishos.share (shell share sheet), Accounts (Alpine signond/libaccounts-qt6), pickers (Keel platform; needs KEEL_BUILD_PLATFORM=ON).
