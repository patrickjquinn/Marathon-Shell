# MP01 first flash: green-light checklist

State of `feat/mp01-integration` for the Minimal Phone MP01's first
Marathon flash. Nothing here has been written to the phone yet.

**Verdict: flashable, untested.** Every artifact the flash needs exists:
the U-Boot boot image for `boot_b` and a `userdata` image built through
`scripts/build-image.sh` (no raw mkosi). Nothing of the OS has run on an
MP01, so the first flash is a test boot on slot `b` with stock Android on
slot `a` as the fallback. The board DT's reserved memory has been checked
against the MP01's own LK map (below).

This is a **developer image**: `MARATHON_DEV_SSH_KEY` gave it the
builder's `~/.ssh/id_ed25519.pub` for key-only SSH as root and the user
(root has no password). It is not for anyone else's phone, and must never
be published.

## What is built

### The image (`/mnt/deckard-build/mp01-build/mp01/`)

Built by `scripts/build-minimal-mp01-image.sh` at `4e2802974`
(`MARATHON_BUILD_DIR=/mnt/deckard-build/mp01-build`), image version
`26112301`, with `linux-minimal-mp01` 7.0.0-r2 (the reserved-memory fix).
It replaces the `88b3174e8` image, whose files are gone.
`…SHA256SUMS` beside them lists the same hashes.

| File | sha256 |
|---|---|
| `mp01-duranium-20261123-4e2802974.userdata.img` (Android sparse, for `fastboot flash userdata`) | `352b6f65671ae0021e838794a6bff68e82ac391ae13fc2e8665574220155f54d` |
| `mp01-duranium-20261123-4e2802974.userdata.img.zst` | `1d19aaecfc7ff2ba738037d4a593b1c4780ee0fa9ff01678342333e9c9c62011` |
| `mp01-duranium-20261123-4e2802974.ext4` (the root alone, 8 GiB, 2.1 GiB used) | `99fe0883731f3b202a5f02c923f98d14369ba77022d546461b7c0a26c69bf585` |
| `mp01-duranium-20261123-4e2802974.ext4.zst` | `e75e7851e443a6821438b1541882c596f3140832c95b34c7eacc7f46ec55339d` |

The `userdata` image: a GPT with 4 KiB sectors; partition 1 the FAT32 ESP
(`pmOS_boot`: systemd-boot, `linux.efi`, `initramfs`,
`dtbs/mediatek/mt6789-minimal-mp01.dtb`, one loader entry), partition 2 the
ext4 carrier (`pmOS_root`) holding the root as
`/var/lib/marathon/images/mp01-duranium-20261123-4e2802974.ext4`. The entry
boots it with `mp01.rootfs_file=`; the initramfs grows the carrier into
the rest of `userdata` on first boot.

What the root carries, checked in the image (the ESP's `linux.efi`,
`initramfs` and DTB have the same hashes):

| | |
|---|---|
| `/boot/linux.efi` | `1de5b513d787c100cb5df67443751fc82cc01a5e9ecadbb190b238a1901adc28` (`linux-minimal-mp01` 7.0.0-r2) |
| `/boot/dtbs/mediatek/mt6789-minimal-mp01.dtb` | `d327a41535ef6cd0291bfe1adb145740599c0a1db1bf5144c636aef24f6f97c7` (`rotation = <270>`, touch `touchscreen-inverted-x` + `touchscreen-swapped-x-y`, modem window `md1@de000000`, `ramoops` at `0x48090000`) |
| `/boot/initramfs` (mkinitfs in the image, with the carrier hook and `carrier.conf`) | `8223b2812adc8a6c3f450b7a32831eda83c55a24faa9ae141e8033ea15e9bf51` |
| `/usr/share/marathon/carrier.conf` | `CARRIER_NAME=mp01`, the board DTB, `50-device-minimal-mp01.conf` |
| `/etc/marathon/device-profile.conf` | `DISPLAY_TECHNOLOGY=epaper`, `PANEL_ORIENTATION=kms`, `FORCE_DPI=180` |
| Command line | `console=tty0 fbcon=rotate:3 loglevel=7`, the carrier options (`pmos_rootfsopts=defaults systemd.gpt_auto=0 systemd.confext=0 systemd.sysext=0`), the UUIDs, `mp01.rootfs_file=` |
| Packages | `marathon-shell` 1.0.0-r573 built from this branch (panel orientation), `device-minimal-mp01-marathon` 1.0.0-r1, `device-minimal-mp01` 1-r0, `mt6789-platform` 1.0.0-r0, Marathon's `mesa` 26.2.6-r100 and `libcamera` |

### Packages

In `~/q25-build/test-pkgs/mp01/` (the packages in the image are also in
`/mnt/deckard-build/mp01-build/duranium/mkosi.packages/`):

| File | sha256 |
|---|---|
| `linux-minimal-mp01-7.0.0-r2.apk` (reserved memory and ramoops from the MP01 LK; in the image) | `3dd2cc5a3de06e62a2510d8a876d697389678a581872e73d95a15c22a66a238b` |
| `mp01-kernel-modules-7.0.0-r2.apk` (CONNSYS, audio, ECCCI out-of-tree, built against r2; no image pulls it in) | `bfc6f8812ff1451e21036820331d19ca6b9e23f662a2ee697b0de5095c0788bb` |
| `device-minimal-mp01-marathon-1.0.0-r1.apk` (`PANEL_ORIENTATION=kms`; in the image) | `5bbefbda11b1054d6215e3ea801015b3303224bc23a5ed27880265c6a32eece8` |
| `device-minimal-mp01-1-r0.apk` (deviceinfo, `deviceinfo_dtb`, cmdline, initramfs modules; in the image) | `d4b485d601f40b78fc897724b7e1f9e115ad59e7486354e35e62ce7887502521` |
| `mt6789-platform-1.0.0-r0.apk` (shared MT6789 services; in the image) | `436e4c86ec89efa3a970525b2e120bd2dda7ab03c113d20feadccada6581c9f8` |
| `linux-minimal-mp01-7.0.0-r1.apk`, `linux-minimal-mp01-7.0.0-r0.apk`, `mp01-kernel-modules-7.0.0-r0.apk`, `device-minimal-mp01-marathon-1.0.0-r0.apk` | superseded |

Build logs: `/mnt/deckard-build/mp01-build/image-build-r2.log` (the image),
`/mnt/deckard-build/mp01-build/kernel-r2-build.log` (the r2 kernel),
`~/q25-build/test-pkgs/mp01/logs/` (the r0 packages).

### U-Boot

Built outside this repository by `~/q25-build/uboot-chainload/build.sh`
(JamiKettunen/u-boot-mt6789 at `11b7b36c`, the Q25's U-Boot patches
0001-0007, then MP01 patches 0008-0019):

| File | sha256 |
|---|---|
| `~/q25-build/uboot-chainload/boot/boot-uboot-mp01.img` (all MP01 patches, 64 MiB, AVB footer with a throwaway key) | `1d8725a33aaf3d156a074dff164f83a9fd4fdc0e5c93e911d00c633786ed8de5` |

Earlier U-Boot builds ran on the phone, up to the UFS bring-up patches.
This one adds the USB result reporting (0016), the UFS host stop (0017),
LK's carve-outs and framebuffer for the OS (0018) and the nested ESP boot
(0019). Those four have not run yet. 0019 looks for exactly what the
`userdata` image has: `\EFI\BOOT\BOOTAA64.EFI` on partition 1 of the
nested GPT.

## Before the first flash

1. Check the files against the hashes above
   (`sha256sum -c mp01-duranium-20261123-4e2802974.SHA256SUMS` in the
   image directory).
2. A full battery: nothing charges under Marathon yet.

## Reserved memory: checked against the MP01's LK

A reserved region the DT misses is an SError at first touch
(`kernel/README.md`, "Memory and the boot chain"). Android's
`/proc/device-tree/reserved-memory/*/reg` cannot be read without root, but
the stock LK prints its whole `mblock` table at every boot, and its
`expdb` partition (in the private inventory) keeps the log of a locked and
two unlocked boots. Every region LK hands the kernel lies inside a
`reserved-memory` node of `mt6789-minimal-mp01.dts`, in both states. The
check found one gap, now fixed in `linux-minimal-mp01` r2: the modem's DSP
image, 14 MiB at `0xe5200000`, was outside the modem window, which was
the Q25's (`0xdc000000`); it is now `0xde000000` +128 MiB.

The `mblock-13` framebuffer is `0xffa23000` +`0x5dc000`, the buffer U-Boot
draws in; the DT keeps it no-map (LK maps it for its vendor kernel), as
arm64 will not ioremap RAM it has mapped for a `simple-framebuffer`. U-Boot 0018 also copies every LK region into
the OS's tree and stops the boot if it can't; the DT no longer depends on
it.

## Flash commands (first test boot: slot b, fallback to slot a)

From FLASHING.md, with the built files:

    adb reboot bootloader
    fastboot getvar product      # Z10
    fastboot getvar unlocked     # yes
    scripts/flash/flash-minimal-mp01.sh --slot b \
        ~/q25-build/uboot-chainload/boot/boot-uboot-mp01.img \
        /mnt/deckard-build/mp01-build/mp01/mp01-duranium-20261123-4e2802974.userdata.img

The script checks for exactly one unlocked `Z10`, asks for `YES`, and then
runs:

    fastboot flash userdata mp01-duranium-20261123-4e2802974.userdata.img
    fastboot flash boot_b boot-uboot-mp01.img
    fastboot --set-active=b
    fastboot reboot

It writes only `boot_b` and `userdata`: never `lk`, `preloader`, `vbmeta`,
`nvram`, `nvdata`, `nvcfg`, `md1img`, `protect1/2`, `persist`, `seccfg`,
`misc` or `super`.

How the fallback works: a U-Boot failure, hang (15 s watchdog) or panic
resets the phone. LK retries slot `b` until its A/B tries run out (7 after
`--set-active`), then boots stock on slot `a`. Stock cannot read
Marathon's `userdata` and will offer a factory reset. Accepting it erases
the install. Nothing marks slot `b` successful yet, so run
`fastboot --set-active=b` again every few boots.

U-Boot only, keeping `userdata` (a run with Android's `userdata` should
end in LK's fastboot):

    scripts/flash/flash-minimal-mp01.sh --boot-only --slot b \
        ~/q25-build/uboot-chainload/boot/boot-uboot-mp01.img

## Observing the first boot

The phone has no serial port, and U-Boot's USB does not work. Watch the
host (`lsusb`, `dmesg -w`, `fastboot devices`) and the panel:

| The host sees | Meaning |
|---|---|
| The OS's USB gadget (the postmarketOS initramfs network: `usb0`, or ACM) | Linux started |
| LK's fastboot | UFS works and U-Boot wrote its marker, but there is no Marathon ESP or EFI failed |
| Stock Android after a few silent resets | U-Boot failed before that, usually at UFS |

- The panel keeps U-Boot's last report: 10 s on the way to fastboot, 20 s
  before a failure reset.
- The proof-of-life block is 63 MiB into `boot_b`.
- A kernel that dies before USB leaves its log in ramoops (`0x48090000`,
  the stock layout). Read `/sys/fs/pstore` from the next boot that gets
  far enough. On stock Android that needs root.

First-boot success, in order (`kernel/README.md`, "First boot"):

1. The USB gadget enumerates: kernel, UFS driver and initramfs work.
2. The initramfs finds the root in `userdata`, and the UFS is used
   read-only until that is trusted.
3. `mediatek-drm` binds and the e-paper shows the console upright
   (`rotation = <270>` and `fbcon=rotate:3`). If it is upside down, the
   rotation is 90, and the touch inversion moves from x to y.
4. The shell comes up portrait: its log says `panel orientation Left Side
   Up ... the scene turns 270`. A tap lands under the finger. With the
   USB network up, `ssh root@172.16.42.1` with the builder's key (the
   Q25's address; unconfirmed here).
5. The keypad, the PMIC keys and the AW9523 keyboard work (`evtest`,
   every key), then the frontlight.
6. The gauge reads close to stock.

## Known untested risks

- **Nothing of this kernel has run on an MP01.** It compiles, and its
  DTB builds with one known warning (the UFS PHY unit address in
  `mt6789.dtsi`, the same as on the Q25).
- **Reserved memory** is the MP01 LK's (above), but LK places some regions
  at boot: a different LK build (slot `a` has a newer one) or modem image
  could move them. U-Boot 0018's copy of LK's own regions covers that.
- **The boot path** U-Boot (0016-0019) → systemd-boot → Linux has never
  run.
- **The DTB builds** (checked by applying the series to `978b8b67` and
  building it); `make dtbs_check` was not run.
- **E-paper** (`eink-series.md`, "Untested"): the lane routing (2/3
  crossed), whether the CPLD accepts split write/read transfers, the
  power-on order and delays, taking over from the bootloader without a
  reset, the refresh modes, and the rotation. The driver cannot reach the
  CPLD's flash or configuration opcodes.
- **GPIO12** is treated as NFC VEN, not as a panel enable.
- **Display SMI and idle**: `0111`/`0112` replay the Q25 LK's display SMI
  set-up, and `0122` keeps system idle off while the CRTC runs. Neither
  has been checked against the MP01's LK.
- **Power**: there is no MT6375 charger driver, so charging runs on LK's
  settings and there is no charger `power_supply`. Start with a full
  battery. PMIC power-off (`0123`/`0125`) assumes the same BL31 as the Q25.
- **No vendor modules in the image**: no Wi-Fi, Bluetooth, GNSS, modem or
  audio. `mt6789-platform`'s units fail without them.
- **Base rotation and touch** have not run on the phone: the compositor
  turns the scene and the `wl_output` by the connector's panel
  orientation, and the DT reports touch in the scanout frame. Neither
  could be checked without the panel. A sideways or mirrored result is a
  DT fix (`rotation`, the touchscreen properties), not a shell one.
  `display_technology = "epaper"` only reduces motion.
- **The `userdata` image has never booted anywhere.** Its layout, hook and
  options are the Q25's, made by the same script, but systemd-boot,
  the carrier hook and the root have not run with this kernel.

## Back to stock

The restore uses the phone's own `boot_a`/`boot_b`, read with mtkclient
before any write. They are in the private inventory and match its
`SHA256SUMS-parts.txt`; checked again for this list.

    adb reboot bootloader      # or any U-Boot run that ends in fastboot
    scripts/flash/flash-minimal-mp01.sh --restore-stock ~/q25-build/mp01-inventory/brom/parts

That flashes `boot_a` and `boot_b`, sets slot `a` active, wipes
`userdata` and `metadata` (`fastboot -w`), and reboots into stock Android
as after a factory reset. No other partition is ever written, so nothing
else needs restoring.

If fastboot can't be reached: LK's boot menu has a Fastboot entry (its
key combination on the MP01 is unconfirmed). As a last resort,
mtkclient's preloader mode (power off, plug in with no keys) can write
the backed-up partitions; the full 59-partition backup, without `super`
and `userdata`, is in the private inventory and its second copy under
`/mnt/deckard-build/mp01-evidence-private/`.
