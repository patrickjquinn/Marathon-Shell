# Installing Marathon on the Zinwa Q25

This replaces Android on the phone. Everything in internal storage is
erased, and the Android bootloader is replaced by U-Boot: Android no longer
starts. Going back needs Zinwa's stock firmware and mtkclient.

## What gets written

| Partition | Becomes |
|---|---|
| `userdata` | A small disk image with its own GPT (4 KiB sectors): `pmOS_boot`, the ESP (systemd-boot, kernel, initramfs, device tree), and `pmOS_root`, the carrier, an ext4 file system that holds the Marathon root as a file in `/var/lib/marathon/images/`. |
| `lk_a`, `lk_b` | U-Boot, inside the phone's own lk image. MediaTek's `bl2_ext` and the signing certificates in that image stay as they were. |

Nothing else on the phone is touched. The preloader starts U-Boot, U-Boot
finds the ESP inside `userdata` and starts systemd-boot, and the initramfs
mounts the root file.

## What you need

- A Linux PC with `fastboot`, `simg2img` (android-tools), `zstd`, Python 3,
  and [mtkclient](https://github.com/bkerler/mtkclient).
- liblk, for putting U-Boot into the lk image:
  ```sh
  pip install --user git+https://github.com/R0rt1z2/liblk.git@75c8f14f16457b6c53d950d18d1ed7d2a665bed6
  ```
- The Marathon release for the Q25, or your own build (below). Check it:
  `sha256sum -c --ignore-missing q25-duranium-*.SHA256SUMS`.
- A phone with an **unlocked bootloader**: in Android, enable Developer
  options, turn on OEM unlocking, run `adb reboot bootloader`, then
  `fastboot flashing unlock` and confirm on the phone. Unlocking erases the
  phone. `fastboot getvar unlocked` must say `yes`.
- Charge the phone first.

## 1. Read the phone's lk partition

U-Boot goes into the phone's own lk image, which you read once with
mtkclient. Keep it: it is also how you put the Android bootloader back.

1. Stop ModemManager on the PC (`sudo systemctl stop ModemManager`); it takes
   the phone's USB port.
2. Run `mtk r lk_a stock-lk_a.img`, then, with the phone powered off, hold a
   volume key and plug it in.
3. Read `lk_b` the same way into `stock-lk_b.img` for the backup.

If mtkclient stops with `Cannot Reinit daconfig` or `xread: Wrong length`,
unplug, hold power for about 15 seconds, start the command again and then
reconnect the phone. Use `mtk r` (by partition name); do not use `mtk ro`.

## 2. Flash

Start the phone in the stock bootloader's fastboot mode (`adb reboot
bootloader` from Android), connect it and run, from the
directory with the release files (or with your build in
`$MARATHON_BUILD_DIR/q25`):

```sh
./scripts/flash/flash-zinwa-q25.sh --stock-lk stock-lk_a.img path/to/release
```

The script checks the files against the `.SHA256SUMS`, puts U-Boot into the
lk image and checks that the result still has the stock certificates. It
then lists what it will erase and waits for `YES`. It checks that exactly one
device is connected and that its bootloader is unlocked, and then runs
`fastboot flash userdata`, `fastboot flash lk_a`, `fastboot flash lk_b` and
`fastboot reboot`.

## 3. First boot

- The screen shows U-Boot's text for a moment, then the Marathon splash.
- The first boot takes a few minutes longer. The initramfs grows the carrier
  into the rest of `userdata`. Then the root file grows to 32 GiB, and
  `/home` is created: a LUKS2 container (`home.luks`) next to the root file,
  made on the phone so that it has its own key. See
  [ENCRYPTION.md](../ENCRYPTION.md#first-boot-q25).
- Setup (the OOBE) starts. The PIN you choose there locks `/home`. From the
  next boot on, the splash asks for it before Marathon starts. Type it on the
  keyboard; the digits are on Alt.
- If you forget the PIN, `/home` cannot be recovered. Install again (below).

## Updates

Settings > Software updates installs new releases over the air
([OTA.md](../OTA.md#zinwa-q25)). A new root image goes next to the running
one on the carrier, and at the next restart it boots with its own kernel,
initramfs and device tree as the default entry. The previous root stays as
the fallback, and the phone returns to it if the new one fails to start
three times. `/home`, Wi-Fi networks, Bluetooth pairings and the modem's
settings carry over (`q25-root-install` on the phone,
`/usr/libexec/marathon/q25-root-install`, from
`packaging/packages/device-zinwa-q25-marathon`).

Updating from 1.0 (26103101) turns SSH off once: 1.0's update step does not
carry the Developer tools switch. Turn it on again after the update.

## Recovery

Marathon's U-Boot has no usable fastboot (the phone has no keys it can read,
and its USB gadget does not start), so recovery is through BROM with
mtkclient.

- **Marathon does not start, or you want a clean install:** with the phone
  off, run
  ```sh
  ./scripts/flash/flash-zinwa-q25.sh --mtkclient path/to/release
  ```
  and hold a volume key while plugging the phone in. This rewrites `userdata`
  and erases `/home`. Add `--stock-lk stock-lk_a.img` to write U-Boot again
  as well.
- **U-Boot does not start** (black screen, the PC never sees the phone after
  the preloader): write U-Boot again with the command above and
  `--stock-lk`, or put the Android bootloader back:
  `mtk w lk_a,lk_b stock-lk_a.img,stock-lk_b.img`. Android then needs
  Zinwa's stock firmware in `userdata` and the other partitions.
- mtkclient tips: stop ModemManager first. After a failed or interrupted
  write, power-cycle the phone (hold power about 15 seconds) before trying
  again; every retry fails until you do.

## Building the image yourself

```sh
Q25_CONNSYS_FIRMWARE_DIR=…/connsys-firmware \
./scripts/build-zinwa-q25-image.sh
```

The kernel builds from source (`packaging/packages/linux-zinwa-q25`); its
build tree takes several GB, so point `MARATHON_APK_WORK_DIR` at a disk with
room for it.

This writes the root, the `userdata` image, U-Boot and `gimme-uboot.py` and a
`.SHA256SUMS` to `$Q25_IMAGE_OUT` (default `$MARATHON_BUILD_DIR/q25`). U-Boot
is built with `scripts/q25/build-q25-uboot.sh`, which refuses a build that
differs by one byte from the U-Boot the phone was tested with. The `userdata`
image comes from `scripts/q25/q25-userdata-image.sh`.
