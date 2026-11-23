# MP01 first flash: green-light checklist

State of `feat/mp01-integration` for the Minimal Phone MP01's first
Marathon flash. Nothing here has been written to the phone yet.

**Verdict: not ready for an OS flash.** The kernel and device packages
build. Nothing turns them into the `userdata` image that
`flash-minimal-mp01.sh` writes (see "What blocks the flash"). What can
happen tomorrow without that: the read-only `adb` dump, and a U-Boot-only
run that keeps `userdata`.

## What is built

Packages, built from this branch at `16a33e852` (the kernel package is unchanged since `13a00c196`), in `~/q25-build/test-pkgs/mp01/`:

| File | sha256 |
|---|---|
| `linux-minimal-mp01-7.0.0-r0.apk` (kernel, DTBs, in-tree modules) | `8a2e33fbb5895322a7e75d4135414da2279f06528e0fec54645b0e983b8be51d` |
| `mp01-kernel-modules-7.0.0-r0.apk` (CONNSYS, audio, ECCCI out-of-tree; no image pulls it in) | `f70ddd7231afedb796bfaa4595591a8f5bea2c90e6997ee9aee1410cfe318fdd` |
| `device-minimal-mp01-1-r0.apk` (deviceinfo, `deviceinfo_dtb`, cmdline, initramfs modules) | `d4b485d601f40b78fc897724b7e1f9e115ad59e7486354e35e62ce7887502521` |
| `device-minimal-mp01-marathon-1.0.0-r0.apk` (session, profile with `DISPLAY_TECHNOLOGY=epaper`) | `2c20bb12a814f38f885f25c4084c6eb3726eff3af243cac334989d206e9d9ca2` |
| `mt6789-platform-1.0.0-r0.apk` (shared MT6789 services) | `436e4c86ec89efa3a970525b2e120bd2dda7ab03c113d20feadccada6581c9f8` |

Inside `linux-minimal-mp01` (release `7.0.0-mp01`):

| File | sha256 |
|---|---|
| `/boot/linux.efi` | `11ec085076f34c05ff6cc07ad7df97cde2f7e33034cc05b7d17f06d75d3a3652` |
| `/boot/vmlinuz` | `35720949d51e3d372fa7e176eddc02af51443532686aca7833ae26f975ed0b1e` |
| `/boot/dtbs/mediatek/mt6789-minimal-mp01.dtb` (the one `deviceinfo_dtb` names: `data-lanes = <1 2 4 3>`, `rotation = <270>`) | `ed1b473a73cb34f0e2cf08cd154d5341140fcf3fc8862d57ce9ed903cf3186e2` |
| `/boot/dtbs/mediatek/mt6789-minimal-mp01-vendor.dtb` (plus the CONNSYS overlay) | `97198420b58fdbaaa3308c225046c4d55ef7f3fb396b865ba52e777074089863` |

Build logs are in `~/q25-build/test-pkgs/mp01/logs/`. The earlier kernel
built outside abuild, in `/mnt/deckard-build/mp01-kbuild/out/`, predates the
e-paper series and is superseded.

U-Boot boot image, built outside this repository by
`~/q25-build/uboot-chainload/build.sh` (JamiKettunen/u-boot-mt6789 at
`11b7b36c`, the Q25's U-Boot patches 0001-0007, then MP01 patches
0008-0019):

| File | sha256 |
|---|---|
| `~/q25-build/uboot-chainload/boot/boot-uboot-mp01.img` (all MP01 patches, 64 MiB, AVB footer with a throwaway key) | `1d8725a33aaf3d156a074dff164f83a9fd4fdc0e5c93e911d00c633786ed8de5` |

Earlier U-Boot builds ran on the phone, up to the UFS bring-up patches.
This one adds the USB result reporting (0016), the UFS host stop (0017),
LK's carve-outs and framebuffer for the OS (0018) and the nested ESP boot
(0019). Those four have not run yet.

Not built: the Marathon image and the `userdata` image. See below.

## What blocks the flash

1. **No MP01 `userdata` image.** FLASHING.md writes
   `marathon-mp01.userdata.img`, "the Q25's layout". Nothing in the tree
   makes one for the MP01:
   - `scripts/q25/q25-userdata-image.sh` hard-codes the Q25's DTB and
     command-line file. Its file-on-carrier root needs `q25-carrier.hook`
     in the initramfs (from `device-zinwa-q25`), the Q25-only `mkinitfs`
     step in `mkosi.finalize`, and the root-only layout of pipeline patch
     0053. None of these exist for `minimal-mp01`.
   - The other way is to `img2simg` the generic GPT image that
     `scripts/build-minimal-mp01-image.sh` produces, and let the
     postmarketOS initramfs mount its subpartitions from `userdata`.
     Nobody has checked that Marathon's generic image boots like that.
2. **The image was not built.** A Q25-class image needs an ~8 GiB root
   plus mkosi's workspace and every Marathon package. That is more than
   the ~15 GB budget: `/mnt/deckard-build` had 16-17 GB free, and `/home`
   about 7 GB. It needs a run of `scripts/build-minimal-mp01-image.sh` on
   a disk with room, with its own `MARATHON_BUILD_DIR`. Set
   `MARATHON_DEV_SSH_KEY` so the test image can be reached over the USB
   gadget.

Neither blocks the read-only dump or a U-Boot-only run.

## First: the read-only reserved-memory dump

This changes nothing on the phone. It must happen before any kernel boot,
because a reserved region the DT misses is an SError at first touch
(`kernel/README.md`, "Memory and the boot chain").

1. Boot stock Android (slot `a`). Unlocking wiped Android, so re-enable
   Settings > About phone > tap "Build number" seven times, then
   Settings > System > Developer options > **USB debugging**, and accept
   the host's key.
2. Run, saving the output into the private inventory
   (`~/q25-build/mp01-inventory/<date>/`), never into this repository:

       adb shell 'for n in /proc/device-tree/reserved-memory/*/; do echo "$n $(xxd -p "$n/reg" 2>/dev/null)"; done'
       adb shell cat /proc/iomem
       adb shell cat /proc/cmdline

3. Check that every `mblock-*` region lies inside a `reserved-memory` node
   of `mt6789-minimal-mp01.dts` (`linux-minimal-mp01`'s `mp01-0015`), and
   fix the DTS where it doesn't. The `mblock-13` framebuffer should be
   the `0xffa23000` buffer U-Boot draws in. U-Boot 0018 also copies LK's
   regions into the OS's tree, and stops the boot if it can't, but the
   DTS should not depend on that.

## Flash commands (first test boot: slot b, fallback to slot a)

These are from FLASHING.md. Run them only once a `userdata` image exists.

    adb reboot bootloader
    fastboot getvar product      # Z10
    fastboot getvar unlocked     # yes
    scripts/flash/flash-minimal-mp01.sh --slot b \
        ~/q25-build/uboot-chainload/boot/boot-uboot-mp01.img \
        marathon-mp01.userdata.img

The script checks for exactly one unlocked `Z10`, asks for `YES`, and then
runs:

    fastboot flash userdata marathon-mp01.userdata.img
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

U-Boot only, keeping `userdata` (possible today; a run with Android's
`userdata` should end in LK's fastboot):

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
   rotation is 90.
4. The keypad, the PMIC keys and the AW9523 keyboard work (`evtest`,
   every key), then touch and the frontlight.
5. The gauge reads close to stock.

## Known untested risks

- **Nothing of this kernel has run on an MP01.** It compiles, and its
  DTB builds with one known warning (the UFS PHY unit address in
  `mt6789.dtsi`, the same as on the Q25).
- **Reserved memory** follows the Q25 and Daylight DC-1 LK layout until
  the dump above confirms it.
- **The boot path** U-Boot (0016-0019) → systemd-boot → Linux has never
  run.
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
- **The shell has no base rotation**: the UI renders onto the 800x600
  landscape scanout. `display_technology = "epaper"` only reduces motion.

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
