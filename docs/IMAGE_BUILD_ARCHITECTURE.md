# Marathon image build architecture

How Marathon-Shell turns a clone into a bootable image, and why the
device-specific scripts look the way they do. Written 2026-05-20 after
a deep audit corrected several wrong assumptions.

## The one-line summary

Marathon ships **two image formats** to **four target classes**:

1. **duranium** (postmarketOS mkosi + systemd-boot + erofs+verity GPT
   disk image) for QEMU (UEFI directly), fastboot Android phones
   (via u-boot's UEFI emulation), and uuu i.MX phones (also via
   u-boot's UEFI emulation).
2. **raspios-style** (Raspberry Pi firmware + FAT32 boot + ext4
   rootfs) for the HackberryPi CM5 — because the CM5's HyperPixel
   DPI panel requires a config.txt-driven overlay applied at
   firmware stage, which is fundamentally incompatible with
   duranium's systemd-boot chain.

## Why duranium, not pmbootstrap

`feedback_duranium_primary.md` is the project rule. The reasoning:

- erofs+verity gives integrity-checked, atomically-updated /usr
- systemd-boot + UKI is the modern Linux boot story
- mkosi composes well with our existing apk overlay
- duranium upstream actively CI-builds OnePlus 6, OnePlus 6T,
  FairPhone 5, and Pixel 3a phones (see
  `duranium-build/duranium/.ci/config.py`)

pmbootstrap is the older path. It produces split boot.img + rootfs.img
artifacts, but isn't immutable, doesn't have verity, and isn't where
postmarketOS is investing. We stay on duranium.

## How u-boot bridges duranium → phone

The trick that makes duranium work on Android phones is documented in
the introduction post (postmarketos.org/blog/2026/03/17/introducing-duranium/):

> "On phones, Duranium is installed to a GPT partition table embedded
> within the device's userdata partition, and U-Boot can boot from
> these subpartitions via the blkmap command."

So the flow on a fastboot phone like the OnePlus 6 is:

```
bootrom → Android boot partition → u-boot (Android-bootimg wrapped)
                                       ↓
                                       u-boot's blkmap reads
                                       the GPT inside userdata
                                       ↓
                                       u-boot's EFI loader runs
                                       systemd-boot from inner ESP
                                       ↓
                                       systemd-boot loads UKI from /boot
                                       ↓
                                       Linux + initramfs
                                       ↓
                                       Marathon
```

Two artifacts flash to the phone:

| Artifact | Where it lives | When you flash it |
|---|---|---|
| `boot.img` (extracted from `*.esp.raw`) | Android `boot` partition | **One time** — until u-boot is updated |
| `*.raw` (the GPT image) | Android `userdata` partition | **Every release** — sparse-converted via `img2simg` |

For the Librem 5 (uuu/SDP flash method) the same idea applies but
u-boot lives at sector 33 of the eMMC, written via `uuu`'s SDP path,
not flashed to a named partition.

## Per-device file map

```
scripts/
├── build-image.sh                  ← shared orchestrator
│   ├── stage 3: build local apks (qmf, shell, mail-oauth, …)
│   ├── stage 4: mkosi bake via duranium's build-image.py
│   └── stage 5 (per-device): extract artifacts the flash scripts need
│       ├── purism-librem5  → extract phone-boot.img from u-boot-librem5 apk
│       └── oneplus-enchilada → mcopy boot.img out of *.esp.raw via mtools
├── build-qemu-image.sh             ← wrapper, target=qemu-aarch64
├── build-oneplus6-image.sh         ← wrapper, target=oneplus-enchilada
├── build-librem5-image.sh          ← wrapper, target=purism-librem5
├── build-hackberry-pi-image.sh     ← refuses; pipeline doesn't exist
└── flash/
    ├── flash-oneplus6.sh           ← fastboot: boot.img + sparse(rootfs)
    ├── flash-librem5.sh            ← sd (dd) or emmc (uuu via SDP)
    └── flash-hackberry-pi.sh       ← refuses; see header for blockers
```

## How `mkosi.repart` shapes the artifacts

Duranium's mkosi config (`duranium-build/duranium/mkosi.conf`) hardcodes:

```
[Output]
Format=disk
SplitArtifacts=partitions,uki

[Content]
Bootable=yes
Bootloader=systemd-boot
UnifiedKernelImages=unsigned
```

That gives us, per build, alongside the consolidated `.raw`:

| Output | What | We use it for |
|---|---|---|
| `*.raw` | full GPT disk image | flash to `userdata` on phones; whole-disk dd on Librem 5 SD; QEMU `-drive` |
| `*.esp.raw` | EFI System Partition (FAT32, 1G) | extract OP6's `boot.img-<kver>` via mtools |
| `*.usr-arm64.<hash>.raw` | erofs /usr image | sysupdate atomic /usr swap |
| `*.usr-arm64-verity.<hash>.raw` | dm-verity hashes | verity integrity check at boot |
| `*.efi` | UKI (unified kernel image) | systemd-boot loads this |

The ESP gets `CopyFiles=/boot:/` from `mkosi.repart/00-esp.conf`. When a
device's deviceinfo has `deviceinfo_generate_bootimg="true"` (e.g. OP6),
`boot-deploy` runs during the rootfs bake and produces `/boot/boot.img-<kver>`,
which ends up at the ESP root as `boot.img-<kver>`. The orchestrator
extracts it post-bake with `mcopy -n -i <esp.raw> ::boot.img-\* boot.img`.

## Per-device overrides

These flow through `duranium/scripts/pmaports.py::resolve()` → JSON →
mkosi's `mkosi.configure` script:

- `deviceinfo_arch` → mkosi `Architecture=`
- `deviceinfo_rootfs_image_sector_size` → mkosi `SectorSize=`
- `deviceinfo_generate_bootimg` → `boot-deploy` runs at bake time
- `deviceinfo_flash_method` → informational; consumed by flash scripts

The OP6 deviceinfo sets `SectorSize=4096` (UFS storage). The L5 sets
`deviceinfo_sd_embed_firmware="u-boot/librem5/phone-boot.img:33"` so
`phone-boot.img` gets dd'd into sector 33 of the raw image at bake
time — that's how the SD-card flash path works without any host-side
trickery (just dd the .raw to a microSD and the device boots).

## How the HackberryPi CM5 pipeline works (the second pipeline)

The CM5 doesn't fit the duranium chain because:

1. **Boot chain** — Pi uses `raspberrypi-firmware` (config.txt + cmdline.txt + start.elf + bootcode.bin), not UEFI. While pftf/RPi4 EDK2 exists for the Pi 4B, there's no equivalent for the Pi 5/CM5's BCM2712.
2. **Panel** — the 720×720 display is DPI/GPIO via Pimoroni's HyperPixel 4.0 Square overlay + ZitaoTech's `hackberrypi.dtbo` overlay (compatible with `brcm,bcm2712`, `raspberrypi,5-compute-module`). Linux DRM applies these overlays only once Linux is up, configured via `/boot/firmware/config.txt`. Duranium ships an ESP with systemd-boot — no place to inject `dtoverlay=` lines.
3. **Keyboard** — the ZitaoTech CM5 keyboard is **USB HID** (RP2040 + QMK/Vial firmware on the keyboard PCB). It enumerates as a standard USB keyboard + mouse to the CM5. No kernel module needed. (This was a correction from earlier audit notes that referenced the I²C-attached BBQ10/Beepy keyboard — that driver is for a different product.)

The pipeline is in `scripts/build-hackberry-cm5-image.sh`:

```
scripts/
├── build-hackberry-cm5-image.sh    ← entry point
├── hackberry-cm5/lib/
│   ├── check-host.sh               ← verify tools (losetup, nspawn, dtc, …)
│   ├── fetch-raspios.sh            ← pinned RaspiOS Lite arm64 download
│   ├── customize-image.sh          ← grow rootfs, loop-mount, nspawn into it
│   ├── inside-chroot.sh            ← apt install Qt6 + build marathon-shell + LightDM
│   └── finalize.sh                 ← xz compress + emit to out/
└── flash/flash-hackberry-cm5.sh    ← dd to microSD with safety checks
```

Build flow:
1. Fetch pinned RaspiOS Lite arm64 `.img.xz` from `downloads.raspberrypi.com` (default: `2025-05-13` Bookworm)
2. Grow rootfs partition to 6 GiB (RaspiOS Lite ships ~3 GiB; we need room for Qt6 + WebEngine)
3. Loop-mount + `systemd-nspawn` into the rootfs
4. Inside the chroot: `apt install qt6-base-dev qt6-wayland qt6-webengine-dev …`, build marathon-shell from the bind-mounted source, install LightDM + the `platforms/raspberry-pi/config/` session files, enable autologin
5. Compile ZitaoTech's `hackberrypi.dts` to `.dtbo` via `dtc`, install to `/boot/firmware/overlays/`
6. Append HyperPixel + KMS overlay lines to `/boot/firmware/config.txt`
7. Purge build-time `-dev` packages (saves ~1.5 GiB), `apt clean`
8. `xz` compress, emit to `out/marathon-hackberry-cm5.img.xz`
9. Flash with `dd` (handled by `scripts/flash/flash-hackberry-cm5.sh`)

Marathon-shell runs as the Wayland session under LightDM's autologin
as user `pi`. The shell uses the `eglfs` Qt platform plugin (direct
KMS/DRM, no nested compositor), which on the CM5 means raw GPU access
through the V3D KMS driver — same model as on the OnePlus 6 / Librem 5
under duranium, just at a different layer of the boot stack.

The first build takes ~30-45 minutes (apt install of Qt6 + WebEngine
+ marathon-shell compile dominate). Subsequent builds reuse the
cached base image but re-do the customization stage — pass
`--skip-download` to skip the base-image fetch.

Other Hackberry variants (Zero 2 W, Pi 4B, Pi 5) aren't supported
yet; the CM5 was prioritized because it's the highest-spec variant
and the one currently being tested. Adding another variant is a
narrower scope each (new device overlay aport + corresponding boot
config), now that the first one is built.

## What's verified vs. what isn't

| Path | Build | Flash | Boot on hardware |
|---|---|---|---|
| QEMU UEFI | ✅ yes | n/a | ✅ verified (virgl + VNC) |
| OnePlus 6 | ✅ yes (overlay aport + boot.img extraction wired) | ⚠️ written but unverified | ❌ not yet — needs flashing |
| Librem 5 | ✅ overlay aport + phone-boot.img extraction wired | ⚠️ written but unverified | ❌ not yet — needs flashing |
| HackberryPi CM5 | ✅ raspios-style pipeline + hackberrypi.dtbo + LightDM session | ⚠️ written but unverified | ❌ not yet — needs flashing. QML responsiveness at 720×720 verified locally. |

"unverified" means the script follows the duranium-on-phone protocol
the postmarketOS team documented, but Marathon hasn't run it against
real hardware on its branch yet. The first time someone flashes a
real OP6 or Librem 5, expect to iterate on the exact fastboot/uuu
arguments.

## References

- [Introducing Duranium](https://postmarketos.org/blog/2026/03/17/introducing-duranium/)
- [Duranium image server](https://duranium.postmarketos.org/)
- [Deviceinfo flash methods](https://wiki.postmarketos.org/wiki/Deviceinfo_flash_methods)
- [OnePlus 6 wiki](https://wiki.postmarketos.org/wiki/OnePlus_6_(oneplus-enchilada))
- [Librem 5 wiki](https://wiki.postmarketos.org/wiki/Purism_Librem_5_(purism-librem5))
- [Librem 5 u-boot docs](https://docs.u-boot.org/en/latest/board/purism/librem5.html)
