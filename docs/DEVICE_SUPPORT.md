# Marathon OS Device Support

Which devices Marathon builds for, what each one needs, and where to start a
new port. The mechanics of overlays and `DeviceProfile` are in
[`DEVICE_OVERLAYS.md`](DEVICE_OVERLAYS.md); the boot chains are in
[`IMAGE_BUILD_ARCHITECTURE.md`](IMAGE_BUILD_ARCHITECTURE.md).

## Model

The shell, the app runners and `marathon-base-config` are the same on every
device. What Marathon knows about a device is in its manifest,
`devices/<vendor>/<codename>/device.toml`, with the facts its SoC shares in
`socs/<soc>.toml`: status, build target and scripts, boot method, kernel and
pinned binaries, display, input, modem/GPS/sensors, firmware, GPU stack and
the device profile. `tools/devices/devices.py check` (the `Devices_Check`
ctest) validates them against their schemas and against the aports and the
shell; see [`DEVICE_OVERLAYS.md`](DEVICE_OVERLAYS.md#device-manifests-the-source-of-truth).
The manifests are the source of truth: when this page and a manifest
disagree, the manifest wins.

Each device's files are in one overlay aport,
`packaging/packages/device-<vendor>-<codename>-marathon`, which depends on the
upstream pmaports `device-*` package and Marathon's runtime stack, and ships:

- `/etc/marathon/device-profile.conf` — traits the shell reads through
  `DeviceProfile` (GPU stack, GLES level, MSAA, DPI, brightness floor, CPU
  governor, call audio, ...), generated from the manifest when the overlay is
  built;
- greetd and logind configuration, udev rules, firmware dependencies;
- a kernel or U-Boot fork as a dependency when upstream's is not good enough;
- for U-Boot devices, `marathon-boot.cmd`, compiled into `boot.scr` at build
  time.

`scripts/build-image.sh <target>` builds the overlay for that target (and any
`*-marathon` fork it depends on) and bakes the image.

## Devices

| Device | Manifest | Target | Overlay | SoC / GPU | Kernel | Status |
|---|---|---|---|---|---|---|
| Purism Librem 5 | `purism/librem5` | `purism-librem5` | `device-purism-librem5-marathon` | `imx8mq`: Vivante GC7000L, etnaviv GLES2 (optional Vivante blobs) | `linux-purism-librem5-marathon` 6.6 | primary |
| HackberryPi CM5 | `hackberrypi/cm5` | `raspberry-pi5` + CM5 layer | `device-hackberrypi-cm5-marathon` on `device-raspberry-pi5-marathon` | `bcm2712`: VideoCore VII, v3d | `linux-rpi` 6.12.85 (pinned) | primary |
| PINE64 PinePhone | `pine64/pinephone` | `pine64-pinephone` | `device-pine64-pinephone-marathon` | `sun50i-a64`: Mali-400, lima GLES2 | `linux-postmarketos-allwinner-marathon` 6.18, `u-boot-pinephone-marathon` | working: boots to OOBE and the shell |
| Raspberry Pi 5 / CM5 | `raspberry/pi5` | `raspberry-pi5` | `device-raspberry-pi5-marathon` | `bcm2712`: v3d | `linux-rpi` 6.12.85 (pinned) | bring-up: base for the CM5 layer; bare-board HDMI not validated |
| QEMU aarch64 | `qemu/aarch64` | `qemu-aarch64` | none (base image only) | `qemu-virt`: virtio-gpu-gl (virgl) | upstream | working: developer simulator |
| OnePlus 6 | `oneplus/enchilada` | `oneplus-enchilada` | `device-oneplus-enchilada-marathon` | `sdm845`: Adreno 630 | `linux-marathon` (SDM845) | dormant: kept, not maintained or tested |

### Librem 5

- Boot: U-Boot `phone-boot.img` at byte 33 KiB, `boot.scr` on an ext4 boot
  partition at sector 4096. Flash with `scripts/flash/flash-librem5.sh`
  (`sd` or `emmc` via uuu).
- `GPU_MSAA=0`: etnaviv cannot do FBO MSAA at a usable frame rate.
- The overlay carries the speaker-over-HDMI WirePlumber rule, the modem
  wakeup and Wi-Fi rfkill rules, Wi-Fi recovery, the cellular connection
  profile and GPU stack selection (`marathon-gpu-select`).
- Recovery: `packaging/scripts/setup-librem5-recovery.sh`;
  [`LIBREM5_RECOVERY.md`](LIBREM5_RECOVERY.md).

### PinePhone

- Boot: pure MBR, U-Boot SPL at 8 KiB, `boot.scr` loading the board DTB from
  `allwinner/` on the ext4 boot partition. Build with
  `scripts/build-pinephone-image.sh`; flash with
  `scripts/flash/flash-pinephone.sh /dev/sdX`, to a microSD card or to the
  eMMC that JumpDrive exposes. The phone tries the microSD first.
- Kernel and U-Boot forks carry the A64 watchdog and lockup detection and a
  TF-A PSCI fix; call audio goes through `pinephone-callaudiod-marathon`.

### HackberryPi CM5 and Raspberry Pi 5

- Boot: Pi EEPROM reads a FAT32 boot partition (MBR type 0x0c) with
  `config.txt`, `cmdline.txt`, `kernel_2712.img` and `initramfs_2712`. The
  root partition grows to fill the card on first boot.
- The HackberryPi layer adds the HyperPixel 4 Square 720x720 panel and touch
  (device tree overlay), the physical keyboard, the fuel gauge, the
  speaker service and `usercfg-hackberrypi.txt`. Its profile sets
  `FORCE_DPI=254` and `PANEL_DEPTH=6` (dithered 6-bit panel), keeps the
  screen on (`SCREEN_TIMEOUT_MS=0`) and wakes on a key press.
- Build with `scripts/build-hackberry-cm5-image.sh`; flash with
  `scripts/flash/flash-hackberry-cm5.sh`. A bare Pi 5 / CM5 board is
  `scripts/build-image.sh raspberry-pi5`.

### QEMU

`scripts/build-qemu-image.sh --boot` boots the image with GL, as a GTK window
or on VNC `127.0.0.1:5905`; SSH on port 2233. The default panel is 720x1440
(`MARATHON_QEMU_WIDTH` / `MARATHON_QEMU_HEIGHT`).

### OnePlus 6

`scripts/build-oneplus6-image.sh` and `scripts/flash/flash-oneplus6.sh`
(fastboot) still exist, and `packaging/devices/` holds its kernel-config
fragment, but the overlay has not changed since the 2026-09 merge and recent
images are untested.

## Adding a device

Follow the checklist in
[`DEVICE_OVERLAYS.md`](DEVICE_OVERLAYS.md#checklist-adding-a-new-device).
In short:

1. The device must boot postmarketOS with a mainline-style kernel, DRM/KMS
   display, a Mesa GLES 2.0+ driver and working touch or keyboard.
2. Write `devices/<vendor>/<codename>/device.toml` (and `socs/<soc>.toml`
   for a new SoC), then add `packaging/packages/device-<vendor>-<codename>-marathon`;
   its `device-profile.conf` is generated from the manifest. Prefer runtime
   probing; never add device names to shell code.
3. If the boot ROM needs something mkosi's default layout cannot give it,
   add a numbered pipeline patch (see the Librem 5, PinePhone and Pi patches
   in [`../packaging/pipeline-patches/README.md`](../packaging/pipeline-patches/README.md)).
4. Build with `scripts/build-image.sh <target>`; add a
   `scripts/build-<device>-image.sh` wrapper once it works, and name it in the
   manifest.

## Minimum hardware

- ARM64 CPU, 2 GB RAM or more
- GPU with an OpenGL ES 2.0 Mesa driver
- Touch screen or keyboard and pointer
- Wi-Fi or Ethernet for app installs
