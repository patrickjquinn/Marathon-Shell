# Deckard M0 on the HackberryPi CM5: stock Waydroid

Measured on 18 October 2026 on the HackberryPi CM5 (CM5 Lite, 16 GB, V3D),
image 26101807 (A/B, Alpine/pmOS edge), kernel 6.12.85-0-rpi, marathon-shell
1.0.0-r479. The shell had none of the M0 shell or compositor fixes yet
(per-app cards, xdg-activation, `marathon_surface_v1`). Every number here comes
from this device. Design corrections are in
[../roadmap/DECKARD.md](../roadmap/DECKARD.md).

## Results

| M0 criterion | Result |
|---|---|
| Android app on screen as a Marathon window | Yes, in two ways. A single multi-window app: the Clock task's window showed in the switcher and came to the front from it. Full-UI mode: one "Waydroid" window running Android Settings, scrolled by touch through Marathon. In multi-window mode, keeping an app on screen is unreliable (see *System_server deadlock* and *Window churn*). |
| Scroll smoothness | Settings "All apps" list, 12 flings (300 px, 250 ms each) sent through Marathon's touch path over 14.2 s. **Android:** `dumpsys gfxinfo` reported 561 frames, 0 janky, frame time p50 5 ms, p90 5 ms, p99 9 ms, GPU p99 7 ms, 0 missed vsyncs. **Compositor:** 626 `drm_vblank_event_delivered` events on crtc 0. Each fling was a continuous 60 Hz run of 46–58 flips; 2 vblanks were missed in total (33.3 ms gaps). This was full-UI mode, after the window had been brought to the front. |
| Focus stealing | Display: none. A window created by `waydroid app launch` or `waydroid app intent` became a background task, and `foregroundApp` stayed `""`. Keyboard: yes. Every new Android toplevel was sent `wl_keyboard.enter` straight away, while the shell kept showing Home. The keyboard follows a window the user can't see. |
| One switcher card per Android app | The protocol allows it; the shell can't yet. Waydroid makes one `xdg_toplevel` per Android task, with `app_id` `waydroid.<package>` and `title` set to the app label, or briefly the package name. The shell made one task per `app_id` (Clock, Settings and Browser listed separately in `apps.running`), but the switcher was wrong. The Clock card showed and worked. The Browser card was in `apps.running` but not in the switcher. A stale "Waydroid" card outlived its window. Two windows sharing an `app_id` (Waydroid created two for Jelly within 20 ms) left a card that disappeared when one of them closed. |
| Binder round trip | Host to container through `/dev/binderfs/binder` (aidl3), from Python with gbinder, 3 runs of 2000 calls. `PING_TRANSACTION`: median 16.5–16.7 µs, p99 22–27 µs, min 10.3 µs. A real call (`waydroidplatform` getprop): median 31–35 µs, p99 60–69 µs. The numbers include Python overhead. |
| Left-edge Hub peek during an Android gesture | A drag that starts at the left edge opens the Hub, and the Android client gets no `wl_touch.down`, only a single empty `wl_touch.frame`, so no `ACTION_CANCEL` is needed. A peek that interrupts a touch already in progress needs a second finger, and the single-contact injector can't do that, so that case is untested. |
| RAM | MemAvailable with no container: 14,427,208 kB. Container booted, no app window: 13,704,292 kB, so **706 MiB** used. With the Clock app also started: 13,441,292 kB, **963 MiB** in total. The container cgroup was charged 1457 MiB (446 MiB anon) at idle and 1683 MiB (607 MiB anon) with Clock. Android's own count: "Used RAM 1,702,633K (1,058,297K PSS + 644,336K kernel)". After two system_server restarts, the old SystemUI, launcher and Settings processes stayed resident: PSS was 1.3 GB and the cgroup peaked at 2567 MiB. |
| Idle CPU and wakeups | 60 s windows, from cgroup `cpu.stat` and per-task context switches. Container not running: whole system 1.2 % busy, 5991 IRQ/s. Container idle, no window: **0.11 % of one core, 69 context switches/s**, system 1.9 % busy, 6246 IRQ/s. With Clock started (moved to the back by Android, see below): 0.54 % of one core, 111 context switches/s, 6527 IRQ/s. The shell stayed at 0.15 %. |
| Doze and the freezer | The shell's freezer can't reach Android. The container runs in `/sys/fs/cgroup/lxc.payload.waydroid`, outside `marathon-app-*` and the user slice, and its processes keep Android's oom scores on the host: surfaceflinger and the composer -1000, system_server -800 (the same as the shell). Waydroid freezes the whole container itself: 60 s after the last Android input (Android's default `screen_off_timeout`), Android asks its suspend HAL, which runs `lxc-freeze`. Seen twice (19:15:38 and 19:26:12). On freeze, the hwcomposer destroys every toplevel. `waydroid app launch` thawed it once (19:16:31). I didn't put the shell into Doze. |
| Session start | `waydroid session start` to "Android with user 0 is ready": 16.1, 16.5 and 16.7 s, with a warm page cache. |

## Blockers found

### System_server deadlock in Waydroid's hwcomposer (3 times out of 4)

Android's watchdog killed system_server at 18:14:29, 18:23:09 and 18:40:09
(Android clock, UTC), each about 60–70 s after an app launch in multi-window
mode. The ANR trace (`/data/anr/anr_2026-10-18-18-13-46-948` in the container),
and `debuggerd -b` on the composer during the second and third hangs, show the
same cycle:

1. The composer's Wayland thread is in `keyboard_handle_enter` and calls
   `IWaydroidTask::setFocusedTask` (HIDL, into system_server), while holding
   the hwcomposer lock.
2. The composer's present path (`hwc_set`) waits on that lock, so
   SurfaceFlinger's `presentDisplay` blocks.
3. system_server's `android.display` thread is in a display hotplug
   (`LocalDisplayAdapter.onHotplug` → `getDynamicDisplayInfo`). It holds
   DisplayManagerService's SyncRoot and waits on SurfaceFlinger.
4. `InputDispatcher` holds the WindowManager global lock and waits on that
   SyncRoot. It is there because of an input configuration change: the
   `wayland_touch` device is re-added over and over (EventHub log).
   `setFocusedTask` needs the WindowManager lock, which closes the cycle.

The trigger is the shell sending `wl_keyboard.enter` while Waydroid is
reconfiguring. The one launch that didn't hang created its window only once.
Full-UI mode never hung (one window, one `enter`).

### Window churn on launch

For each new task, the shell sent `configure(0,0,[])`, then
`configure(480,419,[maximized,activated])`, then `configure([maximized])`
(deactivated), then `wl_keyboard.enter`, then
`configure([maximized,activated])`. Waydroid then often destroyed the toplevel
within 10–100 ms and created a new one: three to four times per launch for
Clock and Jelly. After that, Android sometimes moved the task behind its
launcher (`topResumedActivity` = launcher3) and the window was gone.
The activated → deactivated → activated flip comes from the shell.

### Smaller findings

- **One new `wl_buffer` per frame.** The hwcomposer imports a fresh dmabuf for
  every frame (`zwp_linux_buffer_params_v1.create_immed`), attaches it and
  destroys it a few milliseconds later. It never asks for `wl_surface.frame`.
  In 148 s there were 18,188 `create_immed` calls and 1 `wl_buffer.release`.
  Each window is a 1×1 `wl_shm` parent scaled with `wp_viewport`, with
  per-layer dmabuf subsurfaces (ARGB8888, linear, stride 1484 for a 371×408
  app). Shortly after session start it also sent `wl_pointer.set_cursor(null)`
  about every 16 ms; the rate over longer periods wasn't measured.
- **Size and scale.** The shell configures 480×419 logical with a preferred
  fractional scale of 180 (1.5). Android ends up with a 720×628 display at
  density 270. In multi-window mode, apps open as freeform windows (371×408)
  centred on a black, maximised parent.
- **Android notifications reach the Hub.** Waydroid forwards them over the
  session bus: "Configure physical keyboard", from "Waydroid.android", turned
  up four times.
- **Launching "Waydroid" from the grid** runs `Waydroid.desktop`, so `waydroid`
  switches Android to full UI and closes the per-app windows. The shell then
  shows "Waydroid couldn't open – It didn't respond in time", although a
  `Waydroid` toplevel did map.
- **Android apps aren't in Marathon's grid** on r479. Waydroid writes
  `~/.local/share/applications/waydroid.<package>.desktop` with
  `NoDisplay=true`. (Commit 7b46f434 addresses this in the shell; it isn't on
  the device.)
- **Android is set to UTC.** Its clock showed 6:24 while Marathon showed 7:24.
- **Container networking is unreliable.** netd's legacy `iptables-restore`
  failed with "unable to initialize table 'filter'" because the container
  can't load `iptable_*` modules. Loading them on the host and restarting the
  session gave Android a route (ping 1.1.1.1, about 19 ms) once. A later
  session again had no default route, and Jelly showed
  `ERR_INTERNET_DISCONNECTED`. Not resolved.
- **Vulkan.** Waydroid's `gpu.py` has no `v3d` → `broadcom` mapping, so Android
  gets GLES only (Mesa, gbm gralloc on renderD128).
- **Image constraint (LUKS).** A reboot of this image stops at the PIN prompt
  for the encrypted data partition, and nobody can type it there remotely. My
  one reboot (18:05) waited there for an hour until the user entered the PIN.
  It didn't hang. I didn't turn the PIN encryption off.

### Items the user reported (19:33)

1. **Empty "Clock" card.** Android still listed the deskclock task in recents
   but it had no window, and the shell kept the card. In every window
   disappearance I captured on the wire (the logging relay below), the
   hwcomposer sent `xdg_toplevel.destroy` and then `wl_surface.destroy`. It
   never just stopped attaching buffers. That held for the churn, for
   container freeze (both Jelly toplevels destroyed at once), and for the
   full-UI switch. The shell still kept a "Waydroid" task after
   `xdg_toplevel.destroy` of its window (run 2, 108.2 s). The relay wasn't
   running for the 19:30 Clock launch, so that particular card isn't captured.
   It needs re-checking once the shell fixes are deployed.
2. **Lock screen showing the switcher through it.** Not reproduced. My
   injected input before 19:33: a tap at 19:24 (switcher card), a swipe
   (360,500)→(360,150) over 300 ms at 19:24, aimed at Android's keyguard, and
   a tap at (360,474) at 19:20. Nothing between 19:26 and 19:34. `shell.state`
   said `locked: false` every time I queried it (19:13–19:37). Whether a
   partial lock swipe can be left stuck hasn't been tested yet.

## How it was set up

### Install, by hand, until an image carries patch 0042

No `apk` on the device. Packages came from Alpine edge (main and community,
fetched 18 October), with the closure resolved on the host against the
device's `/lib/apk/db/installed`: waydroid 1.6.3-r0, waydroid-systemd,
lxc 7.0.0, lxc-libs, gbinder-python 1.3.1, libgbinder 1.1.54, libglibutil
1.0.83, dnsmasq 2.93 (and -common), iptables 1.8.13, libxtables, libnftnl,
nftables 1.1.7, py3-pyclip, xclip, and iproute2 7.2.0. iproute2 turned out not
to be needed: busybox 1.38 `ip` ran waydroid-net.sh's bridge commands in a
netns. The apks were unpacked into an empty directory, `sbin/` was moved under
`usr/` (`/sbin` is a symlink on the device), and the tree was sent with
`tar --owner=0 --group=0 --numeric-owner -cf - . | ssh root@… 'tar --keep-directory-symlink -xf - -C /'`.
dnsmasq's pre-install script was run by hand (`addgroup`/`adduser dnsmasq`).

```sh
waydroid init -s VANILLA        # lineage-20.0-20260927 system + MAINLINE vendor, 2.4 GB in /var/lib/waydroid/images
# /boot/cmdline.txt: add psi=1, reboot (lmkd needs /proc/pressure)
# as uid 1000, with XDG_RUNTIME_DIR=/run/user/1000 and the session bus:
WAYLAND_DISPLAY=marathon-wayland-0 waydroid session start
waydroid prop set persist.waydroid.multi_windows true    # the [properties] entry in waydroid.cfg was not applied by itself
waydroid app launch com.android.deskclock
waydroid show-full-ui
```

Before `psi=1`, Android's init aborted with "critical process 'lmkd' exited 4
times before boot completed": `CONFIG_PSI_DEFAULT_DISABLED=y` and no
`/proc/pressure`. The same gap disables the shell's PSI policy on this device.
`createProcessGroup … Read-only file system` is logged for every Android
service (the container sees cgroup read-only). It isn't fatal.

### Measurement tools

Scratch tools; not in the repo.

- **Wayland:** a logging relay (Python, forwards fds with `SCM_RIGHTS`,
  decodes messages using the protocol XML) on `$XDG_RUNTIME_DIR/wdproxy-0`.
  The session was started with `WAYLAND_DISPLAY=wdproxy-0`.
- **Frame pacing:** tracefs `drm/drm_vblank_event_delivered` during the
  flings, and `dumpsys gfxinfo <pkg>` (reset first).
- **Input:** the `/run/touch.fifo` touch injector (single contact).
- **Shell state:** keel-mcp `apps.running`, `shell.state` and `shell.switcher`.
- **Binder:** gbinder from Python against `waydroidplatform`.
- **Idle:** `cpu.stat` of `lxc.payload.waydroid`, per-task
  `voluntary/nonvoluntary_ctxt_switches`, `/proc/interrupts`.
- **Screenshots:** the shell's SIGUSR1 snapshot.

### Left on the device

- Waydroid and its dependencies installed in the root slot (gone after an OTA
  slot switch).
- Images and data in `/var/lib/waydroid` and `~user/.local/share/waydroid`.
- `psi=1` in `/boot/cmdline.txt`; the original is `/boot/cmdline.txt.pre-psi`.
- `/usr/lib/modules-load.d/marathon-waydroid.conf`.
- Android `screen_off_timeout` set to 1,800,000 ms.
- The Waydroid session stopped; `waydroid-container.service` idle.

## Image changes

- `packaging/pipeline-patches/0041-fix-pi-turn-PSI-on-Android-s-lmkd-needs-it.patch`:
  `psi=1` on both Pi cmdline copies.
- `packaging/pipeline-patches/0042-feat-hackberrypi-ship-stock-Waydroid.patch`:
  `waydroid` and `waydroid-systemd` on the HackberryPi image.
  `waydroid-container.service` is D-Bus activated by `waydroid session start`
  (seen on the device, not enabled), and Waydroid mounts binderfs at
  `/dev/binderfs` and allocates its binder nodes itself.
- `device-hackberrypi-cm5-marathon` r18: `modules-load.d/marathon-waydroid.conf`
  loads the iptables modules for netd.
- `waydroid init` (2.4 GB download) stays a step on the device.

No image was built with these changes. The patches apply to the cached
duranium tree, and bootstrap accepts it.
