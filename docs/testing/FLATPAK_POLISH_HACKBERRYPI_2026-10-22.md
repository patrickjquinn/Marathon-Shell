# Flatpak fit-and-finish audit - HackberryPi CM5, 2026-10-22

This audit was run on the physical Marathon device on `rust/migration`. Apps
were installed through `marathon-store-handler`, launched through the shell,
and driven with touchscreen events from `marathon-touchctl`. Screenshots came
from the device KMS output and findings were checked against the user journal.

## Test set

All nine applications are present in the Store's generated phone catalogue.

| Application | App ID | Toolkit/runtime | Coverage |
|---|---|---|---|
| Fragments 3.0.1 | `de.haeckerfelix.Fragments` | GTK/libadwaita, GNOME 50 | edge menus, tooltips, preferences, switcher |
| Authenticator 4.6.2 | `com.belmoussaoui.Authenticator` | GTK/libadwaita, GNOME 50 | edge menus, account editor, preferences, back |
| Audio Player 49.6 | `org.gnome.Decibels` | GTK/libadwaita, GNOME 51 | left-edge menu, open-file portal |
| Kasts 26.08.2 | `org.kde.kasts` | Qt/Kirigami, KDE 6.11 | adaptive layout, search, menus, file portal |
| Shortwave 5.1.0 | `de.haeckerfelix.Shortwave` | GTK/libadwaita, GNOME 50 | menus, nested navigation, switcher |
| Musicfetch 1.6.0 | `net.fhannenheim.musicfetch` | COSMIC | pointer compatibility, folder portal |
| Weather 26.08.1 | `org.kde.kweather` | Qt/Kirigami, KDE 6.11 | handset onboarding, primary action, typography |
| Photos 26.08.1 | `org.kde.koko` | Qt/Kirigami, KDE 6.11 | gallery grid, bottom navigation, search, palette |
| KDE Itinerary 26.08.2 | `org.kde.itinerary` | Qt/Kirigami, KDE 6.11 | handset onboarding, settings rows, switches |

The four new installs appeared immediately in the Store's `installed.json`.
The install pass reduced free space on `/home` from 8.2 GB to 5.7 GB, mostly
because GNOME 51 and KDE 6.11 runtimes were not already installed.

## Hit list

Status reflects the second implementation and device-validation pass. Resolved
rows remain here because they are part of the regression contract.

| Priority | Area | Reproduced result | Scope |
|---|---|---|---|
| Resolved | `xdg_popup` constraints | Marathon applies the positioner's flip/slide/resize policy and keeps its configured geometry authoritative over QtWayland's unconstrained item position. Shortwave's right-edge menu and nested Sorting panel remain entirely inside the 720 px output. | Compositor-wide |
| Resolved | `xdg_popup` lifecycle/input | Marathon tracks the popup and its surface with guarded pointers, sends `popup_done` on an outside press before input reaches the underlying app, and prunes either object when it is destroyed. The Shortwave menu and nested submenu dismissed correctly on-device; a follow-up touch retained the same shell PID with no coredump. | Compositor-wide |
| Resolved | Qt/Kirigami mobile profile | The app process receives `QT_QUICK_CONTROLS_MOBILE=1`, Breeze, and the Marathon KDE palette. Kasts intentionally uses its upstream landscape sidebar because the 720x628 app viewport is wider than tall; KWeather, Koko, and Itinerary all render their handset layouts correctly. | Qt/Kirigami-wide |
| Resolved | Native back | Marathon sends the toolkit back key, retries GTK/libadwaita with Escape when the first key causes no visible change, and only dismisses the task if both attempts are unhandled. A right-to-left gesture-bar Back closed Authenticator's libadwaita Preferences dialog while Authenticator and the shell remained alive. | GTK/native back |
| P1 | Transient toplevel handling | Source classification recognizes Marathon's title-tagged dialogs, not ordinary Flatpak `xdg_toplevel.set_parent` or `xdg_dialog_v1` dialogs. Such windows can be maximized and replace the task's primary surface. The sampled apps mostly use in-process libadwaita dialogs, so a dedicated transient-window fixture is still required. | Compositor-wide risk |
| P1 | Maximize/fullscreen geometry | Native initial geometry uses Marathon's logical app viewport, but the advertised output available geometry is the physical shell window. A client maximize/fullscreen request can therefore jump to oversized or clipped geometry. A video/browser fixture is still required. | Compositor-wide risk |
| Resolved | Qt process environment | Shell-only EGLFS, scaling, QML import, render-loop, and WebEngine variables are stripped before Flatpak launch. KDE apps receive one coherent Wayland/Breeze/mobile profile. | Qt-wide |
| Resolved | Flatpak process environment | Shell-only `GIO_USE_VFS=local` and `GSETTINGS_BACKEND=memory` no longer leak into Flatpaks. Sessions publish `LANG=C.UTF-8`; the sampled Shortwave process inherited the locale and portal routing without a forced renderer or protocol-debug variable. | Flatpak-wide |
| Resolved | KDE style resolution | Marathon no longer forces `Basic`. KWeather, Koko, Kasts, and Itinerary use Breeze geometry with materially larger touch targets. | KDE/Kirigami-wide |
| Resolved | KDE palette materialization | The theme service generates both `Marathon.colors` and `kdeglobals`; Flatpak overrides expose them read-only. KDE Widgets and Kirigami now share the neutral dark Marathon palette. | KDE Flatpaks |
| P2 | Native dialog layout | Authenticator's Preferences sheet cuts the bottom row at the dialog edge. Fragments' Preferences content overlaps its header (`PreferencesBehavior`) and its lower content sits behind the fixed tab strip. | GTK dialog integration |
| Resolved | File chooser polish | Desktop mnemonic markers are stripped and the location strip scrolls horizontally with safe edge margins. QML regression coverage includes both behaviors. | Shell portal UI |
| Resolved | Portal hot replacement | The session exports its current Wayland and locale environment to the user manager, then restarts the portal frontend and GTK backend after the replacement compositor socket exists. Both services remained active and Musicfetch raised Marathon's folder picker after a hot deploy. | Session/portal lifecycle |
| P2 | File chooser ownership | The portal backend discards the requesting app ID and parent-window token. Its one global chooser can therefore remain over the wrong foreground task after an app switch, while a second request cancels the first. | Shell portal lifecycle |
| Resolved | Palette consistency | GTK 4/libadwaita and KDE use neutral elevated surfaces with semantic Marathon accent colors. GTK 3 falls back to complete upstream Adwaita rather than a partial global selector theme. Musicfetch retains its upstream COSMIC treatment. | Visual system |
| P2 | Icon compatibility | Loading Authenticator's exported SVG repeatedly logs an unresolved gradient reference. Marathon has no freedesktop icon theme for Flatpaks and falls back to Adwaita or Breeze, so launcher and in-app icon treatment is toolkit-specific. | Launcher/toolkit-wide |
| P2 | Compatibility policy | Every app receives GTK, libadwaita, Purism, and Qt mobile hints regardless of toolkit. COSMIC pointer fallback is selected from desktop metadata. There is no tested GTK3/libadwaita/Kirigami/COSMIC compatibility profile. | Launch policy |
| P2 | COSMIC popup input | Musicfetch's main surface uses Marathon's touch-to-pointer compatibility item, but automatically created popup surfaces use Qt's base shell-surface item and do not inherit that fallback. A COSMIC xdg-popup fixture is required before calling this path complete. | COSMIC/compositor risk |
| P3 | Switcher capture | In-process Preferences dialogs are included in task cards. Open xdg popups were dismissed before the switcher capture in the tested gesture path, but popup/subsurface capture has no focused regression test. | Switcher polish |
| Resolved | Flatpak hot-restart lifecycle | Frozen Flatpak scopes survived compositor replacement, retained D-Bus singleton names, and made Koko/Kasts relaunches wait. Session startup now thaws and stops every scope from the previous compositor generation; the device test removed a deliberately frozen Kasts scope and name. | Session lifecycle |
| Resolved | Store installed/update state | The Installed tab renders all 9 Flatpaks and 5 Android apps. Update discovery now requests application refs only, so runtime components no longer create app badges; the tested state contains zero pending app updates. | Store |

## What worked

- All tested applications launch, resume, accept primary touch actions, and
  retain stable task-switcher covers.
- Store installation, installed-state refresh, app icons, and launch routing
  work end to end for the new applications.
- The Marathon file chooser opens from GTK, Qt/Kirigami, and COSMIC Flatpaks.
  Musicfetch's Select action now raises the chooser instead of doing nothing.
- Fragments and Authenticator use adaptive in-process dialogs rather than
  separate desktop windows; their geometry still needs the fixes above.
- The absence of an on-screen keyboard was not counted as a defect on this
  Hackberry device because it exposes a physical keyboard and Marathon
  intentionally suppresses the OSK in that configuration.

## Remaining implementation order

1. Model ordinary transient toplevels and fullscreen geometry explicitly rather
   than treating every Flatpak surface as the task's maximized primary surface.
2. Preserve file-chooser ownership across task switches and concurrent portal
   requests.
3. Define a freedesktop icon policy and cover COSMIC popup pointer fallback.
4. Add the device screenshot suite for edge popups, modal dialogs, text fields,
   portals, fullscreen, and task-switcher covers for each toolkit.

The device should keep this exact application set until these items are fixed;
it provides a repeatable cross-toolkit regression matrix without another large
runtime download.

## Second-pass implementation contract

- Keep `XDG_CURRENT_DESKTOP=marathon`; Marathon must not impersonate a Plasma
  session. KDE Flatpaks get `QT_QPA_PLATFORMTHEME=kde`,
  `QT_QUICK_CONTROLS_STYLE=org.kde.breeze`,
  `QT_QUICK_CONTROLS_MOBILE=1`, `PLASMA_PLATFORM=phone:handset`, and
  `PLASMA_INTEGRATION_USE_PORTAL=1`.
- Strip EGLFS, shell scaling, host QML import, render-loop, and WebEngine
  sandbox overrides before starting third-party clients.
- Use the existing Marathon GTK and KDE integrations. Wallpaper ambience may
  change the accent, but window, view, header, button, and popover surfaces use
  Marathon's neutral elevation tokens. Generate a live `Marathon.colors` in
  `xdg-data/color-schemes` and a matching `xdg-config/kdeglobals`: current KDE
  Flatpaks do not all materialize the portal palette into `QPalette`.
- Do not globally resize toolkit widgets with CSS. Mobile behavior comes from
  real allocation, Kirigami's mobile mode, toolkit fonts, and native style
  metrics. App-specific failures remain visible instead of being hidden by a
  brittle global selector sheet.
- Treat clipped xdg popups as a compositor/protocol defect. QtWayland 6.11
  repositions its item with the unconstrained coordinate after the compositor
  sends a constrained configure. Marathon queues its item placement after that
  handler and implements outside-touch dismissal in the compositor; the policy
  solver and physical-device screenshots cover the corrected path.

## Flatpak frame-pacing benchmark

Shortwave's station browser was scrolled with six identical 370 px upward
gestures (`MARATHON_TOUCH_HEIGHT=720`, 40 steps) while the compositor's
`MARATHON_PRESENT_STATS` meter counted swaps and client commits. The shipping
8 ms late-latch path sustained about 35 fps; immediate frame-start callbacks
sustained about 47 fps, with compositor and client counts tracking one another
in both runs. The late gate therefore caused missed vblanks rather than GPU or
client-side saturation, and immediate latching is now the default. The
`MARATHON_FRAME_PHASE_MS` override remains available for device experiments.

Commit-gated free-run is now enabled by default: a client commit grants four
vblank-paced compositor frames, then the compositor returns to 0 fps while
idle. Active samples improved from roughly 29-51 fps to 36-60 fps. Forcing
Shortwave from GTK's default Vulkan renderer to OpenGL was neutral or slower,
so Marathon does not impose `GSK_RENDERER`; the bottleneck was scheduling, not
QtWayland buffer transport or a software-rendering fallback.

Flatpak process setup is no longer the visible cold-start bottleneck: after a
clean compositor session the D-Bus launch call returned in 44-65 ms, the
Flatpak systemd scope existed about 140 ms after input, and Shortwave had its
fully rendered station view on screen by the 1.5 s capture. Kasts still showed
the Marathon splash at 1 s and completed shortly afterward, which is its own
Qt/KDE runtime and database initialization rather than sandbox or portal
startup. `marathon-flatpak-prewarm.timer` starts the Flatpak helper and portal
processes after login so the first app does not pay those service startups.

The Rust task registry also now validates a registered PID before trying
`org.freedesktop.Application.Activate`, removes both directions of stale PID
state, and rechecks a Flatpak's inner process after its supervisor exits. Before
this fix, terminating Shortwave left a stale live-app record and its next launch
waited about 13.6 seconds. On the final physical-device build, clean launch and
post-termination relaunch mapped in 2.036 seconds and 2.027 seconds respectively.
