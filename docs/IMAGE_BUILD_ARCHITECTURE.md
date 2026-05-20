# Marathon image build architecture

How Marathon-Shell turns a clone into a bootable image, and why the
device-specific scripts look the way they do. Written 2026-05-20 after
a deep audit corrected several wrong assumptions.

## The one-line summary

Marathon ships **one image format** — a duranium (postmarketOS mkosi)
GPT disk image with systemd-boot + UKI + erofs+verity /usr — to
**three target classes**: QEMU (UEFI directly), fastboot Android phones
(via u-boot's UEFI emulation), and uuu i.MX phones (via u-boot's
UEFI emulation). A fourth class (raspberrypi-firmware-boot handhelds
like Hackberry) is not supported — it needs a parallel raspios-style
pipeline that doesn't exist.

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

## Why Hackberry doesn't fit

The Hackberry Pi (4B variant) is the odd one out because:

1. **Boot chain** — Pi uses `raspberrypi-firmware` boot (config.txt + cmdline.txt + start.elf), not UEFI. There is a UEFI-on-Pi-4B firmware (pftf/RPi4 EDK2), but
2. **Panel** — the 720×720 display is DPI/GPIO via Pimoroni HyperPixel 4.0 Square overlay. Linux DRM applies the overlay only once Linux is up, so the firmware-stage UEFI can never show anything. The HyperPixel overlay is configured in `/boot/config.txt`, but duranium ships an ESP with systemd-boot, not a `/boot/config.txt`.
3. **Keyboard** — BlackBerry-style I²C keyboard (BBQ10) needs the ardangelo/beepberry-keyboard-driver DKMS module against the kernel. No pmaports aport. No upstream submission.

To support Hackberry properly we'd need a parallel raspios-style
pipeline that produces a normal Pi image (FAT32 boot partition with
config.txt + cmdline.txt + bootcode.bin + start.elf + overlays/, plus
an ext4 rootfs). That's enough work that we currently refuse — both
the build script and the flash script say so honestly.

## What's verified vs. what isn't

| Path | Build | Flash | Boot on hardware |
|---|---|---|---|
| QEMU UEFI | ✅ yes | n/a | ✅ verified (virgl + VNC) |
| OnePlus 6 | ✅ yes (overlay aport present) | ⚠️ written but unverified | ❌ not yet — needs flashing |
| Librem 5 | ⚠️ overlay aport present + phone-boot.img extracted | ⚠️ written but unverified | ❌ not yet — needs flashing |
| Hackberry | ❌ refuses | ❌ refuses | ❌ refuses |

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
