# Device Overlays & Porting Guide

How Marathon supports many devices from one shell binary and one image
pipeline, and the exact checklist for adding a new one.

## The principle

**Device-specific hardware knowledge lives in per-device overlays, never in
the core.** The shell binary, the app runners, and `marathon-base-config` are
device-agnostic. Anything that differs between a Librem 5, a Pi 5, a QEMU VM,
or the next device is declared in that device's overlay and consumed through
one of three seams:

1. **Runtime probing** (preferred where possible) — the shell discovers power
   keys, haptics, backlight, sensors, rfkill, modem, and the cpufreq policy by
   enumerating `/proc`, `/sys`, and D-Bus. No device names in code.
2. **`/etc/marathon/device-profile.conf`** (`DeviceProfile`, see below) — the
   declarative source of truth for traits the shell *cannot* reliably probe
   before it needs them (GPU driver stack, GLES level, framebuffer alpha, HW
   MSAA, panel brightness floor, CPU governor policy, render node).
3. **The device overlay aport** `packages/device-<vendor>-<model>-marathon` —
   ships the device's udev rules, DT overlays, boot config, firmware
   (`depends=`), service drop-ins, kernel fork, and its `device-profile.conf`.

If you find yourself writing `if (device == "...")` in C++/QML, stop — the
answer is a runtime probe or a `DeviceProfile` field.

## DeviceProfile (the shell seam)

`shell/src/managers/deviceprofile.{h,cpp}` — a process-lifetime singleton
loaded once, early in `main()` (before `QGuiApplication`, so it can decide the
default `QSurfaceFormat`). Also a QML singleton (`MarathonOS.Shell`,
`DeviceProfile`).

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
| `GPU_STACK` | `MARATHON_GPU_STACK` | `mesa-etnaviv` | `mesa-etnaviv` \| `vivante-blob` \| `mesa-v3d` \| `mesa-virgl` \| `llvmpipe` |
| `GLES_LEVEL` | `MARATHON_GLES_VERSION` | `2.0` | ES context version for the default surface |
| `SURFACE_ALPHA` | `MARATHON_SURFACE_ALPHA` | `0` | 1 if the CRTC framebuffer has an alpha channel (ARGB); 0 for XRGB (i.MX8 LCDIF) |
| `GPU_MSAA` | `MARATHON_LAYER_SAMPLES` | `0` | Max HW FBO sample count (0 = none) |
| `GPU_RGBA16F` | `MARATHON_GPU_HDR` | `0` | HDR/RGBA16F capable |
| `RENDER_NODE` | `MARATHON_RENDER_NODE` | `/dev/dri/renderD128` | DRM render node for dmabuf |
| `CPU_GOVERNOR` | `MARATHON_CPU_GOVERNOR` | `ondemand` | Balanced-mode governor |
| `BRIGHTNESS_FLOOR` | `MARATHON_BRIGHTNESS_FLOOR` | `0.28` | Min visible backlight duty cycle |
| `RUNNER_WIDTH` | `MARATHON_APP_WIDTH` | `540` | Initial app-runner canvas width (logical px) |
| `RUNNER_HEIGHT` | `MARATHON_APP_HEIGHT` | `1140` | Initial app-runner canvas height (logical px) |

## The image seam (build-time selection)

Device selection is package-driven (see `~/duranium-build/duranium/` and
`Marathon-Image/`):

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
`GPU_STACK` in its `device-profile.conf` and pulls the matching driver bits
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
`=m` + selector restructure is behaviour-neutral), then flip
`GPU_STACK=vivante-blob` once galcore + the blob userspace are validated in
isolation.

## Checklist: adding a new device

1. **Create the overlay aport** `Marathon-Image/packages/device-<vendor>-<model>-marathon/`:
   - `APKBUILD` (copy an existing one; set `pkgname`, `depends=` for firmware +
     any GPU-blob subpackage + kernel fork).
   - `device-profile.conf` — declare the device's traits (table above). Start
     from the base-config default and change only what differs.
   - udev rules, DT overlay(s), boot config, service drop-ins as needed.
   - A greetd drop-in if Qt needs device-specific env (KMS device pinning,
     `QT_QPA_EGLFS_INTEGRATION`, GPU library path).
2. **Kernel**: reuse a mainline kernel if the SoC is upstream; else add a
   `linux-<vendor>-<model>-marathon` fork (precedent: the L5 fork with the
   RS9116 out-of-tree patch).
3. **Partition/boot**: add a `mkosi.repart.<device>/` if the layout differs,
   and a `mkosi.finalize` branch + `build-image.py` disk-surgery branch if the
   device needs raw-kernel boot composition.
4. **Register selection**: ensure `mkosi-configure.py` recognises the device
   (bootloader type, kernel pin) and that its overlay `.apk` lands in
   `mkosi.packages/`.
5. **Build + boot test**: `build-image.py device-<name> ui-shell`, then boot
   (QEMU first if the SoC is emulated; otherwise flash to hardware). Confirm the
   shell reaches the lock screen and the `[DeviceProfile]` log line reports the
   expected traits.
6. **Verify no core leak**: `grep -rni "<soc>\|<vendor>" shell/ apps/` should
   return only comments — any live branch is a bug; move it to a probe or a
   `DeviceProfile` field.

## Anti-leak rules

- No hardware constant in the shell that isn't either runtime-probed or a
  `DeviceProfile` field.
- No device-specific env in global `marathon-base-config` — GPU driver env, CPU
  governor, and I/O scheduler tuning belong in the device overlay (or are
  derived from `DeviceProfile`).
- `Marathon-Image/{devices,configs,scripts/build-rootless*.sh}` are a **dead**
  pmbootstrap-era path not used by the mkosi build; do not add to them (their
  `configs/udev.rules.d/` copies have already diverged from the packaged ones).
