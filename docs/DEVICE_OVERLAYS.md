# Device Overlays & Porting Guide

How Marathon supports many devices from one shell binary and one image
pipeline, and the exact checklist for adding a new one.

## The principle

**Device-specific hardware knowledge lives in per-device manifests and
overlays, never in the core.** The shell binary, the app runners, and
`marathon-base-config` are device-agnostic. Anything that differs between a
Librem 5, a Pi 5, a QEMU VM, or the next device is described in that device's
manifest (`devices/<vendor>/<codename>/device.toml`, see below), shipped by
its overlay, and consumed through one of three seams:

1. **Runtime probing** (preferred where possible) — the shell discovers power
   keys, haptics, backlight, sensors, rfkill, modem, and the cpufreq policy by
   enumerating `/proc`, `/sys`, and D-Bus. No device names in code.
2. **`/etc/marathon/device-profile.conf`** (`DeviceProfile`, see below) — the
   traits the shell *cannot* reliably probe before it needs them (GPU driver
   stack, GLES level, framebuffer alpha, HW MSAA, panel brightness floor, CPU
   governor policy, render node). Generated from the manifest's `[profile]`
   when the overlay is built; never edited by hand.
3. **The device overlay aport** `packaging/packages/device-<vendor>-<codename>-marathon`
   — ships the device's udev rules, DT overlays, boot config, firmware
   (`depends=`), service drop-ins, kernel fork, and the generated
   `device-profile.conf`.

## Device manifests (the source of truth)

```
devices/device.schema.json            JSON Schema for device.toml
devices/<vendor>/<codename>/device.toml
socs/soc.schema.json                  JSON Schema for <soc>.toml
socs/<soc>.toml                       facts shared by every board on a SoC
tools/devices/devices.py              checker and generator
```

`<vendor>-<codename>` is the device's `id`: the postmarketOS device name the
pipeline keys on and `DEVICE_ID` in its profile. The overlay is
`device-<id>-marathon`. A manifest records the device's status (`primary`,
`working`, `bring-up`, `dormant`), build target, wrapper and flash scripts,
mkosi bootloader, boot method and loader offset, kernel (and any binary apks
pinned by SHA-512), display (resolution, DPI, panel depth, quirks), input,
modem/GPS/sensors, firmware packages, and the `[profile]`
keys its `device-profile.conf` ships. Comments in the TOML carry the reasons.

A SoC file lists the GPU, each GPU stack a board may run (driver, the highest
ES version the shell may ask for, whether MSAA is usable) and `[profile]`
defaults its boards inherit; a device's own profile keys win. Keys in neither
are left out of the conf and keep the shell's built-in default.

```
python3 tools/devices/devices.py check                         # validate (Devices_Check ctest)
python3 tools/devices/devices.py profile device-<id>-marathon  # print the generated conf
python3 tools/devices/devices.py pins <target>                 # binary pins for a build target
```

`scripts/qemu/lib/build-device-marathon-apk.sh` writes the generated
`device-profile.conf` into the aport before `abuild` runs. The APKBUILD lists
it in `source=` and keeps its sha512; the checker fails when that sum is stale,
which is the reminder to bump the overlay's `pkgrel` (`build-image.sh` reuses a
cached apk whose pkgver-pkgrel matches). `scripts/build-image.sh` downloads the
target's `kernel.pins` and refuses any that fail their SHA-512.

Besides the schemas, `devices.py check` enforces:

- path, `id` and package name agree, and every `device-*-marathon` aport has a
  manifest;
- the wrapper builds the manifest's target, and the wrapper and flash scripts
  exist;
- kernel and firmware versions match in-tree APKBUILDs;
- `profile.gpu_stack` is one of the SoC's stacks, `gles_level` is within the
  stack's ceiling, and `gpu_msaa` is 0 on a stack without usable MSAA (the
  etnaviv trap: `layer.samples: 4` renders at ~2 fps on the GC7000Lite);
- a panel under 8 bits per channel sets `panel_depth`, so the shell dithers;
- `display.scale_dpi` is what `profile.force_dpi` or the overlay's greetd
  `MARATHON_FORCE_DPI` sets;
- the schema's profile keys are exactly the keys `DeviceProfile` and
  `marathon-shell-session` read, so a new shell key needs a schema entry.

The layout follows Luma's `devices/<vendor>/<codename>` + `socs/` +
`tools/check-devices.py` ([SimplyLuma/luma](https://github.com/SimplyLuma/luma)).

If you find yourself writing `if (device == "...")` in C++/QML, stop — the
answer is a runtime probe or a `DeviceProfile` field.

## DeviceProfile (the shell seam)

`crates/marathon-shell-native/src/device.rs` — read once, early in `main()`
(before `QGuiApplication`, so it can decide the default `QSurfaceFormat`);
C++ calls `marathon::device::profile()`. QML sees the keys it needs as the
`DeviceProfile` context property.

Every field resolves with the precedence:

```
built-in default   <   /etc/marathon/device-profile.conf   <   MARATHON_* env
```

The built-in defaults deliberately equal the historical Librem 5 constants, so
a device with **no** profile file behaves exactly as Marathon did before this
abstraction existed. `MARATHON_DEVICE_PROFILE=<path>` overrides the file
location (for host testing).

| Conf key | Env override | Default | Meaning |
|---|---|---|---|
| `DEVICE_ID` | `MARATHON_DEVICE_ID` | `generic` | Log/telemetry id |
| `GPU_STACK` | `MARATHON_GPU_STACK` | `mesa-etnaviv` | `mesa-etnaviv` \| `vivante-blob` \| `mesa-lima` \| `mesa-v3d` \| `mesa-virgl` \| `mesa-freedreno` \| `llvmpipe` |
| `GLES_LEVEL` | `MARATHON_GLES_VERSION` | `2.0` | ES context version for the default surface |
| `SURFACE_ALPHA` | `MARATHON_SURFACE_ALPHA` | `0` | 1 if the CRTC framebuffer has an alpha channel (ARGB); 0 for XRGB (i.MX8 LCDIF) |
| `GPU_MSAA` | `MARATHON_LAYER_SAMPLES` | `0` | Max HW FBO sample count (0 = none) |
| `GPU_RGBA16F` | `MARATHON_GPU_HDR` | `0` | HDR/RGBA16F capable |
| `PANEL_DITHER` | `MARATHON_PANEL_DITHER` | `1` | Overlay dither noise on the wallpaper; needed on 18 bpp panels, 0 on 24 bpp panels saves a full-screen blended layer |
| `RENDER_NODE` | `MARATHON_RENDER_NODE` | `/dev/dri/renderD128` | DRM render node for dmabuf |
| `CPU_GOVERNOR` | `MARATHON_CPU_GOVERNOR` | `ondemand` | Balanced-mode governor |
| `BRIGHTNESS_FLOOR` | `MARATHON_BRIGHTNESS_FLOOR` | `0.28` | Min visible backlight duty cycle |
| `RUNNER_WIDTH` | `MARATHON_APP_WIDTH` | `540` | Initial app-runner canvas width (logical px) |
| `RUNNER_HEIGHT` | `MARATHON_APP_HEIGHT` | `1140` | Initial app-runner canvas height (logical px) |
| `PANEL_DPI` | `MARATHON_PANEL_DPI` | `0` | True panel DPI, used for the physical size the compositor advertises on `wl_output` (what Wayland clients such as Pacific scale web content by); 0 = the screen's reported size |
| `NATIVE_SCALE` | `MARATHON_NATIVE_SCALE` | `0` | Wayland scale for native (GTK/Qt/Flatpak) apps at the default interface size; 0 = DPI/160. See `docs/NATIVE_APP_SCALE.md` |
| `DOZE_DPMS` | `MARATHON_DOZE_DPMS` | `1` | Doze powers the display pipeline down (CRTC `ACTIVE=0`); `0` blanks the backlight only, for panels that don't recover from a stopped pixel stream (HyperPixel on RP1 DPI) |
| `WIFI_POWERSAVE` | `MARATHON_WIFI_POWERSAVE` | `1` | Doze turns on Wi-Fi power save (`iw ... power_save on`); `0` leaves it off |
| `SCREEN_TIMEOUT_MS` | `MARATHON_SCREEN_TIMEOUT_MS` | `300000` | Default idle screen-off timeout until the user picks one; `0` = never (devices whose power key is out of reach, like the HackberryPi) |
| `WAKE_ON_KEY` | `MARATHON_WAKE_ON_KEY` | `0` | `1` = any key on a physical keyboard wakes a blanked screen (not delivered to apps, doesn't unlock); for keyboard handhelds whose power key is hard to reach |
| `RUNNER_POOL` | `MARATHON_RUNNER_POOL` | `1` | Warm spare app runners (~150–220 MB RSS each). `1` keeps one, in the sandbox (with or without the media folders) most recent launches needed; `2` keeps one of each, so every Marathon app but the WebEngine ones starts warm; `0` none |
| `PANEL_DEPTH` | `MARATHON_PANEL_DEPTH` | `8` | Bits per colour channel the panel shows; below 8 the shell dithers the whole frame (the HackberryPi's RP1 DPI is wired BGR666 and doesn't dither) |
| `TOUCH_FILTER` | `MARATHON_TOUCH_FILTER` | `0` | The shell reads touchscreens with Qt's evdevtouch on its own thread (libinput ignores them, `71-marathon-touch.rules`) and applies each report as it comes, without Qt Quick's touch compression. `1` smooths them with evdevtouch's Kalman filter, one point a frame: even steps, about 60 ms more lag |
| `TOUCH_PARAMS` | `MARATHON_TOUCH_PARAMS` | empty | Extra evdevtouch parameters for a panel whose touch axes don't match the display, colon-separated: `rotate=90\|180\|270`, `invertx`, `inverty`, `prediction=<ms>` |
| `FORCE_DPI` | `MARATHON_FORCE_DPI` | unset | Read by marathon-shell-session; pins the shell's DPI and so its scale factor (= DPI/160) |

A manifest's `[profile]` writes each key in lower case with TOML types
(`gpu_msaa = 4`, `doze_dpms = false`); `DEVICE_ID` is the manifest's `id`.
Adding a key to the shell means adding it to `devices/device.schema.json`
too, or `Devices_Check` fails.

## The image seam (build-time selection)

Device selection is package-driven (see `~/.cache/marathon-build/duranium/` and
`packaging/`):

1. `build-image.py device-<name> ui-<name>` → `PMOS_DEVICE=<name>`.
2. `mkosi-configure.py` injects the `device-<name>-marathon` overlay aport
   into the image **iff** a matching `.apk` exists in `mkosi.packages/`, sets
   `Bootloader=`, pins the kernel, and handles layer-2 nesting (e.g. CM5 under
   Pi5).
3. Each overlay's `APKBUILD package()` installs its files to fixed rootfs
   paths — this is the real "overlay directory."
4. `build-image.py` + `mkosi.finalize` do post-build disk/boot surgery keyed on
   the `PMOS_DEVICE` prefix (GPT rebuild + `phone-boot.img` for L5, MBR + Pi
   firmware composer for Pi).

The GPU driver stack is one dimension of the overlay: a device declares
`profile.gpu_stack` in its manifest (one of its SoC's `gpu.stacks`) and pulls
the matching driver bits
(Mesa packages by default; for `vivante-blob`, an extra `*-vivante-blobs` aport
+ the galcore kernel module via the device kernel fork's `depends=`).

### GPU driver arbitration on the Librem 5 (etnaviv ↔ Vivante galcore)

The GC7000Lite can be bound by **either** the open `etnaviv` DRM driver **or**
NXP's proprietary Vivante `galcore` module — never both; they claim the same
hardware. The L5 overlay arbitrates at boot:

- **Kernel**: `CONFIG_DRM_ETNAVIV=m` (not `=y`) in
  `config-purism-librem5.aarch64`, so etnaviv can be prevented from binding.
  `galcore.ko` is built out-of-tree by `linux-purism-librem5-marathon` and
  shipped in `modules/<kver>/extra/` (never auto-loaded).
- **`/etc/modprobe.d/marathon-gpu.conf`**: `blacklist etnaviv` +
  `blacklist galcore` — udev must not race either driver onto the GPU.
- **`marathon-gpu-select.service`** (oneshot, `Before=greetd`): runs
  `marathon-gpu-select.sh`, which reads `GPU_STACK` from `device-profile.conf`
  (kernel cmdline `marathon.gpu=<stack>` overrides for recovery) and
  `modprobe`s exactly one driver. `vivante-blob` loads galcore and verifies
  `/dev/galcore`; **anything else, or any galcore failure, falls back to
  `modprobe etnaviv`.**
- **Safety contract (anti-wedge)**: the display controllers (`mxsfb` /
  `imx-dcss`, both `=y`) are separate hardware and come up at kernel init
  regardless of the GPU driver, so even total GPU-driver failure degrades to
  software render on a working panel — never an unwakeable phone.

Because etnaviv is now a late-loaded module, the DRM **card index** it lands on
is no longer fixed (mxsfb/dcss, being built-in, register first). The eglfs KMS
config therefore selects the display by **stable by-path symlink**
(`/dev/dri/by-path/platform-30320000.lcd-controller-card`), not `cardN`. The
etnaviv **render node** stays `renderD128` (etnaviv is the only render-capable
driver, so it is always the first/only `renderD1NN` regardless of card index),
so `RENDER_NODE` needs no change. galcore does not use the DRM render-node
model at all (it exposes `/dev/galcore`), so `RENDER_NODE` is inert under
`vivante-blob`.

Bring-up is staged: bake/flash with `GPU_STACK=mesa-etnaviv` first (proves the
`=m` + selector restructure is behaviour-neutral), then set
`gpu_stack = "vivante-blob"` (and its `gles_level`) in
`devices/purism/librem5/device.toml` once galcore + the blob userspace are
validated in isolation.

## Checklist: adding a new device

1. **Write the manifest** `devices/<vendor>/<codename>/device.toml` (copy the
   closest device; `<vendor>-<codename>` is the pmOS device name), and
   `socs/<soc>.toml` if the SoC is new. Put the device's traits in `[profile]`
   (table above), only where they differ from the SoC's and the shell's
   defaults, with the reason in a comment. Start at `status = "bring-up"`.
2. **Create the overlay aport** `packaging/packages/device-<vendor>-<codename>-marathon/`:
   - `APKBUILD` (copy an existing one; set `pkgname`, `depends=` for firmware +
     any GPU-blob subpackage + kernel fork). If the manifest has a
     `[profile]`, list `device-profile.conf` in `source=`, install it to
     `/etc/marathon/device-profile.conf`, and put the sha512 that
     `devices.py check` reports in `sha512sums=`. Don't check the file in.
   - udev rules, DT overlay(s), boot config, service drop-ins as needed.
   - A greetd drop-in if Qt needs device-specific env (KMS device pinning,
     `QT_QPA_EGLFS_INTEGRATION`, GPU library path).
   - A modem without its own manager (unlike eg25-manager on the PinePhone):
     link `marathon-modem-sleep.service` into `sleep.target.wants`, as the
     Librem 5 does (`docs/BACKGROUND_WORK.md`).
3. **Kernel**: reuse a mainline kernel if the SoC is upstream; else add a
   `linux-<vendor>-<model>-marathon` fork (precedent: the L5 fork with the
   RS9116 out-of-tree patch).
4. **Partition/boot**: add a `mkosi.repart.<device>/` if the layout differs,
   and a `mkosi.finalize` branch + `build-image.py` disk-surgery branch if the
   device needs raw-kernel boot composition.
5. **Register selection**: ensure `mkosi-configure.py` recognises the device
   (bootloader type, kernel pin) and that its overlay `.apk` lands in
   `mkosi.packages/`.
6. **Build + boot test**: add `scripts/build-<device>-image.sh` (and a flash
   script under `scripts/flash/`) and name them in the manifest's `[build]`.
   Build, then boot (QEMU first if the SoC is emulated; otherwise flash to
   hardware). Confirm the shell reaches the lock screen with the expected
   traits (scale, panel depth, GPU stack), then move the manifest's `status`
   on.
7. **Verify no core leak**: `grep -rni "<soc>\|<vendor>" shell/ apps/` should
   return only comments — any live branch is a bug; move it to a probe or a
   `DeviceProfile` field.

## Anti-leak rules

- No hardware constant in the shell that isn't either runtime-probed or a
  `DeviceProfile` field.
- No device-specific env in global `marathon-base-config` — GPU driver env, CPU
  governor, and I/O scheduler tuning belong in the device overlay (or are
  derived from `DeviceProfile`).
- `packaging/devices` is a **dead** pmbootstrap-era path not used by
  the mkosi build; do not add to it. The `scripts/build-rootless*.sh` and
  `packaging/configs/` halves of that path are gone; `packaging/devices/` is
  retained only because `packages/linux-marathon/APKBUILD` still reads it. It is
  unrelated to the top-level `devices/` manifests.
