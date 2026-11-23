# Installing Marathon on the Zinwa Q25

This replaces Android on the phone. **Everything in the phone's internal
storage is erased**: Android, its apps, photos and files. Copy off anything you
want to keep first.

The installer is one command on a Linux PC. It talks to the phone in
MediaTek's download mode over USB, so you do not unlock the bootloader or
change anything in Android first. It:

1. saves the phone's own bootloader and settings partitions to your PC, so
   you can go back to Android later;
2. writes Marathon's bootloader (U-Boot) to the phone;
3. writes Marathon itself;
4. restarts the phone into Marathon.

Writing takes about ten minutes; the download before it depends on your
connection.

## What you need

- A PC running Linux (x86-64 or ARM64) with Python 3.9 or later, `git`,
  `zstd` and an internet connection. On Debian or Ubuntu:
  `sudo apt install python3-venv git zstd`. Windows and macOS are not
  supported.
- About 3 GB of free disk space: 1.9 GB for the download and 0.6 GB for the
  backup of the phone.
- A USB cable that carries data (not a charge-only cable).
- The phone charged to at least half.

## 1. Prepare the PC (once)

Two things on the PC get in the way of the phone's download mode.

**Let your user talk to the phone.** Without this only root can:

```sh
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="0e8d", MODE="0666", TAG+="uaccess"' |
    sudo tee /etc/udev/rules.d/51-marathon-q25.rules
sudo udevadm control --reload
```

**Stop ModemManager while you install.** It takes the phone for a modem and
grabs its USB port:

```sh
sudo systemctl stop ModemManager
```

Start it again afterwards with `sudo systemctl start ModemManager`, or
restart the PC. The installer checks both and tells you if one is missing.

## 2. Install

Download the installer and run it:

```sh
curl -fLO https://raw.githubusercontent.com/patrickjquinn/Marathon-Shell/main/scripts/flash/q25-install
python3 q25-install
```

(From a copy of this repository it is `./scripts/flash/q25-install`.)

The first time, it offers to set up
[mtkclient](https://github.com/bkerler/mtkclient), the tool that speaks the
phone's download mode, in a folder of its own
(`~/.local/share/marathon/q25-install`). Answer `y`.

It then downloads the newest Marathon release for the Q25 and checks it
against the release's checksums. It asks you to type `erase`, then tells you
what to do with the phone:

1. **Switch the phone off.** If it does not switch off, hold the power key
   for about 15 seconds.
2. **Hold both volume keys** and, while holding them, **plug in the USB
   cable**. Keep holding until the PC says `Connected`.

Leave the phone plugged in. The PC shows each step with its progress: the
backup (to `~/marathon-q25-backups/`), U-Boot, then Marathon. At the end the
phone restarts by itself.

### If the installer asks you to restart the phone

Some phones take only one write each time they are connected (see
[Download mode and mtkclient](#download-mode-and-mtkclient)). If the phone
stops answering, the installer says so and asks you to:

1. unplug the phone;
2. hold the power key for about 15 seconds until the phone is off, let go,
   and press Enter;
3. hold both volume keys and plug the cable in again.

It then checks what the phone already holds and carries on from there. If
the last step ends this way, the installer tells you to start the phone
yourself: unplug it, hold power for 15 seconds, then press power once.

If you stop the installer (Ctrl+C) or the cable comes out, run the same
command again: it carries on where it stopped. The phone is never left with
Marathon's storage under Android's bootloader (see
[What gets written](#what-gets-written)).

## 3. First start

- The screen shows U-Boot's text for a moment, then the Marathon splash.
- The first start takes a few minutes longer than later ones: Marathon grows
  its storage into the whole of the phone's internal storage and sets up the
  encrypted `/home` (see [ENCRYPTION.md](../ENCRYPTION.md#first-boot-q25)).
- Setup starts. The PIN you choose there locks `/home`. From the next start
  on, the splash asks for it before Marathon starts. Type it on the keyboard;
  the digits are on Alt.
- If you forget the PIN, `/home` cannot be recovered. Install again.

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

The installer installs the newest *install* release, which can be older than
the newest update: check for updates once setup is done.

Updating from 1.0 (26103101) turns SSH off once: 1.0's update step does not
carry the Developer tools switch. Turn it on again after the update.

## Going back to Android

```sh
python3 q25-install restore-stock
```

It uses the backup the installer made of this phone. It erases the start of
`userdata` and writes the phone's own Android bootloader back to `lk_a` and
`lk_b`. Android then starts and sets up its storage again, as after a factory
reset. If Android shows "Cannot load Android system", choose "Factory data
reset".

The backup is in `~/marathon-q25-backups/q25-<id>/<date>/`: each saved
partition as `<name>.bin` (the bootloaders, boot images, verified-boot
metadata, the phone's calibration and identity partitions, the partition
table and the preloader), a `SHA256SUMS`, and `manifest.json` with the
phone's partition table. Keep it. The installer writes only `lk_a`, `lk_b`
and `userdata`.

## Reinstalling, or when Marathon does not start

Run the installer again. It finds the backup it made the first time and
installs Marathon again from scratch; `/home` is erased.

Download mode is in the phone's boot ROM and preloader, which run before any
of Marathon's software, so it works whatever state Marathon is in: hold power
for 15 seconds to switch the phone off, then hold both volume keys and plug
it in.

## Options

| Option | |
|---|---|
| `--image FILE` | Install a local image instead of downloading one: a `*.userdata.img` or `*.userdata.img.zst`, with `u-boot-q25.bin` and the `.SHA256SUMS` beside it (what `scripts/build-zinwa-q25-image.sh` writes) |
| `--release TAG` | Install that release of the [feed](https://github.com/patrickjquinn/marathon-updates/releases), e.g. `zinwa-q25/26103101` |
| `--backup-dir DIR` | Keep backups there (default `~/marathon-q25-backups`) |
| `--cache-dir DIR` | Download there (default `~/.cache/marathon/q25-install`) |
| `--dry-run` | Download and check the image, then stop before the phone |
| `--verbose` | Show mtkclient's own messages |
| `backup` | Only back the phone up, then restart it as it was |

## How it works

### What gets written

| Partition | Becomes |
|---|---|
| `lk_a`, `lk_b` | U-Boot, inside the phone's own lk image. MediaTek's `bl2_ext`, `aee` and `lk_main_dtb` and the signing certificates in that image stay as they were. |
| `userdata` | A disk image with its own GPT (4 KiB sectors): `pmOS_boot`, the ESP (systemd-boot, kernel, initramfs, device tree), and `pmOS_root`, the carrier, an ext4 file system that holds the Marathon root as a file in `/var/lib/marathon/images/`. |

The preloader starts U-Boot, U-Boot finds the ESP inside `userdata` and
starts systemd-boot, and the initramfs mounts the root file.

U-Boot goes in first, and `userdata` is written only once both `lk_a` and
`lk_b` hold it and read back correctly. Android's bootloader would start
Android on Marathon's storage, and Android could reformat it; with U-Boot in
place and `userdata` not yet written, the phone just stops in U-Boot.

### Why the lk image comes from the phone

The lk partition holds more than the bootloader: MediaTek's `bl2_ext`, `aee`
and `lk_main_dtb`, each with its certificates. Marathon cannot redistribute
them, and they have to match the rest of the phone's firmware (one phone's
two slots can carry different versions). So the installer reads `lk_a` from
the phone, replaces only its first part with U-Boot, byte for byte as
`gimme-uboot.py` does, and writes the result to both slots.

### Download mode and mtkclient

The installer loads mtkclient's MediaTek download agent (`MTK_DA_V6.bin`)
through the phone's preloader (USB `0e8d:2000`) and reads and writes the
partitions through it. A phone that comes up in the boot ROM instead
(`0e8d:0003`) needs the preloader, which the backup saves.

mtkclient's own `mtk w` reads the whole image into memory and, after each
write, sends the agent one acknowledgement more than the protocol has. The
next command then got no answer (`xread: Wrong length`, `Read flash isn't
supported`), so a session managed one write, and the next `mtk` run found the
agent wedged (`Cannot Reinit daconfig`) until the phone was switched off. The
installer makes its own writes: it streams the image as it reads it, leaves
out the blocks a sparse image leaves out, ends each write as the agent
expects, and reads each write back. If a phone still stops answering after a
write, the installer remembers that for this phone and makes one write per
connection.

Marathon's U-Boot has no fastboot: the phone has no keys U-Boot can read,
and its USB gadget does not start. Download mode is the way in.

## Building the image yourself

```sh
Q25_CONNSYS_FIRMWARE_DIR=…/connsys-firmware \
./scripts/build-zinwa-q25-image.sh
./scripts/flash/q25-install --image "$MARATHON_BUILD_DIR"/q25/<name>.userdata.img
```

The kernel builds from source (`packaging/packages/linux-zinwa-q25`); its
build tree takes several GB, so point `MARATHON_APK_WORK_DIR` at a disk with
room for it.

This writes the root, the `userdata` image, U-Boot and `gimme-uboot.py` and a
`.SHA256SUMS` to `$Q25_IMAGE_OUT` (default `$MARATHON_BUILD_DIR/q25`). U-Boot
is built with `scripts/q25/build-q25-uboot.sh`, which refuses a build that
differs by one byte from the U-Boot the phone was tested with. The `userdata`
image comes from `scripts/carrier/carrier-userdata-image.sh`, which takes the
board DTB and carrier name from the root's `carrier.conf` (the manifest's
`boot.carrier`).
