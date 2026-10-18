# Erase all content

Settings → System → Erase all content puts the phone back to how it was when
it was new: apps' data, accounts, Wi-Fi networks, settings and files are
deleted, and it starts setup (the OOBE) again. The OS stays at the version it
runs: nothing is downloaded or reflashed, and the A/B commit state in
`autoboot.txt` is not touched.

Today only Raspberry Pi 5 / HackberryPi CM5 images built with
`MARATHON_IMAGE_LAYOUT=ab` can erase themselves (layout in
[OTA.md](OTA.md#layout-mkosirepartab-pi-pipeline-patches-0037-and-0038)).
Elsewhere Settings hides the entry, and the page says so if opened by route.

## Flow

```
Settings (sandboxed)  ErasePage → EraseDialog (PIN, or system password without one)
  └ Security.eraseAllContent(secret) ─(session bus)─► shell Security1.EraseAllContent
        requires the "system" permission and the Security rate limit
        SecurityManager::confirmOwner: lockout → PIN/PAM check → failures count towards the lockout
        FactoryReset: connect /run/marathon/factory-reset.sock, send "erase"
  ◄ EraseFailed(reason) on any refusal; the dialog comes back with it
marathon-factory-reset.socket (root:wheel 0660, Accept=yes)
  └ marathon-factory-reset@.service: /usr/libexec/marathon-factory-reset
        needs /dev/disk/by-partlabel/marathon_data
        touches /.marathon-factory-reset on the running slot's root, answers "ok"
        SuccessAction=reboot
shutdown: marathon-health --mode arm arms no trial while the marker exists
next boot, initramfs (mkinitfs, before switch_root)
  hooks-cleanup/40-marathon-factory-reset.sh   marker on /sysroot?
        /usr/libexec/marathon-wipe-data <marathon_data>; on success removes the marker
  hooks-cleanup/50-marathon-ab.sh              empty data: seeded from the slot's /var and /home
        as on a first boot, fresh /etc overlay upper → OOBE
```

### Access control

The PIN is checked in the shell, which holds it. The privileged step is a
socket under `/run`, which no app sandbox binds (bwrap and sailjail bind only
`/run/dbus` and `/run/systemd/resolve`; Flatpak has its own `/run`), so only
the shell, or the owner in a terminal, can reach it. A polkit rule on
`systemd1` `StartUnit` was not used: apps run as the session's user and reach
the system bus, so polkit could not tell an app from the shell, and any app
could have erased the phone.

### Why not systemd's factory reset

systemd 262's `factory-reset.target` writes the `FactoryResetRequest` EFI
variable, and systemd-repart in a systemd initrd then recreates the
partitions marked `FactoryReset=yes`. The Pi has no EFI variables, its
initramfs is postmarketOS mkinitfs rather than a systemd initrd, and its data
partition is mounted there by `50-marathon-ab.sh`, not by repart. So the Pi
records the request as a file and erases in a mkinitfs hook.

## Layouts

| Layout | Erase |
|---|---|
| Pi A/B, plain ext4 data | header zeroed, `mke2fs -t ext4 -L marathon_data` (discards on cards that support it). Not a secure erase on cards without discard |
| Pi A/B, LUKS data | `cryptsetup luksErase` (every keyslot: the old data is unreadable), header zeroed, then a new container: see the contract |
| QEMU A/B (UEFI) | not wired. It should use systemd's own path, `systemctl start factory-reset.target`, but duranium's `repart.d/30-root.conf` says `FactoryResetRequest=yes`, a key systemd-repart ignores, so its root is never recreated (`systemd-repart --can-factory-reset` is false). Fixing that needs the corrected file in the initrd as well as the image |
| single-root images (Librem 5, PinePhone, OnePlus 6, Pi without `ab`) | none: the data shares the root file system the OS runs from |

What is not erased: the OS slots themselves (only `/var`, `/home` and the
`/etc` overlay live on `marathon_data`), and anything the image bakes into
the slot, such as a developer build's Wi-Fi keyfile or SSH key.

## Contract with data encryption

`/usr/libexec/marathon-wipe-data [--key-file FILE] DEVICE` is the one helper
for leaving the data partition empty. It is in the rootfs and in the
initramfs (`mkinitfs/files/40-marathon-factory-reset.files`, with
`cryptsetup` and `mke2fs`). It must run on a device that is neither mounted
nor open.

- If DEVICE is LUKS (`cryptsetup isLuks`), `cryptsetup luksErase` first.
- The first 16 MiB are zeroed, so no old LUKS or file system signature is left.
- With `--key-file FILE`: a new LUKS2 container whose only keyslot is FILE,
  holding an empty ext4 labelled `marathon_data`. No PIN keyslot: the OOBE
  sets a PIN again and the encryption code adds its keyslot then.
- Without it: a plain empty ext4 labelled `marathon_data`.

The request side is this document's: the marker `/.marathon-factory-reset`
on the running slot's root, written only by `marathon-factory-reset`. The
erase runs in `hooks-cleanup/40-marathon-factory-reset.sh`, before
`50-marathon-ab.sh` unlocks or mounts the data. Once the data partition is
LUKS, the encryption work changes that hook's call to pass `--key-file` with
the key its unlock path uses before a PIN exists, and puts `dm_crypt` in the
initramfs modules (its unlock needs it too).

## Failure handling

- A wrong PIN or password, a lockout, or a service that says no: Settings
  shows why and nothing is recorded.
- The erase fails at boot: the marker stays, the kernel log has
  `marathon-factory-reset: could not erase …`, and the next boot tries again.
  While the marker exists no update is tried, since the other slot would not
  erase.
- A request made on a trial boot that never committed (the shell's first frame
  commits it, so this needs a failed commit) reboots into the committed slot,
  which has no marker: nothing is erased and the data is still there.

## Checking it on a HackberryPi

On an A/B image built from this tree, over SSH as root:

1. `systemctl status marathon-factory-reset.socket` is listening,
   `ls -l /run/marathon/factory-reset.sock` is `srw-rw---- root wheel`, and
   `cpio -it < /boot/initramfs_2712 | grep -e factory-reset -e wipe-data -e mke2fs -e cryptsetup`
   lists the hook, the helper, `mke2fs` and `cryptsetup` (the Pi's
   initramfs is plain cpio).
2. Leave something to lose: a Wi-Fi network added in Settings, a file in
   `/home/user`, a changed setting, a quick PIN. Note `IMAGE_VERSION` in
   `/etc/os-release` and the booted partition.
3. Settings → Erase all content: the page names the running version. Erase
   with a wrong PIN: the dialog comes back with "Incorrect PIN", Security
   shows a failed attempt, and nothing restarts.
4. Erase with the right PIN: "Restarting to erase…", then one restart.
5. After it (the old journal was on the data partition, so it is gone too):
   `journalctl -k -b | grep marathon-factory-reset` shows "erasing
   /dev/mmcblk0p6" and "erased"; `/.marathon-factory-reset` is gone; the OOBE
   runs; the file, the added network, the setting and the PIN are gone;
   `IMAGE_VERSION` and the booted partition are unchanged and tryboot is 0
   (OTA.md shows how to read both).
