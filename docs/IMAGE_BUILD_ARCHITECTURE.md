# Marathon image build architecture

How a clone of this repo becomes a bootable image, and why each device's
boot path looks the way it does. For a step-by-step build, see
[`BUILDING.md`](BUILDING.md).

## Summary

Every Marathon image is built by **one pipeline**: postmarketOS duranium
(mkosi) with Marathon's patch series applied, driven by
`scripts/build-image.sh`. Each device differs only in how its boot ROM
finds a kernel, which is handled after mkosi by duranium's
`scripts/build-image.py` (as patched) and by `mkosi.finalize`.

| Target | Boot chain | Disk layout after the build |
|---|---|---|
| `qemu-aarch64` | EDK2 UEFI → systemd-boot → UKI | GPT: FAT32 ESP + ext4 root |
| `purism-librem5` | BootROM → U-Boot (`phone-boot.img` at 33 KiB) → `boot.scr` → `vmlinuz` + `initramfs` + board DTB | GPT: ext4 boot at sector 4096 (512 MiB) + ext4 root |
| `pine64-pinephone` | BROM → U-Boot SPL at 8 KiB → `boot.scr` → `vmlinuz` + `initramfs` + `allwinner/<board>.dtb` | MBR: ext4 boot + ext4 root |
| `raspberry-pi5` (Pi 5, HackberryPi CM5) | Pi EEPROM → `config.txt` / `cmdline.txt` → `kernel_2712.img` + `initramfs_2712` | MBR: FAT32 boot (type 0x0c, bootable) + ext4 root |
| `oneplus-enchilada` (dormant) | Android bootloader → `boot.img` | GPT image flashed to `userdata` |

The earlier plan of a separate Raspberry Pi OS pipeline for the CM5, and of
an erofs + dm-verity `/usr`, is gone: patch 0008 replaced the `/usr` and
verity partitions with a single 5 GiB ext4 root (`pmOS_root`), and the Pi
boots from the same duranium build as everything else.

## Stages of `scripts/build-image.sh`

`scripts/build-image.sh <target>` (or a `build-<device>-image.sh` wrapper):

1. **Host check** — `scripts/qemu/lib/check-host.sh` (podman, qemu, EFI
   firmware, ...).
2. **Trees** — `scripts/qemu/lib/setup-trees.sh` runs
   `packaging/pipeline-patches/bootstrap.sh`, which clones duranium at the
   pinned commit, `git am`s the patch series, and clones a pinned mkosi.
   Default location `~/.cache/marathon-build/` (`MARATHON_BUILD_DIR`). It then
   rsyncs `scripts/qemu/duranium-overlay/` over the tree and sets the dev
   root password.
3. **Apks** — builds each Marathon aport into `mkosi.packages/` unless an
   apk with the aport's current `pkgver-pkgrel` is already there: `marathon-base-config`,
   `marathon-plymouth-theme`,
   `keel-silica`, `wpewebkit`, `pacific`, `shoal-pilotd`, `shoal-pilot`,
   `keel-mcp`, `marathon-shell`, `postmarketos-ui-marathon`, then the
   target's `device-<target>-marathon` overlay and any `*-marathon` kernel
   or U-Boot fork it depends on. Pi targets also fetch the pinned
   `linux-rpi` 6.12.85 apks. `FORCE_REBUILD=1` drops the cache.
4. **Bake** — `python3 scripts/build-image.py device-<target> ui-marathon`
   in the duranium tree: mkosi, then the per-device disk rebuild below.
5. **Post-bake** — prune old split artifacts; extract `phone-boot.img`
   (Librem 5) or `boot.img` (OnePlus 6) next to the image for the flash
   scripts. `--boot` / `--verify` / `--boot-only` boot the QEMU image.

Images land in
`~/.cache/marathon-build/duranium/mkosi.output/<target>_marathon_edge/`.

Raw `mkosi build` skips step 4's disk rebuild, and the result will not boot
on a Librem 5, PinePhone or Pi.

## What the patches change

The duranium tree is generated; Marathon's changes to it live only in
`packaging/pipeline-patches/` (33 patches, 0001–0034, no 0011; index in
[`../packaging/pipeline-patches/README.md`](../packaging/pipeline-patches/README.md)).
The main groups:

- **Base image** — mail OAuth helper, avahi hostname, sshd and keys via
  `/usr/share/factory`, Plymouth in the initrd, local apk trust, Pacific as
  the web handler, store handler units, factory shell settings.
- **Device overlays** — Marathon's `device-*-marathon` and
  `linux-*-marathon` aports are synced into pmaports for each build (0013,
  0018); the HackberryPi overlay is layered on the Pi 5 overlay (0010, 0029).
- **U-Boot script devices** (Librem 5, PinePhone) — `Bootloader=uki` in
  `mkosi-configure.py`; `mkosi.finalize` restores `vmlinuz`, runs
  `mkinitfs` in the image for a real initramfs (the UKI initrd holds only
  modules), stashes `/etc` for first boot, compiles the device's
  `marathon-boot.cmd` into `boot.scr`; `build-image.py` rebuilds the disk
  with the U-Boot blob at its ROM offset (0012, 0014, 0015, 0018, 0022,
  0023, 0030).
- **Raspberry Pi** — `Bootloader=uki`; `mkosi.finalize` writes
  `cmdline.txt` (with `cgroup_enable=memory` and
  `pmos.force-partition-resize`) and stages `kernel_2712.img` and a plain
  cpio `initramfs_2712`; `build-image.py` converts the GPT to a pure MBR
  laid out as Raspberry Pi OS does (0008, 0009, 0030–0033).

## Device-specific runtime configuration

The image's device knowledge comes from the overlay aport, not from the
pipeline: `/etc/marathon/device-profile.conf` (generated from the device's
`devices/<vendor>/<codename>/device.toml`), greetd and logind config, udev
rules, firmware and kernel dependencies. See
[`DEVICE_OVERLAYS.md`](DEVICE_OVERLAYS.md).

## Status

| Target | Builds | Boots on hardware |
|---|---|---|
| QEMU | yes | yes (virgl) |
| Librem 5 | yes | yes |
| PinePhone | yes | yes, to OOBE and the shell |
| HackberryPi CM5 | yes | yes |
| OnePlus 6 | wired up, not exercised recently | unverified |

## References

- [Introducing Duranium](https://postmarketos.org/blog/2026/03/17/introducing-duranium/)
- [Librem 5 on the postmarketOS wiki](https://wiki.postmarketos.org/wiki/Purism_Librem_5_(purism-librem5))
- [PinePhone on the postmarketOS wiki](https://wiki.postmarketos.org/wiki/PINE64_PinePhone_(pine64-pinephone))
- [Librem 5 U-Boot docs](https://docs.u-boot.org/en/latest/board/purism/librem5.html)
