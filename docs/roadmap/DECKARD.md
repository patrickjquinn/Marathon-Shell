# Deckard: corrections to the design against Marathon as it is

The design is "Deckard – Android runtime for Marathon OS, technical design" (draft, 18 October 2026). This page records where it differs from the Marathon tree and devices, checked on 2026-10-18. The Android base question is in [DECKARD_ANDROID_BASE.md](DECKARD_ANDROID_BASE.md); M0 device results are in [../testing/DECKARD_M0_HACKBERRYPI.md](../testing/DECKARD_M0_HACKBERRYPI.md).

## Open questions (§17) answered

| Question | Answer |
|---|---|
| Does the keyboard serve Wayland clients over text-input-v3? | Yes. The compositor creates `QWaylandTextInputManagerV3` (`shell/src/wayland/waylandcompositor.h`), and Marathon's keyboard types into Wayland apps through it. |
| Hub interface and app registry API | The Hub is `org.freedesktop.Notifications` (`shell/src/dbus/freedesktopnotifications.*`), with KDE inline reply and `NotificationReplied`. The shell services are `org.marathonos.Shell.*1` in `shell/src/ipc/shellservices.h`: AppStore1, Navigation1, AppLifecycle1, Permissions1, Alarm1, Location1, Sensor1, and others. Apps also expose Keel Actions (`org.shipwright.Keel.Actions`). |
| BINDER_FREEZE and a delegatable cgroup2 freezer | HackberryPi kernel 6.12.85: `ANDROID_BINDER_IPC=y`, `ANDROID_BINDERFS=y`, `USER_NS=y`, `CGROUP_FREEZER=y`, PSI, memcg; binder is in `/proc/filesystems`. The shell already freezes apps by writing `cgroup.freeze` in a subtree delegated to it. |
| Touch cancel, libdbus across the user namespace, binder on PREEMPT_RT, palette | To be measured in M0. Note that `packaging/packages/linux-marathon/config-marathon-base.aarch64` sets `PREEMPT_RT=y`. |

## Where the design assumes a different Marathon

1. **Power.** Marathon doesn't use opportunistic suspend or kernel wake locks. It uses Marathon-Doze (`docs/UI_DESIGN_SYSTEM.md` §12): the display and GPU turn off, the kernel keeps running, and background apps are frozen with the cgroup freezer. So the suspend HAL should map an Android wake lock to `AppLifecycle1.BeginBackgroundTask` (stay thawed), and AlarmManager's next wake-up to `Alarm1`.
2. **Push.** The shell already is a UnifiedPush distributor (`org.unifiedpush.Distributor2` in `shell/src/services/unifiedpushdistributor.*`, over ntfy). Android apps that support UnifiedPush can use it directly; microG FCM is needed only for the rest.
3. **One client, many apps.** The shell keys tasks, freezing and killing by PID (`applaunchservice.cpp` surface matching, `applifecyclemanager.cpp` `killOldestFrozenApp`), and sandboxed clients get one app id per client. Android apps would merge into one card, and reclaiming one would kill the container. M0 fixes this in the shell. The design's identity broker covers portals only, not this.
4. **The Hub has no threaded view.** `x-marathon-conversation` is new Hub work, not an existing target.
5. **xdg-activation isn't in the compositor.** M0 adds it.
6. **Keel Actions.** Not in the design: Android app shortcuts and intent filters can be listed as Keel Actions, so Android apps show up in search and can be driven over MCP like Marathon apps.

## Problems in the design itself

- M1 puts notifications in the Hub, but the bionic libdbus they depend on arrives in M2. Use the host-side bridge first and make libdbus the later optimisation; it has no prior art and nothing should wait on it.
- Building on Android 13 and then rebasing to 15 or 16 in M3 means building the hwcomposer, IME, suspend HAL, overlays and stubs twice. See [DECKARD_ANDROID_BASE.md](DECKARD_ANDROID_BASE.md).
- A userdebug image for microG makes the daily image debuggable. That is a security trade-off and should be stated as one.
- The GPU depends on the device:

  | Device | GPU | Android outlook |
  |---|---|---|
  | HackberryPi CM5 | V3D (v3d/v3dv) | The test device for M0. |
  | OnePlus 6 | freedreno | Builds as `oneplus-enchilada`, but hasn't been booted recently. |
  | Librem 5 | etnaviv, GLES2 | Probably out. |
  | PinePhone | lima, GLES2 | Probably out. |
  | Zinwa Q25 | Mali G57 | Panfrost in principle, but its working route is Halium, which already runs an Android vendor container and conflicts with "the image ships no GPU userspace". |

## M0, on the HackberryPi

1. **Shell.** Each toplevel of one client is its own app, and lifecycle never freezes or kills a PID that hosts several tasks. Add xdg-activation and `marathon_surface_v1` (insets, back events, window flags).
2. **Image.** Stock Waydroid in the A/B image, added through a numbered pipeline patch. Measure scrolling, focus, binder latency, touch cancel on a Hub peek, and RAM and idle cost.
3. **Design.** Update the design with the corrections on this page and the M0 numbers before starting M1.
