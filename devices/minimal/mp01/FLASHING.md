# Flashing the Minimal Phone MP01

Marathon is installed on the MP01 (board `Z10`, MT6789) with `fastboot`
alone, from the phone's own bootloader. The steps below are the same
ones a UBports-installer config would run. You don't need mtkclient,
BROM mode or a serial cable.

## How the phone boots

```
preloader -> bl2_ext -> LK (stock, unchanged)
          -> boot_<slot>: U-Boot, packed as an Android boot image
          -> userdata: nested GPT -> ESP -> systemd-boot -> Linux
```

- **LK.** The stock LK loads `boot_<slot>` and starts U-Boot as if it
  were Linux, passing LK's device tree. Nothing below `boot` is
  replaced.
- **U-Boot's boot image.** It is a header-v4 Android boot image whose
  kernel is a gzipped U-Boot. Its AVB hash footer is signed with a key
  that is not in the stock vbmeta. An unlocked phone boots it in the
  orange state and shows LK's five-second "OS not being verified"
  banner. The stock `vbmeta_*` stays as it is.
- **U-Boot.**
  1. It takes DRAM and LK's reserved regions (firmware, TEE, modem,
     framebuffer) from LK's tree.
  2. It writes a proof-of-life block into `boot_b`, 63 MiB in, past the
     image.
  3. It maps the `userdata` partition as a disk (blkmap) and starts
     `\EFI\BOOT\BOOTAA64.EFI` from the nested ESP.
  4. When systemd-boot installs the entry's device tree, U-Boot adds
     LK's reserved regions and the panel's `simple-framebuffer` to it.
- **userdata.** The image uses the Q25's layout
  (`scripts/q25/q25-userdata-image.sh`): a GPT with 4 KiB sectors whose
  first partition is the FAT32 ESP (systemd-boot, kernel, initramfs,
  DTB) and whose second is the root carrier.
- **The panel.** It is scanned out at 800x600 and held in portrait. The
  OS's kernel command line needs `fbcon=rotate:3`, so that its console
  reads the way U-Boot's does.

## What the phone shows over USB

The phone has no serial port, and U-Boot's USB does not work. Instead,
the end of every U-Boot run can be read from the host:

| The host sees | Meaning |
|---|---|
| The OS's own USB gadget | Linux started. |
| LK's fastboot (`fastboot devices`) | UFS works and the marker was written, but userdata holds no Marathon ESP, or EFI failed. Flash userdata now. |
| Stock Android (after a few silent resets) | U-Boot failed before that, usually at UFS. |

How it works:

- **Fastboot.** U-Boot sets the reboot mode in TOPRGU `NONRST_REG2`
  (`0x10007024`, bits 3:0) to 3 ("bootloader") and resets the phone.
  This is the stock tree's `syscon-reboot-mode`, the same one
  `adb reboot bootloader` uses.
- **Failure.** U-Boot sets the mode to 0 and resets. LK boots the same
  slot again until its A/B tries run out, then falls back to the other
  slot.
- **Hangs and panics.** The watchdog (15 s) and the panic handler turn
  these into resets too, so they end the same way as a failure.
- **On the e-paper.** The last run's report stays on the panel: 10 s on
  the way to fastboot, 20 s before a failure reset.

## Getting into fastboot

You can get there in either of two ways:

- From Android, run `adb reboot bootloader`.
- Any U-Boot run that ends with "no OS" goes there by itself.

Then check the phone:

```
fastboot getvar product     # Z10
fastboot getvar unlocked    # yes
```

To unlock, run `fastboot flashing unlock` and confirm on the phone. This
wipes Android's data.

## Install

```
scripts/flash/flash-minimal-mp01.sh [--slot a|b] boot-uboot-mp01.img marathon-mp01.userdata.img
```

`boot-uboot-mp01.img` comes from the MP01 chain-load U-Boot build: the
Q25's U-Boot series plus the MP01 patches. That build is not in this
repository yet.

The script refuses to run on anything but a single unlocked `Z10`, and
asks you to type `YES` first. It then runs:

```
fastboot flash userdata marathon-mp01.userdata.img   # Android sparse image
fastboot flash boot_b boot-uboot-mp01.img
fastboot --set-active=b
fastboot reboot
```

If you only want to try a new U-Boot and keep userdata, run
`flash-minimal-mp01.sh --boot-only boot-uboot-mp01.img`.

**What gets written.** The script writes `boot_a` or `boot_b` and
`userdata`, and nothing else. It never touches:

- `lk`, `preloader` or `vbmeta`;
- `nvram`, `nvdata`, `nvcfg`, `md1img`, `protect1`, `protect2`,
  `persist`, `seccfg` or `misc`.

The default slot is `b`. Slot `a` keeps stock Android as the fallback.

## Known limits

- **LK's A/B tries count down.** Every boot of the active slot uses one
  of LK's A/B tries. `--set-active` sets 7, and only Android's
  boot-control HAL marks a slot successful. Nothing on the Marathon side
  does that yet, so after seven boots LK falls back to the other slot.
  - Until Marathon marks the slot successful, run
    `fastboot --set-active=b` again to restore the tries.
  - Marking the slot belongs in the OS, after a good boot, as Android
    does it. It does not belong in U-Boot, which would then mark boots
    whose kernel never came up.
- **Falling back to stock Android after an install.** Once Marathon has
  replaced userdata, stock Android on slot `a` cannot read it. Android
  will offer a factory reset. Accepting it erases the Marathon install.
  - To get back into Marathon, use `adb reboot bootloader` if adb is
    available. Otherwise use LK's boot menu, which has a Fastboot entry.
    Its key combination on the MP01 is not confirmed yet.
  - Then run `fastboot --set-active=b`.
- **The proof-of-life block is always written into `boot_b`,** even when
  U-Boot runs from `boot_a`. It only ever writes over zeroes or an
  earlier block. A stock boot image ends well before 63 MiB.

## Back to stock

The restore uses the phone's own backup of `boot_a` and `boot_b`, read
with mtkclient before the first install (`mtk r boot_a,boot_b ...`). It
is checked against `SHA256SUMS-parts.txt` when that file is next to the
backup.

```
scripts/flash/flash-minimal-mp01.sh --restore-stock PARTS_DIR
```

This runs:

```
fastboot flash boot_a PARTS_DIR/boot_a.bin
fastboot flash boot_b PARTS_DIR/boot_b.bin
fastboot --set-active=a
fastboot -w
fastboot reboot
```

`fastboot -w` wipes userdata and metadata, so Android starts as it does
after a factory reset. Android's own apps and data were lost when
userdata was flashed. No partition outside `boot_*`, `userdata` and
`metadata` was ever changed, so nothing else needs restoring.
