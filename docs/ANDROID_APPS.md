# Android apps (Deckard)

Deckard runs Android apps as Marathon apps. It is Waydroid (LineageOS 20,
Android 13) plus Marathon's own pieces on both sides of the container. Its
source, design and measured findings are in
[Marathon-Deckard](https://github.com/patrickjquinn/Marathon-Deckard); this
page covers what the shell does with it.

## Parts

| Part | Where | Role |
|---|---|---|
| Android runtime | `waydroid-container.service` (system), `deckard-session.service` (user) | The system container manager is still Python; the user session and app launcher are Rust. Android runs zygote, system_server, and SurfaceFlinger with Waydroid's Wayland hwcomposer in multi-window mode. |
| Image overlay | Marathon-Deckard `image/` | Marathon's system apps inside Android (DeckardBridge, DeckardSystem, the blank home, `deckard-wm`), the slimmed system and microG. Mounted over Android's system partition. |
| `deckardd` | Marathon-Deckard `host/deckardd` | The host daemon: notifications, media, permissions, packages, location and toasts over the bridge protocol (`protocol/bridge.md`). |
| `deckard` aport | `packaging/packages/deckard` | Packages all of it at the Marathon-Deckard commit `_commit` pins. |

## In the shell

- **App ids.** An Android app is `waydroid.<package>`
  (`PermissionAuth::isAndroidAppId`, `shell/src/ipc/permissionauth.h`).
  The native session retains these IDs but exports desktop commands through
  `/usr/libexec/deckard-launch`.
- **Windows.** The hwcomposer makes one Wayland toplevel per Android task,
  all from one client. The shell files each toplevel as its own app and
  card, and never freezes or kills a PID that hosts several tasks.
  `deckard-wm` keeps every task freeform at the display's size, because a
  fullscreen task hides the ones under it and Waydroid then destroys their
  windows.
- **A window going.** Waydroid re-creates a task's window as Android
  redraws it, so the last window of an app waits `WINDOW_GRACE` (1 s,
  `Tasks::window_destroyed`, `tasks/launch.rs`) before the app is closed. If it
  was on screen, its app window closes with it (`MarathonAppWindow.qml`).
- **Permissions.** Android's runtime permission prompts are drawn by the
  shell (`Permissions1`, `crates/marathon-shell-native/src/permissions.rs`). Allow and Deny
  answer Android; Back cancels and changes nothing.
- **Notifications.** `deckardd` posts Android's notifications to the Hub
  through `org.freedesktop.Notifications`, with inline reply, and its media
  sessions as MPRIS players.
- **Keel Actions.** Android apps' shortcuts are listed as Keel Actions
  (`waydroid.<package>__app.show`, `__shortcut.*`), so they appear in
  search and can be driven over MCP.

## Settings and the Store

- Settings > Android apps (`apps/settings/pages/AndroidPage.qml`): status,
  start at login, reset, the installed apps with each one's permissions,
  notifications and battery use, special access, and Google services
  (microG): on or off, push on or off, and a self-check. Routes: `android`,
  `androidapps`, `androidaccess`.
- The Store installs APKs through `deckardd` and checks each app's needs
  (required features, libraries, ABIs, Google services) against
  `Packages.DeviceProfile()` before install.

## microG

GmsCore and its Play Store stub (Companion), v0.3.17. LineageOS 20's
userdebug build spoofs their signatures. It gives apps FCM push with no
Google account; check-in and push connect at boot. Location: Android's
network and fused providers take Marathon's GeoClue fix through
DeckardBridge; microG's own fused and geocoder providers are off, since
they kept its main process running.

Measured on the HackberryPi: +113-134 MB of Android memory, +121-142 MiB
on the host, no change to boot (about 11 s) or idle CPU (0.15 %), one
wake-up about every 325 s, about 300 MB of disk. Details:
Marathon-Deckard `docs/microg.md`.

## Deploying to a device

The overlay is synced only when the container starts
(`ExecStartPre=deckard-overlay-sync`). After installing a new `deckard`
package:

```sh
systemctl --user stop deckard-session.service
sudo systemctl daemon-reload
sudo systemctl restart waydroid-container.service
systemctl --user start deckard-session.service
```

Restarting the container alone stops the user session and leaves it down.

## Looking inside Android

```sh
A='lxc-attach -P /var/lib/waydroid/lxc -n waydroid --clear-env -- /system/bin/sh -c'
$A 'dumpsys activity activities | grep ResumedActivity'   # what is on top
$A 'dumpsys activity recents | grep "Recent #"'           # tasks
$A 'pm list packages -3'                                   # installed apps
```

The resumed activity `org.marathonos.deckard.home/.HomeActivity` means no
Android app is open: it is a blank home that never shows.

## Known gaps

- When microG already has a window open, its sign-in window doesn't come
  to the front: a second window of an app that has one open.
- The Store opened on an `android:` id before the Store is running shows
  an empty page.
